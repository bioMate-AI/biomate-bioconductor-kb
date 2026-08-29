#!/usr/bin/env bash
# Re-run ONLY the result cells that are >=50% empty (the ones killed by the $10 key cap).
# Reuses run_baseline.py + the funded uncapped key. Models in parallel, tasks sequential per model.
set -u
cd "$(dirname "$0")"
export OPENROUTER_API_KEY="${OPENROUTER_API_KEY:?}"
BASE="https://openrouter.ai/api/v1"
LOGDIR="${LOGDIR:-/private/tmp/claude-501/-Users-kky-biomate/46c7e29b-b39f-4c97-870e-9e9ba76af59f/scratchpad/rerun_empty}"
mkdir -p "$LOGDIR"

# enumerate empty cells as "dir|filebase" pairs
mapfile -t CELLS < <(python3 -c "
import glob,json,os
for f in sorted(glob.glob('results/*/*.jsonl')):
    rows=[json.loads(l) for l in open(f)]
    if not rows: continue
    emp=sum(1 for r in rows if r['prediction'] in ('',{},None))
    if emp/len(rows)>=0.5:
        d=os.path.basename(os.path.dirname(f)); b=os.path.basename(f)[:-6]
        print(f'{d}|{b}')
")

dir_to_slug(){ printf '%s' "$1" | sed 's/_/\//'; }   # first underscore -> slash

run_dir(){
  local dir="$1"; local slug; slug=$(dir_to_slug "$dir"); local log="$LOGDIR/$dir.log"
  echo "=== $slug $(date -u +%H:%M:%S) ===" > "$log"
  for cell in "${CELLS[@]}"; do
    IFS='|' read -r d b <<< "$cell"; [ "$d" = "$dir" ] || continue
    if [[ "$b" == cross_domain_routing_bare ]]; then args="cross_domain_routing --mode bare"
    elif [[ "$b" == cross_domain_routing_catalog ]]; then args="cross_domain_routing --mode catalog"
    else args="$b"; fi
    echo ">> $args" >> "$log"
    python3 run_baseline.py $args --model "$slug" --base-url "$BASE" --key-env OPENROUTER_API_KEY >> "$log" 2>&1
  done
  echo "=== DONE $slug $(date -u +%H:%M:%S) ===" >> "$log"
}

# unique dirs among empty cells
mapfile -t DIRS < <(printf '%s\n' "${CELLS[@]}" | cut -d'|' -f1 | sort -u)
echo "re-running empty cells in dirs: ${DIRS[*]}"
for d in "${DIRS[@]}"; do run_dir "$d" & done
wait
echo "RERUN DONE $(date -u +%H:%M:%S)" > "$LOGDIR/_DONE"
