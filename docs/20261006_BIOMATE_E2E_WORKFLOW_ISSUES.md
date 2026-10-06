# BioMate E2E / After-Run Workflow Issues (found during ZH tutorial capture)

Date: 2026-10-06. Found while capturing complete end-to-end (settings → phases →
running → **after-run tabs**) for each drug-discovery use case on dev
(https://dev-public.biomate.ai). Three real product issues block a populated
after-run for several workflows. None is a tutorial problem.

## 1. Findings generation hangs on "Analyzing outputs…" (qsar, likely others)
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

## 2. PBPK does not route to any workflow
- **Repro:** "Run a PBPK simulation …" never produces a workflow card (Confirm &
  Run never appears; 240 s timeout).
- **Root cause:** `pbpk_simulation` exists on disk
  (`backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/pbpk_simulation/`,
  a working 8-compartment Rodgers/Rowland SciPy ODE model) but is **NOT indexed in
  the routing/tools DB** (`galaxy_ai_tools.db` pbpk tool count = 0). So the router
  has nothing to match.
- **Fix:** index `pbpk_simulation` (and the other `*pbpk*` subworkflows:
  pbpk_pediatric, simcyp_pbpk, pk_sim_pbpk, pbpk_peripheral_nerve, …) into the
  workflow/tools DB so the router can select them. It has sensible param defaults
  (dose_mg, population, fu_plasma) so it runs without a file input once routable.

## 3. Survival routes to a broken virtual workflow
- **Repro:** "Kaplan-Meier survival analysis and Cox …" routes to
  `survival_cox_proportional_hazards_regression`, whose panel shows **no input
  binding and no params** ("此工作流仅接受参数——没有需要绑定的数据输入"), yet the run
  fails immediately.
- **Root cause:** that routed workflow's R reads a hardcoded
  `patient_clinical_data.csv` that is not bundled and cannot be supplied from the UI
  (no input param exposed). It is a generated/virtual name, not a real subworkflow
  dir (only `bioconductor/survival` and `bioconductor/rlassocox` exist on disk).
- **Fix options:** (a) route survival goals to `bioconductor/survival` (which has an
  input binding so the user can supply a clinical-data CSV), or (b) give the
  cox-regression workflow a declared `input_csv` binding, or (c) bundle a demo
  clinical dataset for it. Note BioMate's **data-first policy** (galaxy-assistant.ts:848)
  — do NOT fabricate a built-in demo; supply input via the data library.

## Notes / non-issues
- NCA, survival, FEP require the user's own data by design (data-first). Their
  after-run is produced from uploaded data via the data library, not a built-in demo.
- FEP (`openfe_rbfe`) additionally needs real protein PDB + ligand SDFs + GPU.
