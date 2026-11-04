# BioMate AI — Information Security Risk Assessment

| | |
|---|---|
| **Version** | 0.1 DRAFT |
| **Owner** | `[CONFIRM: Security owner]` |
| **Prepared** | 2026-09-01 |
| **Method basis** | Risk Management Policy (`policies/04_risk_management_policy.md`) |
| **Review cadence** | At least annually and upon significant change |
| **Companion file** | `08_risk_register.xlsx` (working copy) |

> **What this is / isn't.** This is a *pre-populated draft* risk register built from BioMate's actual architecture (repo/config recon) to satisfy the SOC 2 foundational requirement and to feed the System Description's risk→control chain. It is **not** final: management must validate each risk, confirm the `[CONFIRM]` items, adjust ratings to its own risk appetite, assign owners and target dates, and formally approve it. A risk assessment is management's judgment — this draft accelerates it, it does not replace it.

## 1. Methodology
- **Scope.** Risks to the confidentiality, integrity, and availability of the BioMate AI Assistant Services System, its data, and its supporting third parties — including AI/LLM-specific risks.
- **Scoring.** Each risk is rated **Likelihood (L)** and **Impact (I)** on a 1–5 scale; **Inherent Risk = L × I** (before controls). After accounting for controls in place, a **Residual Risk** rating is assigned.
- **Scale.**
  - Likelihood: 1 Rare · 2 Unlikely · 3 Possible · 4 Likely · 5 Almost certain
  - Impact: 1 Negligible · 2 Minor · 3 Moderate · 4 Major · 5 Severe
  - Tiers: **Low 1–6 · Medium 8–12 · High 15–25**
- **Treatment.** Each risk gets a treatment decision: **Mitigate / Accept / Transfer / Avoid**, an owner, and a target date. Accepted risks are documented with rationale.
- **Linkage.** Every material risk maps to the control(s) and Trust Services Criteria that address it; this linkage feeds System Description DC2→risk→DC5.

## 2. Summary — highest residual risks to prioritize
1. **R-04 MFA not enforced in production** (`[CONFIRM]`) — account takeover of admin/IdP.
2. **R-10 No tested backup restore / BC/DR** — recoverability unproven.
3. **R-09 No penetration test** — unknown exploitable app vulnerabilities.
4. **R-02 Secrets partly in host `.env`** — complete Secrets Manager migration.
5. **R-17 No security-awareness training** — phishing/social engineering.
6. **R-19 System Description misstatement risk** — qualified opinion if template/aspirational language ships.

These align with the Priority-1/2 remediation backlog in `02_READINESS_SELF_ASSESSMENT.md`.

## 3. Risk register (draft)
L/I on 1–5; Inherent = L×I. Residual reflects controls currently in place. `[CONFIRM]` = verify before approval.

| ID | Category | Risk | L | I | Inherent | Existing controls | Treatment | Residual | Owner |
|---|---|---|---|---|---|---|---|---|---|
| R-01 | Infrastructure | Single-AZ RDS / single EC2 / single-node Redis → outage, data-loss window | 3 | 4 | 12 (Med) | Automated RDS backups; S3 durability | Mitigate (multi-AZ) `[CONFIRM status]`; accept interim | Med | Eng |
| R-02 | Secrets | Some secrets in host `.env` rather than Secrets Manager | 3 | 4 | 12 (Med) | Billing/RDS secrets in Secrets Manager; not in git | Mitigate — finish migration | Med | Eng |
| R-03 | Access | Break-glass SSH via IP-whitelist could be abused | 2 | 4 | 8 (Med) | SSM is primary broker; port 22 IP-restricted | Mitigate (VPN) `[CONFIRM]` | Low | Eng |
| R-04 | Access | MFA not enforced in production (prototype only) `[CONFIRM]` | 3 | 5 | 15 (High) | JWT+bcrypt+15-min timeout; IdP MFA `[CONFIRM]` | Mitigate — deploy/enforce MFA | High→Med | Eng |
| R-05 | Endpoint | No MDM on workstations → data on unmanaged laptops | 3 | 3 | 9 (Med) | Acceptable-use expectations `[CONFIRM]` | Mitigate — deploy MDM | Med | Sec |
| R-06 | Application/AI | Prompt injection / malicious input drives unsafe action | 3 | 3 | 9 (Med) | Guardrails; `run_code` sandboxing `[CONFIRM]`; role tiers | Mitigate | Med | Eng |
| R-07 | Data/AI | PHI leakage to external LLM providers | 3 | 5 | 15 (High) | PHI-stripping guardrail; Bedrock BAA routing; hash-only logging | Mitigate | Med | Sec |
| R-08 | AI | AI output relied on for regulated decisions is wrong | 3 | 4 | 12 (Med) | User-review CUEC; no-medical-advice stance | Mitigate/Transfer (to user) | Med | Product |
| R-09 | Application | Exploitable web-app vulnerability (OWASP) | 3 | 4 | 12 (Med) | Helmet/CORS/CSRF/rate-limit; dep + ZAP scans `[CONFIRM]` | Mitigate — pen test (gap) | Med | Eng |
| R-10 | Availability | Backups exist but restore never tested | 3 | 4 | 12 (Med) | RDS automated backups; S3 backups bucket | Mitigate — BC/DR test (gap) | Med | Eng |
| R-11 | Data | Multi-tenant isolation failure → cross-customer data access | 2 | 5 | 10 (Med) | Role tiers; ownership checks; project-routes tests | Mitigate | Low | Eng |
| R-12 | Third-party | AWS subservice-org failure or misconfiguration | 2 | 4 | 8 (Med) | Reliance on AWS SOC2/CSOCs; config review `[CONFIRM]` | Mitigate/Accept | Low | Sec |
| R-13 | Third-party/AI | LLM provider trains on / retains prompt data | 3 | 3 | 9 (Med) | Bedrock BAA; vendor review of terms `[CONFIRM]` | Mitigate | Med | Sec |
| R-14 | Third-party | Payment data mishandling (Stripe) | 2 | 3 | 6 (Low) | Stripe handles card data; webhook signature verification | Accept/Transfer | Low | Eng |
| R-15 | People | Key-person dependency (small team) | 4 | 3 | 12 (Med) | Documentation; runbooks | Mitigate — cross-train/document | Med | CEO |
| R-16 | People | No evidenced onboarding/offboarding → orphaned access | 3 | 4 | 12 (Med) | IAM/SSM provisioning; HR policy (draft) | Mitigate — ticketed workflow | Med | CEO/Sec |
| R-17 | People | No security-awareness training → phishing/social eng. | 3 | 4 | 12 (Med) | None found | Mitigate — stand up training | High→Med | Sec |
| R-18 | Change | Insufficient change SoD on small team | 3 | 3 | 9 (Med) | PR review + required CI + gated deploy | Mitigate | Med | Eng |
| R-19 | Compliance | System Description misstatement → qualified opinion | 3 | 4 | 12 (Med) | Management-authored draft; self-review checklist | Mitigate | Med | CEO |
| R-20 | Lab network | Insecure lab-instrument protocols (gRPC `insecure`, plain HTTP) | 2 | 3 | 6 (Low) | Isolated lab VLAN, no internet exposure | Accept (documented); out of audit boundary `[CONFIRM]` | Low | Eng |

## 4. Accepted risks (require documented sign-off)
- **R-20** lab-instrument insecure protocols — accepted because the lab VLAN is isolated with no internet exposure and is proposed out of the audit boundary.
- **R-01 (interim)** single-AZ topology — accepted until multi-AZ is in place, if management's availability appetite permits (note: Availability is not in the current examination scope).
Any other "Accept" decisions must be recorded here with rationale and an approver.

## 5. Next steps
1. Management reviews and adjusts every row; resolves `[CONFIRM]`; sets owners + target dates.
2. Approve and date the register; load into Vanta as the risk assessment of record.
3. Wire the risk→control→TSC linkage into the System Description (DC2/DC5).
4. Re-assess at least annually and on significant change.
