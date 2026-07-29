# Requirement — Claude-Design Tutorial Demo: Multi-Omics Integration Benchmarking

**Date:** 2026-07-28
**For:** the Claude-design tutorial pipeline (style/format = `reference/claude_design/
tutorials-work/clips/tut_mg_stratification/`; visual standard = reference design at
`http://localhost:7779`).
**Owner of the science:** see `docs/20260728_MULTIOMICS_FINDING_AND_COMPETITIVE_
REASSESSMENT.md` and `docs/20260727_MULTIOMICS_BENCHMARK_DESIGN.md`. **Every claim in
the demo MUST trace to those docs + a real run ID.**

---

## 0. Readiness gate (READ FIRST)
This requirement covers the **capability tutorial** (a real user journey through
BioMate), which is demonstrable NOW on the CLL cohort. It is **NOT** the manuscript.
The manuscript/preprint has a separate, higher bar (multi-cohort generalization; see §7)
and MUST NOT ship until Track B (TCGA) lands. The tutorial may show the *method*; it may
NOT assert the *generalized scientific finding* as settled.

---

## 1. Purpose & audience
- **Purpose:** show that BioMate uniquely runs a user's *own* multi-omics data through
  *multiple* integration methods with a **fair, ground-truth-scored head-to-head**, and
  surfaces a real, mechanistic insight — reproducibly, in plain English.
- **Audience:** computational biologists, translational/pharma multi-omics users, and
  reviewers evaluating the platform.
- **One-sentence takeaway the viewer should leave with:** *"There is no universal-best
  integration method; which one to trust is data- and method-dependent and not
  predictable a-priori — so you must benchmark, and BioMate is the platform that does it
  for you."*

## 2. Format
- **Medium:** narrated screen-capture clip (like `tut_mg_stratification`), 2–4 min, plus
  an ending slide (reuse `tutorials-work/make_ending_slide.py` pattern).
- **Resolution / framing:** match the reference design; capture the real app UI (chat
  left panel + workflow panel right), not mockups.
- **No mocked data or fabricated screens.** Every screen is a real run (§6 provides run
  IDs). If a state must be re-captured, re-run through the platform.

## 3. Storyline (the honest narrative, in order)
1. **Hook — the problem.** Multi-omics integration has no consensus winner; the method
   you pick changes which biology you recover. (1 slide.)
2. **Plain-English upload.** User describes CLL multi-omics (drugs, methylation, mRNA,
   mutations; 200 patients) in chat → BioMate routes to the multi-omics workflows.
3. **Normalize + QC.** Run `omics_normalize`; show the QC table **before vs after**
   (per-omic skew/sd corrected; NAs preserved) — the fairness step.
4. **Run two methods, same interface.** MOFA2 and SNF, identical inputs, through AWS
   Batch — show idle → running → completed states in the workflow panel.
5. **Fair head-to-head, scored on ground truth.** IGHV status held out as label;
   scorecard from `scripts/multiomics_metric_harness.py`:
   MOFA2 Factor-1 **AUC 0.968**; SNF **ARI 0.375–0.55**. MOFA2 exposes IGHV as one
   interpretable factor; SNF as a hard partition.
6. **The mechanistic insight (labeled as a pilot finding, not settled law).** Add a
   noisy/degenerate modality → **SNF degrades** (mutations −0.18 ARI *even though it
   contains the label*; pure noise −0.057) while **MOFA2 stays flat** (ARD down-weights
   the bad view 40×). *Robustness is a property of the method's view-weighting.*
7. **Takeaway.** You can't tell a-priori which modality/method wins → benchmark it.
   BioMate = the reproducible head-to-head, every run re-executable.

## 4. Required screens / states (each must appear, captured live)
- [ ] Chat: NL request → BioMate response with correct workflow name + structured
      pre-execution summary + workflow card (no "undefined", per the Chat Presentation
      Standard in CLAUDE.md).
- [ ] `omics_normalize` QC table (before/after) rendered in the outputs/findings panel.
- [ ] MOFA2 workflow panel: idle → running (≥1 phase spinner) → completed ("Run again").
- [ ] SNF workflow panel: same lifecycle.
- [ ] Head-to-head scorecard (MOFA2 vs SNF, the real numbers) — a comparison figure.
- [ ] The 2×2 finding visual (SNF vs MOFA2 × baseline/+noise) — bar or slope chart.
- [ ] Findings tab: summary paragraph with **actual values**, Download-report button.

## 5. Claims policy (HONESTY GUARDRAILS — non-negotiable)
**ALLOWED (backed by data + run IDs):**
- The measured numbers only: MOFA2 AUC 0.968 / matched-k3 ARI 0.526; SNF ARI 0.375
  (4 views) / 0.553 (3 views); normalization QC deltas; noise −0.057; mutations −0.18;
  ARD per-view |loading| (mrna/meth ~0.12 vs noise 0.003).
- "Method-dependent robustness to uninformative modalities" (2×2 + ARD proof).
- "Modality value is not predictable from cheap per-view metrics → benchmark it."
- "Runs your own data through many methods with a shared normalization + one metric
  harness, reproducibly."

**FORBIDDEN (would be false / unsupported — do NOT say or imply):**
- ❌ "BioMate predicts the best method/modality a-priori." (The standalone-alignment and
  affinity-quality predictors were **tested and REFUTED**; r≈0.)
- ❌ "First / only / novel platform for LLM multi-omics." (OmniBioAI, OmicOS, OmicsNavigator,
  OMICX, CEPICS exist — see the reassessment doc.)
- ❌ "MOFA2 is universally better than SNF." (It's mechanism-dependent, one cohort.)
- ❌ Any cross-cohort / generalization claim until TCGA lands (§7).
- ❌ Any number without a traceable run ID.
- ❌ Fabricated screens, mocked SSE, or invented DOIs.

## 6. Data & provenance (real run IDs to capture from)
- **CLL cohort:** `s3://biomate-nextflow-work/cll_test/` (drugs/methylation/mrna/mutations,
  200 patients; IGHV in mutations).
- **MOFA2 (4 views):** run `bfa3fb42`/`6517aaf4` (AUC 0.968). **SNF (4 views):** `fc3b1719`
  (ARI 0.375). **Normalize:** `a0f1138f`. **2×2:** SNF base `bd351c4b`, +noise `d6dbc925`;
  MOFA2 base `f45e29d4`, +noise `e06888b3`. **SNF LOO:** `f8e1ef4d`/`e5e6c018`/`9f52da92`.
- Scorecards reproducible via `scripts/multiomics_metric_harness.py`.

## 7. Manuscript / preprint / blog track (separate, gated — do NOT start the write-up
until these hold)
1. **Generalization** — reproduce the 2×2 on ≥2 TCGA cohorts (BRCA PAM50, GBM Verhaak,
   AML cyto-risk via the Rappoport & Shamir 2018 benchmark). The tutorial can add these
   as a "and it holds on TCGA" beat *once real*.
2. **≥1 more weighting mechanism** (intNMF / iClusterPlus / DIABLO) so the claim is
   "view-weighting mechanism," not "MOFA vs SNF."
3. Only then: preprint (bioRxiv) framed as *platform + honest finding*, blog (link the
   reproducible runs), and this tutorial as the embedded demo.

## 8. Deliverables from the Claude-design pipeline
1. Storyboard (screen-by-screen, mapped to §3–§4).
2. Live screen recordings per required state (§4), captured from real runs (§6).
3. Narration script honoring §5 (claims policy) verbatim in spirit.
4. Final edited 2–4 min clip + ending slide.
5. A stills set (the scorecard + 2×2 figure) reusable in the blog/preprint.

**Sign-off check before publishing the clip:** re-read §5; confirm no forbidden claim
appears in narration, on-screen text, or title; confirm every number maps to a §6 run ID.
