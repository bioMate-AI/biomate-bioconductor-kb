# Zemin Zhang Pan-Cancer TME Atlas — Data Acquisition + Integration-as-Resource Plan

Date: 2026-10-01
Status: VERIFIED availability; atlas NOT released yet → stopgap plan
Author: research pass (WebSearch/WebFetch verified; no fabrication)

---

## 0. One-line verdict

The target atlas (Qin et al., "Pan-cancer tumor classification by a holistic
tumor microenvironment atlas," bioRxiv 2025, Zemin Zhang group) is **real and
numbers are verified**, but the processed data is **NOT downloadable now** — the
data-availability statement explicitly says release is gated on **formal
publication**. Plan = **track for release + use prior released Zhang atlases
(T-cell GSE156728, myeloid GSE154763) as the stopgap resource** today. We
consume their maps as a RESOURCE; we do NOT compete on TME-composition
classification.

---

## 1. Paper + verified scale numbers

- Title: *Pan-cancer tumor classification by a holistic tumor microenvironment atlas*
- Authors: Shishang Qin, ..., Dongfang Wang, Zemin Zhang (corresponding). Peking University BIOPIC.
- Preprint: bioRxiv, DOI `10.64898/2025.12.27.696641` (v1). ~278 days old as of this pass; **no journal version found yet**.
- Competing interest (verbatim): "Z.Z. is the founder of Analytical BioSciences.
  Liangtao Z., C.L., and P.F. are employees of Analytical BioSciences." → a
  commercial entity is attached; licensing posture may be more restrictive than a
  pure-academic release. Flag for the eventual DUA/license read.

Verified numbers (quoted/extracted from the full-text HTML):

| Claim in the brief | Verified value in paper | Note |
|---|---|---|
| ~94 scRNA datasets | **94 scRNA-seq datasets** | "we collected 94 scRNA-seq datasets spanning 26 solid cancer types" |
| ~4.59M cells | **4,590,413 high-quality cells** | from **1,192 samples / 819 patients**, representing **24 cancer types** (the CORE single-cell cohort) |
| ~24–26 cancer types | **26** (collection) / **24** (core post-QC) | both numbers are real, used in different scopes |
| Harmony-integrated | **yes** | scIB benchmark → Harmony v0.0.9 selected over scVI/Scanorama |
| 6 compartments + 95 subsets | **six major compartments; 95 fine-grained subsets** | "assigned all cells into six major compartments ... identified 95 fine-grained subsets" |
| ~1,271 patients | **1,271 patients across 26 cancer types** | this is the CLASSIFICATION cohort (single-cell discovery + bulk/validation), larger than the 819 core sc patients |
| ~10 patient TME groups | **10 stable TME groups** | k=10 hyperparameter; "G01".."G10"; tied to ICB response |

Important scope nuance to carry forward: **two different N's.** The single-cell
atlas substrate = 4.59M cells / 819 patients / 24 cancers. The patient
classification into 10 TME groups = 1,271 patients / 26 cancers (adds bulk /
validation cohorts). Do not conflate them when we wire features.

Biological headline (for context, not for us to re-derive): an IFN-I
multicellular module (IFIT1+ TAMs, distinct from CXCL9+ TAMs) marks
immune-activated TMEs; the 10 groups show differential ICB response; they build a
random-forest TME gene panel for ICB-response prediction.

---

## 2. Data availability — VERIFIED (the decisive finding)

**Data and code availability statement, verbatim:**

> "This study primarily utilized public datasets, with newly generated mouse
> RNA-seq data from experimental validation also included. The integrated
> single-cell data and other analyzed data, as well as analysis codes, **will be
> made publicly accessible upon formal publication of this manuscript.**"

Consequences:
- **No GEO / Zenodo / CELLxGENE / figshare / lab-portal accession** is provided in
  the preprint for the integrated atlas, the 95 cell-state labels, or the 10
  patient TME groups. (The only external URLs in the paper are tool/reference
  resources: UCSC Xena, 10x pbmc3k, SCENIC cisTarget, infercnvpy, Boyle-Lab
  blacklist — none are the atlas.)
- The underlying 94 datasets are "public," i.e. the constituent studies were
  previously deposited by their original authors, but the paper does **not** give
  a manifest/accession list in the main text, and — critically — the **value-add
  artifacts we actually want (Harmony-integrated object + 95 subset labels + 10
  TME group assignments) are the thing being withheld until publication.**

**Answer to "is the processed atlas downloadable now?": NO.** Release-on-publication.
Not controlled-access per se — just not released. Re-check at journal publication
(watch for a Nature/Cell-family paper + a GEO superseries or CELLxGENE collection).

---

## 3. Stopgap: prior Zhang-lab atlases that ARE released now

These are the right interim resource (same lab, same annotation philosophy,
overlapping compartments) and let us build the integration scaffolding before the
TME atlas drops:

| Atlas | Scope | Released artifacts | Use for us |
|---|---|---|---|
| **Zheng et al. 2021, Science** (pan-cancer T cells) | ~390k T cells, 316 donors, 21 cancers | **GEO GSE156728** (processed expr), raw at GSA **PRJCA001702**, interactive browser `http://cancer-pku.cn:3838/PanC_T` | T-compartment annotation reference; backbone training data; batch-clean substrate |
| **Cheng et al. 2021, Cell** (pan-cancer myeloid) | tumor-infiltrating myeloid cells, multi-cancer | **GEO GSE154763**; count matrix mirror on **Zenodo (record 17140779)** | Myeloid-compartment reference (incl. the TAM states central to the new atlas's IFN-I story) |

Both are fully open, processed, and immediately usable. The myeloid atlas is
especially aligned because the new TME paper's headline (IFIT1+ vs CXCL9+ TAMs)
lives in the myeloid compartment.

Gap vs the new atlas: the stopgaps are **single-compartment** (T, myeloid) and do
**not** carry the 6-compartment holistic integration or the 10 patient-level TME
groups. So they cover resource uses (a) annotation reference and (c) training data
for those compartments, but **cannot** substitute for use (d) — the 10 TME-group
feature — which is unique to the unreleased atlas.

---

## 4. Integration plan — ACQUIRE + INTEGRATE AS RESOURCE

Do NOT acquire huge files yet (per instruction). Sizes: GSE156728 processed
matrices are low-GB; Cheng myeloid Zenodo count matrix similar scale — both
tractable on our normal S3/EC2 path when we pull. The new atlas (~4.59M cells) will
be tens of GB as an integrated `.h5ad`; budget accordingly at release.

### Now (pre-release) — build the scaffolding against stopgaps
- **(a) Annotation reference:** ingest GSE156728 (T) + GSE154763 (myeloid) as
  reference label sets; stand up our cell→reference mapping (e.g. scANVI/Symphony/
  our SciBet-style path) so that when the 95-subset atlas releases we swap the
  reference object with zero pipeline change.
- **(b) Batch-clean atlas-of-atlases substrate / leakage fix:** add these two as
  additional study sources into the batch-corrected substrate. Reuse the
  study-ID-collision discipline from the immune-preproc audit (ARCHITECTURE_DESIGN
  §4b, F3) — these are multi-study atlases, so study-ID must be a first-class batch
  key, not folded into donor-ID.
- **(c) Backbone training data:** fold the T + myeloid cells into the multi-cancer
  pretraining pool; they add real multi-cancer immune diversity now.

### At release — swap in the real atlas
- Replace the stopgap references with the integrated 6-compartment / 95-subset
  object; map our cells to all 95 subsets + 6 compartments.
- **(d) Consume the 10 TME groups as a FEATURE/context input** to our
  stratification + target-nomination heads. We **ingest** their per-patient group
  label (G01–G10) and their RF TME gene panel as an input context vector — we do
  **not** re-derive the classification. This is the "build on top, don't recompute"
  principle made concrete.

### Acquisition mechanics (when we pull)
- Use the EC2 corpus-job path with `AutoimmuneCorpusProfile` IAM + dead-man's-switch
  preamble (reference_ec2_corpus_jobs). Land artifacts on S3 knowledge-datasets.
- Licensing read required at pull time: the constituent GEO sets inherit their
  original licenses (mostly open CC-BY / unrestricted processed matrices, but raw
  GSA PRJCA001702 may need an application — verify per source); and the new atlas's
  Analytical-BioSciences commercial tie means we must read its eventual license
  before using it in a product backbone vs. research-only. **Flag: potential
  non-commercial / research-only clause on the new atlas — do not assume CC-BY.**

---

## 5. NON-competing task boundary (resource, not comparator)

**What they do (and we DON'T reproduce or claim to beat):**
- RNA-only TME **composition classification**: cluster patients into 10 TME groups
  from single-cell cellular fractions; associate groups with ICB response; build a
  bulk-RNA gene-panel classifier for IO response.
- We make **no claim** to match or exceed their TME-composition classification, their
  10-group taxonomy, or their IO-response gene panel. Their classification is an
  INPUT we trust, not a baseline we benchmark against.

**What WE do on top (our non-overlapping surface):**
- **Multi-omic** integration (their maps are the RNA/annotation layer; we add
  the proteomic/MS/TCR/HLA/genetic layers our presentation+stratification model
  consumes) — they are single-modality (scRNA), we are multimodal.
- **Causal** target confidence (perturbation substrate, e.g. the 22M Perturb-seq
  line) — out of scope for an observational TME atlas entirely.
- **Multi-omic target nomination + therapeutic design** (pair/complementary-exposure
  target selection, then design) — downstream of composition, which they stop at.
- **Predictive stratification + causal target confidence** — our ranked value
  (project_immunotherapy_bottleneck); their TME group is one feature feeding it,
  not the product.

One-line boundary statement for decks/internal:
> "The Zhang pan-cancer TME atlas is a reference MAP we consume (cell-state
> annotation, batch-clean substrate, and a per-patient TME-group context feature).
> We build multi-omic + causal target nomination and therapeutic design on top of
> it. We do not compete on RNA TME-composition classification — we integrate it."

---

## 6. Open items / re-check triggers
1. **Watch for formal publication** → that is the release gate for the atlas +
   95 labels + 10 groups + code. Set a recurring check on the bioRxiv DOI /
   PubMed for the journal version.
2. At release, confirm the deposit location (GEO superseries vs CELLxGENE
   collection vs Analytical-BioSciences portal) and **read the license** before any
   product (non-research) use.
3. Verify GSE154763 is the exact Cheng-2021 accession at pull time (Zenodo mirror
   17140779 confirmed; GEO number to re-confirm against the paper's data statement).
4. Do the study-ID batch-key wiring for the stopgaps now so the leakage-fix
   substrate is ready for the big atlas.

---

## Sources (verified this pass)
- Paper (full text + data-availability + competing-interest): bioRxiv `10.64898/2025.12.27.696641v1`
- Zheng 2021 Science T-cell atlas: `science.org/doi/10.1126/science.abe6474`; GEO GSE156728; GSA PRJCA001702; browser `http://cancer-pku.cn:3838/PanC_T`
- Cheng 2021 Cell myeloid atlas: `cell.com/cell/fulltext/S0092-8674(21)00010-6`; GEO GSE154763; Zenodo record 17140779
