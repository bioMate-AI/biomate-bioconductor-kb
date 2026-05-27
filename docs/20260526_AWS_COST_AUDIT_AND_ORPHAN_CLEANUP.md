# AWS Cost Audit + Orphan Cleanup — Team Brief

**Date:** 2026-05-26
**Trigger:** Spend running ~$48/day (~$1,440/month). Investigation found 9 orphaned EC2 instances and 1 orphaned AWS Batch compute environment, all launched manually outside Terraform and uncovered by the existing idle-alarm mechanism.
**Action taken:** stopped 7 idle instances, scaled 1 orphan Batch CE to minvCpus=0. Expected new run-rate **~$14–18/day** (savings **~$30/day, ~$900/month**).

---

## 1. The numbers (last 14 days)

| Date | $/day |
|---|---|
| 2026-05-13 | 38.34 |
| 2026-05-14 | 37.19 |
| 2026-05-15 | 45.39 |
| 2026-05-16 | 54.79 |
| 2026-05-17 | 45.17 |
| 2026-05-18 | 48.59 |
| 2026-05-19 | 51.20 |
| 2026-05-20 | 47.56 |
| 2026-05-21 | 47.65 |
| 2026-05-22 | 47.24 |
| 2026-05-23 | 46.98 |
| 2026-05-24 | 46.63 |
| 2026-05-25 | 47.14 |
| 2026-05-26 | 38.63 |

Last 7-day breakdown by service:

| Service | $7d | Notes |
|---|---|---|
| **EC2 Compute** | **$266** | 12 instances running; most idle |
| VPC | $23 | NAT gateway hours |
| EC2 — Other | $19 | EBS volumes, snapshots, data transfer |
| RDS | $7 | test-env Postgres |
| ECR | $6 | image storage |
| ElastiCache | $5 | billing Redis |
| EFS | $4 | |
| S3 | $1.4 | |
| CloudWatch | $1.0 | |
| Secrets Manager | $0.8 | |
| **Total** | **$334** | ~$48/day |

---

## 2. Instance inventory (before cleanup)

12 EC2 instances were running in `us-west-2`. Classified:

### Needed (3) — kept running

| ID | Type | Name tag | Up since | Purpose |
|---|---|---|---|---|
| i-06696b0d91f4346e0 | t3.large | BioMate-Production | 2026-04-08 | dev-public.biomate.ai (active dev box) |
| i-0482a6fa98c6f301a | t3.medium | biomate-deploy-test | 2026-05-18 | test env (new CD target) |
| i-069fbdf5d2c30eb1b | t3.medium | bill | 2026-03-04 | Lago + Java billing (35.86.137.71) |

### Orphans stopped (7) — confirmed <3% avg CPU over 7 days

| ID | Type | Name tag | Up since | ~$/day |
|---|---|---|---|---|
| **i-038b64f058b9b395e** | **c5.4xlarge** | docker-build-optimized | 2026-05-15 | **~$16.32** |
| i-01cb2186bb4589203 | t3.xlarge | claude-docker-builder | 2026-04-21 | ~$4.00 |
| i-0171139e7f1ed45f2 | t3.xlarge | docker-quick-test | 2026-04-24 | ~$4.00 |
| i-0c1810cd013b0a1f4 | t3.large | docker-build-optimized | 2026-04-25 | ~$2.00 |
| i-08f5543b617980a1d | t3.medium | HeadNode | 2026-02-27 | ~$1.00 |
| i-0e260d66893125a56 | t3.medium | protrek-docker-builder-v2 | 2026-03-25 | ~$1.00 |
| i-0a20417c5b630ab46 | t3.small | lt-v6-test | **2025-11-30** (~6 months) | ~$0.50 |

Stopped (not terminated) — EBS volumes preserved for 7-day grace; reversible by `aws ec2 start-instances`.

### Batch CE orphan (drained)

| Resource | Detail | Action |
|---|---|---|
| `galaxy-cloud-compute-al2023-final` | AWS Batch compute env. Not attached to any job queue. Was holding `i-078826b16b76fa2a6` (m6i.xlarge, ~$5/day) warm via `minvCpus=2` for 40 days. | `minvCpus` 2 → 0. ASG will drain the instance. Total burned previously ≈ $200. |

### Untouched

| ID | Type | Name tag | Reason left running |
|---|---|---|---|
| i-0fa1fc210fe9541f6 | t2.small | vpn-server | Launched 2026-05-25 (1 day ago); ~$0.50/day; presumably actively in use |

---

## 3. Why the CW idle alarm didn't catch any of this

Per the CI/CD rebuild plan (L14): *"Alarm created on every EC2 launch via Terraform"*.

Reality:

```
biomate-deploy-dev-idle    → i-06696b0d91f4346e0  (BioMate-Production)
biomate-deploy-test-idle   → i-0482a6fa98c6f301a  (biomate-deploy-test)
```

Only the **two Terraform-managed instances** have idle alarms attached. **All 9 orphans were launched manually** — from the console, one-off scripts, ad-hoc `aws ec2 run-instances` calls — and bypassed the Terraform module that creates the alarm. The mechanism is sound; the enforcement gap is human discipline around manual launches.

This is the same failure class that caused the **$1,400 g6.12xlarge orphan in 12 days** incident (per memory `project_gpu_infrastructure_issue.md`). We patched the symptom (added the alarm in Terraform) but didn't close the underlying gap (manual launches still possible without alarm coverage).

---

## 4. The fix — account-wide enforcement, not per-instance Terraform

Two options to discuss with the team:

### Option A: EventBridge → Lambda auto-attach

- EventBridge rule on `RunInstances` API event (any caller, any tool, any IAM principal).
- Lambda receives the new InstanceId, calls `cloudwatch put-metric-alarm` to attach a default idle alarm (CPU<5% for 1h → SNS `biomate-deploy-events`).
- Cost: pennies/month. Coverage: every EC2 launched in the account, full stop.

### Option B: AWS Config rule

- AWS Config rule that periodically evaluates every EC2 instance and flags any without an idle alarm.
- Slack/SNS notification on non-compliance.
- Cost: ~$2/month for the rule + per-evaluation. Coverage: includes pre-existing instances, not just new launches.

**Recommendation:** **A + B**. EventBridge auto-creates the alarm at launch (90% of value); Config rule audits the long tail (existing instances, edge cases, alarms deleted out-of-band).

### Additional team hygiene

- **Tag every manually-launched instance** with `Owner=<email>` and `Purpose=<short>`. Untagged instance = subject to weekly cleanup.
- **Weekly cost review** — automate `aws ce` query into a Slack post every Monday with top 5 services and top 5 instances by spend.
- **AWS Budgets** alert at $30/day and hard cap at $60/day (existing? unknown — to confirm).
- **All-team policy:** Docker builders, ad-hoc test boxes, headnodes — stop after use, terminate after a week. Don't leave running over a weekend.

---

## 5. Why so many Docker-builder boxes?

Three of the seven orphans are some flavor of "docker-build-*". Investigating further:

- `docker-build-optimized` (c5.4xlarge, May 15) — biggest single line item
- `docker-build-optimized` (t3.large, April 25) — duplicate name, different instance
- `docker-quick-test` (t3.xlarge, April 24)
- `claude-docker-builder` (t3.xlarge, April 21)
- `protrek-docker-builder-v2` (t3.medium, March 25)

Pattern: every Docker-build experiment seems to have spawned a dedicated long-running EC2. The proper pattern would be **CodeBuild** or **ephemeral GHA runners** for image builds — they exist for the lifetime of one build, then disappear. Worth a follow-up.

For the immediate ask: were any of these still actively needed by team members? If yes, we should restart them and tag with Owner. If no, terminate to release the EBS volumes (EBS-Other line was $19/week).

---

## 6. Recommended decisions for team meeting

1. **Confirm:** all 7 stopped instances + the m6i.xlarge can be terminated after 7-day grace. (If anyone wants one back, restart now.)
2. **Approve:** EventBridge + Lambda auto-attach for idle alarms (Option A above). I can implement this — ~2 hours of work.
3. **Approve:** AWS Budgets alarms at $30/day soft + $60/day hard. (To confirm whether any exist already.)
4. **Decide:** Docker-builder pattern. Move image builds to CodeBuild / GHA-only? Or keep dedicated builders with strict shutdown discipline?
5. **Adopt:** required tag policy on all manual EC2 launches: `Owner=<email>`, `Purpose=<short>`. AWS Config rule denies untagged launches (or at minimum, weekly cleanup script terminates them).

---

## 7. Validation after cleanup

To verify in 24 hours:

```bash
START=$(date -u -d '24 hours ago' +%Y-%m-%d)
END=$(date -u +%Y-%m-%d)
aws ce get-cost-and-usage --time-period Start=$START,End=$END \
  --granularity DAILY --metrics UnblendedCost \
  --query 'ResultsByTime[].[TimePeriod.Start,Total.UnblendedCost.Amount]' --output text
```

Expected: $14–18/day instead of $48/day.

Then in 7 days, decide on terminate-vs-restart for each of the 7 stopped instances based on whether anyone reclaimed them.
