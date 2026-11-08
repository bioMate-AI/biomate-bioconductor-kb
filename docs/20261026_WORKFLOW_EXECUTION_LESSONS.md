# Lessons: running real workflows through BioMate (2026-10-26)

From stress-testing the execute path end-to-end (search → run → AWS Batch → S3) while producing real run
data for the Design UI handoff: BOIN (`clinical_trial_simulation`), survival KM + Cox
(`survival` / `survival_cox_proportional_hazards_regression`), and DESeq2
(`validation_deseq2_raw_counts`) on real inputs.

## Headline
**Capabilities and engine are solid; the weak layer is the declared contract.** A workflow's full
contract — intents, parameters, and **inputs** — is not declared in one place the system can read, so
prefill / gating / routing / validation all degrade exactly where real pipelines get complex
(multi-input). See the fix in `docs/20261026_PARAMS_VS_INPUTS_GAP.md`.

## What works
- The execute path works: `run_workflow` → AWS Batch (Nextflow) → S3 outputs produced real results for
  every workflow we actually got running. The substrate is not the problem.
- **Declared scalar params** degrade gracefully: schema/.nf defaults, then a rule+LLM prefill from the
  user message, with per-value provenance (`default`/`recommended`/`from message`/`llm_extracted`/
  `autoFilled`). BOIN auto-filled `design=BOIN`; everything else fell back to defaults and ran.

## What doesn't (every failure this session)
- **Required inputs are invisible.** They live in the script (`read.csv("patient_clinical_data.csv")`) or
  a wrapper (`read_input_file("cts")`), not in `required_params`. `search_workflow` reported
  `required_params: []` for workflows that in fact require a file → they **launch and crash at runtime**,
  empty output dir, real error buried in the S3 `.command.err`. No pre-run "attach X" prompt.
- **Multi-input is discovered by serial crashing.** DESeq2 needed input key `cts` (not `input`), *then* a
  second input `coldata` — each learned only by a failed Batch run. Input *keys*, *arity*, and *format*
  are not queryable up front.
- **Upload filename mismatch.** `upload_file` UUID-prefixes the S3 key; a workflow that reads a hardcoded
  basename can't find it until the object is re-keyed to the exact name (unless the workflow declares
  `stageAs`).
- **Inconsistent auto-mapping.** The KM workflow auto-maps `event→status`/`time_days→time`; the Cox
  workflow does not (needs literal `time`/`status`). Same domain, different behavior — no shared contract.

## Operational know-how (reusable)
- Read outputs **directly from S3 via rclone**, not `get_run`/`list_runs` (85 KB+ responses). Bucket is
  **us-east-1** (region mismatch breaks some rclone ops). `output/` often holds empty publish-symlinks
  while the real files sit in the task/work dir (`.../clinical_trial_run/`, `.../NN/<hash>/`).
- Diagnose a failed Batch task from `work/.../<hash>/.command.err` + `.exitcode` (cheap, targeted).
- To fix the upload-name trap: `rclone copyto` the uploaded object to a clean-named key, pass that key.

## Data-reality lessons
- **"Validated" ≠ reproducible on demand.** NCA, PBPK (full param set), and survival had no committed
  real-run outputs; the DB `real_exec_status` column is **not back-filled** even where dated Batch-run
  docs exist — trusting the DB column alone misreads validation status.
- **Some shown numbers aren't reproducible as shown.** The displayed DESeq2 "34,371 / 1,242" split needs
  the *original* full results (only top-200 is committed); a fresh airway re-run gives different,
  self-consistent totals. Design's "no number without a run" rule is what surfaced all of this.
- Genuinely blocked-on-data items: qPCR geNorm (raw Ct matrix not committed), exact GSE52778 full split.

## Adjacent findings (same root cause)
- **Naming/identity confusion:** `survival_analysis_km` is trial-DESIGN, not data KM/Cox (data KM/Cox =
  `survival` / `survival_cox_proportional_hazards_regression`).
- **Polymorphic workflows** (one implementation, N intents via a `mode` param) are common (~8–15) →
  intent-alias pattern (keep old name as deprecated alias; no breaking rename).
- **Verify by rendering/running, not assuming:** the "platform panels render English" alarm was wrong —
  a single screenshot disproved it. Direct evidence beats inference.

## The through-line
Declare the whole contract (intents + params + inputs) in one machine-readable place, derive it from the
scripts so it can't drift, and every downstream system (prefill, gating, routing, executor staging,
prereq benchmark) improves at once.
