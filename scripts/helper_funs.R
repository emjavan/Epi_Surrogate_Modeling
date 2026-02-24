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
  hash_list$batch_num <- NULL
  
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









