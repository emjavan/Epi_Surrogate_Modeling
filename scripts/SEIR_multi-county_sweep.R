#///////////////////////////////////////////////////////////////////////////////
#' Parameter sweep over:
#'  - top n=5 most connected counties within a state
#'  - 4 states + DC = 125 county sets
#'  - R0 from 0.5 to 5 by 0.5 = 10 R0
#'  - initial infected of 1, 10, 100, 1000 equal value per county
#' Results in 5,000 total templates and *100 = 500,000 simulations
#'  => too many to create unique/informative labels
#' Creating hash for each scenario and giving UUIDv7 to all batch num
#'  => every scenario id comes back with the correct input file
#'  => every batch id is a large unique string & will be new each time
#' Emily Javan, 02/23/26, TACC
#///////////////////////////////////////////////////////////////////////////////

#///////////////////////////////////////////////////////////////////////////////
#### Load libraries & helper funs ####
library(tidyverse)
library(jsonlite)
library(digest)
library(RcppUUID)
source("../data/private_input_data/api_keys.R")
source("helper_funs.R")

#///////////////////////////////////////////////////////////////////////////////
# Set initial conditions
states = c("District-of-Columbia", "New-Jersey", "North-Dakota", "Wisconsin", "North-Carolina")
R0 = seq(0.5, 5, 0.5)
init_inf = c(1, 10, 100, 1000)
simulation_days = 500

#///////////////////////////////////////////////////////////////////////////////
#### Most connected counties ####
# This ranks the population flowing out of each node per day
# DC is a single node and has no outflow
county_rank_files = list.files(path = paste0("../data/", states), 
                               pattern="_quarterly-2019_county-connection-ranking.csv$", 
                               recursive = T, full.names = T) # 4

# Get only the county row with the highest outflow of people
top_n_counties = map_dfr(
  county_rank_files,
  ~ read_csv(.x, col_types = cols(.default = "c")) %>%
    rename(COUNTY_POP_ACS2023 = POP_ACS2023) %>%
    dplyr::filter(quarter=="4") %>%
    mutate( # needs to be numeric before ranking correctly
      prop_county_outflow       = as.numeric(prop_county_outflow),
      total_pop_outflow         = as.numeric(total_pop_outflow),
      total_counties_connected  = as.numeric(total_counties_connected),
      COUNTY_POP_ACS2023        = as.numeric(COUNTY_POP_ACS2023)
    ) %>%
    arrange(desc(total_pop_outflow), desc(total_counties_connected), desc(COUNTY_POP_ACS2023)) %>%
    slice(1:5)) %>%
  # Adding DC back in manually
  bind_rows(data.frame(
    state_fips = "11",
    state_name = "District-of-Columbia",
    state_abbr = "DC",
    geoid_o = "11001",
    prop_county_outflow = 0,
    total_counties_connected = 0,
    total_pop_outflow = 0)) 

# Counties per state as a named list: state_name -> character vector of geoid_o
counties_by_state = top_n_counties %>%
  dplyr::select(state_name, geoid_o) %>%
  group_by(state_name) %>%
  summarise(counties = list(geoid_o), .groups = "drop") %>%
  tibble::deframe()  # named list: state_name -> county vector

# All subsets of counties (size 1 through n) for each state
county_combos = map_dfr(names(counties_by_state), function(state) {
  counties = counties_by_state[[state]]
  map_dfr(seq_along(counties), function(k) {
    combos = combn(counties, k, simplify = FALSE)
    tibble(state_name = state, county_set = combos)
  })
})

# All unique combinations of county_set x init_inf x R0 = 5000
sweep_combos = crossing(
  county_combos,
  init_inf = init_inf,
  R0       = R0
)

# double checking the county sets look correct and they do: 125 as expected
check_county_combos = sweep_combos %>%
  dplyr::select(county_set) %>%
  distinct()

#///////////////////////////////////////////////////////////////////////////////
#### Create input files ####
# Get base template path
input_dir_path   = "../data/INPUT_FILE_TEMPLATES"
base_file = list.files(path        = input_dir_path,
                       pattern     = "^INPUT_SEIRS-STOCH_BASELINE\\.json$",
                       full.names  = TRUE, recursive  = TRUE)
base_template = jsonlite::fromJSON(base_file, simplifyVector = FALSE)

# Create dir for all initial condition files
commands_dir = "../SEIR-STOCH_Param_Sweep/"
input_scenario_dir = "input_files/"
input_scenario_dir_path = paste0(commands_dir, input_scenario_dir)
dir.create(input_scenario_dir_path, recursive = TRUE)

# Build one template per (county set x init_inf x R0) combo, 
# with initial_infected the same infected value for all in set
scenario_results = pmap(sweep_combos, function(state_name, county_set, init_inf, R0) {
  tmpl <- base_template
  tmpl$initial_infected <- lapply(
    county_set,
    function(county) {
      list(
        county    = county,
        infected  = as.character(init_inf),
        age_group = "2"
      )})
  # Set R0 in disease model
  tmpl$disease_model$parameters$R0 <- as.character(R0)
  # Replace STATE tokens first, then hash, then insert hash into output_dir_path
  tmpl <- replace_STATE_tokens(tmpl, state_name)
  hash <- compute_scenario_hash(tmpl)
  tmpl$output_dir_path <- gsub("REPLACE", hash, tmpl$output_dir_path)
  uuid <- RcppUUID::uuid_generate_time()
  tmpl$batch_num <- uuid
  
  jsonlite::write_json(tmpl, paste0(input_scenario_dir, state_name, "_", hash, ".json"), 
                       auto_unbox = TRUE, pretty = TRUE, null = "null")
  
  return(list(template = tmpl, hash = hash, uuid = uuid))
})

# Pull templates and add hash + uuid columns to sweep_combos for easy inspection
scenario_templates = map(scenario_results, "template")
sweep_combos$scenario_hash = map_chr(scenario_results, "hash")
sweep_combos$batch_num     = map_chr(scenario_results, "uuid")
sweep_combos_final = sweep_combos %>%
  mutate(output_path = paste0(input_scenario_dir, state_name, "_", scenario_hash, ".json") )

# Save metadata of each scenario hash, etc.
sweep_combos_final %>%
  mutate(county_set = map_chr(county_set, paste, collapse = ",")) %>%
  write.table(paste0(commands_dir, "scenario_metadata.txt"),
              sep = "\t", row.names = FALSE, quote = FALSE)

#//////////////////////////////////////
#### Create parallel commands file ####
commands_script = sweep_combos_final %>%
  mutate(poetry_command_start = 
           paste("poetry run python3 ../src/simulator.py -l INFO -d", simulation_days ,"-i")) %>%
  rowwise() %>%
  mutate(final_poetry_command = paste(poetry_command_start, output_path)) %>%
  ungroup() %>%
  dplyr::select(final_poetry_command)

write.table(commands_script,
            paste0(commands_dir, "state_commands.txt"),
            sep = "", col.names = FALSE,  row.names = FALSE, quote = FALSE)








