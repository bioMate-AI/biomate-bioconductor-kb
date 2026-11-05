# Deep E2E bug fix-spec

Date: 2026-11-04. Source: the deep (content + logic + code) E2E audit in `20261104_UI_E2E_TEST_PLAN.md`. Every item here is a **confirmed, serious** defect — ranked not "safety vs annoyance" but by *axis of harm*. Each has: symptom, root cause (file:line, current code), recommended fix, who applies it.

Status key: 🔧 in progress (agent) · ✍️ spec-only (needs implementation) · 👤 needs human (production `.nf`).

---

## 1. ADMET DILI → wrong safety gate — *axis: toxicity verdict* — 👤
**Symptom:** for terfenadine (1 compound) the DILI QC gate is recorded **FAILING** though the compound's model DILI is 0.041 (passes). `toxicity.dili_probability=0.672` ("high") vs `per_compound.dili_probability=0.041`.
**Root cause:** `backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/predict_admet_properties/main.nf` — top-level DILI is seeded by a Phase‑1 RDKit logP heuristic `0.55+0.05*(logP−4)` → 0.672; the Phase‑2 ADMET‑AI override (~479‑485) is **asymmetric** (`if>=0.65:high; elif>=0.40 and risk!=high:medium`, **no `else`**) so a low AI DILI never overwrites the stale value. hERG/clintox are overwritten **unconditionally** (hence correct). QC reads the stale aggregate (`main.nf` qc_metrics ~789‑815; executor `nextflow_executor.py` `_extract` ~4741 / `_pass_or_fail` ~4855). Same in `ADMET_pred/main.nf` (~127‑158, 274‑280) + archived copy.
**Fix:** make DILI aggregation unconditional/single-source like hERG — compute the aggregate as the worst over `per_compound_admet` directly (add the `else → "low"`), so aggregate == per-compound for n=1 and all 3 consumers agree. **Production `.nf` (embedded Python) — a human applies + verifies with a live ADMET run.**

## 2. BOIN recommends a dose above its own MTD — *axis: patient-safety verdict* — 👤
**Symptom:** run `c93845cd` computes `true_MTD_dose_mg=20` (40 mg flagged overdosing; 40 mg DLT 0.362 ≥ its 0.325 de-escalation boundary) yet `recommended_Phase2_dose="40 mg QD"`.
**Root cause:** Phase‑2 dose is selected purely by efficacy `P_success` (40 mg = 1.0), ignoring the MTD safety ceiling the same run produced (20 mg had P_success 0.84). The dose-selection step has no safety cap. (Workflow: `clinical_trial_simulation` — locate the Phase‑2-dose selection in its script.)
**Fix:** constrain the Phase‑2 recommendation to doses **≤ MTD** and below the DLT de-escalation boundary; among those, pick the best efficacy (→ 20 mg here). **Production workflow logic — human applies.** (Secondary: the clinical run's `qc_events` uses a "FASTP" gate label — wrong gate mapping for a clinical domain.)

## 3. GEO pseudobulk — meaningless contrasts, no DE output — *axis: scientific correctness* — 👤
**Symptom:** `640b7e9d` contrast = "Public on Jun 10 2010_vs_Public on May 28 2010" (grouped by GEO **publication date**); `863429cf` contrast = "disease state: HNSCC, N+ _vs_ sample type: 15 human cell lines" (two different GEO characteristic **keys**, cross-axis). Both: `geo_scrna_pseudobulk` run on `data_type=microarray`/`pseudobulk_method=none`, **no DESeq2 output despite status "completed"**; gene IDs bare integers, first row all-zeros.
**Fix:** the GEO metadata→contrast parser must pick a real biological variable (not a housekeeping field like publication date, not mix characteristic keys); reject/flag when no valid two-level factor exists instead of emitting a nonsense contrast + "completed" with zero DE output; and the scRNA-pseudobulk path should not accept bulk microarray input. **Workflow/parser logic — human applies.**

## 4. Findings dual-summary contradiction — *axis: core deliverable correctness* — 🔧 (agent)
`findings_data.json` ships two unreconciled liability verdicts (flat `summary` flags hERG+CYP2D6; embedded `findings_document.summary` says "no liabilities"). Root cause: `routes.ts` `_parseAdmetOutput` vs `shared/findings-extract.ts buildFindingsDocument` (the `ADMET_REPORT` descriptor lacks hERG/CYP2D6 metrics), merged at `routes.ts:15806`; also affects the VARIANT descriptor. **Being fixed by a running agent** (single-source / reconcile + extend descriptor).

## 5. Findings — two separate issues (CORRECTED; earlier overstated as "no findings anywhere") — ✍️ / ✍️
**Correction:** findings ARE generated and DO render — ADMET's `findings_data.json` has real content (hERG 0.977, DILI 0.041…) and the UI "AI Findings" card shows it (observed live). The two real, narrower issues are:

**5a — the AI-findings deliverable is essentially unwired platform-wide** (*axis: core deliverable missing almost everywhere*). Surveyed **32 completed runs across 17 workflow types**: only **2** produced a `findings_data.json`, and **both are "Predict ADMET Properties (AI)"** — even that path is only **2/11**. Every other workflow produced **zero**: `clinical_trial_simulation`, `in_vivo_cart_codesign`, `Herg Cardiac Safety Qsar`, `Qsar Rf Model`, `survival` / `survival_cox_proportional_hazards`, `Blast Sequence`, `Analyze Calcium Imaging Data`, `Analyze Protease Kinetics`, `Annotate Celltype With Panhumanpy`, `analyze_fda_safety_signals`, `get_fda_drug_label_info`, `Adaptation retrain`, the non-AI `Predict Admet Properties`, nf-core/differentialabundance, etc. → **~94% of completed runs have no findings narrative at all.** The deterministic findings parsers in `routes.ts` (`_parseAdmetOutput`, `_parseDeseq2Output`, `_parseEnrichGoOutput`, `_parseRarediseaseOutput`) exist but evidently only the AI-ADMET completion path actually invokes findings generation + writes the sidecar — and inconsistently. **Fix:** make findings generation a general post-completion step that runs for every workflow (route each workflow's outputs to a parser or an LLM summarizer), and make it reliable for ADMET (2/11 → should be 11/11). This is the headline "AI findings" capability being absent for nearly the whole platform — high priority. Needs a human/product decision on the generation path (deterministic-per-domain vs a generic LLM summarizer over any run's outputs).

**5b — `inline_findings` run-record field is always `[]`, even for ADMET** (*axis: vestigial/unpopulated API field — NOT the cause of an empty Findings tab*). `frontend/server/routes.ts:12478` sets `inline_findings: ns.findings || ns.ai_findings || ns.key_results || []`, and nothing populates `ns.findings` from `findings_data.json`. The main UI Findings display reads the `findings_data.json` file, not this field, so the empty field does **not** blank the Findings tab — it only affects a consumer that reads `inline_findings` directly (API clients, findings-search). **Fix (Node-side):** populate it from `findings_data.json` at completion so the run-record field matches what the UI shows; LOW urgency vs 5a.

## 6. `run.metrics` all-zero — *axis: billing / accounting integrity* — ✍️
**Symptom:** `metrics` (runtime.totalSeconds, resources.peakMemoryGB/avgCpuPercent/diskUsedGB, outputs.fileCount/totalSizeBytes) is **all zero on every run** despite real output files and real runtime; usage/billing attribution from this block reads zero.
**Root cause:** `frontend/server/storage.ts:431` initializes `metrics` to all-zero and **no code ever updates it** with the completed run's real values (no non-zero writer exists).
**Fix (Node-side, implementable):** on completion, populate `outputs.fileCount`/`totalSizeBytes`/`byType` from the run's `output_files`, and `runtime`/`resources` from the Nextflow trace (the executor has the trace/`.nextflow.log`; surface the figures to the Node record, or compute fileCount/size Node-side immediately and backfill runtime/resources from the trace). At minimum fileCount/size are trivially derivable and should never be zero for a run with outputs.

## 7. Dead / mock-as-real UI — *axis: data-integrity + "does the button work"* — 🔧 (agent)
Projects page shows fabricated demo projects as the user's real ones; Starred Workflows + Recent Tools serve hardcoded demo data with no-op Run/View/Star/CTA buttons. **Being fixed by a running agent** (honest empty-states, wire or remove no-op controls). A CI guard `__wiring__/wiring-contracts.test.ts` exists for this class and should gain contracts for these.

---

## Ownership summary
- **Human-applied (production `.nf`/workflow logic):** #1 ADMET DILI, #2 BOIN dose, #3 GEO contrast. These change executed workflow reduce/selection logic and must be verified with live runs.
- **In progress (agents, frontend-safe):** #4 findings contradiction, #7 dead/mock UI.
- **To implement next (Node-side, frontend-safe):** #5 inline_findings population, #6 run.metrics population — after the running agents land and worktree disk frees. Both are "wire the real data the run already produced into the run record."
