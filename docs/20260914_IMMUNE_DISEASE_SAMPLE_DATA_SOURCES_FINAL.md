# Immune-disease sample & data sources — FINAL consolidated report

Date 2026-09-14. Definitive reference for sourcing **patient samples and cohort data** to
validate immune targets/biomarkers as a for-profit (BioMate), across the full immune-disease
range. Two halves: (A) population biobanks + disease-specific consortia (this report), and
(B) commercial specimen vendors (separate menu, `20260914_LUPUS_IBD_SAMPLE_SOURCING_MENU.md`,
being finalized by the vendor-research fleet). Every fact sourced; "verify" flags where public
pages didn't confirm exact terms.

Scope of "immune-relevant diseases": autoimmune/rheumatic (SLE/LN, RA, PsA, Sjögren's, SSc,
vasculitis/ANCA, MG, autoimmune thyroid), demyelinating (MS), endocrine autoimmune (T1D),
IBD (UC/Crohn's), allergy/atopy (asthma, atopic dermatitis, food allergy), infection/vaccine
immunology, immuno-oncology (checkpoint response + irAE), primary immunodeficiency.

---

## A. Population biobanks — cover ALL immune diseases as coded phenotypes (data-rich)

| Resource | For-profit access? | What (immune coverage) | Route / cost / timeline | IRB |
|---|---|---|---|---|
| **NIH All of Us** | **YES, conditional** on a company **DURA** | De-identified **EHR + surveys + genomics (WGS, long-read, arrays)** for essentially all immune-mediated diseases (SLE, LN, UC, Crohn's, RA, MS, T1D, psoriasis, asthma) in one cohort. **Data only** — physical samples need a separate competitive **X01 (PAR-27-069)**. | DURA (signing-official; **weeks-to-months**) → Workbench **free + $300 credits**, then **GCP pay-as-you-go**. | Data de-identified; program doesn't mandate IRB (check local); X01 samples carry NIH human-subjects rules. |
| **UK Biobank** | **YES** (commercial OK; insurance sector excluded) | ~500k: linked **health records + WGS/WES + Olink + imaging**, immune diseases as **ICD-coded** phenotypes; **data AND physical biosamples**. | AMS portal + MTA; **tiered fees ~£3k/£6k/£9k per 3 yr (+£1k)**; **~15 weeks**. | RTB ethics (REC 11/NW/0382) covers applicants. |

*Both are population-scale → validate across many indications from one account. Data, not fresh samples.*

---

## B. Disease-specific immune consortia / biobanks

| Resource | Disease | What's available | For-profit access | Route / cost / timeline | Source |
|---|---|---|---|---|---|
| **USIDNET** (registry + **Cell Repository**) | Primary immunodeficiency | Registry data (free); **DNA + functional lymphoid cell lines** | **YES — academic AND commercial, "modest cost"** | Statement of Research Intent + Assurance; fast | [NIAID USIDNET Cell Repository](https://www.niaid.nih.gov/research/usidnet-cell-repository) |
| **Accelerated Cure Project (ACP)** | MS + demyelinating + controls | 3,200+ participants: **blood samples + deep clinical/phenotype data** | **YES — "available to any scientist worldwide," low-cost** | ACP researcher portal application | [ACP Researchers](https://www.acceleratedcure.org/research/researchers/) |
| **iConquerMS** | MS | Patient-reported REAL-MS data + blood/saliva biospecimens; recruitment | Yes (incl. industry) | via ACP/iConquerMS | [iConquerMS](https://www.acceleratedcure.org/iconquerms/) |
| **nPOD** | T1D (+ diabetes) | **Human pancreas + spleen + pancreatic-lymph-node tissue** + data — unique immune-tissue resource | Worldwide distribution; application-based *(verify for-profit terms)* | online proposal (OPPA); competitive (scarce tissue) | [nPOD](https://npod.org/about/t1d-research-community/) |
| **T1D Exchange Biobank** | T1D | 2,200 participants: **biospecimens + data**, browsable | Nonprofit; portal request *(verify for-profit terms)* | web portal | [T1D Exchange](https://clinicaltrials.gov/study/NCT04629586) |
| **TrialNet** | T1D (prevention) | Trial samples/data | **Academic-led** ancillary studies (industry via collab) | ancillary-study application | [TrialNet](https://link.springer.com/article/10.1007/s00125-017-4384-2) |
| **NHLBI BioLINCC** (incl. **SARP** asthma) | Asthma + cardiopulmonary/immune | Data + biospecimens from many NHLBI studies | **YES — external incl. industry** | BioLINCC request; DUA/MTA; IRB determination | [SARP III](https://www.sciencedirect.com/science/article/pii/S2213219817305263) |
| **ImmPort** | **Broad immune** (vaccine, infection, allergy, autoimmune) | **Open** immune study data (1,500 studies, 195k subjects) | **YES — open, free, no application** | direct download; **already in our S3 (DR66)** | ImmPort / our S3 |
| **AMP RA/SLE** | RA + lupus | Synovial + renal single-cell + clinical | **Free data** via ImmPort/ARK; genotype **controlled** (dbGaP phs001457) | ImmPort download / dbGaP DAR (academic-PI cleaner) | dbGaP |
| **IBD Plexus / SPARC** | IBD (UC/Crohn's) | Rich **data + biosamples** | **YES — but only via industry membership/CDA** (academic RFP excludes for-profit) | membership + DUA/MTDA + data give-back; **industry fee not public**; IRB for biosamples | CCF |
| **Lupus Nexus / DREAM** | SLE/LN | **Biosamples + data**, industry-inclusive | **YES** (industry-inclusive) | portal-gated terms (fees/timeline unverified) | LRA |
| **NIDDK Central Repository** | T1D, IBD, immune-metabolic | **Biosamples + data** | **YES** | request portal; **published per-specimen fees**; NIST 800-171 attestation (Apr 2026) | NIDDK |

*Immuno-oncology / irAE: no single consortium biobank — sourced via commercial vendors + trial data (TCGA/clinical-trial correlatives).*

---

## C. Disease × source matrix (where to go per indication)

| Disease | Directly industry-open, low friction | Application (industry-eligible) | Population data |
|---|---|---|---|
| SLE / LN | ImmPort | AMP (dbGaP), commercial vendors | All of Us, UK Biobank |
| RA / PsA | ImmPort | AMP (dbGaP), vendors | All of Us, UK Biobank |
| MS | **ACP / iConquerMS** | — | All of Us, UK Biobank |
| T1D | — | nPOD, T1D Exchange (BioLINCC-style) | All of Us, UK Biobank |
| IBD (UC/Crohn's) | ImmPort | IBD Plexus/SPARC, vendors | All of Us, UK Biobank |
| Asthma / allergy | ImmPort | **NHLBI BioLINCC (SARP)**, vendors | All of Us, UK Biobank |
| Primary immunodeficiency | **USIDNET** | — | — |
| Infection / vaccine | **ImmPort** | — | All of Us |
| IO / irAE | — | commercial vendors + trial correlatives | All of Us, UK Biobank |

---

## D. Access reality — three friction tiers

1. **No collaborator, low/zero cost, fast:** ImmPort (open, already held), USIDNET (PID, modest cost), ACP (MS, low cost). Just an SRI/assurance or nothing.
2. **Direct industry application (weeks-to-months, fee/DUA):** All of Us (DURA), UK Biobank (fees), NHLBI BioLINCC (SARP), nPOD, T1D Exchange, IBD Plexus, commercial vendors (purchase/MTA).
3. **Need an academic PI/collaborator:** AMP (controlled dbGaP), TrialNet, academic disease registries — where a partner like Mohan helps.

**Cross-cutting:** IRB determination (usually "not human subjects" for de-identified data/samples) + MTA/DUA + per-source consent/commercial-use check.

---

## E. Recommendations

- **Start now, no dependencies:** exploit **ImmPort** (in our S3), and open a **USIDNET** (PID) and **ACP** (MS) request — all industry-open at zero/modest cost.
- **Begin the long-pole applications in parallel:** the **All of Us DURA** (weeks-to-months; unlocks genomics-rich EHR across every immune disease) and **UK Biobank** — both are data goldmines for computational cross-cohort validation.
- **For physical samples of a specific indication:** commercial vendors (Section B menu) for on-demand purchase; NHLBI BioLINCC / nPOD / T1D Exchange for consortium samples.
- **Reserve the collaborator route (Mohan / academic PI)** for the controlled sets (AMP dbGaP) and the on-request outcome-labeled cohorts — not needed for the open/direct sources above.
- **Bottom line:** for validation data and samples across the immune-disease range, BioMate is **not dependent on any single collaborator** — multiple industry-open and direct-application sources cover it; a collaborator only accelerates the controlled/on-request tier.
