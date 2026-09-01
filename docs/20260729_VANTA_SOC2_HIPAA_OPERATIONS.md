# Vanta SOC 2 + HIPAA — Compliance Operations Log & Runbook

**Date:** 2026-07-29
**Org:** biomate.ai (Vanta: https://app.vanta.com/c/biomate.ai/)
**Frameworks in scope:** SOC 2 (Security) + HIPAA (Covered Entity)
**Driver:** Yaoyun Zhang (yaoyun.zhang@biomate.ai) — Org Admin
**Tooling:** Vanta hosted MCP server (`https://mcp.vanta.com/mcp`, OAuth, Admin-only),
connected to Claude Code via project `.mcp.json`.

> Key business fact driving decisions: **BioMate AI does not currently process PHI.**
> Customer data = de-identified research/genomic data, molecular structures,
> public reference datasets. HIPAA controls are maintained "ready" so that a BAA /
> covered-entity relationship can be onboarded later with zero rework.

---

## 1. Starting state (2026-07-29)

| Framework | Controls | Documents | Tests |
|---|---|---|---|
| HIPAA (Covered Entity) | 28/135 | 0/51 | 24/30 |
| SOC 2 (Security) | 21/80 | 0/43 | 22/29 |

Dashboard: **34/94 tests passing (36%)** — Automated 78% (28/36), Documents 10% (6/58).
Integrations connected: **none**. Policies: 19 (all approved 2026-07-27).

---

## 2. Hard constraints discovered (MCP capability boundary)

1. **MCP cannot connect integrations.** AWS / GitHub / Google Workspace must be
   connected in the Vanta UI (OAuth / IAM-role). No MCP write tool exists for this.
2. **MCP cannot finalize/submit evidence.** MCP can upload → attach → AI-evaluate a
   document, but it lands in **DRAFT**. The final **Submit** (which flips the test
   green) is a **UI-only** click. No `finalize`/`submit` MCP tool exists.
3. **MCP cannot take a risk-register snapshot.** UI-only.
4. **MCP cannot mark a test "Not Applicable" / Deactivate.** UI-only (⋯ menu).
5. **Never fabricate evidence.** Pen-test reports, training-completion records,
   access-review sign-offs, tabletop notes, breach reports = real artifacts only.

### Upload pipeline that works (for reference)
`upload_local_file` → returns presigned S3 POST fields (⚠️ 15-min expiry) →
`curl` multipart POST (204) → `uploadDocumentFromS3(s3Key)` → `addDocumentsToEvidenceRequest` →
`evaluateEvidence`. Presigned fields expire in 15 min — request + upload in one go.

---

## 3. COMPLETED via MCP (this session)

### 3.1 Risk register — 10 risk scenarios (register "Default")
All with owner = yaoyun.zhang@biomate.ai, inherent + residual scored, treatment = Mitigate.
Includes **2 Privacy-category risks** (required for `hipaa-risks-reviewed-annually`).

| ID | Risk | Category |
|---|---|---|
| R-1 | Exposure/disclosure of PHI or sensitive research/genomic data | Privacy |
| R-2 | Unauthorized access to production AWS infra | Access Management |
| R-3 | Loss of platform availability | Availability |
| R-4 | Data loss / failed restore | Data Management |
| R-5 | Vulnerability in app code / dependency | Vulnerability Management |
| R-6 | Third-party / sub-processor compromise | Vendor Management |
| R-7 | Credential compromise via phishing | Access Management |
| R-8 | Insider threat / privileged misuse | Access Management |
| R-9 | Ransomware / malware | Endpoint Security |
| R-10 | Non-compliance with privacy obligations (HIPAA/GDPR/CCPA) | Privacy |

### 3.2 Evidence documents authored + uploaded (12) — status = DRAFT, AI-evaluated
All local sources under `/tmp/vanta_evidence/`. All passed Vanta's AI evidence check
unless noted. **User must click Submit in UI to turn each green.**

| Evidence request | Doc | AI check |
|---|---|---|
| phi-accounting-of-disclosures-log | N/A statement (no PHI) | ✅ |
| baa-template | BAA template | ✅ |
| phi-minimum-necessary-access-matrix | Role→PHI access matrix | ✅ |
| system-description | SOC 2 §III system description | ✅ (drop "DRAFT" note) |
| network-diagram | Textual/ASCII architecture | ✅ (confirm region/VPC) |
| privacy-official-designation-record | Privacy Official = Yaoyun Zhang (FINAL) | ✅ |
| application-session-timeout | Real 15-min timeout code (security-config.ts) | ✅ |
| msa-template | MSA template | ✅ |
| privacy-compliance-policy | Privacy compliance policy | ✅ |
| security-job-descriptions | Key security/privacy role descriptions | ✅ |
| policy-exists-termination | Employee termination security policy | ✅ |
| hipaa-notice-of-privacy-practices | Notice of Privacy Practices | ⚠️ needs distribution proof → **Deactivate** (no PHI) |

> `application-session-timeout` uses REAL config: `frontend/server/security-config.ts`
> `sessionTimeout: 15` + `sessionTimeoutMiddleware` (HIPAA §164.312(a)(2)(iii)).
> For `privacy-official-designation-record` there are 2 files attached — delete the
> non-FINAL one in UI before submitting.

---

## 4. DONE by user in UI (as of this session)

- Deactivated a batch of pure-N/A HIPAA PHI evidence requests (⋯ → Deactivate).
- Took / located risk-register snapshot (Risk → Overview).
- (Confirm exact list against live dashboard.)

---

## 5. PENDING — user UI actions (ordered by leverage)

### 5.1 Submit the 12 DRAFT evidence docs (Task "1")
Tests → search each name → open → **Submit** (set effective date = today if asked).
Turns them green. (Delete the non-FINAL privacy-official file first.)

### 5.2 Deactivate remaining pure-N/A items (Task "A")
⋯ → Deactivate, paste the standard reason (Appendix A). Items:
Signed BAA (baa-example), Privacy complaint log, Customer data deletion record,
Removable media encryption, Employee termination checklist, Board of directors CVs,
Board of directors charter, Bug Bounty program, Incident report/RCA example,
Notice of Privacy Practices (per §3.2 gap).

### 5.3 Connect integrations (Task "4") — biggest automated-test lever
Integrations → Connect:
- **Google Workspace** (IdP) → `idp-linked-to-vanta`, access reviews, personnel sync
  (unblocks HR tests + HIPAA Security Officer designation).
- **GitHub** → CI/CD in use, public change log, internal-comms-for-updates.
- **AWS** (CloudFormation read-only role → paste Role ARN) → `infra-linked-to-vanta`,
  network segregation, log alerting, firewall review, cloud-provider agreement.
- **AWS Inspector** (after AWS) → `vulnerability-scanner-linked` (the one OVERDUE test),
  vulnerability-scan, remediated-vulnerabilities-sample.

### 5.4 Vanta config clicks (Task "C") — after Google Workspace
- Select a Security Awareness Training program → `security-training-records` (+ HIPAA).
- Designate **HIPAA Security Officer = Yaoyun Zhang** (Settings).
- Add ≥1 vendor manually (Vendors page, e.g. AWS) → `vendor-management-records`;
  run a vendor security assessment → `high-severity-vendor-compliance-reports`.

### 5.5 Provide public URLs (Task "E") — Tests → Add URL
privacy-policy, terms-of-service, security-page, status-page, product-documentation,
customer-support-site, public-change-log. (Deactivate any that don't exist yet.)

### 5.6 Real activities (Task "F") — schedule or defer
Pen test + remediation; cyber-insurance policy (or deactivate, optional);
data restore test; DR tabletop + IR plan test; vendor security review;
AWS Artifact cloud-provider agreement download.

---

## 6. Framework strategy note

Pursuing HIPAA Covered Entity with **no PHI today** means ~20+ PHI evidence requests
are legitimately N/A / Deactivated. This is defensible ("we do not process PHI; controls
are ready pending a BAA") but an auditor will ask why HIPAA is in scope. Revisit whether
to keep HIPAA active now vs. activate when a PHI/BAA customer materializes. SOC 2 has no
such tension and should be the primary near-term target.

---

## Appendix A — Standard N/A reason (paste when Deactivating)

```
BioMate AI does not currently create, receive, maintain, or transmit PHI/ePHI, and
has not received any requests or disclosures of this type. As no such activity has
occurred, this evidence request is Not Applicable. This determination is reviewed at
least annually and before any PHI is onboarded under a Business Associate Agreement.
```

## Appendix B — "Complete certification" reality

Getting these green ≠ a SOC 2 / HIPAA report. A **third-party auditor** must run an audit
window and issue the report. MCP + this runbook get the Vanta program audit-ready; booking
the auditor and the observation period is a separate, human step.
