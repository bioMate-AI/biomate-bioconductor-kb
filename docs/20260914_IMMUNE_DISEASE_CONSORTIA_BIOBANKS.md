# Disease-specific immune consortia / biobanks — sample & data access

Date 2026-09-14. Companion to the vendor + population-biobank menu
(`20260914_LUPUS_IBD_SAMPLE_SOURCING_MENU.md`). Covers the disease-specific immune
consortia across the immune-disease range. Every row sourced; "verify" where the direct
industry route wasn't confirmable from public pages.

| Resource | Disease | What's available | Direct for-profit access? | Route / cost / notes | Source |
|---|---|---|---|---|---|
| **USIDNET** (registry + **Cell Repository**) | Primary immunodeficiency (inborn errors of immunity) | De-identified registry data (free); **DNA + functional lymphoid cell lines** | **YES — explicitly academic AND commercial** | "available at **modest cost** to qualified investigators in academic and commercial organizations"; sign a **Statement of Research Intent** + Assurance | [NIAID USIDNET Cell Repository](https://www.niaid.nih.gov/research/usidnet-cell-repository) |
| **Accelerated Cure Project (ACP) Repository** | MS + related demyelinating + controls | 3,200+ participants: **blood-derived samples + detailed clinical/phenotype data** | **YES — "available to any scientist worldwide"** | rapid, **low-cost**; apply via ACP researcher portal | [ACP Researchers](https://www.acceleratedcure.org/research/researchers/) |
| **iConquerMS** | MS | Patient-reported REAL-MS data + blood/saliva biospecimens; recruitment access | Yes (researchers incl. industry) | via iConquerMS/ACP; patient-powered network (8,500+) | [iConquerMS](https://www.acceleratedcure.org/iconquerms/) |
| **nPOD** | T1D (+ other diabetes) | **Human pancreas + spleen + pancreatic-lymph-node tissue** + de-identified data — unique immune-tissue resource | Distributes **worldwide**; application/collaboration-based (verify for-profit terms) | online project proposal (OPPA); tissue is scarce → competitive review | [nPOD](https://npod.org/about/t1d-research-community/) |
| **T1D Exchange Biobank** | T1D | 2,200 participants: **biospecimens + associated data**, browsable | Nonprofit; **web portal to browse + request** (verify for-profit terms) | request via portal | [T1D Exchange Registry](https://clinicaltrials.gov/study/NCT04629586) |
| **TrialNet** | T1D (prevention) | Samples/data from prevention trials | Usually **academic-led ancillary studies** (industry via collaboration) | ancillary-study application | [TrialNet overview](https://link.springer.com/article/10.1007/s00125-017-4384-2) |
| **SARP** (Severe Asthma Research Program) | Severe asthma | 700+ participants: clinical + molecular/cellular; **samples/data via NHLBI BioLINCC** | Via **NHLBI BioLINCC** — accepts external incl. **industry** by application | BioLINCC request (DUA/MTA) | [SARP III cohort](https://www.sciencedirect.com/science/article/pii/S2213219817305263) |
| **NHLBI BioLINCC** | Asthma + cardiopulmonary/immune | Data + biospecimens from many NHLBI studies (incl. SARP) | **Yes — external incl. industry** by application | online request; DUA/MTA; IRB determination | (BioLINCC portal) |
| **ImmPort** | **Broad immune** (vaccine, infection, allergy, autoimmune) | **Open** immune study data (1,500 studies, 195k subjects) | **YES — fully open, free, no application** | direct download; **we already hold full DR66 in our S3** | (ImmPort / our S3) |
| **AMP RA/SLE** | RA + lupus | Synovial + renal single-cell + clinical | Controlled (dbGaP phs001457) — see dbGaP plan | apply via dbGaP (academic-PI route cleaner) | — |

## Key findings (my half)
- **Explicitly industry-open, low friction:** **USIDNET** (PID cell lines/DNA, modest cost, commercial OK), **ACP** (MS, "any scientist," low-cost), **ImmPort** (broad immune, open/free — already in our S3).
- **Industry via application (doable, more process):** **NHLBI BioLINCC** (asthma SARP + more), **nPOD** (T1D tissue — competitive), **T1D Exchange** (portal).
- **Academic-led (need collaborator):** **TrialNet**; **AMP** (controlled).
- **Gap:** no single consortium biobank for **immuno-oncology / irAE** — that's commercial vendors + trial data.

## Cross-cutting (same as vendor menu)
IRB determination (usually "not human subjects" for de-identified), MTA/DUA, and per-source consent/commercial-use check. "Modest cost" (USIDNET/ACP) ≠ free but far below commercial-vendor per-sample pricing.
