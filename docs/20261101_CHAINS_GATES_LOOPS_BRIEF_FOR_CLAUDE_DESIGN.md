# Chains, human gates and loops — a brief for Claude Design (design and tutorial demo first)

**Date:** 2026-11-01. **For:** Claude Design. **Companion docs:** `20261101_ORCHESTRATION_OVERVIEW_AND_UNIFICATION.md`,
`20261101_USE_CASE_SURVEY_PROPOSE_MEASURE_PLAN.md`, and the earlier briefs `20261023_UI_DESIGN_PROBLEMS_FOR_CLAUDE_DESIGN.md`,
`20261023_CAPABILITY_DEMOS_INFOFLOW_FOR_CLAUDE_DESIGN.md`.

## 0. Why design comes first, and what it blocks
Backend slices S1-S5 (corpus tests, command interface, step registry, capability steps in chains, new steps) do not need a design and proceed in
parallel. **Slice S6 (human gates and review screens) and S7 (`orchestrate` tool) do**: a gate is the one place the person decides, so its layout, evidence
and wording must be designed before it is built. A tutorial demo made from the design then serves as the acceptance reference for S6.

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

## 3. Three exemplars to design and to demo (data, not templates)
1. **Survey, propose, measure** (plan in `20261101_USE_CASE_SURVEY_PROPOSE_MEASURE_PLAN.md`): gates H1-H7. Key moments: reviewing the evidence table (H2), choosing a gap (H3),
   accepting assumptions in the proposal (H4), approving data and cost (H5), go / revise / stop on a weak pilot (H6).
2. **Screening chain with a blocked QC gate** (ADMET, docking, binding): approve the compound set, review the blocked gate, approve the shortlist.
3. **Campaign round** (DMTA): approve the proposed batch, the CRO order handoff (irreversible), wait for assay data, review outliers, approve continue / stop.

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
