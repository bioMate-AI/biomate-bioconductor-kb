#!/usr/bin/env bash
# REAL end-to-end local test for foldseek_structure_search (no Docker).
# Installs the foldseek static binary if missing, fetches 3 small PDB structures,
# and exercises BOTH query modes:
#
#   PART A — query_type=structure (default, unchanged behavior):
#     runs the workflow with 2 query structures (per-query fan-out) against a
#     demo target folder. Asserts:
#       (a) 2 parallel FOLDSEEK_STRUCTURE_SEARCH tasks
#       (b) each query produces a summary JSON with hits
#       (c) each query self-matches its own structure as the best hit
#
#   PART B — query_type=sequence (ProstT5 3Di-from-sequence):
#     runs the workflow with a protein FASTA query + the ProstT5 model against
#     the same structure DB. If the ProstT5 weights are present (PROSTT5_MODEL,
#     default /tmp/foldseek/prostt5) this is a REAL search and we assert a hits
#     file + summary json are produced and the best hit is sane (the FASTA is
#     ubiquitin's sequence -> best hit should be 1UBQ). If the weights are NOT
#     present (~1-2 GB download), we fall back to asserting the command is
#     CONSTRUCTED correctly via `nextflow -preview` + the .command.sh — full
#     ProstT5 validation is then deferred to a Batch GPU run.
#
#   PART C — guard: query_type=sequence WITHOUT --prostt5_model must error.
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
PROSTT5_MODEL="${PROSTT5_MODEL:-/tmp/foldseek/prostt5}"

check() { if [ "$2" = "$3" ]; then echo "  PASS: $1 ($2)"; else echo "  FAIL: $1 — got '$2', expected '$3'"; fails=$((fails+1)); fi }
best() { python3 -c "import json;d=json.load(open('$1'));print((d.get('best_hit') or {}).get('target'))" 2>/dev/null || echo ERR; }
nhits() { python3 -c "import json;print(json.load(open('$1')).get('n_hits'))" 2>/dev/null || echo ERR; }
qtype() { python3 -c "import json;print(json.load(open('$1')).get('query_type'))" 2>/dev/null || echo ERR; }

# 2. Demo structures (crambin, ubiquitin, lysozyme). Two are reused as queries.
DEMO="$WORK/demo"; mkdir -p "$DEMO/targets" "$DEMO/query"
for id in 1CRN 1UBQ 1LYZ; do
  curl -fsSL "https://files.rcsb.org/download/$id.pdb" -o "$DEMO/targets/$id.pdb" || { echo "PDB fetch failed ($id)"; exit 1; }
done
cp "$DEMO/targets/1UBQ.pdb" "$DEMO/query/q_ubq.pdb"
cp "$DEMO/targets/1CRN.pdb" "$DEMO/query/q_crn.pdb"

# ==================================================================
echo "=== PART A: query_type=structure (default, unchanged) ==="
# ==================================================================
( cd "$WORK" && PATH="$FSDIR:$PATH" nextflow -q run "$DIR/main.nf" -c "$DIR/tests/test.config" \
    -with-trace "$WORK/trace_A.txt" \
    --query_structures "$DEMO/query/q_ubq.pdb,$DEMO/query/q_crn.pdb" \
    --foldseek_db "$DEMO/targets" \
    --outdir "$WORK/results_A" > "$WORK/log_A" 2>&1 )
if [ $? -ne 0 ]; then echo "  FAIL: PART A nextflow run"; tail -30 "$WORK/log_A"; fails=$((fails+1)); fi

check "parallel query tasks" "$(grep -c FOLDSEEK_STRUCTURE_SEARCH "$WORK/trace_A.txt" 2>/dev/null || echo 0)" 2
S_UBQ="$WORK/results_A/q_ubq/q_ubq_foldseek_summary.json"
S_CRN="$WORK/results_A/q_crn/q_crn_foldseek_summary.json"
check "ubiquitin query produced summary" "$([ -f "$S_UBQ" ] && echo yes || echo no)" yes
check "crambin query produced summary"   "$([ -f "$S_CRN" ] && echo yes || echo no)" yes
check "ubiquitin best hit is 1UBQ (self-match)" "$(best "$S_UBQ")" 1UBQ
check "crambin best hit is 1CRN (self-match)"   "$(best "$S_CRN")" 1CRN
check "summary records query_type=structure" "$(qtype "$S_UBQ")" structure
[ "$(nhits "$S_UBQ")" -ge 1 ] 2>/dev/null && echo "  PASS: ubiquitin has >=1 hit ($(nhits "$S_UBQ"))" || { echo "  FAIL: ubiquitin hits"; fails=$((fails+1)); }

# ==================================================================
echo
echo "=== PART C: guard — query_type=sequence with no prostt5_model errors ==="
# ==================================================================
# Build a query FASTA (ubiquitin sequence, 1UBQ).
cat > "$DEMO/query/q_ubq.fasta" <<'FASTA'
>q_ubq ubiquitin (1UBQ chain A)
MQIFVKTLTGKTITLEVEPSDTIENVKAKIQDKEGIPPDQQRLIFAGKQLEDGRTLSDYNIQKESTLHLVLRLRGG
FASTA
( cd "$WORK" && PATH="$FSDIR:$PATH" nextflow -q run "$DIR/main.nf" -c "$DIR/tests/test.config" \
    --query_type sequence \
    --query_structures "$DEMO/query/q_ubq.fasta" \
    --foldseek_db "$DEMO/targets" \
    --outdir "$WORK/results_C" > "$WORK/log_C" 2>&1 )
if grep -q "requires --prostt5_model" "$WORK/log_C"; then
  echo "  PASS: missing prostt5_model produced a clear guard error"
else
  echo "  FAIL: guard did not fire; log:"; tail -10 "$WORK/log_C"; fails=$((fails+1))
fi

# ==================================================================
echo
echo "=== PART B: query_type=sequence (ProstT5 3Di-from-sequence) ==="
# ==================================================================
if [ -d "$PROSTT5_MODEL" ] || [ -f "$PROSTT5_MODEL" ]; then
  echo "  ProstT5 weights found at $PROSTT5_MODEL — running REAL sequence search."
  ( cd "$WORK" && PATH="$FSDIR:$PATH" nextflow -q run "$DIR/main.nf" -c "$DIR/tests/test.config" \
      -with-trace "$WORK/trace_B.txt" \
      --query_type sequence \
      --query_structures "$DEMO/query/q_ubq.fasta" \
      --prostt5_model "$PROSTT5_MODEL" \
      --foldseek_db "$DEMO/targets" \
      --outdir "$WORK/results_B" > "$WORK/log_B" 2>&1 )
  if [ $? -ne 0 ]; then echo "  FAIL: PART B nextflow run"; tail -30 "$WORK/log_B"; fails=$((fails+1)); fi
  S_SEQ="$WORK/results_B/q_ubq/q_ubq_foldseek_summary.json"
  H_SEQ="$WORK/results_B/q_ubq/q_ubq_foldseek_hits.m8"
  check "sequence-mode produced hits file"   "$([ -f "$H_SEQ" ] && echo yes || echo no)" yes
  check "sequence-mode produced summary json" "$([ -f "$S_SEQ" ] && echo yes || echo no)" yes
  check "summary records query_type=sequence" "$(qtype "$S_SEQ")" sequence
  # Sanity: ubiquitin FASTA -> ProstT5 3Di -> best hit should be 1UBQ.
  check "sequence best hit is 1UBQ (sane)" "$(best "$S_SEQ")" 1UBQ
  [ "$(nhits "$S_SEQ")" -ge 1 ] 2>/dev/null && echo "  PASS: sequence query has >=1 hit ($(nhits "$S_SEQ"))" || { echo "  FAIL: sequence hits"; fails=$((fails+1)); }
else
  echo "  ProstT5 weights NOT present at $PROSTT5_MODEL (~1-2 GB download)."
  echo "  Falling back to COMMAND-CONSTRUCTION assertion via 'nextflow -preview'."
  echo "  Full ProstT5 validation is DEFERRED to a Batch GPU run (weights staged from"
  echo "  s3://biomate-production-data-399683337364/reference/foldseek/prostt5/ via"
  echo "  tools/prepare_prostt5_model.sh)."
  FAKE_MODEL="$WORK/fake_prostt5_model"; mkdir -p "$FAKE_MODEL"
  # -preview resolves the DAG + process scripts WITHOUT executing; enough to
  # verify our Groovy wires --prostt5-model into the foldseek command.
  ( cd "$WORK" && PATH="$FSDIR:$PATH" nextflow -q run "$DIR/main.nf" -c "$DIR/tests/test.config" \
      -preview \
      --query_type sequence \
      --query_structures "$DEMO/query/q_ubq.fasta" \
      --prostt5_model "$FAKE_MODEL" \
      --foldseek_db "$DEMO/targets" \
      --outdir "$WORK/results_B" > "$WORK/log_B" 2>&1 )
  # -preview alone doesn't emit .command.sh, so also unit-test the Groovy
  # interpolation directly: with a stub foldseek that echoes its argv, confirm
  # --prostt5-model appears for query_type=sequence and NOT for structure.
  STUB="$WORK/stub"; mkdir -p "$STUB"
  cat > "$STUB/foldseek" <<'STUBEOF'
#!/usr/bin/env bash
# Stub: on easy-search, record argv and emit a dummy hits file (arg 3), so the
# workflow's downstream python + summary path still runs. On version, print one.
if [ "$1" = "easy-search" ]; then
  printf '%s\n' "$*" >> "$PWD/../.foldseek_argv" 2>/dev/null || printf '%s\n' "$*" > /dev/null
  # arg 3 is the hits output path in our command.
  : > "$3" 2>/dev/null || true
  echo "1UBQ 1UBQ 0.0 100 1.0 0.99" | tr ' ' '\t' > "$3" 2>/dev/null || true
  exit 0
elif [ "$1" = "version" ]; then echo "stub-foldseek"; exit 0; fi
exit 0
STUBEOF
  chmod +x "$STUB/foldseek"
  ARGV_LOG="$WORK/foldseek_argv.log"
  # Wrap the stub so argv lands in a known file regardless of task cwd.
  cat > "$STUB/foldseek" <<STUBEOF
#!/usr/bin/env bash
if [ "\$1" = "easy-search" ]; then
  printf '%s\n' "\$*" >> "$ARGV_LOG"
  echo "1UBQ 1UBQ 0.0 100 1.0 0.99" | tr ' ' '\t' > "\$3"
  exit 0
elif [ "\$1" = "version" ]; then echo "stub-foldseek"; exit 0; fi
exit 0
STUBEOF
  chmod +x "$STUB/foldseek"

  : > "$ARGV_LOG"
  ( cd "$WORK" && PATH="$STUB:$PATH" nextflow -q run "$DIR/main.nf" -c "$DIR/tests/test.config" \
      --query_type sequence \
      --query_structures "$DEMO/query/q_ubq.fasta" \
      --prostt5_model "$FAKE_MODEL" \
      --foldseek_db "$DEMO/targets" \
      --outdir "$WORK/results_Bstub" > "$WORK/log_Bstub" 2>&1 )
  if grep -q -- "--prostt5-model $FAKE_MODEL" "$ARGV_LOG" 2>/dev/null; then
    echo "  PASS: sequence-mode command includes --prostt5-model <model> (mock)"
  else
    echo "  FAIL: --prostt5-model not wired into command; argv:"; cat "$ARGV_LOG"; fails=$((fails+1))
  fi
  S_STUB="$WORK/results_Bstub/q_ubq/q_ubq_foldseek_summary.json"
  check "mock sequence run recorded query_type=sequence" "$(qtype "$S_STUB")" sequence

  # And confirm structure-mode does NOT add --prostt5-model.
  : > "$ARGV_LOG"
  ( cd "$WORK" && PATH="$STUB:$PATH" nextflow -q run "$DIR/main.nf" -c "$DIR/tests/test.config" \
      --query_structures "$DEMO/query/q_crn.pdb" \
      --foldseek_db "$DEMO/targets" \
      --outdir "$WORK/results_Astub" > "$WORK/log_Astub" 2>&1 )
  if grep -q -- "--prostt5-model" "$ARGV_LOG" 2>/dev/null; then
    echo "  FAIL: structure-mode leaked --prostt5-model"; fails=$((fails+1))
  else
    echo "  PASS: structure-mode command omits --prostt5-model (mock)"
  fi
fi

echo
if [ "$fails" -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "$fails CHECK(S) FAILED"; fi
echo "(work dir: $WORK)"
exit $fails
