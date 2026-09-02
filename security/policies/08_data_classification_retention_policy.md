# Data Classification, Retention & Disposal Policy

| | |
|---|---|
| **Version** | 0.1 DRAFT |
| **Owner** | `[CONFIRM: Security owner]` |
| **Effective date** | `[CONFIRM]` |
| **Review cadence** | Annual |

## 1. Purpose
Define how BioMate classifies data by sensitivity and how long data is retained and how it is disposed of. Supports CC6.5 (and Confidentiality criteria if scope expands) and the HIPAA track.

## 2. Scope
All data processed or stored by the BioMate AI Assistant Services System.

## 3. Data classification
| Class | Examples | Handling |
|---|---|---|
| **Restricted** | Credentials/secrets, any PHI a user uploads, encrypted API keys | Encrypted at rest + in transit; least-privilege access; audit-logged; PHI stripped from LLM inputs |
| **Confidential** | User account data, customer research data (omics, chemistry, de-identified clinical metadata), workflow outputs, billing data | Encrypted; access limited to authenticated owner + authorized personnel |
| **Internal** | Application logs, operational config | Access limited to personnel |
| **Public** | Marketing site content, public docs | No restriction |

## 4. Policy statements
1. **PHI minimization.** BioMate does not require PHI to function. A PHI-detection guardrail strips 18-identifier patterns (SSN, DOB, MRN, Patient ID, NPI, insurance) from text before LLM processing and logs a hash rather than the value. Users are responsible for uploading appropriately de-identified data (see CUEC and Acceptable Use).
2. **Encryption.** Restricted/Confidential data is encrypted at rest (AES-256/KMS) and in transit (TLS 1.2+) per the Encryption & Key Management Policy.
3. **Retention.**
   - Audit logs: 90 days hot (PostgreSQL) + 6 years cold (S3 Glacier IR).
   - Customer research data & account data: `[CONFIRM: retention period and deletion-on-request process]`.
   - Backups: `[CONFIRM retention]`.
4. **Disposal.** Data deletions are performed through defined processes and, for PHI, logged (`data.phi.delete`). Asset/data disposal is `[CONFIRM: tracked in ticketing with an ID]`.
5. **Data location.** Restricted/Confidential data resides in AWS (RDS, S3, ElastiCache) in us-west-2 (us-east-1 for cryo-EM). No production data stored onsite `[CONFIRM]`.

## 5. Roles & responsibilities
- **Security owner** — maintains classification and retention schedules.
- **Engineering** — implements retention/disposal in the platform.

## 6. Enforcement & 7. Review
Per the Information Security Policy. Reviewed annually.
