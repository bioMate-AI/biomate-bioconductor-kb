# AWS Quota Increase Requests + Support Case

**Filed:** 2026-06-08 21:38 (us-west-2)
**Account:** 399683337364
**Region:** us-west-2

## 1. Service Quotas requests (filed via API, PENDING)

| Quota | Code | Current | Requested | Rationale |
|---|---|---|---|---|
| Running On-Demand Standard (A,C,D,H,I,M,R,T,Z) instances | L-1216C47A | 626 vCPUs | **2,000 vCPUs** | 3.2× — supports ~30 m5.4xl concurrent for CPU pipelines (RNA-seq, ChIP-seq, ATAC-seq, ADMET screens). Current cap is hit at ~7 concurrent c5.9xl. |
| All Standard Spot Instance Requests | L-34B43A08 | 512 vCPUs | **4,000 vCPUs** | 8× — most production NF tasks run on Spot for cost. Burst patterns (overnight screening campaigns) routinely need 1,500+ vCPUs Spot. |
| Running On-Demand G and VT instances | L-DB2E81BA | 128 vCPUs | **384 vCPUs** | 3× — current cap allows only ~2 concurrent g6.12xlarge (48 vCPUs/instance) or 16 p3.2xlarge. Insufficient for parallel CryoSPARC + AlphaFold + drug-discovery GPU jobs. |
| All G and VT Spot Instance Requests | L-3819A6DF | 128 vCPUs | **768 vCPUs** | 6× — Spot GPU is the primary cost-effective path for cryo-EM and molecular-dynamics workloads; 128 vCPUs caps us at ~3 parallel users. |

Request IDs:
- `f67a893c5b414c1b9ce8dc4565586d4eL0XfGH3u` (CPU OD)
- `1bbb0893309b4899b0cf51128be0a0ef7IXFsvWl` (CPU Spot)
- `9dc89476a8ab4b4baadb38dd2cf95c6eskcI8lQ3` (GPU OD)
- `20c9c467ff2a455a818f4b2bd673601fx353uYan` (GPU Spot)

## 2. Manual AWS Support case — body to paste

(No Premium Support plan on the account, so the API can't open the case. Open at
https://console.aws.amazon.com/support/home → Create case → Service limit increase, OR
file at https://support.console.aws.amazon.com/support/contacts → Account and billing
→ Service limit increase.)

**Subject:** Urgent quota review — BioMate production soft launch capacity constraint

**Case type:** Service limit increase
**Severity:** **High** (production system, customer impact)

**Body:**

> Hello AWS Support team,
>
> We are BioMate (AWS account 399683337364, us-west-2), an AI-driven bioinformatics platform
> that orchestrates Nextflow workflows on AWS Batch. We launched into soft-launch testing this
> week and **hit our compute quotas hard enough to cause user-visible system instability**:
>
> - Our dev environment OOM'd twice in 24 hours when concurrent workflow submissions exceeded
>   capacity, causing host impairment (2026-06-07 17:25 UTC) and Galaxy container crashes
>   (2026-06-08 ~19:00 UTC).
> - On the AWS Batch side, we are routinely queue-bound on `biomate-nextflow-queue` because
>   the backing CE cannot scale past the 626 on-demand / 512 spot vCPU quota for standard
>   instance families, and similarly capped at 128 vCPUs for G/VT (GPU).
> - We have **128 vCPUs of GPU quota** — that is roughly 2 concurrent g6.12xlarge instances
>   for an entire SaaS customer base running cryo-EM, AlphaFold, molecular dynamics, and
>   GPU-accelerated drug-discovery pipelines.
>
> We have filed Service Quotas increase requests for the four EC2 quotas (request IDs above).
> Please expedite the trust & safety review given the production impact. We are happy to share
> 30/90-day usage projections, billing history, and architecture documentation if useful.
>
> We're also requesting an upgrade evaluation for our support plan to Business or Enterprise
> so future incidents can be reported via the Support API directly.
>
> Thanks,
> [Your name]
> BioMate Engineering
> Account: 399683337364
> Primary region: us-west-2

## 3. Other quotas to monitor (NOT auto-requested — review before bumping)

These weren't filed because they require usage data to justify or have non-trivial cost
implications:

| Quota | Default | Notes |
|---|---|---|
| EC2 VPC Elastic IPs per region | 5 | Bump if multi-NAT-GW or many bastion hosts. |
| AWS Batch Maximum jobs in RUNNABLE | 100,000 | Default is large; only bump if we routinely fan out >100k tasks. |
| S3 PUT/COPY/POST/DELETE requests/sec/prefix | 3,500 | Per-prefix, not per-account; mitigation is prefix sharding in NF workDir layout (already using `<runId>/<task-hash>/`). |
| EBS gp3 storage | 50 TiB | Only an issue if many large EBS-backed instances run simultaneously. |
| Lambda concurrent executions | 1,000 | We don't use Lambda in the hot path; not blocking. |

## 4. Verification when AWS lifts the quotas

Once any of the 4 PENDING requests is approved, re-run:

```
aws service-quotas list-requested-service-quota-change-history --service-code ec2 \
    --region us-west-2 \
    --query 'RequestedQuotas[?Status==`APPROVED`]'
```

Then update the CE `desiredvCpus` and `maxvCpus` to take advantage of the new room — without
that, the higher quota does nothing for Batch dispatch. The current CEs are set to
`maxvCpus = 256`, which is below several of the new quotas; raise to e.g. `maxvCpus = 2000`
on `biomate-nextflow-ce-v2` and proportionally on the others.
