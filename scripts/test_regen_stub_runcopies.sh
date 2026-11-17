#!/usr/bin/env bash
#
# test_regen_stub_runcopies.sh — unit test / guard for scripts/regen_stub_runcopies.sh
#
# Verifies the root-cause fix for the Stream-6 saga: stub-sourced nf-core
# RUN-copies are regenerated from the stub on deploy, WITHOUT clobbering
# legitimately-downloaded real nf-core pipelines. Runs the real canonical
# script against a throwaway APP_ROOT fixture — no container, no network.
#
# Usage: bash scripts/test_regen_stub_runcopies.sh
# Exit 0 = all assertions pass; nonzero = a guarantee regressed.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/regen_stub_runcopies.sh"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/regen_test.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT

fail=0
ok()   { echo "  PASS: $1"; }
bad()  { echo "  FAIL: $1" >&2; fail=1; }

mkstub() { mkdir -p "$ROOT/biomni_workflows/nfcore/$1"; printf '%s\n' "$2" > "$ROOT/biomni_workflows/nfcore/$1/main.nf"; }
mkrun()  { mkdir -p "$ROOT/nf-core-workflows/$1";        printf '%s\n' "$2" > "$ROOT/nf-core-workflows/$1/main.nf"; }

# --- Fixture --------------------------------------------------------------
# 1. differentialabundance: BioMate source-of-truth stub (carries marker) +
#    a STALE real run-copy (no marker) and a sibling nextflow.config that MUST
#    survive (we overwrite only main.nf).
DIFFAB_STUB='// nf-core/differentialabundance — BioMate stub
// Input: samplesheet.csv, matrix.csv, contrasts.csv
process DESEQ2_DIFFERENTIAL_ANALYSIS {
    gate_row = "bioc_deseq2_design_blocking"
}
workflow DIFFERENTIALABUNDANCE_WORKFLOW { main: DESEQ2_DIFFERENTIAL_ANALYSIS(ch_input) }'
mkstub differentialabundance "$DIFFAB_STUB"
mkrun  differentialabundance '// STALE real nf-core differentialabundance main.nf (no // Input header)'
printf 'params.outdir = "./results"\n' > "$ROOT/nf-core-workflows/differentialabundance/nextflow.config"

# 2. rnaseq: display-only stub (NO marker) + a REAL downloaded pipeline run-copy.
#    The real pipeline MUST be left 100% untouched.
mkstub rnaseq '// nf-core/rnaseq — display-only BioMate stub (no declared inputs)
workflow RNASEQ { }'
REAL_RNASEQ='// REAL nf-core/rnaseq main.nf — downloaded pipeline, do not touch
include { FASTQC } from "./modules/nf-core/fastqc"'
mkrun  rnaseq "$REAL_RNASEQ"

# 3. newthing: marker stub but NO real download (no run-copy dir). Must be
#    skipped — we must NOT fabricate a run-copy for it.
mkstub newthing '// Input: reads.fastq
workflow NEWTHING { }'

# --- Run the real canonical script ---------------------------------------
echo "[test] running $SCRIPT against fixture APP_ROOT=$ROOT"
APP_ROOT="$ROOT" bash "$SCRIPT"
rc=$?
[ "$rc" -eq 0 ] && ok "script exited 0 on healthy fixture" || bad "script exited $rc (expected 0)"

diffab_run="$ROOT/nf-core-workflows/differentialabundance/main.nf"
rnaseq_run="$ROOT/nf-core-workflows/rnaseq/main.nf"

# --- Assertions -----------------------------------------------------------
# A) diffab run-copy regenerated from stub: carries all three required markers.
grep -qE '^// Input: samplesheet' "$diffab_run"        && ok "diffab run-copy has '// Input: samplesheet' header"          || bad "diffab run-copy missing '// Input:' header"
grep -q 'DIFFERENTIALABUNDANCE_WORKFLOW'  "$diffab_run" && ok "diffab run-copy has DIFFERENTIALABUNDANCE_WORKFLOW"          || bad "diffab run-copy missing DIFFERENTIALABUNDANCE_WORKFLOW"
grep -q 'bioc_deseq2_design_blocking'     "$diffab_run" && ok "diffab run-copy has bioc_deseq2_design_blocking gate"        || bad "diffab run-copy missing bioc_deseq2_design_blocking"
[ "$(grep -cE '^// Input: samplesheet' "$diffab_run")" -eq 1 ] && ok "diffab run-copy '// Input: samplesheet' count == 1"   || bad "diffab run-copy '// Input: samplesheet' count != 1"

# B) sibling nextflow.config of the real download survives (only main.nf replaced).
[ -f "$ROOT/nf-core-workflows/differentialabundance/nextflow.config" ] && ok "diffab run-copy nextflow.config preserved" || bad "diffab run-copy nextflow.config was deleted"

# C) real rnaseq pipeline left 100% untouched (display-only stub must not win).
if [ "$(cat "$rnaseq_run")" = "$REAL_RNASEQ" ]; then ok "real rnaseq run-copy untouched (no clobber)"; else bad "real rnaseq run-copy was overwritten — SAFETY VIOLATION"; fi
grep -q 'display-only' "$rnaseq_run" && bad "rnaseq run-copy got display-only stub content — SAFETY VIOLATION" || ok "rnaseq run-copy did not receive stub content"

# D) newthing (marker stub, no real download) must NOT get a fabricated run-copy.
[ -e "$ROOT/nf-core-workflows/newthing" ] && bad "fabricated a run-copy for newthing (no real download existed)" || ok "no run-copy fabricated for newthing (correctly skipped)"

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS — regen_stub_runcopies.sh behaves correctly"; else echo "FAILURES DETECTED" >&2; fi
exit $fail
