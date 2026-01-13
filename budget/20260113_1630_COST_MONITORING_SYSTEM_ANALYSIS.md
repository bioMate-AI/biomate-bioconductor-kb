# BioMate Cost Monitoring & Billing System Analysis

**Date**: 2026-01-13
**Purpose**: Evaluate existing systems for comprehensive cost tracking and billing
**Requirement**: Per-workflow cost tracking for usage-based and outcome-based pricing

---

## Executive Summary

BioMate needs a **two-layer system**:
1. **Cost Tracking Layer**: Track actual AWS costs per workflow/user
2. **Billing Layer**: Meter usage and bill customers

**Recommendation**: AWS Native + Lago (open source) for Day 1, upgrade to Orb/Stripe Metronome as scale grows.

---

## 1. Complete Cost Component Inventory

BioMate has **6 major cost categories** that need tracking:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    BIOMATE COMPLETE COST STRUCTURE                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. COMPUTE                           4. LLM / AI                          │
│     ├── EC2 (web servers)                ├── Claude API (Anthropic)        │
│     ├── AWS Batch (workflows)            ├── Gemini API (Google)           │
│     ├── Lambda (serverless)              ├── Ollama (local inference)      │
│     └── Fargate (containers)             └── Embeddings (if used)          │
│                                                                             │
│  2. STORAGE                           5. WEBSITE / APPLICATION             │
│     ├── S3 (data files)                  ├── ALB (load balancer)           │
│     ├── EBS (EC2 volumes)                ├── CloudFront (CDN)              │
│     ├── RDS (PostgreSQL)                 ├── Route 53 (DNS)                │
│     └── ElastiCache (Redis)              └── ACM (SSL certs)               │
│                                                                             │
│  3. NETWORKING                        6. SUPPORTING SERVICES               │
│     ├── Data Transfer (egress)           ├── CloudWatch (logs/metrics)     │
│     ├── NAT Gateway                      ├── ECR (container registry)      │
│     ├── VPC Endpoints                    ├── Secrets Manager               │
│     └── Inter-AZ traffic                 └── SES (email)                   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.1 Detailed Cost Component Matrix

| Category | Component | Source | Granularity | Tracking Method | Delay |
|----------|-----------|--------|-------------|-----------------|-------|
| **Compute** | EC2 (servers) | AWS | Per-instance | Tags + CUR | 24hr |
| | AWS Batch | AWS | Per-job | Tags + CUR | 24hr |
| | Lambda | AWS | Per-invocation | CloudWatch | Minutes |
| **Storage** | S3 | AWS | Per-bucket/prefix | S3 Analytics | 24hr |
| | EBS | AWS | Per-volume | Tags + CUR | 24hr |
| | RDS | AWS | Per-instance | CUR | 24hr |
| **Networking** | Data Transfer | AWS | Per-service | CUR | 24hr |
| | NAT Gateway | AWS | Per-GB | CUR | 24hr |
| **LLM** | Claude API | Anthropic | Per-request | API response | Real-time |
| | Gemini API | Google | Per-request | API response | Real-time |
| | Ollama | Local | Per-request | Self-track | Real-time |
| **Website** | ALB | AWS | Per-LCU-hour | CUR | 24hr |
| | CloudFront | AWS | Per-request/GB | CUR | 24hr |
| **Support** | CloudWatch | AWS | Per-metric/log | CUR | 24hr |
| | ECR | AWS | Per-GB stored | CUR | 24hr |

### 1.2 The Core Challenge

**AWS billing data has a 24-hour delay**. For real-time billing, we need to:
1. **Estimate costs** during execution
2. **Reconcile** with actual AWS bills nightly
3. **Track LLM costs** in real-time (APIs return usage)
4. **Allocate shared costs** (servers, databases) to users

---

## 2. AWS Native Cost Tracking Tools

### 2.1 AWS Cost Explorer API

| Feature | Capability | Limitation |
|---------|------------|------------|
| Granularity | Hourly/Daily/Monthly | 24-hour delay |
| Filtering | By tag, service, region | Requires tag activation |
| Pricing | $0.01 per API request | Can add up |
| Integration | REST API, SDK | Rate limited |

```python
# Example: Query costs by workflow tag
import boto3

client = boto3.client('ce')
response = client.get_cost_and_usage(
    TimePeriod={'Start': '2026-01-01', 'End': '2026-01-13'},
    Granularity='DAILY',
    Filter={
        'Tags': {
            'Key': 'workflow_id',
            'Values': ['wf-12345']
        }
    },
    Metrics=['UnblendedCost']
)
```

### 2.2 AWS Cost Allocation Tags

**Required tags for BioMate**:

| Tag Key | Purpose | Example Value |
|---------|---------|---------------|
| `biomate:user_id` | Bill to user | `user-abc123` |
| `biomate:project_id` | Group by project | `proj-xyz789` |
| `biomate:workflow_id` | Per-workflow cost | `wf-12345` |
| `biomate:workflow_type` | Cost by type | `rna-seq` |
| `biomate:tier` | Pricing tier | `pro` |

**Implementation**:
```python
# Tag AWS Batch jobs on submission
job_definition = {
    'jobName': 'rna-seq-analysis',
    'tags': {
        'biomate:user_id': 'user-abc123',
        'biomate:workflow_id': 'wf-12345',
        'biomate:workflow_type': 'rna-seq'
    }
}
```

### 2.3 AWS Split Cost Allocation Data

**Best for**: ECS tasks and AWS Batch jobs

AWS Split Cost Allocation Data provides container-level cost visibility:
- Allocates shared EC2 costs to individual tasks
- Available in Cost and Usage Reports (CUR)
- Enables chargeback by task/job

**Setup**:
1. Enable Split Cost Allocation in Billing Console
2. Configure CUR export to S3
3. Query via Athena for per-job costs

### 2.4 Serverless Batch Cost Guardian

AWS provides an [open-source solution](https://github.com/aws-samples/serverless-batch-cost-guardian) for real-time Batch cost monitoring:

- Monitors spend via Cost Allocation Tags
- Triggers alerts when budget threshold approached
- Can auto-terminate jobs when budget exceeded
- Uses Step Functions for orchestration

---

## 3. Third-Party FinOps Platforms

### 3.1 Comparison Matrix

| Platform | Best For | AWS Batch Support | Pricing | Setup Time |
|----------|----------|-------------------|---------|------------|
| **Vantage** | Startups, fast setup | Via tags | $30-200/mo | Hours |
| **CloudHealth** | Enterprise | Yes | 3% of spend | Weeks |
| **CloudZero** | Engineering teams | Yes | Custom | Days |
| **Kubecost** | Kubernetes | EKS only | Free/Enterprise | Hours |
| **nOps** | AWS-focused | Yes | Custom | Days |
| **OpenCost** | K8s, open source | EKS only | Free | Hours |

### 3.2 Vantage (Recommended for Startups)

**Pros**:
- Quick setup (connect AWS in minutes)
- Clean UI, easy to understand
- Supports AWS, GCP, Azure, Kubernetes
- Integrates with Datadog, Snowflake, etc.
- Cost anomaly alerts

**Cons**:
- Limited automation
- No direct Batch job tracking (uses tags)

**Pricing**:
| Tier | Tracked Costs | Price |
|------|--------------|-------|
| Starter | Up to $2,500/mo | Free |
| Pro | Up to $7,500/mo | $30/mo |
| Business | Up to $20,000/mo | $200/mo |
| Enterprise | Unlimited | Custom |

### 3.3 OpenCost (Open Source)

**Pros**:
- Free, CNCF project
- Real-time cost allocation
- Kubernetes-native
- AWS/GCP/Azure billing API integration

**Cons**:
- Kubernetes-focused (needs EKS for Batch)
- Self-hosted, requires maintenance

**Best for**: If BioMate moves to EKS for workflow execution

---

## 4. Usage-Based Billing Platforms

### 4.1 The Billing Challenge

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    COST TRACKING vs BILLING                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  COST TRACKING (Internal)          BILLING (Customer-facing)               │
│  ─────────────────────────         ─────────────────────────               │
│  • What did it cost us?            • What do we charge?                    │
│  • AWS bills (delayed)             • Real-time metering                    │
│  • Per-resource granular           • Per-user/workflow                     │
│  • Reconciliation                  • Invoicing                             │
│                                                                             │
│  These are DIFFERENT systems with different requirements!                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Billing Platform Comparison

| Platform | Model | AI/Usage Focus | Open Source | Pricing |
|----------|-------|----------------|-------------|---------|
| **Metronome** (Stripe) | Metering + Billing | Yes (OpenAI, Anthropic) | No | % of revenue |
| **Orb** | Full-stack billing | Yes | No | Custom |
| **Lago** | Metering + Billing | Yes | Yes (self-host free) | Free/$$/$$$ |
| **Stripe Billing** | Subscription + Usage | Basic | No | 0.5% + fees |
| **Chargebee** | Subscription | Limited usage | No | $$/$$$ |

### 4.3 Lago (Recommended for Day 1)

**Why Lago**:
- **Open source** - self-host for free
- **Event-based metering** - "if you can track it, you can charge for it"
- **Hybrid pricing** - subscriptions + usage + one-time
- **Real-time** - instant usage tracking
- **No revenue share** - unlike Metronome/Orb

**Architecture**:
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         LAGO INTEGRATION                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  BioMate Workflow                                                           │
│       │                                                                     │
│       ▼                                                                     │
│  ┌─────────────┐    Events    ┌─────────────┐    Invoice    ┌───────────┐ │
│  │  Workflow   │─────────────▶│    Lago     │──────────────▶│  Stripe   │ │
│  │  Executor   │              │  (Metering) │               │ (Payment) │ │
│  └─────────────┘              └─────────────┘               └───────────┘ │
│                                     │                                       │
│                                     ▼                                       │
│                              ┌─────────────┐                               │
│                              │  PostgreSQL │                               │
│                              │  (Usage DB) │                               │
│                              └─────────────┘                               │
│                                                                             │
│  Event Example:                                                             │
│  {                                                                          │
│    "transaction_id": "wf-12345",                                           │
│    "external_customer_id": "user-abc123",                                  │
│    "code": "workflow_completed",                                           │
│    "properties": {                                                          │
│      "workflow_type": "rna-seq",                                           │
│      "compute_seconds": 7200,                                              │
│      "outcome": "success"                                                  │
│    }                                                                        │
│  }                                                                          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Lago Pricing**:
| Tier | Price | Features |
|------|-------|----------|
| Open Source | Free | Self-host, full features |
| Cloud Starter | $250/mo | Managed, up to 10K events |
| Cloud Scale | Custom | High volume, support |

### 4.4 Orb / Metronome (Scale Option)

**When to upgrade**:
- Processing >100K events/month
- Need enterprise features (SSO, audit logs)
- Want managed service
- Revenue justifies cost

**Metronome** (now Stripe):
- Used by OpenAI, Anthropic, Databricks
- Charges per 1,000 events + % of billing
- Now part of Stripe ecosystem

**Orb**:
- Metronome competitor
- More comprehensive (includes invoicing)
- Better for complex pricing models

---

## 5. Recommended Architecture for BioMate

### 5.1 Phase 1: Day 1 (MVP)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    BIOMATE COST SYSTEM - PHASE 1                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                        ┌──────────────────┐                                │
│                        │   BioMate App    │                                │
│                        └────────┬─────────┘                                │
│                                 │                                          │
│         ┌───────────────────────┼───────────────────────┐                  │
│         ▼                       ▼                       ▼                  │
│  ┌─────────────┐        ┌─────────────┐        ┌─────────────┐            │
│  │   AWS Batch │        │   Ollama    │        │  Claude/    │            │
│  │   (tagged)  │        │   (local)   │        │  Gemini API │            │
│  └──────┬──────┘        └──────┬──────┘        └──────┬──────┘            │
│         │                      │                      │                    │
│         ▼                      ▼                      ▼                    │
│  ┌─────────────────────────────────────────────────────────────┐          │
│  │                    Usage Tracker Service                     │          │
│  │                    (Custom Python/Node)                      │          │
│  │                                                              │          │
│  │  • Log workflow start/end times                             │          │
│  │  • Estimate costs in real-time                              │          │
│  │  • Track LLM token usage                                    │          │
│  │  • Store in PostgreSQL                                      │          │
│  └─────────────────────────────────────────────────────────────┘          │
│         │                                                                  │
│         ▼                                                                  │
│  ┌─────────────┐        ┌─────────────┐        ┌─────────────┐            │
│  │  PostgreSQL │        │    Lago     │        │   Stripe    │            │
│  │  (usage DB) │───────▶│  (billing)  │───────▶│  (payment)  │            │
│  └─────────────┘        └─────────────┘        └─────────────┘            │
│                                                                            │
│  Nightly Reconciliation:                                                   │
│  ┌─────────────┐        ┌─────────────┐                                   │
│  │  AWS Cost   │───────▶│ Reconcile   │──▶ Adjust estimates               │
│  │  Explorer   │        │  Service    │                                   │
│  └─────────────┘        └─────────────┘                                   │
│                                                                            │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 5.2 Phase 2: Growth (Month 6+)

Add:
- Vantage for cost visualization & anomaly detection
- More sophisticated cost allocation
- Customer-facing usage dashboard

### 5.3 Phase 3: Scale (Year 2+)

Consider:
- Orb or Stripe Metronome for enterprise billing
- OpenCost if moving to EKS
- Custom BI dashboards

---

## 6. Implementation Details

### 6.1 LLM Cost Tracking (Real-Time)

LLM costs can be tracked **in real-time** because APIs return token usage.

#### 6.1.1 Claude API (Anthropic)

```python
# llm_cost_tracker.py - Claude Integration

import anthropic
from dataclasses import dataclass
from datetime import datetime

@dataclass
class LLMUsageRecord:
    timestamp: datetime
    user_id: str
    request_id: str
    model: str
    input_tokens: int
    output_tokens: int
    cost: float
    latency_ms: int

class ClaudeCostTracker:
    # Pricing as of Jan 2026 (per million tokens)
    PRICING = {
        'claude-opus-4': {'input': 15.0, 'output': 75.0},
        'claude-sonnet-4': {'input': 3.0, 'output': 15.0},
        'claude-haiku-3.5': {'input': 0.80, 'output': 4.0},
    }

    def __init__(self, db_connection):
        self.client = anthropic.Anthropic()
        self.db = db_connection

    def chat_with_tracking(self, user_id: str, messages: list,
                           model: str = 'claude-sonnet-4') -> tuple:
        """Make Claude API call and track costs"""
        start_time = datetime.now()

        response = self.client.messages.create(
            model=model,
            max_tokens=4096,
            messages=messages
        )

        latency_ms = (datetime.now() - start_time).total_seconds() * 1000

        # Extract usage from response
        input_tokens = response.usage.input_tokens
        output_tokens = response.usage.output_tokens

        # Calculate cost
        pricing = self.PRICING.get(model, self.PRICING['claude-sonnet-4'])
        cost = (input_tokens * pricing['input'] / 1_000_000 +
                output_tokens * pricing['output'] / 1_000_000)

        # Record usage
        record = LLMUsageRecord(
            timestamp=datetime.now(),
            user_id=user_id,
            request_id=response.id,
            model=model,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            cost=cost,
            latency_ms=int(latency_ms)
        )
        self._save_record(record)

        return response.content[0].text, record

    def _save_record(self, record: LLMUsageRecord):
        self.db.execute("""
            INSERT INTO llm_usage
            (timestamp, user_id, request_id, model, input_tokens,
             output_tokens, cost, latency_ms, provider)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, 'anthropic')
        """, (record.timestamp, record.user_id, record.request_id,
              record.model, record.input_tokens, record.output_tokens,
              record.cost, record.latency_ms))
```

#### 6.1.2 Gemini API (Google)

```python
# Gemini cost tracking
import google.generativeai as genai

class GeminiCostTracker:
    PRICING = {
        'gemini-2.0-flash': {'input': 0.075, 'output': 0.30},
        'gemini-1.5-pro': {'input': 1.25, 'output': 5.0},
        'gemini-1.5-flash': {'input': 0.075, 'output': 0.30},
    }

    def chat_with_tracking(self, user_id: str, prompt: str,
                           model: str = 'gemini-2.0-flash') -> tuple:
        genai.configure(api_key=os.environ['GOOGLE_API_KEY'])
        model_instance = genai.GenerativeModel(model)

        response = model_instance.generate_content(prompt)

        # Gemini returns usage metadata
        input_tokens = response.usage_metadata.prompt_token_count
        output_tokens = response.usage_metadata.candidates_token_count

        pricing = self.PRICING.get(model, self.PRICING['gemini-2.0-flash'])
        cost = (input_tokens * pricing['input'] / 1_000_000 +
                output_tokens * pricing['output'] / 1_000_000)

        # Save to database (similar to Claude)
        self._save_record(user_id, model, input_tokens, output_tokens, cost, 'google')

        return response.text, cost
```

#### 6.1.3 Ollama (Local) - Zero Marginal Cost

```python
# Ollama tracking - for usage analytics only (cost = 0)
import httpx
import tiktoken  # For token counting

class OllamaCostTracker:
    def __init__(self, base_url: str = "http://localhost:11434"):
        self.base_url = base_url
        self.encoder = tiktoken.get_encoding("cl100k_base")

    def chat_with_tracking(self, user_id: str, prompt: str,
                           model: str = 'qwen3:32b') -> tuple:
        # Count input tokens
        input_tokens = len(self.encoder.encode(prompt))

        response = httpx.post(
            f"{self.base_url}/api/generate",
            json={"model": model, "prompt": prompt, "stream": False},
            timeout=300
        )
        result = response.json()

        # Count output tokens
        output_tokens = len(self.encoder.encode(result['response']))

        # Record for analytics (cost = 0 for local)
        self._save_record(
            user_id=user_id,
            model=model,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            cost=0.0,  # Local = free
            provider='ollama'
        )

        return result['response'], 0.0
```

#### 6.1.4 Unified LLM Router with Cost Tracking

```python
# Hybrid LLM router with integrated cost tracking
class LLMRouterWithCosts:
    def __init__(self, db):
        self.claude = ClaudeCostTracker(db)
        self.gemini = GeminiCostTracker(db)
        self.ollama = OllamaCostTracker()
        self.db = db

    async def route_and_track(self, user_id: str, prompt: str,
                               task_complexity: str = 'moderate') -> tuple:
        """Route to appropriate LLM based on complexity, track all costs"""

        if task_complexity in ['trivial', 'simple']:
            # Use local Ollama (free)
            response, cost = self.ollama.chat_with_tracking(
                user_id, prompt, 'qwen3:32b'
            )
            provider = 'ollama'

        elif task_complexity == 'moderate':
            # Use Gemini Flash (cheap)
            response, cost = self.gemini.chat_with_tracking(
                user_id, prompt, 'gemini-2.0-flash'
            )
            provider = 'google'

        else:  # complex, expert
            # Use Claude Sonnet (best quality)
            response, cost = self.claude.chat_with_tracking(
                user_id, [{"role": "user", "content": prompt}], 'claude-sonnet-4'
            )
            provider = 'anthropic'

        return response, {'cost': cost, 'provider': provider}
```

### 6.2 Storage Cost Tracking

#### 6.2.1 S3 Storage (Per-User/Project)

```python
# s3_cost_tracker.py
import boto3
from datetime import datetime, timedelta

class S3CostTracker:
    # S3 pricing (us-east-1)
    PRICING = {
        'STANDARD': 0.023,           # per GB/month
        'INTELLIGENT_TIERING': 0.023,
        'STANDARD_IA': 0.0125,
        'GLACIER': 0.004,
    }

    def __init__(self):
        self.s3 = boto3.client('s3')
        self.cw = boto3.client('cloudwatch')

    def get_user_storage_usage(self, bucket: str, user_prefix: str) -> dict:
        """Get storage usage for a specific user's prefix"""
        paginator = self.s3.get_paginator('list_objects_v2')

        total_size = 0
        object_count = 0

        for page in paginator.paginate(Bucket=bucket, Prefix=f"users/{user_prefix}/"):
            for obj in page.get('Contents', []):
                total_size += obj['Size']
                object_count += 1

        size_gb = total_size / (1024 ** 3)
        monthly_cost = size_gb * self.PRICING['STANDARD']

        return {
            'user_prefix': user_prefix,
            'total_bytes': total_size,
            'total_gb': round(size_gb, 4),
            'object_count': object_count,
            'estimated_monthly_cost': round(monthly_cost, 4),
            'storage_class': 'STANDARD'
        }

    def get_bucket_metrics(self, bucket: str) -> dict:
        """Get CloudWatch metrics for bucket-level storage"""
        response = self.cw.get_metric_statistics(
            Namespace='AWS/S3',
            MetricName='BucketSizeBytes',
            Dimensions=[
                {'Name': 'BucketName', 'Value': bucket},
                {'Name': 'StorageType', 'Value': 'StandardStorage'}
            ],
            StartTime=datetime.now() - timedelta(days=1),
            EndTime=datetime.now(),
            Period=86400,
            Statistics=['Average']
        )
        return response

    def allocate_shared_storage_cost(self, bucket: str, users: list) -> dict:
        """Allocate shared bucket costs proportionally to users"""
        user_usage = {}
        total_usage = 0

        for user_id in users:
            usage = self.get_user_storage_usage(bucket, user_id)
            user_usage[user_id] = usage['total_bytes']
            total_usage += usage['total_bytes']

        # Get actual bucket cost from Cost Explorer (delayed)
        actual_cost = self._get_bucket_cost_from_cur(bucket)

        # Allocate proportionally
        allocations = {}
        for user_id, usage in user_usage.items():
            proportion = usage / total_usage if total_usage > 0 else 0
            allocations[user_id] = {
                'bytes': usage,
                'proportion': proportion,
                'allocated_cost': actual_cost * proportion
            }

        return allocations
```

#### 6.2.2 RDS Database Cost Tracking

```python
# rds_cost_tracker.py
class RDSCostTracker:
    # RDS PostgreSQL pricing (us-east-1, on-demand)
    INSTANCE_PRICING = {
        'db.t3.micro': 0.017,    # per hour
        'db.t3.small': 0.034,
        'db.t3.medium': 0.068,
        'db.m6i.large': 0.171,
        'db.m6i.xlarge': 0.342,
        'db.r6i.large': 0.240,
    }
    STORAGE_PRICING = 0.115  # per GB/month for gp3

    def __init__(self):
        self.rds = boto3.client('rds')

    def get_rds_costs(self, db_identifier: str) -> dict:
        """Get RDS instance costs"""
        response = self.rds.describe_db_instances(
            DBInstanceIdentifier=db_identifier
        )
        instance = response['DBInstances'][0]

        instance_class = instance['DBInstanceClass']
        storage_gb = instance['AllocatedStorage']

        hourly_rate = self.INSTANCE_PRICING.get(instance_class, 0.10)
        monthly_instance = hourly_rate * 24 * 30
        monthly_storage = storage_gb * self.STORAGE_PRICING

        return {
            'instance_class': instance_class,
            'storage_gb': storage_gb,
            'monthly_instance_cost': round(monthly_instance, 2),
            'monthly_storage_cost': round(monthly_storage, 2),
            'total_monthly': round(monthly_instance + monthly_storage, 2)
        }

    def allocate_db_cost_to_users(self, total_users: int,
                                   monthly_cost: float) -> float:
        """Allocate shared DB cost per user"""
        return monthly_cost / total_users if total_users > 0 else 0
```

### 6.3 Website & Application Cost Tracking

#### 6.3.1 EC2 Application Servers

```python
# ec2_cost_tracker.py
class EC2CostTracker:
    INSTANCE_PRICING = {
        't3.medium': 0.0416,
        't3.large': 0.0832,
        'm6i.large': 0.096,
        'm6i.xlarge': 0.192,
        'm6i.2xlarge': 0.384,
        'r6i.xlarge': 0.252,
    }

    def __init__(self):
        self.ec2 = boto3.client('ec2')

    def get_tagged_instance_costs(self, tag_key: str, tag_value: str) -> dict:
        """Get costs for instances with specific tag"""
        response = self.ec2.describe_instances(
            Filters=[
                {'Name': f'tag:{tag_key}', 'Values': [tag_value]},
                {'Name': 'instance-state-name', 'Values': ['running']}
            ]
        )

        total_hourly = 0
        instances = []

        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                instance_type = instance['InstanceType']
                hourly_rate = self.INSTANCE_PRICING.get(instance_type, 0.10)
                total_hourly += hourly_rate
                instances.append({
                    'instance_id': instance['InstanceId'],
                    'type': instance_type,
                    'hourly_rate': hourly_rate
                })

        return {
            'instances': instances,
            'total_hourly': total_hourly,
            'total_daily': total_hourly * 24,
            'total_monthly': total_hourly * 24 * 30
        }
```

#### 6.3.2 ALB (Load Balancer) Cost Tracking

```python
# alb_cost_tracker.py
class ALBCostTracker:
    # ALB pricing
    HOURLY_RATE = 0.0225  # per hour
    LCU_RATE = 0.008      # per LCU-hour

    def __init__(self):
        self.elbv2 = boto3.client('elbv2')
        self.cw = boto3.client('cloudwatch')

    def get_alb_costs(self, alb_arn: str) -> dict:
        """Estimate ALB costs based on usage"""
        # Get LCU usage from CloudWatch
        response = self.cw.get_metric_statistics(
            Namespace='AWS/ApplicationELB',
            MetricName='ConsumedLCUs',
            Dimensions=[{'Name': 'LoadBalancer', 'Value': alb_arn.split('/')[-1]}],
            StartTime=datetime.now() - timedelta(days=1),
            EndTime=datetime.now(),
            Period=3600,
            Statistics=['Average']
        )

        avg_lcus = sum(dp['Average'] for dp in response['Datapoints']) / len(response['Datapoints']) if response['Datapoints'] else 1

        hourly_fixed = self.HOURLY_RATE
        hourly_lcu = avg_lcus * self.LCU_RATE
        total_hourly = hourly_fixed + hourly_lcu

        return {
            'avg_lcus': round(avg_lcus, 2),
            'hourly_fixed': hourly_fixed,
            'hourly_lcu': round(hourly_lcu, 4),
            'total_hourly': round(total_hourly, 4),
            'total_monthly': round(total_hourly * 24 * 30, 2)
        }
```

#### 6.3.3 CloudFront CDN Cost Tracking

```python
# cloudfront_cost_tracker.py
class CloudFrontCostTracker:
    # CloudFront pricing (simplified, varies by region)
    REQUEST_PRICING = 0.0075 / 10000  # per request (HTTPS)
    DATA_PRICING = 0.085  # per GB (first 10TB)

    def __init__(self):
        self.cf = boto3.client('cloudfront')
        self.cw = boto3.client('cloudwatch')

    def get_distribution_costs(self, distribution_id: str) -> dict:
        """Get CloudFront costs for a distribution"""
        # Get request count
        requests = self.cw.get_metric_statistics(
            Namespace='AWS/CloudFront',
            MetricName='Requests',
            Dimensions=[
                {'Name': 'DistributionId', 'Value': distribution_id},
                {'Name': 'Region', 'Value': 'Global'}
            ],
            StartTime=datetime.now() - timedelta(days=30),
            EndTime=datetime.now(),
            Period=2592000,  # 30 days
            Statistics=['Sum']
        )

        # Get data transfer
        data_transfer = self.cw.get_metric_statistics(
            Namespace='AWS/CloudFront',
            MetricName='BytesDownloaded',
            Dimensions=[
                {'Name': 'DistributionId', 'Value': distribution_id},
                {'Name': 'Region', 'Value': 'Global'}
            ],
            StartTime=datetime.now() - timedelta(days=30),
            EndTime=datetime.now(),
            Period=2592000,
            Statistics=['Sum']
        )

        total_requests = requests['Datapoints'][0]['Sum'] if requests['Datapoints'] else 0
        total_bytes = data_transfer['Datapoints'][0]['Sum'] if data_transfer['Datapoints'] else 0
        total_gb = total_bytes / (1024 ** 3)

        request_cost = total_requests * self.REQUEST_PRICING
        data_cost = total_gb * self.DATA_PRICING

        return {
            'total_requests': int(total_requests),
            'total_gb': round(total_gb, 2),
            'request_cost': round(request_cost, 2),
            'data_cost': round(data_cost, 2),
            'total_monthly': round(request_cost + data_cost, 2)
        }
```

### 6.4 Networking Cost Tracking

```python
# networking_cost_tracker.py
class NetworkingCostTracker:
    # Data transfer pricing
    DATA_OUT_PRICING = {
        'first_10tb': 0.09,
        'next_40tb': 0.085,
        'next_100tb': 0.07,
        'over_150tb': 0.05
    }
    NAT_GATEWAY_HOURLY = 0.045
    NAT_GATEWAY_PER_GB = 0.045

    def get_data_transfer_costs(self, start_date: str, end_date: str) -> dict:
        """Get data transfer costs from Cost Explorer"""
        ce = boto3.client('ce')

        response = ce.get_cost_and_usage(
            TimePeriod={'Start': start_date, 'End': end_date},
            Granularity='MONTHLY',
            Filter={
                'Dimensions': {
                    'Key': 'USAGE_TYPE_GROUP',
                    'Values': ['EC2: Data Transfer - Internet (Out)']
                }
            },
            Metrics=['UsageQuantity', 'UnblendedCost']
        )

        return response

    def estimate_nat_gateway_cost(self, data_processed_gb: float,
                                   hours_running: int = 720) -> dict:
        """Estimate NAT Gateway costs"""
        hourly_cost = hours_running * self.NAT_GATEWAY_HOURLY
        data_cost = data_processed_gb * self.NAT_GATEWAY_PER_GB

        return {
            'hourly_cost': round(hourly_cost, 2),
            'data_cost': round(data_cost, 2),
            'total': round(hourly_cost + data_cost, 2)
        }
```

### 6.5 Unified Cost Aggregator

Combine all cost components into a single service:

```python
# unified_cost_aggregator.py
from dataclasses import dataclass
from datetime import datetime, date
from typing import Dict, Optional
import asyncio

@dataclass
class UserCostSummary:
    user_id: str
    period_start: date
    period_end: date

    # Workflow costs (variable, per-use)
    workflow_compute_cost: float
    workflow_count: int

    # LLM costs (variable, per-use)
    llm_cost_anthropic: float
    llm_cost_google: float
    llm_cost_ollama: float  # Always 0, but track usage
    llm_total_tokens: int
    llm_request_count: int

    # Storage costs (monthly, allocated)
    s3_storage_cost: float
    s3_storage_gb: float

    # Shared infrastructure (allocated per-user)
    allocated_server_cost: float
    allocated_db_cost: float
    allocated_network_cost: float

    # Totals
    total_variable_cost: float
    total_fixed_allocated: float
    total_cost: float


class UnifiedCostAggregator:
    """
    Central service that aggregates all cost components for billing.
    """

    def __init__(self, db):
        self.db = db
        self.batch_tracker = BatchCostTracker()
        self.llm_tracker = LLMRouterWithCosts(db)
        self.s3_tracker = S3CostTracker()
        self.ec2_tracker = EC2CostTracker()
        self.rds_tracker = RDSCostTracker()
        self.alb_tracker = ALBCostTracker()
        self.network_tracker = NetworkingCostTracker()

    async def get_user_costs(self, user_id: str,
                              start_date: date, end_date: date) -> UserCostSummary:
        """Get complete cost breakdown for a user"""

        # 1. Workflow compute costs (from usage_events table)
        workflow_costs = await self._get_workflow_costs(user_id, start_date, end_date)

        # 2. LLM costs (from llm_usage table)
        llm_costs = await self._get_llm_costs(user_id, start_date, end_date)

        # 3. Storage costs (calculated from S3)
        storage_costs = self.s3_tracker.get_user_storage_usage(
            bucket='biomate-data',
            user_prefix=user_id
        )

        # 4. Shared infrastructure allocation
        total_users = await self._get_active_user_count(start_date, end_date)
        shared_costs = await self._get_shared_infrastructure_costs()
        per_user_shared = {
            'server': shared_costs['server'] / total_users,
            'db': shared_costs['db'] / total_users,
            'network': shared_costs['network'] / total_users,
        }

        # Calculate totals
        total_variable = (
            workflow_costs['total'] +
            llm_costs['total'] +
            storage_costs['estimated_monthly_cost']
        )
        total_fixed = sum(per_user_shared.values())

        return UserCostSummary(
            user_id=user_id,
            period_start=start_date,
            period_end=end_date,

            workflow_compute_cost=workflow_costs['total'],
            workflow_count=workflow_costs['count'],

            llm_cost_anthropic=llm_costs['anthropic'],
            llm_cost_google=llm_costs['google'],
            llm_cost_ollama=0.0,
            llm_total_tokens=llm_costs['total_tokens'],
            llm_request_count=llm_costs['request_count'],

            s3_storage_cost=storage_costs['estimated_monthly_cost'],
            s3_storage_gb=storage_costs['total_gb'],

            allocated_server_cost=per_user_shared['server'],
            allocated_db_cost=per_user_shared['db'],
            allocated_network_cost=per_user_shared['network'],

            total_variable_cost=total_variable,
            total_fixed_allocated=total_fixed,
            total_cost=total_variable + total_fixed
        )

    async def _get_workflow_costs(self, user_id: str,
                                   start: date, end: date) -> dict:
        """Query workflow costs from database"""
        result = self.db.execute("""
            SELECT
                COUNT(*) as count,
                SUM(COALESCE(actual_cost, estimated_cost)) as total
            FROM usage_events
            WHERE user_id = %s
              AND timestamp BETWEEN %s AND %s
              AND event_type = 'workflow_completed'
        """, (user_id, start, end))
        row = result.fetchone()
        return {'count': row[0] or 0, 'total': float(row[1] or 0)}

    async def _get_llm_costs(self, user_id: str,
                              start: date, end: date) -> dict:
        """Query LLM costs from database"""
        result = self.db.execute("""
            SELECT
                provider,
                COUNT(*) as request_count,
                SUM(input_tokens + output_tokens) as total_tokens,
                SUM(cost) as total_cost
            FROM llm_usage
            WHERE user_id = %s
              AND timestamp BETWEEN %s AND %s
            GROUP BY provider
        """, (user_id, start, end))

        costs = {'anthropic': 0, 'google': 0, 'ollama': 0,
                 'total_tokens': 0, 'request_count': 0, 'total': 0}

        for row in result.fetchall():
            provider, count, tokens, cost = row
            costs[provider] = float(cost or 0)
            costs['total_tokens'] += int(tokens or 0)
            costs['request_count'] += int(count or 0)
            costs['total'] += float(cost or 0)

        return costs

    async def _get_shared_infrastructure_costs(self) -> dict:
        """Get monthly costs of shared infrastructure"""
        # EC2 servers
        server_costs = self.ec2_tracker.get_tagged_instance_costs(
            'Application', 'biomate'
        )

        # RDS
        db_costs = self.rds_tracker.get_rds_costs('biomate-production')

        # ALB
        alb_costs = self.alb_tracker.get_alb_costs(
            'arn:aws:elasticloadbalancing:us-east-1:xxx:loadbalancer/app/biomate-alb/xxx'
        )

        # Network (NAT Gateway estimate)
        network_costs = self.network_tracker.estimate_nat_gateway_cost(
            data_processed_gb=100  # Estimate
        )

        return {
            'server': server_costs['total_monthly'],
            'db': db_costs['total_monthly'],
            'alb': alb_costs['total_monthly'],
            'network': network_costs['total'],
        }

    async def generate_billing_report(self, user_id: str, month: date) -> dict:
        """Generate a complete billing report for invoicing"""
        start = month.replace(day=1)
        if month.month == 12:
            end = month.replace(year=month.year + 1, month=1, day=1)
        else:
            end = month.replace(month=month.month + 1, day=1)

        costs = await self.get_user_costs(user_id, start, end)

        # Get user's pricing tier
        tier = await self._get_user_tier(user_id)

        # Calculate charges based on pricing model
        if tier['pricing_model'] == 'usage_based':
            charges = self._calculate_usage_charges(costs, tier)
        elif tier['pricing_model'] == 'outcome_based':
            charges = self._calculate_outcome_charges(costs, tier)
        else:  # hybrid
            charges = self._calculate_hybrid_charges(costs, tier)

        return {
            'user_id': user_id,
            'period': f"{start} to {end}",
            'tier': tier['name'],
            'cost_breakdown': {
                'workflows': costs.workflow_compute_cost,
                'llm': costs.llm_cost_anthropic + costs.llm_cost_google,
                'storage': costs.s3_storage_cost,
                'infrastructure': costs.total_fixed_allocated,
            },
            'our_cost': costs.total_cost,
            'charges': charges,
            'margin': charges['total'] - costs.total_cost,
            'margin_percent': ((charges['total'] - costs.total_cost) /
                               charges['total'] * 100) if charges['total'] > 0 else 0
        }
```

### 6.6 Complete Cost Estimation Model

Since AWS billing is delayed 24 hours, estimate costs in real-time:

```python
# cost_estimator.py

COST_ESTIMATES = {
    # Instance type: cost per second (Spot prices)
    'c6i.large': 0.026 / 3600,    # $0.026/hr
    'c6i.xlarge': 0.051 / 3600,
    'c6i.2xlarge': 0.102 / 3600,
    'c6i.4xlarge': 0.204 / 3600,
    'r6i.xlarge': 0.076 / 3600,
    'r6i.2xlarge': 0.151 / 3600,
    'r6i.4xlarge': 0.302 / 3600,
}

LLM_COSTS = {
    'claude-sonnet': {'input': 3.0 / 1_000_000, 'output': 15.0 / 1_000_000},
    'claude-haiku': {'input': 0.25 / 1_000_000, 'output': 1.25 / 1_000_000},
    'gemini-flash': {'input': 0.075 / 1_000_000, 'output': 0.30 / 1_000_000},
    'qwen3-32b': {'input': 0, 'output': 0},  # Local = free
}

STORAGE_COSTS = {
    's3_standard': 0.023 / (1024 * 1024 * 1024) / 30 / 24 / 3600,  # per byte per second
    'ebs_gp3': 0.08 / (1024 * 1024 * 1024) / 30 / 24 / 3600,
}


class CostEstimator:
    def estimate_workflow_cost(self, workflow_type: str, instance_type: str,
                                duration_seconds: int, storage_gb: float) -> dict:
        compute_cost = COST_ESTIMATES.get(instance_type, 0.1/3600) * duration_seconds
        storage_cost = storage_gb * 0.023 / 30  # Monthly rate prorated

        return {
            'compute': round(compute_cost, 4),
            'storage': round(storage_cost, 4),
            'total': round(compute_cost + storage_cost, 4),
            'estimated': True,  # Flag for reconciliation
        }

    def estimate_llm_cost(self, model: str, input_tokens: int, output_tokens: int) -> float:
        costs = LLM_COSTS.get(model, {'input': 0.003, 'output': 0.015})
        return input_tokens * costs['input'] + output_tokens * costs['output']
```

### 6.2 Usage Event Schema

```python
# Track every billable event
@dataclass
class UsageEvent:
    event_id: str
    user_id: str
    project_id: str
    timestamp: datetime
    event_type: str  # 'workflow_started', 'workflow_completed', 'llm_query', etc.

    # Workflow-specific
    workflow_id: Optional[str]
    workflow_type: Optional[str]
    instance_type: Optional[str]
    duration_seconds: Optional[int]

    # LLM-specific
    llm_model: Optional[str]
    input_tokens: Optional[int]
    output_tokens: Optional[int]

    # Cost tracking
    estimated_cost: float
    actual_cost: Optional[float]  # Filled after reconciliation

    # Billing
    billed: bool = False
    invoice_id: Optional[str] = None
```

### 6.8 Complete Database Schema

```sql
-- ============================================================
-- BIOMATE COMPREHENSIVE COST TRACKING DATABASE SCHEMA
-- ============================================================

-- 1. LLM Usage Table (Real-time tracking)
-- ============================================================
CREATE TABLE llm_usage (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    user_id VARCHAR(255) NOT NULL,
    request_id VARCHAR(255) UNIQUE,

    -- Provider & Model
    provider VARCHAR(50) NOT NULL,  -- 'anthropic', 'google', 'ollama'
    model VARCHAR(100) NOT NULL,

    -- Token Usage
    input_tokens INTEGER NOT NULL DEFAULT 0,
    output_tokens INTEGER NOT NULL DEFAULT 0,

    -- Cost (0 for Ollama local)
    cost DECIMAL(10, 6) NOT NULL DEFAULT 0,

    -- Performance
    latency_ms INTEGER,

    -- Context
    workflow_id VARCHAR(255),       -- If part of a workflow
    task_type VARCHAR(100),         -- 'chat', 'workflow_gen', 'tool_selection'

    CONSTRAINT idx_llm_user_time UNIQUE (user_id, timestamp, request_id)
);
CREATE INDEX idx_llm_provider ON llm_usage (provider, timestamp);
CREATE INDEX idx_llm_workflow ON llm_usage (workflow_id);

-- 2. Workflow Compute Events
-- ============================================================
CREATE TABLE workflow_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    user_id VARCHAR(255) NOT NULL,
    project_id VARCHAR(255),

    -- Workflow identification
    workflow_id VARCHAR(255) NOT NULL,
    workflow_type VARCHAR(100) NOT NULL,  -- 'rna-seq', 'chip-seq', etc.

    -- Execution details
    event_type VARCHAR(50) NOT NULL,  -- 'started', 'completed', 'failed'
    instance_type VARCHAR(50),        -- 'c6i.2xlarge', etc.
    duration_seconds INTEGER,

    -- AWS Batch details
    batch_job_id VARCHAR(255),
    compute_environment VARCHAR(255),

    -- Cost tracking
    estimated_cost DECIMAL(10, 6),
    actual_cost DECIMAL(10, 6),
    reconciled BOOLEAN DEFAULT FALSE,
    reconciled_at TIMESTAMPTZ,

    -- Billing
    billed BOOLEAN DEFAULT FALSE,
    invoice_id VARCHAR(255),

    -- Outcome (for outcome-based pricing)
    outcome VARCHAR(50),  -- 'success', 'failed', 'partial'
    outcome_tier VARCHAR(50)  -- 'quick', 'standard', 'advanced', 'complex'
);
CREATE INDEX idx_wf_user_time ON workflow_events (user_id, timestamp);
CREATE INDEX idx_wf_workflow ON workflow_events (workflow_id);
CREATE INDEX idx_wf_billing ON workflow_events (billed, timestamp);

-- 3. Storage Usage (Daily snapshots)
-- ============================================================
CREATE TABLE storage_usage (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    date DATE NOT NULL,
    user_id VARCHAR(255) NOT NULL,

    -- S3 storage
    s3_bytes BIGINT DEFAULT 0,
    s3_object_count INTEGER DEFAULT 0,
    s3_storage_class VARCHAR(50) DEFAULT 'STANDARD',

    -- Calculated costs
    s3_cost DECIMAL(10, 6) DEFAULT 0,

    -- Data transfer (that day)
    data_transfer_in_bytes BIGINT DEFAULT 0,
    data_transfer_out_bytes BIGINT DEFAULT 0,
    data_transfer_cost DECIMAL(10, 6) DEFAULT 0,

    UNIQUE(date, user_id)
);

-- 4. Infrastructure Costs (Monthly allocation)
-- ============================================================
CREATE TABLE infrastructure_costs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    month DATE NOT NULL,  -- First day of month

    -- EC2 Servers
    ec2_server_cost DECIMAL(10, 4) DEFAULT 0,

    -- RDS Database
    rds_instance_cost DECIMAL(10, 4) DEFAULT 0,
    rds_storage_cost DECIMAL(10, 4) DEFAULT 0,

    -- Load Balancer
    alb_cost DECIMAL(10, 4) DEFAULT 0,

    -- Networking
    nat_gateway_cost DECIMAL(10, 4) DEFAULT 0,
    data_transfer_cost DECIMAL(10, 4) DEFAULT 0,

    -- CDN
    cloudfront_cost DECIMAL(10, 4) DEFAULT 0,

    -- Supporting services
    cloudwatch_cost DECIMAL(10, 4) DEFAULT 0,
    ecr_cost DECIMAL(10, 4) DEFAULT 0,
    secrets_manager_cost DECIMAL(10, 4) DEFAULT 0,
    ses_cost DECIMAL(10, 4) DEFAULT 0,

    -- Totals
    total_fixed_cost DECIMAL(10, 4) DEFAULT 0,
    active_user_count INTEGER DEFAULT 1,
    cost_per_user DECIMAL(10, 4) DEFAULT 0,

    UNIQUE(month)
);

-- 5. Daily Cost Summary (Aggregated view)
-- ============================================================
CREATE TABLE daily_cost_summary (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    date DATE NOT NULL,
    user_id VARCHAR(255) NOT NULL,

    -- Counts
    workflow_count INTEGER DEFAULT 0,
    llm_request_count INTEGER DEFAULT 0,
    llm_tokens_used INTEGER DEFAULT 0,

    -- Variable costs
    workflow_compute_cost DECIMAL(10, 4) DEFAULT 0,
    llm_anthropic_cost DECIMAL(10, 4) DEFAULT 0,
    llm_google_cost DECIMAL(10, 4) DEFAULT 0,
    llm_ollama_cost DECIMAL(10, 4) DEFAULT 0,  -- Always 0
    storage_cost DECIMAL(10, 4) DEFAULT 0,
    data_transfer_cost DECIMAL(10, 4) DEFAULT 0,

    -- Allocated fixed costs
    infrastructure_allocation DECIMAL(10, 4) DEFAULT 0,

    -- Totals
    total_variable DECIMAL(10, 4) DEFAULT 0,
    total_fixed DECIMAL(10, 4) DEFAULT 0,
    total_cost DECIMAL(10, 4) DEFAULT 0,

    UNIQUE(date, user_id)
);

-- 6. Cost Reconciliation Log
-- ============================================================
CREATE TABLE cost_reconciliation (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reconciliation_date DATE NOT NULL,

    -- AWS actual costs (from Cost Explorer)
    aws_ec2_cost DECIMAL(10, 4),
    aws_batch_cost DECIMAL(10, 4),
    aws_s3_cost DECIMAL(10, 4),
    aws_rds_cost DECIMAL(10, 4),
    aws_network_cost DECIMAL(10, 4),
    aws_other_cost DECIMAL(10, 4),
    aws_total_cost DECIMAL(10, 4),

    -- Our estimates
    estimated_total DECIMAL(10, 4),

    -- Variance analysis
    variance DECIMAL(10, 4),
    variance_percent DECIMAL(5, 2),

    -- Status
    status VARCHAR(50) DEFAULT 'pending',  -- 'pending', 'completed', 'alert'
    notes TEXT,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. User Billing Summary (Monthly invoicing)
-- ============================================================
CREATE TABLE billing_summary (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id VARCHAR(255) NOT NULL,
    billing_period_start DATE NOT NULL,
    billing_period_end DATE NOT NULL,

    -- Subscription
    tier VARCHAR(50) NOT NULL,  -- 'free', 'pro', 'team', 'enterprise'
    subscription_fee DECIMAL(10, 4) DEFAULT 0,

    -- Usage charges
    workflow_charges DECIMAL(10, 4) DEFAULT 0,
    llm_overage_charges DECIMAL(10, 4) DEFAULT 0,
    storage_charges DECIMAL(10, 4) DEFAULT 0,
    compute_overage DECIMAL(10, 4) DEFAULT 0,

    -- Our costs
    total_cost_to_us DECIMAL(10, 4) DEFAULT 0,

    -- Customer charges
    total_charges DECIMAL(10, 4) DEFAULT 0,

    -- Margin
    gross_margin DECIMAL(10, 4) DEFAULT 0,
    margin_percent DECIMAL(5, 2) DEFAULT 0,

    -- Invoice
    invoice_id VARCHAR(255),
    invoice_status VARCHAR(50) DEFAULT 'draft',  -- 'draft', 'sent', 'paid'
    stripe_invoice_id VARCHAR(255),

    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, billing_period_start)
);

-- 8. Views for dashboards
-- ============================================================

-- User cost overview
CREATE VIEW v_user_cost_overview AS
SELECT
    dcs.user_id,
    DATE_TRUNC('month', dcs.date) as month,
    SUM(dcs.workflow_count) as total_workflows,
    SUM(dcs.llm_request_count) as total_llm_requests,
    SUM(dcs.llm_tokens_used) as total_tokens,
    SUM(dcs.total_variable) as variable_costs,
    SUM(dcs.total_fixed) as fixed_costs,
    SUM(dcs.total_cost) as total_cost
FROM daily_cost_summary dcs
GROUP BY dcs.user_id, DATE_TRUNC('month', dcs.date);

-- LLM provider breakdown
CREATE VIEW v_llm_provider_breakdown AS
SELECT
    DATE_TRUNC('day', timestamp) as day,
    provider,
    COUNT(*) as request_count,
    SUM(input_tokens + output_tokens) as total_tokens,
    SUM(cost) as total_cost,
    AVG(latency_ms) as avg_latency_ms
FROM llm_usage
GROUP BY DATE_TRUNC('day', timestamp), provider;

-- Workflow type costs
CREATE VIEW v_workflow_type_costs AS
SELECT
    DATE_TRUNC('month', timestamp) as month,
    workflow_type,
    COUNT(*) as count,
    AVG(duration_seconds) as avg_duration,
    SUM(COALESCE(actual_cost, estimated_cost)) as total_cost,
    AVG(COALESCE(actual_cost, estimated_cost)) as avg_cost
FROM workflow_events
WHERE event_type = 'completed'
GROUP BY DATE_TRUNC('month', timestamp), workflow_type;
```

### 6.4 Lago Integration

```python
# lago_client.py
import lago_python

class BillingService:
    def __init__(self):
        self.lago = lago_python.Client(api_key=os.environ['LAGO_API_KEY'])

    def send_workflow_event(self, user_id: str, workflow_id: str,
                            workflow_type: str, outcome: str,
                            compute_seconds: int):
        """Send workflow completion event to Lago for billing"""
        self.lago.events.create(
            transaction_id=workflow_id,
            external_customer_id=user_id,
            code='workflow_completed',
            timestamp=datetime.now().isoformat(),
            properties={
                'workflow_type': workflow_type,
                'outcome': outcome,  # 'success' or 'failed'
                'compute_seconds': compute_seconds,
            }
        )

    def send_llm_event(self, user_id: str, query_id: str,
                       model: str, tokens: int):
        """Send LLM query event to Lago"""
        self.lago.events.create(
            transaction_id=query_id,
            external_customer_id=user_id,
            code='llm_query',
            properties={
                'model': model,
                'tokens': tokens,
            }
        )
```

### 6.5 Nightly Reconciliation Job

```python
# reconciliation.py
import boto3
from datetime import datetime, timedelta

class CostReconciliation:
    def __init__(self):
        self.ce_client = boto3.client('ce')
        self.db = get_database_connection()

    def reconcile_yesterday(self):
        """Run nightly to reconcile estimated vs actual costs"""
        yesterday = (datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d')

        # Get actual costs from AWS Cost Explorer
        aws_costs = self.get_aws_costs_by_workflow(yesterday)

        # Get our estimates from database
        estimated_costs = self.get_estimated_costs(yesterday)

        # Update database with actual costs
        for workflow_id, actual_cost in aws_costs.items():
            self.db.execute("""
                UPDATE usage_events
                SET actual_cost = %s, reconciled = TRUE, reconciled_at = NOW()
                WHERE workflow_id = %s AND DATE(timestamp) = %s
            """, (actual_cost, workflow_id, yesterday))

        # Log variance for monitoring
        total_estimated = sum(estimated_costs.values())
        total_actual = sum(aws_costs.values())
        variance = total_actual - total_estimated
        variance_pct = (variance / total_estimated * 100) if total_estimated > 0 else 0

        self.db.execute("""
            INSERT INTO cost_reconciliation
            (reconciliation_date, aws_cost_explorer_total, estimated_total,
             variance, variance_percent)
            VALUES (%s, %s, %s, %s, %s)
        """, (yesterday, total_actual, total_estimated, variance, variance_pct))

        # Alert if variance > 10%
        if abs(variance_pct) > 10:
            self.send_alert(f"Cost variance alert: {variance_pct:.1f}% on {yesterday}")

    def get_aws_costs_by_workflow(self, date: str) -> dict:
        """Query AWS Cost Explorer for costs by workflow_id tag"""
        response = self.ce_client.get_cost_and_usage(
            TimePeriod={'Start': date, 'End': date},
            Granularity='DAILY',
            GroupBy=[{'Type': 'TAG', 'Key': 'biomate:workflow_id'}],
            Metrics=['UnblendedCost']
        )

        costs = {}
        for group in response['ResultsByTime'][0]['Groups']:
            workflow_id = group['Keys'][0].replace('biomate:workflow_id$', '')
            cost = float(group['Metrics']['UnblendedCost']['Amount'])
            costs[workflow_id] = cost

        return costs
```

---

## 7. Cost Comparison: Build vs Buy

### 7.1 Build Custom System

| Component | Effort | Ongoing Cost |
|-----------|--------|--------------|
| Usage tracking service | 2-4 weeks | $50/mo (hosting) |
| Database schema | 1 week | Included in RDS |
| Cost estimation | 1 week | - |
| Reconciliation job | 1 week | - |
| Lago integration | 1 week | Free (self-host) |
| Dashboard | 2-4 weeks | - |
| **Total** | **8-12 weeks** | **$50/mo** |

### 7.2 Buy Third-Party

| Solution | Setup | Monthly Cost |
|----------|-------|--------------|
| Vantage + Stripe Billing | Days | $30-200 + 0.5% |
| Orb (full stack) | Weeks | $500-2000+ |
| Metronome (Stripe) | Weeks | % of billing |

### 7.3 Recommendation

| Stage | Recommendation | Rationale |
|-------|----------------|-----------|
| **Day 1** | Custom + Lago | Full control, free |
| **Growth** | Add Vantage | Better visualization |
| **Scale** | Evaluate Orb | Enterprise features |

---

## 8. Summary: BioMate Comprehensive Cost System

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                BIOMATE COMPLETE COST MONITORING ARCHITECTURE                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                      DATA COLLECTION LAYER                           │  │
│  │                                                                       │  │
│  │  COMPUTE           LLM                 STORAGE         WEBSITE       │  │
│  │  ─────────         ───                 ───────         ───────       │  │
│  │  • AWS Batch       • Claude API        • S3 buckets    • EC2         │  │
│  │    (tagged)          (real-time)         (per-user)      servers     │  │
│  │  • Lambda          • Gemini API        • EBS volumes   • ALB         │  │
│  │  • Fargate           (real-time)       • RDS           • CloudFront  │  │
│  │                    • Ollama            • ElastiCache   • Route 53    │  │
│  │                      (local, free)                                    │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                     │                                       │
│         Real-time events            │          Nightly batch                │
│         ─────────────────           │          ─────────────                │
│                ▼                    │                 ▼                     │
│  ┌──────────────────────┐          │     ┌──────────────────────┐         │
│  │   PostgreSQL         │          │     │  AWS Cost Explorer   │         │
│  │   ───────────────    │          │     │  ──────────────────  │         │
│  │   • llm_usage        │          │     │  • Actual costs      │         │
│  │   • workflow_events  │◀─────────┼────▶│  • By service/tag    │         │
│  │   • storage_usage    │ Reconcile│     │  • 24hr delay        │         │
│  │   • daily_summary    │          │     └──────────────────────┘         │
│  └──────────────────────┘                                                  │
│              │                                                              │
│              ▼                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                    UNIFIED COST AGGREGATOR                           │  │
│  │                                                                       │  │
│  │  Per-User Cost Summary:                                              │  │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐   │  │
│  │  │  Workflow   │ │    LLM      │ │  Storage    │ │Infrastructure│   │  │
│  │  │  Compute    │ │   Costs     │ │   Costs     │ │ Allocated    │   │  │
│  │  │  $X.XX      │ │   $X.XX     │ │   $X.XX     │ │   $X.XX      │   │  │
│  │  └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘   │  │
│  │                          │                                          │  │
│  │                          ▼                                          │  │
│  │              ┌─────────────────────┐                               │  │
│  │              │  TOTAL USER COST    │                               │  │
│  │              │  Variable + Fixed   │                               │  │
│  │              └─────────────────────┘                               │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│              │                                                              │
│              ▼                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                        BILLING LAYER                                 │  │
│  │                                                                       │  │
│  │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐              │  │
│  │  │    Lago     │───▶│   Stripe    │───▶│  Customer   │              │  │
│  │  │  (Metering) │    │ (Payments)  │    │  Invoice    │              │  │
│  │  └─────────────┘    └─────────────┘    └─────────────┘              │  │
│  │                                                                       │  │
│  │  Pricing Models Supported:                                           │  │
│  │  • Usage-based (compute at cost + 20%)                              │  │
│  │  • Outcome-based ($25/successful analysis)                          │  │
│  │  • Hybrid (subscription + usage)                                    │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

COST CATEGORIES TRACKED:
════════════════════════

┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│  VARIABLE COSTS (Per-Use)          │  FIXED COSTS (Allocated)              │
│  ─────────────────────────         │  ────────────────────────             │
│                                    │                                       │
│  • AWS Batch compute               │  • EC2 application servers           │
│  • Claude API tokens               │  • RDS PostgreSQL                    │
│  • Gemini API tokens               │  • ALB load balancer                 │
│  • S3 storage (per GB)             │  • NAT Gateway                       │
│  • Data transfer (per GB)          │  • CloudWatch logs/metrics           │
│                                    │  • ECR container registry            │
│  Tracked: Real-time                │  • CloudFront CDN                    │
│  Billed: Per-use or outcome        │  • Secrets Manager, SES              │
│                                    │                                       │
│                                    │  Tracked: Monthly from AWS           │
│                                    │  Billed: Divided by active users     │
│                                    │                                       │
└─────────────────────────────────────────────────────────────────────────────┘

KEY METRICS DASHBOARD:
═════════════════════

│ Metric                      │ Target      │ Alert If        │
│─────────────────────────────│─────────────│─────────────────│
│ Estimation accuracy         │ < 5% var    │ > 10% variance  │
│ LLM local vs API ratio      │ > 85% local │ < 70% local     │
│ Gross margin (Pro tier)     │ > 60%       │ < 50%           │
│ Gross margin (Outcome)      │ > 85%       │ < 75%           │
│ Cost per workflow (avg)     │ < $1.50     │ > $3.00         │
│ Cost per LLM query (avg)    │ < $0.01     │ > $0.02         │
│ Storage cost per user       │ < $5/mo     │ > $10/mo        │
│ Reconciliation status       │ Completed   │ Failed/Stale    │

```

---

## 9. Next Steps

### Immediate (Week 1-2)
- [ ] Define tagging strategy for ALL AWS resources
- [ ] Create complete database schema (8 tables)
- [ ] Build LLM cost trackers (Claude, Gemini, Ollama)
- [ ] Build compute cost estimator

### Short-term (Week 3-4)
- [ ] Build storage cost tracker (S3, RDS)
- [ ] Build infrastructure cost allocation
- [ ] Deploy Lago (self-hosted)
- [ ] Integrate Lago with Stripe
- [ ] Build nightly reconciliation job

### Medium-term (Month 2-3)
- [ ] Unified Cost Aggregator service
- [ ] Customer usage dashboard
- [ ] Cost anomaly alerts
- [ ] Billing report generation
- [ ] Evaluate Vantage for visualization

---

## Appendix: Sources

- [AWS Cost Explorer API](https://docs.aws.amazon.com/cost-management/latest/userguide/ce-api.html)
- [AWS Cost Allocation Tags](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/cost-alloc-tags.html)
- [AWS Batch Tagging](https://docs.aws.amazon.com/batch/latest/userguide/using-tags.html)
- [Serverless Batch Cost Guardian](https://github.com/aws-samples/serverless-batch-cost-guardian)
- [Vantage FinOps Tools](https://www.vantage.sh/blog/top-finops-tools-for-cloud-cost-optimization)
- [Lago Open Source Billing](https://github.com/getlago/lago)
- [Stripe Acquires Metronome](https://www.pymnts.com/acquisitions/2025/stripe-acquires-metronome-to-enhance-metered-pricing-capabilities-for-ai-companies/)
- [OpenCost](https://opencost.io/)
