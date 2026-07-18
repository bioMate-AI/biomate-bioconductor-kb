#!/usr/bin/env bash
# REAL end-to-end local test for fpsim2_chemical_similarity (no Docker).
# Uses a Python venv with FPSim2 + RDKit, builds a small fingerprint DB, and runs
# the workflow with 2 query molecules (per-query fan-out). Asserts:
#   (a) 2 parallel FPSIM2_SIMILARITY_SEARCH tasks
#   (b) each query produces a hits JSON
#   (c) each query self-matches its own molecule as the best hit (Tanimoto 1.0)
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
fails=0

# 1. Python venv with FPSim2 + RDKit (no Docker).
VENV="${FPSIM2_VENV:-/tmp/fpsim_venv}"
if [ ! -x "$VENV/bin/python" ] || ! "$VENV/bin/python" -c "import FPSim2, rdkit" 2>/dev/null; then
  echo "creating FPSim2 venv..."
  python3 -m venv --clear "$VENV" && "$VENV/bin/python" -m ensurepip --upgrade >/dev/null 2>&1
  "$VENV/bin/python" -m pip install -q FPSim2 rdkit >/dev/null 2>&1 || { echo "FPSim2 install failed"; exit 1; }
fi
VBIN="$VENV/bin"

# 2. Build a small demo fingerprint DB (aspirin, salicylic acid, ibuprofen, caffeine, acetaminophen).
DB="$WORK/chem_demo.h5"
"$VBIN/python" - "$DB" <<'PY'
import sys
from FPSim2.io import create_db_file
mols = [
    ["CC(=O)Oc1ccccc1C(=O)O", 1],       # aspirin
    ["O=C(O)c1ccccc1O", 2],              # salicylic acid
    ["CC(C)Cc1ccc(cc1)C(C)C(=O)O", 3],   # ibuprofen
    ["Cn1cnc2c1c(=O)n(C)c(=O)n2C", 4],   # caffeine
    ["CC(=O)Nc1ccc(O)cc1", 5],           # acetaminophen
]
create_db_file(mols, sys.argv[1], mol_format="smiles", fp_type="Morgan", fp_params={"radius":2,"fpSize":2048})
print("built demo DB")
PY

# 3. Run the workflow (FPSim2 python on PATH; local tasks inherit it).
( cd "$WORK" && PATH="$VBIN:$PATH" nextflow -q run "$DIR/main.nf" -c "$DIR/tests/test.config" \
    -with-trace "$WORK/trace.txt" \
    --query_smiles "CC(=O)Oc1ccccc1C(=O)O,CC(C)Cc1ccc(cc1)C(C)C(=O)O" \
    --fpsim2_db "$DB" --similarity_threshold 0.3 --outdir "$WORK/results" > "$WORK/log" 2>&1 )
if [ $? -ne 0 ]; then echo "NEXTFLOW FAILED:"; tail -30 "$WORK/log"; exit 1; fi

check() { if [ "$2" = "$3" ]; then echo "  PASS: $1 ($2)"; else echo "  FAIL: $1 — got '$2', expected '$3'"; fails=$((fails+1)); fi }
bestid()  { "$VBIN/python" -c "import json;d=json.load(open('$1'));print((d.get('best_hit') or {}).get('mol_id'))" 2>/dev/null || echo ERR; }
bestsim() { "$VBIN/python" -c "import json;d=json.load(open('$1'));print((d.get('best_hit') or {}).get('tanimoto'))" 2>/dev/null || echo ERR; }

check "parallel query tasks" "$(grep -c FPSIM2_SIMILARITY_SEARCH "$WORK/trace.txt" 2>/dev/null || echo 0)" 2
Q0="$WORK/results/q_0/q_0_similarity_hits.json"   # aspirin
Q1="$WORK/results/q_1/q_1_similarity_hits.json"   # ibuprofen
check "aspirin query produced hits" "$([ -f "$Q0" ] && echo yes || echo no)" yes
check "ibuprofen query produced hits" "$([ -f "$Q1" ] && echo yes || echo no)" yes
check "aspirin best hit = mol_id 1 (self)" "$(bestid "$Q0")" 1
check "aspirin best Tanimoto = 1.0" "$(bestsim "$Q0")" 1.0
check "ibuprofen best hit = mol_id 3 (self)" "$(bestid "$Q1")" 3
check "ibuprofen best Tanimoto = 1.0" "$(bestsim "$Q1")" 1.0

echo
if [ "$fails" -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "$fails CHECK(S) FAILED"; fi
echo "(work dir: $WORK)"
exit $fails
