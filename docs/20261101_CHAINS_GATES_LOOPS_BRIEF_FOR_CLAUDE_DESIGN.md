# Chains, human gates and loops — a brief for Claude Design (design and tutorial demo first)

**Date:** 2026-11-01. **For:** Claude Design. **Companion docs:** `20261101_ORCHESTRATION_OVERVIEW_AND_UNIFICATION.md`,
`20261101_USE_CASE_SURVEY_PROPOSE_MEASURE_PLAN.md`, and the earlier briefs `20261023_UI_DESIGN_PROBLEMS_FOR_CLAUDE_DESIGN.md`,
`20261023_CAPABILITY_DEMOS_INFOFLOW_FOR_CLAUDE_DESIGN.md`.

## 0. Why design comes first, and what it blocks
Backend slices S1-S5 (corpus tests, command interface, step registry, capability steps in chains, new steps) do not need a design and proceed in
parallel. **Slice S6 (human gates and review screens) and S7 (`orchestrate` tool) do**: a gate is the one place the person decides, so its layout, evidence
and wording must be designed before it is built. A tutorial demo made from the design then serves as the acceptance reference for S6.

## 0.1 The chains that exist today (from `workflow_chains` in `backend/database/galaxy_ai_tools.db`, read 2026-11-01)
69 defined chains: 63 curated, 6 `bioc_reactive`; 17 domains. By domain: drug_discovery 18, transcriptomics 15, single_cell 7, epigenomics 5, genomics 5,
variant_calling 4, pharmacology 3, population_genetics 3, and one each in cryo_em, immuno_oncology, immunology, metabolomics, metagenomics, multi_omics,
proteomics, rare_disease, structural_biology. Length is 1 to 7 workflows. Each step carries `order`, `workflow_name` / `workflow_id`, `nextflow_path`, `role`,
`params_template`; the `connections` list wires an output of one step to an input of another, so chains are DAGs (fan-in exists), not only straight lines.
- Drug development (18): e.g. `target_to_lead_full` (pocket detection -> pharmacophore filtering -> ADMET triage -> docking -> GROMACS MM-GBSA -> REINVENT4 lead design,
  fan-in at docking), `drug_discovery_admet_gated_screening` (pharmacophore -> ADMET -> docking), `andv_inhibitor_track_v1` (6 steps, aligned with the research campaign CLI),
  `cyp450_ddi_chain`, `admet_to_cipa_cardiac`, `pbpk_to_tumor_tgi`, `target_discovery_full`, `rnaseq_to_lincs_moa`.
- Multi-modal: `rare_disease_multimodal_workup` (sarek -> VEP; rnaseq -> DROP; both feed case_report_aggregation), `multi_omics_mofa_chain`, `single_cell_multimodal_analysis`.
- Routine analysis: `bulk_rnaseq_de_analysis`, `bioc_bulk_rnaseq_de_v2`, `scrna_pseudobulk_de_bioc` (7 steps), `methylation_450k_array_analysis`.
Facts that matter for design: (1) the chain definition has **no gate or approval field**: today's approvals live in the executor and the workflow panel, not in the chain; (2) steps can only
be workflows, not capability steps; (3) **no tutorial names any of these chains** (0 of 69 chain identifiers appear in the tutorial files; T11 and M3 show similar pipelines, not by chain id).

## 1. Governing principle (unchanged): no custom UI per use case
Design the finite set of **primitives and patterns**; the harness and model compose a response from them for each run. The three exemplars in §3 show
primitives used well; they are not templates. The existing design reference, workflow panel and tokens remain the style source.

## 2. Primitives requested (the finite part)
| Primitive | Purpose | States to design |
|---|---|---|
| **Plan view** | Shows a chain/plan as a DAG: steps (workflow or capability), dependencies, which are fan-outs, which are gates | draft, running, waiting for you, complete, failed, skipped; fan-out collapsed ("38 of 120 papers read") and expanded |
| **Step card** | One step: name, kind, inputs, outputs, status, cost so far, provenance link | idle, running, done, `unsupported`, `unverified`, failed |
| **Gate card** | The place a person decides. Shows the decision asked, the evidence behind it, the options, the consequence of each, and what happens if ignored | `approve` (blocks), `review` (does not block), decided, expired |
| **Estimate dialog** | Before spend or compute above a threshold: items, count, estimated cost and time, what will be skipped on decline | accept, reduce scope, decline |
| **Evidence table with claim status** | Rows of extracted claims, each with source, verbatim quote, verified / unsupported / rejected-by-reviewer, and include/exclude controls | filter, sort, bulk exclude, expand quote in source |
| **Proposal editor** | A study proposal whose every element is linked to evidence or marked an assumption the person must accept | evidence-linked, assumption (needs accept), edited, accepted |
| **Loop strip** | A repeating plan (a campaign): rounds as a timeline, the gate cadence, the stopping rule, current round state | waiting for lab data, awaiting approval, converged, stopped |
| **Handoff card** | Outward-facing action (CRO order, synthesis request): what leaves, to whom, irreversible warning | draft, approved, sent, confirmed |

## 3. Four exemplars to design and to demo (data, not templates)
1. **Survey, propose, measure** (plan in `20261101_USE_CASE_SURVEY_PROPOSE_MEASURE_PLAN.md`): gates H1-H7. Key moments: reviewing the evidence table (H2), choosing a gap (H3),
   accepting assumptions in the proposal (H4), approving data and cost (H5), go / revise / stop on a weak pilot (H6).
2. **`target_to_lead_full`** (real chain, 6 steps with fan-in at docking) with a blocked QC gate at the ADMET triage: approve the target and compound set, review the blocked gate, approve the shortlist before lead design.
3. **`rare_disease_multimodal_workup`** (real chain, two parallel branches that join in case_report_aggregation): the plan view for a DAG with fan-in, a failed branch, and sign-off of the report.
4. **Campaign round** (DMTA): approve the proposed batch, the CRO order handoff (irreversible), wait for assay data, review outliers, approve continue / stop.

## 4. Information each gate must show (quality bar)
The decision asked in one sentence; the evidence (citations, counts, claim status, numbers linked to source); what each option does next; cost and time if any;
what the system did automatically up to here; and honest status for anything unverified. No bare predicted numbers; no claim without its source; no wording that
nudges the person toward an option.

## 5. Tutorial demo (after the design)
Auto-playing HTML capture, English and Chinese, in the established tutorial pipeline (background first, then the steps). Storyboard for the first demo:
1. State the topic and the question; scope confirmation (H1). 2. The survey fills in: fan-out counter, claims arriving with verified quotes. 3. Evidence table review (H2).
4. Gap choice (H3) with evidence. 5. Proposal with assumptions marked (H4). 6. Public data found; estimate dialog (H5). 7. Pilot result and the go / revise / stop decision (H6).
8. Plan and report ready; sign-off (H7). Every figure in the demo must come from a real run on public data (the ClinicalTrials.gov mirror and the switch-like test are available); no invented numbers.

## 6. Questions for Design
- Plan view at 100+ fan-out items: aggregate by status and drill down, or sample? - How does a blocked `approve` gate differ visually from a non-blocking `review`?
- How is irreversible (handoff) distinguished from reversible approval? - Where do the gates live relative to chat and the right-hand panel?
- How are Chinese and English evidence quotes shown side by side without implying a translation is the source?

## 7. Source index
Overview and plan docs above; `docs/20260601_CHAIN_FRAMEWORK_AUDIT_AND_FIX.md` (approve-each-step); `nextflow-workflow-viewer.tsx` (current panel, QC gate);
`backend/lib/galaxy/ai/drug_discovery/api_router.py` (campaign routes); `backend/lib/galaxy/ai/corpus_fs/llm_map.py` (claim status).
