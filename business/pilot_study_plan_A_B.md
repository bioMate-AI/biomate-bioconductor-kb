# BioMate AI — Pilot Study Plans (Directions A & B)

*Clinical research & bioinformatics pilot design · March 2026 · Confidential — partner planning*

This document defines two four-week pilot protocols aligned with the [Pilot Study Preparation Partner Brief](pilot_study_preparation_partner_brief.md) and the [Research Direction Survey](BioMate_Research_Direction_Survey_20260303.md). QC gate rationale and evidence tiers reference [QC Threshold Evidence](../docs/QC/20260224_QC_THRESHOLDS_EVIDENCE.md) and the live gate implementation in `qc_trace_monitor.py`.

---

# Direction A — Drug Discovery Pilot Study Plan

**Partner:** UT Southwestern Simmons Cancer Center

## 1. Scientific Objective

**Question the pilot answers:** Can an oncology medicinal-chemistry / biology team obtain a **reproducible, QC-governed** computational package—ADMET safety screening plus structure-based pose evaluation—for **10–20 proprietary or literature-matched small molecules** against a **cancer-relevant target** (e.g., kinase or surface receptor with an available or modeled binding site), such that the outputs support **internal prioritization** (which analogs to advance) and a **defensible methods narrative** for grants or IND-enabling discussions?

**Data used:**

- **Structures:** Receptor coordinates (PDB or AlphaFold-derived model acceptable for pilot) and curated **SMILES** for 10–20 compounds (internal library subset or de-identified structures).
- **Optional PK curve:** If the partner supplies **sparse Phase I–like concentration–time data** (even historical or anonymized), a **non-compartmental analysis (NCA)** branch can be exercised in Week 3–4 to validate Phase I analytics.

**Expected biological insight:**

- Ranked compounds with **transparent toxicity and developability flags** (cardiac, hepatotoxicity, mutagenicity, clinical toxicity proxies) and **docking-derived binding hypotheses** (poses, scores, RMSD where redocking to a reference ligand is applicable).
- A clear **QC audit trail** tying each gate to an evidence tier and citation—so the team can explain *why* a compound passed or failed without ad hoc cutoffs.

---

## 2. BioMate Capabilities Engaged

### Platform features & workflows

- Natural-language **query → validated workflow plan** (L0 cache patterns, L2 tool-plan validation before Nextflow generation).
- **Execution on AWS** with real-time status, **QC gates** in the workflow artifact viewer, and **AutoFix** on common failure classes (parameters, resource hints, environment).
- **Exportable QC / methods narrative** (PDF/HTML export is a documented pilot prerequisite in the partner brief).

### Twelve drug-discovery phases — coverage in this pilot

| Phase (survey numbering) | Covered in pilot? | How |
|---|:---:|---|
| 1. Target identification | Partial | Context setting only; partner names target |
| 2. Target validation | **Yes** | Receptor + binding site definition for docking |
| 3. Hit identification | Optional | Scope stays 10–20 compounds, not large VS |
| 4. Hit-to-lead (ADMET) | **Yes** | `predict_admet_properties` / physicochemical prediction path |
| 5. Lead optimization | **Yes** | **hERG / DILI / Ames / ClinTox** safety QC gates |
| 6. Preclinical | No | Out of 4-week scope unless partner extends |
| 7. Regulatory prep | Optional | VCOG / label tools available but not default |
| 8. Phase I — NCA | Optional | `nca_pknca` if PK data supplied |
| 9–12. PopPK, PGx, formulation, post-market | No | Future tranche |

### QC gates that fire (ADMET, docking, NCA)

- **ADMET / toxicity (process-matched):** Gates on **hERG** (e.g., IC50 bands and inhibition probability), **DILI**, **Ames**, **ClinTox**-class outputs when present in tool JSON; parser paths include `ADMET_pred_results.json` and related toxicity blocks (see `qc_trace_monitor` ADMET toxicity section).
- **ADMET / docking precheck:** **[GOLD]** — SMILES must be parseable before heavy computation; undefined stereochemistry / salt-form warnings **[SILVER]** — documented as advisory or pre-run warnings in the evidence framework; **MW heuristics** for drug-like space **[BRONZE/EMPIRICAL]** per implementation notes.
- **Docking gates:** **Binding affinity / score** threshold (implementation default **−7.0 kcal/mol** reference gate) and **pose RMSD** check (**2.0 Å** vs. reference pose when a reference ligand pose is available).
- **NCA gates (if NCA run):** Parameter completeness (dose, time, concentration units), numerical stability of trapezoidal integration, and sensible bounds on derived metrics (AUC, Cmax, t½, CL/F, MRT) — surfaced as **NCA-specific QC** in the execution trace.

### Evidence levels (GOLD / SILVER / BRONZE) and published anchors

| Tier | Role in drug pilot | Example citations / sources |
|---|---|---|
| **GOLD** | Hard preconditions | SMILES validity before ADMET/docking; alignment to regulatory-grade expectations where drug QC maps to documented standards |
| **SILVER** | Strong recommendations | Tool-author or community standards (e.g., pose RMSD norms, widely used docking score cutoffs as *operational* gates) |
| **BRONZE** | Sensible defaults | MW / drug-likeness heuristics; thresholds documented as community practice when no single paper defines a universal cutoff |

*RNA-seq–specific ENCODE / nf-core citations in the global QC doc apply primarily to Direction B; drug-specific gates are implemented in the drug/docking segments of the same monitor and should be cited from the exported audit log per run.*

### Nextflow subworkflows invoked (representative)

- **Pharmacology / ADMET:** `pharmacology/ADMET_pred`, `pharmacology/predict_admet_properties` (and related ADMET safety screening processes).
- **Drug discovery / docking:** `drug_discovery/structure_prediction_docking` (molecular docking / pose generation pipeline).
- **Phase I (optional):** `pharmacology/ivive_hepatic_clearance`, NCA-related pharmacology workflows as selected by the planner from the validated catalog.

*Exact subgraph depends on the natural-language plan; the pilot success criterion is that the **selected** subgraph is one that exists in the indexed Nextflow library and completes without orphan processes.*

### AutoFix in this domain

| Failure class | AutoFix-style handling |
|---|---|
| **DeepPurpose / optional ML ADMET unavailable** | Fall back to **RDKit / heuristic ADMET** path where configured; surface **install script** prerequisite for partner HPC if they require DeepPurpose locally (per partner brief). |
| **Docking non-convergence / no poses** | Relax box size / exhaustiveness step (within bounded retries), retry with alternate seed; if receptor prep fails, suggest protonation state / file format fix. |
| **SMILES / salt forms** | Precheck failure → user-directed correction before burn cycles. |
| **OOM / time limit** | Reduce parallel poses or chunk compounds; escalate compute profile. |

---

## 3. Study Protocol (4-week timeline)

| Week | Activity | BioMate Role | Partner Role | Expected Output |
|---:|---|---|---|---|
| **1** | Kickoff, target & compound list freeze, data ingress | Ingest SMILES + receptor; generate baseline workflow; first dry-run or small subset | Name target, deliver SMILES list (10–20) + receptor file; confirm licensing for structures | Executable workflow spec + first execution log |
| **2** | Full ADMET + toxicity QC pass | Run `predict_admet_properties` / `ADMET_pred` path; populate QC gates; export interim QC table | Review flagged compounds; annotate known false positives/negatives from medchem | Ranked table with GOLD/SILVER/BRONZE annotations in audit log |
| **3** | Molecular docking at scale | Run `structure_prediction_docking`; apply docking score + RMSD gates; AutoFix retries logged | Confirm biological relevance of binding site; optional reference ligand for RMSD | Pose outputs + docking QC gate outcomes |
| **4** | Optional NCA branch + synthesis | If PK data available, run NCA workflow; otherwise sensitivity analysis on docking parameters | Provide PK spreadsheet **or** sign off on docking-only scope | **Methods-ready report** + researcher feedback survey |

---

## 4. Evaluation Metrics

| Metric | Hypothesis It Tests | Measurement Method | Target Value | Failure Threshold |
|---|---|---|---|---|
| Workflow generation correctness | Plain-English query yields a runnable Nextflow graph without hand-editing | Telemetry: manual correction events per workflow; run success without DSL edit | ≥80% runs complete with ≤1 manual correction per 5 workflows (partner brief) | <60% auto-success or >2 corrections per workflow median |
| QC defensibility | Researchers trust gates for internal / publication use | 5-point Likert + expert review of audit log | ≥70% rate QC as publication-ready or near-ready | <50% positive or repeated disputes on GOLD-tier gates |
| Time savings | BioMate reduces wall-clock vs. manual scripting | Timestamp query → completion vs. self-reported historical baseline | Median **<60 min** end-to-end for scoped compound count on standard compute | Slower than manual baseline for majority of runs |
| Hallucination rate | No invalid tool or impossible parameters from catalog | Log analysis: unknown tool name, schema validation failures | **0** tool-not-found / type mismatch failures attributable to planner | Any safety-critical hallucination (e.g., wrong route of admin in NCA) |
| AutoFix effectiveness | Automated recovery reduces operator toil | AutoFix success / attempted ratio from execution metadata | ≥50% of eligible failures auto-resolved within retry budget | <25% recovery on eligible failures |
| Researcher satisfaction | Usability for domain scientists | Post-run survey (1–5) | Mean ≥4.0 | Mean <3.0 |
| ADMET pass rate | Filters enrich developable set | % compounds passing partner-agreed toxicity gate profile | Meets or beats historical manual screen on same list | Worse than manual baseline without documented cause |
| Docking RMSD | Poses are chemically plausible when reference exists | Mean / median RMSD vs. cocrystal or re-docked reference | Median ≤ **2.0 Å** for held-out references | Median > **2.5 Å** with systematic pose failures |
| NCA parameter accuracy (if run) | Phase I analytics match gold standard | % metrics within 10% of partner’s validated R/WinNonlin | ≥90% metrics within 10% | <75% agreement |

---

## 5. Data Requirements

| Item | Partner provides | Public substitute | Format |
|---|---|---|---|
| Compounds | 10–20 SMILES (+ optional internal IDs) | ChEMBL / PubChem analogs of same target | `.smi`, `.csv`, or pasted list |
| Receptor | PDB/mmCIF or modeled structure | PDB entry for same target class | `.pdb` / `.cif` |
| Reference ligand (optional) | SDF or SMILES for pose RMSD | Co-crystal ligand from PDB | `.sdf` / SMILES |
| PK for NCA (optional) | Dose, time, concentration matrix | Published PK supplement (de-identified) | `.csv` / Excel |

**Data governance:** Covered by BioMate Terms of Service accepted at platform registration; public ChEMBL analogs acceptable for Week 1 dry-run while partner uploads proprietary structures.

---

## 6. Success Criteria

**Expand (“yes, we scale”):**

- ≥80% of scoped workflows complete without destructive manual intervention.
- QC audit rated publication-ready/near-ready by **≥70%** of participating researchers.
- **Zero** planner-attributed tool hallucinations on safety-critical paths.
- Time-to-result **beats** self-reported manual baseline for the same compound count.

**Remediate first (“need to fix”):**

- Repeated docking or ADMET failures tied to **environment gaps** (e.g., DeepPurpose) without acceptable fallback.
- QC audit dismissed by domain experts for **GOLD-tier** gates without a documented mitigation.
- Exportable methods report **unavailable** or incomplete at pilot end (blocks the stated deliverable).

---

## 7. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Proprietary data upload delayed | Medium | High | Start Week 1 on public ChEMBL analogs; swap SMILES once partner data is ready |
| DeepPurpose not installed on execution environment | Medium | Medium | Default to RDKit/heuristic ADMET; provide install playbook |
| Poor receptor quality → meaningless docking | Medium | High | Pre-flight structural QC; optional AlphaFold model disclaimer in report |
| Compute cost / queue latency | Low | Medium | Pre-allocate pilot queue; subset compounds on retry |
| Over-trust in ML toxicity models | Medium | High | Label outputs as screening-tier; medchem sign-off on flags |

---

# Direction B — RNA-seq / Precision Medicine Pilot Study Plan

**Partner:** Texas Children's Hospital — Research Institute

## 1. Scientific Objective

**Question the pilot answers:** For **pediatric tumor versus normal** tissue (or tumor versus non-malignant comparator), can BioMate execute a standard **FASTQ → QC → alignment → gene-level quantification → differential expression → pathway enrichment** path that yields **biologically coherent DE signals and pathway statistics** with an **ENCODE-aligned, evidence-graded QC audit** suitable for manuscript methods?

**Data used:**

- **Primary:** Paired-end RNA-seq from pediatric oncology cohorts (tumor + normal or germline comparator), **human (GRCh38)**, with **biological replicates** per condition as available.
- **Fallback:** Public **GEO** RNA-seq series with pediatric tumor–normal design if partner data is not available at pilot start.

**Expected biological insight:**

- Calibrated lists of **differentially expressed genes** (DESeq2 or edgeR as selected by the validated workflow plan), control of FDR, and **pathway enrichment** (e.g., **clusterProfiler** / compatible enricher) highlighting **cell cycle, DNA repair, immune, or lineage** programs consistent with tumor biology.

---

## 2. BioMate Capabilities Engaged

### Platform features & workflows

- **186 RNA-seq–related tools** in the unified index; Bioconductor layer includes **DESeq2**, **edgeR**, **limma-voom**, and auxiliary packages as wrapped.
- **Tiered clarification** before generation: **organism = human**, **paired-end**, **replicate structure** (n tumor / n normal), library type (polyA selected vs ribo-depleted vs FFPE if applicable).
- **Five named QC profiles** (e.g., polyA standard, ribo-depleted, FFPE, single-nucleus, non-model); pediatric solid tumor pilot defaults to **polyA standard** unless samples are FFPE — then **`rnaseq_ffpe`** profile per survey.
- **QC parsers** spanning **FastQC**, trimming, **STAR** alignment stats, **featureCounts** / assignment rates, duplication metrics where applicable, and alignment QC compatible with ENCODE-informed thresholds.

### QC gates & evidence (ENCODE / nf-core–aligned)

Representative gates documented in [QC Threshold Evidence](../docs/QC/20260224_QC_THRESHOLDS_EVIDENCE.md):

| Stage | Metric / gate | Evidence tier | Cited / anchored source |
|---|---|---|---|
| Trimming | Reads surviving post-trim | **[SILVER]** | nf-core/rnaseq defaults; ENCODE RNA-seq guidance |
| STAR / aligner | Unique alignment rate | **[SILVER]** | ENCODE post-2020 alignment guidance; STAR docs; 70% floor as community minimum gate |
| featureCounts | % assigned reads | **[SILVER]** | nf-core/rnaseq; DESeq2 vignette practice |
| FastQC | Module FAIL count | **[SILVER]** | FastQC documentation |
| DNA-seq dup gate | *Not applied as RNA hard fail* | **[GOLD]** | dupRadar / domain-aware exemption for RNA-seq |

**Survey-aligned RNA-seq highlights (Direction B asset table):** GOLD-tier exemplars include **high mapping (≥70% gate; ≥85% ENCODE target)**, **TSS enrichment**, **NRF** where ATAC/ChIP parsers extend — primary pilot focuses on **alignment + assignment + FastQC** gates.

### Pathway & statistics layer

- **clusterProfiler** (or equivalent wrapped enricher) for **GO / KEGG / MSigDb**-style enrichment on ranked gene lists from DE.
- DE tool choice logged in audit trail for reproducibility.

### Nextflow subworkflows

- RNA quantification and QC steps resolve from the biomni Nextflow library (trimming, alignment, counting modules as selected by the planner — e.g., STAR-aligned gene counts feeding DESeq2/edgeR processes).
- *Exact module names are recorded per run in the execution artifact; pilot validation requires the runbook to list the executed subgraph.*

### AutoFix in this domain

| Failure class | Handling |
|---|---|
| STAR index mismatch | Regenerate or point to correct GRCh38 index |
| Sample sheet typo | AutoFix on column names / replicate labels |
| Low memory on sort | Reduce threads / increase RAM tier |
| Annotation GTF mismatch | Align GTF release to FASTA build |

---

## 3. Study Protocol (4-week timeline)

| Week | Activity | BioMate Role | Partner Role | Expected Output |
|---:|---|---|---|---|
| **1** | Dataset prep + first end-to-end run | Clarification dialogue (human, paired-end, replicates); generate workflow; execute **FastQC → trim → STAR → counts → DE** | Upload FASTQs or metadata; confirm comparator groups | First full run + preliminary QC dashboard |
| **2** | QC review + parameter tuning | Re-run with **ENCODE-informed** profile adjustments (FFPE vs polyA); surface FastQC FAIL modules | Pathologist / molecular lead reviews QC flags; approve exclusions | Locked QC parameters + rerun logs |
| **3** | DE analysis + pathway enrichment | DESeq2/edgeR DE; **clusterProfiler** enrichment; FDR reporting | Interpret top genes for biological plausibility | DE tables + enrichment results |
| **4** | Report generation + feedback | Export **HTML/PDF methods + QC audit**; collect survey | PI review for publication readiness; written feedback | Final deliverable + go/no-go memo |

---

## 4. Evaluation Metrics

| Metric | Hypothesis It Tests | Measurement Method | Target Value | Failure Threshold |
|---|---|---|---|---|
| Workflow generation correctness | RNA query → runnable bulk RNA-seq graph | Correction telemetry; successful Nextflow completion | ≥80% workflows without major manual rewrites | <60% success |
| QC defensibility | Hospital-grade QC narrative | Likert + pathologist review | ≥70% publication-ready / near-ready | <50% positive |
| Time savings | Faster than in-house manual pipeline | Timestamp query → completion vs. baseline survey | Median **<60 min** for ≤6 samples simple design; **<90 min** for larger sets | Slower than baseline for majority |
| Hallucination rate | Planner stays within tool catalog | Schema + execution logs | **0** nonexistent tools on critical path | Any occurrence on DE or alignment |
| AutoFix effectiveness | Recovery from benign failures | AutoFix success / attempt ratio | ≥50% eligible failures resolved | <25% |
| Researcher satisfaction | Post-run survey | Mean 1–5 | ≥4.0 | <3.0 |
| Mapping rate | Libraries map to human reference | STAR uniquely mapped % | Median **≥85%** (ENCODE target); all samples **≥70%** gate | Any sample <70% without documented exception |
| DEG count | Biologically plausible signal | # FDR genes at α=0.05 | Within order-of-magnitude of power analysis expectation | Zero significant genes with obvious tech failure |
| Pathway FDR | Enrichment not noise | Benjamini–Hochberg on pathways | Top sets **q ≤ 0.05** with theme consistency | Random / single-gene driven pathways only |
| QC gate pass rate (% GC window) | Library prep sanity | FastQC GC vs. reference | Within expected species / protocol band; no FAIL without review | Unexplained FAIL modules on >50% samples |
| Duplication rate | PCR / library quality | Picard / tool dup metrics | Interpret per **RNA-seq** context (no inappropriate DNA 40% gate); flag outliers | Partner unable to reconcile with lab history |
| Insert size | Fragment distribution | Picard / collectInsertSizeMetrics | Concordant with library kit; no adapter skew | Severe skew without mitigation |

---

## 5. Data Requirements

| Item | Partner provides | Public substitute | Format |
|---|---|---|---|
| Reads | FASTQ (paired-end) | GEO download | `fastq.gz` |
| Design | Sample manifest: condition, patient ID, batch | GEO `SRA_run_table` | CSV |
| Reference | Default GRCh38 + GENCODE (platform) | Same | Managed by BioMate |
| Comparator | Tumor vs normal labels | From GEO phenotype fields | Metadata table |

**Public GEO option if partner data is not available:**

- **GSE243682** — **Pediatric neoplastic and normal brain RNA-seq** (bulk RNA-seq with childhood brain tumor and **normal brain** comparator samples; suited to **tumor vs. normal DE** when metadata clearly tags disease vs. control).
- **Alternate (hematologic):** **GSE71359** — **RNA-seq of pediatric T-ALL** (Children’s Oncology Group study); often used for **molecular subtype / lesion contrasts** — confirm whether a true **non-malignant** comparator is available in the run table; if not, scope Week 3 DE as **predefined biological contrasts** (e.g., fusion-positive vs. negative) rather than literal tumor–normal.

*Accession choice is confirmed Week 0 with the PI; pilot protocol allows swapping accession if library type (polyA vs total) mismatches the selected QC profile.*

---

## 6. Success Criteria

**Expand:**

- Completed **tumor vs. normal DE + enrichment** with audit log tying thresholds to **GOLD/SILVER/BRONZE** citations.
- **≥70%** of researchers rate outputs publication-ready/near-ready.
- Mapping and assignment metrics meet or exceed **implementation gates** (≥70% alignment minimum; target ≥85% for high-quality samples).

**Remediate first:**

- Systematic alignment failure indicating **wrong reference or sample swap**.
- DE results dominated by **batch / RIN / FFPE** artifacts without QC escalation path.
- Missing **exportable report** or inability to record **clusterProfiler** parameters in the audit trail.

---

## 7. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Partner data upload delay | Medium | High | Use **GSE243682** or **GSE71359** Week 1 (with design agreed from GEO metadata) |
| FFPE low quality | Medium | Medium | Switch to **`rnaseq_ffpe`** profile; set expectations on DEG yield |
| Batch confounding | High | High | Incorporate batch covariate in DE design; stratify analysis |
| Pediatric sample rarity | Medium | Medium | Downscope to public data; focus on QC narrative quality |
| Survival / clinical linkage absent | Medium | Low | Out of scope for 4-week pilot; note as Phase 2 per survey gap list |

---

*Document owner: BioMate Clinical & Bioinformatics Pilot Design · For internal and partner planning — align with legal before external distribution.*
