<!--
COVER LETTER (to the Editor)

Dear Editor,

We submit "Reproducibility is the missing endotype: why autoimmune molecular subtyping does not replicate — and how to fix it" for consideration as a Perspective. The same disease is partitioned into 3, 5, or 8 molecular endotypes by different groups; we argue this is not a biological mystery but a methodological failure — consensus clustering always returns clusters, and almost no published endotype is tested for reproducibility outside its discovery cohort. We propose a minimal, enforceable "gate 0" (out-of-cohort label transfer, longitudinal stability, variance decomposition, and an over-correction audit) that any endotype claim should clear before publication, and we show how it can be automated. The Perspective is timely given the maturation of harmonized multi-cohort resources (AMP AIM, 3TR) and directly relevant to trial stratification. It contains no new clinical data. We believe it fits the journal's readership across rheumatology, immunology, and computational medicine.

Sincerely, [Corresponding Author] on behalf of the authors.
-->

# Reproducibility is the missing endotype: why autoimmune molecular subtyping does not replicate — and how to fix it

**[Author One]¹, [Author Two]², [Corresponding Author]¹\***

¹ [Affiliation 1]  ² [Affiliation 2]
\* Correspondence: [email]

**Article type:** Perspective  **Word count (main text):** ~1,900  **Display items:** 1 table, 1 box

---

## Abstract

Molecular "endotyping" promises to divide heterogeneous autoimmune diseases into treatment-relevant subgroups, yet published schemes for a single disease disagree: systemic lupus erythematosus has been partitioned into three, five, and eight endotypes by different groups. We contend that this disagreement does not show the biology is unknowable but exposes a methodological gap. Consensus clustering returns clusters for any target number; internal indices such as silhouette measure geometric compactness, not biological reality; and almost no published endotype is tested for reproducibility outside its discovery cohort. We propose a minimal reproducibility standard — a "gate 0" comprising out-of-cohort label transfer, longitudinal stability, variance decomposition against technical and clinical covariates, and an over-correction audit — that any endotype claim should clear before it is reported. We describe how these checks can be automated within an orchestrated multi-omic pipeline that scores batch integration on two competing objectives and flags over-correction. The rate-limiting resource is not another clustering algorithm but harmonized, longitudinal cohorts coupled with a discipline of out-of-cohort validation.

---

## Main

### One disease, many "answers"

For the same disease, incompatible endotype counts coexist in the literature (Table 1). Systemic lupus erythematosus (SLE) alone has been resolved into three cross-diagnostic clusters within a seven-disease taxonomy¹, five drug-mapped endotypes², and eight whole-blood-transcriptomic endotypes⁹; adult-onset Still's disease into three³; and an orthogonal B-cell-architecture framing cuts across diagnostic boundaries entirely⁴. Three, five, and eight endotypes for one disease is not the signature of a maturing field. It is the signature of a **reproducibility problem** — and the reviews themselves locate the blocker in the absence of large, harmonized, longitudinal cohorts for training and validation, not in the absence of algorithms.

**Table 1 | Competing molecular endotype schemes for overlapping autoimmune indications.**

| Scheme | Partition | Basis | Source |
|---|---|---|---|
| PRECISESADS | 7 systemic autoimmune diseases → **3** cross-diagnostic clusters (+1 low-activity) | multi-omic; longitudinally stable | Barturen et al. 2021¹ |
| SLE molecular taxonomy | **5** SLE endotypes, cluster-tailored drug predictions | transcriptomic | Garantziotis et al. 2022² |
| Whole-blood-transcriptomic SLE endotypes | **8** SLE endotypes | whole-blood transcriptomic | Hubbard et al. 2025⁹ |
| Adult-onset Still's disease | **3** immune endotypes | circulating immune profiles | Guo et al. 2023³ |
| B-cell architecture | extrafollicular- / plasma-cell- / BAFF-dominant | mechanistic; cross-diagnostic | Sarrand & Soyfoo 2026⁴ |

### Why endotypes do not replicate

Three failure modes, all avoidable, none about "better clustering":

**1. Clustering always succeeds.** Consensus clustering and *k*-means return *k* clusters for any *k*. Internal indices (silhouette, within-cluster sum of squares) quantify geometric compactness, not biological existence. A high silhouette on the discovery cohort is not evidence the partition exists elsewhere.

**2. No out-of-cohort validation.** The decisive test — whether a model trained on cohort A assigns cohort B's patients to the same, biologically coherent groups — is rarely performed. Without it, the number of endotypes is a property of the *dataset and pipeline*, not the disease.

**3. Batch and harmonization confounds.** When cohorts differ by site, platform, ancestry, medication, and sampling time, "clusters" can be technical strata in disguise. Correcting for this is itself a trap. The technical batch-integration layer is now mature and well-benchmarked⁵,⁶, but **every method trades batch removal against biological-signal preservation, and over-correction can erase the very endotype it was meant to reveal**⁵. The harder, still-unsolved layer is clinical/metadata harmonization — mapping heterogeneous annotations to common ontologies — which remains the real bottleneck.

### A reproducibility standard: "gate 0"

Before an endotype is reported, it should clear four checks (Box 1). None requires a new algorithm; all are mechanical and should be automated rather than left to author discretion.

> **Box 1 | Gate 0 — the reproducibility checks an endotype claim must pass.**
>
> **(i) Out-of-cohort label transfer.** Train the assignment model on the discovery cohort; report assignment accuracy and biological coherence in ≥1 *independent* cohort. Non-transfer ⇒ discovery-cohort artefact.
> **(ii) Longitudinal stability.** Under repeated sampling, patients remain in their pathological cluster (movement only toward a healthy/low-activity state is acceptable). PRECISESADS¹ is a positive example of this specific test.
> **(iii) Variance decomposition.** Quantify the partition's variance explained by site, platform, ancestry, disease duration, and medication versus disease biology. A partition dominated by technical/clinical covariates is not an endotype.
> **(iv) Over-correction audit.** When batch integration is applied, score **both** objectives — batch mixing *and* biological-signal conservation⁵,⁶ — and demonstrate biology was not erased.

### Operationalizing gate 0 in an orchestrated pipeline

Because there is no universal-best integration method⁵,⁶, a credible pipeline should **select and evaluate** rather than default to one tool: run a menu (e.g. Harmony⁶, scVI, Scanorama, fastMNN for single-cell; ComBat-seq for bulk), then score each result with the two-objective scIB harness⁵ — iLISI/ASW-batch (mixing) versus cLISI/ASW-cell-type (conservation), using local inverse-Simpson indices⁶ — and **auto-flag over-correction** (batch well-mixed *and* biology degraded). Latent-factor discovery then proceeds with multi-omic factor analysis⁷, and a **gate-0 report** (Box 1) is attached to every proposed endotype. This is the difference between "we ran Harmony" and "we selected the method that removed batch without erasing biology, and here is the two-objective score."

### What a credible endotype claim must report

- The number of endotypes **and** the out-of-cohort transfer accuracy that justifies it.
- The two-objective integration scores — not merely "batch-corrected."
- Variance explained by technical and clinical covariates.
- Longitudinal stability of assignments.
- The fraction of patients whose assignment is confident versus ambiguous.

A partition reported without these is a hypothesis, not an endotype.

### Outlook

The clinical stakes are concrete: trial stratification and treatment selection are only as sound as the reproducibility of the subgroups beneath them. An endotype that does not transfer out of its discovery cohort will not survive contact with a multi-site trial. The rate-limiting resource is therefore **harmonized, longitudinal, multi-site cohorts** — precisely what consortia such as AMP AIM and 3TR are assembling — coupled with the discipline of out-of-cohort validation. The number of autoimmune endotypes is answerable; it is simply not answered by any single cohort or clustering run. Progress will come from making reproducibility a precondition of publication and from automating the checks, so that "how many endotypes" stops being a property of whose pipeline ran last.

---

## Declarations

**Author contributions.** [A.O.] and [C.A.] conceived the Perspective; all authors drafted and revised the manuscript and approved the final version.
**Competing interests.** [State any commercial interests, e.g. affiliation with a bioinformatics-platform company. The authors declare no other competing interests.]
**Funding.** [Funding sources / none.]
**Data and code availability.** No new data were generated. All cohort and method references are to published work; the two-objective integration-scoring approach described is implementable with open tools (scIB⁵, Harmony⁶, MOFA+⁷).

## References
1. Barturen, G. *et al.* Integrative Analysis Reveals a Molecular Stratification of Systemic Autoimmune Diseases. *Arthritis Rheumatol.* **73**, 1073–1085 (2021). doi:10.1002/art.41610. PMID 33351139.
2. Garantziotis, P. *et al.* Molecular Taxonomy of Systemic Lupus Erythematosus Through Data-Driven Patient Stratification: Molecular Endotypes and Cluster-Tailored Drugs. *Front. Immunol.* **13**, 860726 (2022). doi:10.3389/fimmu.2022.860726.
3. Guo, R. *et al.* AOSD endotypes based on immune cell profiles: patient stratification with hierarchical clustering analysis. *Rheumatology (Oxford)* **62**, 1636–1644 (2023). doi:10.1093/rheumatology/keac439.
4. Sarrand, J. & Soyfoo, M. B-Cells and Plasmablasts as Architects of Autoimmune Disease: From Molecular Footprints to Precision Therapeutics. *Cells* **15**, 119 (2026). doi:10.3390/cells15020119. PMID 41597194.
5. Luecken, M. D. *et al.* Benchmarking atlas-level data integration in single-cell genomics. *Nat. Methods* **19**, 41–50 (2022). doi:10.1038/s41592-021-01336-8. PMID 34949812.
6. Korsunsky, I. *et al.* Fast, sensitive and accurate integration of single-cell data with Harmony. *Nat. Methods* **16**, 1289–1296 (2019). doi:10.1038/s41592-019-0619-0. PMID 31740819.
7. Argelaguet, R. *et al.* MOFA+: a statistical framework for comprehensive integration of multi-modal single-cell data. *Genome Biol.* **21**, 111 (2020). doi:10.1186/s13059-020-02015-1. PMID 32393329.
8. Tran, H. T. N. *et al.* A benchmark of batch-effect correction methods for single-cell RNA sequencing data. *Genome Biol.* **21**, 12 (2020). doi:10.1186/s13059-019-1850-9. PMID 31948481.
9. Hubbard, E. *et al.* Validation of eight endotypes of lupus based on whole-blood RNA profiles. *Lupus Sci. Med.* **12**, e001526 (2025). doi:10.1136/lupus-2025-001526. PMID 40368437.

---

## Submission checklist
- **Title** — concise, precise, states the contribution — **PASS**
- **Author/affiliation/correspondence block** — **PASS** (placeholders to complete)
- **Abstract** — unstructured, ~180 words, no citations — **PASS**
- **Perspective structure** with subheadings, opening → problem → mechanism → standard → operationalization → outlook — **PASS**
- **Display items** — Table 1 (schemes) + Box 1 (gate 0) with legends — **PASS**
- **References** — Nature numbered style, superscript in text — **PASS** (all refs resolved to DOIs/PMIDs; refs 3–4 completed with full citations; the former "commercial platform" claim now cited to Hubbard et al. 2025, ref 9)
- **Declarations** — contributions, competing interests, funding, data/code availability — **PASS** (competing-interests statement must disclose any platform affiliation — **NOTE**)
- **Honesty / no over-claim** — framed as position/framework, no new clinical data — **PASS**
- **Cover letter** — included (top, commented) — **PASS**

*Remaining before submission: complete author/affiliation/funding; disclose competing interests; confirm target journal word/format limits. (All bibliographic details now filled and verified against DOIs/PMIDs.)*
