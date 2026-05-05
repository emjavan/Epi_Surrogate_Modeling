#!/usr/bin/env bash
set -euo pipefail

STATES=(
   "District-of-Columbia"
   "New-Jersey"
   "North-Dakota"
   "Wisconsin"
   "North-Carolina"
)

EXPECTED=100
OUT_STATUS="scenario_status.csv"
META_INDEX=".metadata_sim_index.tsv"

echo "Building metadata index..."

python3 - <<'PY' > "$META_INDEX"
import csv
import json
from pathlib import Path
from collections import defaultdict

rows = defaultdict(lambda: {
    "hashes": set(),
    "dirs": set(),
    "batches": set(),
    "finished": 0,
})

counted_dirs = set()

for meta_path in Path(".").rglob("metadata_batch-*.json"):
    scenario_dir = meta_path.parent.resolve()

    # Avoid double-counting the same scenario dir when it contains multiple metadata files
    if scenario_dir in counted_dirs:
        continue
    counted_dirs.add(scenario_dir)

    try:
        with open(meta_path, "r") as f:
            meta = json.load(f)
    except Exception:
        continue

    cli_input = meta.get("cli_args", {}).get("input_filename")
    if not cli_input:
        continue

    input_key = Path(cli_input).name
    scenario_hash = meta.get("scenario_hash", "")
    output_dir = meta.get("output_dir_path", str(meta_path.parent))

    finished = 0
    batches = set()

    for sim_file in scenario_dir.glob("simulation_times_batch-*.csv"):
        batch = sim_file.name.removeprefix("simulation_times_batch-").removesuffix(".csv")
        batches.add(batch)

        with open(sim_file, newline="") as f:
            reader = csv.DictReader(f)
            finished += sum(
                1 for row in reader
                if row.get("sim_id") not in ("", None)
            )

    rows[input_key]["hashes"].add(scenario_hash)
    rows[input_key]["dirs"].add(output_dir)
    rows[input_key]["batches"].update(batches)
    rows[input_key]["finished"] += finished

print("input_key\tscenario_hash\toutput_dir\tbatch_num\tfinished_count")

for input_key, x in rows.items():
    print(
        input_key,
        ";".join(sorted(x["hashes"])),
        ";".join(sorted(x["dirs"])),
        ";".join(sorted(x["batches"])),
        x["finished"],
        sep="\t",
    )
PY

echo "state,input_file,input_key,scenario_hash,output_dir,batch_num,finished_count,needs_resubmit,source_manifest" > "$OUT_STATUS"

for state in "${STATES[@]}"; do
   start_state=$(date +%s)

   MANIFEST="${state}_commands.txt"
   OUT_RESUBMIT="${state}_resubmit_commands.txt"

   : > "$OUT_RESUBMIT"

   if [[ ! -f "$MANIFEST" ]]; then
      echo "WARN: missing manifest: $MANIFEST" >&2
      continue
   fi

   while IFS= read -r cmd; do
      [[ -z "${cmd// }" ]] && continue
      [[ "$cmd" =~ ^# ]] && continue

      input_file=$(printf "%s\n" "$cmd" | sed -n 's/.* -i \([^ ]\+\).*/\1/p')

      if [[ -z "$input_file" ]]; then
         echo "WARN: could not parse input file from command: $cmd" >&2
         continue
      fi

      input_key=$(basename "$input_file")

      match=$(
         awk -F'\t' -v key="$input_key" '
            NR > 1 && $1 == key {
               print $2 "\t" $3 "\t" $4 "\t" $5
               found = 1
               exit
            }
            END {
               if (!found) print "NA\tNA\tNA\t0"
            }
         ' "$META_INDEX"
      )

      scenario_hash=$(printf "%s" "$match" | cut -f1)
      output_dir=$(printf "%s" "$match" | cut -f2)
      batch_num=$(printf "%s" "$match" | cut -f3)
      finished=$(printf "%s" "$match" | cut -f4)

      needs=0
      if [[ "$finished" -lt "$EXPECTED" ]]; then
         needs=1
         echo "$cmd" >> "$OUT_RESUBMIT"
      fi

      echo "${state},${input_file},${input_key},${scenario_hash},${output_dir},${batch_num},${finished},${needs},${MANIFEST}" >> "$OUT_STATUS"

   done < "$MANIFEST"

   echo "Wrote $OUT_RESUBMIT"

   end_state=$(date +%s)
   elapsed=$((end_state - start_state))
   printf "State %-20s | %6ds\n" "$state" "$elapsed"
done

echo "Wrote:"
echo "   $OUT_STATUS"
echo "   $META_INDEX"
