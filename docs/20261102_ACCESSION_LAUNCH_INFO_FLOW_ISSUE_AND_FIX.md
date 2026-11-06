# Accession → workflow launch: empty run, no fetch, no prefill — issue & fix

**Date:** 2026-11-02
**Trigger:** `failed_workflow.png` — a user launched **nf-core/differentialabundance** for GEO
accession **GSE12345** in project "RNA-seq Differential Expression". The run launched with
**all inputs "not set"** (Samplesheet / Matrix / Contrasts), **nothing was fetched** for the
accession, and it then died with a work-directory error.

File:line references below come from a code trace on 2026-11-02; verify against current code
before editing (lines drift).

---

## 1. The issue (symptoms)

- The run was routed to `nf-core/differentialabundance`, which **expects pre-staged inputs**
  (a count matrix + a samplesheet/metadata + contrasts). It does **not** self-fetch data.
- **GSE12345 was never resolved or fetched**, so Samplesheet / Matrix / Contrasts came through
  **"not set" / "optional — empty"**.
- The run was **allowed to launch anyway** with no inputs, and failed at launch — surfaced as a
  generic "work directory could not be recognized as a valid file system path or S3 bucket"
  error (the opaque symptom of `main.nf` getting no files, not the real cause).

The work-directory error is a red herring. The real failure is **an empty, unfillable run that
was allowed to launch.**

## 2. Root cause — detected but orphaned

The GEO/accession capability **is built** — resolution, GEO-aware routing, fetchers, and a
required-param gate all exist. The failure is **wiring + one data bug**, not missing features.

### (a) The direct workflow-launch path does not resolve accessions
Accession machinery lives on surfaces that were **not invoked** by a direct launch:
- `resolve_accession` MCP tool — `frontend/server/routes.ts:9104-9194` (dispatch `:936-937`).
  Classifies `GSE\d+` → `geo_data_connector`, returns `prefilled_params`, `ready_to_run`, and a
  `next_step` telling the caller to **separately** call `run_workflow`. A two-call protocol;
  nothing auto-chains it into a launch.
- Chat GEO fast-path — `backend/lib/galaxy/ai/ai_assistant.py:4125-4351`
  (`_try_fast_path_geo_scrna_pseudobulk` / `_return_geo_bulk_connector`), only reachable inside
  `generate_workflow_unified` (`:4542-4550`). For a bare GSE it routes to
  **geo_data_connector / geo_scrna_pseudobulk — not differentialabundance**. The user got a DE
  card, so **this path was bypassed** (direct library/card launch).
- Executor accession-chain — `backend/.../nextflow_executor.py:6828-6865`. Fires **only when an
  accession is already a parameter VALUE**. All inputs were empty → `accession_params` empty →
  no fetch, and the "Detected … accession in --<key>" log (`:6862-6865`) never printed — silent.

### (b) The `geo_accession` type is never mapped to DE file inputs
- Typed extraction (`frontend/server/galaxy-assistant.ts:2612-2613, 2759-2761`) tags GSE12345 as
  `geo_accession`. But `WORKFLOW_PARAM_ALIASES` (`:1022+`) has **no differentialabundance entry**,
  so `geo_accession` is never remapped to `samplesheet`/`matrix`/`contrasts` → dropped.
- Backend `_inject_sra_into_params` (`ai_assistant.py:2787-2801`) only targets params named
  `reads/input/fastq/sample/...` — it can at best drop the raw string `"GSE12345"` into `input`,
  never a count matrix.
- Correct binding **requires a file that does not exist yet** — the accession can only become
  those files by first running the GEO ingest. That fetch→map step is absent from the launch path.

### (c) The empty-launch gate was disabled by a stub-schema bug
- `_get_workflow_params` prefers the JSON schema over the `.nf` parser (`ai_assistant.py:2742-2745`).
- The stub schema `backend/biomni_workflows/nfcore/differentialabundance/nextflow_schema.json`
  declares the Input/output group with **`required: []`** (props: samplesheet, input, matrix,
  contrasts, outdir). So every input is marked **OPTIONAL**.
- This contradicts the stub's own `.nf`: `main.nf:267` hard-requires
  `if (!params.samplesheet && !params.input) error …`, and the R step requires a matrix (`:92-93`).
- Consequence: the server-side execute gate (`routes.ts:10857-10896`) filters on `required_params`
  only; with **zero** required params it finds `missingParams=[]` and **permits the launch** with
  everything empty. The MCP prefill backstop (`routes.ts:869-890`) is keyed the same way and
  likewise no-ops.

### (d) Secondary bug: wrong fetcher for DE
Even if the accession had bound, the executor registry maps `GSE` → `handler:"sequencing"` →
**nf-core/fetchngs** (`nextflow_executor.py:612-617`), which produces a **FASTQ samplesheet**, not
the **count matrix** differentialabundance needs. GSE for a DE workflow must go through
`geo_data_connector` (count matrix), not fetchngs.

### (e) Observability gap — the flow is silent
There is **no log line that says "user named GSE12345 but it was never bound/fetched."** The only
trace is a generic run-start + a downstream work-dir error. Grep targets on dev — `GeoFastPath`,
`Detected .* accession in --`, `fetching_accessions`, `_return_nextflow_match`,
`missing_required_params` — are expected **ABSENT**, and that absence *is* the diagnosis.

## 3. The join point (the exact missing wiring)
GSE12345 should have become bound inputs at **launch time**:
`detect accession → resolve (geo_data_connector) → run the fetch → map count-matrix/metadata/
contrasts onto DE inputs → launch`. Today `run_workflow` (`routes.ts:841-900`) and
`/api/workflows/execute` (`:10625+`, gate `:10857`) do prefill/validation but **never call
accession resolution**, and nothing converts the `geo_accession` type into DE file params.

## 4. Solution — prioritized

1. **Re-arm the empty-launch gate (highest leverage, smallest change).** Align the stub schema's
   `required` with the `.nf` so `_parse_nextflow_schema` marks the real inputs required; the
   execute gate (`routes.ts:10877`) then returns an honest `missing_required_params` block instead
   of a silent empty launch. **Caveat:** the `.nf` requires samplesheet **OR** input, which a flat
   `required` array can't express — choose the always-required fields (e.g. `matrix`, and/or
   enforce the samplesheet-or-input rule in the gate, not the schema). Editing the nfcore **stub**
   schema is allowed (CLAUDE.md); do not touch executed `nextflow_nfcore/**` files.
2. **Wire accession-resolve-and-fetch into the launch path** (`/api/workflows/execute` or
   `run_workflow`): if a required file input is empty and the goal/message names an accession,
   resolve it; if it maps to a *fetcher* workflow (geo_data_connector), either auto-insert the
   fetch as a pre-step and map its outputs onto `samplesheet`/`matrix`/`contrasts`, or **refuse
   with a clear redirect** ("fetch GSE12345 via geo_data_connector first, then run DE").
3. **Enforce the geo_accession→DE guard at the router/LLM boundary.** The rule already exists as
   advice (`galaxy-assistant.ts:994-995`); make it enforced: a DE workflow (differentialabundance/
   DESeq2/edgeR/limma) + a bare GEO accession + no count matrix → block/redirect to
   geo_data_connector (mirror `_return_geo_bulk_connector` on the launch surface).
4. **Add "named-but-unbound accession" observability.** Emit a log/telemetry event when an
   accession is extracted but bound to no workflow param at launch (execute gate +
   `_return_nextflow_match`). One line would have pinpointed this in seconds.
5. **Fix GSE→fetchngs routing** (`nextflow_executor.py:612-617`) — route GSE for count-based DE
   through geo_data_connector, not fetchngs; or have the DE path reject a raw GSE value.
6. **Fail loudly pre-launch** — a pre-dispatch "DE selected but no count matrix resolved" check
   converts the opaque Nextflow work-dir crash into an actionable message.

### Built vs. not-built
**Built:** `resolve_accession`, GEO-aware routing (`_try_fast_path_geo_scrna_pseudobulk`,
`_return_geo_bulk_connector`), the geo_data_connector/fetchngs fetchers, the required-param gate.
**The gap is wiring + one data bug:** (i) resolution/fetch/GEO-routing aren't reachable from the
direct workflow-launch path, (ii) the `geo_accession` type is never mapped to DE file params, and
(iii) the stub schema's `required:[]` disables the gate that would have caught the empty launch.

## 5. Related
- GEO cascade / accession benchmark work (the capability that IS built): memory
  `project_accession_benchmark`, `docs/20260817_ACCESSION_TO_ANALYSIS_BENCHMARK_SPEC.md`,
  `docs/20260817_..._GEO_ACCESSION_CASCADE_AND_L2_EVIDENCE.md`. `geo_scrna_pseudobulk` is a general
  GEO ingest (getGEO series-matrix = array/bulk; RAW.tar pseudobulk = scRNA).
- UI-side fixes already shipped for the failed-run presentation (not the root cause above):
  `docs/20261101_UI_REFINEMENT_FIX_SESSION.md` (commit `628b3327e`: no false "Resume", platform
  error messaging).
