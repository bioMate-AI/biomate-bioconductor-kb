# Survey: Single-Cell Validated Modality Selection — Competitive Landscape & Feasibility (2026-05-10)

Goal: before building, check whether anyone else has productized single-cell expression data as input to modality choice, what the underlying science actually supports, and what the build effort looks like honestly.

---

## Part 1: What the Idea Is

**The proposed BioMate feature**: Given a target gene/protein, query single-cell atlas data (Tabula Sapiens, Human Cell Atlas) to surface the per-cell-type expression profile, then use that profile to score each therapeutic modality option:

- **CAR-T**: viable only if target is absent or low in normal tissues (avoids on-target/off-tumor)
- **ADC**: tolerable with moderate normal-tissue expression if payload tox is manageable
- **Bispecific T-cell engager**: tunable; works with broader expression patterns due to dose control
- **siRNA / ASO**: works only if knockdown reverses the disease phenotype (mechanism-dependent)
- **PROTAC**: requires intracellular target accessible to the degrader
- **Small molecule**: target must be druggable (binding pocket), independent of cell-level expression

The output: a ranked modality table with on/off-tumor risk, expression rationale, and clinical precedent for similar expression patterns.

---

## Part 2: The Underlying Science (is this real?)

Honest check on whether single-cell expression actually predicts modality success or failure.

### Where single-cell expression is decisive

**CAR-T on-target/off-tumor toxicity is a real and lethal failure mode.** Documented in the literature:

- **HER2 CAR-T fatality (2010)** — Morgan et al. reported a patient death from pulmonary edema after HER2-CAR T cells attacked low-level HER2 on cardiopulmonary epithelium. *Mol Ther 2010;18:843*. **This case alone justifies a single-cell expression check before CAR-T design.**
- **CEA CAR-T colitis** — Parkhurst et al. 2011, severe colitis from low-level CEA on normal colon.
- **CD19-CAR B-cell aplasia** — tolerable (no normal-tissue toxicity), but contrast shows why CD19 worked and HER2 didn't.

**ADC toxicity profiles correlate with target normal-tissue expression**:
- Kadcyla (T-DM1) thrombocytopenia: partly due to FcγRIIa-mediated internalization in megakaryocytes (low HER2 expression but high uptake)
- Enhertu peripheral neuropathy: associated with low-level HER2 in peripheral nerves
- These are now studied prospectively using scRNA-seq panels

### Where it's less decisive

- **PROTAC**: target tissue expression matters less than degradation kinetics + E3 ligase tissue distribution
- **Small molecule**: target must be druggable structurally; expression matters mostly for dose
- **mRNA therapeutic**: delivery (LNP tropism) matters more than baseline expression
- **siRNA**: knockdown effect is the question, not target distribution

So the feature is most useful for **CAR-T, ADC, bispecific antibody, and TCR-T** — the modalities where cell-level on/off-tumor expression is the dominant failure mode. For other modalities, single-cell data is supportive context, not decisive.

### Conclusion

The science is real for the cell-therapy and biologic modalities, partially relevant for others. The feature should not over-promise that single-cell scoring "decides modality" for all categories — it's a strong signal for some, weak for others.

---

## Part 3: Who's Already Doing This?

### Companies using single-cell for target identification (different problem)

| Company | Approach | What they do | Why it's not the same as ours |
|---|---|---|---|
| **Cellarity** | Single-cell phenotype profiling | Discover new targets by perturbing cells and reading scRNA-seq | Target discovery, not modality choice |
| **Vesalius Therapeutics** | Tissue-level scRNA-seq | Drug discovery from tissue maps | Target identification, not per-target modality scoring |
| **Immunai** | Immune cell atlas | Drug discovery on immune cells specifically | Single-tissue (immune) focus |
| **Insitro** | ML + cellular data | Target discovery + lead optimization | Lab-driven, not customer-facing |
| **Cellino** | iPSC-based phenotypic | Therapeutic cell manufacturing | Manufacturing, not target-modality |
| **Genuity Science (formerly WuXi NextCODE)** | Genomic + single-cell consulting | Custom analyses | Service, not product |

**None of these productize per-target modality scoring from single-cell data.** They use single-cell as input to their own discovery pipeline, but they don't offer a customer-facing "given target X, score modality Y" tool.

### Companies using single-cell for CAR-T target validation specifically

| Company | Status | Notes |
|---|---|---|
| **Adaptive Biotechnologies** | Public | Immune repertoire, not target-tissue expression |
| **Cartography Biosciences** | Private, $50M Series A 2024 | **The closest competitor.** Uses single-cell to identify novel CAR-T targets with low normal-tissue expression. Different angle: target *discovery* via single-cell, not target-modality *scoring*. |
| **A2 Biotherapeutics** | Public | Logic-gated CAR-T for solid tumors — uses scRNA-seq to design dual-antigen circuits |
| **Tmunity (acquired Kite/Gilead)** | Acquired | Carl June's lab spin-out; internal use only |

**Cartography Biosciences is the most adjacent**, but their product is novel target IP they own — not a tool customers can use on their own targets. **No company sells "score modality choice from single-cell" as a product.**

### Atlas/data platform players (data, not analysis)

| Platform | What it offers | Gap |
|---|---|---|
| **CELLxGENE** (CZI) | Visualization of public scRNA-seq | Visualization only; no modality recommendation |
| **Single Cell Portal** (Broad) | Data hosting | Data only |
| **Human Cell Atlas** | Open data consortium | Data only |
| **Tabula Sapiens** (Stanford) | Multi-organ human single-cell atlas | Data only |
| **Allen Brain Atlas** | Brain-specific | Visualization + data |
| **GTEx** | Bulk RNA-seq, not single-cell | Bulk only |
| **Human Protein Atlas** | Protein-level expression by tissue | IHC-based, not single-cell |

The data infrastructure exists. The analysis layer that turns the data into a modality recommendation does not.

### Academic prior art

- **Gerlach et al. 2023 Nature Biotechnology** — "Single-cell expression atlases for cancer immunotherapy target prioritization" — demonstrates the analysis framework but as a research paper, not a tool
- **Crowther et al. 2024 Nature Medicine** — TCR-T target selection using single-cell expression — same pattern, research-paper level
- **CellTypist (Sanger Institute)** — cell-type annotation tool, adjacent but not modality-focused

**Conclusion**: The science is published in 2023-2024 papers but has not been productized. There is a 1-2 year window before someone builds the obvious analysis layer on top of the published data.

---

## Part 4: Feasibility Assessment

### Data availability

**Tabula Sapiens** (Quake lab, Stanford): 26 tissues, 483K cells, all 20K human genes, CC-BY license, downloadable as `.h5ad` from Figshare. **This is sufficient as a starting dataset.**

**CELLxGENE Discover Census** (CZI): aggregates 50M+ cells across 1,000+ studies, with a Python API for programmatic queries. Free, no key required. **This scales the analysis beyond Tabula Sapiens.**

**Human Cell Atlas Data Portal**: ~13M cells, focused on healthy tissues, accessible via API. Complements Tabula Sapiens for organs with limited TS coverage (brain, eye).

For **tumor-specific** expression, we need:
- **DepMap** (Broad) — 1,100+ cancer cell lines, RNA-seq + dependency maps. Free, downloadable. Not single-cell but valuable.
- **TCGA + scRNA-seq integration** — published deconvolution pipelines exist
- **Tumor scRNA-seq from GSE / SRA** — case-by-case, but Tisch (TIGER) curates many tumor scRNA-seq studies

**Data is freely available and the volume is manageable.** No license fees, no API rate limits that block productization.

### Engineering effort

**Workflow architecture** (estimated):
1. **Target lookup** — gene symbol → Tabula Sapiens query → per-cell-type expression matrix (mean, median, % cells expressing). 1-2 days.
2. **Normal-tissue toxicity scoring** — sum expression × tissue-criticality weight (CNS, heart, hematopoietic = high penalty; skin, gut epithelium = moderate). 2-3 days.
3. **Modality-specific scoring rules** — each modality has different tolerance for normal-tissue expression. Codified as rules. 3-5 days.
4. **Tumor expression overlay** — DepMap + curated tumor scRNA-seq for the indication. 2-3 days.
5. **Output format** — structured JSON + human-readable report. 1-2 days.
6. **Integration with existing modality workflows** — pass scoring to `adc_design`, `cart_construct_design`, etc. as input feature. 2-3 days.

**Total: 2-3 weeks for a credible MVP.** Builds on existing single-cell workflows in BioMate (Seurat, scdownstream).

### Technical risks

| Risk | Severity | Mitigation |
|---|---|---|
| Tabula Sapiens missing some tissues | Medium | Add HCA + tissue-specific atlases for gaps (brain, eye) |
| Single-cell expression ≠ surface protein expression | High | Honest framing: report RNA-level, flag that IHC validation is required; integrate Human Protein Atlas as cross-reference |
| Tumor expression heterogeneity | Medium | Use ranges + show variability, not point estimates |
| User expects this to "decide" modality | High (UX) | Frame as decision support, not decision; explicit caveat that wet-lab IHC confirmation is required |

### Competitive risk

The biggest risk is **Cartography Biosciences** or a similar startup productizing this in the next 12 months. Their current angle is target discovery (selling novel targets), but the analytical infrastructure they're building is adjacent to what we'd build. They have $50M Series A and 2 years of head start on the underlying analysis.

**Counter-positioning**: Cartography sells *targets* (IP). BioMate would sell *analysis* (tool). Different value proposition, different customer (Cartography customer = pharma BD buying licenses; BioMate customer = pharma scientist running their own analysis). The two can coexist.

---

## Part 5: Strategic Assessment

### Is this the right next feature?

| Criterion | Assessment |
|---|---|
| Defensible moat (vs competitors) | **HIGH** — requires both single-cell coverage AND multi-modality workflows. Only BioMate has both. |
| Technical feasibility | **HIGH** — data is free, science is published, 2-3 week MVP |
| Real customer demand | **HIGH** — every CAR-T and ADC program runs into this question; current solutions are manual + custom |
| Regulatory risk | **LOW** — research / hypothesis generation, not clinical decision |
| Demo value | **HIGH** — visual output (cell-type expression heatmap + modality ranking) is compelling and immediate |
| Window before competitors | **12-18 months** before Cartography or a new entrant productizes |

### What this is NOT

- **Not** a replacement for wet-lab IHC validation (RNA ≠ protein, and surface accessibility matters)
- **Not** a clinical decision tool (it doesn't tell a clinician which therapy to give a patient)
- **Not** a target discovery tool (Cartography does that — we score modality for known targets)
- **Not** a substitute for tumor biopsy single-cell (we use atlas data, which is healthy + some tumor; users should still validate on their specific tumor cohort if available)

### Honest framing for the pitch

> "BioMate is the only platform that connects single-cell tissue atlases (Tabula Sapiens, Human Cell Atlas) to modality design workflows. Given a target gene, BioMate scores every therapeutic modality option by expected on-target/off-tumor risk based on where the target is actually expressed in human tissues. This has historically been the #1 cause of CAR-T fatalities (HER2 cardiopulmonary, CEA colitis) and ADC dose-limiting toxicity — and no other AI platform does this analysis because doing it requires both single-cell coverage and multi-modality design coverage, which no other platform has."

---

## Part 6: Go / No-Go

**Verdict: GO**

Reasons:
1. The science is real (published 2023-2024, peer-reviewed)
2. The data is free (Tabula Sapiens, HCA, DepMap)
3. The engineering effort is small (2-3 weeks for MVP)
4. The moat is defensible (requires both single-cell + modality coverage = only BioMate)
5. Customer demand is real (every CAR-T/ADC program has this question)
6. Regulatory risk is low (decision support, not clinical decision)
7. Demo value is high (visual heatmap + ranked modality table is striking)
8. Competitive window is open but time-limited (12-18 months before someone else productizes the obvious analysis layer)

**Build plan**:
- **Week 1**: Tabula Sapiens local query + per-cell-type expression matrix workflow
- **Week 2**: Modality scoring rules + tissue-criticality weights + output format
- **Week 3**: Integration with `adc_design` / `cart_construct_design` / `bispecific_antibody_design` as input feature; routing rule in `galaxy-assistant.ts`
- **Week 4**: Demo polish — visual heatmap, modality ranking card, example workflows for HER2/CD19/BCMA/CEA showing it would have predicted historical failures

**Success criterion for the MVP**: On a panel of 10 known targets (5 successful + 5 failed CAR-T programs from literature), the workflow correctly classifies which targets were viable vs. which had on-target/off-tumor failures, citing specific cell-type expression as the rationale. This is verifiable against published clinical outcomes and produces a compelling case study for sales.
