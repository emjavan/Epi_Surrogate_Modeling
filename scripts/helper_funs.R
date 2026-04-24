#///////////////////////////////////////////////////////////////////////////////
#### Helper Functions ####

library(tidyverse)

#///////////////////////////////////////////////////////////////////////////////
# Replace "STATE" tokens in all strings from template
replace_STATE_tokens = function(x, state_dir) {
  # match STATE when not next to letters/digits (underscore is ok)
  pat = "(?<![A-Za-z0-9])STATE(?![A-Za-z0-9])"
  if (is.character(x)) {
    stringr::str_replace_all(x, pat, state_dir)
  } else if (is.list(x)) {
    lapply(x, replace_STATE_tokens, state_dir = state_dir)
  } else x
} # end replace_STATE_tokens

#///////////////////////////////////////////////////////////////////////////////
# Create sequence of initial infected for a single county based on init_inf_per_1M
make_init_series = function(init_inf_per_1M, total_vals = 10) { # init_inf_per_1M = 40
  # Small values: just use 1:total_vals
  if(init_inf_per_1M <= total_vals){return(1:total_vals)}
  
  # Initial set: 1, all multiples of 5, and init_inf_per_1M itself
  max_val = ceiling(init_inf_per_1M / 5) * 5 # Round up init to nearest multiple of 5
  vals = sort(unique(c(1, seq(5, max_val, by = 5), init_inf_per_1M)))
  
  # If we already have 10, we're done
  if(length(vals) == total_vals){ 
    return(vals)
  # If we have fewer than 10, add neighbors, prioritizing those closest to init
  }else if(length(vals) < total_vals){ 
    needed = total_vals - length(vals)
    
    # Candidates are all integers between 1 and max_val that aren't already in vals
    candidates = setdiff(1:max_val, vals)
    
    # Prioritize candidates by distance to init (closest first, then by value)
    candidates = candidates[order(abs(candidates - init_inf_per_1M), candidates)]
    extras = head(candidates, needed)
    more_vals = sort(c(vals, extras))
    return(more_vals)
  }else{ # If more than total_vals, thin them out to total_vals while keeping the range.
    idx = round(seq(1, length(vals), length.out = total_vals))
    less_vals = sort(vals[idx])
    return(less_vals)
  } # end if to get total_vals requested in final param sweep
} # end make_init_series


#///////////////////////////////////////////////////////////////////////////////
# Select n states evenly distributed across the range of a numeric column.
# Returns a tibble with the state name and value column.
pick_distributed_states <- function(df, value_col, name_col, n, max_value = Inf) {
  df <- df[df[[value_col]] <= max_value, ]
  df <- df[order(df[[value_col]]), ]
  idx <- round(seq(1, nrow(df), length.out = n))
  df[idx, c(name_col, value_col)]
}

#///////////////////////////////////////////////////////////////////////////////
# Make hash id for the scenario based only on disease pertinant fields
compute_scenario_hash <- function(input_list) {
  
  # Make a deep copy
  hash_list <- input_list
  
  # Remove runtime-only fields
  hash_list$output_dir_path <- NULL
  hash_list$realization_range <- NULL
  hash_list$BATCH_NUM <- NULL
  
  # Canonical JSON (stable representation)
  canonical_json <- toJSON(
    hash_list,
    auto_unbox = TRUE,
    pretty = FALSE
  )
  
  # SHA256
  scenario_hash <- digest::digest(
    canonical_json,
    algo = "sha256"
  )
  
  return(scenario_hash)
}


#///////////////////////////////////////////////////////////////////////////////
# Turn a state's vaccine schedule into the vaccine_stockpile JSON list
make_stockpile_json = function(state_df) {
  state_df %>%
    arrange(ReleaseDay) %>%
    transmute(
      day    = as.character(ReleaseDay),
      amount = as.character(round(TotalWeeklyNewFullProtect))
    ) %>%
    transpose()
} # end make_stockpile_json


#///////////////////////////////////////////////////////////////////////////////
# Parse STATE / SCENARIO from path and read network CSV
read_network = function(path) {
  scenario  = basename(dirname(path))
  state     = basename(dirname(dirname(path)))
  read_csv(path, show_col_types = FALSE,
           col_types = cols(.default = col_character())) %>%
    mutate(STATE_NAME_DIR = state, 
           SCENARIO_HASH = scenario,
           BATCH_NUM = tools::file_path_sans_ext(basename(path)),
           BATCH_NUM = gsub("network_batch-", "", BATCH_NUM),
           .before = 1) %>%
    drop_na()
} # end read_network


#///////////////////////////////////////////////////////////////////////////////
# Summarize one network file: per sim_id x compartment min/max value + day
summarise_one_network_file = function(path,
                                      comp_cols = c("S","E","IA","IP","IS","H","R","D","cum_hosp")) {
  df = read_network(path) %>%
    group_by(BATCH_NUM, STATE_NAME_DIR, SCENARIO_HASH, sim_id) %>%
    arrange(BATCH_NUM, STATE_NAME_DIR, SCENARIO_HASH, sim_id, day) %>%
    mutate(
      new_hosp = pmax(H - dplyr::lag(H, default = 0), 0),
      cum_hosp = cumsum(new_hosp)
    ) %>%
    ungroup() %>%
    group_by(STATE_NAME_DIR, SCENARIO_HASH, sim_id) %>%
    complete(day = full_seq(range(day), 1)) %>%
    fill(H, cum_hosp, new_hosp, .direction = "down") %>%
    replace_na(list(H = 0, cum_hosp = 0, new_hosp = 0)) %>%
    ungroup()

  df %>%
    arrange(STATE_NAME_DIR, SCENARIO_HASH, sim_id, day) %>%
    group_by(STATE_NAME_DIR, SCENARIO_HASH, BATCH_NUM, sim_id) %>%
    pivot_longer(all_of(comp_cols), names_to = "comp", values_to = "val") %>%
    ungroup() %>%
    group_by(STATE_NAME_DIR, SCENARIO_HASH, BATCH_NUM, sim_id, comp) %>%
    summarise(
      max_value = if (all(is.na(val))) NA_real_ else max(val, na.rm = TRUE),
      max_day   = if (all(is.na(val))) NA_integer_ else day[which.max(replace_na(val, -Inf))],
      min_value = if (all(is.na(val))) NA_real_ else min(val, na.rm = TRUE),
      min_day   = if (all(is.na(val))) NA_integer_ else day[which.min(replace_na(val,  Inf))],
      .groups = "drop_last"
    ) %>%
    ungroup() %>%
    pivot_wider(
      id_cols    = c(STATE_NAME_DIR, SCENARIO_HASH, BATCH_NUM, sim_id),
      names_from = comp,
      values_from = c(max_value, max_day, min_value, min_day),
      names_glue = "{comp}_{.value}"
    )
} # end summarise_one_network_file


#///////////////////////////////////////////////////////////////////////////////
# Read timing stats from a CSV and return summary tibble
read_time_stats = function(csv_path) {
  df = readr::read_csv(csv_path, show_col_types = FALSE)
  x  = df[["time_seconds"]]
  tibble(
    file       = csv_path,
    n          = length(x),
    mean_sec   = mean(x),
    median_sec = median(x),
    sd_sec     = sd(x),
    q05_sec    = quantile(x, 0.05, names = FALSE, type = 7),
    q25_sec    = quantile(x, 0.25, names = FALSE, type = 7),
    q75_sec    = quantile(x, 0.75, names = FALSE, type = 7),
    q95_sec    = quantile(x, 0.95, names = FALSE, type = 7)
  )
} # end read_time_stats


#///////////////////////////////////////////////////////////////////////////////
# Parse STATE / SCENARIO / FIPS / batch from path and read node CSV
read_node = function(path) {
  scenario_dir  = basename(dirname(path))
  state_dir     = basename(dirname(dirname(path)))
  file_stem    = tools::file_path_sans_ext(basename(path))
  read_csv(path, show_col_types = FALSE,
           col_types = cols(.default = col_character())) %>%
    mutate(
      STATE_NAME_DIR  = state_dir,
      SCENARIO_HASH   = scenario_dir,
      county_fips = gsub("node_|_batch-.*", "", file_stem),
      BATCH_NUM   = gsub(".*batch-", "", file_stem),
      .before = 1
    )
} # end read_node


#///////////////////////////////////////////////////////////////////////////////
# Summarize one node file: per sim_id x compartment min/max value + day
summarise_one_node_file = function(path,
                                   comp_cols = c("S","E","IA","IP","IS","H","R","D","cum_hosp")) {
  df = read_node(path) %>%
    group_by(BATCH_NUM, STATE_NAME_DIR, SCENARIO_HASH, sim_id) %>%
    mutate(day = as.numeric(day),
           across(S:D_L_V_age4, as.numeric)) %>%
    arrange(BATCH_NUM, STATE_NAME_DIR, SCENARIO_HASH, sim_id, day) %>%
    mutate(
      new_hosp = pmax(H - dplyr::lag(H, default = 0), 0),
      cum_hosp = cumsum(new_hosp)
    ) %>%
    ungroup() %>%
    group_by(STATE_NAME_DIR, SCENARIO_HASH, sim_id) %>%
    complete(day = full_seq(range(day), 1)) %>%
    fill(H, cum_hosp, new_hosp, .direction = "down") %>%
    replace_na(list(H = 0, cum_hosp = 0, new_hosp = 0)) %>%
    ungroup()

  df %>%
    arrange(STATE_NAME_DIR, SCENARIO_HASH, sim_id, day) %>%
    group_by(STATE_NAME_DIR, SCENARIO_HASH, county_fips, BATCH_NUM, sim_id) %>%
    pivot_longer(all_of(comp_cols), names_to = "comp", values_to = "val") %>%
    ungroup() %>%
    group_by(STATE_NAME_DIR, SCENARIO_HASH, county_fips, BATCH_NUM, sim_id, comp) %>%
    summarise(
      max_value = if (all(is.na(val))) NA_real_ else max(val, na.rm = TRUE),
      max_day   = if (all(is.na(val))) NA_integer_ else day[which.max(replace_na(val, -Inf))],
      min_value = if (all(is.na(val))) NA_real_ else min(val, na.rm = TRUE),
      min_day   = if (all(is.na(val))) NA_integer_ else day[which.min(replace_na(val,  Inf))],
      .groups = "drop_last"
    ) %>%
    ungroup() %>%
    pivot_wider(
      id_cols    = c(STATE_NAME_DIR, SCENARIO_HASH, county_fips, BATCH_NUM, sim_id),
      names_from = comp,
      values_from = c(max_value, max_day, min_value, min_day),
      names_glue = "{comp}_{.value}"
    )
} # end summarise_one_node_file
