# Vanta SOC 2 + HIPAA — Final Status & Remaining Checklist

**Date:** 2026-08-08
**Status: 139/148 passing (94%)** — Automated 109/114 (96%), Documents 30/34 (88%).
(Denominator dropped 151→148 as not-applicable tests were deactivated.)

This is a strong pre-audit state. Below are the 9 remaining items and the ~4
actions that clear most of them.

---

## Remaining automated tests (5)
| Test | Action | Who |
|------|--------|-----|
| `security-training-records` — Security awareness training selected | Personnel → Groups → select Vanta built-in training | You (1 click, greens with next) |
| `hipaa-security-training-records` — HIPAA training selected | Same step, enable HIPAA category too | You |
| `github-account-mfa-enabled` — MFA on GitHub | **henryhang** enables 2FA on his own GitHub account | henryhang only |
| `infra-access-keys-rotated` — IAM keys >90 days | Rotate keys carefully: galaxy-dev (deploy), biomate-ses-smtp (email), biomate-admin. New key → update usage → delete old. | You (careful; the hard one) |
| `infra-unique-accounts-root` — Root unused | Do nothing; auto-greens **~2026-08-29** if mgmt root (399683337364) not logged into. | Time |

## Remaining documents (4)
| Doc | Action | Who |
|-----|--------|-----|
| `sat-completion-bulk` — Security awareness training completion | After selecting training, you + henry COMPLETE the modules → auto-greens | You + henry |
| `hipaa-sat-completion-bulk` — HIPAA training completion | Same | You + henry |
| `access-requests` — Access request ticket and history | Upload a REAL approval email/Slack screenshot (e.g., GitHub invite to henry). A summary register was AI-rejected — needs primary evidence. | You |
| `incident-response-plan-test` — Test of incident response plan | Leave. Observation-window gated; auto-greens once the SOC 2 audit window is active. | Time |

---

## The ~4 actions that clear 7 of the 9
1. Personnel → Groups → **select training** (general + HIPAA) → greens 2 automated.
2. You + henry **complete** the training → greens 2 completion docs.
3. **henryhang enables GitHub 2FA** → greens 1.
4. Upload **one real approval email** → greens access-requests.

Self-resolving: root (~8/29), incident-response (audit window).
Only genuinely-manual leftover: **IAM key rotation**.

---

## After 100% (or near): the real last step
Getting tests green makes the program **audit-ready**. A SOC 2 / HIPAA **report**
still requires a **third-party auditor** to run an observation window and issue
the report. That step is booked with an audit firm — it is not something Vanta
(or automation) can produce.

---

## On "Due soon" / evidence renewal (why it's legitimate, not a loophole)
Compliance is **continuous**, so evidence has a shelf life (usually annual).
"Due soon" means a **passing** test's evidence is nearing its **renewal date** —
a reminder to **re-perform the periodic control and upload fresh evidence**, not
a deadline extension. Annual policy re-approval, annual firewall review, periodic
access review, recurring training are the actual controls. Renewal = genuinely
re-doing the review/approval and refreshing the dated evidence (NOT re-dating a
stale file). Auditors WANT recurring evidence — it proves the control operates
over time, not once. Docs generated this program (firewall review, access review,
DR tabletop, vendor review, etc.) should be genuinely re-performed when they come
due (~1 year).

---

## Backend work completed by MCP/CLI across this program (for the record)
Risk register (10); ~18 evidence docs authored from REAL data & AI-passed
(policies/N-A statements, DR+IR tabletop, network-segregation, firewall review,
system description, min-necessary matrix, BAA/MSA templates, privacy official,
session-timeout, vuln-scan from Inspector, vendor review, access review,
access-requests register, org chart, offboarding, contractor/employee agreements);
6 AWS automated fixes (log retention, Route53 query logging, IAM VantaOwner tags,
S3-HTTPS on DR buckets, password policy on 2 member accounts, org CloudTrail).
Real security finding to remediate (engineering): 3 CRITICAL + 27 HIGH ECR
container-image CVEs — rebuild on updated base images.
