# BioMate E2E / After-Run Workflow Issues (found during ZH tutorial capture)

Date: 2026-10-06. Found while capturing complete end-to-end (settings → phases →
running → **after-run tabs**) for each drug-discovery use case on dev
(https://dev-public.biomate.ai). Three real product issues block a populated
after-run for several workflows. None is a tutorial problem.

> **STATUS 2026-10-06 (update):**
> - **#1 FIXED + deployed** — findings synthesis is now bounded by a timeout
>   with auto-recovery via model fallback (commit `9b0899bf5`).
> - **#2 FIXED + committed** — root cause was NOT a missing DB index (the
>   workflow is indexed and executable); it was a wrong prompt rule. Fixed in
>   `a96deefda`.
> - **#3 routing FIXED + committed** (`a96deefda`); the deeper panel file-picker
>   gap is reframed below as a general Style-A limitation and documented (not a
>   workaround-shipped change) because it is high-blast-radius and needs a real
>   AWS Batch run to validate.

## 1. Findings generation hangs on "Analyzing outputs…" (qsar, likely others) — FIXED
- **Repro:** Run `Qsar Rf Model` with a valid `input_csv` (smiles + target). The
  run executes and the **运行结果 / After-run** tab opens, but the Summary stays on
  "正在分析输出… / Analysis in progress…" for >10 min and never populates.
- **Contrast:** ADMET (`predict_admet_properties`) findings populate fine
  (hERG/DILI/oral-bioavailability values appear within ~1 min).
- **Where:** `/api/workflows/runs/:id/findings` (frontend `routes.ts:14105`) returns
  `status:'pending'` while the Galaxy backend generates findings
  (`backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` → OutputAnalyzer +
  FindingReporter). The frontend `jobs/handlers/findings-analysis.ts` only polls.
- **Likely root cause:** the backend findings/OutputAnalyzer step for the qsar
  output set never reaches `ready` (parsing of qsar outputs, or the analysis LLM
  call, not completing). **Needs dev backend logs** for the specific run id to
  confirm (docker logs biomate-galaxy-dev around the findings call).
- **Impact:** real users running qsar never see findings; the after-run Summary is
  stuck. Fix the backend findings generation so it reaches `ready` (or surfaces an
  error) for qsar-type outputs.

## 2. PBPK does not route to any workflow — FIXED (`a96deefda`)
- **Repro:** "Run a PBPK simulation …" never produces a workflow card (Confirm &
  Run never appears; 240 s timeout).
- **ACTUAL root cause (re-diagnosed 2026-10-06):** NOT a missing index. The
  workflow IS indexed and routable — `pbpk_simulation` is present in the
  `workflows` table (`id=12873, domain=drug_discovery, source=nextflow,
  executable=1`); routing queries `workflows`, not `tools`, so the earlier
  "pbpk tool count = 0" was a red herring (these NF workflows live in `workflows`).
  The real cause was in the **prompt routing rule** (`galaxy-assistant.ts:820`):
  the `pbpk_simulation` bullet carried a `REQUIRED PREREQ CHECK` instructing the
  LLM to withhold the card until the user supplied SMILES + CLint + fu_plasma.
  Those params **all have defaults** in `main.nf` (SMILES=aspirin, fu_plasma=0.05,
  CLint=45, population=healthy_adult, dose=500). It was the only PK rule with such
  a block; every sibling ends "NO PREREQ CHECK — all params have defaults". So PBPK
  requests got a clarifying question and no card → the panel polled forever.
- **Fix applied:** replaced the prereq sentence with the sibling-standard
  "generate the card immediately; surface SMILES/CLint/fu_plasma/dose as editable
  params; do NOT block". One prompt-string edit, no DB/code/workflow-file change.
- **Verify:** on dev, "Run a PBPK simulation…" → `pbpk_simulation` card with
  Confirm & Run and prefilled defaults (no clarifying ask, no timeout).

## 3. Survival routing + a general Style-A panel-picker gap
### 3a. Survival mis-routing — FIXED (`a96deefda`)
- **Repro:** "Kaplan-Meier survival analysis and Cox …" routed to
  `survival_cox_proportional_hazards_regression` (the top dense-cosine candidate,
  because the query contains the verbatim workflow name) instead of a real
  input-bound workflow.
- **Root cause:** the single survival rule (`galaxy-assistant.ts:814`) lumped
  data-analysis terms with trial-design terms and pointed all of them at
  `survival_analysis_km` (a parametric trial-DESIGN workflow with no data input),
  and gave reselection no instruction to prefer the input-bound `survival` over the
  broken `survival_cox`.
- **Fix applied:** split into two disjoint bullets — DATA ANALYSIS (KM/Cox/log-rank/
  hazard-ratio on patient records) → select the `survival` workflow, explicitly
  NOT `survival_cox_proportional_hazards_regression` or `survival_analysis_km`;
  TRIAL DESIGN (sample size / power / accrual / Schoenfeld) → `survival_analysis_km`.

### 3b. NOT a bug — the "hardcoded `patient_clinical_data.csv`" read
- The R body's `read.csv("patient_clinical_data.csv")` is the **intended** Style-A
  contract, not a defect. The executor's `_resolve_read_filename` +
  `_stage_declared_input` (`nextflow_executor.py:1723-1936`) deliberately stage the
  user's uploaded file **under the exact filename the R reads**. Editing the R would
  have been a wrong "fix". No change made here.

### 3c. General gap (DOCUMENTED, not shipped) — Style-A workflows expose no panel file-picker
- **Observation:** `survival` (and every `// Input:`-header "Style-A" bioc workflow)
  shows "此工作流仅接受参数——没有需要绑定的数据输入 / no data inputs to bind" in the panel.
- **Root cause (traced):** the panel renders an input-binding row only for a param
  of `type:'file'` (`nextflow-workflow-viewer.tsx:2950`). File-typed params come
  only from (i) a null nextflow.config param ending in `_path`/`_ref`
  (`ai_assistant.py:1186-1191`) or (ii) an inline `file` annotation
  (`ai_assistant.py:1263`). **Nothing** consumes the `// Input:` header or
  `params_schema.data_inputs` into a file param — confirmed: no `data_inputs`
  reference exists anywhere in `frontend/server` or `frontend/client`. So Style-A
  workflows never surface a panel picker; today their data binds instead via the
  chat / data-library upload path + the executor's step-3 universal-fallback staging
  (`nextflow_executor.py:1827-1858`), which collects any file-valued param. For the
  hardcoded-read workflows, correct binding additionally requires the supplied file
  to reach `params["<declared token>"]` (e.g. `patient_clinical_data`) so step-2
  (`:1818-1826`) stages it under the exact read filename; an arbitrarily-named param
  goes through the list branch and keeps its own basename → the hardcoded read fails.
- **Proper fix (needs a focused, Batch-validated session — NOT shipped here):**
  surface each `// Input:` declared input (or `params_schema.data_inputs`) as a
  `type:'file'` required_param **named by the declared token** in the
  generate-workflow path (`ai_assistant.py`). This is the general, non-workflow-file
  root-cause fix, but it rewrites **every** workflow's `required_params` and could
  break the one-click no-input demo placeholders, so it must be validated with a real
  AWS Batch run across representative Style-A workflows before shipping. Per the
  project's no-speculative-deploy rule, it is documented here rather than shipped
  blind. (A narrower per-workflow alternative — annotating `survival`'s config input
  as `file` named `patient_clinical_data` — is possible but still needs a Batch run
  to confirm the end-to-end staging, and touches a production workflow file.)

## Notes / non-issues
- NCA, survival, FEP require the user's own data by design (data-first). Their
  after-run is produced from uploaded data via the data library, not a built-in demo.
- FEP (`openfe_rbfe`) additionally needs real protein PDB + ligand SDFs + GPU.
