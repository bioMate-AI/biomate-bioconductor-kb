# Control-to-TSC Matrix — BioMate Controls mapped to Common Criteria (CC1–CC9)

| | |
|---|---|
| **Version** | 0.1 DRAFT |
| **Purpose** | Map BioMate's *actual* controls to the 2017 Trust Services Criteria (Security / Common Criteria) so the Vanta control set can be reconciled to reality faster, and to feed the System Description DC5. |
| **Companion file** | `10_control_tsc_matrix.xlsx` (working copy) |
| **Status legend** | ✅ in place · 🟡 partial · ❌ gap · `[CONFIRM]` verify |

> **How to use:** for each criterion, confirm the stated control is *performed as written*, then align the Vanta control text to this. Where status is 🟡/❌, it's a remediation item (cross-ref `02` and `08`). Do **not** mark a Vanta control "ready" if the row here says 🟡/❌.

## CC1 — Control Environment
| Ref | Criterion (abbrev.) | BioMate control | Status | Evidence |
|---|---|---|---|---|
| CC1.1 | Integrity & ethical values | Acceptable Use + AI Acceptable Use policies (draft); confidentiality/IP agreements `[CONFIRM]` | 🟡 | `policies/10,11`; signed agreements |
| CC1.2 | Governance oversight | Founder/management oversight; `[CONFIRM]` formal governance cadence for a small company | 🟡 | mgmt review records |
| CC1.3 | Org structure & reporting lines | `[CONFIRM]` org chart / role definitions | 🟡 | org chart |
| CC1.4 | Commitment to competence | Hiring, background checks (draft HR policy), security training (❌ tool) | 🟡 | `policies/12,13` |
| CC1.5 | Accountability | Control owners assigned in Vanta (❌ to do); policy acknowledgment | ❌ | Vanta owner assignments |

## CC2 — Communication & Information
| Ref | Criterion | BioMate control | Status | Evidence |
|---|---|---|---|---|
| CC2.1 | Quality information for control | Application `audit_logs`; CloudTrail; CloudWatch metrics | ✅🟡 | audit_logs schema; CloudTrail |
| CC2.2 | Internal communication of responsibilities | Policies + acknowledgment; training (❌) | 🟡 | Vanta policy acks |
| CC2.3 | External communication | Privacy Policy, ToS; customer/breach notification `[CONFIRM windows]` | 🟡 | `docs/export/*`; IR policy |

## CC3 — Risk Assessment
| Ref | Criterion | BioMate control | Status | Evidence |
|---|---|---|---|---|
| CC3.1 | Specify objectives | Service commitments/system requirements (DC2) `[CONFIRM to contract]` | 🟡 | `04` DC2 |
| CC3.2 | Identify & assess risk | Risk assessment + register (drafted `08`) | 🟡→✅ on approval | `08_risk_register.xlsx` |
| CC3.3 | Consider fraud risk | Included in risk assessment | 🟡 | `08` |
| CC3.4 | Assess change impact | Change management + risk re-assessment on change | 🟡 | `policies/03,04` |

## CC4 — Monitoring Activities
| Ref | Criterion | BioMate control | Status | Evidence |
|---|---|---|---|---|
| CC4.1 | Ongoing/separate evaluations | Vanta continuous monitoring `[CONFIRM]`; CloudWatch; dependency/ZAP scans `[CONFIRM]` | 🟡 | Vanta tests; scan results |
| CC4.2 | Evaluate & communicate deficiencies | Incident process + remediation tracking (Vanta tasks) | 🟡 | IR records; Vanta |

## CC5 — Control Activities
| Ref | Criterion | BioMate control | Status | Evidence |
|---|---|---|---|---|
| CC5.1 | Select & develop controls | Vanta control set (❌ reconcile to reality) | 🟡 | Vanta controls |
| CC5.2 | Technology general controls | Encryption, access, logging, CI/CD gates | ✅ | recon citations |
| CC5.3 | Deploy via policies & procedures | Policy pack (drafted `policies/`) | 🟡 | `policies/` |

## CC6 — Logical & Physical Access
| Ref | Criterion | BioMate control | Status | Evidence |
|---|---|---|---|---|
| CC6.1 | Logical access security (identify/auth + encryption) | IAM least-privilege; JWT+bcrypt(12)+15-min timeout; TLS 1.2+/KMS/AES-256; role tiers; `[CONFIRM MFA]` | ✅🟡 | recon §4,§5 |
| CC6.2 | Register & authorize users | Provisioning on approval; CUEC (user-entity authorized list) | 🟡 | `05`; onboarding records |
| CC6.3 | Role-based access; modify/remove | Role tiers; deprovisioning `[CONFIRM ≤24h]`; access reviews `[CONFIRM cadence]` | 🟡 | access-review template |
| CC6.4 | Physical access | AWS data centers (subservice-org CSOC, carve-out); no onsite prod data `[CONFIRM]` | ✅ (carve-out) | `04` DC7; AWS SOC 2 |
| CC6.5 | Data disposal | Data-deletion logging (`data.phi.delete`); retention policy (draft); asset disposal `[CONFIRM]` | 🟡 | `policies/08` |
| CC6.6 | Boundary protection (external threats) | Security groups (`biomate-sg`); ALB TLS 1.2+; Helmet/CORS/CSRF/rate-limit; SSM (no open SSH) | ✅ | recon §1,§3,§4 |
| CC6.7 | Restrict transmission/movement of data | TLS everywhere; PHI-stripping guardrail; encryption; endpoint/MDM `[CONFIRM ❌]` | 🟡 | recon §5,§7 |
| CC6.8 | Prevent/detect unauthorized software | Dependency scanning `[CONFIRM]`; container images from ECR; endpoint controls (❌ MDM) | 🟡 | scan results |

## CC7 — System Operations
| Ref | Criterion | BioMate control | Status | Evidence |
|---|---|---|---|---|
| CC7.1 | Detect vulnerabilities | Dependency scans + OWASP ZAP `[CONFIRM cadence]`; **pen test ❌** | 🟡 | scan/pen-test reports |
| CC7.2 | Monitor for anomalies | CloudWatch auth-failure alarm → SNS; audit-log event types | ✅🟡 | CloudWatch; audit_logs |
| CC7.3 | Evaluate security events | Incident response triage (severity defs `[CONFIRM]`) | 🟡 | `policies/06` |
| CC7.4 | Respond to incidents | IR policy + runbook (`docs/runbooks/incident.md`) | 🟡 | IR records |
| CC7.5 | Recover | RDS automated backups; S3 backups; **restore/BC-DR test ❌** | 🟡 | `policies/07`; test results |

## CC8 — Change Management
| Ref | Criterion | BioMate control | Status | Evidence |
|---|---|---|---|---|
| CC8.1 | Authorized, tested, approved changes | Protected branches; peer-reviewed PRs; required CI; health-gated deploy + auto-rollback; SoD `[CONFIRM]` | ✅🟡 | GitHub PRs; CI logs |

## CC9 — Risk Mitigation
| Ref | Criterion | BioMate control | Status | Evidence |
|---|---|---|---|---|
| CC9.1 | Mitigate business-disruption risk | BC/DR + backups; insurance `[CONFIRM]` | 🟡 | `policies/07` |
| CC9.2 | Manage vendor/subservice-org risk | Vendor register (drafted `09`); AWS CSOC reliance | 🟡 | `09_vendor_register.xlsx` |

## Reconciliation summary
- **Strong / ✅:** CC5.2, CC6.1 (core), CC6.4 (carve-out), CC6.6, CC7.2, CC8.1 — the technical spine.
- **Partial / 🟡 (most rows):** need the policies adopted + acknowledged, control owners assigned, access-review cadence operating, and evidence produced.
- **Hard gaps / ❌:** control-owner assignment (CC1.5), pen test (CC7.1), BC/DR test (CC7.5), security training (CC1.4/CC2.2), MDM/endpoint (CC6.7/6.8).
