# QC After-Run Document — Root-Cause Diagnosis & Fix (2026-10-19)

## Symptom (user report)
> "The QC tab in after-run just shows a large-font 'QC passed'. Where is the
> well-formatted QC document with the list of QC gates and detailed status?"
> …and on reopening a historical run, the after-run panel info is gone.

## Investigation (on dev, fixture account, real runs — no mocks)
Drove a real ADMET run via the BioMate MCP (`biomate_session`) against
`dev-public.biomate.ai`. Observed run `e2c3e772` complete (195 s, outputs in S3)
yet stay `status:running` in the persisted record, `finalized_by:None`,
`qc:False`, and **no `qc_events.json` sidecar** — while `qc_metrics.json` and
`toxicity_report.json` sat durably in S3.

## Root cause — three layers
1. **Sidecar path/region (Layer A).** The earlier fix wrote the QC sidecar to
   the parent dir of the first S3 output file. But Nextflow publishes outputs
   under `<outdir>/run/` and `<outdir>/pipeline_info/` — there is **no
   `<outdir>/output/`** — so the sidecar landed in `/run/` while the Node reader
   looked in `/output/`. Region was also pinned to `us-west-2`; the bucket is
   `us-east-1` (cross-region `PutObject` → `PermanentRedirect`, silent loss).
2. **QC never evaluated for orphaned Batch completions (Layer B).** QC eval
   (`_evaluate_qc_from_s3`) only runs inside the Galaxy completion path, gated on
   `run_id in _runs` (the launching worker's in-process dict). For AWS Batch runs
   the Node status-sync independently marks the run `completed` (and saves
   outputs) while the Galaxy completion thread is frequently orphaned (worker
   recycle) and the orphan poller doesn't always finalize. Net: no live monitor,
   no audit log, AND no sidecar — the QC tab shows the empty "all passed"
   fallback even though the gate data is in S3.
3. **All-pass runs record no gate rows (Layer C).** `_check_qc_thresholds`
   appends to its list only on threshold *violation*; `get_qc_report()` returns
   `events = qc_event_log` which holds only triggered gates + warnings. An
   all-pass run therefore yields `events:[]` → the frontend's "QC passed" empty
   state. This is the literal symptom the user described.

## Fixes
- **A** (`bf4b0fba6`): write sidecar to `<outdir>/output/qc_events.json` via the
  run's authoritative stored outdir (`get_run_state_store().get_run(run_id)
  ["outdir"]`, = `nextflowOutputDir` that Node reads), with bucket-region
  resolution.
- **B** (`c6e6505d3`, `2d592dd38`): on-demand S3 QC eval. Node `/qc-events`
  resolves the run (Postgres is the only durable invocation→outdir map) and
  forwards `outdir`/`run_id`/`workdir` to the backend; the backend, when the live
  monitor + audit are gone, lists S3 outputs and runs `_evaluate_qc_from_s3`
  (self-detects ADMET/CryoEM/preproc from file signatures — no domain needed),
  writes the sidecar, and returns it as `source:"s3_ondemand"`.
- **C** (in progress): record every evaluated gate (pass *and* fail) so the
  after-run QC tab shows the full gate table even when nothing failed. The
  frontend QcAuditTab already renders ✓ PASS rows — backend-only change.

## Verification (dev)
- `GET /api/invocations/b65f8ac0…/qc-events` for completed run `e2c3e772` →
  `source:"s3_sidecar"`, and `qc_events.json` is now persisted at
  `…/56413605/output/qc_events.json`. On-demand eval + correct path confirmed.
- `events:[]` for this run because the ADMET-AI workflow computed only AMES
  (passing) — see Layer C.

## Capability observations (separate from QC rendering)
- The "Predict ADMET Properties (AI)" workflow emitted only AMES in
  `toxicity_report.json` — no hERG/CYP3A4/bioavailability despite the request.
- The parallel "hERG Cardiac Safety QSAR" run failed with empty
  `toolParameters:{}` — the MCP `biomate_session` did not pass the SMILES to the
  second workflow (param-prefill gap).

## Follow-ups
- Extend Layer-C pass-gate recording beyond ADMET to the CryoEM/preproc branches.
- Investigate why Batch completions orphan (RUN_STATE_STORE/poller on dev).
- ADMET-AI endpoint coverage (hERG/CYP) + MCP multi-workflow param prefill.
