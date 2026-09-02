# BioMate AI — Security & Compliance (SOC 2 Type 2 + HIPAA)

Working folder for the SOC 2 Type 2 (Security) examination with **Sentry Assurance** on the **Vanta** platform, funded via **Workstreet**, plus the parallel **HIPAA** readiness track.

**Start here:** `00_PLAN_SOC2_HIPAA.md` — the master plan and sequenced roadmap.
**Engineering:** read `TEAM_REVIEW_SUMMARY.md` — what to double-check (facts E1–E15).
**Driving the work:** `11_ACTION_TRACKER.md` — every open item with owner + status.

| File | What it is | Who acts |
|---|---|---|
| `00_PLAN_SOC2_HIPAA.md` | Master plan, engagement facts, roadmap, open decisions | Read first |
| `01_SOW_REVIEW_MEMO.md` | Review of the PSA/SOW — **5 items to clarify before signing** | Yaoyun / counsel |
| `02_READINESS_SELF_ASSESSMENT.md` | Honest 9-domain gap analysis + remediation backlog | Yaoyun + owners |
| `03_SCOPING_QUESTIONNAIRE_ANSWERS.md` | Narrative answers to Sentry's intake questionnaire | Yaoyun |
| `03_scoping_questionnaire_FILLED.xlsx` | The intake Excel, filled | return to Sentry |
| `04_SYSTEM_DESCRIPTION_DRAFT.md` | Management draft of the System Description (DC1–DC9) | Yaoyun authors; owners verify |
| `05_CUEC_MAPPING_TABLE.md` | CUEC mapping table (4-column) | Yaoyun |
| `06_MANAGEMENT_ACKNOWLEDGMENT.md` | Self-review checklist + sign-off for the description | Yaoyun signs |
| `07_EVIDENCE_AND_POLICY_INDEX.md` | Required policies & evidence, with status | Yaoyun + owners |
| `08_RISK_ASSESSMENT.md` + `08_risk_register.xlsx` | **Risk assessment** (methodology + 20-risk register, pre-populated) | Yaoyun validates + approves |
| `09_vendor_register.xlsx` | **Vendor/subprocessor register** (risk-ranked, SOC 2 / BAA columns) | Sec owner completes reviews |
| `10_CONTROL_TSC_MATRIX.md` + `10_control_tsc_matrix.xlsx` | **Control-to-TSC matrix** (BioMate controls → CC1–CC9, with status) | reconcile Vanta set |
| `11_ACTION_TRACKER.md` | Every open item — owner, priority, status, `[CONFIRM]` cluster | everyone |
| `12_MANAGEMENT_REPRESENTATION_LETTER.md` | End-of-fieldwork rep-letter shell | Yaoyun signs later |
| `TEAM_REVIEW_SUMMARY.md` | Summary + double-check list for engineering | Eng team |
| `policies/` | **Draft policy pack (13 policies + index)** — `policies/00_POLICY_INDEX.md` | Yaoyun + owners adopt |
| `templates/` | **Recurring-evidence templates:** onboarding/offboarding checklist, access-review workbook | use each period |
| `evidence/` | Collected artifacts (empty) | fill during remediation |

## The three hard truths driving everything
1. **Management writes the System Description — the auditor won't, and Vanta template language gets it returned.** All drafts here are built from BioMate's real architecture and flag `[CONFIRM]` where a fact must be verified.
2. **SOC 2 has no remediation window.** Controls must be live and evidenced from day one of the observation period — so we set that start date only after we're genuinely ready.
3. **Readiness is a scheduling gate** (Sentry wants Vanta Control Readiness ≥ 85%), and slipping fieldwork risks the SOW's ~120% rescheduling penalty. Get ready first; schedule second.

## Honesty contract
Every draft distinguishes what is verified from repo/config vs. what needs management confirmation (`[CONFIRM]`). Nothing here claims a control BioMate doesn't actually operate (e.g., MDM was not found and is not asserted). This is deliberate: overstated controls become audit findings.

## Immediate next actions
1. Read `01` → send the 5-item clarification email to Sentry/Workstreet → sign when answered.
2. Resolve the `[CONFIRM]` cluster (IdP, HRIS, MDM, VPN, MFA-in-prod, background checks, training, risk-assessment date, customer status, Workstreet role).
3. Start Priority-1 remediation in `02` (risk assessment, control reconciliation + owners, policies).
4. Return the filled questionnaire (`03_*.xlsx`) once `[CONFIRM]`s are resolved.
