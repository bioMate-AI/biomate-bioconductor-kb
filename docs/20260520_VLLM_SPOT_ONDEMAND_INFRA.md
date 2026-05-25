# vLLM Serving — Spot + On-Demand Backup Infrastructure

**Date:** 2026-05-20
**Decision:** vLLM on AWS spot instances with on-demand capacity as automatic backup. No other architecture under consideration.
**Replaces:** the direct HuggingFace transformers path in `_call_local_regulatory_llm` (current ~1-2 tok/s on GB10) once Phase 2 ships.

---

## Architecture

```
                            ┌──────────────────────────────────┐
                            │  Galaxy backend (frontend :5000) │
                            │  _load_local_llm() = HTTP client │
                            └──────────────┬───────────────────┘
                                           │
                                  Application Load Balancer
                                  /v1/chat/completions
                                           │
                  ┌────────────────────────┼────────────────────────┐
                  │                        │                        │
        ┌─────────▼──────────┐  ┌──────────▼──────────┐  ┌──────────▼──────────┐
        │  vLLM ASG          │  │  vLLM ASG           │  │  vLLM ASG           │
        │  Spot g6.xlarge    │  │  Spot g6.xlarge     │  │  On-Demand g6.xlarge│
        │  AZ us-west-2a     │  │  AZ us-west-2b      │  │  AZ us-west-2c      │
        │  weight=4 (target) │  │  weight=4 (target)  │  │  weight=1 (backup)  │
        └────────────────────┘  └─────────────────────┘  └─────────────────────┘
                                           │
                                  Single Auto Scaling Group
                                  Mixed Instances Policy
                                  80% spot / 20% on-demand
                                  Allocation strategy: capacity-optimized
                                  Spot interruption → on-demand back-fills
```

## Why this exact shape

**Single ASG, mixed-instances policy.** AWS handles the spot↔on-demand promotion automatically. When a spot is reclaimed, the ASG launches an on-demand replacement (per the configured `on_demand_percentage_above_base_capacity`). No custom failover code.

**Three AZs.** AWS rebalances spot capacity per AZ. Diversifying across us-west-2a/b/c reduces correlated interruption (one AZ's g6 pool drying up doesn't take us down).

**80/20 spot/on-demand.** During normal operation 4 of 5 instances are spot at ~$0.40/hr; the 5th is on-demand at ~$0.80/hr as a warm fallback for sudden cluster-wide spot reclamation. Steady-state cost: ~$0.48/hr for 5× g6.xlarge.

**`capacity-optimized` allocation.** AWS chooses spot pools with deepest available capacity (lowest interruption probability). Tested better than `lowest-price` for ML workloads where interruption mid-generation wastes work.

**Target group health check on `/v1/models`.** Spots being drained get pulled from the load balancer 120s before reclamation (per AWS Spot Instance termination notice).

---

## Instance choice

| Instance | GPU | VRAM | Cost on-demand | Cost spot (typical) | Notes |
|---|---|---|---|---|---|
| `g6.xlarge` | 1× L4 | 24 GB | $0.80/hr | $0.30-0.45/hr | Right size for Qwen3-8B + LoRA + KV cache |
| `g6.2xlarge` | 1× L4 | 24 GB | $1.00/hr | $0.40-0.60/hr | More vCPU; over-spec for one model |
| `g5.xlarge` | 1× A10G | 24 GB | $1.00/hr | $0.35-0.55/hr | Older GPU, sometimes cheaper than g6 |
| `p4d.24xlarge` | 8× A100 | 320 GB | $32/hr | (rare on spot) | Overkill |

**Default:** `g6.xlarge`. Falls back to `g5.xlarge` in the ASG's instance-type override list if g6 spot pool is empty.

---

## vLLM container

Use the official `vllm/vllm-openai` image with LoRA hot-swap. Start command:

```bash
docker run --rm --gpus all --ipc=host \
  -v /mnt/efs/biomate-adapters:/adapters:ro \
  -p 8000:8000 \
  vllm/vllm-openai:latest \
  --model Qwen/Qwen3-8B \
  --download-dir /mnt/efs/biomate-hfcache \
  --tokenizer Qwen/Qwen3-8B \
  --gpu-memory-utilization 0.85 \
  --max-model-len 4096 \
  --enable-lora \
  --max-loras 6 \
  --max-lora-rank 16 \
  --lora-modules \
      "regulatory_llm_v6=/adapters/regulatory_llm_v6/lora_adapter" \
      "regulatory_llm_v6_acme=/adapters/regulatory_llm_v6_acme/lora_adapter" \
      "regulatory_llm_v6_novobio=/adapters/regulatory_llm_v6_novobio/lora_adapter" \
  --quantization bitsandbytes \
  --enforce-eager
```

Key flags explained:

- **`--enable-lora --max-loras 6`** — serve up to 6 LoRA adapters on the same base model; per-request `model: <adapter_name>` selects which. **This is what makes per-customer adapters viable** — no separate base-model loads.
- **`--lora-modules name=path ...`** — adapter manifest at startup. Adding a new paid customer means rebuilding this list. (vLLM also supports dynamic LoRA loading via API; we can switch when we exceed 6 paid customers.)
- **`--gpu-memory-utilization 0.85`** — leaves 3.6 GB of L4's 24 GB for KV cache + safety margin.
- **`--quantization bitsandbytes`** — 4-bit NF4 (matches what `_call_local_regulatory_llm` already loads).
- **`--enforce-eager`** — skip CUDA graph compilation (faster cold start, slightly slower per-token; right tradeoff for our request volume).

Expected throughput on g6.xlarge: ~25-40 tok/s per active request, ~120 tok/s aggregate with continuous batching. A 400-token §2.6.6 subsection completes in ~10s warm.

---

## Adapter storage

**EFS volume** mounted at `/mnt/efs/biomate-adapters` on every vLLM node. EFS gives us:

- Same adapter set visible to every spot instance (no per-node sync)
- Cheap (~$0.30/GB-month) for 175 MB × N adapters
- Survives spot reclamation (vs. EBS which gets destroyed when the instance does)
- Single source of truth — reg-science team writes new per-org adapters to EFS, ASG nodes see them on next vLLM restart

Update flow when a new per-org adapter trains:

1. Adapter lands in S3 from the training job
2. Sync to EFS: `aws s3 sync s3://biomate-models/regulatory_llm_v6_orgname/ /mnt/efs/biomate-adapters/regulatory_llm_v6_orgname/`
3. Rolling restart of the ASG (`aws autoscaling start-instance-refresh`)
4. New adapter served to all instances in ~5 minutes

---

## Spot interruption handling

vLLM doesn't natively handle SIGTERM gracefully for in-flight requests. Wrap the container in a startup script that:

1. Polls AWS IMDSv2 metadata at `http://169.254.169.254/latest/meta-data/spot/instance-action` every 5s
2. On termination notice (received 120s before reclamation):
   - Immediately deregister from ALB target group (`aws elbv2 deregister-targets`)
   - Wait for in-flight requests to drain (vLLM exposes `/health` and `/metrics` for queue depth)
   - SIGTERM vLLM at T-30s
3. ASG launches replacement (spot first; if pool empty, on-demand per the mixed-instances policy)

Total in-flight loss: ≤ 30s of requests. Customer-facing impact: a single failed regenerate that the customer retries.

---

## Cost model

Steady-state (5 vLLM nodes × 24h × 30d):
- 4 × g6.xlarge spot @ $0.40/hr × 720h = $1,152
- 1 × g6.xlarge on-demand @ $0.80/hr × 720h = $576
- 5 × EFS storage (negligible)
- 5 × CloudWatch metrics + logs (~$30)
- **Total: ~$1,760/month** for 5-node cluster

Per customer (assuming 50 documents/customer/month, each generating ~5000 tokens):
- Compute time per doc: ~2 min @ peak parallel of 5 nodes → ~24 sec billed-equivalent
- Cost per doc: ~$0.005
- Per customer: ~$0.25/month
- 100 customers = $25 of compute on top of fixed $1,760 = **$1,785/month total**

At pilot scale (≤10 customers), the fixed cost dominates. Cluster could shrink to 3 nodes (`min_size=2, max_size=3`) for ~$1,050/month.

---

## Migration from on-prem GB10

Phase by phase, no big-bang:

| Phase | What runs the LLM | Trigger | Risk |
|---|---|---|---|
| **0 (now)** | On-prem GB10, direct HF transformers via `_call_local_regulatory_llm` | — | Slow but works for ≤5 simultaneous customers |
| **1** | Same as Phase 0, but with vLLM on-prem GB10 (replace transformers backend, keep hardware) | First customer complaint about latency, or OQ-1 measures median generation > 60s | Low — same hardware, faster server |
| **2** | vLLM on EC2 spot/on-demand ASG | 3+ paying customers OR pilot signs up to scale | Medium — first production cloud deployment |
| **3** | Multi-region (us-west-2 + eu-west-1) | First EU customer signs (OQ-4) | Higher — config + data residency |

Phase 1 → Phase 2 cutover is a config change in `_load_local_llm` (HTTP client target). Phase 2 → Phase 3 needs region tagging in `paid_orgs.json` + per-region EFS replication.

---

## Production wiring change

`backend/lib/galaxy/ai/drug_discovery/ind_assembly.py` `_call_local_regulatory_llm` becomes:

```python
def _call_local_regulatory_llm(
    section_type: str, system: str, user_prompt: str,
    max_new_tokens: int = 400, temperature: float = 0.3,
    org_id: str | None = None,
) -> str:
    """Call vLLM via OpenAI-compatible HTTP endpoint."""
    import os, requests
    base_url = os.environ.get("VLLM_BASE_URL", "http://localhost:8000")
    # Resolve adapter name (logic identical to _resolve_adapter_path)
    adapter_name = _resolve_adapter_name(org_id=org_id)  # → "regulatory_llm_v6" or "_v6_acme"
    try:
        resp = requests.post(
            f"{base_url}/v1/chat/completions",
            json={
                "model": adapter_name,
                "messages": [
                    {"role": "system", "content": system},
                    {"role": "user", "content": f"/no_think\n{user_prompt}"},
                ],
                "max_tokens": max_new_tokens,
                "temperature": temperature,
                "top_p": 0.9,
                "extra_body": {"repetition_penalty": 1.1},
            },
            timeout=60,
        )
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"]
    except Exception as exc:
        log.warning("[vllm] %s failed: %s — falling back to Gemini", adapter_name, exc)
        return ""
```

Net change: ~15 lines. The fallback chain to Gemini is preserved. `_resolve_adapter_path` is renamed to `_resolve_adapter_name` (returns the vLLM `--lora-modules` key instead of a filesystem path) but the resolution order (env → per-org → public version chain) is unchanged.

---

## Open questions for this infra (also empirical, like the OQ-1..4 set)

| ID | Question | How we'll know |
|---|---|---|
| **VL-1** | Is g6.xlarge enough headroom for 5 concurrent paid customers + spike? | vLLM exposes `/metrics`; alert when `vllm_running_requests` p95 > 10. If alerts fire, scale up to g6.2xlarge. |
| **VL-2** | Does `--enforce-eager` actually pay off vs. CUDA graphs at our request rate? | A/B by running 2 ASGs (one with, one without) for a week; compare p50/p99 first-token latency. |
| **VL-3** | Spot interruption rate per AZ — does the 80/20 mix hold? | CloudWatch `aws.autoscaling.SpotInstanceTermination` counter. If >5/day, raise on-demand percentage. |
| **VL-4** | Per-customer LoRA load latency on first request after restart | log first-call-after-restart per adapter; if >5s, pre-warm via a synthetic ping on ASG instance bootstrap. |
