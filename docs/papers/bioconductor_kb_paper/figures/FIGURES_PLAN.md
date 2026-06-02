# Figures Plan — BioMate-KB Papers
**Date**: 2026-06-01

---

## Paper 1: NAR Database Issue

### Figure 1 — BioMate-KB Extraction and Curation Pipeline
**File**: `fig1_pipeline_overview.drawio`  
**Format**: draw.io XML → export as PDF/SVG for submission  
**Type**: Architecture / process flow  
**Content**:
- Input: Bioconductor 3.20 (2,241 packages)
- Phase 1: HTML/Rnw vignette parsing (section headings + code blocks)
- Phase 2: External gap filling (13 stub packages → 257 steps)
- Raw steps: 28,485 raw steps (50,959 function annotations)
- NAMESPACE validation + S4 type chain verification
- 4-round quality curation → 15,641 curated steps
- Metadata enrichment row: EDAM 94.7% | Biocontainer 98.8% | DOI 100% | Nextflow templates | Provenance
- Dual-agent LLM review (κ = 0.96)
- Outputs: BioMate AI Platform + Claude Code Skills Bundle

**Placement in paper**: §1 or §3 (Extraction Pipeline)

---

### Figure 2 — Domain Coverage Horizontal Bar Chart
**File**: `fig2_domain_coverage.py` → `fig2_domain_coverage.png/.pdf`  
**Format**: matplotlib, horizontal bar chart  
**Content**:
- 10 Bioconductor domains (BiocViews-based)
- Package counts and % of 2,241 total
- Note: 78.5% of packages span multiple domains (non-exclusive)

**Placement in paper**: §4.4 (Domain Coverage)

---

### Figure 3 — Curation Funnel
**File**: `fig3_curation_funnel.py` → `fig3_curation_funnel.png/.pdf`  
**Format**: matplotlib, custom funnel chart  
**Content**:
- 2,241 packages → 1,970 with vignettes → 28,485 raw → 15,641 curated
- 4 curation rounds labeled
- FAIR metadata coverage stats at bottom

**Placement in paper**: §3.6 (Quality Curation Pipeline) or §4.3

---

## Paper 2: Methods / AI Paper

### Figure 4 — Study Design: Grounded vs. Ungrounded
**File**: `fig4_study_design.drawio`  
**Format**: draw.io XML → export as PDF/SVG  
**Type**: Experimental design comparison  
**Content**:
- Shared input: Natural language bioinformatics task
- Left column (red): LLM-only path — hallucinated functions, wrong-package citations, no executable code
- Right column (green): Structure-grounded path — NAMESPACE validation, vignette sample code, S4 type verification
- Bottom: +16.8 pp improvement callout
- Evaluation protocol note (20 tasks × 7 domains, NAMESPACE validation)

**Placement in paper**: §1 or §3 (Methods overview)

---

### Figure 5 — Bioconductor Structural Properties as Grounding Anchors
**File**: `fig5_bioconductor_structure.drawio`  
**Format**: draw.io XML → export as PDF/SVG  
**Type**: Conceptual architecture  
**Content**:
- Four structural properties (NAMESPACE, S4, BiocViews, Vignette) arranged around central LLM node
- Each property box: what it provides, grounding role, concrete examples
- Arrows showing how each property constrains/validates LLM output
- Output: Structure-grounded workflow steps
- Key insight callout at bottom

**Placement in paper**: §2 (Background) or §3.1 (Methods overview)

---

### Figure 6 — Dual-Agent LLM Cross-Validation Protocol
**File**: `fig6_dual_agent_protocol.drawio`  
**Format**: draw.io XML → export as PDF/SVG  
**Type**: Protocol / workflow diagram  
**Content**:
- Input package → parallel Expert A (Technical Specialist) + Expert B (Applied Practitioner)
- 4 scoring criteria shown
- Agreement check (diamond): |score_A − score_B| ≤ 0.30?
- YES path → Step Accepted
- NO path → Mediator Agent (root-cause classification, 5 action types)
- Mediator outcomes: 208 renames applied to KB, 131 flagged for next cycle
- Iterative calibration box (κ 0.801 → 0.96, 1,204 revisions)
- Final output: 90.0% step correctness, κ = 0.96

**Placement in paper**: §3.5 (Dual-agent protocol)

---

### Figure 7 — Results: Generation Quality Comparison (4-panel bar chart)
**File**: `fig7_results_comparison.py` → `fig7_results_comparison.png/.pdf`  
**Format**: matplotlib, 4-panel grouped bar chart  
**Content**:
- 4 metrics: function citation accuracy, correct-package citation, executable sample code, KB context provided
- LLM-only (red) vs. BioMate+KB (green) for each
- Delta annotations in purple (+16.8 pp, +12.2 pp, +83.0 pp, +100 pp)

**Placement in paper**: §4.5 (Workflow Generation Quality)

---

### Figure 8 — κ Improvement and Step Correctness by Domain (2-panel)
**File**: `fig8_kappa_improvement.py` → `fig8_kappa_improvement.png/.pdf`  
**Format**: matplotlib, 2-panel grouped bar chart  
**Content**:
- Panel A: κ v1 vs κ v2 per domain — shows improvement from calibration
- Panel B: Step correctness % per domain — shows which domains hit threshold
- Pre-registered thresholds marked (κ ≥ 0.70, correctness ≥ 85%)

**Placement in paper**: §4.2–4.4 (Dual-agent results)

---

## How to Generate

### draw.io figures (1, 4, 5, 6)
Open in draw.io desktop app or diagrams.net:
1. File → Open → select `.drawio` file
2. Export → PDF (vector, for submission) or PNG at 300 dpi

### Python chart figures (2, 3, 7, 8)
```bash
cd docs/papers/bioconductor_kb_paper/figures/
python3 fig2_domain_coverage.py
python3 fig3_curation_funnel.py
python3 fig7_results_comparison.py
python3 fig8_kappa_improvement.py
```
Requires: `pip install matplotlib numpy`

---

## Figure Numbering Per Paper

| File | Paper 1 Fig | Paper 2 Fig |
|------|-------------|-------------|
| fig1_pipeline_overview.drawio | Fig. 1 | (supplementary or §5 ref) |
| fig2_domain_coverage.py | Fig. 2 | — |
| fig3_curation_funnel.py | Fig. 3 | — |
| fig4_study_design.drawio | — | Fig. 1 |
| fig5_bioconductor_structure.drawio | — | Fig. 2 |
| fig6_dual_agent_protocol.drawio | — | Fig. 3 |
| fig7_results_comparison.py | — | Fig. 4 |
| fig8_kappa_improvement.py | — | Fig. 5 |

---

## Submission Format Notes

- **NAR Database Issue**: Figures as separate TIFF/PDF files; no embedded figures in Word. Max 300 dpi for raster.
- **Nature Methods**: Figures as PDF preferred; panels ≤ 7 cm wide for single-column, ≤ 14 cm for double-column.
- **Bioinformatics / PLOS Comp Bio**: PDF or EPS preferred; figures cited as "Fig. X" in text.
