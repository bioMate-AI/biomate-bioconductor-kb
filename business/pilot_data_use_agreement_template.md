# Data Use Agreement — Pilot Study

---

> **⚠ DRAFT — FOR LEGAL REVIEW ONLY**
>
> This document is a starting-point template prepared for internal review and has not been reviewed or approved by legal counsel. It does not constitute a legally binding agreement. Do not send to any external party until reviewed and approved by qualified legal counsel licensed in the applicable jurisdiction.

---

**DATA USE AGREEMENT (PILOT STUDY)**

This Data Use Agreement ("Agreement") is entered into as of the **Effective Date** set forth below, by and between:

**BioMate AI LLC**, a limited liability company organised under the laws of the State of Texas, with its principal place of business at [BioMate Address] ("BioMate"); and

**[Partner Institution Full Legal Name]**, a [type of institution, e.g., non-profit academic medical center / state university] located at [Institution Address] ("Institution").

BioMate and Institution are each referred to herein as a "Party" and collectively as the "Parties."

---

## 1. Parties and Authorized Representatives

**BioMate AI LLC**
Principal Contact: [BioMate CEO Full Name], Chief Executive Officer
Email: [email]
Address: [address]

**Institution**
Principal Investigator (PI): [PI Full Name], [Title]
Department: [Department Name]
Email: [PI institutional email]
Address: [Institution address]

---

## 2. Purpose

The sole purpose of this Agreement is to enable Institution to participate in a BioMate AI pilot study ("Pilot") for the purpose of evaluating BioMate's AI-driven bioinformatics workflow platform. The specific research direction covered by this Pilot is:

**[Select one — delete others, or specify custom scope below:]**
- [ ] RNA-seq differential expression analysis
- [ ] ADMET screening and molecular docking (drug discovery)
- [ ] Single-particle cryo-EM analysis (CryoSPARC SPA)
- [ ] Single-cell RNA-seq clustering and cell-type annotation
- [ ] DIA-LC-MS/MS proteomics QC and differential abundance analysis
- [ ] Other (specify): _______________________________________________

The Pilot period begins on **[Start Date]** and ends on **[End Date]** ("Pilot Period"), unless terminated earlier pursuant to Section 11 of this Agreement.

No data shared under this Agreement may be used for any purpose other than the Pilot analysis described in this Section.

---

## 3. Data Description

Institution may share the following categories of data with BioMate solely for the purposes described in Section 2:

| Field | Description |
|---|---|
| **Data type** | [e.g., genomic sequencing (FASTQ), proteomic (MaxQuant/DIA-NN output), cryo-EM micrographs (MRC/TIFF), single-cell count matrices] |
| **Format** | [e.g., FASTQ, CSV, MRC, HDF5] |
| **Estimated data volume** | [e.g., approximately 50 GB] |
| **Number of samples/files** | [e.g., 12 RNA-seq samples; 24 FASTQ files] |
| **Does the data contain Protected Health Information (PHI)?** | [ ] Yes — a separate BAA is required before any data transfer. [ ] No |
| **Does the data contain personally identifiable information (PII)?** | [ ] Yes — specify: __________________ [ ] No |
| **Is the data subject to additional regulatory requirements?** | [ ] HIPAA [ ] FERPA [ ] Export controls [ ] IRB protocol number: __________ [ ] None |

Institution warrants that it has the right to share the data described above under this Agreement, and that any necessary IRB approvals, consent waivers, or data access authorisations are in place prior to data transfer.

---

## 4. Data Handling

**Storage location:** Institution's data shall be stored in one of the following locations (select one):

- [ ] **Institution-controlled S3 bucket:** Institution provisions an Amazon S3 bucket in their own AWS account and grants BioMate time-limited, read-only access credentials during the Pilot Period only. BioMate will not copy or move data outside this bucket.
- [ ] **BioMate-managed S3 bucket:** BioMate provisions a dedicated S3 bucket in its AWS account for this Pilot. All data will be encrypted at rest (AES-256) and in transit (TLS 1.2 or higher). Access is restricted to BioMate personnel directly involved in the Pilot. Data will be permanently deleted within 14 days of Pilot completion or termination, and BioMate will provide written confirmation of deletion.

**Encryption:** All data is encrypted at rest using AES-256 and in transit using TLS 1.2 or higher, regardless of storage location.

**Access controls:** Access to Institution data is restricted to BioMate personnel directly involved in operating the Pilot. No third-party subcontractors will have access to Institution data without prior written consent from Institution.

**Compute environment:** Pilot workflows are executed on [AWS region: us-east-1 / us-west-2 — confirm] cloud infrastructure. No data is processed on shared or multi-tenant compute nodes that would permit access by other BioMate customers.

---

## 5. Data Retention and Deletion

BioMate shall retain no Institution data after completion or termination of the Pilot, except as set out in this Section.

- **Raw data** (FASTQ files, mass spectrometry output, micrographs, etc.): Permanently deleted from all BioMate systems within **14 calendar days** of Pilot completion or termination.
- **Analysis outputs** (QC reports, workflow logs, differential expression tables, annotated cell atlases, refined maps, etc.): These belong to Institution. BioMate will deliver all analysis outputs to Institution in a format agreed in advance (e.g., S3 transfer, HTTPS download link). BioMate retains no copies of analysis outputs after delivery, except for anonymised aggregate performance metrics (e.g., workflow run duration, step completion rates) that contain no Institution data or identifiable results.
- **Audit logs:** The computational audit log generated by BioMate's platform (tool versions, parameters, timestamps, QC gate evaluations) is delivered to Institution as part of the standard Pilot deliverables. BioMate may retain a copy of the audit log for internal QC purposes for up to 90 days, after which it is deleted.

BioMate will provide Institution with written confirmation of data deletion within 5 business days of completing deletion.

---

## 6. Pilot Evaluation Data

To measure the performance of the BioMate platform, Institution participants may be asked to complete brief in-product surveys at the end of each workflow run and at the end of the Pilot Period ("Evaluation Data"). Evaluation Data includes Likert-scale ratings, time estimates, and free-text responses submitted voluntarily by Institution personnel through the BioMate interface.

Evaluation Data is distinct from Institution research data. It does not include raw genomic, proteomic, or imaging files. BioMate may use aggregated, anonymised Evaluation Data to report pilot outcomes, improve the platform, and — with Institution's express written consent — include anonymised aggregate statistics in academic publications. Individual-level responses will not be attributed to Institution or any named individual without consent.

Participation in surveys is voluntary. Pilot participation is not contingent on completing any survey.

---

## 7. Permitted Use

BioMate may use Institution data solely for the purpose of executing the Pilot workflows described in Section 2.

BioMate expressly may **not**, without prior written consent from Institution's PI:

- Use Institution data to train, fine-tune, or evaluate any machine learning or AI model.
- Use Institution data as a benchmark for any internal or external performance evaluation.
- Include Institution data or Institution-specific results in any publication, conference presentation, marketing material, or case study.
- Share Institution data with any third party for any purpose.
- Retain Institution data beyond the retention periods specified in Section 5.

These restrictions survive termination of this Agreement.

---

## 8. Publication Rights

Institution retains all rights to publish, present, or otherwise disseminate the results of the Pilot analysis. BioMate makes no claim to authorship, data ownership, or intellectual property rights in any results derived from Institution data.

If Institution publishes research that made use of BioMate's platform during the Pilot, Institution agrees to consider acknowledging BioMate AI in the Acknowledgements section of the publication (e.g., "Bioinformatics analyses were performed using the BioMate AI platform (biomate.ai)."). This acknowledgement is requested but not required.

Institution shall notify BioMate at [BioMate email] when a manuscript that uses Pilot results is submitted for publication. BioMate may request to review the computational methods section for accuracy within 5 business days of notification, but has no right to delay or prevent submission.

---

## 9. Confidentiality

**Institution data:** BioMate shall treat all Institution data, including raw data, intermediate results, and analysis outputs, as confidential. BioMate will not disclose Institution data to any person or entity not directly involved in operating the Pilot, except as required by applicable law.

**BioMate platform:** Institution shall treat non-public details of the BioMate platform, including proprietary workflow logic, QC gate configurations, and pricing, as confidential.

The confidentiality obligations in this Section survive termination of this Agreement for a period of **two (2) years** from the Effective Date.

The following information is not subject to confidentiality obligations: (a) information that is or becomes publicly available through no fault of the receiving Party; (b) information the receiving Party independently developed without use of the disclosing Party's confidential information; or (c) information required to be disclosed by law or court order, provided the receiving Party gives the disclosing Party prompt written notice.

---

## 10. Limitation of Liability

THE BIOMATE PLATFORM IS PROVIDED "AS IS" FOR PILOT EVALUATION PURPOSES. TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, BIOMATE MAKES NO WARRANTIES, EXPRESS OR IMPLIED, REGARDING THE ACCURACY, COMPLETENESS, OR FITNESS FOR ANY PARTICULAR PURPOSE OF ANY WORKFLOW OUTPUT, QC REPORT, OR ANALYSIS RESULT.

IN NO EVENT SHALL EITHER PARTY BE LIABLE TO THE OTHER FOR INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES ARISING OUT OF OR RELATED TO THIS AGREEMENT, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGES. BIOMATE'S TOTAL LIABILITY UNDER THIS AGREEMENT SHALL NOT EXCEED [USD $1,000 / the total amount paid by Institution under this Agreement — select applicable, noting this is a no-cost pilot].

Nothing in this Section limits either Party's liability for: (a) gross negligence or wilful misconduct; (b) breach of confidentiality obligations in Section 9; or (c) a Party's indemnification obligations, if any, agreed separately in writing.

---

## 11. Termination

Either Party may terminate this Agreement at any time with **five (5) calendar days' written notice** to the other Party. Notice may be given by email to the contacts listed in Section 1.

Upon termination:

- BioMate will cease all processing of Institution data immediately.
- BioMate will deliver any completed analysis outputs to Institution within 5 business days.
- BioMate will permanently delete all Institution data from its systems within **14 calendar days** of the termination date and provide written confirmation.

Sections 5 (Data Retention), 6 (Pilot Evaluation Data), 7 (Permitted Use), 8 (Publication Rights), 9 (Confidentiality), and 10 (Limitation of Liability) survive termination of this Agreement.

---

## 12. Governing Law

This Agreement shall be governed by and construed in accordance with the laws of the **State of [Texas / to be confirmed by legal counsel]**, without regard to its conflict of law principles. Any disputes arising under this Agreement shall be resolved in the state or federal courts located in [County, Texas].

*Note to legal: confirm whether Institution's standard terms require their state's governing law or a mutual agreement on jurisdiction.*

---

## 13. Entire Agreement; Amendments

This Agreement constitutes the entire agreement between the Parties with respect to the subject matter hereof and supersedes all prior understandings, whether oral or written. This Agreement may not be amended except by a written instrument signed by authorised representatives of both Parties.

If Institution requires a Business Associate Agreement (BAA) under HIPAA (because data contains PHI), the BAA must be executed as a separate document and takes precedence over this Agreement with respect to PHI handling.

---

## Signatures

By signing below, each Party agrees to be bound by the terms of this Agreement.

**BioMate AI LLC**

Signature: ___________________________________

Printed Name: [BioMate CEO Full Name]

Title: Chief Executive Officer

Date: ___________________________________

---

**[Partner Institution Full Legal Name]**

Signature: ___________________________________

Printed Name: ___________________________________

Title: ___________________________________

Department: ___________________________________

Date: ___________________________________

---

---

## Pre-Send Checklist

The following items **must be completed** before this Agreement is ready to send to a pilot partner. Do not send until all items are checked.

### Parties and Contacts
- [ ] Fill in **BioMate's full legal address** (Section 1 and header)
- [ ] Fill in **BioMate CEO's full name** (Sections 1 and 13)
- [ ] Fill in **BioMate's designated contact email** for publication notifications (Section 8)
- [ ] Fill in **Institution's full legal name** — confirm the exact legal entity that should be party to the agreement (e.g., "The University of Texas Southwestern Medical Center" not "UT Southwestern")
- [ ] Fill in **PI's full name, title, department, and institutional email** (Section 1)
- [ ] Fill in **Institution's full mailing address** (Section 1)

### Purpose and Dates
- [ ] Select the correct **research direction** from the list in Section 2 (or write a custom scope)
- [ ] Confirm and fill in **Pilot Start Date** and **End Date** (Section 2)

### Data Description (Section 3)
- [ ] Fill in **data type** (e.g., genomic FASTQ, proteomic output, micrographs)
- [ ] Fill in **data format** (e.g., FASTQ, MRC, CSV)
- [ ] Fill in **estimated data volume** (GB)
- [ ] Fill in **number of samples/files**
- [ ] Confirm whether data contains **PHI** — if yes, a separate BAA must be executed before data transfer; do not proceed without it
- [ ] Confirm whether data is subject to an **IRB protocol** and record the protocol number
- [ ] Obtain Institution's confirmation that it has the right to share the data

### Data Handling (Section 4)
- [ ] Select **storage location** option (Institution-controlled S3 or BioMate-managed S3)
- [ ] Confirm the **AWS region** that will be used for compute (Section 4)

### Legal Review
- [ ] **Attorney review:** Have this Agreement reviewed by qualified legal counsel before sending. This is a template only.
- [ ] **Confirm governing law:** Check whether Institution's policies require a specific governing state or dispute resolution mechanism (Section 12) — fill in the state and county.
- [ ] **Liability cap:** Confirm the appropriate liability cap amount in Section 10, or remove if this is a no-cost pilot with no payments.
- [ ] **Confirm BAA requirement:** If there is any possibility the data contains PHI, initiate a BAA process in parallel.
- [ ] Check for any Institution-specific contracting requirements (e.g., some academic medical centres require agreements to be executed through their Office of Research or Sponsored Programs — do not send directly to the PI in those cases).

---

> **⚠ DRAFT — FOR LEGAL REVIEW ONLY**
>
> This document is a starting-point template and has not been reviewed or approved by legal counsel. Do not send to any external party without prior legal review.

---

*BioMate AI LLC | biomate.ai | Pilot Program 2026 | Confidential*
