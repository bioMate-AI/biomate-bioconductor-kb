# GPU Cost Attribution Analysis

**Date**: 2026-02-19 17:45
**Issue**: GPU cost ($6.55) < vCPU cost ($16.38) for 8-GPU workloads
**Test**: `test_billing_edge_cases.py::TestInstanceTypeExtremes::test_eight_gpu_job`
**Status**: Under Review

---

## Current Cost Attribution Model

### Shares for GPU Jobs
- **vCPU**: 50%
- **Memory**: 30%
- **GPU**: 20%
- **Total**: 100% ✅

### Shares for CPU-Only Jobs
- **vCPU**: 60%
- **Memory**: 40%
- **GPU**: 0%
- **Total**: 100% ✅

### Example: p4d.24xlarge (8-GPU instance)
**Instance**: p4d.24xlarge at $32.77/hr
- 96 vCPUs, 1152 GB RAM, 8 GPUs

**Current Breakdown**:
```
vCPU cost:   $32.77 × 50% = $16.38
Memory cost: $32.77 × 30% = $9.83
GPU cost:    $32.77 × 20% = $6.55
Total:       $32.77
```

**Per-Resource Cost**:
```
Per vCPU:  $16.38 / 96  = $0.171/vCPU-hr
Per GB:    $9.83 / 1152 = $0.0085/GB-hr
Per GPU:   $6.55 / 8    = $0.819/GPU-hr  ⚠️
```

---

## Market Analysis: GPU vs CPU Pricing

### Comparable Instance Comparison

| Instance Type | vCPUs | RAM (GB) | GPUs | Price/hr | vCPU $/hr | RAM $/GB-hr | GPU $/hr |
|---------------|-------|----------|------|----------|-----------|-------------|----------|
| **CPU-Only** |
| c6i.xlarge    | 4     | 8        | 0    | $0.170   | $0.0425   | $0.0212     | -        |
| m6i.2xlarge   | 8     | 32       | 0    | $0.384   | $0.048    | $0.012      | -        |
| **GPU Instances** |
| g4dn.xlarge   | 4     | 16       | 1    | $0.526   | -         | -           | **$0.356** (incremental) |
| g5.2xlarge    | 8     | 32       | 1    | $1.212   | -         | -           | **$0.828** (incremental) |
| p3.2xlarge    | 8     | 61       | 1    | $3.060   | -         | -           | **$2.676** (incremental) |
| p4d.24xlarge  | 96    | 1152     | 8    | $32.77   | -         | -           | **$3.28** (incremental/GPU) |

### Incremental GPU Cost Analysis

**g5.2xlarge** (1 GPU) vs **m6i.2xlarge** (0 GPUs):
- Same: 8 vCPUs, 32 GB RAM
- Difference: +1 GPU, +$0.828/hr
- **GPU incremental cost: $0.828/GPU-hr**

**Inference**: AWS charges ~$0.83/hr for adding 1 GPU to a baseline CPU instance.

**p4d.24xlarge** (8 GPUs):
- If baseline CPU (96 vCPU + 1152 GB) ≈ $6/hr (extrapolated from m6i series)
- GPU premium: $32.77 - $6 = **$26.77 for 8 GPUs**
- **Incremental cost per GPU: $3.35/GPU-hr**

---

## Problem: Current Model Undercharges GPUs

### Current Attribution
```
GPU share: 20% of $32.77 = $6.55 total
Per GPU: $6.55 / 8 = $0.819/GPU-hr
```

### Market Reality
```
Incremental GPU cost (from comparison): $3.35/GPU-hr
Current attribution: $0.819/GPU-hr

Undercharge: $3.35 - $0.819 = $2.53/GPU-hr (75% undercharged!)
```

**Conclusion**: The current 20% GPU share dramatically undercharges GPU usage.

---

## Proposed Solutions

### Option 1: Dynamic GPU Share Based on GPU Count

**Rationale**: More GPUs → GPU becomes the dominant cost driver

**Formula**:
```python
if gpu_count == 0:
    vcpu_share = 0.60, memory_share = 0.40, gpu_share = 0.00
elif gpu_count == 1:
    vcpu_share = 0.50, memory_share = 0.30, gpu_share = 0.20  # Current
elif gpu_count >= 2:
    vcpu_share = 0.30, memory_share = 0.20, gpu_share = 0.50  # GPU-dominant
```

**Example: p4d.24xlarge (8 GPUs)**
```
vCPU cost:   $32.77 × 30% = $9.83
Memory cost: $32.77 × 20% = $6.55
GPU cost:    $32.77 × 50% = $16.38

Per GPU: $16.38 / 8 = $2.05/GPU-hr (closer to $3.35 market rate)
```

**Pros**:
- Better reflects GPU-heavy workload economics
- Multi-GPU jobs appropriately charged
- Simple to implement

**Cons**:
- Still undercharges GPUs by ~40%
- Arbitrary threshold (why 2 GPUs?)

---

### Option 2: Incremental GPU Pricing

**Rationale**: Charge based on actual incremental GPU cost

**Formula**:
1. Calculate baseline CPU instance cost (vCPU + memory only)
2. Add incremental GPU cost ($3.35/GPU-hr for p4d, $0.83/GPU-hr for g5)
3. Attribute baseline as 60% vCPU / 40% memory
4. Attribute GPU premium 100% to GPU

**Example: p4d.24xlarge (8 GPUs)**
```
Baseline (96 vCPU + 1152 GB): ~$6/hr
  vCPU cost:   $6 × 60% = $3.60
  Memory cost: $6 × 40% = $2.40

GPU premium: $26.77 (8 GPUs × $3.35)
  GPU cost: $26.77

Total: $3.60 + $2.40 + $26.77 = $32.77
Per GPU: $26.77 / 8 = $3.35/GPU-hr (matches market!)
```

**Pros**:
- Accurately reflects AWS pricing structure
- GPU cost matches incremental market rate
- Fair attribution across all instance types

**Cons**:
- More complex to implement
- Requires baseline cost calculation per instance type
- May surprise users with high GPU costs (even if accurate)

---

### Option 3: Fixed Share Adjustment (Simple Fix)

**Rationale**: Quick fix without complexity

**Formula**:
```python
if gpu_count > 0:
    vcpu_share = 0.40, memory_share = 0.20, gpu_share = 0.40
else:
    vcpu_share = 0.60, memory_share = 0.40, gpu_share = 0.00
```

**Example: p4d.24xlarge (8 GPUs)**
```
vCPU cost:   $32.77 × 40% = $13.11
Memory cost: $32.77 × 20% = $6.55
GPU cost:    $32.77 × 40% = $13.11

Per GPU: $13.11 / 8 = $1.64/GPU-hr (better, but still 50% under market)
```

**Pros**:
- Minimal code change
- GPU cost now exceeds vCPU cost (test passes)
- Simple to understand

**Cons**:
- Still undercharges GPUs
- Doesn't scale with GPU count

---

## Recommendation: Option 1 (Dynamic GPU Share)

**Recommended Implementation**:
```python
if gpu_count == 0:
    vcpu_cost   = base * 0.60
    memory_cost = base * 0.40
    gpu_cost    = 0.0
elif gpu_count == 1:
    vcpu_cost   = base * 0.50
    memory_cost = base * 0.30
    gpu_cost    = base * 0.20
else:  # gpu_count >= 2 (multi-GPU)
    vcpu_cost   = base * 0.30
    memory_cost = base * 0.20
    gpu_cost    = base * 0.50
```

**Rationale**:
1. **Accuracy**: Better reflects economics of multi-GPU workloads
2. **Simplicity**: Easy to implement, easy to test
3. **Fairness**: Single-GPU jobs unchanged, multi-GPU jobs appropriately charged
4. **Test compliance**: GPU cost > vCPU cost for 8-GPU jobs ✅

**Trade-offs Accepted**:
- Still undercharges GPUs by ~40% (vs Option 2)
- But avoids complexity and user sticker shock

---

## Implementation Impact

### Code Changes Required
**File**: `lib/galaxy/ai/billing/core/cost_calculator.py`
**Lines**: 192-199 (cost attribution logic)

**Current**:
```python
if gpu_count > 0:
    vcpu_cost   = base * 0.50
    memory_cost = base * 0.30
    gpu_cost    = base * 0.20
```

**Proposed**:
```python
if gpu_count == 0:
    vcpu_cost   = base * 0.60
    memory_cost = base * 0.40
    gpu_cost    = 0.0
elif gpu_count == 1:
    vcpu_cost   = base * 0.50
    memory_cost = base * 0.30
    gpu_cost    = base * 0.20
else:  # gpu_count >= 2
    vcpu_cost   = base * 0.30
    memory_cost = base * 0.20
    gpu_cost    = base * 0.50
```

### Test Impact
- **Current**: 24/25 edge case tests passing
- **After fix**: 25/25 edge case tests passing (100% ✅)
- **Regression risk**: Low (all existing tests validate 100% cost sum)

### User Impact
**Before** (p4d.24xlarge, 1 hour):
```
vCPU:   $16.38
Memory: $9.83
GPU:    $6.55
Total:  $32.77
```

**After** (p4d.24xlarge, 1 hour):
```
vCPU:   $9.83  (-40%)
Memory: $6.55  (-33%)
GPU:    $16.38 (+150%)
Total:  $32.77 (unchanged)
```

**Impact**: Users running multi-GPU jobs will see higher GPU line item, but total cost unchanged.

---

## Business Questions

Before implementing, product/finance should answer:

1. **Revenue Impact**: Do we want to charge GPUs at market rate (+40%) or accept undercharging?
   - Option 1: +150% GPU cost (but still 40% under market)
   - Option 2: +400% GPU cost (matches market exactly)

2. **User Communication**: How do we explain GPU cost increases in bills?
   - "GPU attribution increased to better reflect AWS pricing structure"
   - Provide cost breakdown transparency

3. **Competitive Position**: How do competitors charge for GPU usage?
   - Benchmark against Google Colab, Paperspace, Lambda Labs

4. **Pricing Strategy**: Should multi-GPU jobs have premium pricing?
   - Current: Flat 20% regardless of GPU count
   - Proposed: Scaled 50% for multi-GPU workloads

---

## Next Steps

### For Engineering (if Option 1 approved)
1. Update cost attribution logic in `cost_calculator.py`
2. Add test cases for 1-GPU vs multi-GPU attribution
3. Verify all 25 edge case tests pass
4. Run full billing test suite (194 tests)

### For Product/Finance
1. Review revenue impact of GPU cost reallocation
2. Decide on attribution model (Option 1, 2, or 3)
3. Approve implementation if acceptable
4. Draft user communication for billing changes

### For Documentation
1. Update billing documentation with new GPU shares
2. Add cost breakdown examples to user guides
3. Create FAQ: "Why did my GPU costs increase?"

---

**Status**: Awaiting product/finance decision on attribution model
**Blocker**: None (technical implementation ready)
**Risk**: Low (total cost unchanged, only internal attribution)
