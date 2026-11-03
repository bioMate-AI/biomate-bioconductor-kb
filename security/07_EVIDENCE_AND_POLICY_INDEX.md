# Evidence & Policy Index — Required Documents and Status

Tracks the policies and supplemental evidence SOC 2 (and the parallel HIPAA track) require, with current status and where each lives. Grounded in repo recon (`docs/20260412_SOC2_HIPAA_AUDIT_FRAMEWORK.md` + code). **Status:** ✅ exists · 🟡 informal/partial · ❌ missing. Make each ❌/🟡 a Vanta task with an owner + due date.

## A. Policies (Domain 6)
**Draft policy pack authored** in `policies/` (13 policies + index), grounded in actual practice with `[CONFIRM]` fields. Status below = **📝 DRAFT** (drafted, needs `[CONFIRM]` resolution + owner + approval + acknowledgment) vs. ✅ exists vs. ❌ still missing.

| Policy | Status | Where / note |
|---|---|---|
| Information Security Policy (master) | 📝 DRAFT | `policies/01_information_security_policy.md` |
| Access Control Policy (incl. access-review cadence) | 📝 DRAFT | `policies/02_access_control_policy.md` — confirm review cadence, MFA, IdP |
| Change Management Policy | 📝 DRAFT | `policies/03_change_management_policy.md` — confirm SoD on small team |
| Vendor / Third-Party Risk Management Policy | 📝 DRAFT | `policies/05_vendor_management_policy.md` — plus build the register (§D) |
| Data Classification, Retention & Disposal Policy | 📝 DRAFT | `policies/08_data_classification_retention_policy.md` — confirm user-data retention |
| Risk Management Policy + **Risk Assessment** | 📝 DRAFT / ❌ | Policy `policies/04_risk_management_policy.md`; **the risk assessment artifact itself is still ❌ Priority 1** |
| Business Continuity / Disaster Recovery Policy + **test results** | 📝 DRAFT / ❌ | Policy `policies/07_bcdr_policy.md`; **test results still ❌** |
| Incident Response **Policy** | 📝 DRAFT | `policies/06_incident_response_policy.md` (formalizes `docs/runbooks/incident.md`) |
| Breach Notification Procedure | 🟡 | Covered within IR policy; confirm committed windows / operationalize SOP |
| Encryption / Key Management Policy | 📝 DRAFT | `policies/09_encryption_key_management_policy.md` |
| Acceptable Use Policy | 📝 DRAFT | `policies/10_acceptable_use_policy.md` |
| **AI Acceptable Use Policy** | 📝 DRAFT | `policies/11_ai_acceptable_use_policy.md` |
| Security Awareness Training Policy + records | 📝 DRAFT / ❌ | Policy `policies/13_security_awareness_training_policy.md`; **training tool + records still ❌** |
| HR / Onboarding-Offboarding + Background-check Policy | 📝 DRAFT | `policies/12_hr_personnel_security_policy.md` — confirm background-check process |
| Privacy Policy | ✅ | `docs/export/privacy_policy.md`. |
| Terms of Service | ✅ | `docs/export/terms_of_service.md`. |

> **Note:** a drafted policy is not a satisfied control. Each 📝 DRAFT still needs `[CONFIRM]` fields resolved, an owner + approver, publication in Vanta, and employee acknowledgment before it counts. And several policies point at evidence that must still be *produced* (risk assessment, BC/DR test, training records) — those remain ❌ in §B.

## B. Supplemental evidence (Domain 8)
| Evidence | Status | Note |
|---|---|---|
| Penetration test report | ❌ | Not performed / not found. Commission one. |
| Formal risk assessment | 📝 DRAFT | **Pre-populated draft authored:** `08_RISK_ASSESSMENT.md` + `08_risk_register.xlsx` (20 risks). Needs management validation, `[CONFIRM]` resolution, owners/dates, approval → load into Vanta. |
| Vendor security reviews (SOC 2s / BAAs) | 📝 DRAFT / ❌ | **Register drafted + risk-ranked:** `09_vendor_register.xlsx` (11 vendors). Still ❌: actually collecting each SOC 2/ISO + confirming DPAs/BAAs. |
| BC/DR test results | ❌ | Perform + document a restore test. |
| Access-review evidence (recurring) | ❌/🟡 | Establish cadence; produce query-backed evidence. |
| Onboarding/offboarding tickets | 🟡 | `[CONFIRM]` where ticketed. |
| Security-awareness training completion records | ❌ | After training stood up. |
| Automated compliance evidence | ✅ | `s3://biomate-compliance-evidence-399683337364/` (versioned) + daily audit-log export. Align to Vanta control requests. |
| CloudTrail / audit logs | ✅ | `biomate-audit-trail` (multi-region); `audit_logs` table. |

## C. Populations for Type 2 (must be query-backed, incl. zero-populations)
| Population | Source | Status |
|---|---|---|
| New hires / current employees / terminations | HRIS `[CONFIRM]` | 🟡 |
| Incidents | `audit_logs` + CloudWatch alarm + IR runbook | 🟡 |
| Change tickets | GitHub PRs on protected branches + CI | 🟡 |
| Access grants/revocations | IAM / IdP `[CONFIRM]` | 🟡 |

## D. Vendor / subprocessor register — 📝 drafted
**`09_vendor_register.xlsx`** (11 vendors, risk-ranked by data sensitivity × access, with Subservice-org / SOC 2-ISO / DPA-BAA / owner columns): AWS (critical subservice org), Anthropic-via-Bedrock, Google (Gemini), OpenAI, Stripe, AWS SES, GitHub, Vanta, Workstreet `[CONFIRM role]`, Google Analytics, Ollama (self-hosted). **Remaining work:** collect each vendor's SOC 2/ISO, confirm DPAs, and confirm BAAs where PHI applies.

## E. HIPAA parallel track (see plan §2)
Confirm scope; enable Vanta HIPAA framework; map SOC 2 controls to HIPAA Security/Privacy/Breach safeguards; execute BAAs with PHI-touching subprocessors (AWS BAA already covers RDS/S3/Bedrock/ElastiCache/Lambda per repo) and offer BAAs to customers; formalize PHI handling, minimum-necessary, and de-identification posture.
