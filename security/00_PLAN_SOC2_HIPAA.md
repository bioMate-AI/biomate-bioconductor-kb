# BioMate AI — SOC 2 Type 2 & HIPAA Compliance: Master Plan

**Owner:** Yaoyun Zhang (Client Contract Manager)
**Auditor:** Sentry Assurance, LLC — contact: matt.drewyor@sentryassurance.com
**Compliance platform:** Vanta
**Audit funding:** billed to Workstreet (see SOW review)
**Plan date:** 2026-09-01
**Status:** DRAFT — plan for review before executing the document-production phase

---

## 0. What we were asked to do

1. **Review the SOW/PSA** — flag any problems; if none, it gets signed. → `01_SOW_REVIEW_MEMO.md`
2. **Self-examine our current status** against the three Sentry documents (Readiness Self-Assessment, System Description & CUEC Guide, Scoping Intake Questionnaire). → `02_READINESS_SELF_ASSESSMENT.md`
3. **Prepare the requirement documents as instructed** — the management-authored System Description, the CUEC mapping table, and the management acknowledgment (the guide's "Required Client Deliverable"), plus the evidence/policy set. → `04_*`, `05_*`, `06_*`, `07_*`
4. **Address the Scoping Intake Questionnaire** — fill the Excel. → `03_*`
5. **Create a dedicated Security folder** under `biomate/`. → this folder.

---

## 1. What the engagement actually is (from the SOW)

| Item | Value |
|---|---|
| Report type | **SOC 2 Type 2** (period-based, tests operating effectiveness) |
| Standard | AT-C 105 & 205 (AICPA attestation) |
| Trust Services Criteria in scope | **Security / Common Criteria ONLY** (no Availability, Confidentiality, Processing Integrity, or Privacy) |
| System in scope | "BioMate AI Assistant Services System" |
| SOC 2 location | Bellaire, TX |
| Review period | **TBD — "to be mutually agreed"** (a decision we must make; see §5) |
| Description criteria | DC section 200 (2018, revised 2022) |
| TSC | TSP section 100 (2017, revised 2022) |
| Report | Restricted-use PDF |

**Critical framing facts (from the two Sentry guides):**
- The **System Description is audited subject matter**, not a preamble. Management (us) must author it. Sentry cannot write it, choose disclosures, or pick our CUECs (AICPA independence rule ET 1.295.030). Vanta only supplies a scaffold — **its template language will be rejected**.
- The description must be **delivered and cleared through Sentry's description-criteria review BEFORE kickoff** — submit ≥10 business days before the requested kickoff date; Sentry returns comments in ~5 business days. A late/returned description **moves the audit**, it does not compress it.
- **SOC 2 has no remediation window.** Controls must be designed and operating effectively **from the first day of the observation period.** This drives our start-date decision.

---

## 2. HIPAA — important scope note

**The signed SOW covers SOC 2 Type 2 Security only. It does NOT include HIPAA.**

HIPAA is a separate framework. In the Vanta model it is typically run as:
- The **Vanta HIPAA framework** (mapping our controls to the HIPAA Security Rule / Privacy Rule / Breach Notification safeguards), plus
- Either a **HIPAA gap assessment / attestation** by the same auditor under a separate SOW, or a **SOC 2 + HIPAA combined report** (SOC 2 controls mapped to HIPAA).

**Action:** Confirm with Sentry/Workstreet whether HIPAA is (a) a separate future SOW, (b) an add-on to this examination, or (c) handled purely inside Vanta as a self-attested framework. This plan proceeds with SOC 2 Security as the committed path and treats HIPAA readiness as a parallel track (§7) because — given BioMate ingests biomedical and potentially clinical/health data — HIPAA (and a BAA posture with customers) is likely a real customer requirement.

**Also flag for a scope decision:** For a platform handling sensitive biomedical/health data, enterprise customers frequently expect **Confidentiality** and **Availability** TSC in addition to Security. Adding them later is a re-scope. Decide now whether Security-only meets our sales needs (see SOW review, item on scope).

---

## 3. The three Sentry documents and what each demands

### 3a. Engagement Readiness Self-Assessment (9 domains)
A gate to scheduling. We must honestly confirm all boxes across 9 domains, then sign the attestation. **We cannot honestly check every box today** — the honest output is a gap list. Domains:
1. Scope & Framework · 2. Controls Defined · 3. Control Owners · 4. Integrations & Automated Tests · 5. People, Access & Training · 6. Policies & Documentation · 7. System Description · 8. Supplemental Evidence · 9. Vendors & Risk.
→ Self-assessed honestly in `02_READINESS_SELF_ASSESSMENT.md`.

### 3b. System Description & CUEC Development Guide
Defines the required deliverable: a management-authored System Description addressing **9 description criteria (DC1–DC9)** + a **CUEC mapping table** (4 columns: CUEC · commitment it supports · complementary control · applicable TSC) + a **signed Management Acknowledgment**.
Eight "tells" that get a description returned: placeholders, tech we don't run, verbatim template phrasing, aspirational tense ("committed to," "best-in-class"), control text contradicted by evidence, copied CUEC blocks, orphaned subservice orgs, boundary/change silence.
→ Draft in `04_SYSTEM_DESCRIPTION_DRAFT.md`, `05_CUEC_MAPPING_TABLE.md`, `06_MANAGEMENT_ACKNOWLEDGMENT.md`.

### 3c. Scoping Intake Preparedness Questionnaire (Excel)
Two working sheets — **Audit Preparedness** (7 readiness items) and **Tooling and Tech Stack** (core infra, IAM, misc, change mgmt, asset mgmt, and a dedicated **Use of AI** section). Notable: it explicitly probes AI risk controls — directly relevant to us.
→ Answered in `03_SCOPING_QUESTIONNAIRE_ANSWERS.md` and the filled workbook `03_scoping_questionnaire_FILLED.xlsx`.

---

## 4. Deliverables produced in this folder

| File | What it is | Depends on | Who finalizes |
|---|---|---|---|
| `00_PLAN_SOC2_HIPAA.md` | This plan | — | Yaoyun |
| `01_SOW_REVIEW_MEMO.md` | Legal/commercial review of the PSA+SOW | — | Yaoyun / counsel |
| `02_READINESS_SELF_ASSESSMENT.md` | Honest 9-domain gap analysis + remediation list | repo facts | Yaoyun |
| `03_SCOPING_QUESTIONNAIRE_ANSWERS.md` | Narrative answers to the intake questionnaire | repo facts | Yaoyun |
| `03_scoping_questionnaire_FILLED.xlsx` | The Excel, filled | repo facts | Yaoyun |
| `04_SYSTEM_DESCRIPTION_DRAFT.md` | Management draft of the System Description (DC1–DC9) | repo facts | Yaoyun (authors), control owners (verify) |
| `05_CUEC_MAPPING_TABLE.md` | CUEC mapping table | System Description | Yaoyun |
| `06_MANAGEMENT_ACKNOWLEDGMENT.md` | Sign-off template for the description | 04, 05 | Yaoyun signs |
| `07_EVIDENCE_AND_POLICY_INDEX.md` | Required policies & evidence, with status/owner | repo facts | Yaoyun + owners |

**Honesty contract for every draft:** any statement I cannot verify from the repo is marked `[CONFIRM]` with the specific fact needed. Nothing aspirational, nothing first-person, no technology we don't run — because those are exactly the defects Sentry returns descriptions for. These drafts are **starting points for management to verify and own**, not finished submissions.

---

## 5. Sequenced roadmap (recommended order of operations)

**Phase A — Contract (now)**
1. Review SOW (`01`). Resolve the flagged items with Sentry/Workstreet. Sign PSA + SOW.

**Phase B — Readiness & scoping (weeks 1–2)**
2. Finalize the self-assessment (`02`); turn every unchecked box into a tracked remediation task with an owner.
3. Fill and return the scoping questionnaire (`03`).
4. **Decide the observation period.** SOC 2 Type 2 tests a *period* (commonly 3 months for a first Type 2, or a Type 1 "as-of" date first, then Type 2). Because there is no remediation window, the period start must be a date on which all in-scope controls are already live. Recommendation: pick the start date only after Vanta Control Readiness ≥ 85–95% (Sentry's fieldwork gate) and all policies are published + acknowledged.

**Phase C — Controls & evidence (weeks 2–8, overlaps B)**
5. In Vanta: customize the control set to operational reality (do not ship template controls), assign a named owner to every control, connect all integrations, clear/annotate automated tests, drive Control Readiness to ≥ 85%.
6. Publish all required policies; get employee acknowledgment. Stand up recurring evidence (access reviews, change tickets, onboarding/offboarding, training). See `07`.
7. Complete the org risk assessment, vendor inventory + risk ranking + vendor security reviews, and (if required) a penetration test and BC/DR test.

**Phase D — System Description (before kickoff)**
8. Author the System Description from the `04` draft — replace every `[CONFIRM]` with a verified fact; control owners confirm each described control is performed as written.
9. Build the CUEC mapping table (`05`); keep it short — most SaaS orgs need very few genuine CUECs.
10. Run Management's self-review checklist (in the guide); sign the acknowledgment (`06`).
11. Submit description + CUEC table + acknowledgment to Sentry **≥10 business days before** the requested kickoff.

**Phase E — Fieldwork**
12. After description clears review and Vanta readiness ≥ 85%, book kickoff. Provide populations (new hires, terminations, current employees, incidents, change tickets) as **auditable system queries**, not written lists — including proving zero-populations return null.
13. Sign the management representation letter (required for the opinion).

**Parallel track — HIPAA (§2):** confirm scope; enable the Vanta HIPAA framework; map SOC 2 controls to HIPAA safeguards; put BAAs in place with subprocessors that touch PHI and offer BAAs to customers.

---

## 6. Top risks / watch-items (detail in the individual docs)

- **Vanta template language in the System Description → automatic return and a moved kickoff.** Highest-probability failure mode. We author from our real architecture.
- **Controls that don't match reality** (e.g., a control claims MDM/quarterly access reviews we don't actually run) → findings. Every control must be reconciled to what we truly do *before* the period starts.
- **No remediation window** → do not start the observation period until controls are genuinely operating.
- **Populations must be query-backed**, including zero-populations.
- **AI-specific risk controls** — the questionnaire explicitly asks; if AI is core to the service and there are no AI risk considerations in the risk assessment / vendor mgmt / acceptable-use policy, it becomes a fieldwork issue. We should get ahead of this.
- **Subservice organizations** (AWS and any other hyperscaler/managed service) must be identified with the carve-out method and specific CSOCs, not generic language.

---

## 7. Open decisions requiring the founder (not derivable from repo/code)

These are flagged as `[CONFIRM]` throughout the deliverables:
- Observation period type (Type 1 first vs. straight Type 2) and start date.
- HIPAA scope and timing (§2); whether to add Confidentiality/Availability TSC.
- Corporate IT facts: primary IdP (Google Workspace / Entra), HRIS, MDM tool, background-check process, security-awareness training tool.
- Whether a penetration test and BC/DR test have been performed and their dates.
- Risk assessment completion date; vendor inventory owner.
- The finance/commercial relationship with Workstreet (who pays, total contract value for the rescheduling-fee clause).
