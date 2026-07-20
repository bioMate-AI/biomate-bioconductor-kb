# BioMate Case-Study Webinar Series — Schedule & Readiness Plan

**Series start:** Friday **2026-07-24** · weekly, Fridays · **Cadence:** 1 webinar/week
**Sequencing logic:** readiness first (webinars whose numbers are already measured lead), strategic pull second, and a **prep gate** so any "one-run-away" case has its benchmark executed *before* its slot.

Readiness key: **A** = finished, real numbers ready · **B** = one run from ready (prep gate noted) · **C** = roadmap/vision.

---

## Schedule

| # | Date (Fri) | Webinar | Case study | Ready | Lead metrics to show | Primary audience | Prep gate (must finish before slot) |
|---|---|---|---|---|---|---|---|
| 1 | **2026-07-24** | From Structure to IND in an Afternoon | 01 Drug-discovery pipeline | A | AUROC 0.93 vs ADMET-AI; CiPA FP 58→8%; EMA-qualified PBPK; 96.4% auto-loop | Pharma / biotech discovery + reg | Slides only — evidence ready |
| 2 | **2026-07-31** | Cryo-EM Structures at 1/33rd the Cost | 02 Cryo-EM SPA | A | 1.78 Å Nyquist; 2.8 GPU-h; $27 vs $900; zero false halts | Structural biology / core facilities | Reconcile metrics.json 5.46 Å vs 1.78 Å note |
| 3 | **2026-08-07** | A Validated Workflow for Every Patient Cohort | 03 Clinical PBPK cohorts | A | EMA 2-fold (100% AUC); semaglutide vs SUSTAIN-1; 8+ populations | Clinical pharmacology / DMPK | Resolve PopPK/nlmixr2 status note |
| 4 | **2026-08-14** | More Accurate Than a Frontier AI | 05 Retrieval + 07 Agentic eval | A/B | 100% P@1 vs Claude 85.2%; BixBench 48% vs 29.2% | Platform / data-science leads; investors | Run full BixBench 296 (upgrade 07 to A) |
| 5 | **2026-08-21** | The Pipeline That Fixes Its Own Failures | 04 QC governance + 10 AutoFix | B | 96.4% auto-loop; audit 1.0 vs 0.0; AutoFix 19 fixers | Compliance / regulated labs | **Run QC-governance AWS benchmark (~$500) + AutoFix 20-case benchmark** |
| 6 | **2026-08-28** | What You Can't Run Locally | 06 Speedup + 09 Foldseek | B | cache 10³–10⁴×; cryo 3.4×; Foldseek 214M-structure search | Platform / infra buyers | **Measure ADMET fan-out on Batch; build full Foldseek index** |
| 7 | **2026-09-04** | Reproduce Any Published Method | 08 Paper-to-workflow | B | Hit@5 = 1.00; 2–8 h → seconds | Academic / repro-focused labs | Wire + measure dense+LLM re-rank |
| 8 | **2026-09-11** | The Autoimmune & Multi-Omics Roadmap | Roadmap tier (C1–C3) | C | Gold standards + planned targets (framed as vision) | Strategic partners / investors | Label clearly as roadmap; no unmeasured claims as fact |

---

## Prep gate → measurement backlog (do these before their webinar)

| Needed for | Run | Effort | Converts |
|---|---|---|---|
| Webinar 4 | Full BixBench 296-question run + official scorer | ~3–4 wk | 07 Agentic eval B → A |
| Webinar 5 | QC-governance 5-dataset AWS confusion-matrix benchmark (~$500) | ~2–3 wk | 04 QC governance placeholder → real |
| Webinar 5 | AutoFix 20-case benchmark (`run_autofix_benchmark.py`) | ~1 wk | 10 AutoFix target → measured |
| Webinar 6 | ADMET fan-out dev-Batch before/after wall-clock | ~1–2 wk | 06 Speedup target → measured |
| Webinar 6 | Full AlphaFold-DB Foldseek index + Batch smoke test | ~1 wk build | 09 Foldseek expected → measured |

**Start the Webinar-5 and Webinar-6 runs now** — they have the longest lead time and the biggest credibility upside (they turn "target/placeholder" into measured numbers before the compliance and infra audiences see them).

---

## Per-webinar format (60 min)
1. **The problem** (5 min) — operational/cost framing from the Commercial brief.
2. **Live/recorded demo** (20 min) — the workflow running on BioMate.
3. **The evidence** (20 min) — the Scientific report's §4 tables + diagrams; name the comparator and the reference standard.
4. **Q&A + roadmap** (15 min) — honest limitations (§6) and what's next (§8).

## Materials per webinar (already drafted)
- Commercial brief PDF (audience handout) · Scientific report PDF (technical follow-up "available on request") · slide deck (to build from the two).

## Notes on honesty (carry into every session)
- Only present measured numbers as results; label targets/placeholders/self-reported explicitly.
- Webinar 8 is explicitly a **roadmap** session — no proposal-tier number is stated as an achieved result.
