#!/usr/bin/env bash
# REAL end-to-end local test for foldseek_structure_search (no Docker).
# Installs the foldseek static binary if missing, fetches 3 small PDB structures,
# and runs the workflow with 2 query structures (per-query fan-out) against a
# demo target folder. Asserts:
#   (a) 2 parallel FOLDSEEK_STRUCTURE_SEARCH tasks
#   (b) each query produces a summary JSON with hits
#   (c) each query self-matches its own structure as the best hit (correctness)
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
fails=0

# 1. foldseek static binary (no Docker needed).
FSBIN="${FOLDSEEK_BIN:-/tmp/foldseek/bin/foldseek}"
if [ ! -x "$FSBIN" ]; then
  echo "installing foldseek static binary..."
  ( cd /tmp && curl -fsSL https://mmseqs.com/foldseek/foldseek-osx-universal.tar.gz -o fs.tgz && tar xzf fs.tgz ) || { echo "foldseek install failed"; exit 1; }
fi
FSDIR="$(dirname "$FSBIN")"

# 2. Demo structures (crambin, ubiquitin, lysozyme). Two are reused as queries.
DEMO="$WORK/demo"; mkdir -p "$DEMO/targets" "$DEMO/query"
for id in 1CRN 1UBQ 1LYZ; do
  curl -fsSL "https://files.rcsb.org/download/$id.pdb" -o "$DEMO/targets/$id.pdb" || { echo "PDB fetch failed ($id)"; exit 1; }
done
cp "$DEMO/targets/1UBQ.pdb" "$DEMO/query/q_ubq.pdb"
cp "$DEMO/targets/1CRN.pdb" "$DEMO/query/q_crn.pdb"

# 3. Run the workflow (foldseek on PATH; tasks inherit it via the local executor).
( cd "$WORK" && PATH="$FSDIR:$PATH" nextflow -q run "$DIR/main.nf" -c "$DIR/tests/test.config" \
    -with-trace "$WORK/trace.txt" \
    --query_structures "$DEMO/query/q_ubq.pdb,$DEMO/query/q_crn.pdb" \
    --foldseek_db "$DEMO/targets" \
    --outdir "$WORK/results" > "$WORK/log" 2>&1 )
if [ $? -ne 0 ]; then echo "NEXTFLOW FAILED:"; tail -30 "$WORK/log"; exit 1; fi

check() { if [ "$2" = "$3" ]; then echo "  PASS: $1 ($2)"; else echo "  FAIL: $1 — got '$2', expected '$3'"; fails=$((fails+1)); fi }
best() { python3 -c "import json;d=json.load(open('$1'));print((d.get('best_hit') or {}).get('target'))" 2>/dev/null || echo ERR; }
nhits() { python3 -c "import json;print(json.load(open('$1')).get('n_hits'))" 2>/dev/null || echo ERR; }

check "parallel query tasks" "$(grep -c FOLDSEEK_STRUCTURE_SEARCH "$WORK/trace.txt" 2>/dev/null || echo 0)" 2
S_UBQ="$WORK/results/q_ubq/q_ubq_foldseek_summary.json"
S_CRN="$WORK/results/q_crn/q_crn_foldseek_summary.json"
check "ubiquitin query produced summary" "$([ -f "$S_UBQ" ] && echo yes || echo no)" yes
check "crambin query produced summary"   "$([ -f "$S_CRN" ] && echo yes || echo no)" yes
check "ubiquitin best hit is 1UBQ (self-match)" "$(best "$S_UBQ")" 1UBQ
check "crambin best hit is 1CRN (self-match)"   "$(best "$S_CRN")" 1CRN
[ "$(nhits "$S_UBQ")" -ge 1 ] 2>/dev/null && echo "  PASS: ubiquitin has >=1 hit ($(nhits "$S_UBQ"))" || { echo "  FAIL: ubiquitin hits"; fails=$((fails+1)); }

echo
if [ "$fails" -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "$fails CHECK(S) FAILED"; fi
echo "(work dir: $WORK)"
exit $fails
