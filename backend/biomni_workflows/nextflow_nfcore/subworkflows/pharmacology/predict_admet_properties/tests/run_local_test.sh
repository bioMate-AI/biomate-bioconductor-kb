#!/usr/bin/env bash
# Local (no-Docker) verification of ADMET compound-library fan-out.
# Runs the real reduce (PREDICT_ADMET_PROPERTIES) with a mocked map and asserts:
#   (a) N=7,size=3  -> 3 parallel map tasks + 1 reduce
#   (b) merged per_compound_admet_ai length == 7 (all compounds present)
#   (c) global worst hERG (CWORST in shard_1) surfaces as toxicity.hERG_probability
#   (d) N=2,size=25 -> 1 map task (no fan-out) + correct merge (no regression)
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"   # -> predict_admet_properties/ (abs)
SCRIPT="$DIR/tests/test_shard.nf"
CFG="$DIR/tests/test.config"
WORK="$(mktemp -d)"
NF="${NEXTFLOW:-nextflow}"
fails=0

# Launch Nextflow FROM the temp dir (via absolute script path) so no .nextflow/
# artifacts land in the repo. Includes resolve relative to the script file.
run() {  # name smiles size
  rm -rf "$WORK/$1"; mkdir -p "$WORK/$1"
  ( cd "$WORK/$1" && "$NF" -q run "$SCRIPT" -c "$CFG" \
     -with-trace "$WORK/$1/trace.txt" \
     --smiles_list "$2" --admet_shard_size "$3" --outdir "$WORK/$1/results" \
     > "$WORK/$1/log" 2>&1 )
  if [ $? -ne 0 ]; then echo "  NEXTFLOW FAILED ($1):"; tail -30 "$WORK/$1/log"; fails=$((fails+1)); return 1; fi
}

check() { # description  actual  expected
  if [ "$2" = "$3" ]; then echo "  PASS: $1 ($2)"; else echo "  FAIL: $1 — got '$2', expected '$3'"; fails=$((fails+1)); fi
}

count_proc() { grep -c "$2" "$WORK/$1/trace.txt" 2>/dev/null || echo 0; }
jq_len() { python3 -c "import json,sys;d=json.load(open('$1'));print(len(d.get('toxicity',{}).get('per_compound_admet_ai',[]) if False else d.get('per_compound_admet_ai',[])))" 2>/dev/null || echo ERR; }
tox_field() { python3 -c "import json;d=json.load(open('$1'));print(d.get('toxicity',{}).get('$2'))" 2>/dev/null || echo ERR; }

echo "== Scenario A: N=7, shard_size=3 =="
run A '["C1","C2","C3","C4","CWORST","C6","C7"]' 3 || { echo "aborting A"; }
TOX_A="$WORK/A/results/run/toxicity_report.json"
check "map tasks (ceil 7/3)"        "$(count_proc A ADMET_INFER_SHARD_MOCK)" 3
check "reduce tasks"                "$(count_proc A 'PREDICT_ADMET_PROPERTIES')" 1
check "all compounds merged"        "$(jq_len "$TOX_A")" 7
check "global-worst hERG surfaced"  "$(tox_field "$TOX_A" hERG_probability)" 0.99

echo "== Scenario B: N=2, shard_size=25 (no fan-out / no regression) =="
run B '["CC(=O)OC1=CC=CC=C1C(=O)O","CWORST"]' 25 || { echo "aborting B"; }
TOX_B="$WORK/B/results/run/toxicity_report.json"
check "single map task (1 shard)"   "$(count_proc B ADMET_INFER_SHARD_MOCK)" 1
check "reduce tasks"                "$(count_proc B 'PREDICT_ADMET_PROPERTIES')" 1
check "both compounds merged"       "$(jq_len "$TOX_B")" 2
check "global-worst hERG surfaced"  "$(tox_field "$TOX_B" hERG_probability)" 0.99

echo
if [ "$fails" -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "$fails CHECK(S) FAILED"; fi
echo "(work dir: $WORK)"
exit $fails
