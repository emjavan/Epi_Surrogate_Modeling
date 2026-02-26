#///////////////////////////////////////////////////////////////////////////////
# Change the template files to be state specific
#   then create the parallel commands to submit on LS6
# This job took about 12h on 2 nodes, 64 tasks in parallel
#   TX and GA take the longest to run at ~2sec per sim day
# Files are named {state}_{scenario_hash}.json; batch_num is a UUIDv7.
#///////////////////////////////////////////////////////////////////////////////

#///////////////////////////////////////////////////////////////////////////////
#### Load libraries & helper funs ####
library(tidyverse)
library(jsonlite)
library(digest)
library(RcppUUID)
source("helper_funs.R")

#///////////////////////////////////////////////////////////////////////////////
#### Initial conditions ####
commands_dir           = "../US_Vax_Compare/"
input_scenario_dir     = "input_files/"
input_scenario_dir_path = paste0(commands_dir, input_scenario_dir)
dir.create(input_scenario_dir_path, recursive = TRUE)
simulation_days = 212

#///////////////////////////////////////////////////////////////////////////////
#### Load data ####
input_dir_path = "../data/INPUT_FILE_TEMPLATES"
base_file = list.files(path       = input_dir_path,
                       pattern    = "^INPUT_SEIHRD-STOCH_STATE.*BASELINE\\.json$",
                       full.names = TRUE, recursive = TRUE)
vax_file  = list.files(path       = input_dir_path,
                       pattern    = "^INPUT_SEIHRD-STOCH_STATE.*VAX\\.json$",
                       full.names = TRUE, recursive = TRUE)

state_weekly_vax_given = read_csv("../data/VACCINATION/all_US_weekly_vax_distribution.csv")

county_df = read_csv("../data/POPULATION/county_lookup_2019-2023ACS.csv")
county_per_state = county_df %>%
  group_by(STATE_NAME) %>%
  summarise(num_county = n(), .groups = "drop")

county_init_inf = read_csv("../data/POPULATION/all_US_initial_infected.csv") %>%
  drop_na() %>%
  left_join(county_per_state, by = "STATE_NAME") %>%
  mutate(
    STATE_NAME_DIR = str_replace_all(STATE_NAME, " ", "-"),
    fips           = str_pad(fips, width = 5, pad = "0")
  )

base_template = jsonlite::fromJSON(base_file, simplifyVector = FALSE)
vax_template  = jsonlite::fromJSON(vax_file,  simplifyVector = FALSE)

#///////////////////////////////////////////////////////////////////////////////
#### Create input files ####
scenario_results = map(seq_len(nrow(county_init_inf)), function(i) {
  row = county_init_inf[i, ]
  state_vax_ts = state_weekly_vax_given %>%
    dplyr::filter(State == row$STATE_NAME)
  
  # --- Baseline ---
  base_tmpl = replace_STATE_tokens(base_template, row$STATE_NAME_DIR)
  base_tmpl$initial_infected[[1]]$county   = as.character(row$fips)
  base_tmpl$initial_infected[[1]]$infected = as.character(row$init_inf_per_1M)
  base_hash = compute_scenario_hash(base_tmpl)
  base_tmpl$output_dir_path = gsub("REPLACE", base_hash, base_tmpl$output_dir_path)
  base_uuid = RcppUUID::uuid_generate_time()
  base_tmpl$batch_num = base_uuid
  base_path = paste0(input_scenario_dir_path, row$STATE_NAME_DIR, "_", base_hash, ".json")
  write_json(base_tmpl, base_path, auto_unbox = TRUE, pretty = TRUE, null = "null")
  
  # --- Vax ---
  vax_tmpl = replace_STATE_tokens(vax_template, row$STATE_NAME_DIR)
  vax_tmpl$initial_infected[[1]]$county   = as.character(row$fips)
  vax_tmpl$initial_infected[[1]]$infected = as.character(row$init_inf_per_1M)
  vax_tmpl$vaccine_model$parameters$vaccine_stockpile = make_stockpile_json(state_vax_ts)
  vax_hash = compute_scenario_hash(vax_tmpl)
  vax_tmpl$output_dir_path = gsub("REPLACE", vax_hash, vax_tmpl$output_dir_path)
  vax_uuid = RcppUUID::uuid_generate_time()
  vax_tmpl$batch_num = vax_uuid
  vax_path = paste0(input_scenario_dir_path, row$STATE_NAME_DIR, "_", vax_hash, ".json")
  write_json(vax_tmpl, vax_path, auto_unbox = TRUE, pretty = TRUE, null = "null")
  
  list(
    base = list(scenario_type = "baseline", scenario_hash = base_hash,
                batch_num = base_uuid, output_path = base_path),
    vax  = list(scenario_type = "vax",      scenario_hash = vax_hash,
                batch_num = vax_uuid,  output_path = vax_path)
  )
})

#///////////////////////////////////////////////////////////////////////////////
#### Build & save metadata ####
scenario_metadata = map_dfr(seq_along(scenario_results), function(i) {
  row = county_init_inf[i, ]
  res = scenario_results[[i]]
  map_dfr(list(res$base, res$vax), function(s) {
    tibble(
      STATE_NAME     = row$STATE_NAME,
      STATE_NAME_DIR = row$STATE_NAME_DIR,
      fips           = row$fips,
      scenario_type  = s$scenario_type,
      scenario_hash  = s$scenario_hash,
      batch_num      = s$batch_num,
      output_path    = s$output_path
    )
  })
})

write.table(scenario_metadata,
            paste0(commands_dir, "scenario_metadata.txt"),
            sep = "\t", row.names = FALSE, quote = FALSE)

#///////////////////////////////////////////////////////////////////////////////
#### Create parallel commands file ####
commands_script = scenario_metadata %>%
  mutate(
    poetry_command_start = paste("poetry run python3 ../src/simulator.py -l INFO -d", simulation_days, "-i"),
    final_poetry_command = paste(poetry_command_start, str_remove(output_path, fixed(commands_dir)))
  ) %>%
  select(final_poetry_command)

write.table(commands_script,
            paste0(commands_dir, "state_commands.txt"),
            sep = "", col.names = FALSE, row.names = FALSE, quote = FALSE)
