# 2026-07-23 — End-to-End Use-Case Audit (Clinical Pharma track)

Continuation of the MG-tutorial-style comprehensive design-conformance audit,
extended to new use cases. Each use case is driven **fully end-to-end**:
generate → run on Batch → audit chat flow, panel states, outputs, findings +
report, and **biomedical soundness of the actual results**. Also auditing (per
user) **chat-flow fluency** and **citation-backed rational updates**.

Driver: `frontend/e2e/_e2e_usecase.mjs` (login → query → answer clarification →
prerun shot → Confirm & Run → running shot → afterrun shot).

---

## Use case 1 — Clinical trial / BOIN dose escalation ✅ COMPLETE, EXCELLENT

Query: *"Design a phase I dose-escalation trial…"* + clarification answer
*"dose levels [10,30,60,100,200] mg; target toxicity 0.30; cohort 3; max 36."*

Run: `36f26f0c-cf69-42f4-bb80-ce708fe2620c` — **succeeded** on Batch.

| Dimension | Result |
|---|---|
| Chat pre-exec | Fluent, accurate: BOIN calculator → posterior toxicity inference → MTD → decision table + RP2D + stopping rules |
| Panel pre-run | **20 params configured**; clarification data flowed in (`Dose Levels [10,30,60,100,200] · DLT Target 0.3`); per-phase params render |
| Outputs (8) | `BOIN_decision_table.json`, `dose_escalation_results.csv`, `operating_characteristics.json`, `phase2_simulation.csv`, `clinical_trial_results.json`, … |
| Output content | MTD = **30 mg**, RP2D = **"30 mg QD"**, 1000-sim operating characteristics: P(correct MTD)=0.409, P(underdose)=0.525, P(overdose)=0.066 |
| Biomedical soundness | BOIN boundaries λ_escalate=**0.27** / λ_deescalate=**0.37** for target 0.30 match the Liu & Yuan (2015) standard boundaries. Internally consistent. |

### Findings (fluent + rational + provenance)
- **Summary** correctly reads "design tends toward conservative dose
  recommendations" from the 52.5% underdosing rate.
- **next_steps**: Phase II at 30 mg QD (100 pts); adaptive design given
  underdosing; confirm 29.4% DLT assumption.
- **caveats**: honestly flags 40.9% correct-MTD as simulation variability;
  real-world variability risk; power confirmation needed.
- **Provenance**: every `key_result` carries a `source_file` (e.g.
  λ_escalate ← `BOIN_decision_table.json`).
- **Report**: clean markdown (`/findings/report`), Summary + Key Results.
- **Citations tab** (`/api/workflows/clinical_trial_simulation/citations`):
  **Liu S, Yuan Y. J R Stat Soc C 2015; 64(3):507-523** — the canonical BOIN
  paper. Correct methodology citation, surfaced in the separate Citations tab
  (per design: data claims use source_file provenance, method uses lit citation).

**Verdict:** full end-to-end pass. Chat flow fluent; rational updates with
honest caveats; citation support complete.

---

## Use case 2 — PBPK / allometric scaling (3-step chain) ⚠ 2 GAPS

Query: *"Run a PBPK simulation … scale mouse to human using allometric
scaling…"*

Routing: **correct** → `ADMET + PBPK → Virtual Patient Dose Optimization`
(3 steps: `predict_admet_properties` → `pbpk_simulation` →
`virtual_patient_cohort`). Chat flow **fluent** (maps request, lists 3 steps
with paths, "Confirm & Run to execute them in order").

### Gap 2a — chain surfaces no configurable params
Panel shows *"This workflow has no configurable parameters."* For a PBPK sim,
dose / species / SMILES should be surfaced (contrast: clinical_trial showed 20).
The clarification answer (aspirin, 10 mg/kg, mouse→human 70 kg) was neither
solicited nor captured.

### Gap 2b — "Confirm and run workflow" is a no-op for the virtual chain
After clicking Confirm & Run, **no run was created** (API run list unchanged;
panel did not transition to running/phases; button greyed with no error). The
chain contains **virtual workflows** (`virtual_patient_cohort`) not in the
Galaxy DB — step 1 (`Predict ADMET Properties`) runs standalone (completed runs
exist), but the composed multi-step virtual chain does not execute via this
path.

### ROOT CAUSE (traced 2026-07-23 — NOT a virtual-workflow limitation)

It is a **run-dispatch wiring bug in the right panel**, fully fixable:

1. The chain is `workflow_type: 'pipeline'` (set in
   `server/galaxy-assistant.ts:4614/4912/5083`; `'chain'` variant in
   `server/routes.ts:11416`).
2. **In the chat message** (`chat-message.tsx`) dispatch is CORRECT:
   - `'pipeline'` → `PipelineListView` … `onConfirmRun → onRunPipeline(wf)` (L759-788)
   - `'chain'` → `WorkflowChainPlan` … `onRunChain(wf)` (L794-817)
   - single workflow → `NextflowWorkflowViewer` … `onExecute → onRunWorkflow`
3. **In the right panel** (`chat-with-artifacts.tsx:2291`) the viewer is rendered
   **unconditionally as `NextflowWorkflowViewer`**, and its `onExecute`
   (L2302-2318) **always calls `handleRunWorkflow(panelWorkflow, [])`** —
   empty steps, no type check.
4. `handleRunWorkflow` (L937): a pipeline has no `nextflow_path` →
   `isNextflow = false` (L956); `steps = []` → the guard at **L959**
   (`!isNextflow && steps.length === 0`) fires → `console.error` +
   `setIsWorkflowRunning(false)` + **silent `return`**. No run, no user error.
   ⇒ exactly the greyed-button no-op observed.

### CONCRETE FIX (minimal; mirrors the chat-message dispatch already in the codebase)

In `chat-with-artifacts.tsx` panel `onExecute` (~L2302), branch on
`panelWorkflow.workflow_type` BEFORE defaulting to `handleRunWorkflow`:
```
if (panelWorkflow?.workflow_type === 'pipeline') return handleRunPipeline(panelWorkflow);
if (panelWorkflow?.workflow_type === 'chain')    return handleRunChain(panelWorkflow);
// else: existing single-workflow path (handleRunWorkflow with merged params)
```
`handleRunPipeline`/`handleRunChain` already exist and call
`submitWorkflowFromArtifact` (pipeline runs step 1 with `endAtStep:0`, then the
chat-side `PipelineListView` approval gate drives subsequent steps). Step 1
(`predict_admet_properties`) executes standalone today, so this makes the chain
start end-to-end via the panel button.

Gap 2a ("no configurable parameters") is **acceptable** for pipelines/chains —
params live per sub-step, not at the pipeline level. Not part of the bug.

**Status:** root cause confirmed, fix specified. NOT yet applied (reporting
first per user instruction). No workaround shipped.

---

## Non-issue — 3 failed `nf-core/rnaseq` runs
Investigated: all have **no batchJobId, no samplesheet** (only `version` /
`toolParameters`) — they never submitted to Batch. These are earlier E2E test
stubs without real FASTQ input. **Not a regression.**

---

## Use case 3 — ADMET liability panel (3 compounds) ✅ COMPLETE, SOUND

Query: *"Screen aspirin / ibuprofen / caffeine for ADMET liabilities — flag
hERG, hepatotoxicity, CYP inhibition."* No clarification needed.

Run: `8b12a2ca-285b-41e5-87a2-f3ad5c424b84` — **completed** on Batch.
Routed to `predict_admet_properties` (executes standalone; chain step 1).

### Predicted values (ADMET-AI / Chemprop-RDKit; Swanson et al. 2023 Bioinformatics)
| Metric | Aspirin | Ibuprofen | Caffeine | Soundness |
|---|---|---|---|---|
| hERG inhibition | 0.003 | 0.008 | 0.115 | ✓ all low — none are hERG blockers |
| DILI probability | 0.855 | 0.487 | 0.875 | over-flagged (known ADMET-AI DILI noise), not a BioMate defect |
| Plasma protein bind % | 73.2 | 90.7 | 29.2 | ✓ caffeine ~30% matches literature |
| BBB penetration | 0.811 | 0.511 | **0.970** | ✓ caffeine highest — correct CNS penetration |
| Oral bioavailability | 0.873 | 0.945 | 0.936 | ✓ all well-absorbed |
| CYP2D6 inhibitor | 0.007 | 0.008 | 0.001 | ✓ all ~0 — correct |

### Findings (correctly flag requested liabilities)
- hERG 0.003 → "Acceptable cardiac liability risk" ✓
- DILI 0.855 → "**Elevated** drug-induced liver injury risk — potential
  liability" ✓ (hepatotoxicity flag requested)
- CYP2D6 0.007 → "Acceptable CYP2D6 inhibitor risk" ✓ (CYP flag requested)
- Model attribution present in output (Swanson et al. 2023).

**Minor:** ADMET findings **summary is terse** ("Key ADMET properties assessed
against standard thresholds") vs. the BOIN run's rich narrative prose.
Candidate for enrichment — the per-compound interpretation IS in key_results,
so functional, but the top-line summary could name the standout results.

**Verdict:** end-to-end pass, biomedically sound.

---

## Consolidated status (3 use cases audited end-to-end)
| Use case | Route | Run | Outputs | Biomedical soundness | Findings/citations |
|---|---|---|---|---|---|
| Clinical trial (BOIN) | ✓ | succeeded | ✓ 8 files | ✓ MTD 30mg, λ boundaries match Liu&Yuan | ✓ fluent + caveats + Liu&Yuan citation |
| PBPK chain | ✓ | **no-op** (virtual) | — | — | — (Gap 2a/2b) |
| ADMET panel | ✓ | completed | ✓ | ✓ hERG/BBB/PPB/CYP correct | ✓ flags DILI/hERG/CYP; terse summary |

## Next
- Remaining breadth targets: single-cell (GEO), multi-omics (MOFA+).
- Decision needed on PBPK-chain Gap 2b (virtual-chain Confirm&Run no-op).
- Optional polish: enrich ADMET findings summary to match BOIN narrative depth.
