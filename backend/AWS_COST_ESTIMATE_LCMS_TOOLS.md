# AWS Cost Estimate for LC-MS Tool Installation

**Date**: October 7, 2025
**Analysis**: Based on parallel installation of 20 LC-MS/Metabolomics tools

---

## Executive Summary

**One-Time Installation Cost**: ~$0.50 - $2.00
**Monthly Operational Cost**: ~$120 - $250/month (if running 24/7)
**Recommended Strategy**: Use spot instances + auto-stop = ~$15-30/month

---

## Resource Requirements (Estimated)

Based on typical Galaxy tool installations with parallel workers:

| Resource | Minimum | Recommended | Peak |
|----------|---------|-------------|------|
| **vCPU** | 4 cores | 8 cores | 16 cores |
| **RAM** | 8 GB | 16 GB | 32 GB |
| **Storage** | 20 GB | 50 GB | 100 GB |
| **Network** | 1 Gbps | 5 Gbps | 10 Gbps |

### Installation Metrics (Estimated)

```
Total Tools: 20
Installation Method: Parallel (3 workers)
Expected Time: 30-60 minutes
Expected CPU Usage: 60-80% average, 90-100% peak
Expected Memory: 8-12 GB average, 14-16 GB peak
Expected Disk Space: 3-5 GB for tools + 2 GB temp
Expected Network: 500 MB - 1 GB download
```

---

## AWS Instance Recommendations

### 1. **Budget Option: t3.xlarge** ✅ **RECOMMENDED FOR TESTING**

```yaml
Specs:
  vCPU: 4
  RAM: 16 GB
  Price: $0.1664/hour
  Category: Burstable Performance

One-Time Installation:
  Compute: $0.17 - $0.33  (1-2 hours)
  Storage: $0.01          (EBS GP3, prorated)
  Transfer: $0.05         (1 GB download)
  Total: ~$0.23 - $0.39

Monthly (24/7 operation):
  Compute: $121.47/month  (730 hours)
  Storage: $4.00/month    (50 GB EBS GP3)
  Total: ~$125/month

Cost Optimizations:
  - Spot Instance: Save 70% → $36/month
  - Auto-stop (8hrs/day): $40/month
  - Spot + Auto-stop: $12/month
```

**Best For**: Development, testing, small-scale production

---

### 2. **Performance Option: c6i.2xlarge**

```yaml
Specs:
  vCPU: 8
  RAM: 16 GB
  Price: $0.34/hour
  Category: Compute Optimized

One-Time Installation:
  Compute: $0.34 - $0.68  (1-2 hours)
  Storage: $0.01          (EBS GP3, prorated)
  Transfer: $0.05         (1 GB download)
  Total: ~$0.40 - $0.74

Monthly (24/7 operation):
  Compute: $248.20/month  (730 hours)
  Storage: $4.00/month    (50 GB EBS GP3)
  Total: ~$252/month

Cost Optimizations:
  - Spot Instance: Save 70% → $76/month
  - Auto-stop (8hrs/day): $82/month
  - Spot + Auto-stop: $25/month
```

**Best For**: Production workloads with high concurrency

---

### 3. **High-Memory Option: r6i.xlarge**

```yaml
Specs:
  vCPU: 4
  RAM: 32 GB
  Price: $0.252/hour
  Category: Memory Optimized

One-Time Installation:
  Compute: $0.25 - $0.50  (1-2 hours)
  Storage: $0.01          (EBS GP3, prorated)
  Transfer: $0.05         (1 GB download)
  Total: ~$0.31 - $0.56

Monthly (24/7 operation):
  Compute: $183.96/month  (730 hours)
  Storage: $4.00/month    (50 GB EBS GP3)
  Total: ~$188/month

Cost Optimizations:
  - Spot Instance: Save 70% → $57/month
  - Auto-stop (8hrs/day): $62/month
  - Spot + Auto-stop: $19/month
```

**Best For**: Memory-intensive workflows, large datasets

---

## Detailed Cost Breakdown

### Storage Costs (EBS GP3)

| Use Case | Size | Monthly Cost | Notes |
|----------|------|--------------|-------|
| Tool Installation Only | 20 GB | $1.60/month | Base tools + Galaxy |
| + Workflow Storage | 50 GB | $4.00/month | Recommended |
| + Data Caching | 100 GB | $8.00/month | For active workflows |
| + Large Datasets | 500 GB | $40.00/month | Enterprise scale |

**Alternative**: Use S3 for cold storage at $0.023/GB-month

### Data Transfer Costs

| Type | Volume | Cost | Notes |
|------|--------|------|-------|
| Inbound (from internet) | Unlimited | $0.00 | Always free |
| Outbound (first 10 TB) | Per GB | $0.09/GB | Tool downloads |
| Outbound (next 40 TB) | Per GB | $0.085/GB | Volume discount |
| Inter-region transfer | Per GB | $0.02/GB | Between AWS regions |

**Typical Installation**:
- Tool downloads: ~1 GB = $0.09
- Dependencies: ~500 MB = $0.045
- Total: ~$0.14

---

## Cost Optimization Strategies

### 1. **Spot Instances** 💰 **Save 60-90%**

```
Availability: 95%+
Savings: 70% average
Risk: Low (predictable interruption patterns)

Example (t3.xlarge):
  On-Demand: $121.47/month
  Spot: $36.44/month
  Savings: $85.03/month (70%)
```

**Recommendation**: Use for non-critical workloads and installations

---

### 2. **Auto-Stop / Auto-Start** ⏰ **Save 60-70%**

```
Strategy: Stop instance when not in use
Savings: Proportional to uptime reduction

Example (8 hours/day usage):
  24/7: $121.47/month
  8 hrs/day: $40.49/month
  Savings: $80.98/month (67%)
```

**Implementation**:
```bash
# Auto-stop at 6 PM
aws ec2 stop-instances --instance-ids i-xxxxx

# Auto-start at 9 AM
aws ec2 start-instances --instance-ids i-xxxxx

# Use CloudWatch Events + Lambda for automation
```

---

### 3. **Reserved Instances** 📅 **Save 30-40%**

```
Commitment: 1 or 3 years
Savings: 30-40% vs On-Demand
Best For: Predictable, long-term workloads

Example (t3.xlarge, 1-year, All Upfront):
  On-Demand: $1,457/year
  Reserved: $1,020/year
  Savings: $437/year (30%)
```

**Not Recommended** for development/testing environments

---

### 4. **Savings Plans** 💼 **Save 20-30%**

```
Commitment: 1 or 3 years
Flexibility: Any instance type, any region
Savings: 20-30% vs On-Demand

Example ($10/month commitment):
  Covers: 60 hours of t3.xlarge
  Or: 30 hours of c6i.2xlarge
  Savings: ~25%
```

**Recommended** for mixed workloads

---

### 5. **Caching Pre-Installed Tools** 🚀 **Save 100% on re-installation**

```
Strategy: Create AMI after tool installation
Cost: $0.05/GB-month for AMI storage
Benefit: Instant deployment, no re-installation

Example:
  AMI Size: 50 GB
  Storage Cost: $2.50/month
  Time Saved: 30-60 minutes per deployment
  Compute Saved: $0.17-0.34 per deployment
```

**ROI**: Break-even after 8-15 deployments

---

## Production Deployment Scenarios

### Scenario 1: **Development Environment**

```
Usage: 8 hours/day, 5 days/week
Instance: t3.xlarge (spot)
Storage: 50 GB EBS GP3

Monthly Cost Breakdown:
  Compute: 160 hrs × $0.05/hr (spot) = $8.00
  Storage: 50 GB × $0.08/GB = $4.00
  Transfer: Minimal = $0.50
  ─────────────────────────────────────
  Total: ~$12.50/month
```

---

### Scenario 2: **Testing Environment**

```
Usage: 12 hours/day, 7 days/week
Instance: t3.xlarge (on-demand)
Storage: 100 GB EBS GP3

Monthly Cost Breakdown:
  Compute: 360 hrs × $0.17/hr = $61.20
  Storage: 100 GB × $0.08/GB = $8.00
  Transfer: Moderate = $2.00
  ─────────────────────────────────────
  Total: ~$71/month
```

---

### Scenario 3: **Production Environment**

```
Usage: 24/7 with high availability
Instance: c6i.2xlarge (reserved, 1-year)
Storage: 500 GB EBS GP3 + 1 TB S3
Load Balancer: Application LB
Auto-Scaling: 2-4 instances

Monthly Cost Breakdown:
  Compute (reserved): $176.00
  Storage (EBS): $40.00
  Storage (S3): $23.00
  Load Balancer: $20.00
  Transfer: $10.00
  ─────────────────────────────────────
  Total: ~$269/month (single instance)
  With auto-scaling: ~$400-600/month
```

---

## Cost Comparison Table

| Scenario | Instance | Usage | Monthly Cost | Annual Cost |
|----------|----------|-------|--------------|-------------|
| Dev (Spot + Auto-stop) | t3.xlarge | 8hrs/day | $12 | $144 |
| Test (On-Demand) | t3.xlarge | 12hrs/day | $71 | $852 |
| Prod (Reserved 24/7) | c6i.2xlarge | 24/7 | $176 | $2,112 |
| Prod (Spot + Auto-scale) | c6i.2xlarge | 24/7 | $80-120 | $960-1,440 |

---

## Installation Time Estimates

Based on tool complexity and parallel workers:

| Tool Category | Installation Time | Notes |
|---------------|------------------|-------|
| Simple R Package | 2-5 minutes | Low dependencies |
| R + Dependencies | 5-15 minutes | Conda environment setup |
| Java/Complex | 10-30 minutes | Large dependencies |
| XCMS (full suite) | 20-40 minutes | Multiple interconnected tools |

**Parallel Installation (3 workers)**:
- Total wall time: 30-60 minutes
- Actual compute time: 90-180 minutes (3× parallel)
- Cost (t3.xlarge): $0.17-0.34

**Sequential Installation**:
- Total wall time: 2-3 hours
- Cost (t3.xlarge): $0.34-0.50

---

## Network Requirements

### Bandwidth Needs

| Operation | Bandwidth | Duration |
|-----------|-----------|----------|
| Tool Download | 50-100 MB/tool | 5-30 sec/tool |
| Dependency Install | 100-500 MB/tool | 1-10 min/tool |
| Workflow Execution | 10-100 MB/job | 5-60 min/job |

### Data Transfer Costs

```
Tool Installation (20 tools):
  Downloads: ~1 GB
  Cost: ~$0.09

Monthly Workflow Operations (100 jobs):
  Input data: Free (inbound)
  Output data: ~10 GB
  Cost: ~$0.90/month
```

---

## ROI Analysis

### Break-Even Point for Caching vs Re-Installation

```
AMI Storage Cost: $2.50/month (50 GB)
Installation Cost: $0.25 per installation

Break-even: 10 installations/month
Recommendation: Create AMI after 3rd installation
```

### Spot vs On-Demand ROI

```
Spot Savings: 70%
Interruption Risk: <5% (t3.xlarge)
Expected Value: 65% savings after interruptions

Recommendation: Use spot for all non-critical workloads
```

---

## Recommendations

### For Development/Testing:

✅ **t3.xlarge Spot Instance**
✅ **Auto-stop when not in use**
✅ **EBS GP3 50 GB**
✅ **Create AMI after first installation**

**Expected Cost**: $12-30/month

---

### For Production:

✅ **c6i.2xlarge with Auto-Scaling (2-4 instances)**
✅ **Spot instances for workers**
✅ **Reserved instance for main server**
✅ **EBS GP3 500 GB + S3 for archives**
✅ **Application Load Balancer**

**Expected Cost**: $400-600/month

---

### For Enterprise:

✅ **Multi-region deployment**
✅ **Auto-scaling 5-20 instances**
✅ **Mix of reserved + spot**
✅ **S3 + Glacier for data lifecycle**
✅ **CloudFront for result caching**

**Expected Cost**: $2,000-5,000/month

---

## Monitoring & Alerts

```yaml
CloudWatch Metrics to Track:
  - CPU Utilization
  - Memory Utilization
  - Disk I/O
  - Network Throughput
  - Spot Interruption Warnings

Cost Alerts:
  - Budget: $100/month warning
  - Daily spend: >$5/day alert
  - Anomaly detection enabled
```

---

## Next Steps

1. **Start Small**: Launch t3.xlarge spot instance
2. **Install Tools**: Run parallel installation (~30-60 min)
3. **Create AMI**: Save installed state
4. **Monitor Costs**: Use AWS Cost Explorer
5. **Optimize**: Based on actual usage patterns
6. **Scale Up**: If needed for production

---

## Cost Estimation Tool

```python
def estimate_aws_cost(hours_per_day, days_per_month, instance_type='t3.xlarge'):
    """Quick AWS cost estimator"""

    prices = {
        't3.xlarge': 0.1664,
        'c6i.2xlarge': 0.34,
        'r6i.xlarge': 0.252
    }

    hours_per_month = hours_per_day * days_per_month
    compute_cost = hours_per_month * prices[instance_type]
    storage_cost = 4.00  # 50 GB EBS GP3

    return {
        'compute': compute_cost,
        'storage': storage_cost,
        'total': compute_cost + storage_cost
    }

# Example usage:
# Dev: 8 hrs/day, 20 days/month
# >>> estimate_aws_cost(8, 20, 't3.xlarge')
# {'compute': $26.62, 'storage': $4.00, 'total': $30.62}
```

---

## Summary

**One-Time Installation**: **$0.25 - $0.75**
**Monthly Development**: **$12 - $30** (optimized)
**Monthly Production**: **$400 - $600** (auto-scaled)

**Key Insight**: Use spot instances + auto-stop to achieve **~90% cost savings** compared to 24/7 on-demand instances.

---

**Generated**: October 7, 2025
**Tool**: AWS Cost Analyzer for LC-MS Tool Installation
**Contact**: AWS Cost Optimization Team
