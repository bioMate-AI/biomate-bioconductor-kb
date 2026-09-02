# Scoping Intake Preparedness Questionnaire — Answers

**Source workbook:** `[Client Name] - [Year] - [Scoping Intake Preparedness Questionnare].xlsx`
**Filled copy produced:** `03_scoping_questionnaire_FILLED.xlsx` (same folder)
**Answers grounded in:** repo/config facts (see `docs/20260412_SOC2_HIPAA_AUDIT_FRAMEWORK.md` and code citations). `[CONFIRM]` = management/IT must verify before returning to Sentry.

---

## Introduction tab — Audit Scope
- **Client:** BioMate AI LLC
- **Engagement:** 2026 — SOC 2 — **Type 2** (first examination; `[CONFIRM]` Type 1-then-2 vs. straight Type 2 — see `00` plan §5)
- **Review Period / As-of Date:** `[CONFIRM]` — to be set once Vanta Control Readiness ≥ 85% (no remediation window)
- **TSC:** **Security (Common Criteria) only** per SOW

---

## Tab: Audit Preparedness

| # | Question | Answer |
|---|---|---|
| 1 | **System Description drafted & reviewed?** | 🟡 **In progress.** Management draft prepared (`04_SYSTEM_DESCRIPTION_DRAFT.md`) written from our real AWS architecture — NOT Vanta template language. First-person language avoided; no "industry-best"/aspirational phrasing. CUECs reviewed and reduced to genuine dependencies (`05`). Still needs management to replace `[CONFIRM]` facts and sign. |
| 2 | **Control customization — control set reviewed & updated to reflect reality?** | 🟡 **Partial / highest-risk item.** Strong technical controls exist in code + AWS, but the **Vanta control set must be reconciled line-by-line to operational reality before the observation period starts.** Explicit watch: do **not** assert MDM (none found), or claim VPN/quarterly access reviews/MFA-in-prod unless each is actually operating (`[CONFIRM]`). |
| 3 | **Population validation — auditable systems of record for populations?** | 🟡 New hires / current employees / terminations sourced from `[CONFIRM]` HRIS. **Incidents** tracked via incident runbook + `audit_logs` table + CloudWatch alarm (`biomate-auth-failures-alarm`). **Change tickets** via GitHub PRs on protected branches (`main`, `integration/next-phase`) + CI gates. **All populations, including zero-populations, must be provable by query** (e.g., a null-returning search), not written lists. |
| 4 | **Control Readiness in Vanta ≥ 85–95%?** | ❌ **`[CONFIRM]` current %.** Must reach ≥ 85% before Sentry begins fieldwork. Drive via owner assignment + evidence upload. |
| 5 | **Controls in place & operating effectively as of the start of the observation period?** | ❌ **Not yet — this dictates the start date.** SOC 2 has no remediation window. The period must start only after all in-scope controls are live and evidenced. |
| 6 | **Subservice organizations identified + their controls understood?** | 🟡 **AWS** is the primary subservice org (physical/environmental + infra security for RDS, S3, ElastiCache, Bedrock, Lambda; carve-out method). Additional third parties to classify: Stripe, Google (Gemini), OpenAI, AWS SES, Google Analytics, Vanta, Workstreet. See `04` DC7 + `05`. |
| 7 | **Report logo** | `[CONFIRM]` — provide hi-res BioMate logo for the report. |

---

## Tab: Tooling and Tech Stack

### Core Infrastructure
- **Managed Services solely responsible for in-matrix controls?** `[CONFIRM]` — Workstreet appears to provide vCISO/compliance-management services; if Workstreet operates any in-scope control on our behalf, provide the active contract + a responsibilities matrix. Otherwise: no MSP runs our infra decisions.
- **Physical presence / production data onsite?** Registered office 4625 Cedar Oaks Ln, Bellaire, TX. `[CONFIRM]` — expected answer: no significant onsite workforce; **no production data stored onsite**; fully cloud-hosted (employees on laptops). **Exception to note:** lab instruments (CryoSPARC, Oxford Nanopore/MinKNOW, Thermo EPU, SiLA2 devices) on an isolated lab VLAN — `[CONFIRM]` whether that lab is in audit scope or carved out.
- **Colocation centers?** No — fully cloud-hosted on AWS.
- **In-scope services (+ pre-customer vs. active):** BioMate AI Assistant — an AI-driven bioinformatics / drug-discovery / clinical-workflow SaaS platform. `[CONFIRM]` active vs. pre-customer customer base.
- **Cloud hosted?** **Yes — AWS**, account `399683337364`, primary region **us-west-2** (secondary us-east-1 for cryo-EM). Standard AWS security/monitoring tooling: CloudTrail (`biomate-audit-trail`, multi-region), CloudWatch alarms + SNS, KMS, Secrets Manager.
- **Servers:** EC2 (single instance `i-06696b0d91f4346e0`, us-west-2a) hosting the Node.js/Express frontend (port 3000) + Galaxy/Python backend (gunicorn, port 8080). Workflow compute on **AWS Batch** (queues `galaxy-cloud-queue`, `galaxy-cloud-queue-gpu`). Containers in ECR. *(Note single-AZ = an availability gap, not a Security-TSC finding, but relevant if Availability is added.)*
- **Datastores (production-data exposure):**
  - **RDS PostgreSQL** (`biomate-postgres`, AES-256/KMS at rest, TLS in transit, automated backups) — user accounts, workflow records, `audit_logs`, encrypted Galaxy API keys.
  - **ElastiCache Redis** (`biomate-billing-redis…usw2`, TLS required, AES-256) — sessions, billing/quota.
  - **S3** (SSE-KMS/SSE-S3): `biomate-production-data-399683337364` (user uploads/outputs), `biomate-production-backups-399683337364`, `biomate-compliance-evidence-399683337364` (versioned), `biomate-nextflow-work`, `biomate-cryo-data`, + others.
- **Firewalls:** AWS security groups (`biomate-sg`); SSH/port 22 restricted to team IP `[CONFIRM current]`; ALB terminates TLS 1.2+. Application-layer: Helmet, CORS, CSRF, rate limiting.

### Identity & Access Management
- **Primary IdP?** `[CONFIRM]` — Google Workspace or Entra ID (not evident in repo). **This is a key gap to confirm** — SOC 2 leans heavily on IdP-centralized access.
- **In-scope tools federated to IdP?** `[CONFIRM]` — AWS, GitHub, HRIS ideally federated to the IdP.
- **Tools NOT federated to IdP?** `[CONFIRM]`.
- **How is production access brokered?** **AWS Systems Manager (SSM) Session Manager** (no direct SSH exposure; deploys via SSM). Port 22 on `biomate-sg` restricted to a team IP. `[CONFIRM]` whether Tailscale/VPN is now the broker (VPN was "planned Q3 2026").
- **SSH to sensitive systems?** Access is via **SSM**, not open SSH; port 22 IP-restricted for break-glass. `[CONFIRM]`.
- **VPN for remote connection?** `[CONFIRM]` — "planned Q3 2026"; confirm current state.
- **Shared accounts?** `[CONFIRM]` — AWS IAM users `biomate-admin`, `galaxy-dev` (automation service account), `biomate-ses-smtp`; root key deactivated. Confirm no shared human logins; `galaxy-dev` is a service account (document it as such).

### Miscellaneous
- **Risk assessment completed?** ❌ `[CONFIRM]` date — **formal documented risk assessment is a gap** (Priority-1 remediation).
- **HRIS?** `[CONFIRM]` — which system (Rippling/Gusto/etc.), if any.
- **Systematic tracking of asset disposals & data deletions?** 🟡 Data-deletion / PHI events are logged in `audit_logs` (e.g., `data.phi.delete`); audit logs retained 90 days hot + 6 years S3 Glacier IR. `[CONFIRM]` a formal asset-disposal tracking process.
- **Incident intake/tracking?** 🟡 Incident runbook (`docs/runbooks/incident.md`); auth-failure CloudWatch alarm → SNS → founder; security event types logged. `[CONFIRM]` formal ticket-based intake + severity definitions (formal IR *policy* is a gap vs. the runbook).
- **System Description reviewed/updated (no first-person / superfluous language)?** 🟡 Draft prepared to that standard (`04`); needs sign-off.
- **Vulnerability scanning practices?** 🟡 `[CONFIRM]` current cadence — framework doc cites dependency scanning (npm/pip-audit) and monthly OWASP ZAP; confirm these run and where results live.

### Change Management
- **Ticketing records of production changes (developer / QA / merge approval / merge activity)?** 🟡 **GitHub PRs** on protected branches (`main`, `integration/next-phase`) with required CI suite; deploy via GitHub Actions → SSM with health gates + auto-rollback. `[CONFIRM]` that PR approval captures a distinct reviewer/approver and that this satisfies the developer/QA/approver/merge-activity fields (small-team segregation-of-duties note).

### Asset Management
- **Centralized workstation MDM?** ❌ `[CONFIRM]` — **no MDM found in repo.** Do NOT claim MDM in any control unless a real MDM (Kandji/Jamf/Intune) is deployed. Likely a gap.
- **Up-to-date asset inventory?** 🟡 AWS resources partially tracked via AWS Config; **no comprehensive asset register** (incl. laptops) found. Likely a gap.

### Use of AI  ⭐ (directly relevant — expect scrutiny)
- **Does the org use AI as a core component and/or in internal ops?** **Yes — AI is core to the service.** The BioMate AI Assistant routes user requests through an LLM fallback chain: **Google Gemini (primary), Anthropic Claude, OpenAI GPT-4o, and a local Ollama offline fallback** (`backend/config/llm_providers.yml`). Claude calls route via **AWS Bedrock** (under AWS's BAA). AI is used for workflow routing, parameter extraction, narrative/report generation, and research assistance.
- **Has the org considered AI risks in existing controls / designed AI-specific controls?** 🟡 **Partial — strengthen before fieldwork.** In place: a **PHI detection + stripping guardrail** (`safety-guardrails.ts`) that strips SSN/DOB/MRN/PatientID/NPI/insurance before LLM processing and logs a hash (not plaintext); Bedrock BAA routing for Claude; audit logging of AI-relevant events. **Gaps to close:** an **AI Acceptable Use Policy** (reviewed on hire + annually), explicit **AI risk entries in the Risk Assessment**, **AI/LLM vendors in Vendor Management** (Google, OpenAI, AWS Bedrock — data-use/retention terms), and AI considerations in **BC/DR**. The questionnaire warns: *if AI is deeply embedded and there are no risk considerations, it will be raised in fieldwork.* → make these explicit.

---

## Net: what to confirm before returning the workbook
The `[CONFIRM]` items cluster into a short list only management can answer: **IdP, HRIS, MDM, VPN/access-broker current state, MFA-in-prod, background checks, security-training tool, risk-assessment date, vuln-scan cadence, customer status (pre/active), and the Workstreet responsibilities matrix.** Everything else is answered from our actual stack above.
