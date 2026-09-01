# Vanta — Remaining Tasks: Click-by-Click Operation Guide

**Date:** 2026-08-02
**Audience:** Yaoyun Zhang (non-expert). Follow top to bottom.
**Scope:** The ~44 tests still red after AWS+GitHub connected. Google Workspace
is intentionally EXCLUDED (cannot be configured). Everything else here is doable.

**Standard N/A reason (paste when Deactivating anything):**
> BioMate AI does not currently create, receive, maintain, or transmit PHI/ePHI,
> and this control/artifact is not currently applicable. This will be revisited
> before any PHI is onboarded under a Business Associate Agreement.

General navigation: left menu = **Tests / Compliance / Risk / Vendors /
Personnel / Integrations**. To open a test: **Tests** → type its name in the
search box → click the row. Filter by **Status = Needs remediation** to see reds.

---

## STEP 1 — Submit the 2 evidence docs already prepared (fastest)
Evidence is uploaded + AI-approved; you only click Submit.
For each: **Tests** → search → open → find the uploaded file under **Evidence** →
click **Submit** (if asked for an **Effective date**, pick **today**).
1. `Network segregation`  → file `network-segregation.txt`
2. `Firewall reviewed annually` → file `annual-firewall-review.txt`
Result: both turn green.

---

## STEP 2 — Add yourself as Personnel (unlocks HR items without Google)
Because Google isn't connected, Vanta has no employee list. Add people manually.
1. Left menu → **Personnel** → **People**.
2. Click **Add person** (top right).
3. Enter name = Yaoyun Zhang, email = yaoyun.zhang@biomate.ai, role/title.
   Add any other real team members the same way.
4. Save.
This makes the next two steps possible.

---

## STEP 3 — Designate the HIPAA Security Officer
Fixes `HIPAA Security Officer is an active employee`.
1. Left menu → **Settings** (gear, top right) → find **Roles** / **HIPAA** /
   **Business information** (name varies) → **HIPAA Security Officer**.
2. Select **Yaoyun Zhang** (must exist in Personnel from Step 2).
3. Save.

---

## STEP 4 — Select a Security Awareness Training program
Fixes `Security awareness training selected` + `HIPAA security awareness training selected`.
1. Left menu → **Personnel** → **Groups** (or **Settings → Training**).
2. Find **Security Awareness Training** → choose Vanta's **built-in training**.
3. Enable both **general** and **HIPAA** training categories.
4. Save/assign to the default group.
NOTE: `Security awareness training completion` + `HIPAA … completion` only go
green after the assigned people actually COMPLETE the training. Assign it to
yourself (Step 2 person) and complete it to satisfy those too.

---

## STEP 5 — Add a Vendor + do a security assessment
Fixes `Vendors list maintained`, `Company completes security assessments…`,
`Vendor security review`.
1. Left menu → **Vendors** → **Add vendor** (top right).
2. Add a real vendor you use, e.g. **OpenAI** or **Anthropic** or **Stripe**
   (something NOT auto-detected). Set a risk level.
3. Open that vendor → **Assessment** / **Security review** → run/complete a
   basic security assessment (attach the vendor's SOC 2 or security page link,
   or fill the questionnaire). Save.

---

## STEP 6 — Two AWS changes (AWS Console)
### 6a. Enable pgaudit on RDS PostgreSQL — fixes `RDS … pgaudit auditing enabled`
(Confirmed: your DB `biomate-rds-sg` runs PostgreSQL on 5432, so this applies.)
1. AWS Console → **RDS** → **Parameter groups**.
2. If your DB uses the default group, **create a new DB parameter group**
   (same family, e.g. postgres15) and later attach it; you can't edit defaults.
3. Edit the parameter group:
   - `shared_preload_libraries` → add `pgaudit` (e.g. `pg_stat_statements,pgaudit`).
   - `pgaudit.log` → set to `write,ddl` (or `all`).
4. RDS → **Databases** → your instance → **Modify** → set its **DB parameter
   group** to the new one → apply.
5. **Reboot** the instance (shared_preload_libraries needs a restart).
   ⚠️ Brief downtime — do it in a low-traffic window.

### 6b. Enable Route 53 query logging — fixes `Route53 query logging enabled`
(You have 2 public zones: dev-public.biomate.ai, stage-public.biomate.ai.)
1. AWS Console → **Route 53** → **Hosted zones** → open **dev-public.biomate.ai**.
2. **Configure query logging** → create/select a **CloudWatch Logs log group**
   (Route 53 needs it in **us-east-1**) → confirm.
3. Repeat for **stage-public.biomate.ai**.

---

## STEP 7 — Paste public links (Tests → open → Add URL)
If the page exists, open the test → **Add URL** → paste → save. If it does NOT
exist, open the test → **⋯ → Deactivate** with the standard reason.
| Test | What to paste |
|------|---------------|
| Publicly available privacy policy | your website privacy-policy URL |
| Publicly available terms of service | your ToS URL |
| Security information page | your security page / whitepaper URL |
| Application status page | your status page URL (or Deactivate) |
| Product documentation site | your docs site URL |
| Customer support site or email alias | support page or support@ email |
| Public change log or release notes | a PUBLIC GitHub Releases page URL (make Releases public) or Deactivate |
| Anonymous whistleblower channel | link/email of an anonymous reporting channel (or Deactivate) |

---

## STEP 8 — Upload screenshots (Tests → open → Upload)
Text won't pass these; Vanta wants a picture. Screenshot, then Upload (set
effective date = today).
| Test | Screenshot to take |
|------|--------------------|
| CI/CD system in use | GitHub → repo → **Actions** tab → the list of successful **Deploy** runs |
| Internal communication for system updates | the **deploy notification email** (SNS `biomate-deploy-events`) or a Slack deploy message |
| Vulnerability scan | AWS **Inspector** → Findings list |
| Sample of remediated vulnerabilities | one Inspector finding marked resolved, or a fix ticket |
| Application access request denied log | an app/auth log line showing a denied login (401/403) |

---

## STEP 9 — Deactivate (can't produce / optional / not applicable)
Open test → **⋯ → Deactivate** → paste a short reason.
| Test | Reason |
|------|--------|
| Penetration test report | "Pen test scheduled before audit; not yet performed." |
| Penetration test remediation | "Pending completion of the penetration test." |
| Cybersecurity insurance policy document | "Optional control; cyber insurance not currently procured." |
| Data restore test | "Action item A5 from 2026-07-30 DR tabletop; target 2026-09-15." |
| Intrusion detection system installation | "No dedicated IDS; will enable AWS GuardDuty if required." |
| Cloud provider service agreement | download from **AWS Console → Artifact → Agreements** and upload, OR Deactivate |

---

## STEP 10 — Leave alone (will auto-green during the audit)
- `Test of incident response plan` — evidence is in place; it is
  **observation-window gated** and turns green only once your SOC 2 audit
  observation window is active. Do NOT deactivate.

---

## Blocked without Google Workspace (accept as pending)
These need an Identity Provider integration and cannot be done manually:
- `Identity provider linked to Vanta`
- `Proof of completed access review`
- `Access request ticket and history`
(If you later connect Google/Okta, they clear automatically. Until then they
remain red — that's expected, not an error.)

---

## Suggested order (fastest wins first)
Step 1 (submit 2) → Step 9 (deactivate 5-6) → Step 5 (vendor) → Step 4 (training)
→ Step 2+3 (personnel + officer) → Step 7 (paste URLs you have) → Step 8
(screenshots) → Step 6 (AWS pgaudit/route53).

After a batch, re-check **Tests → Status: Needs remediation** to watch the count drop.

---

## UPDATE 2026-08-02 (evening) — remaining ~26

Green since last update: pen-test ×2, cyber-insurance, data-restore, ids-ips,
cloud-provider-agreement (deactivated); network-segregation, firewall-review,
CI/CD (submitted). New red surfaced: `vendors-have-authentication-method-specified`
(appeared after vendors were added — each vendor needs an auth method set).

### Still to do, by action:

**A. Automated — no Submit; do the real thing, it auto-greens**
- security-training-records / hipaa-security-training-records → select a training program (Step 4)
- vendors-have-authentication-method-specified → Vendors → open each vendor → set Authentication method (SSO/Password+MFA)
- high-severity-vendor-compliance-reports → run a security assessment on each vendor
- aws-rds-pgaudit-enabled → enable pgaudit on RDS (Step 6a)
- aws-route53-query-logging-enabled → enable Route53 query logging (Step 6b)
- idp-linked-to-vanta → BLOCKED (needs Google/Okta; cannot do now)

**B. Document — paste a public URL (Add URL), or Deactivate if none**
- privacy-policy, terms-of-service, security-page, status-page,
  product-documentation, customer-support-site, public-change-log,
  anonymous-communication-channel

**C. Document — upload a screenshot**
- system-update-internal-communication → deploy-notification email / Slack
- vulnerability-scan → AWS Inspector findings
- vulnerabilities-remediated-sample → a resolved Inspector finding / fix ticket
- access-requests-denied-log → app log line of a denied login (401/403)
- system-activity-log-settings → CloudWatch alarm config (or Deactivate if no alerting)

**D. Needs personnel / training completion (partly blocked without Google)**
- sat-completion-bulk / hipaa-sat-completion-bulk → assign + COMPLETE the training
- access-requests / access-reviews → best done via IdP (Google) — leave pending or provide manual records

**E. Vendor review doc**
- third-party-security-reviews → upload your vendor security review report

**F. Leave alone (observation-window gated)**
- incident-response-plan-test
