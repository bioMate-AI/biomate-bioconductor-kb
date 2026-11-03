# Onboarding / Offboarding Checklist (Template)

Recurring-evidence template. Complete one per hire and one per departure; retain the completed record (ticket or signed form) — these are the **populations auditors sample every period** for CC6.2/CC6.3/CC1.4. Keep them query-backed (e.g., a ticket per event), not as an informal list.

**Instructions:** copy this per person; file the completed record in `[CONFIRM: ticketing system / HRIS]`; the manager and the access approver both confirm completion.

---

## Onboarding — new hire / contractor
**Name:** ____________  **Role:** ____________  **Type:** ☐ Employee ☐ Contractor  **Start date:** ______  **Manager:** ______

| # | Step | Owner | Done | Date | Evidence ref |
|---|---|---|---|---|---|
| 1 | Offer accepted; confidentiality / IP agreement signed | HR | ☐ | | |
| 2 | Background check completed (where required) `[CONFIRM process]` | HR | ☐ | | |
| 3 | Identity created in IdP `[CONFIRM: Google Workspace/Entra]` | IT | ☐ | | |
| 4 | Access provisioned per role (least-privilege), approved by access owner | Access owner | ☐ | | |
| 5 | MFA enrolled `[CONFIRM enforced]` | IT | ☐ | | |
| 6 | Device issued/enrolled (disk encryption, screen lock; MDM if deployed `[CONFIRM]`) | IT | ☐ | | |
| 7 | Password manager / secrets access set up as needed | IT | ☐ | | |
| 8 | Policies acknowledged: InfoSec, Acceptable Use, AI Acceptable Use | Security | ☐ | | |
| 9 | Security-awareness training assigned (complete within `[CONFIRM: 30 days]`) | Security | ☐ | | |
| 10 | HIPAA workforce training (if PHI in scope) | Security | ☐ | | |

**Onboarding complete — approver:** ____________  **Date:** ______

---

## Offboarding — departure
**Name:** ____________  **Role:** ____________  **Last day:** ______  **Manager:** ______  **Reason:** ☐ Voluntary ☐ Involuntary

> **Target: revoke all access within `[CONFIRM: 24 hours]` of termination.** For involuntary terminations, coordinate timing with HR before notice.

| # | Step | Owner | Done | Date | Evidence ref |
|---|---|---|---|---|---|
| 1 | IdP account disabled | IT | ☐ | | |
| 2 | AWS IAM access removed / keys deactivated | IT | ☐ | | |
| 3 | GitHub / source-control access removed | IT | ☐ | | |
| 4 | SaaS app access removed (all federated + non-federated tools) | IT | ☐ | | |
| 5 | Production/host access removed (SSM, any break-glass) | Eng | ☐ | | |
| 6 | Shared secrets rotated if the person had access | Eng | ☐ | | |
| 7 | Company device recovered / wiped | IT | ☐ | | |
| 8 | Email forwarded/archived per policy | IT | ☐ | | |
| 9 | Physical access / credentials returned (if any) | HR | ☐ | | |
| 10 | Manager confirms no orphaned access remains | Manager | ☐ | | |

**Offboarding complete — approver:** ____________  **Date:** ______

---
*Cross-references: `policies/12_hr_personnel_security_policy.md`, `policies/02_access_control_policy.md`.*
