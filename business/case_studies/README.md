# BioMate Case Studies — Index

Paired **Commercial Case Briefs** (1-page, outcome framing) and **Scientific & Technical Validation Reports** (methods + benchmark framing, with Mermaid diagrams and results tables) built from BioMate's documented, executed work. Feeds the forthcoming **BioMate white paper**.

## Contents

| File | What it is |
|---|---|
| `BioMate_CaseStudy_UseCase_Catalog.xlsx` | Master inventory — 5 sheets: Master Catalog (27 use cases, status-colored), Finished Benchmarks (27 head-to-head rows), Cohort Coverage matrix, Evidence Gaps, Nature/Science Roadmap |
| `00_TEMPLATE_ALIGNMENT_ASSESSMENT.md` | Which use cases fit the templates now (Tier A), need one run (Tier B), need major work (Tier C), or need reframing (Tier D) |
| `09_ROADMAP_TIER_case_studies.md` | Compact briefs for the not-yet-executed use cases (multi-omics, autoimmune, CryoEnsemble, proteomics, stability, auto-update, SGI positioning) |
| `commercial_briefs/` (+ `pdf/`) | 10 one-page commercial briefs (Markdown master + rendered PDF) |
| `scientific_reports/` (+ `pdf/`) | 10 validation reports with Mermaid diagrams + results tables (Markdown master + rendered PDF) |
| `BioMate_White_Paper.pdf` / `12_WHITE_PAPER_DRAFT.md` | White-paper draft — innovation→benefit spine, four pillars, evidence table, roadmap |
| `BioMate_Webinar_Schedule.pdf` / `11_WEBINAR_SCHEDULE.md` | 8-week webinar series from 2026-07-24, readiness-sequenced with a measurement prep-gate |

**PDF generation:** Markdown is the editable master; PDFs are rendered via Chrome headless + Mermaid (script: `build_pdfs.py`). Re-run after editing any `.md` to refresh its PDF. Template styling (navy headings, title page, TOC, bordered tables, KEY MESSAGE box, sign-off) matches the BizBildr template.

**Dual spine:** every report and the white paper pair a **technical innovation** (the novel technique) with its **measured benefit** — see the white paper's §3 "Core Technical Innovations" and each Scientific report's "Technical innovation —" line in §3 Methods.

## The 8 anchor case studies

| # | Case study | Tier | Headline evidence |
|---|---|---|---|
| 01 | Drug-discovery pipeline (ADMET→CiPA→PBPK→IND→BOIN) | A | AUROC 0.93 beating ADMET-AI; CiPA FP 58→8%; EMA-qualified PBPK; 96.4% auto-loop |
| 02 | Cryo-EM single-particle (EMPIAR-10028) | A | 1.78 Å Nyquist, 2.8 GPU-h, $27 vs $900, zero false halts |
| 03 | Clinical PBPK cohort coverage | A | 8+ special populations; EMA 2-fold; semaglutide validated vs SUSTAIN-1 |
| 04 | QC governance + autonomous remediation | B | 96.4% gate convergence; audit 1.0 vs 0.0 (p=1.6e-4); 3-tier regulatory basis |
| 05 | Workflow retrieval (key-term injection) | A | 100% P@1 vs Claude 85.2%; +18.5pp over keyword |
| 06 | Speedup (fan-out, cache, multi-GPU) | B | cache 10³–10⁴× per hit; cryo-EM 3.4×; fan-out 20–50× target |
| 07 | Agentic evaluation (BixBench/BiomniEval1) | B | 48% vs 29.2% (BixBench); 71.3% vs 65% (BiomniEval1) |
| 08 | Paper-to-workflow retrieval | B | Hit@5 = 1.00, MRR 0.63 (lexical lower bound) |

## Editing & export

- Markdown is the **editable master**. Diagrams are Mermaid (render on GitHub; convert to figures with `pandoc` + `mermaid-filter`/`mmdc` where installed).
- To export to DOCX (matching the `business/` convention): `pandoc <file>.md -o <file>.docx` (install pandoc + mermaid-filter on a machine that has them).
- Every quantitative value carries a source path; unfilled fields are marked `[GAP]`.

## Provenance & honesty rules applied

- Only **real, documented** values are used; nothing fabricated.
- Estimates, targets, self-reported, and placeholder figures are labelled as such.
- Proposal/in-progress use cases are quarantined in the roadmap tier so they never inflate the finished evidence.
