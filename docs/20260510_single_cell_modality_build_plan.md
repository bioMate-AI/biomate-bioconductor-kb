# Single-Cell Validated Modality Triage — Build Plan (2026-05-10)

Concrete 4-week build plan for the P0 feature identified in the modality vision + competitor survey + RNA-vs-protein reframe.

**Companion docs**:
- `20260510_single_cell_modality_validation_survey.md` — landscape, science, competitors, RNA-vs-protein reframe
- `20260510_why_multimodality_is_open_window.md` — defensive narrative
- `20260509_competitor_survey_and_feasibility.md` — feasibility triage across all 8 vision features

---

## Reframed Mission

**What we are building**:
A workflow that, given a target gene and indication, queries single-cell atlas data to surface normal-tissue expression at cell-type resolution, scores each major therapeutic modality option by expected on-target/off-tumor risk, and routes the output into BioMate's modality design workflows.

**What we are NOT building**:
- A replacement for IHC / flow / proteomics validation
- A clinical decision tool
- A target discovery tool (that's Cartography's space)
- A guarantee of modality success

**The honest value claim**:
Reduce target × modality triage from ~$1M and 6 months of IHC panels to atlas queries in hours, so the limited IHC budget gets spent on the candidates that survive atlas screening.

---

## Scientific Validation Strategy

Before users trust the workflow, the workflow must demonstrate it would have caught known failures. The MVP must pass a **retrospective validation panel**:

### 10-target panel for MVP validation

| # | Target | Modality | Outcome | Red flag expected? |
|---|---|---|---|---|
| 1 | CD19 | CAR-T | Approved (Kymriah, Yescarta) | NO — B-cell-restricted |
| 2 | BCMA | CAR-T | Approved (Abecma, Carvykti) | NO — plasma-cell-restricted |
| 3 | CD22 | CAR-T | Approved (academic) | NO — B-cell-restricted |
| 4 | HER2 | CAR-T | Patient death 2010 (Morgan) | **YES** — cardiac epithelium |
| 5 | CEA | CAR-T | Severe colitis (Parkhurst 2011) | **YES** — normal colon |
| 6 | ROR1 | CAR-T | Toxicity, abandoned | **YES** — adipose, parathyroid |
| 7 | EGFR | CAR-T | Skin/lung toxicity in trials | **YES** — skin, lung |
| 8 | GD2 | CAR-T | Approved (Unituxin antibody; CAR-T in trials with neurotoxicity) | **PARTIAL** — peripheral nerves |
| 9 | HER2 | ADC | Approved (Kadcyla, Enhertu) | TOLERATED — thrombocytopenia manageable |
| 10 | TROP2 | ADC | Approved (Trodelvy) | TOLERATED — neutropenia manageable |

**Success criterion**: workflow correctly flags red-flag targets (#4-8) with specific cell-type expression as rationale; correctly classifies #1-3 and #9-10 as tolerable; provides honest "partial" verdict for #8.

If the MVP achieves this on 8-10/10 cases, the case study is the demo.

---

## Architecture

```
USER INPUT
   target_gene: HER2
   indication: solid_tumor (or specific cancer type)
   candidate_modalities: [adc, cart, bispecific, protac, sirna] (optional, defaults all)
        │
        ▼
PHASE 1: ATLAS QUERY
   Tabula Sapiens (Quake lab, 483K cells, 26 tissues)
        │ + CELLxGENE Census (50M+ cells)
        │ + Human Cell Atlas (gaps: brain, eye)
        ▼
   Output: per-cell-type expression matrix
     {cell_type: {mean, median, pct_expressing, tissue}}
        │
        ▼
PHASE 2: TISSUE CRITICALITY SCORING
   Apply tissue-criticality weights (hardcoded):
     - HIGH penalty: cardiac, CNS, hematopoietic stem, lung alveolar
     - MODERATE penalty: skin keratinocytes, gut epithelium, kidney tubule
     - LOW penalty: thyroid, adipose, parathyroid (off-target tolerable)
        │
        ▼
PHASE 3: MODALITY-SPECIFIC SCORING
   For each modality, apply its tolerance rules:
     - CAR-T:  expression > 5% in ANY critical tissue → REJECT
                expression > 1% in moderate tissue → CAUTION
                add logic-gated dual-antigen suggestion if CAUTION
     - ADC:   expression in critical tissue → score by payload tox profile
                MMAE (bystander+) → reject high cardiac/neural
                MMAF (no bystander) → tolerate moderate normal tissue
     - Bispecific T-cell engager: tunable; CAUTION but not REJECT for moderate expression
                                  recommend lower dose ceiling
     - PROTAC: expression in critical tissue → flag tissue-restricted E3 ligase need
                                                (e.g., DCAF15 for hematologic)
     - siRNA / ASO: less affected by normal-tissue expression
                    (knockdown effect matters more than baseline)
        │
        ▼
PHASE 4: TUMOR EXPRESSION OVERLAY
   DepMap (1100+ cancer lines) + curated tumor scRNA-seq:
     Tumor expression range + heterogeneity
     Computes "therapeutic window" estimate:
        tumor expression / max normal tissue expression
        │
        ▼
PHASE 5: OUTPUT
   modality_triage_report.json
   modality_ranking.csv         — ranked table per modality
   cell_type_heatmap.png        — visual normal-tissue expression
   ihc_followup_panel.txt       — recommended antibodies + tissues for confirmation
   tumor_vs_normal_summary.json — therapeutic window estimate
```

---

## Week-by-Week Build

### Week 1: Atlas Query Infrastructure
**Goal**: a workflow that takes a gene symbol and returns per-cell-type expression across human tissues in <30 seconds.

- Day 1-2: Download Tabula Sapiens `.h5ad` from Figshare (~13GB). Build local query function with scanpy. Sanity-check on known targets (CD19, MS4A1) — expect B-cell-restricted.
- Day 3: Add CELLxGENE Census API as broader fallback when Tabula Sapiens lacks a tissue. (Read-only API, no key, free.)
- Day 4-5: Build per-cell-type expression aggregator (mean, median, %expressing) with confidence intervals; output as JSON + CSV.

**Deliverable**: `backend/nf-core-workflows/modules/biomate-ai-tools/atlas_expression_query/main.nf`

### Week 2: Modality Scoring Rules
**Goal**: turn the expression profile into modality-specific risk scores, validated against the 10-target panel.

- Day 1-2: Codify tissue-criticality weights (cardiac, CNS, hematopoietic = high; skin, gut = moderate; thyroid, adipose = low). Cite literature for each weight.
- Day 3-4: Implement per-modality scoring rules (CAR-T strict, ADC payload-dependent, bispecific tunable, PROTAC tissue-restricted-E3-aware, siRNA expression-tolerant).
- Day 5: Retrospective validation: run all 10 targets, compare workflow output to known clinical outcomes. Tune weights if needed (but no overfitting — at most one tuning pass).

**Deliverable**: `backend/nf-core-workflows/modules/biomate-ai-tools/modality_triage/main.nf` + validation report

### Week 3: Integration With Existing Modality Workflows
**Goal**: make atlas-derived risk scores flow into the design workflows we already shipped.

- Day 1: Pipe modality_triage output into `adc_design` as a pre-flight check — if HER2 ADC for solid tumor and cardiac expression flagged, surface warning + suggest MMAF over MMAE.
- Day 2: Same integration for `cart_construct_design` — if expression in normal tissue, suggest logic-gated dual-antigen design.
- Day 3: Same for `bispecific_antibody_design` — recommend lower dose ceiling when CAUTION fired.
- Day 4: Routing rules in `frontend/server/galaxy-assistant.ts` — trigger phrases: "single-cell atlas check for [target]", "is [target] safe for CAR-T", "modality triage for [target]".
- Day 5: Routing few-shot examples + end-to-end test.

**Deliverable**: 3 modality workflows now take optional `atlas_check` parameter; routing in place; smoke test passes.

### Week 4: Demo Polish + Validation Report
**Goal**: a compelling case study that sales/BD can show to a pharma CSO in 5 minutes.

- Day 1-2: Cell-type heatmap visualization (matplotlib → SVG, or D3 if frontend) — normal-tissue expression by cell type with criticality color overlay.
- Day 3: IHC follow-up panel generator — given the top risks, recommend specific antibodies + tissues for wet-lab confirmation. Cite Human Protein Atlas for antibody clone recommendations.
- Day 4: Retrospective validation report — formal write-up of 10-target panel results, with citations to each clinical failure / success.
- Day 5: Capabilities page entry + sidebar link + one-page sales sheet.

**Deliverable**: `docs/20260606_single_cell_modality_validation_results.md` (the case study); `/capabilities` page updated with new job cluster.

---

## Resource Plan

**People**: 1 engineer full-time × 4 weeks.

**Data storage**: ~15 GB for Tabula Sapiens + tumor reference data, fits on existing biomni container.

**Compute**: Per-query cost is negligible (~$0.001 in CPU time). MVP scales to ~10K queries/month without infrastructure changes.

**API costs**: CELLxGENE Census is free public API. Tabula Sapiens is CC-BY download. DepMap is free. Total external cost: $0.

**Total burn**: ~$30-50K (engineer time) for the MVP. No license fees, no API costs, no new infrastructure.

---

## Risk Register

| Risk | Severity | Mitigation |
|---|---|---|
| RNA ≠ protein challenge | HIGH | Explicit framing as triage-not-validation; recommend IHC follow-up panel; cross-reference Human Protein Atlas |
| Tabula Sapiens missing tissues | MED | CELLxGENE + HCA fill gaps for brain, eye, fetal tissues |
| Tumor heterogeneity not captured | MED | Show range + IQR, not point estimates; document scRNA-seq tumor reference limitations |
| Workflow overfits to 10-target panel | MED | One tuning pass max; hold out 3 targets for blind test |
| Cartography Biosciences responds | LOW-MED | Different product (they sell targets, we sell analysis); position as compatible not competitive |
| Pharma scientist dismisses RNA-only signal | MED | Lead with HER2 CAR-T death case study — atlas would have flagged it; this is the credibility hook |
| Atlas data updates / breaks API | LOW | Local Tabula Sapiens snapshot; CELLxGENE is stable; version-pin reference data |

---

## Success Metrics

**MVP (end of Week 4)**:
- 10-target retrospective panel: ≥8/10 correct classifications
- HER2 CAR-T red flag clearly visible in output
- One-page case study ready for sales
- Integration with `adc_design` + `cart_construct_design` + `bispecific_antibody_design` working end-to-end

**3 months post-MVP**:
- Used in 5+ customer workflows
- Case study published as BioMate blog post (or co-authored research note)
- 1 pharma client cites this as a reason for choosing BioMate

**6 months post-MVP**:
- Cited in 1+ external publication using BioMate
- Featured in conference presentation (AACR, AAPS, or SLAS)
- Workflow extended to bispecific / TCR-T / NK cell designs

---

## What This Locks In For BioMate's Positioning

After this ships, BioMate's pitch line becomes verifiable:

> "BioMate is the only platform where you can ask: given this target, which modality should I pursue? We answer it by querying single-cell atlas data across 26 tissues at cell-type resolution, scoring every therapeutic modality option for on-target/off-tumor risk, and surfacing the IHC validation panel needed to confirm. No other AI platform does this because doing it requires both single-cell coverage and multi-modality design coverage — which no other platform has."

The MVP is the proof point. The 10-target validation panel is the proof of correctness. The HER2 CAR-T case study is the emotional hook.

---

## Decision Gate

**If after Week 2 validation, fewer than 6/10 targets are correctly classified**, stop and reassess. The framework either has scientific limitations we missed, or the weight tuning needs domain expert review (consult a single-cell immunologist).

**If after Week 4 the case study lands well in 3+ customer conversations**, expand the scope to:
- Add TCR-T (HLA-restricted neoantigen targets)
- Add NK cell therapy
- Add radiopharmaceutical normal-tissue dosimetry overlay
- Build the modality recommender (Feature 1 from vision doc) on top

**Hard stop conditions**:
- Cartography Biosciences (or other competitor) ships an equivalent product before Week 4 → pivot to a differentiated angle (e.g., focus on combination modality triage instead)
- Tabula Sapiens / CELLxGENE changes license terms → pull from public-domain HCA only

---

## Next Step

Proceed with Week 1: Tabula Sapiens local query + per-cell-type expression workflow.
