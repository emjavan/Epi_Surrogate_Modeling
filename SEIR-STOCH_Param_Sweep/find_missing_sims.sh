#!/usr/bin/env bash
set -euo pipefail

MANIFEST="state_commands.txt"
OUT_STATUS="scenario_status.csv"
OUT_RESUBMIT="resubmit_commands.txt"
EXPECTED=100

# header
echo "state,scenario_hash,dir_exists,finished_count,needs_resubmit" > "$OUT_STATUS"
: > "$OUT_RESUBMIT"

while IFS= read -r line; do
   # skip blank/comment lines
   [[ -z "${line// }" ]] && continue
   [[ "$line" =~ ^# ]] && continue

   # Extract "State" and "hash" from "... input_files/State_hash.json"
   # Works with hyphenated states too (e.g., District-of-Columbia)
   state_hash=$(printf "%s\n" "$line" | sed -n 's/.*input_files\/\([^ ]\+\)\.json.*/\1/p')
   if [[ -z "$state_hash" ]]; then
      # If a line doesn't match expected format, skip but leave a breadcrumb
      echo "WARN: couldn't parse: $line" >&2
      continue
   fi

   state="${state_hash%_*}"
   hash="${state_hash#*_}"
   dir="${state}/${hash}"

   dir_exists=0
   finished=0

   if [[ -d "$dir" ]]; then
      dir_exists=1

      # Count finished sims: all non-header lines across all batches
      # If no files exist, this stays 0.
      finished=$(
         find "$dir" -type f -name "simulation_times_batch-*.csv" -print0 2>/dev/null \
            | xargs -0 -r grep -h -v '^sim_num' 2>/dev/null \
            | wc -l
      )
   fi

   needs=0
   if [[ "$dir_exists" -eq 0 || "$finished" -lt "$EXPECTED" ]]; then
      needs=1
      echo "$line" >> "$OUT_RESUBMIT"
   fi

   echo "${state},${hash},${dir_exists},${finished},${needs}" >> "$OUT_STATUS"

done < "$MANIFEST"

echo "Wrote:"
echo "   $OUT_STATUS"
echo "   $OUT_RESUBMIT"
