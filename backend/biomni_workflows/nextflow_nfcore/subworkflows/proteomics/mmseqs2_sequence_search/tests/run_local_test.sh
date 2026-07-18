#!/usr/bin/env bash
# REAL end-to-end local test for mmseqs2_sequence_search (no Docker).
# Installs the MMseqs2 static binary if missing, makes a small target + query
# FASTA, and runs the workflow. Asserts:
#   (a) 1 MMSEQS_SEQUENCE_SEARCH task
#   (b) a summary JSON with all 3 queries
#   (c) each query self-matches its own sequence (100% identity) as best hit
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
fails=0

# 1. MMseqs2 static binary (open GPL; no Docker needed).
MMBIN="${MMSEQS_BIN:-/tmp/mmseqs/bin/mmseqs}"
if [ ! -x "$MMBIN" ]; then
  echo "installing mmseqs2 static binary..."
  ( cd /tmp && curl -fsSL https://mmseqs.com/latest/mmseqs-osx-universal.tar.gz -o mmseqs.tar.gz && tar xzf mmseqs.tar.gz ) || { echo "mmseqs install failed"; exit 1; }
fi
MMDIR="$(dirname "$MMBIN")"

# 2. Demo target + query FASTA (ubiquitin, lysozyme, insulin-B).
cat > "$WORK/targets.fasta" <<'FA'
>ubiquitin
MQIFVKTLTGKTITLEVEPSDTIENVKAKIQDKEGIPPDQQRLIFAGKQLEDGRTLSDYNIQKESTLHLVLRLRGG
>lysozyme
KVFGRCELAAAMKRHGLDNYRGYSLGNWVCAAKFESNFNTQATNRNTDGSTDYGILQINSRWWCNDGRTPGSRNLCNIPCSALLSSDITASVNCAKKIVSDGNGMNAWVAWRNRCKGTDVQAWIRGCRL
>insulin_b
FVNQHLCGSHLVEALYLVCGERGFFYTPKT
FA
cp "$WORK/targets.fasta" "$WORK/query.fasta"

# 3. Run the workflow (mmseqs on PATH; local tasks inherit it).
( cd "$WORK" && PATH="$MMDIR:$PATH" nextflow -q run "$DIR/main.nf" -c "$DIR/tests/test.config" \
    -with-trace "$WORK/trace.txt" \
    --query_fasta "$WORK/query.fasta" --mmseqs_db "$WORK/targets.fasta" \
    --outdir "$WORK/results" > "$WORK/log" 2>&1 )
if [ $? -ne 0 ]; then echo "NEXTFLOW FAILED:"; tail -30 "$WORK/log"; exit 1; fi

check() { if [ "$2" = "$3" ]; then echo "  PASS: $1 ($2)"; else echo "  FAIL: $1 — got '$2', expected '$3'"; fails=$((fails+1)); fi }
SUM="$WORK/results/mmseqs/mmseqs_summary.json"
nq() { python3 -c "import json;print(json.load(open('$1')).get('n_queries'))" 2>/dev/null || echo ERR; }
selfmatch() { python3 -c "
import json
d=json.load(open('$1'))
ok=all((q.get('best_hit') or {}).get('target')==q['query'] for q in d['queries'])
print('yes' if ok else 'no')" 2>/dev/null || echo ERR; }

check "search task ran" "$(grep -c MMSEQS_SEQUENCE_SEARCH "$WORK/trace.txt" 2>/dev/null || echo 0)" 1
check "summary produced" "$([ -f "$SUM" ] && echo yes || echo no)" yes
check "all 3 queries present" "$(nq "$SUM")" 3
check "every query self-matches (best hit == query)" "$(selfmatch "$SUM")" yes

echo
if [ "$fails" -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "$fails CHECK(S) FAILED"; fi
echo "(work dir: $WORK)"
exit $fails
