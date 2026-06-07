# BioMate Trial Quota Configuration Guide
**Date**: 2026-05-18
**Purpose**: Set reasonable resource limits for trial users to prevent abuse

---

> ⚠️ **SUPERSEDED.** The `$55/month` figure below is a planning-phase recommendation
> that was never adopted. Production reality, set on the same day:
>
> - **Trial budget:** `$25 / 14 days` (not `$55/month`)
> - **Authoritative source:** `backend/lib/galaxy/ai/billing/core/quota_enforcer.py`
>   → `DEFAULT_PLAN_LIMITS["base"] = 25.00` / `"basic": 25.00`
> - **See:** [`20260518_TRIAL_QUOTA_REDUCED_TO_25.md`](20260518_TRIAL_QUOTA_REDUCED_TO_25.md) for the actual deployed configuration.
>
> Treat this document as historical context for the per-resource breakdown
> rationale (CPU, GPU, LLM, storage proportions). The total budget figure
> is wrong; the proportions are still informative.

---

## Recommended Trial Limits

### Resource Allocation
- **CPU**: 200 hours → ~$10 USD
- **GPU**: 20 hours (g4dn) → ~$25 USD
- **LLM**: 1.5M tokens → ~$15 USD
- **Storage**: 200 GB → ~$5 USD
- **TOTAL**: **$55/month** (or $100 for comfortable headroom)

### User Experience
- **200 CPU-hours** = 8-10 medium RNA-seq workflows OR 15-20 small variant calling runs
- **20 GPU-hours** = 2-3 CryoEM reconstructions OR 5-10 AlphaFold predictions
- **1.5M tokens** = 300-500 chat exchanges with workflow generation
- **200 GB storage** = ~100 FASTQ files OR 20 BAM files

---

## Configuration Method 1: Unified Monthly Quota (Recommended)

### Set Default Quota for Trial Plan

**File**: `backend/lib/galaxy/ai/billing/core/quota_enforcer.py`

```python
DEFAULT_PLAN_LIMITS: dict[str, float] = {
    "free":       5.00,      # Existing free tier (very limited)
    "trial":     55.00,      # NEW: Trial users (generous for testing)
    "base":      50.00,      # Existing paid tier
    "pro":      500.00,
    "test":     float("inf"), # Internal testing only
    "enterprise": float("inf"),
}
```

### Register Users with Trial Plan

**During signup** (`frontend/server/auth-service.ts` or equivalent):

```typescript
// After user registration, register them in billing system
const billingPayload = {
  user_id: newUser.id,
  email: newUser.email,
  name: newUser.fullName,
  plan: "trial",  // ← Use trial plan instead of "free"
};

await fetch(`${GALAXY_URL}/internal/billing/register_user`, {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'X-Internal-Key': process.env.BILLING_INTERNAL_KEY,
  },
  body: JSON.stringify(billingPayload),
});
```

### Effect
- ✅ All costs (LLM + CPU + GPU + storage) count against single $55 quota
- ✅ Quota enforcer blocks jobs when limit reached
- ✅ User sees quota % in billing dashboard
- ✅ Simple to understand: "You have $45.20 of $55 remaining"

---

## Configuration Method 2: Per-Resource Quotas (More Control)

### Create Custom Trial Plan in Lago

**Lago Dashboard** → Plans → Create Plan

```json
{
  "name": "BioMate Trial",
  "code": "trial",
  "interval": "monthly",
  "amount_cents": 0,
  "charges": [
    {
      "billable_metric_code": "llm",
      "charge_model": "package",
      "properties": {
        "amount": "0",
        "free_units": 1500000,
        "package_size": 1000
      }
    },
    {
      "billable_metric_code": "batch_vcpu_seconds",
      "charge_model": "package",
      "properties": {
        "amount": "0",
        "free_units": 720000,
        "package_size": 3600
      }
    },
    {
      "billable_metric_code": "batch_gpu_seconds",
      "charge_model": "package",
      "properties": {
        "amount": "0",
        "free_units": 72000,
        "package_size": 3600
      }
    },
    {
      "billable_metric_code": "s3_storage_gb_hours",
      "charge_model": "package",
      "properties": {
        "amount": "0",
        "free_units": 144000,
        "package_size": 720
      }
    }
  ]
}
```

**Explanation**:
- `free_units`: How many units included before charging
- `llm`: 1.5M tokens free
- `batch_vcpu_seconds`: 720,000 seconds = 200 vCPU-hours
- `batch_gpu_seconds`: 72,000 seconds = 20 GPU-hours
- `s3_storage_gb_hours`: 144,000 GB-hours = 200 GB for 30 days
- `amount`: "0" = no charge after free units exhausted (just blocks)

### Effect
- ✅ Fine-grained control per resource type
- ✅ Lago enforces limits automatically
- ✅ User dashboard shows per-resource usage
- ⚠️ More complex to explain to users

---

## Configuration Method 3: Hybrid (USD Quota + Lago Metering)

**Best of both worlds**: Use USD quota for enforcement, Lago for detailed metering.

### Step 1: Set USD Quota via API

```python
# After user registration
import requests

payload = {
    "user_id": user_id,
    "quota_usd": 55.00,  # $55/month trial quota
    "month": None,  # Current month
}

response = requests.post(
    f"{GALAXY_URL}/internal/billing/set_quota",
    json=payload,
    headers={"X-Internal-Key": BILLING_INTERNAL_KEY}
)
```

### Step 2: Subscribe User to Trial Plan in Lago

```python
# Register user with trial plan (for metering visibility)
payload = {
    "user_id": user_id,
    "email": user_email,
    "name": user_name,
    "plan": "trial",
}

response = requests.post(
    f"{GALAXY_URL}/internal/billing/register_user",
    json=payload,
    headers={"X-Internal-Key": BILLING_INTERNAL_KEY}
)
```

### Effect
- ✅ Redis enforces $55 USD limit (fast, simple)
- ✅ Lago tracks detailed metrics (LLM tokens, vCPU-sec, GB-hours)
- ✅ Dashboard shows both: "$45 of $55 used" AND "1.2M tokens, 150 CPU-hrs"
- ✅ Easy to upgrade: just change quota to $500 for paid tier

---

## Quota Enforcement Flow

### Pre-Job Check (CPU/GPU jobs)

```python
from galaxy.ai.billing.core.quota_enforcer import check_and_reserve, QuotaExceededError

# Before submitting AWS Batch job
try:
    estimated_cost = estimate_job_cost(
        instance_type="m5.xlarge",
        vcpus=4,
        memory_mb=8192,
        gpu_count=0,
        expected_duration_minutes=30,
    )
    # estimated_cost ≈ $0.096 for 30min on m5.xlarge

    check_and_reserve(user_id, estimated_cost)

    # Quota OK → submit job
    submit_batch_job(...)

except QuotaExceededError as e:
    # Quota exceeded → block job
    return {"error": str(e), "quota_exceeded": True}, 402
```

### Post-Event Recording (All costs)

```python
# After job completes (Lambda does this automatically)
cost_usd = calculate_actual_cost(vcpus, duration_seconds)
redis.incrbyfloat(f"cost:{user_id}:month:{month}:total", cost_usd)

# Check if over quota
total = redis.get(f"cost:{user_id}:month:{month}:total")
limit = redis.get(f"quota:{user_id}:month:{month}:limit")

if float(total) >= float(limit):
    # Block future jobs (quota_pct >= 100%)
    pass
```

---

## User Experience Examples

### Example 1: Heavy GPU User
**Activity**: Runs 3 CryoEM reconstructions (7 GPU-hours each)
- **GPU cost**: 21 hrs × $0.526 = **$11.05**
- **Storage cost**: 50 GB results = **$1.15**
- **LLM cost**: 200K tokens = **$3.50**
- **Total**: **$15.70 of $55** (71% remaining)
- ✅ Well within quota

### Example 2: Heavy LLM User
**Activity**: 500 chat exchanges with workflow generation
- **LLM cost**: 1.5M tokens = **$15.00**
- **CPU cost**: Light workflows = **$5.00**
- **Storage cost**: 10 GB = **$0.23**
- **Total**: **$20.23 of $55** (63% remaining)
- ✅ Well within quota

### Example 3: Mixed Usage (Typical)
**Activity**: 10 RNA-seq runs + 1 GPU AlphaFold + 100 chats
- **CPU cost**: 100 CPU-hours = **$4.80**
- **GPU cost**: 2 GPU-hours = **$1.05**
- **LLM cost**: 300K tokens = **$4.50**
- **Storage cost**: 30 GB = **$0.69**
- **Total**: **$11.04 of $55** (80% remaining)
- ✅ Comfortable usage

### Example 4: Abuse Attempt
**Activity**: User launches 50 parallel GPU jobs
- **First job**: Passes quota check (total = $0)
- **Jobs 2-10**: Pass quota check (total < $55)
- **Job 20**: **BLOCKED** (estimated total would exceed $55)
- **Effect**: User maxes out at ~$55, cannot cause unlimited damage

---

## Monitoring & Alerts

### Admin Dashboard
**Endpoint**: `GET /internal/billing/admin/users`

```bash
curl -H "X-Internal-Key: $BILLING_INTERNAL_KEY" \
  http://localhost:8081/internal/billing/admin/users
```

**Response**:
```json
{
  "month": "2026-05",
  "user_count": 150,
  "users": [
    {
      "user_id": "trial-user-123",
      "total_usd": 52.30,
      "quota_usd": 55.00,
      "pct": 95.1,
      "llm_usd": 12.50,
      "compute_usd": 38.00,
      "storage_usd": 1.80
    },
    ...
  ]
}
```

### User Warning at 80%
**Code**: `backend/lib/galaxy/ai/billing/core/realtime_cost_service.py:151-160`

```python
def _check_quota_alert(self, user_id: str, month: str, total: float, limit: float):
    pct = (total / limit) * 100
    if pct >= 80 and not self._r.get(f"quota:{user_id}:month:{month}:alert_sent"):
        # Send warning email
        send_quota_warning_email(user_id, pct, limit)
        # Mark alert as sent
        self._r.set(f"quota:{user_id}:month:{month}:alert_sent", "1", ex=86400*35)
```

---

## Recommended Configuration for Trial Launch

### Option: Method 3 (Hybrid) - Best Balance

**Step 1**: Update `quota_enforcer.py`
```python
DEFAULT_PLAN_LIMITS = {
    "free": 5.00,
    "trial": 55.00,  # ADD THIS
    "base": 50.00,
    "pro": 500.00,
}
```

**Step 2**: Set users to "trial" plan during registration
```typescript
const billingPayload = {
  user_id: newUser.id,
  email: newUser.email,
  name: newUser.fullName,
  plan: "trial",  // ← Use this
};
```

**Step 3**: Monitor usage weekly
```bash
# Check who's approaching quota
curl -H "X-Internal-Key: $KEY" http://localhost:8081/internal/billing/admin/users \
  | jq '.users[] | select(.pct > 80)'
```

**Step 4**: (Optional) Configure 80% email warning
- Integrate with `emailService.sendEmail()` in `realtime_cost_service.py`
- Template: "You've used 80% of your trial quota ($44 of $55). Upgrade to continue."

---

## Cost Projections

### Conservative Estimate (Light Usage)
- 100 trial users
- 50% active (use any resources)
- Average usage: $15/user
- **Total cost**: 100 × 50% × $15 = **$750/month**

### Moderate Estimate (Medium Usage)
- 100 trial users
- 70% active
- Average usage: $30/user
- **Total cost**: 100 × 70% × $30 = **$2,100/month**

### High Estimate (Heavy Usage)
- 100 trial users
- 80% active
- Average usage: $45/user (near quota limit)
- **Total cost**: 100 × 80% × $45 = **$3,600/month**

### Abuse Prevention
- With $55 quota: **Maximum damage = $5,500** (100 users × $55)
- Without quota: **Unlimited damage** (users could rack up thousands)
- **ROI**: Quota system prevents potential $50K+ abuse scenarios

---

## Summary

**Recommended Setup**:
1. Add `"trial": 55.00` to `DEFAULT_PLAN_LIMITS`
2. Register new users with `plan="trial"`
3. Monitor usage via `/internal/billing/admin/users`
4. Send email warnings at 80% quota
5. Auto-block jobs when quota reached (already implemented)

**User gets**:
- 200 CPU-hours
- 20 GPU-hours
- 1.5M LLM tokens
- 200 GB storage
- **Total: $55 budget**

**You get**:
- ✅ Abuse prevention (max $55 per user)
- ✅ Cost control (predictable trial expense)
- ✅ Full tracking (all usage recorded)
- ✅ Easy upgrade path (just change quota to $500)

**Next Step**: Update `quota_enforcer.py` and I'll help you test it.
