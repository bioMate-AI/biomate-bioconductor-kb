# Vendor / Third-Party Risk Management Policy

| | |
|---|---|
| **Version** | 0.1 DRAFT |
| **Owner** | `[CONFIRM: Security owner]` |
| **Effective date** | `[CONFIRM]` |
| **Review cadence** | Annual (vendor reviews at least annually) |

## 1. Purpose
Ensure third parties and subservice organizations that access, process, or store BioMate data, or that operate controls on BioMate's behalf, are assessed and monitored commensurate with risk. Supports CC9.2.

## 2. Scope
All vendors, subprocessors, and subservice organizations supporting the BioMate AI Assistant Services System.

## 3. Policy statements
1. **Vendor inventory.** A vendor register is maintained listing each third party, the data it can access, its level of access, and its criticality. Current inventory (to be made authoritative): AWS, Stripe, Google (Gemini), OpenAI (GPT-4o), AWS SES, Google Analytics, Vanta, Workstreet `[CONFIRM role]`.
2. **Risk ranking.** Each vendor is risk-ranked by data sensitivity and access level (e.g., AWS = critical subservice org; Stripe = payment data; LLM providers = process user prompt text).
3. **Due diligence.** For medium/high-risk vendors, a security review is performed at onboarding and at least annually, collecting evidence such as SOC 2 / ISO reports (e.g., AWS via AWS Artifact) and reviewing data-use/retention terms.
4. **Subservice organizations.** AWS is treated as a subservice organization (carve-out method `[CONFIRM]`); the CSOCs BioMate relies on are documented in the System Description (DC7) and monitored via AWS's SOC 2/ISO reports.
5. **AI/LLM providers.** Google, OpenAI, and AWS Bedrock are reviewed specifically for data handling: whether prompt/response data is used for training, retention windows, and regional processing. Claude is routed via AWS Bedrock under the AWS BAA.
6. **Data protection agreements / BAAs.** DPAs and, where PHI is processed, BAAs are executed with applicable vendors (AWS BAA covers RDS, S3, Bedrock, ElastiCache, Lambda per current configuration). `[CONFIRM other DPAs/BAAs.]`
7. **Offboarding.** On vendor termination, access and data are removed and confirmed.

## 4. Roles & responsibilities
- **Security owner** — maintains the register, performs reviews, tracks BAAs/DPAs.

## 5. Enforcement & 6. Review
Per the Information Security Policy. Reviewed annually.
