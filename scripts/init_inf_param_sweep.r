#///////////////////////////////////////////////////////////////
#' Create the input files for varying the initial infected param
#'  in a single county
#' Running 100 simulations for 212 days because 500 days takes 
#'  too long for larger states and isn't adding much
#///////////////////////////////////////////////////////////////

#///////////////////////
#### Load libraries ####
library(tidyverse)
library(jsonlite)
library(digest)
source("../data/private_input_data/api_keys.R")
source("helper_funs.R")

commands_dir = "../SEIHRD-STOCH_Param_Sweep/"
dir.create(commands_dir)
simulation_days = 500

#/////////////////////////
#### Load data ####
acs_state_pop_2023 = 
  tidycensus::get_acs(geography = "state", variables="B01001_001",
                      year = 2023, geometry=F) %>%
  dplyr::select(-moe, -variable, -NAME) %>%
  rename(STATE_POP_ACS2023 = estimate,
         state_fips = GEOID) %>%
  mutate(state_fips = as.character(state_fips))

# This ranks the population flowing out of each node per day
# DC is a single node and has no outflow
county_rank_files = list.files(path = "../data", pattern="_quarterly-2019_county-connection-ranking.csv$", 
           recursive = T, full.names = T) # 50

# Get template paths
input_dir_path   = "../data/INPUT_FILE_TEMPLATES"      # where files are written (FS path from here)
base_file = list.files(path        = input_dir_path,
                       pattern     = "^INPUT_SEIHRD-STOCH_STATE_InitInf-N_SingleCounty\\.json$",
                       full.names  = TRUE, recursive  = TRUE)

#////////////////////////////////
#### Most connected counties ####
# Get only the county row with the highest outflow of people
top_county = map_dfr(
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
    slice_max(order_by = data.frame(total_pop_outflow, total_counties_connected, COUNTY_POP_ACS2023), 
              with_ties=FALSE)) %>% # no ties, must be single max county for this experiment
  # Adding DC back in manually
  bind_rows(data.frame(
    state_fips = "11",
    state_name = "District-of-Columbia",
    state_abbr = "DC",
    geoid_o = "11001",
    prop_county_outflow = 0,
    total_counties_connected = 0,
    total_pop_outflow = 0)) %>%
  left_join(acs_state_pop_2023, by="state_fips") %>%
  rowwise() %>%
  mutate(#frac_tot_pop_outflow = total_pop_outflow/STATE_POP_ACS2023,
         init_inf_per_1M = ceiling(STATE_POP_ACS2023/1000000) ) %>%
  ungroup()
  
# Get every unique param combination
top_county_expanded = top_county %>%
  mutate(
    init_inf_series = map(init_inf_per_1M, make_init_series)
  ) %>%
  tidyr::unnest_longer(init_inf_series, values_to = "init_inf_series") %>%
  mutate(base_file = base_file) %>%
  separate(base_file, into = c(NA, NA, NA, "BASE_FILENAME_ONLY"), sep="\\/", remove=T) %>%
  mutate(
    BASE_FILENAME_ONLY = replace_STATE_tokens(BASE_FILENAME_ONLY, state_name),
    BASE_FILENAME_ONLY = str_replace(BASE_FILENAME_ONLY, "(?<=InitInf-)N", as.character(init_inf_series)), 
    BASE_OUTPUT_FILE_PATH = paste0("../data/", state_name, "/", "SingleCounty_InputJSONs", "/", BASE_FILENAME_ONLY)
  )

# Pick states in the desired range of sizes by county
state_df = pick_distributed_states(
  top_county,
  value_col = "total_counties_connected",
  name_col  = "state_name",
  n         = 5,
  max_value = 100
)

#////////////////////////////////////
#### Create simulation templates ####
base_template = jsonlite::fromJSON(base_file, simplifyVector = FALSE)
for(i in 1:nrow(top_county_expanded)){
  print(i)
  # grab row just for single param pair and make new template
  single_state = top_county_expanded %>%
    slice(i)
  state_template_copy = base_template
  state_template = replace_STATE_tokens(state_template_copy, state_dir = single_state$state_name)
  
  # replace N with the actual init inf
  replace_N = str_replace(state_template$output_dir_path,
                          "(?<=InitInf-)N", as.character(single_state$init_inf_series)) 
  remove_json = str_remove(replace_N, "\\.json")
  
  
  state_template$output_dir_path = remove_json
  state_template$initial_infected[[1]]$county   = single_state$geoid_o
  state_template$initial_infected[[1]]$infected = as.character(single_state$init_inf_series)
  
  # Make the dir for output file if it doesn't exist and silence the warnings about it existing
  dir.create(dirname(single_state$BASE_OUTPUT_FILE_PATH), 
             recursive = TRUE, showWarnings = FALSE)
  
  jsonlite::write_json(state_template, single_state$BASE_OUTPUT_FILE_PATH, 
             auto_unbox = TRUE, pretty = TRUE, null = "null")
  print(paste0("wrote file to ", single_state$BASE_OUTPUT_FILE_PATH))
} # end loop over states


#//////////////////////////////////////
#### Create parallel commands file ####
commands_script = top_county_expanded %>%
  mutate(poetry_command_start = paste("poetry run python3 ../src/simulator.py -l INFO -d", simulation_days ,"-i")) %>%
  rowwise() %>%
  mutate(final_poetry_command = paste(poetry_command_start, BASE_OUTPUT_FILE_PATH)) %>%
  ungroup() %>%
  dplyr::select(final_poetry_command)

write.table(commands_script,
            paste0(commands_dir, "state_commands.txt"),
            sep = "", col.names = FALSE,  row.names = FALSE, quote = FALSE)

