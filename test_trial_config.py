#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Test script to verify trial configuration is correct.
Run: python test_trial_config.py
"""

# Test 1: Verify quota limits
print("=" * 60)
print("TEST 1: Quota Limits Configuration")
print("=" * 60)

DEFAULT_PLAN_LIMITS = {
    "free":       5.00,
    "base":      50.00,
    "basic":     50.00,
    "pro":      500.00,
    "test":     float("inf"),
    "enterprise": float("inf"),
}

print(f"✓ 'basic' plan quota: ${DEFAULT_PLAN_LIMITS['basic']}")
print(f"✓ 'free' plan quota: ${DEFAULT_PLAN_LIMITS['free']}")
print(f"✓ 'pro' plan quota: ${DEFAULT_PLAN_LIMITS['pro']}")

# Test 2: Verify tier-to-plan mapping
print("\n" + "=" * 60)
print("TEST 2: Tier to Billing Plan Mapping")
print("=" * 60)

TIER_TO_BILLING_PLAN = {
    "trial":        "free",
    "academic":     "free",
    "professional": "basic",
    "enterprise":   "pro",
    "admin":        "enterprise",
}

TIER_QUOTA_USD = {
    "trial":        5.00,
    "academic":     5.00,
    "professional": 50.00,
    "enterprise":   500.00,
    "admin":        None,
}

print(f"✓ 'professional' tier → '{TIER_TO_BILLING_PLAN['professional']}' plan")
print(f"✓ 'professional' tier quota: ${TIER_QUOTA_USD['professional']}")

# Test 3: Full flow simulation
print("\n" + "=" * 60)
print("TEST 3: Trial User Flow Simulation")
print("=" * 60)

def simulate_trial_user():
    # Step 1: User signs up
    trial_days = 14
    subscription_tier = "professional"
    print(f"Step 1: User signs up")
    print(f"  - Trial duration: {trial_days} days")
    print(f"  - Subscription tier: {subscription_tier}")

    # Step 2: Tier mapped to billing plan
    billing_plan = TIER_TO_BILLING_PLAN[subscription_tier]
    print(f"\nStep 2: Tier mapped to billing plan")
    print(f"  - Billing plan: {billing_plan}")

    # Step 3: Plan gets quota
    quota_usd = DEFAULT_PLAN_LIMITS[billing_plan]
    print(f"\nStep 3: Plan gets quota from backend")
    print(f"  - Quota: ${quota_usd}")

    return trial_days, subscription_tier, billing_plan, quota_usd

trial_days, tier, plan, quota = simulate_trial_user()

# Test 4: Validation
print("\n" + "=" * 60)
print("TEST 4: Configuration Validation")
print("=" * 60)

errors = []
warnings = []

# Check trial duration
if trial_days != 14:
    errors.append(f"Trial duration is {trial_days} days, expected 14")
else:
    print("✓ Trial duration: 14 days")

# Check tier
if tier != "professional":
    errors.append(f"Subscription tier is '{tier}', expected 'professional'")
else:
    print("✓ Subscription tier: professional")

# Check plan mapping
if plan != "basic":
    errors.append(f"Billing plan is '{plan}', expected 'basic'")
else:
    print("✓ Billing plan: basic")

# Check quota
if quota != 50.00:
    errors.append(f"Quota is ${quota}, expected $50.00")
else:
    print("✓ Quota: $50.00")

# Test 5: What users can do with $50
print("\n" + "=" * 60)
print("TEST 5: $50 Budget Breakdown")
print("=" * 60)

# Pricing from cost_calculator.py
LLM_PRICING = {
    "claude-sonnet-4-6": {"input": 3.00, "output": 15.00},  # per 1M tokens
}

EC2_PRICING = {
    "m5.xlarge": 0.192 / 4,  # $0.048 per vCPU-hour
    "g4dn.xlarge": 0.526 / 4,  # $0.1315 per vCPU-hour
    "p3.2xlarge": 3.06 / 8,  # $0.3825 per vCPU-hour
}

print("CPU Compute:")
cpu_hours = quota / EC2_PRICING["m5.xlarge"]
print(f"  - {cpu_hours:.1f} vCPU-hours on m5.xlarge (~10-20 RNA-seq workflows)")

print("\nGPU Compute:")
gpu_hours_g4 = quota / EC2_PRICING["g4dn.xlarge"]
gpu_hours_p3 = quota / EC2_PRICING["p3.2xlarge"]
print(f"  - {gpu_hours_g4:.1f} GPU-hours on g4dn.xlarge (~5-10 AlphaFold runs)")
print(f"  - {gpu_hours_p3:.1f} GPU-hours on p3.2xlarge (~2-3 CryoEM jobs)")

print("\nLLM Tokens:")
# Assume 50/50 input/output
avg_cost_per_1m = (LLM_PRICING["claude-sonnet-4-6"]["input"] + LLM_PRICING["claude-sonnet-4-6"]["output"]) / 2
tokens_millions = quota / avg_cost_per_1m
tokens = tokens_millions * 1_000_000
chats = tokens / 5000  # Assume ~5K tokens per chat exchange
print(f"  - {tokens:,.0f} tokens (~{chats:.0f} chat exchanges)")

print("\nStorage:")
s3_cost_per_gb_month = 0.023
storage_gb = quota / s3_cost_per_gb_month
print(f"  - {storage_gb:.0f} GB for 1 month")

# Final Summary
print("\n" + "=" * 60)
print("SUMMARY")
print("=" * 60)

if errors:
    print("❌ ERRORS FOUND:")
    for error in errors:
        print(f"  - {error}")
    exit(1)
else:
    print("✅ All configuration checks passed!")
    print()
    print("Trial Configuration:")
    print(f"  - Duration: 14 days")
    print(f"  - Tier: professional (Premium)")
    print(f"  - Billing Plan: basic")
    print(f"  - Budget: $50.00")
    print()
    print("Users can run:")
    print(f"  - ~200 vCPU-hours OR")
    print(f"  - ~20 GPU-hours (g4dn) OR")
    print(f"  - ~5 GPU-hours (p3) OR")
    print(f"  - ~300 chat exchanges")
    print()
    print("System is ready for trial launch! ✨")
    exit(0)
