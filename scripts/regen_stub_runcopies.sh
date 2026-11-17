#!/usr/bin/env bash
#
# regen_stub_runcopies.sh — regenerate stub-sourced nf-core RUN-copies.
#
# ROOT CAUSE (the Stream-6 saga, fixed 2026-11-17):
#   backend/nf-core-workflows/<wf>/ holds REAL nf-core pipeline downloads. It is
#   .gitignore'd (see .gitignore: `backend/nf-core-workflows/`) and lives only on
#   the container — the deploy NEVER ships it. Meanwhile the executor resolver
#   (_resolve_nextflow_path in nextflow_executor.py) searches that REAL run-copy
#   BEFORE the biomni_workflows/nfcore/<wf> stub. So for workflows where OUR stub
#   is the functional source of truth (declared `// Input:` contract + gate
#   self-correction, e.g. differentialabundance), the stale run-copy main.nf
#   shadowed the stub and editing+committing+deploying the stub had ZERO runtime
#   effect. This script closes that gap on every workflows-layer sync.
#
# SAFE GENERIC RULE:
#   A stub is treated as source-of-truth ONLY if its main.nf carries the BioMate
#   declared-input marker: a line matching `^// Input:`. Display-only stubs
#   (rnaseq, sarek, scrnaseq, …) have no such header, so legitimately-downloaded
#   real nf-core pipelines are left 100% untouched. We overwrite ONLY main.nf
#   (keeping the real pipeline's nextflow.config / schema / modules) and ONLY
#   when a run-copy dir already exists (no real download ⇒ the resolver already
#   falls back to the stub, nothing to regenerate).
#
# GUARD: after regenerating a stub-sourced run-copy, assert it carries the marker.
#   A missing marker means a silent stub/run-copy divergence → hard-fail the deploy.
#
# Parametrized by APP_ROOT (default /app) so it can run inside the Galaxy
# container during deploy AND against a temp fixture dir in the unit test
# (scripts/test_regen_stub_runcopies.sh). Single source of truth — do not inline.

set -u

APP_ROOT="${APP_ROOT:-/app}"
STUB_GLOB="${APP_ROOT}/biomni_workflows/nfcore/*/main.nf"

marker_re='^// Input:'
regenerated=0
rc=0

for stub in $STUB_GLOB; do
  [ -f "$stub" ] || continue
  # Only stubs that declare the BioMate `// Input:` input contract are
  # source-of-truth; display-only stubs are skipped (real download wins).
  grep -qE "$marker_re" "$stub" || continue
  wf="$(basename "$(dirname "$stub")")"
  runcopy="${APP_ROOT}/nf-core-workflows/${wf}/main.nf"
  # No real download for this wf ⇒ resolver already uses the stub; skip.
  [ -f "$runcopy" ] || continue
  cp -f "$stub" "$runcopy"
  regenerated=$((regenerated + 1))
  echo "  ✓ regenerated nf-core-workflows/${wf}/main.nf from stub (BioMate source-of-truth)"
  # Guard: a stub-sourced run-copy MUST carry the marker after regen.
  if [ "$(grep -cE "$marker_re" "$runcopy")" -lt 1 ]; then
    echo "  ✗ FATAL: run-copy ${wf}/main.nf missing '// Input:' marker after regen — stub/run-copy divergence" >&2
    rc=1
  fi
done

echo "  regen_stub_runcopies: ${regenerated} run-copy(ies) regenerated from stub"
exit $rc
