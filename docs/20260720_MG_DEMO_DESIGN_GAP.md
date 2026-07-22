# MG Demo — Design Gap Analysis (2026-07-20)

Reference design: `reference/claude_design/tutorials-work/research-agent-ui-latest-2/` (DD01 / DD02)
Live system: dev-public.biomate.ai, E2E test `frontend/e2e/test_mg_demo_v2.mjs`

---

## 1. Functional bugs found in today's E2E run

| # | Bug | Symptom | Location |
|---|-----|---------|----------|
| B1 | Panel state not reset when new workflow loaded | After DESeq2 FAILED, panel showed `clusterprofiler` header but still "FAILED" badge + "Restart" footer. `clickRun` timed out looking for "Confirm & Run" — Turn 2 and Turn 3 never executed. | `nextflow-workflow-viewer.tsx` — run state not cleared on new workflow push |
| B2 | DESeq2 samplesheet not constructed | `nf-core/differentialabundance` failed immediately: `Input samplesheet not specified!`. Uploaded `counts_matrix.csv` + `sample_metadata.csv` were attached in chat but the `--input` samplesheet param (nf-core format) was never assembled or filled. | Parameter prefill pipeline / `galaxy-assistant.ts` Step 5 |
| B3 | clusterProfiler domain badge wrong | Panel shows "GENOMICS · WORKFLOW" for clusterprofiler; should be "TRANSCRIPTOMICS". | Workflow DB record for `clusterprofiler` has wrong domain |

---

## 2. UX gaps vs. DD01/DD02 design

| Gap | Design expects | Current behaviour |
|-----|---------------|-------------------|
| Progressive panel reveal | DD01: panel grows one phase per turn — Phase A after Turn 1, Phase B after user agrees to enrichGO, Phase C after ADMET suggested. `progressiveReveal: true`. | Panel is replaced wholesale each turn; no cumulative reveal. |
| Proactive next-step suggestion | After DESeq2 result, BioMate suggests "shall we run pathway enrichment?" without user asking. User just says "yes". | User must explicitly request enrichGO (Turn 2 message). BioMate does not proactively propose. |
| ChEMBL SMILES resolution | BioMate looks up iptacopan → CHEMBL4594448 → canonical SMILES itself. User says "screen iptacopan", never pastes SMILES. | Test (and presumably demo) requires user to paste SMILES string. |
| Speaker pills in chat | Every AI line carries a typed pill: WF (blue), QC (amber), FIND (green), AGENT (teal), LOOP (purple), PLAN (grey). | No pills. All AI messages are plain text with no speaker type distinction. |
| Plan checklist | Sticky strip above chat showing DESeq2 → enrichGO → ADMET items with live status (pending/running/done/warn). | No plan checklist. |
| (why?) rationale tooltip | Each AI chat line with `rationaleId` shows a hoverable "(why?)" anchor linking to RESEARCH_PHASE_TRACE. | No why? tooltips anywhere. |
| Two agent steps before ADMET | Target selection (CFD→CFB judgment) + knowledge search (CFB→iptacopan via Open Targets) are two separate AGENT beats with citations. | Collapsed into one suggestion line. |

---

## 3. Style gaps

| Gap | Design | Current |
|-----|--------|---------|
| CSS design tokens | `tokens.css` defines `--accent oklch(0.55 0.14 245)`, cool-leaning neutrals with oklch, `--shadow-md`, tight letter-spacing `-0.005em`. | Tailwind-based; tokens not fully aligned with the reference system. |
| Speaker pill colors | 6 named colors: `--bm-wf` blue, `--bm-qc` amber, `--bm-loop` purple, `--bm-agent` teal, `--bm-find` green, `--bm-plan` grey (+ dark-mode variants). | Not implemented. |
| After-run report | 7 tabs: Findings · Outputs · Methods · Parameters · Software · Citations · QC audit. Report grows turn-by-turn in DD01 (`progressiveReveal`). | 4 tabs: Outputs · Findings · QC report · Parameters. Software and Citations missing. Report appears only on full completion. |
| Findings tab on failed run | Static: "Findings analysis requires readable output files." No spinner. | Currently shows misleading "nf-core/differentialabundance completed. Output files are not yet readable — check Outputs tab." |

---

## 4. What's working correctly

- Login (API token pattern) ✅
- MG chip on home page fills Turn 1 message only (no ADMET/SMILES bleed) ✅
- Turn 1 routes to `nf-core/differentialabundance` ✅
- Turn 2 routes to `clusterprofiler` (Step 6c fix holding) ✅
- Turn 3 routes to "Predict ADMET Properties (AI)" ✅
- Workflow chip appears in chat for all 3 turns ✅
- No "undefined" text in chat messages ✅
- Download button visible in After Run even for failed runs ✅

---

## Priority order for conference (July 21-23)

1. **B1** — Panel state reset (blocks Run on Turns 2+3; hardest visible demo failure)
2. **B2** — DESeq2 samplesheet prefill (Turn 1 execution)
3. Speaker pills (highest visual impact for conference impression)
4. **B3** — clusterProfiler domain badge
5. Proactive next-step suggestion (requires backend logic; likely post-conference)
