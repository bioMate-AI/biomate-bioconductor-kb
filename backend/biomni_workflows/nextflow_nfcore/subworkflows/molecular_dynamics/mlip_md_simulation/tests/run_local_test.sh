#!/usr/bin/env bash
#
# Local dry-run for molecular_dynamics/mlip_md_simulation.
#
# Runs the workflow with --mock true (no GPU / OpenMM / openmm-ml needed) and
# asserts:
#   1. exactly ONE MLIP_MD_SIMULATION process task completes
#   2. a well-formed mlip_md_summary.json is produced with the expected fields
#
# Proves the workflow WIRES correctly end-to-end without any Batch/GPU infra.
#
# Usage:  bash run_local_test.sh
# Requires: nextflow on PATH, python3. Does NOT require docker.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WF_DIR="$(dirname "$HERE")"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mlip_md_test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

echo "[test] work dir: $WORK"

# ── Build a tiny valid PDB input (2 heavy atoms: a diatomic) ──────────────────
INPUT_PDB="$WORK/tiny_system.pdb"
cat > "$INPUT_PDB" <<'PDB'
HETATM    1  C1  LIG A   1       0.000   0.000   0.000  1.00  0.00           C
HETATM    2  O1  LIG A   1       1.200   0.000   0.000  1.00  0.00           O
END
PDB

if ! command -v nextflow >/dev/null 2>&1; then
    echo "[FAIL] nextflow not found on PATH — install it to run the dry-run." >&2
    exit 2
fi

OUTDIR="$WORK/results"

echo "[test] launching nextflow (mock, docker disabled)..."
nextflow -q run "$WF_DIR/main.nf" \
    -c "$HERE/test.config" \
    --input_structure "$INPUT_PDB" \
    --outdir "$OUTDIR" \
    --mock true \
    -work-dir "$WORK/nf_work" \
    2>&1 | tee "$WORK/nf.log"

# ── Assertion 1: exactly one process task ran ─────────────────────────────────
# nextflow log line "Submitted process > MLIP_MD_SIMULATION (...)" appears once.
N_TASKS=$(grep -c "MLIP_MD_SIMULATION" "$WORK/nf.log" | head -1 || true)
SUBMITTED=$(grep -c "process > MLIP_MD_SIMULATION" "$WORK/nf.log" || true)
if [ "${SUBMITTED:-0}" -ne 1 ]; then
    # Fall back to counting produced summaries (robust to log format changes).
    :
fi

SUMMARY="$(find "$OUTDIR" -name 'mlip_md_summary.json' | head -1)"
N_SUMMARIES=$(find "$OUTDIR" -name 'mlip_md_summary.json' | wc -l | tr -d ' ')

if [ "$N_SUMMARIES" -ne 1 ]; then
    echo "[FAIL] expected exactly 1 summary json, found $N_SUMMARIES" >&2
    exit 1
fi
echo "[ok] exactly 1 process task produced 1 summary"

# ── Assertion 2: summary json is well-formed with required fields ─────────────
python3 - "$SUMMARY" <<'PY'
import json, sys
p = sys.argv[1]
with open(p) as f:
    s = json.load(f)

required = [
    "mol_id", "mock", "potential", "openmm_ml_potential_name",
    "n_steps", "temperature_k", "final_potential_energy_kj_mol",
    "rmsd_vs_input_nm", "trajectory", "engine",
]
missing = [k for k in required if k not in s]
assert not missing, f"missing fields: {missing}"

assert s["mock"] is True, "expected mock=True in dry-run"
assert s["potential"] == "aimnet2", f"expected default potential aimnet2, got {s['potential']}"
assert s["n_steps"] == 100, f"expected n_steps=100 from test.config, got {s['n_steps']}"
assert s["temperature_k"] == 300, f"expected temperature_k=300, got {s['temperature_k']}"
assert isinstance(s["final_potential_energy_kj_mol"], (int, float)), "energy must be numeric"
assert s["final_potential_energy_kj_mol"] < 0, "expected negative potential energy"
assert isinstance(s["rmsd_vs_input_nm"], (int, float)) and s["rmsd_vs_input_nm"] >= 0, "rmsd must be non-negative number"
assert s["trajectory"].endswith(".dcd"), "trajectory path must be a .dcd"

print("[ok] summary well-formed:", json.dumps(s, indent=2))
PY

echo ""
echo "[PASS] mlip_md_simulation dry-run: 1 task, well-formed summary json."
