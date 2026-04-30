#!/usr/bin/env bash
set -euo pipefail

STATES=(
   "District-of-Columbia"
   "New-Jersey"
   "North-Dakota"
   "Wisconsin"
   "North-Carolina"
)

OUT_STATUS="scenario_status.csv"
EXPECTED=100

echo "state,scenario_hash,dir_exists,finished_count,needs_resubmit,source_manifest" > "$OUT_STATUS"

for state_name in "${STATES[@]}"; do
   MANIFEST="${state_name}_commands.txt"
   OUT_RESUBMIT="${state_name}_resubmit_commands.txt"

   : > "$OUT_RESUBMIT"

   if [[ ! -f "$MANIFEST" ]]; then
      echo "WARN: missing manifest: $MANIFEST" >&2
      continue
   fi

   while IFS= read -r line; do
      [[ -z "${line// }" ]] && continue
      [[ "$line" =~ ^# ]] && continue

      state_hash=$(printf "%s\n" "$line" | sed -n 's/.*input_files\/\([^ ]\+\)\.json.*/\1/p')

      if [[ -z "$state_hash" ]]; then
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

      echo "${state},${hash},${dir_exists},${finished},${needs},${MANIFEST}" >> "$OUT_STATUS"

   done < "$MANIFEST"

   echo "Wrote $OUT_RESUBMIT"
done

echo "Wrote $OUT_STATUS"