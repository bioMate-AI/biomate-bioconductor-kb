# BioMate Comprehensive Infrastructure Budget

**Date**: 2026-01-12
**Purpose**: Full cost analysis for team budget planning
**Scope**: AWS infrastructure + LLM costs + storage + compute

---

## Executive Summary

| Category | Monthly Cost (Est.) | Annual Cost |
|----------|--------------------:|------------:|
| **Compute (AWS Batch + EC2)** | $2,800 - $8,500 | $33,600 - $102,000 |
| **Storage (S3 + EBS + DB)** | $450 - $1,800 | $5,400 - $21,600 |
| **LLM API Costs** | $30 - $500 | $360 - $6,000 |
| **Networking** | $150 - $600 | $1,800 - $7,200 |
| **Supporting Services** | $100 - $300 | $1,200 - $3,600 |
| **TOTAL** | **$3,530 - $11,700** | **$42,360 - $140,400** |

*Ranges represent Small → Large deployment scenarios*

---

## 1. Deployment Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AWS CLOUD                                       │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                         VPC (10.0.0.0/16)                           │    │
│  │                                                                      │    │
│  │  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐          │    │
│  │  │ Public       │    │ Private      │    │ Private      │          │    │
│  │  │ Subnet       │    │ Subnet A     │    │ Subnet B     │          │    │
│  │  │              │    │              │    │              │          │    │
│  │  │ ┌──────────┐ │    │ ┌──────────┐ │    │ ┌──────────┐ │          │    │
│  │  │ │   ALB    │ │    │ │EC2 Fleet │ │    │ │EC2 Fleet │ │          │    │
│  │  │ │          │ │    │ │(Service) │ │    │ │(Service) │ │          │    │
│  │  │ └──────────┘ │    │ └──────────┘ │    │ └──────────┘ │          │    │
│  │  │              │    │              │    │              │          │    │
│  │  │ ┌──────────┐ │    │ ┌──────────┐ │    │ ┌──────────┐ │          │    │
│  │  │ │   NAT    │ │    │ │   RDS    │ │    │ │   RDS    │ │          │    │
│  │  │ │ Gateway  │ │    │ │(Primary) │ │    │ │(Standby) │ │          │    │
│  │  │ └──────────┘ │    │ └──────────┘ │    │ └──────────┘ │          │    │
│  │  └──────────────┘    └──────────────┘    └──────────────┘          │    │
│  │                                                                      │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                        AWS BATCH                                     │    │
│  │                                                                      │    │
│  │  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐          │    │
│  │  │ Compute Env  │    │ Job Queue    │    │ Job Queue    │          │    │
│  │  │ (Spot/OD)    │    │ (High Pri)   │    │ (Low Pri)    │          │    │
│  │  │              │    │              │    │              │          │    │
│  │  │ c6i, r6i,    │    │ Workflow     │    │ Background   │          │    │
│  │  │ m6i instances│    │ Execution    │    │ Processing   │          │    │
│  │  └──────────────┘    └──────────────┘    └──────────────┘          │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐             │
│  │      S3         │  │   ECR          │  │  CloudWatch     │             │
│  │ (Data Storage)  │  │ (Containers)   │  │  (Monitoring)   │             │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘             │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘

                                    │
                                    │ API Calls
                                    ▼
                    ┌───────────────────────────────┐
                    │      External LLM APIs        │
                    │  (Anthropic, Google, Zhipu)   │
                    └───────────────────────────────┘
```

---

## 2. Compute Costs

### 2.1 Service Hosting (EC2)

**Purpose**: Host BioMate web application, API, Galaxy backend

| Instance Type | vCPU | Memory | On-Demand/hr | Reserved/hr | Use Case |
|---------------|------|--------|--------------|-------------|----------|
| t3.medium | 2 | 4 GB | $0.0416 | $0.026 | Dev/Test |
| t3.large | 2 | 8 GB | $0.0832 | $0.052 | Small prod |
| m6i.large | 2 | 8 GB | $0.096 | $0.060 | Production |
| m6i.xlarge | 4 | 16 GB | $0.192 | $0.120 | Production |
| m6i.2xlarge | 8 | 32 GB | $0.384 | $0.240 | High traffic |
| r6i.xlarge | 4 | 32 GB | $0.252 | $0.157 | Memory-intensive |

**Recommended Setup**:

| Tier | Configuration | Monthly Cost |
|------|---------------|-------------:|
| **Small** | 2× m6i.large (Reserved) | $86 |
| **Medium** | 2× m6i.xlarge + 1× r6i.xlarge (Reserved) | $314 |
| **Large** | 4× m6i.2xlarge + 2× r6i.xlarge (Reserved) | $918 |

### 2.2 AWS Batch (Workflow Execution)

**Purpose**: Run bioinformatics workflows (RNA-seq, ChIP-seq, etc.)

#### Instance Types for Batch

| Instance Type | vCPU | Memory | Spot/hr | On-Demand/hr | Workload |
|---------------|------|--------|---------|--------------|----------|
| c6i.large | 2 | 4 GB | $0.026 | $0.085 | Light CPU |
| c6i.xlarge | 4 | 8 GB | $0.051 | $0.170 | Medium CPU |
| c6i.2xlarge | 8 | 16 GB | $0.102 | $0.340 | Heavy CPU |
| c6i.4xlarge | 16 | 32 GB | $0.204 | $0.680 | Alignment |
| r6i.xlarge | 4 | 32 GB | $0.076 | $0.252 | Memory jobs |
| r6i.2xlarge | 8 | 64 GB | $0.151 | $0.504 | Assembly |
| r6i.4xlarge | 16 | 128 GB | $0.302 | $1.008 | Large genome |

#### Workflow Cost Estimates

| Workflow Type | Avg Duration | Instance | Cost/Run (Spot) | Cost/Run (OD) |
|---------------|--------------|----------|-----------------|---------------|
| RNA-seq (small) | 2 hrs | c6i.2xlarge | $0.20 | $0.68 |
| RNA-seq (large) | 6 hrs | c6i.4xlarge | $1.22 | $4.08 |
| ChIP-seq | 3 hrs | c6i.2xlarge | $0.31 | $1.02 |
| WGS Alignment | 8 hrs | r6i.2xlarge | $1.21 | $4.03 |
| scRNA-seq | 4 hrs | r6i.xlarge | $0.30 | $1.01 |
| Assembly | 12 hrs | r6i.4xlarge | $3.62 | $12.10 |
| Simple analysis | 0.5 hrs | c6i.large | $0.01 | $0.04 |

#### Monthly Batch Estimates

| Scenario | Workflows/Month | Mix | Spot Cost | On-Demand Cost |
|----------|-----------------|-----|----------:|--------------:|
| **Small** | 200 | 70% simple, 30% medium | $150 | $500 |
| **Medium** | 1,000 | 50% simple, 40% medium, 10% heavy | $800 | $2,700 |
| **Large** | 5,000 | 40% simple, 40% medium, 20% heavy | $4,200 | $14,000 |

### 2.3 Total Compute Costs

| Scenario | EC2 (Service) | Batch (Workflows) | Total/Month |
|----------|---------------|-------------------|------------:|
| **Small** | $86 | $150 (Spot) | **$236** |
| **Medium** | $314 | $800 (Spot) | **$1,114** |
| **Large** | $918 | $4,200 (Spot) | **$5,118** |

---

## 3. Storage Costs

### 3.1 Amazon S3 (Object Storage)

**Purpose**: Store genomic data, workflow inputs/outputs, results

| Storage Class | Cost/GB/Month | Use Case |
|---------------|---------------|----------|
| S3 Standard | $0.023 | Active data |
| S3 Infrequent Access | $0.0125 | Archived results |
| S3 Glacier Instant | $0.004 | Long-term archive |
| S3 Glacier Deep | $0.00099 | Compliance archive |

#### Data Volume Estimates

| Data Type | Size/Item | Items/Month | Monthly Growth | Storage Class |
|-----------|-----------|-------------|----------------|---------------|
| Raw FASTQ (small) | 5 GB | 100 | 500 GB | Standard |
| Raw FASTQ (large) | 50 GB | 20 | 1,000 GB | Standard |
| BAM files | 10 GB | 200 | 2,000 GB | Standard → IA |
| Results/Reports | 100 MB | 500 | 50 GB | Standard |
| Workflow logs | 10 MB | 1,000 | 10 GB | Standard |

#### S3 Cost Breakdown

| Scenario | Active Storage | IA Storage | Glacier | Requests | Total/Month |
|----------|----------------|------------|---------|----------|------------:|
| **Small** | 500 GB | 1 TB | 2 TB | 100K | **$50** |
| **Medium** | 2 TB | 5 TB | 10 TB | 500K | **$180** |
| **Large** | 10 TB | 20 TB | 50 TB | 2M | **$700** |

*Note: Includes PUT/GET requests and data retrieval*

### 3.2 Amazon EBS (Block Storage)

**Purpose**: EC2 instance storage, database volumes

| Volume Type | Cost/GB/Month | IOPS | Use Case |
|-------------|---------------|------|----------|
| gp3 | $0.08 | 3,000 baseline | General |
| io2 | $0.125 + IOPS | Up to 64,000 | Database |
| st1 | $0.045 | Throughput opt | Logs |

#### EBS Cost Breakdown

| Component | Size | Type | Monthly Cost |
|-----------|------|------|-------------:|
| EC2 root volumes (×4) | 100 GB each | gp3 | $32 |
| Application data | 500 GB | gp3 | $40 |
| Database primary | 500 GB | io2 (10K IOPS) | $128 |
| Database standby | 500 GB | io2 (10K IOPS) | $128 |
| Snapshots | ~200 GB | Snapshot | $10 |
| **Total EBS** | | | **$338** |

### 3.3 Amazon RDS (Database)

**Purpose**: PostgreSQL for Galaxy, user data, workflow metadata

| Instance Type | vCPU | Memory | Multi-AZ/Month | Single/Month |
|---------------|------|--------|---------------:|-------------:|
| db.t3.medium | 2 | 4 GB | $134 | $67 |
| db.t3.large | 2 | 8 GB | $268 | $134 |
| db.r6i.large | 2 | 16 GB | $438 | $219 |
| db.r6i.xlarge | 4 | 32 GB | $876 | $438 |

#### RDS Cost Breakdown

| Scenario | Instance | Storage | Backups | Total/Month |
|----------|----------|---------|---------|------------:|
| **Small** | db.t3.large (Single) | 100 GB | 7 days | **$160** |
| **Medium** | db.r6i.large (Multi-AZ) | 500 GB | 14 days | **$520** |
| **Large** | db.r6i.xlarge (Multi-AZ) | 1 TB | 30 days | **$1,050** |

### 3.4 Total Storage Costs

| Scenario | S3 | EBS | RDS | Total/Month |
|----------|----|----|-----|------------:|
| **Small** | $50 | $200 | $160 | **$410** |
| **Medium** | $180 | $338 | $520 | **$1,038** |
| **Large** | $700 | $500 | $1,050 | **$2,250** |

---

## 4. Networking Costs

### 4.1 Data Transfer

| Transfer Type | Cost/GB | Notes |
|---------------|---------|-------|
| Inbound (Internet → AWS) | $0.00 | Free |
| Outbound (AWS → Internet) | $0.09 | First 10 TB |
| Outbound (10-50 TB) | $0.085 | Volume discount |
| Cross-AZ | $0.01 | Each direction |
| S3 → EC2 (same region) | $0.00 | Free |

#### Data Transfer Estimates

| Scenario | Outbound/Month | Cross-AZ | Total/Month |
|----------|----------------|----------|------------:|
| **Small** | 500 GB | 200 GB | **$47** |
| **Medium** | 2 TB | 1 TB | **$190** |
| **Large** | 10 TB | 5 TB | **$950** |

### 4.2 Load Balancer (ALB)

| Component | Cost | Unit |
|-----------|------|------|
| ALB hour | $0.0225 | per hour |
| LCU hour | $0.008 | per LCU-hour |

| Scenario | ALB Hours | LCU-Hours | Total/Month |
|----------|-----------|-----------|------------:|
| **Small** | 730 | 500 | **$20** |
| **Medium** | 730 | 2,000 | **$32** |
| **Large** | 730 | 10,000 | **$96** |

### 4.3 NAT Gateway

| Component | Cost | Unit |
|-----------|------|------|
| NAT Gateway hour | $0.045 | per hour |
| Data processed | $0.045 | per GB |

| Scenario | Hours | Data Processed | Total/Month |
|----------|-------|----------------|------------:|
| **Small** | 730 | 500 GB | **$55** |
| **Medium** | 730 | 2 TB | **$123** |
| **Large** | 730 | 10 TB | **$483** |

### 4.4 Total Networking Costs

| Scenario | Data Transfer | ALB | NAT | Total/Month |
|----------|---------------|-----|-----|------------:|
| **Small** | $47 | $20 | $55 | **$122** |
| **Medium** | $190 | $32 | $123 | **$345** |
| **Large** | $950 | $96 | $483 | **$1,529** |

---

## 5. LLM API Costs

### 5.1 Current (API-Only)

| Provider | Model | Usage/Month | Cost/Month |
|----------|-------|-------------|------------:|
| Anthropic | Claude Sonnet | 10M tokens | $90 |
| Anthropic | Claude Haiku | 5M tokens | $7.50 |
| Google | Gemini Flash | 5M tokens | $1.50 |
| OpenAI | Embeddings | 10M tokens | $0.20 |
| **Total API-Only** | | | **$99** |

### 5.2 Hybrid (Local + API Fallback)

| Component | Usage | Cost/Month |
|-----------|-------|------------:|
| Local qwen3:32b | 90% of queries | $0 (infra only) |
| Claude fallback | 10% of queries | $9 |
| Embeddings (local) | All | $0 |
| **Total Hybrid** | | **$9** |

### 5.3 LLM Hosting (Self-Hosted Option)

If hosting LLM on AWS instead of local ARM:

| Instance | GPU | Cost/hr (OD) | Cost/hr (Spot) | Monthly (Spot) |
|----------|-----|--------------|----------------|---------------:|
| g5.xlarge | 1× A10G | $1.006 | $0.302 | $220 |
| g5.2xlarge | 1× A10G | $1.212 | $0.364 | $266 |
| g5.4xlarge | 1× A10G | $1.624 | $0.487 | $355 |
| g5.12xlarge | 4× A10G | $5.672 | $1.702 | $1,242 |
| p4d.24xlarge | 8× A100 | $32.77 | $9.83 | $7,176 |

**For qwen3:32b (needs ~24GB VRAM):**
- Minimum: g5.2xlarge (24GB A10G) - $266/month (Spot)
- Recommended: g5.4xlarge for headroom - $355/month (Spot)

### 5.4 LLM Cost Comparison

| Approach | Setup | Monthly Cost | Notes |
|----------|-------|-------------:|-------|
| API Only (Claude) | None | $99-500 | Scales with usage |
| Hybrid (Local ARM) | Existing | $9-50 | Uses your supercomputer |
| Self-hosted (AWS g5) | New | $266-355 | Dedicated GPU instance |

---

## 6. Supporting Services

### 6.1 Monitoring & Logging

| Service | Cost | Unit |
|---------|------|------|
| CloudWatch Logs | $0.50 | per GB ingested |
| CloudWatch Metrics | $0.30 | per metric/month |
| CloudWatch Alarms | $0.10 | per alarm/month |
| CloudWatch Dashboards | $3.00 | per dashboard/month |

| Scenario | Logs | Metrics | Alarms | Total/Month |
|----------|------|---------|--------|------------:|
| **Small** | 10 GB | 50 | 20 | **$22** |
| **Medium** | 50 GB | 100 | 50 | **$60** |
| **Large** | 200 GB | 200 | 100 | **$170** |

### 6.2 Other Services

| Service | Small | Medium | Large |
|---------|------:|-------:|------:|
| ECR (Container Registry) | $5 | $15 | $40 |
| Secrets Manager | $2 | $5 | $10 |
| Route 53 (DNS) | $2 | $5 | $10 |
| ACM (Certificates) | $0 | $0 | $0 |
| IAM | $0 | $0 | $0 |
| **Total Supporting** | **$31** | **$85** | **$230** |

---

## 7. Complete Budget Summary

### 7.1 Monthly Costs by Category

| Category | Small | Medium | Large |
|----------|------:|-------:|------:|
| **Compute (EC2)** | $86 | $314 | $918 |
| **Compute (Batch)** | $150 | $800 | $4,200 |
| **Storage (S3)** | $50 | $180 | $700 |
| **Storage (EBS)** | $200 | $338 | $500 |
| **Storage (RDS)** | $160 | $520 | $1,050 |
| **Networking** | $122 | $345 | $1,529 |
| **LLM APIs** | $9 | $30 | $100 |
| **Monitoring** | $22 | $60 | $170 |
| **Other Services** | $31 | $85 | $230 |
| **TOTAL** | **$830** | **$2,672** | **$9,397** |

### 7.2 Annual Costs

| Category | Small | Medium | Large |
|----------|------:|-------:|------:|
| **Compute** | $2,832 | $13,368 | $61,416 |
| **Storage** | $4,920 | $12,456 | $27,000 |
| **Networking** | $1,464 | $4,140 | $18,348 |
| **LLM** | $108 | $360 | $1,200 |
| **Supporting** | $636 | $1,740 | $4,800 |
| **TOTAL** | **$9,960** | **$32,064** | **$112,764** |

### 7.3 Cost Optimization with Reserved Instances

| Component | On-Demand | 1-yr Reserved | 3-yr Reserved | Savings |
|-----------|----------:|-------------:|-------------:|--------:|
| EC2 (Medium) | $4,608/yr | $3,154/yr | $2,102/yr | 54% |
| RDS (Medium) | $5,256/yr | $3,942/yr | $2,628/yr | 50% |
| **Total Savings** | | $1,768/yr | $4,134/yr | |

---

## 8. Cost Per Unit Metrics

### 8.1 Cost Per Workflow

| Workflow Type | Compute | Storage | LLM | Total |
|---------------|--------:|--------:|----:|------:|
| Simple analysis | $0.05 | $0.01 | $0.001 | **$0.06** |
| RNA-seq (small) | $0.50 | $0.20 | $0.01 | **$0.71** |
| RNA-seq (large) | $2.00 | $1.00 | $0.03 | **$3.03** |
| WGS Alignment | $3.00 | $2.00 | $0.03 | **$5.03** |
| scRNA-seq | $1.00 | $0.50 | $0.02 | **$1.52** |

### 8.2 Cost Per User (Monthly)

| Activity Level | Workflows | Storage | LLM Queries | Total/User |
|----------------|-----------|---------|-------------|------------:|
| Light | 5/month | 10 GB | 50 | **$5** |
| Moderate | 20/month | 50 GB | 200 | **$20** |
| Heavy | 100/month | 200 GB | 1,000 | **$100** |
| Power | 500/month | 1 TB | 5,000 | **$500** |

### 8.3 Cost Per Query (LLM)

| Query Type | API-Only | Hybrid | Savings |
|------------|----------|--------|--------:|
| Simple | $0.005 | $0.000 | 100% |
| Moderate | $0.015 | $0.001 | 93% |
| Complex | $0.050 | $0.010 | 80% |
| Expert | $0.100 | $0.050 | 50% |
| **Weighted Avg** | **$0.019** | **$0.003** | **84%** |

---

## 9. Cost Allocation & Tracking

### 9.1 AWS Cost Tags

```
Required Tags:
- Project: biomate
- Environment: dev | staging | prod
- Component: compute | storage | llm | network
- Owner: <team-email>
- CostCenter: <department-code>

Optional Tags:
- Workflow: <workflow-type>
- User: <user-id>
```

### 9.2 Budget Alerts

| Alert Level | Threshold | Action |
|-------------|-----------|--------|
| Info | 50% of budget | Email notification |
| Warning | 75% of budget | Slack + Email |
| Critical | 90% of budget | Page on-call |
| Emergency | 100% of budget | Auto-scaling limits |

### 9.3 Cost Dashboard Metrics

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        BIOMATE COST DASHBOARD                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  MTD Spend              Budget Remaining        Daily Burn Rate             │
│  ┌─────────────┐       ┌─────────────┐        ┌─────────────┐              │
│  │  $1,847     │       │  $1,153     │        │   $89/day   │              │
│  │  ████████░░ │       │  ░░░░████░░ │        │   ▲ 12%     │              │
│  │    62%      │       │    38%      │        │             │              │
│  └─────────────┘       └─────────────┘        └─────────────┘              │
│                                                                             │
│  Cost by Category                      Cost by Environment                  │
│  ┌────────────────────────────┐       ┌────────────────────────────┐       │
│  │ Compute    ████████  45%   │       │ Production ████████  72%   │       │
│  │ Storage    █████     28%   │       │ Staging    ██        15%   │       │
│  │ Network    ███       15%   │       │ Dev        █         13%   │       │
│  │ LLM        █          5%   │       │                            │       │
│  │ Other      █          7%   │       │                            │       │
│  └────────────────────────────┘       └────────────────────────────┘       │
│                                                                             │
│  Top Cost Drivers (This Week)          Cost Trend (Last 30 Days)           │
│  ┌────────────────────────────┐       ┌────────────────────────────┐       │
│  │ 1. Batch compute   $423    │       │     ╭─────╮                │       │
│  │ 2. RDS database    $178    │       │    ╭╯     ╰╮   ╭──        │       │
│  │ 3. S3 storage      $124    │       │ ──╯        ╰──╯           │       │
│  │ 4. Data transfer   $98     │       │ $60    $75    $89/day     │       │
│  │ 5. EC2 instances   $87     │       └────────────────────────────┘       │
│  └────────────────────────────┘                                            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 10. Scaling Scenarios

### 10.1 Growth Projections

| Metric | Current | 6 Months | 1 Year | 2 Years |
|--------|--------:|--------:|-------:|--------:|
| Users | 50 | 200 | 500 | 2,000 |
| Workflows/Month | 500 | 2,000 | 5,000 | 20,000 |
| Storage (TB) | 2 | 10 | 30 | 100 |
| LLM Queries/Month | 5,000 | 20,000 | 50,000 | 200,000 |

### 10.2 Projected Costs

| Timeframe | Monthly Cost | Annual Cost |
|-----------|-------------:|------------:|
| Current (Small) | $830 | $9,960 |
| 6 Months (Medium) | $2,672 | $32,064 |
| 1 Year (Medium-Large) | $5,500 | $66,000 |
| 2 Years (Large) | $12,000 | $144,000 |

### 10.3 Cost Per User Trend

| Users | Total Cost | Cost/User |
|------:|-----------:|----------:|
| 50 | $830 | $16.60 |
| 200 | $2,672 | $13.36 |
| 500 | $5,500 | $11.00 |
| 2,000 | $12,000 | $6.00 |

*Economies of scale reduce per-user cost by 64% at 2,000 users*

---

## 11. Cost Reduction Strategies

### 11.1 Immediate Actions (0-30 days)

| Action | Savings | Effort |
|--------|--------:|--------|
| Enable Spot for Batch (already in plan) | 70% on Batch | Low |
| S3 Lifecycle policies | 40% on old data | Low |
| Right-size EC2 instances | 20-30% | Medium |
| Reserved Instances (1-year) | 30-40% | Low |

### 11.2 Short-term (1-3 months)

| Action | Savings | Effort |
|--------|--------:|--------|
| Hybrid LLM (local qwen3:32b) | 85% on LLM | Done |
| Enable S3 Intelligent-Tiering | 20% on storage | Low |
| Implement caching layer | 10-20% overall | Medium |
| Batch job optimization | 15-25% on compute | Medium |

### 11.3 Long-term (3-12 months)

| Action | Savings | Effort |
|--------|--------:|--------|
| Reserved Instances (3-year) | 50-60% on EC2/RDS | Low |
| Savings Plans | 30-40% flexible | Low |
| Multi-region optimization | 10-20% on transfer | High |
| Kubernetes migration (EKS) | Variable | High |

---

## 12. Budget Approval Request

### 12.1 Recommended Budget (Medium Tier)

| Category | Monthly | Annual | Notes |
|----------|--------:|-------:|-------|
| Compute | $1,114 | $13,368 | EC2 + Batch |
| Storage | $1,038 | $12,456 | S3 + EBS + RDS |
| Networking | $345 | $4,140 | Transfer + ALB + NAT |
| LLM | $30 | $360 | Hybrid approach |
| Supporting | $145 | $1,740 | Monitoring + services |
| **Subtotal** | **$2,672** | **$32,064** | |
| Contingency (15%) | $401 | $4,810 | Unexpected growth |
| **TOTAL REQUEST** | **$3,073** | **$36,874** | |

### 12.2 Break-even Analysis

| Investment | Cost | Payback |
|------------|-----:|---------|
| Hybrid LLM setup | 40 dev hours | <1 month (LLM savings) |
| Reserved Instances | Upfront commitment | 8 months |
| Spot integration | 10 dev hours | <1 month |

### 12.3 Approval Milestones

| Phase | Budget | Approval Needed |
|-------|-------:|-----------------|
| Phase 1: MVP (Small) | $830/mo | Team Lead |
| Phase 2: Production (Medium) | $2,672/mo | Director |
| Phase 3: Scale (Large) | $9,397/mo | VP |

---

## Appendix A: AWS Pricing References

- EC2 Pricing: https://aws.amazon.com/ec2/pricing/
- S3 Pricing: https://aws.amazon.com/s3/pricing/
- RDS Pricing: https://aws.amazon.com/rds/pricing/
- Batch Pricing: https://aws.amazon.com/batch/pricing/
- Data Transfer: https://aws.amazon.com/ec2/pricing/on-demand/#Data_Transfer

## Appendix B: Assumptions

1. US-East-1 region pricing
2. Spot instance availability at 30% of On-Demand
3. 730 hours/month for always-on services
4. 70% Spot / 30% On-Demand mix for Batch
5. Data retention: 30 days hot, 90 days warm, 1 year cold
6. Multi-AZ for production database
7. Reserved Instance pricing assumes 1-year term

## Appendix C: Glossary

| Term | Definition |
|------|------------|
| On-Demand | Pay-as-you-go pricing |
| Spot | Spare capacity at discount (can be interrupted) |
| Reserved | Committed usage for 1-3 years |
| LCU | Load Balancer Capacity Unit |
| IOPS | I/O Operations Per Second |
| Multi-AZ | Replicated across Availability Zones |
