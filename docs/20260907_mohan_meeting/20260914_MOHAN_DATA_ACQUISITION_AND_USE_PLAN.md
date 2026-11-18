# Mohan Collaboration — Data Acquisition & Use Plan (detailed)

Date 2026-09-14. Single reference consolidating the cohort inventory, access tiers, how each
dataset is used, the controlled-access applications (dbGaP/EGA), the on-request collaboration
tier, the HOC's role, grants, and the sequenced acquisition plan. Companion files:
`20260914_MOHAN_DATA_AND_GRANT_INVENTORY.md`, `20260914_MOHAN_COHORT_ACCESS_TIERS.md`,
`20260914_DBGAP_ACCESS_APPLICATION.md`, `20260914_OPEN_DATA_FETCH_LOG.md`.

---

## 0. Bottom line

Dr. Chandra Mohan's group (Univ. of Houston; ~$33.4M funding) holds **published** cohorts across
**lupus nephritis / SLE and IBD**, spanning urine/serum/stool **proteomics**, **whole-blood
transcriptomics** (PRECISESADS), **renal single-cell**, **spatial omics**, and **autoantibody
arrays**. Every cohort discussed is *published*; the **data** behind them falls into three access
tiers:
- **Open / download now** — a few ImmPort/PRIDE/GEO deposits (we can take these ourselves).
- **Controlled — apply** — dbGaP + EGA (genotype/scRNA); free but gated by eligibility + Data Use
  Limitations; often cleaner *through Mohan* as academic PI.
- **Published, on-request (DUA)** — the **outcome-labeled** sets (belimumab response, IBD
  longitudinal, spatial non-response). Not downloadable; obtainable only via the collaboration.
  **This tier is the collaboration's unique data value.**

The binding constraint (same lesson as our own program): modalities exist, but **same-patient
pairing + treatment/response labels** are what determine usefulness — and that must be confirmed
with Mohan.

---

## 1. Cohort inventory (published; disease × modality)

| Cohort | Disease | Modality | N | Design | Outcome labels | PMID | Access tier | Accession |
|---|---|---|---|---|---|---|---|---|
| ALCAM urine SomaScan | SLE/LN | urine proteomics (1,129-plex) | 23/95/280 (cross-ethnic) | cross-sectional | active/inactive | Nat Commun 2020;11:2197 | **OPEN** | ImmPort **SDY997**, SRA PRJNA379992 |
| Expanded urine panel | LN | urine proteomics | — | cross-sectional | active/inactive | J Autoimmun 2024 | on-request | — |
| Belimumab responders | LN | urine proteomics | RCT arm | longitudinal | **responder/non-responder** | 36167482 | **ON-REQUEST** | — |
| UC stool aptamer | IBD (UC) | stool proteomics | 50 | **longitudinal** | **wk-4 remission** | 34183667 | ON-REQUEST | — |
| IBD plasma aptamer | IBD | plasma proteomics | 76 | cross-sectional | — | 36549591 | ON-REQUEST | — |
| IBD stool antibody array | IBD | stool array | 73 | treatment-naïve | — | 40252987 | not-located (paywalled) | — |
| Crohn's stool (RISK) | Crohn's | stool proteomics | 47 | longitudinal | **stricturing progression** | 42039204 | ON-REQUEST | — |
| SLE whole-blood transcriptome | SLE | bulk RNA-seq + eQTL | 350/497 | cross-sectional | — | 36996699 | ON-REQUEST (Elsevier); underlying = EGA | EGA (see §3b) |
| LN transcriptome (PRECISESADS) | LN | bulk RNA-seq | — | — | — | 38899167 | **CONTROLLED (EGA)** | EGA |
| NPSLE transcriptome | NPSLE | bulk RNA-seq | — | — | — | 40672966 | **CONTROLLED (EGA)** | EGA |
| Urine proteome + renal scRNA (IL-16) | LN | proteome + scRNA | — | longitudinal (Tx-resp) | Tx-response | 34783463 | proteome **OPEN** / scRNA **CONTROLLED** | ImmPort SDY997 / dbGaP **phs001457** |
| Urine proteome + renal scRNA (IFN-γ) | LN | proteome + scRNA | — | — | — | 32396533 | proteome OPEN / scRNA CONTROLLED | ImmPort SDY997 / dbGaP phs001457 |
| Visium spatial | LN kidney | spatial transcriptomics | — | — | — | 42138328 | not-located (new, paywalled) | — |
| Spatial proteomics | LN kidney | 34-plex spatial | — | — | **induction non-response** | 42656727 | ON-REQUEST | — |
| Imaging mass cytometry | LN kidney | IMC 50-plex | — | — | — | 37516396 | not-located (closed) | — |
| ProtoArray autoantigen | SLE | 9,400-antigen array | — | — | — | 31494269 | not-located | — |
| 274-plex autoantibody | SLE | serum array | — | — | — | 27211902 | not-located | — |
| Immune-complex MS | SLE | proteomics | — | — | — | 35419005 | **OPEN** | PRIDE **PXD031069** |

*Not-located = paywalled full text; access tier unconfirmed until the DA statement is read.*

**Correction on record:** their **human whole-sequence genomics** exists but is **in-house /
unpublished** → **not shareable** (they publish it first). Their *published* genomics is largely
murine. Human genotype we can obtain = via **EGA/PRECISESADS** and **dbGaP** (below).

---

## 2. How we use each dataset (data → analysis → what it proves)

| Dataset | Analysis | Proves |
|---|---|---|
| ALCAM urine (OPEN) | Parity + **blind ALCAM-recovery** with evidence breakdown | We independently recover their validated target → credibility |
| **Belimumab responders** (on-request) | **Responder stratification** from baseline proteome | "Which therapy for which patient" — the top-value claim |
| IBD longitudinal (on-request) | Target-confidence + outcome prediction, **second disease** | Cross-disease generalization |
| Spatial non-response (on-request) | Tissue-localized targets + non-response stratification | Targets in the disease-driving compartment |
| PRECISESADS transcriptome (EGA) | IFN/B-cell mechanism signatures + cross-cohort validation | Replication + mechanism axis |
| Renal scRNA (dbGaP) | Cell-state resolution for the FM substrate | Endotype-level target/stratification |
| Perez SLE scRNA (GEO, open) + genotype (dbGaP) | cis-eQTL/csQTL → **genetics-anchored causal target-confidence** | Driver vs passenger |
| Autoantibody arrays / immune-complex MS | Builds the **autoantibody evidence channel** | Their data type becomes a ranking channel |

---

## 3. Access tiers — exactly how to get each

### 3a. OPEN — download now (no application)
- **ImmPort SDY997** (ALCAM urine + AMP metadata) — *we already hold full ImmPort DR66 in S3; check there first.*
- **PRIDE PXD031069** (immune-complex MS).
- **GEO GSE174188** (Perez SLE scRNA, ~1.2M PBMCs — the open expression side of phs002812).
- **GEO GSE10325/GDS4185** (SLE PBMC), **GSE72535** (discoid-lupus skin).
- Status: **fetch in progress** → `20260914_OPEN_DATA_FETCH_LOG.md`.

### 3b. CONTROLLED — apply (free; gated by DUL + eligibility)
- **dbGaP phs001457** (AMP RA/SLE — renal scRNA). **Best route: apply through Mohan** (he's an AMP contributor).
- **dbGaP phs002812** (Perez) — **genotype only** (scRNA is free on GEO GSE174188).
- **EGA `EGAS00001003662`** (PRECISESADS SLE RNA-seq + genotype, 142 SLE + 58 HC). **We have an EGA account (yaoyun.zhang@biomate.ai)** → submit a Data Access Application to the PRECISESADS DAC (signed DAA + this RUS). *Confirm the exact EGA accession cited in 38899167/40672966 — may be a sibling of EGAS00001003662.*
- Application text (RUS + lay summary + eligibility): `20260914_DBGAP_ACCESS_APPLICATION.md`.
- **Key gate:** read each DUC/DAA for **NPU (non-profit only)** — if NPU, BioMate can't be the
  requester and we route through Mohan (academic PI). Timeline: weeks.

### 3c. ON-REQUEST (DUA) — the collaboration tier
Published papers whose data statement says "available on reasonable request." **Not downloadable,
not guaranteed even if asked — but realistically obtainable as Mohan's collaborator.** Named
datasets to request: **belimumab BLISS-LN responders (36167482)**, **IBD longitudinal
(34183667, 42039204, 36549591)**, **spatial non-response (42656727)**. This is what a partnership
uniquely unlocks (everything in 3a we can get without him).

---

## 4. The HOC (Houston Omics Collaborative) — its role, precisely
Mohan's **own fee-for-service proteomics core** (order via iLab): SomaScan (~11k), Olink, targeted
proteomics, autoantigen arrays, genomics/gene-expression, metabolomics.
- **Not needed for the pilot** — the pilot runs on existing data.
- **Phase-2 only:** if a gap needs **new proteomic profiling**, HOC is the low-friction place (his
  core). Transcriptome/genotype would need a *separate* arrangement — HOC is the proteomic arm only.
- **Not** functional target validation and **not** "validation of our findings" — it generates data.

---

## 5. Sequenced acquisition plan

| Phase | Action | Dependency |
|---|---|---|
| **0 — now** | Fetch OPEN sets (§3a); check S3 ImmPort for SDY997 | none — in progress |
| **1 — weeks** | Submit **EGA** DAA (EGAS00001003662, our account) + **dbGaP** DARs (phs001457 via Mohan; phs002812 genotype) | DUL/NPU check; Signing Official / academic-PI route |
| **2 — collaboration** | Request the **on-request DUA** sets (belimumab, IBD, spatial); confirm pairing + sharing route | Mohan agreement + DUA |
| **3 — later** | New profiling via **HOC** *if* a gap is found; wet-lab (slow-channel) validation of a nominated target | pilot shows value |

---

## 6. Grants (context; ~$33.4M floor)
- **NIH:** 20 projects 1998–2031 (~$29.8M); **3 active** — R01AR086872 (10-yr autoimmunity/proteomics →2031), R01DK134055 ("Objective Classification of LN" →2028), R01AR074096.
- **CPRIT RP250585** — $2.999M, PI/Director, 2025 (Cancer Immunotherapy Biomarker Core / HOC).
- **LRA** — Target-Identification (ALCAM), $600K, 2018–2021.
- **DOD** — confirmed funder; no discrete grant# located.

---

## 7. Critical open questions to confirm with Mohan (the make-or-break)
1. **Same-patient multi-omic pairing** — are urine proteome, transcriptome, renal scRNA, and genotype on the **same patients**? (Determines whether real multi-omic causal + stratification is possible.)
2. **Treatment/response linkage** — which cohorts have per-patient therapy + response? (Determines stratification feasibility.)
3. **Data-sharing route** — email vs data-request form vs DUA vs IRB determination (UH policy).
4. **Which on-request sets he'll share**, and whether he'll be the **academic PI** on the dbGaP/EGA applications (cleanest, sidesteps for-profit DUL risk).

---

## 8. Honest caveats & risks
- **"On request" ≠ guaranteed** — journal boilerplate; realistically obtainable only via the collaboration.
- **DUL/NPU risk** — dbGaP/EGA controlled sets may bar a for-profit requester → route through Mohan.
- **PRECISESADS is consortium-controlled** — EGA DAC can be selective (GDPR); weeks-long.
- **Unpublished in-house data (transcriptome/WGS) is not shareable** — exclude from asks.
- **Not-located papers (6)** — access tier unknown until full-text DA statements are read.
- **Scale/type** — the LN urine cohorts are small (23–280) cross-sectional; the high-value data is the outcome-labeled longitudinal sets, which are exactly the on-request tier.

---

## 9. Recommended first moves
1. **Take the open data now** (§3a) — including checking our S3 ImmPort for SDY997 and pulling Perez scRNA (GSE174188).
2. **File the EGA application** (we have the account) for PRECISESADS transcriptome+genotype.
3. **In the Mohan call:** answer the four §7 questions, agree him as **academic PI** for dbGaP/EGA, and name the **on-request** sets we want (belimumab, IBD, spatial) under a DUA.
4. **Defer HOC** until a specific gap is identified.
