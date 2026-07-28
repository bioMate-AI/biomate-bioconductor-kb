<!--
COVER LETTER (to the Editor, Nature Methods)

Dear Editor,

We submit "A reproducible pipeline for multi-omic endotyping of autoimmune disease"
for consideration as an Analysis. Molecular endotyping is widely pursued yet rarely
reproducible — the same disease is partitioned into three, five, or eight endotypes
depending on cohort and method, and few partitions are validated outside their
discovery cohort. We show this is a process failure, not a biology failure, and
present an orchestrated pipeline that makes subtype claims reproducible by
construction: it gates on data integratability and annotation grounding before
clustering, selects an integration method by a two-objective score that explicitly
detects over-correction, and validates every partition out-of-cohort. All components
are openly implemented and individually verified; we state plainly that the full
pipeline has not yet been run end-to-end on a real cohort. We believe the
reproducibility discipline — not any single algorithm — is of broad methodological
interest to the Nature Methods readership. The work has not been published elsewhere
and is not under consideration by another journal.

Sincerely,
[Corresponding Author] on behalf of all authors
-->

# A reproducible pipeline for multi-omic endotyping of autoimmune disease

**[Author One]**^1,2^, **[Author Two]**^1^, **[Author Three]**^3^, **[Corresponding Author]**^1,2,\*^

^1^ BioMate AI, [City], [Country]
^2^ [Institution / Department]
^3^ [Collaborating Institution]
\* Correspondence: [email]

**Article type:** Analysis · **Word count (main text):** ~2,100 · **Display items:** 1 figure, 1 table

---

## Abstract

Molecular endotyping — partitioning an autoimmune disease into mechanistically distinct subgroups — is widely pursued and rarely reproducible: published schemes for the same disease disagree, and most partitions are never validated outside their discovery cohort. We argue this is a process failure rather than a biology failure, and present a disciplined, orchestrated multi-omic endotyping pipeline designed to make subtype claims reproducible by construction. The pipeline enforces four checks before any clustering is trusted: a quality-control triage gate that rejects cohorts whose batch structure is confounded with biology; grounded, human-in-the-loop metadata harmonization that never fabricates ontology terms; a select-and-evaluate integration step that runs a menu of batch-correction methods and scores each on two competing objectives to detect over-correction rather than defaulting to one tool; and multi-omic factor integration followed by out-of-cohort partition validation. Every method choice is logged and scored. Components are individually implemented and verified on controlled inputs; the full pipeline has not yet been run end-to-end on a real cohort. The contribution is a reproducibility discipline that distinguishes a defensible endotype from a consensus-clustering artefact.

---

## Introduction

Endotyping promises to route patients to mechanism-matched therapy, but the literature is a cautionary tale: consensus clustering always returns clusters, silhouette scores are not evidence of biology, and the same disease is variously partitioned into three, five, or eight endotypes depending on cohort and method. Why this happens is now clarified by benchmarking of the data-harmonization field. The *technical* layer — batch-effect correction and cross-cohort integration — is mature and benchmarkable, with a stable method menu and a standard evaluation harness^1–3^. The *metadata* layer — mapping heterogeneous free-text clinical variables to common ontologies^7^ — is the genuine unsolved bottleneck, where automated (including large-language-model-based) mapping degrades sharply on out-of-dictionary terms and fabricates identifiers.

The implication is that a credible endotype requires a *pipeline*, not a single algorithm: the decisive work is upstream (is the data integratable? are annotations grounded?) and downstream (does the partition survive out-of-cohort?). Here we specify such a pipeline and the reproducibility guarantees it provides, and we are explicit about what remains unvalidated.

## Results

### Overview
The pipeline (Fig. 1) is an ordered sequence of five stages, each with a defined computation and an explicit evaluation, such that a claimed endotype can be regenerated and re-validated by a third party. Each stage is an openly implemented, independently tested workflow (Table 1; Code availability).

### A quality-control triage gate rejects un-integratable cohorts
Before integration, each candidate dataset passes a triage gate that computes metadata completeness over required fields, tests batch-versus-biology confounding via a χ² test and Cramér's *V* on the batch × group contingency table, checks provenance completeness (BRISQ/MIxS fields^6^), and flags per-sample quality-control outliers with a robust median/median-absolute-deviation rule. The gate returns an explicit verdict — INTEGRATE, TRIAGE (fixable, itemized), or REJECT. A cohort whose batch perfectly predicts the biological group (Cramér's *V* ≈ 1) is un-integratable and is rejected *before* it can manufacture a false endotype, directly addressing the largest single source of inter-cohort difference.

### Grounded metadata harmonization never fabricates identifiers
Free-text clinical values are mapped to a controlled vocabulary (EFO^7^, HPO, Cell Ontology, UBERON) by a deterministic match cascade — exact label, exact synonym, token-set Jaccard, then character edit-distance — with a confidence assigned from the winning tier. The mapper never invents a term or an ontology identifier: a value can map only to an ID literally present in the ontology, and every low-confidence, ambiguous, or out-of-dictionary value is flagged for human review. This is deliberate: LLM-only mapping is unreliable on unseen terms and fabricates plausible identifiers, so the metadata layer is human-in-the-loop by design, with per-client adaptation limited to a *proposer* whose suggestions a curator confirms.

### Select-and-evaluate integration detects over-correction
There is no universal-best integration method; each trades batch removal against biological-signal preservation^1,3^. Rather than default to one tool, the pipeline runs a menu — Harmony^2^, scVI/scANVI^5^, Scanorama, FastMNN for single-cell; ComBat-seq^8^ for bulk RNA-seq counts — and scores each result on both objectives with the scIB harness^1^: batch removal (iLISI, ASW-batch) and biology conservation (cLISI-derived purity, ASW-cell-type). The method that maximizes batch mixing *without* erasing biology is auto-selected, and **over-correction is detected explicitly** — high batch mixing with collapsed cell-type structure is flagged, not silently accepted (Methods). This converts "we ran Harmony" into "we selected the method that removed batch while preserving biology, with the two-objective score reported."

### Multi-omic factor integration and endotype discovery
On harmonized, well-integrated data, MOFA+^4^ learns latent factors across omics layers; endotypes are derived from the factor space, with the number of clusters treated as a hypothesis to be validated rather than asserted. Factor–feature weights surface candidate drivers per endotype.

### Gate-0 validation asks whether the partition is real
No endotype is trusted until it passes out-of-cohort label transfer (does the partition reproduce in an independent cohort?), longitudinal stability (do patients remain in their endotype over time, with movement only toward a healthy state?), and variance decomposition against site, ancestry, medication, and disease duration (is the signal biology or confound?). Only partitions clearing these checks proceed to downstream stratification or biomarker claims.

## Limitations

The pipeline's components are individually implemented and verified on controlled inputs — the triage gate correctly rejects a perfectly confounded cohort, the integration scorer correctly flags an over-corrected embedding, and the metadata mapper correctly refuses to invent an identifier. **The full pipeline has not yet been run end-to-end on a real autoimmune cohort.** Doing so requires access to real, harmonized, longitudinal multi-omic cohorts — the field's binding constraint, which consortium releases (AMP AIM; 3TR/ADEx) are only beginning to relieve. The pipeline also inherits the metadata bottleneck: harmonization remains human-in-the-loop, and endotype validity is only as strong as the independent cohorts available for out-of-cohort validation.

## Discussion

The prevailing failure mode — run an integration method, consensus-cluster, report silhouettes — cannot distinguish a mechanistic endotype from a clustering artefact, because it skips the questions that decide reproducibility: was the data integratable, were annotations grounded, was batch removed without erasing biology, and does the partition survive out-of-cohort. By making those questions *gates* rather than afterthoughts, the pipeline trades a single number for an auditable, reproducible claim. That discipline — not any single clustering algorithm — is what a downstream trial-stratification decision can be built on.

---

## Methods

**Quality-control triage.** Metadata completeness is the fraction of required fields (batch, group, sex, age, timepoint, platform) present. Batch–biology confounding is tested by Pearson's χ² of independence on the batch × group contingency table (implemented via the regularized incomplete gamma function) with Cramér's *V* = √(χ²/(*n*·(min(*r*,*c*)−1))) as effect size; *V* ≥ 0.8 → REJECT, ≥ 0.5 → warn. Per-sample continuous QC metrics are flagged as outliers by |*x* − median| > *k*·MAD (default *k* = 3.5). Verdict logic: REJECT on confounding or completeness < 0.6; otherwise TRIAGE if any fixable deficiency, else INTEGRATE.

**Metadata harmonization.** For each free-text value the cascade attempts, in order: normalized exact-label match; exact synonym match; token-set Jaccard similarity; character-level edit-distance (difflib) similarity. Confidence is tiered by the winning method. Values below a confidence threshold, with ambiguous near-ties, or with no acceptable candidate are flagged `needs_review`; no identifier absent from the supplied ontology is ever emitted.

**Integration and evaluation.** Candidate integrations are scored on an embedding with batch and cell-type labels. LISI is the inverse Simpson index of labels among *k* nearest neighbours (iLISI over batches → high = mixed; cLISI over cell types → low = pure)^1,2^; ASW is the average silhouette width by batch (low = mixed) and by cell type (high = biology preserved). Batch-removal and biology-conservation scores are the normalized means of their components; the overall score is a weighted combination (default equal weights). Over-correction is declared when batch removal ≥ threshold while biology conservation < threshold. MOFA+^4^ is fit on the selected, integrated representation.

**Gate-0 validation.** Out-of-cohort label transfer trains a classifier on the discovery-cohort partition and reports transfer accuracy to an independent cohort; longitudinal stability quantifies assignment persistence across timepoints; variance decomposition attributes factor variance to biology versus site/ancestry/medication/duration.

**Statistics and reproducibility.** All tests are two-sided. All method choices, thresholds, and scores are logged. Software: Nextflow (orchestration); Python 3.10 and R/Bioconductor (MOFA+, ComBat-seq). Workflows are deterministic where stochasticity is involved (fixed seeds).

**Data availability.** No new data were generated. Consortium resources referenced: AMP AIM, 3TR/ADEx.
**Code availability.** The pipeline stages are released as open workflows: `cohort_qc_triage`, `metadata_harmonizer`, `integration_benchmark` (and `target_scorecard_ranker` downstream).

---

## Figures and Tables

**Figure 1 | The reproducible endotyping pipeline.** Schematic of the five ordered stages — QC-triage gate → grounded metadata harmonization → select-and-evaluate integration (with over-correction detection) → MOFA+ endotype discovery → gate-0 out-of-cohort validation — with the decision (INTEGRATE/TRIAGE/REJECT; auto-selected method; validated/rejected partition) emitted at each gate. *[Figure to be provided.]*

**Table 1 | Integration-method menu and the two-objective scoring harness.**

| Component | Options / metrics | Objective |
|---|---|---|
| Single-cell integration | Harmony, scVI/scANVI, Scanorama, FastMNN | batch removal vs biology conservation |
| Bulk RNA-seq | ComBat-seq | count-preserving batch correction |
| Batch-removal metrics | iLISI, ASW-batch | higher = better mixing |
| Biology-conservation metrics | cLISI purity, ASW-cell-type | higher = biology preserved |
| Over-correction flag | batch-removal high ∧ biology-conservation low | detect erased structure |

---

## References

1. Luecken, M. D. *et al.* Benchmarking atlas-level data integration in single-cell genomics. *Nat. Methods* **19**, 41–50 (2022). doi:10.1038/s41592-021-01336-8. PMID 34949812.
2. Korsunsky, I. *et al.* Fast, sensitive and accurate integration of single-cell data with Harmony. *Nat. Methods* **16**, 1289–1296 (2019). doi:10.1038/s41592-019-0619-0. PMID 31740819.
3. Tran, H. T. N. *et al.* A benchmark of batch-effect correction methods for single-cell RNA sequencing data. *Genome Biol.* **21**, 12 (2020). doi:10.1186/s13059-019-1850-9. PMID 31948481.
4. Argelaguet, R. *et al.* MOFA+: a statistical framework for comprehensive integration of multi-modal single-cell data. *Genome Biol.* **21**, 111 (2020). doi:10.1186/s13059-020-02015-1. PMID 32393329.
5. Lopez, R. *et al.* Deep generative modeling for single-cell transcriptomics. *Nat. Methods* **15**, 1053–1058 (2018). doi:10.1038/s41592-018-0229-2. PMID 30504886.
6. Moore, H. M. *et al.* Biospecimen Reporting for Improved Study Quality (BRISQ). *Biopreserv. Biobank.* **9**, 57–70 (2011). doi:10.1089/bio.2010.0036. PMID 21826252.
7. Malone, J. *et al.* Modeling sample variables with an Experimental Factor Ontology. *Bioinformatics* **26**, 1112–1118 (2010). doi:10.1093/bioinformatics/btq099. PMID 20200009.
8. Zhang, Y., Parmigiani, G. & Johnson, W. E. ComBat-seq: batch effect adjustment for RNA-seq count data. *NAR Genom. Bioinform.* **2**, lqaa078 (2020). doi:10.1093/nargab/lqaa078. PMID 33015620.

---

## Declarations

**Author contributions.** [A.O.] and [C.A.] conceived the pipeline; [A.O.], [A.T.] implemented and verified the components; [A.T.] performed the controlled-input evaluations; [C.A.] supervised; all authors wrote and approved the manuscript.
**Competing interests.** [Author affiliations with BioMate AI to be declared.]
**Funding.** [To be completed.]
**Ethics.** No human-subjects data were used; the work is a pipeline design with component validation on controlled inputs.

---

## Submission checklist

| Requirement | Status |
|---|---|
| Concise, honest, method-forward title | PASS |
| Author/affiliation/correspondence block | PASS (placeholders) |
| Unstructured abstract, ~180 words, no citations | PASS |
| Introduction → Results → Limitations → Discussion | PASS |
| Over-correction detection called out | PASS |
| Honest limitation (no end-to-end real-cohort run) | PASS — stated plainly |
| Separate, reproducible Methods + Statistics subsection | PASS |
| Figure 1 + Table 1 with legends | PASS (figure is a placeholder for artwork) |
| Nature numbered references, superscript in text | PASS |
| Author contributions / Competing interests / Funding | PASS (placeholders) |
| Data & Code availability | PASS (open workflows named) |
| Cover letter | PASS (top of file) |
| Over-claim audit | PASS — framed as pipeline design + component validation |
