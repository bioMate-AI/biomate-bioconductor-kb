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
- **Physical presence / production data onsite?** Registered office 4625 Cedar Oaks Ln, Bellaire, TX. No significant onsite workforce; no production data stored onsite; fully cloud-hosted (employees on laptops). **Exception (carved out):** lab instruments (CryoSPARC, Oxford Nanopore/MinKNOW, Thermo EPU, SiLA2 devices) on an isolated lab VLAN — no production data access, no internet exposure. Lab network is explicitly carved out of audit scope. `[CONFIRM with team that lab VLAN has no route to production AWS resources.]`
- **Colocation centers?** No — fully cloud-hosted on AWS.
- **In-scope services (+ pre-customer vs. active):** BioMate AI Assistant — an AI-driven bioinformatics / drug-discovery / clinical-workflow SaaS platform. `[CONFIRM]` active vs. pre-customer customer base.
- **Cloud hosted?** **Yes — AWS**, account `399683337364`, primary region **us-west-2** (secondary us-east-1 for cryo-EM). Standard AWS security/monitoring tooling: CloudTrail (`biomate-audit-trail`, multi-region), CloudWatch alarms + SNS, KMS, Secrets Manager.
- **Servers:** EC2 (single instance `i-06696b0d91f4346e0`, us-west-2a) hosting the Node.js/Express frontend (port 3000) + Galaxy/Python backend (gunicorn, port 8080). Workflow compute on **AWS Batch** (queues `galaxy-cloud-queue`, `galaxy-cloud-queue-gpu`). Containers in ECR. *(Note single-AZ = an availability gap, not a Security-TSC finding, but relevant if Availability is added.)*
- **Datastores (production-data exposure):**
  - **RDS PostgreSQL** (`biomate-postgres`, AES-256/KMS at rest, TLS in transit, automated backups) — user accounts, workflow records, `audit_logs`, encrypted Galaxy API keys.
  - **ElastiCache Redis** (`biomate-billing-redis…usw2`, TLS required, AES-256) — sessions, billing/quota.
  - **S3** (SSE-KMS/SSE-S3): `biomate-production-data-399683337364` (user uploads/outputs), `biomate-production-backups-399683337364`, `biomate-compliance-evidence-399683337364` (versioned), `biomate-nextflow-work`, `biomate-cryo-data`, + others.
- **Firewalls:** AWS security groups (`biomate-sg`, `sg-0b2188a4d48d989b8`); SSH/port 22 restricted to 4 individual /32 IPs: `104.63.31.236/32`, `172.58.49.122/32`, `172.58.48.213/32`, `172.58.53.46/32` (confirmed via EC2 `describe-security-groups`). ALB terminates TLS 1.2+. Application-layer: Helmet, CORS, CSRF, rate limiting.

### Identity & Access Management
- **Primary IdP?** **AWS IAM Identity Center** is the identity platform (SAML provider `AWSSSO_9ce4e5ae50e484e9_DO_NOT_DELETE` confirmed in IAM). Google Workspace is the probable upstream directory for AWS SSO but not programmatically confirmed. **Gap:** two team members (Georgiy Mamedaliev, Jian Lv) are on personal Gmail accounts and are outside Workspace management.
- **In-scope tools federated to IdP?** **AWS** (via IAM Identity Center), **GitHub Actions** (via OIDC: `token.actions.githubusercontent.com`). GitHub.com user logins and Slack are not federated.
- **Tools NOT federated to IdP?** GitHub.com direct user logins, Slack. Neither GitHub nor Slack is federated to the IdP as of 2026-09-02.
- **How is production access brokered?** **AWS Systems Manager (SSM) Session Manager** (confirmed; no direct SSH exposure). Port 22 on `biomate-sg` is restricted to `104.63.31.236/32` (test environment; production CIDR to be confirmed in AWS console) for break-glass only. No VPN is deployed.
- **SSH to sensitive systems?** Access is brokered exclusively via SSM. Port 22 is IP-restricted for break-glass only. No open SSH.
- **VPN for remote connection?** **No VPN deployed.** VPN was planned for Q3 2026 but was not delivered. SSM Session Manager serves as the sole access broker.
- **Shared accounts?** AWS IAM users `biomate-admin`, `galaxy-dev` (workflow automation service account — not a human login), `biomate-ses-smtp` (email delivery only, no console access); root key deactivated. No shared human logins confirmed.

### Miscellaneous
- **Risk assessment completed?** ❌ `[CONFIRM]` date — **formal documented risk assessment is a gap** (Priority-1 remediation).
- **HRIS?** `[CONFIRM]` — which system (Rippling/Gusto/etc.), if any.
- **Systematic tracking of asset disposals & data deletions?** 🟡 Data-deletion / PHI events are logged in `audit_logs` (e.g., `data.phi.delete`); audit logs retained 90 days hot + 6 years S3 Glacier IR. `[CONFIRM]` a formal asset-disposal tracking process.
- **Incident intake/tracking?** 🟡 Incident runbook (`docs/runbooks/incident.md`); auth-failure CloudWatch alarm → SNS → founder; security event types logged. `[CONFIRM]` formal ticket-based intake + severity definitions (formal IR *policy* is a gap vs. the runbook).
- **System Description reviewed/updated (no first-person / superfluous language)?** 🟡 Draft prepared to that standard (`04`); needs sign-off.
- **Vulnerability scanning practices?** 🟡 **Confirmed (partial):** Trivy dependency scanning runs on every pull request; results are uploaded to GitHub Code Scanning (SARIF format) — confirmed in `.github/workflows/ci-tests.yml`. Amazon Inspector provides continuous EC2/ECR vulnerability scanning (EventBridge managed rule `DO-NOT-DELETE-AmazonInspectorEc2ManagedRule` confirmed). **However:** Trivy is currently informational only — it is explicitly not a hard merge gate. No DAST/OWASP ZAP confirmed. No Dependabot. Converting Trivy to a hard gate is a tracked remediation item.

### Change Management
- **Ticketing records of production changes (developer / QA / merge approval / merge activity)?** 🟡 **GitHub PRs** on protected branches (`main`, `integration/next-phase`) with required CI suite; deploy via GitHub Actions → SSM with health gates + auto-rollback. **Confirmed as of 2026-09-02:** `enforce_admins=true`, `dismiss_stale_reviews=true`, `require_last_push_approval=true` are set on both biomate and stack repos; PR records include a distinct reviewer/approver field, satisfying the developer/QA/approver/merge fields. **Historical exception:** 64 PRs merged without approval Aug 4–Sep 1 2026 (controls not yet enforced); documented in Vanta with rationale. These predate the observation period.

### Asset Management
- **Centralized workstation MDM?** ❌ **Confirmed: none.** No MDM (Kandji/Jamf/Intune) is deployed. Vanta MDM-1 control is failing. Do NOT claim MDM in any control. Tracked as an open gap (E5/P2-5).
- **Up-to-date asset inventory?** 🟡 AWS resources partially tracked via AWS Config; **no comprehensive asset register** (incl. laptops) found. Likely a gap.

### Use of AI  ⭐ (directly relevant — expect scrutiny)
- **Does the org use AI as a core component and/or in internal ops?** **Yes — AI is core to the service.** The BioMate AI Assistant routes user requests through an LLM fallback chain: **Google Gemini (primary), Anthropic Claude, OpenAI GPT-4o, and a local Ollama offline fallback** (`backend/config/llm_providers.yml`). Claude calls route via **AWS Bedrock** (under AWS's BAA). AI is used for workflow routing, parameter extraction, narrative/report generation, and research assistance.
- **Has the org considered AI risks in existing controls / designed AI-specific controls?** 🟡 **Partial — strengthen before fieldwork.** In place: a **PHI detection + stripping guardrail** (`safety-guardrails.ts`) that strips SSN/DOB/MRN/PatientID/NPI/insurance before LLM processing and logs a hash (not plaintext); Bedrock BAA routing for Claude; audit logging of AI-relevant events. **Gaps to close:** an **AI Acceptable Use Policy** (reviewed on hire + annually), explicit **AI risk entries in the Risk Assessment**, **AI/LLM vendors in Vendor Management** (Google, OpenAI, AWS Bedrock — data-use/retention terms), and AI considerations in **BC/DR**. The questionnaire warns: *if AI is deeply embedded and there are no risk considerations, it will be raised in fieldwork.* → make these explicit.

---

## Net: what to confirm before returning the workbook
**Resolved by engineering (2026-09-02):** IdP (AWS IAM Identity Center + OIDC confirmed), VPN/access-broker (SSM, no VPN), MDM (none — confirmed gap), vuln-scan cadence (Trivy per-PR + Inspector, informational), change-management SoD (branch protection upgraded), lab VLAN (carved out), break-glass CIDR (test: 104.63.31.236/32).

**Still needs management/Yaoyun:** HRIS, MFA-in-prod timeline, background checks (E11), security-awareness training tool, formal risk-assessment sign-off date, customer status (pre/active, E12), Workstreet responsibilities matrix, prod SSH CIDR (AWS console), RDS backup retention (AWS console), RDS/Redis AZ config (AWS console).
