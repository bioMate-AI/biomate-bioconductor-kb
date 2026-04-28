# Regulatory Compliance Roadmap — BioMate AI
## 2026-04-28

## Executive Summary

BioMate is currently ~15–20% of the way to full 21 CFR Part 11 compliance. Rather than treating compliance as a $1.5M greenfield project, this plan identifies what BioMate already has, what AWS provides for free as part of our existing infrastructure, and what needs to be built incrementally. The realistic path to a credible "Part 11-ready" market claim is **18–24 months and $350–600K** — roughly half the gap analysis estimate — by reusing existing components intelligently.

---

## 1. What BioMate Already Has (Reuse — $0)

| Existing Component | How It Maps to Compliance | Gap to Close |
|---|---|---|
| **Audit trail logging** (nextflow_executor.py) | 21 CFR 11.10(e) — computer-generated time-stamped records | Needs immutability + original/new value capture |
| **QC logging** (evidence-graded Gold/Silver/Bronze with citations) | ALCOA+ "Attributable, Legible, Contemporary, Accurate" | Already best-in-class; just needs export format |
| **User ID / session management** | 11.10(d) — system access limited to authorized users | Needs MFA, password policy, session timeout |
| **IND §2.6.1 LLM narrative** (already built + tested) | Module 2.6.1 documentation requirement | Complete — extend to §2.6.2–2.6.7 |
| **Methods section auto-generation** | "Contemporaneous, original" documentation of methods | Complete for existing workflows |
| **S3 output storage** | 11.10(c) — protection of records | Enable S3 Object Lock (WORM); 1 day of work |
| **Nextflow parameter versioning** | 11.10(k) — controls to prevent unauthorized changes | Already captured in run records |
| **JWT auth + PostgreSQL user table** | Identity management foundation | Needs MFA layer on top |

---

## 2. What AWS Gives Us For Free (Infrastructure Layer)

AWS is itself ISO 27001, SOC 2 Type II, and HIPAA certified. BioMate already runs on AWS. We can inherit these certifications by properly **using** AWS compliance features:

| AWS Service | Compliance Feature | Cost | Effort |
|---|---|---|---|
| **AWS CloudTrail** | Immutable system-level audit log (all API calls, user actions) — directly satisfies 11.10(e) at infrastructure level | ~$2/month | 1 day to enable + configure |
| **S3 Object Lock** | WORM (Write Once Read Many) storage for workflow outputs — prevents deletion/modification | Included in S3 | 1 day to enable on output bucket |
| **AWS KMS** | Key management for electronic signatures — satisfies 11.100 cryptographic binding requirement | ~$1/key/month | 2–3 days to wire up |
| **Amazon Cognito** | MFA enforcement, password complexity policy, session timeout — satisfies 11.10(d) | ~$0.0055/MAU | 1 week to migrate auth |
| **CloudWatch Logs** | Centralized, immutable application log aggregation | ~$0.50/GB | 2 days to wire |
| **AWS Backup** | Automated backup with documented retention policy | Minimal | 1 day to configure |
| **AWS Config** | Configuration change tracking — supports change control SOP | ~$2/rule/month | 1 day to enable |

**Total additional AWS cost: ~$50–150/month.** This alone covers the infrastructure layer of Part 11.

---

## 3. What Needs to Be Built (Increment on Existing Code)

### Phase 1 — Quick Wins (1–3 months, ~$30–50K eng time)

These are extensions to code that already exists.

**1.1 Immutable Application Audit Trail**
- Current: `audit_trail` table in PostgreSQL, admin can delete
- Change: switch to append-only audit log with SHA-256 hash chain (each entry hashes previous)
- Location: `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` + new `audit_log` table
- Captures: user_id, timestamp (UTC ISO 8601), action, workflow_id, parameter_before, parameter_after, qc_outcome, output_path
- Export: JSON + CSV download endpoint for regulatory review
- Effort: 1 engineer, 2–3 weeks

**1.2 Electronic Signature for Workflow Approvals**
- Current: user clicks "Confirm & Run" — no cryptographic record
- Change: when user confirms a run, generate a signed approval record using AWS KMS:
  - `sign(user_id + workflow_id + parameters_hash + timestamp)` stored with run record
  - Signature verifiable without private key exposure
- This satisfies 21 CFR 11.100 — signature inseparable from record
- Effort: 1 engineer, 1 week (KMS API is straightforward)

**1.3 Cognito Migration (MFA + Password Policy)**
- Current: custom JWT auth in `frontend/server/routes.ts`
- Change: migrate to AWS Cognito as identity provider; keep existing JWT flow as Cognito-issued tokens
- Cognito enforces: MFA (TOTP or SMS), password complexity (min 12 chars, mixed case, symbols), session timeout (8h configurable), account lockout after 5 failed attempts
- Effort: 1 engineer, 1.5 weeks

**1.4 Enable S3 Object Lock + CloudTrail**
- S3 Object Lock on `biomate-workflow-outputs` bucket: Compliance mode, 7-year retention
- CloudTrail enabled in all regions with CloudWatch Logs integration
- Effort: DevOps, 2 days

**Phase 1 total: ~6 weeks, 1–2 engineers. Achieves: immutable audit trail, electronic signature, MFA, WORM storage.**

---

### Phase 2 — Documentation & Validation (3–9 months, ~$100–150K)

These do not require heavy new code — they require documented processes and structured testing.

**2.1 System Validation Documentation (IQ/OQ/PQ)**
- IQ (Installation Qualification): Document the AWS infrastructure, container versions, database schema, configuration files. Snapshot and version everything.
- OQ (Operational Qualification): Write test protocols for every Part 11 control: audit trail entries appear on correct actions, electronic signatures verify correctly, MFA enforces on login, session expires at timeout, no user can delete audit trail entries.
- PQ (Performance Qualification): Run OQ protocols in production with real users; document pass/fail; get sign-off.
- Tool: Use **Vanta** (~$20K/year) to automate evidence collection and track compliance controls continuously. Vanta monitors your AWS environment and flags gaps automatically.
- Effort: 1 compliance consultant (contract, ~$150/hr), 200–300 hours over 6 months

**2.2 Core SOPs (20 priority SOPs)**
Rather than 50+, focus on the 20 that matter for pharma procurement:

| SOP | Purpose |
|---|---|
| SOP-001: User Access Management | How accounts are created, modified, deactivated |
| SOP-002: Password & MFA Policy | Password requirements, MFA enrollment, account lockout |
| SOP-003: Audit Trail Review | Periodic review of audit log integrity |
| SOP-004: Workflow Execution | How validated workflows are run, confirmed, QC-checked |
| SOP-005: Electronic Signature | When and how signatures are applied to records |
| SOP-006: Data Backup & Recovery | Backup schedule, retention, recovery testing |
| SOP-007: System Change Control | How software updates are tested and deployed |
| SOP-008: Incident Response | What to do when a security event occurs |
| SOP-009: Training & Competency | How users are trained on the system |
| SOP-010: Record Retention | How long records are kept and how they are retrieved |
| SOP-011: QC Threshold Review | Periodic review of Gold/Silver/Bronze thresholds |
| SOP-012: Workflow Validation | How new workflows are validated before production |
| SOPs 013–020: domain-specific | ADMET, PBPK, genomics, cryo-EM workflow-specific |

Effort: 1 regulatory writer (contract), 3–4 months part-time

**2.3 Workflow Validation Documentation (ADMET + PBPK first)**
- For each of the 4 priority workflows (ADMET, PBPK, genomics WGS, cryo-EM SPA):
  - Validation protocol: what is being validated, acceptance criteria
  - Reference dataset: known compounds with published ADMET values (ChEMBL, DrugBank)
  - Performance report: BioMate predictions vs. reference; accuracy, recall, precision
  - Sensitivity analysis: how output changes with ±10% input variation
  - Limitation statement: where the model does not apply
- BioMate already has the evaluation framework (`evaluation/` directory). This is structured documentation of what the code already does.
- Effort: 2 scientists, 3 months each workflow (parallel)

---

### Phase 3 — Third-Party Certification (9–18 months, ~$60–100K)

**3.1 SOC 2 Type II**
- Prerequisite: Phase 1 controls live for 12 months (audit period)
- Auditor: Drata ($15K/year platform) + Big 4 firm ($30–50K audit fee)
- Timeline: Start audit period Month 1; receive report ~Month 14
- What it proves: security, availability, processing integrity controls are operational

**3.2 ISO 27001:2022**
- Builds on SOC 2 evidence; additional scope includes information security governance
- Auditor: BSI, Bureau Veritas, or similar (~$15–25K)
- Can run concurrently with SOC 2 Type II using shared evidence

**3.3 "21 CFR Part 11 Readiness Assessment" (not a certification — a deliverable)**
- Hire regulatory affairs consulting firm (e.g., Halloran, Cognizant Regulatory) to conduct a formal gap assessment
- Output: a written "readiness letter" BioMate can share with pharma customers
- Cost: $25–40K
- This is what pharma procurement actually asks for; there is no FDA "certification" for software

---

## 4. What to Reuse vs. What to Buy vs. What to Build

| Need | Reuse | Buy (SaaS) | Build |
|---|---|---|---|
| Infrastructure audit trail | AWS CloudTrail | — | App-level hash-chain audit log |
| WORM storage | S3 Object Lock | — | — |
| MFA + password policy | — | AWS Cognito ($55/mo for 10K users) | — |
| Electronic signature | AWS KMS | — | Thin wrapper in Python (1 week) |
| Compliance monitoring | — | Vanta ($20K/yr) | — |
| SOP management | — | Notion / Confluence | — |
| Validation documentation | Existing eval/ framework | — | IQ/OQ/PQ docs from existing tests |
| SOC 2 audit | AWS infrastructure certs | Drata + Big 4 auditor | — |
| Workflow validation | Existing evaluation datasets | — | Structured performance reports |

**Don't build**: XML eCTD publisher, 21 CFR Part 11 certificate (doesn't exist), full LIMS, custom KMS — all have better off-the-shelf options.

---

## 5. Revised Cost & Timeline

| Phase | What | Cost | Duration | Outcome |
|---|---|---|---|---|
| Phase 1 | Immutable audit trail, e-signature, Cognito MFA, WORM storage | $30–50K eng | 1–3 months | "Part 11 controls implemented" |
| Phase 2 | IQ/OQ/PQ docs, 20 SOPs, ADMET+PBPK validation reports | $100–150K contracts | 3–9 months | "Validated platform with documented procedures" |
| Phase 3 | SOC 2 Type II + ISO 27001 + readiness letter | $60–100K | 9–18 months | "SOC 2 certified, Part 11 ready" market claim |
| **Total** | | **$190–300K** | **18–24 months** | **Credible pharma procurement** |

Compare: original gap analysis estimate was $1.1–1.9M over 36 months. The reduction comes from leveraging AWS compliance infrastructure and BioMate's existing audit trail / evaluation code.

---

## 6. Market Claim Timeline

| Milestone | What You Can Say |
|---|---|
| **Now** | "Audit trail on every run · Evidence-graded QC · Submission-ready Methods section" |
| **Phase 1 complete** (3 mo) | "Immutable audit trail · Electronic run approval · MFA-enforced access · WORM output storage" |
| **Phase 2 complete** (9 mo) | "Validated platform · IQ/OQ/PQ documented · ADMET and PBPK performance benchmarked" |
| **Phase 3 complete** (18–24 mo) | "SOC 2 Type II certified · ISO 27001 certified · 21 CFR Part 11 ready — independently assessed" |

At Phase 3, BioMate can credibly approach pharma procurement, be included on vendor lists, and charge enterprise pricing for regulated-environment deployments.

---

## 7. IND Nonclinical Package Roadmap (Parallel Track)

This is independent of the compliance certifications — it's about content quality and coverage.

| Item | Status | Next step |
|---|---|---|
| §2.6.1 Introduction LLM narrative | ✅ Complete | — |
| §2.6.2 Pharmacology summary | ~70% | Add off-target safety pharmacology section |
| §2.6.3 Pharmacology tables | ~70% | Add standard CTD table formatting |
| §2.6.4 PK written summary | ✅ PBPK output → narrative pipeline | Add NCA-PK integration |
| §2.6.5 PK tables | ~60% | Standardize to FDA table format (ICH M4S) |
| §2.6.6 Toxicology summary | ~40% | Add repeat-dose and reproductive tox placeholders with citation-ready framing |
| §2.6.7 Toxicology tables | ~40% | Standardize Ames/DILI/hERG to ICH M4S format |
| **CTD-formatted DOCX export** | Partial (DOCX download exists) | Add CTD section numbering, pagination, table of contents |
| **Veeva Vault API push** | Not started | Medium-term: REST API integration to push documents into Vault workspace |

Target: by end of Phase 2 (9 months), a pharma customer can run ADMET + PBPK in BioMate and receive a complete CTD-formatted §2.6 nonclinical package ready for their RA team.

---

## 8. Decision Needed

1. **Phase 1 (3 months, ~$40K)** — Start now? The immutable audit trail + Cognito migration are the highest-ROI changes and create the foundation everything else builds on.

2. **Vanta subscription** — ~$20K/year, automates SOC 2 evidence collection and tracks compliance gaps. Worth starting early so the 12-month audit period begins sooner.

3. **Regulatory affairs consultant** — Hire a contract regulatory writer for SOPs and IQ/OQ/PQ templates. FDA regulatory affairs consultants charge $150–250/hr; 200 hours = $30–50K. This can run in parallel with Phase 1.
