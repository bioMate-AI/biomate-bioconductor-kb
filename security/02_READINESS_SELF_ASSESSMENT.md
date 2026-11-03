# Engagement Readiness Self-Assessment — Honest Status

**Framework:** Sentry Assurance "Engagement Readiness Self-Assessment" (9 domains) — the gate to scheduling.
**Rule (from Sentry):** *"If you cannot honestly check every box, you are not yet ready to schedule."* An incomplete/unsigned workbook is returned, not scheduled.
**Status legend:** ✅ Ready · 🟡 Partial (work remains) · ❌ Gap (not started / not true today) · `[CONFIRM]` = needs a fact only management can supply.
**Assessed:** 2026-09-01, grounded in repo facts (`docs/20260412_SOC2_HIPAA_AUDIT_FRAMEWORK.md`, code, config). Time-sensitive items from April 2026 are re-flagged `[CONFIRM]` because SOC 2 tests what is true *now*.

> **Overall verdict: NOT yet ready to sign the attestation.** We have a genuinely strong technical control base (encryption, audit logging, CI/CD gates, SSM-brokered access), but the *documentation, ownership, policy-acknowledgment, and formal-evidence* layers that SOC 2 tests are incomplete. This is normal for a first audit. Each ❌/🟡 below is a tracked remediation task. Sign the attestation only when every box is honestly ✅.

---

## Domain 1 — Scope & Framework  🟡
| Item | Status | Notes |
|---|---|---|
| Confirmed TSC in scope (Security ± others) | ✅ | Security / Common Criteria only, per SOW. **Decision pending** on adding Confidentiality/Availability (see plan §2). |
| Defined products/services/systems/infrastructure in scope | 🟡 | System = "BioMate AI Assistant Services System." Boundary needs to be written explicitly in the System Description (see `04`). |
| Documented what is out of scope, and why | ❌ | Not yet written. Lab-instrument integrations (CryoSPARC, MinKNOW, SiLA2, EPU) on isolated lab VLANs, the marketing site, and 21 CFR Part 11 scope should be explicitly carved out. |
| Identified subservice organizations | 🟡 | AWS clearly identified (RDS, S3, Bedrock, ElastiCache, Lambda). Also to classify: Stripe, Google (Gemini), OpenAI, AWS SES, GA4, Workstreet, Vanta. Carve-out method + CSOCs not yet drafted (see `04` DC7). |

## Domain 2 — Controls Defined  🟡
| Item | Status | Notes |
|---|---|---|
| Control set reflects how we actually operate (not a template) | 🟡 | Strong technical controls exist in code/AWS. **The Vanta control set must be reconciled line-by-line to reality before the period starts** — this is the #1 finding-risk. |
| Every in-scope control maps to ≥1 criterion | `[CONFIRM]` | Depends on Vanta configuration state — confirm mapping is complete. |
| Each control marked in/out of scope with justification | ❌ | Not yet done in Vanta. |
| Not relying on controls we cannot consistently meet | 🟡 | **Watch items:** MFA (prototype complete but `[CONFIRM]` whether enforced in production); quarterly access reviews (`[CONFIRM]` whether actually running on a cadence); MDM (`[CONFIRM]` — none found in repo; do not claim it if absent); VPN ("planned Q3 2026" — `[CONFIRM]` if deployed, else don't claim it). |

## Domain 3 — Control Owners  ❌
| Item | Status | Notes |
|---|---|---|
| Every active control has a named owner | ❌ | No control-owner assignment found. Small team — likely concentrated on the founder + eng lead; must still be explicitly assigned in Vanta. |
| Each owner understands their control + the evidence it produces | ❌ | Requires a walkthrough once owners are assigned. |
| Owners have appropriate access + notifications | ❌ | Set up in Vanta after assignment. |
| Owners accountable for remediating failures | ❌ | Same. |

## Domain 4 — Integrations & Automated Tests  🟡
| Item | Status | Notes |
|---|---|---|
| All relevant integrations connected + authenticated (Vanta) | `[CONFIRM]` | Which cloud/IdP/HRIS/task integrations are live in Vanta? AWS is the critical one. |
| Each integration pulling data correctly | `[CONFIRM]` | Verify in Vanta. |
| Reviewed every automated test + status | ❌ | Vanta test review not yet done. |
| Failing tests remediated or documented out-of-scope | ❌ | Depends on the above. |
| Manual/custom tests set up for gaps | ❌ | Not yet. |

## Domain 5 — People, Access & Training  🟡
| Item | Status | Notes |
|---|---|---|
| All employees + contractors captured and current | `[CONFIRM]` | Needs the HRIS/roster source of truth (`[CONFIRM]` which HRIS, if any). |
| Security-awareness training assigned + tracked | ❌ | Not found in repo; `[CONFIRM]` whether a training tool/process exists. Likely a gap. |
| Onboarding/offboarding workflows evidenced | 🟡 | Access is IAM/SSM-brokered; but a documented, evidenced on/off-boarding workflow (with tickets) is `[CONFIRM]`/likely a gap. |
| Background checks documented where required | `[CONFIRM]` | No evidence in repo. Likely a gap for a small team — confirm. |
| Recurring access-review process in place | ❌/`[CONFIRM]` | No formal documented access-review cadence found. Likely a gap. |

## Domain 6 — Policies & Documentation  🟡
| Item | Status | Notes |
|---|---|---|
| All required policies drafted, approved, published | 🟡 | **Have:** Privacy Policy, Terms of Service, Incident Response *runbook*, Compliance Summary. **Missing/informal:** formal Information Security Policy, Access Control, Change Management, Vendor Management, Data Retention/Classification, BC/DR, Risk Management, Encryption/Key Mgmt, Acceptable Use (incl. **AI Acceptable Use**), Security Awareness. See `07_EVIDENCE_AND_POLICY_INDEX.md`. |
| Policies mapped to controls | ❌ | After policies exist. |
| Employees reviewed + accepted current versions | ❌ | No acknowledgment tracking found. |
| Review cadence + version history in place | ❌ | Establish in Vanta (annual review + versioning). |

## Domain 7 — System Description  🟡
| Item | Status | Notes |
|---|---|---|
| Draft covers 5 components (infra, software, people, data, procedures) | 🟡 | **Management draft prepared** — see `04_SYSTEM_DESCRIPTION_DRAFT.md`. Needs management to replace all `[CONFIRM]` and own it. |
| System boundaries + services described | 🟡 | Drafted; needs verification. |
| Control environment, risk assessment, monitoring, communication documented | 🟡 | Monitoring/communication drafted from real facts; **formal risk assessment is a gap** (Domain 9). |
| Subservice orgs + CUECs/CSOCs included | 🟡 | Drafted (DC7 + `05_CUEC_MAPPING_TABLE.md`); needs verification. |
| Leadership reviewed for accuracy | ❌ | Pending — Yaoyun must read end-to-end and sign `06`. |

## Domain 8 — Supplemental Evidence  🟡
| Item | Status | Notes |
|---|---|---|
| Identified controls needing manually-uploaded evidence | 🟡 | Partially known; formalize in `07`. |
| Supplemental docs current + uploaded (pen test, risk assessment, vendor reviews, BC/DR results) | ❌ | **Pen test: not found / not performed.** **Formal risk assessment: gap.** **Vendor reviews: gap.** **BC/DR test results: gap** (backups exist; no tested DR). These are the heaviest lifts. |
| Evidence labeled + organized | 🟡 | `s3://biomate-compliance-evidence-399683337364/` exists with automated evidence; needs to align to Vanta control requests. |
| Process to collect recurring evidence | 🟡 | Automated audit-log export + evidence bucket exist; recurring cadence for access reviews/training/vendor reviews is a gap. |

## Domain 9 — Vendors & Risk  ❌
| Item | Status | Notes |
|---|---|---|
| Vendor inventory complete | ❌ | No formal vendor register. Draft list exists from tech-stack recon (see `03`/`07`); needs to be made authoritative. |
| Vendors risk-ranked by data sensitivity + access | ❌ | Not done. |
| Vendor security reviews documented | ❌ | Not done (collect SOC 2s from AWS, Stripe, Google, OpenAI; confirm BAAs where PHI applies). |
| Organizational risk assessment complete + documented | ❌ | **Formal, documented risk assessment is a gap** — this is a foundational SOC 2 requirement and gates the System Description (risk → controls chain). Prioritize. |

---

## Remediation backlog (turn each into a Vanta task with an owner + due date)

**Priority 1 — foundational, gate everything else**
1. Complete a **formal organizational risk assessment** (Domain 9 + DC2/DC5 chain).
2. **Reconcile the Vanta control set to operational reality**; assign a **named owner** to every control (Domains 2, 3).
3. Author + publish the **missing policies** and get **employee acknowledgment** (Domain 6; list in `07`).

**Priority 2 — readiness gates for scheduling**
4. Build the **authoritative vendor inventory**, risk-rank, collect vendor SOC 2s / confirm BAAs (Domain 9).
5. Stand up **recurring evidence**: access reviews (cadence), onboarding/offboarding tickets, security-awareness training (Domains 5, 8).
6. Drive **Vanta Control Readiness ≥ 85–95%** (Sentry's fieldwork threshold).
7. Resolve **MFA-in-production**, **VPN/access-brokering**, **MDM** `[CONFIRM]` items — either operate + evidence them, or do not claim them (Domain 2).

**Priority 3 — supplemental evidence**
8. Commission a **penetration test** (Domain 8).
9. Perform + document a **BC/DR test** (Domain 8).
10. Finalize + sign the **System Description** and **management acknowledgment** (Domain 7; `04`–`06`).

**Do not sign the readiness attestation, and do not set the observation-period start date, until items 1–7 are honestly ✅.** (This also protects against the SOW's 120% rescheduling penalty — see `01`.)
