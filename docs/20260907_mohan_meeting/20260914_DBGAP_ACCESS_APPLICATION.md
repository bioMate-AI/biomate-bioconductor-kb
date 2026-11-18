# dbGaP Controlled-Access Application — package

Date 2026-09-14. For submitting Data Access Requests (DARs) to the resources below.
dbGaP access is **free** (no data fee); the gate is eligibility + the dataset's Data Use
Limitations (DUL). Pull each study's **DUC PDF** to confirm the DUL abbreviations before
submitting — especially whether any is **NPU (non-profit use only)**, which would block a
for-profit requester and force the academic-PI route.

## Resources requested

| Accession | Study | What we need | Note |
|---|---|---|---|
| **phs001457.v1.p1** | AMP RA/SLE (lupus nephritis) | **Renal single-cell RNA-seq** + clinical (the data behind Mohan's urine+scRNA papers) | **Mohan is an AMP data contributor** → cleanest path is applying *through him* (UH academic PI); he may already hold access |
| **phs002812.v1.p1** | Perez et al., "Multiplexed scRNA-Seq… Correlates of SLE" | **Genotype only** (for cis-eQTL) | The **scRNA is already OPEN on GEO GSE174188** — download that free; dbGaP only for the paired genotype |

*(EGA `EGAS00001003662` — PRECISESADS SLE RNA-seq+genotype — is a separate EGA application, not dbGaP; covered elsewhere.)*

## Research Use Statement (≤2200 char — ready to paste)

> We request access to build and validate computational methods for lupus and autoimmune
> research: an integrative single-cell foundation model and a human-genetics–anchored
> target-prioritization framework, applied to systemic lupus erythematosus (SLE) and lupus
> nephritis (LN). Using the requested single-cell/tissue transcriptomes and paired genotypes,
> we will (1) learn batch-corrected cell-state representations across peripheral-blood and
> renal immune compartments and benchmark them against standard methods (PCA, scVI) on
> leave-study-out splits; (2) map cell-type–specific and context-specific cis-eQTL to
> distinguish genetically supported candidate driver genes from disease-associated bystanders,
> and calibrate a null-controlled target-confidence score; and (3) evaluate molecular-endotype
> and treatment-response stratification as held-out validation. All analyses use de-identified
> individual-level data in aggregate within a secure, access-controlled computing environment.
> We will not attempt to re-identify participants, will not link or combine datasets in any way
> that could enable re-identification, and will not redistribute individual-level data. Use
> remains consistent with the study's Data Use Certification, the consent-based Data Use
> Limitations, and the NIH Genomic Data Sharing Policy. Findings will support methods
> development and translational lupus target discovery.

## Non-technical (lay) summary (≤1100 char)

> Lupus is a highly variable autoimmune disease. A central problem is telling which molecular
> changes actually drive the disease — and could be drug targets — from those that are merely
> downstream effects, and matching each patient to the right treatment mechanism. We are
> building computer methods that combine single-cell measurements with genetic data to identify
> genetically supported drug targets and to group patients by disease mechanism. The requested
> lupus data lets us test whether these methods hold up on independent patient groups. We work
> only with de-identified data in a secure system and never attempt to identify individuals.

## Eligibility & submission checklist
- **Requesting PI** with an **eRA Commons** account + an institutional **Signing Official** registered in dbGaP.
- **Local IRB** approval or documented non-human-subjects/self-certification.
- Signed **Data Use Certification**; **GDS-compliant Data Management & Security** attestation; secure environment.
- Confirm the **DUL** from each DUC PDF: if **GRU/HMB/DS(lupus)** → for-profit generally OK; if **NPU** → BioMate ineligible as requester.

## Two routes (pick per dataset once DUL is known)
1. **BioMate as requester** — needs our Signing Official + eRA Commons; works only if DUL is not NPU.
2. **Via Mohan (UH academic PI)** — cleanest for **phs001457** (he's an AMP contributor); BioMate listed as an approved internal collaborator/downloader. This is the collaboration path and sidesteps the for-profit-DUL risk.

## Honest caveats
- The DUL abbreviations were not on the public study page; they must be read from each **DUC PDF** before submitting (esp. NPU).
- dbGaP approval is typically **weeks** (DAC review).
- For Perez (phs002812), only apply if we need the **genotype**; the expression is free on GEO GSE174188.
