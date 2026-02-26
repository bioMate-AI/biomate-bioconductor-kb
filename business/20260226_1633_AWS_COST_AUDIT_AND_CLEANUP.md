# AWS Cost Audit & Cleanup
**Date**: 2026-02-26 16:33
**Performed by**: Claude (AI assistant) + Yaoyun Zhang

---

## Summary

Full audit of AWS account `399683337364` via Cost Explorer and EC2/EFS APIs.
Identified two research instances running 24/7 on-demand — terminated immediately.
Daily run rate reduced from **~$48/day → ~$3/day**.

---

## Findings

### February 2026 Spend (Feb 1–25)

| Service | Cost |
|---|---|
| Amazon EC2 Compute | $659.88 |
| Tax | $48.99 |
| Amazon S3 | $17.65 |
| ECR | $5.34 |
| Amazon ElastiCache | $5.12 |
| Amazon VPC | $8.04 |
| Amazon Route 53 | $3.00 |
| AWS Secrets Manager | $1.37 |
| CloudWatch / Lambda / KMS | $1.09 |
| AWS Batch | $0.00 |
| **Total (Feb 1–25)** | **$786.88** |

**Projected Feb final bill**: ~$840–850 (instances terminated Feb 25)

### Daily Cost Progression

| Period | Daily cost | Cause |
|---|---|---|
| Jan 2026 baseline | ~$8–9/day | lt-v6-test + base services |
| Feb 2–6 | ~$2/day | Brief quiet period |
| Feb 7–11 | ~$24/day | cryosparc-benchmark started |
| Feb 12 | $29/day | biomate-cryoem-spa joined (mid-day) |
| Feb 13–25 | ~$48/day | Both instances running 24/7 |
| Feb 26+ | ~$3/day | Both terminated ✅ |

**Note on budget alerts**: AWS Budgets alert emails show preliminary (unsettled) cost figures
with a 12–24 hour lag. The email showing $27.95 for Feb 22 was preliminary;
the settled amount (confirmed via CE and Budgets history API) was $47.72.
Do not rely on alert email figures for accurate daily totals — use Cost Explorer.

---

## Actions Taken — 2026-02-25

### Terminated (immediate, irreversible)

| Instance | ID | Type | Region | Launched | Feb cost |
|---|---|---|---|---|---|
| `biomate-cryoem-spa` | i-016e0f497a20d6c96 | g6.2xlarge | us-east-1 | 2026-02-12 | $300 |
| `cryosparc-benchmark` | i-09f0545422056b01b | g6.xlarge | us-west-2 | 2026-02-07 | $350 |

Both had `DeleteOnTermination=true` on root EBS volumes — volumes deleted with instances.
EBS data note: any CryoSPARC project data stored only on instance storage is now gone.
Research results already captured in repo (`results/mock_mode_comparison.md` etc.).

**Daily saving: $42.79/day in EC2 compute (~$48/day total account)**
**Monthly saving: ~$1,440/month**

---

## Pending Actions — Backend Team

### Safe to do immediately

| # | Resource | ID | Action |
|---|---|---|---|
| 1 | `BioMate-Production` (t3.small, stopped Oct 2025) | i-06696b0d91f4346e0 | Terminate + delete vol-01e0091136a430c9a (30GB, $2.40/mo) |
| 2 | `docker-build-auto` (t3.medium, stopped Oct 2025) | i-0af396a6d71a467af | Terminate + delete vol-03b9616021a6554e1 (8GB, $0.64/mo) |
| 3 | 6 empty EFS filesystems (orphaned, 6KB each) | fs-059ce03a53ee59974, fs-045b4e8a6c388f50d, fs-08637c72278c93f6a, fs-01d100eb5e7526252, fs-0ec65accd1e447a58, fs-0dd9b5fb35116ba3a | Delete |

### Needs team decision

| # | Resource | ID | Notes |
|---|---|---|---|
| 4 | `HeadNode` — ParallelCluster `galaxy-slurm-minimal` (t3.medium) | i-071f9ea682264c012 | Created 2026-02-26 02:28 UTC — who created this? If not needed: `pcluster delete-cluster -n galaxy-slurm-minimal --region us-west-2` (do NOT terminate directly) |
| 5 | 13 remaining EFS filesystems (18.7 GB, $5.60/mo) | various | Review before deleting — may contain research data |

### Do not touch

| Resource | Reason |
|---|---|
| `lt-v6-test` (i-0a20417c5b630ab46, t3.small) | Galaxy backend — active production |
| ElastiCache Redis (`biomate-billing-redis`) | Billing quota store — active production |

---

## EFS Inventory (us-west-2, 19 filesystems)

| FileSystemId | Size | Cost/mo | Note |
|---|---|---|---|
| fs-05709c2da302cb64f | 7.71 GB | $2.31 | Largest — check before deleting |
| fs-04d6351d804926601 | 3.05 GB | $0.92 | |
| fs-0da3982a4439aa21d | 2.45 GB | $0.74 | |
| fs-07156e19ef1e04d25 | 2.57 GB | $0.77 | |
| fs-0c47557a1aa390c45 | 0.54 GB | $0.16 | |
| fs-0ac992d9b03f55098 | 0.56 GB | $0.17 | |
| fs-070cebada02cf0fc6 | 0.45 GB | $0.14 | |
| fs-0fe5341787a61da74 | 0.47 GB | $0.14 | |
| fs-033ad92c1680093c2 | 0.26 GB | $0.08 | |
| fs-003dab11b7d53c2f5 | 0.26 GB | $0.08 | |
| fs-023576aa2834dbab0 | 0.29 GB | $0.09 | |
| fs-0f3ef3cdd85ef1206 | 0.04 GB | $0.01 | |
| fs-03cb876525b39c9cf | 0.01 GB | $0.00 | |
| fs-059ce03a53ee59974 | 6 KB | $0.00 | **EMPTY — delete** |
| fs-045b4e8a6c388f50d | 6 KB | $0.00 | **EMPTY — delete** |
| fs-08637c72278c93f6a | 6 KB | $0.00 | **EMPTY — delete** |
| fs-01d100eb5e7526252 | 6 KB | $0.00 | **EMPTY — delete** |
| fs-0ec65accd1e447a58 | 6 KB | $0.00 | **EMPTY — delete** |
| fs-0dd9b5fb35116ba3a | 6 KB | $0.00 | **EMPTY — delete** |
| **Total** | **18.66 GB** | **$5.60** | |

---

## Budget Configuration — Recommended Update

Current budget: `Daily_budget` — $10/day, alert at $8 (80%)
Alert emails go to: gmamedaliev@gmail.com only

**Recommended changes:**
- Add yaoyun.zhang@[domain] as alert recipient
- Raise budget to $15/day to cover production baseline (~$9/day) without false alarms
- Add a second alert tier at $30/day for anomaly detection

---

## AWS Marketplace Registration — 2026-02-25 11:42

Seller registration form submitted. Selections:
- Business purpose: Listing software products
- Product types: SaaS + Machine learning / AI
- Pricing models: Contract based + Pay-as-you-go
- Category: Healthcare & Life Sciences
- Industry: Life Sciences, Healthcare

**Status**: Awaiting AWS approval (1–2 weeks). Once Seller ID received, engineering
builds webhook endpoint + registration redirect + entitlement check (~1–2 days work).

Full plan: `business/20260224_1154_RELEASE_PLAN_AWS_PUBLIC_BETA.md` Part 7.
