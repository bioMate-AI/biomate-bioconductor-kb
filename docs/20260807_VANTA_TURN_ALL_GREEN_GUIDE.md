# Vanta — Complete "Turn Everything Green" Guide

**Date:** 2026-08-07
**State:** 120/151 passing (79%). Automated 99/114, Documents 21/37.
**Cause of the overnight drop (111→99 automated):** Vanta's AWS/GitHub
integration completed a deeper full-estate scan ~17h ago; real config gaps
across 72 log groups / 17 S3 buckets / IAM users / GitHub accounts surfaced at
once. Nothing was "broken" — these were always non-compliant; Vanta now sees
all resources.

Verified facts (AWS read-only, account 399683337364):
- IAM password policy IS configured and strong (14-char, complexity, 90-day expiry).
- 3 IAM access keys are >90 days: `galaxy-dev` (2025-12-23), `biomate-ses-smtp`
  (2026-04-16), `biomate-admin` (one key from 2026-04-29). `biomate-admin` has 2 active keys.
- Root was last used 2026-07-30 (so root-unused clears ~2026-08-29 if unused).
- CloudTrail bucket `biomate-cloudtrail-logs-399683337364` exists (CloudTrail on).
- 72 CloudWatch log groups all retain <365 days (15×14d, 51×180d, 6×7d).

---

## PART 1 — Quick Vanta clicks (no AWS/GitHub needed)

1. **Select training** (fixes `Security awareness training selected` +
   `HIPAA … selected`): Personnel → Groups → enable Vanta built-in Security
   Awareness Training (general + HIPAA) for the default group.
2. **Complete training** (fixes `… training completion` ×2): each person opens
   their Vanta task and completes the training modules.
3. **Vendor auth method** (fixes `Vendors have authentication method specified`):
   Vendors → open each vendor → set Authentication method (SSO / Password+MFA).
4. **Inventory user-data** (fixes `Inventory list tracks resources with user data`):
   Inventory/Resources → tag `biomate-production-data-...` (S3) and the RDS
   instance as **contains user data**.
5. **Account ↔ person mapping** (fixes `AWS accounts reviewed` +
   `GitHub accounts associated with users`): Vanta **Access** page → assign each
   AWS IAM user (galaxy-dev, biomate-admin, biomate-ses-smtp) and each GitHub
   account to a person, or mark service accounts as **non-human**.
6. **Access reviews** (fixes `Proof of completed access review` +
   `Access request ticket and history`): Vanta → Access Reviews → start & complete
   a review now that Google-synced personnel exist.

---

## PART 2 — GitHub (org settings)

7. **Require 2FA** (fixes `MFA on GitHub`): GitHub → Org **Settings** →
   Authentication security → **Require two-factor authentication** for everyone.
8. **Private repos** (fixes `GitHub repository visibility set to private` —
   2 repos public): for each public non-fork repo → repo Settings → Danger zone →
   Change visibility → **Private**. (If one MUST stay public, deactivate that entity.)
9. **Branch protection** is already GREEN — keep the rule (require PR approval +
   include admins) so `code-review` tests stay green as you keep merging.

---

## PART 3 — AWS config (mostly one-time, in AWS Console)

10. **IAM access key rotation** (fixes `IAM keys must not be >90 days`):
    IAM → Users → for `galaxy-dev`, `biomate-ses-smtp`, and `biomate-admin`'s
    2026-04-29 key: create a new key, update where it's used, then **deactivate +
    delete the old key**. Also remove the extra 2nd active key on biomate-admin.
    ⚠️ `galaxy-dev` key is in your ~/.aws — update local config after rotating.
11. **CloudWatch log retention ≥365d** (fixes `Server logs retained 365 days` —
    72 groups): CloudWatch → Log groups → select all → **Actions → Edit retention
    → 400 days (or Never expire)**. Repeat in every region that has log groups
    (us-west-2 has 72; check us-east-1 too).
12. **CloudTrail** (fixes `CloudTrail enabled` — "2 items"): CloudTrail appears
    enabled (log bucket exists). If still red, it's likely a 2nd AWS account or a
    non-multi-region trail → create a **multi-region** trail in each account.
13. **Password policy** (fixes `Password policy configured` — "2 items"): already
    configured on account 399683337364. If red persists, a 2nd AWS account lacks
    one → set the same policy there (IAM → Account settings → password policy).
14. **Root account** (fixes `Root infrastructure account unused`): stop logging in
    as root (last use 2026-07-30). Auto-greens ~2026-08-29 if root stays unused.
    Ensure root has MFA and no access keys.

---

## PART 4 — AWS "costs money" → enable OR deactivate with justification

15. **S3 Cross-Region Replication** (`S3 backup configured for redundancy` —
    17 buckets): only 2 buckets hold critical data and may warrant CRR:
    `biomate-production-data-399683337364`, `biomate-production-backups-399683337364`.
    - Enable CRR on those 2 if you want DR (extra storage cost), OR deactivate them too for now.
    - **Deactivate CRR** for the other 15 (temp/logs/config/test/reference):
      biomate-cloudtrail-logs, biomate-compliance-evidence, biomate-config-delivery,
      biomate-cryo-data, biomate-cryoem-benchmark, biomate-models, biomate-nextflow-outputs,
      biomate-nextflow-work, biomate-structure-db, biomate-terraform-state, biomate-test-data,
      biomate-workflow-inputs, galaxy-cloud-data-*, knowledge-datasets-*, parallelcluster-*.
      Reason: `Non-DR bucket (temporary/derived/log data); cross-region replication not required.`
16. **RDS Multi-AZ** (`RDS Multi-AZ deployment configured` — 2 instances):
    Multi-AZ ~doubles DB cost. Either enable (RDS → Modify → Multi-AZ) for prod,
    or **Deactivate + reason**: `Single-AZ acceptable at current stage; Multi-AZ planned before GA.`

---

## PART 5 — Documents (upload / screenshot)

17. **Vulnerability scan** + **Sample of remediated vulnerabilities**: AWS Inspector
    → screenshot the findings list + one resolved finding → upload to each test → Submit.
18. **Vendor security review** (`third-party-security-reviews`): upload a short
    vendor security review report (list critical vendors + their SOC 2 / security posture).

---

## PART 6 — Leave alone
19. **`Test of incident response plan`** — observation-window gated; auto-greens
    once the SOC 2 audit observation window is active. Do NOT deactivate.

---

## Recommended order (fastest score recovery)
Part 1 (Vanta clicks) → Part 2 (GitHub 2FA + private) → Part 3 #11 (log retention
bulk) + #10 (key rotation) → Part 4 (deactivate the 15 non-DR buckets + decide
RDS/prod buckets) → Part 5 (screenshots) → root auto-clears.

After each batch, Tests → Status filter → watch the count drop. Automated should
climb back past 111 and higher.

---

## UPDATE 2026-08-07 (evening) — 6 automated tests fixed via backend CLI (biomate-admin SSO)

AWS Org discovered: `o-36ybtz6cni`, management account **399683337364 (biomate)**,
members **022957193291 (Yuankai)** + **970597967666 (Henry)**. The "2 items"
failures were these 2 member accounts.

Fixed by CLI this session (all pending Vanta re-scan to flip green):
1. **Server logs retained 365 days** — set retention 400d on ALL log groups
   (us-west-2 ×78, us-east-1 ×7) via `aws logs put-retention-policy`.
2. **Route53 query logging** — created log group `/aws/route53/biomate-dns`
   (us-east-1) + resource policy + query-logging-config on both public zones
   (dev-public Z03470822JJ4UEOYJ53ZE, stage-public Z0363771X6YPSJQMFRN8).
3. **AWS accounts reviewed** — tagged IAM users galaxy-dev, biomate-ses-smtp,
   biomate-admin with `VantaOwner=yaoyun.zhang@biomate.ai`.
4. **S3 buckets allow only HTTPS** — added DenyInsecureTransport bucket policy to
   the 2 DR replica buckets (…-data-dr-usw2, …-backups-dr-usw2).
5. **Password policy configured** — assumed OrganizationAccountAccessRole into
   both member accounts, set strong policy (min 14, complexity, 90d, reuse 12).
6. **CloudTrail enabled** — converted `biomate-audit-trail` to an ORG trail
   (enabled cloudtrail trusted access + added org PutObject path to the
   cloudtrail bucket policy + `update-trail --is-organization-trail`). Verified
   IsLogging=true. Now covers all 3 accounts.

### Still pending (decisions / non-CLI)
- **RDS Multi-AZ** (biomate-postgres prod + biomate-test-galaxy test, both
  db.t3.micro): recommend enable Multi-AZ on prod via maintenance window
  (~$12/mo, zero-downtime) + Deactivate the test DB entity in Vanta. AWAITING user A/B/C.
- **IAM key rotation** (galaxy-dev=deploy, biomate-ses-smtp=email, biomate-admin):
  HOLD — rotating breaks live services; do carefully with knowledge of each key's use.
- **GitHub**: biomate-connector (public — Deactivate as intentional OSS),
  biomate-bioconductor-kb (make Private); henryhang enable 2FA.
- **Vanta UI**: S3 CRR — Deactivate the 15 non-DR buckets; inventory tag user-data;
  vendor auth method; select+complete training; /access map GitHub accounts.
- **Root**: auto-clears ~2026-08-29 if unused.
