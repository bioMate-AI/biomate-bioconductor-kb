# Direction E — Multi-Omics (Proteomics + Metabolomics) Pilot Study Plan

**Partner:** St. Jude Children's Research Hospital — Department of Chemical Biology & Therapeutics  
**Document type:** Pilot protocol (internal + partner-facing summary)  
**Version:** 1.0 · March 2026

---

### 1. Scientific Objective

The pilot evaluates whether BioMate can support **data-dependent acquisition (DIA) LC-MS/MS proteomics** workflows—from ingestion through QC, differential abundance, and pathway interpretation—with defensible metrics suitable for manuscript methods sections.

**Protein-level question (primary):** For a defined biological or clinical contrast (e.g., drug-treated vs. vehicle cancer cell lines, or disease-relevant vs. control **plasma**), which proteins change in abundance, how confidently, and do those changes implicate coherent pathways?

**Biological / clinical insight goal:** Obtain a **ranked list of differentially abundant proteins** (with uncertainty estimates), **QC evidence** that the quantification is technically sound (replicate precision, missingness, dynamic range), and **pathway-level hypotheses** (enrichment of curated gene sets) that align with known biology for the model or disease context. Where feasible, results are compared to the partner’s **prior in-house R analysis** to establish analytical concordance, not to replace independent validation.

**Secondary (optional) metabolomics track:** With **Spectrum Health** (or another metabolomics partner) as an optional secondary collaborator, the same pilot framework can extend to **LC-MS metabolomics** processed through an **XCMS → MetaboAnalyst-class** pipeline for feature detection, alignment, and statistical comparison—scoped separately in a short addendum once instrument format and study design are fixed.

---

### 2. BioMate Capabilities Engaged

- **LC-MS-agent integration (1-week engineering prerequisite, not partner-facing in Week 1)**  
  A focused sprint wires the existing **LC-MS-agent** into the same execution path as other BioMate workflows: authenticated calls through the **Galaxy API proxy**, tool/workflow discovery from chat, parameter surfaces consistent with other domains, and run lifecycle (submit → monitor → QC gate → artifacts). Outcome: researchers can trigger proteomics-related workflows from plain-language queries without ad-hoc scripts.

- **MaxQuant / DIA-NN output processing pipeline**  
  Ingestion and normalization of standard tabular outputs (**MaxQuant:** `proteinGroups.txt`, `peptides.txt`; **DIA-NN:** report tables / matrix exports as agreed) into BioMate’s QC and statistics layers, with explicit software version logging for reproducibility.

- **QC gates specific to proteomics**  
  - **Technical CV across replicates:** coefficient of variation on normalized protein (or peptide-level rollup) intensities; **GOLD target &lt;20%** for technical replicates per **Escher et al., 2016** (*Nature Methods* — multi-laboratory study establishing replicate CV expectations for LC-MS proteomics).  
  - **Missing value rate:** **&lt;30%** at protein level after filtering rules agreed with the partner.  
  - **Dynamic range:** **≥4 orders of magnitude** in intensity (or log-scale span equivalent) on a representative subset of high-confidence quantified proteins.  
  - **Peptide / protein identification rate:** peptides mapped per MS run or protein IDs per unit acquisition time—tracked as a **study-specific baseline** and compared to partner expectations for instrument and depth.

- **DEP / limma differential abundance**  
  Linear modeling on log-transformed intensities with moderation (**limma**); optional **DEP**-style filtering where the catalog exposes it—documented in the audit log (contrast matrix, design, normalization).

- **Pathway enrichment**  
  Protein gene symbols (or UniProt → gene mapping) fed to **g:Profiler** and/or **clusterProfiler** (R) for ORA/GSEA-style enrichment with **FDR reporting**.

- **AutoFix for proteomics**  
  Targeted recovery for common failure modes: **DIA-NN version mismatch** vs. report schema; **missing spectral library** or wrong organism build; **memory / OOM** on large matrices (chunking, column subsetting, or cloud instance sizing). Failures are categorized, logged, and retried with corrected parameters when safe.

- **Spectrum Health (secondary option — metabolomics)**  
  Optional parallel track: **XCMS** feature detection and alignment, export to **MetaboAnalyst**-compatible tables, with metabolomics-specific QC (e.g., RT drift, batch effects) scoped in a one-page technical appendix.

---

### 3. Study Protocol (4–6 week timeline)

Partner-facing activities begin **Week 2**; **Week 1** is internal LC-MS-agent integration only.

| Week | Activity | BioMate Role | Partner Role | Expected Output |
|------|----------|--------------|--------------|-----------------|
| **1** | LC-MS-agent integration sprint | Engineering: proxy, tool wiring, smoke tests, documentation | No partner meetings required | Deployed integration; internal demo run on reference files |
| **2** | Kickoff + data contract | Present pilot scope, QC definitions, and artifact list; confirm platform registration | Name contrasts, samples, and de-identification rules; confirm file formats | Registered users; agreed file manifest and contrast table |
| **3** | Data ingest + first QC pass | Run pipelines; apply QC gates; deliver first QC report draft | Upload agreed files; review QC flags; flag biological outliers | QC dashboard / report v0; list of proteins passing QC filters |
| **4** | Differential abundance + concordance | Run DEP/limma; export tables; compare to partner’s prior R log2FC if provided | Provide reference R results (optional); interpret biology | Differential table + volcano-style summary; concordance metrics |
| **5** | Pathway enrichment + AutoFix hardening | Enrichment runs; document parameters; exercise AutoFix on edge cases | Review pathway maps vs. expectations; report misfires | Enrichment report; AutoFix event log |
| **6** (if used) | Buffer / metabolomics optional / exit | Final report polish; optional XCMS/MetaboAnalyst sub-track; satisfaction survey | Feedback session; survey completion | Final exportable QC + methods narrative; pilot retrospective |

*If the partner prefers a strict 4-week window, collapse Weeks 5–6 into Week 5 (pathways + survey only) and defer optional metabolomics.*

---

### 4. Evaluation Metrics

| Metric | Hypothesis It Tests | Measurement Method | Target Value | Failure Threshold |
|--------|---------------------|--------------------|--------------|-------------------|
| Protein identification rate | Sufficient depth for biology | # unique proteins quantified ÷ total MS2 spectra (or agreed alternate: proteins per run hour) | Meet or exceed partner lab typical run | &lt;50% of partner’s historical median without justified cause (instrument change, shorter gradient) |
| Technical CV across replicates | Quantitative reproducibility | CV% on normalized intensity per protein across technical replicates | **&lt;20%** (GOLD, Escher et al. 2016) | **≥30%** median CV triggers SILVER/BRONZE gate and mandatory review |
| Missing value rate | Data completeness / imputation burden | % missing protein quantifications per condition after MBR rules | **&lt;30%** | **≥40%** triggers re-run or design discussion |
| Dynamic range coverage | Instrument / pipeline linearity | Log10 span of reporter intensities (high to noise floor) | **≥4 orders of magnitude** | **&lt;3** triggers instrument or normalization review |
| Differential abundance concordance | Analytical validity vs. trusted baseline | Pearson **r** on log2 fold-change for overlapping proteins vs. partner prior R | **r ≥ 0.85** (pilot stretch goal **≥0.90**) | **r &lt; 0.75** triggers method reconciliation meeting |
| Pathway enrichment FDR | Biological plausibility | Benjamini–Hochberg FDR on top pathways for known-positive contrasts | **FDR &lt; 0.05** for ≥1 expected pathway (where ground truth exists) | No expected pathway at FDR &lt;0.1 with adequate power → pipeline review |
| Time to report vs. manual pipeline | Operational value | Timestamps: data ready → exportable report; compare to self-reported manual hours | **≥50% reduction** vs. partner baseline | No improvement after two iterations → UX / scope review |
| Researcher satisfaction score | Usability and trust | Post-run 5-point Likert (survey) on QC clarity and overall usefulness | **Mean ≥4/5** | **≤3/5** mean → mandatory product interview |

---

### 5. Data Requirements

- **Proteomics inputs (one of):**  
  - **MaxQuant** output directory containing at minimum **`proteinGroups.txt`** and **`peptides.txt`** (and `summary.txt` if available for run metadata), **or**  
  - **Raw Thermo `.raw`** files for **DIA-NN** reanalysis in BioMate/agreed compute, with **software version pinned** in the audit log.

- **Replication:** Minimum **n ≥ 3 biological or technical replicates per condition** (biological preferred for inference); exact design documented before Week 3 ingest.

- **DIA-NN spectral library:** Partner provides or approves a **FASTA-based or empirical library** in a format DIA-NN accepts (e.g., `.speclib` or build-from-DDA workflow documented in runbook); organism and enzyme rules must match acquisition.

- **Metadata:** Sample sheet with run order, batch, condition labels, and any normalization factors the partner uses today (for limma design matrices).

- **PHI / IRB:** De-identified plasma or cell-line-only studies preferred; any PHI requires **separate BAA** and is out of scope for default pilot template.

---

### 6. Success Criteria

Pilot **Direction E** is considered successful if **all** of the following hold:

1. **Integration:** LC-MS-agent sprint completes Week 1; at least one end-to-end proteomics workflow runs from chat through completion on partner or reference data.  
2. **QC:** Technical replicate **median CV &lt;20%**, **missing values &lt;30%**, and **dynamic range ≥4 orders** on the primary dataset, **or** documented exceptions with partner sign-off.  
3. **Statistics:** Differential abundance table delivered with **audit-ready limma/DEP settings**; if partner supplies prior R results, **Pearson r ≥ 0.75** on log2FC (stretch **≥0.85**).  
4. **Biology:** At least one **pathway enrichment result at FDR &lt;0.05** consistent with known biology for the chosen contrast (where such ground truth exists).  
5. **Operations:** **Time-to-report** improves vs. self-reported manual baseline, and **mean satisfaction ≥4/5** on the exit survey.  
6. **Deliverables:** Exportable **QC + methods narrative** suitable for internal manuscript drafting, plus computational audit log.

---

### 7. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| LC-MS-agent sprint slips past Week 1 | Medium | High | Freeze scope to read-only MaxQuant path first; DIA-NN raw second; daily internal standups |
| Partner data delayed or IRB-bound | Medium | High | Start Week 2 with **public reference DIA dataset** in parallel; keep St. Jude data as validation slice |
| Version skew (MaxQuant / DIA-NN) breaks parsers | Medium | Medium | Pin versions in invite metadata; AutoFix rules for schema drift; schema tests in CI |
| Spectral library missing or wrong organism | Medium | High | Pre-flight checklist in Week 2; block “Run” until library + FASTA confirmed |
| OOM / memory on large studies | Medium | Medium | AutoFix: subset proteins, increase memory tier, or chunked processing |
| Low concordance with partner R | Low | High | Joint review session: normalization, contrasts, protein grouping; align to same gene list |
| Plasma matrix effects dominate signal | Medium | Medium | Document batch covariates; limma batch model; set expectations in Week 2 |
| Metabolomics scope creep | Medium | Medium | Treat Spectrum Health track as **optional Phase 2** with separate timeline |

---

*BioMate AI · Pilot Program 2026 · Direction E (Multi-Omics)*
