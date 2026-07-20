# BioMate White Paper — Outline (Case-Study-Driven)

**Aim:** demonstrate BioMate's advantages across the dimensions that matter to research, clinical, and commercial buyers, anchored in executed, benchmarked case studies. Each section names the case study/evidence that substantiates it, so no claim is unsupported.

---

## 0. Executive Summary (1 page)
The one-paragraph thesis + the finished-benchmarks table (27 head-to-head rows from the catalog). Lead metric per pillar: 0.93 AUROC (accuracy), 1.78 Å at $27 (cost), 8+ cohorts (breadth), audit 1.0 vs 0.0 (governance).

## 1. The Problem (2 pp)
- Bioinformatics/drug-discovery analysis is fragmented, expert-gated, slow, and non-reproducible.
- The autonomous-AI mirage: general-purpose "AI scientists" run code that is wrong ~63% of the time. → **Evidence: SGI-Bench (D2), 33.83/100 best autonomous AI.**

## 2. BioMate's Thesis: Orchestration + Evidence-Graded Governance (2 pp)
- Orchestrate *validated* tools, don't generate ad-hoc code; gate every decision with graded evidence; keep a regulatory audit trail.
- → **Evidence: Agentic evaluation (07)** — orchestration beats frontier + fine-tuned models (BixBench 48% vs 29.2%; BiomniEval1 71.3% vs 65%).

## 3. Pillar I — Scientific Rigor & Accuracy (3–4 pp)
- **Drug discovery (01):** ADMET AUROC beating ADMET-AI on all endpoints; CiPA multi-channel cuts false positives 58→8%; PBPK meets EMA qualification; semaglutide validated vs SUSTAIN-1.
- **Cryo-EM (02):** Nyquist-limited 1.78 Å against the published structure.
- Message: BioMate matches or beats the field's gold-standard tools on their own benchmarks.

## 4. Pillar II — Coverage & Cohort Breadth (2–3 pp)
- **Clinical PBPK cohorts (03):** a validated workflow for each special population (pediatric, pregnancy, renal, hepatic, geriatric, obesity, sex, FIH).
- **Routing (05):** 2,455 workflows across 34 domains, selected at 100% top-1 on benchmark.
- Message: one platform, every cohort and every assay — not a point tool.

## 5. Pillar III — Speed & Cost (2 pp)
- **Cryo-EM (02):** 33× cheaper, 89% less analyst time.
- **Speedup (06):** reference cache 10³–10⁴× per hit; multi-GPU 3.4×; compound fan-out 20–50× (target).
- **IND authoring (01):** 40–120 h → <1 min draft.
- Message: same answers, a fraction of the time and cost.

## 6. Pillar IV — Governance, Compliance & Reproducibility (3 pp)
- **QC governance + auto-loop (04):** 96.4% autonomous gate convergence; three-tier regulatory basis (never overrides an FDA/ICH criterion); audit completeness 1.0 vs 0.0 for Tower/Galaxy/KNIME (p=1.6e-4); 21 CFR Part 11.
- Message: speed without losing regulatory defensibility — a moat competitors' silent-filtering pipelines can't match.

## 7. Reproducibility & the Path from Paper to Result (1–2 pp)
- **Paper-to-workflow (08):** Hit@5 = 1.00 finding the right pipeline for a published method.
- Message: BioMate closes the reproduce-and-extend loop.

## 8. Consolidated Evidence Table (1–2 pp)
- The 27-row finished-benchmarks table + the cohort-coverage matrix (from the catalog Excel). This is the "receipts" section.

## 9. Roadmap — Where We're Going (1–2 pp)
- Honest forward look: multi-omics/systems-biology gold standards, autoimmune cross-specialty chaining (SLE/RA/COVID), CryoEnsemble rare-conformer recovery, proteomics QC, cross-run stability. → **Roadmap-tier briefs (09).**
- Framed as pipeline, clearly separated from delivered evidence.

## 10. Appendix — Methods, Data & Code Availability
- Per-case dataset accessions, package versions, compute environments, and the `[GAP]` list (from the Evidence Gaps sheet). Deposition plan (Zenodo/HuggingFace DOIs).

---

## Narrative discipline (carried from the case studies)
1. Every headline number is real and sourced; estimates/targets/self-reported figures are labelled.
2. Finished evidence (Tiers A/B) is the spine; proposals (Tier C) live only in §9; third-party stats (SGI) are positioning, not BioMate results.
3. The four pillars map 1:1 to buyer concerns: *is it right, does it cover me, is it fast/cheap, can I defend it to a regulator.*

## Open decisions for the author
- **Audience split:** one white paper, or a scientific edition (Pillars I/IV heavy) + a commercial edition (Pillars II/III heavy)?
- **§4.2 metric convention:** keep the template's DE-concordance rows, or the per-domain metric substitution used in the reports (recommended)?
- **Which Tier-B runs to complete first** to upgrade their sections to Tier-A confidence (recommended: QC-governance AWS benchmark, ADMET fan-out measurement, routing independent-labeler eval).
