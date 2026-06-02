# Modal serverless GPU — regulatory-LLM deploy

**Status:** Scaffolding committed. Provisioning requires `modal token new` + `modal deploy`.

**Why Modal:** the original 5-node g6.xlarge vLLM ASG was ~$1,760/mo. The cost-reduced 2-node 100% spot version is ~$290–580/mo. Modal serverless GPU, scaling to zero when idle, is **~$5–60/mo at our expected early traffic**. Migrate back to the ASG when monthly Modal billing crosses ~$200.

## Cost model

Modal L4 GPU on-demand: **$0.000222 / second**.

| Usage pattern | Cost / call | Monthly estimate |
|---|---|---|
| Sporadic (10 IND prose calls/day, all in 1 session) | ~$0.003 cold + ~$0.0007 warm + ~$0.067 idle keep-warm | **~$5/mo** |
| Bursty (1000 calls/day, ~5 sessions × 5-min warm windows) | ~$0.0007 inside warm window | **~$25/mo** |
| Continuous (8h/day always-warm) | ~$0.000222/s × 28,800 s/d | **~$160/mo** |

Compare to dedicated ASG:
- Original plan (5× g6.xlarge, 80/20 spot): **~$1,760/mo**
- Cost-reduced plan (2× g6.xlarge spot, scale-to-zero off): **~$290–580/mo**
- Modal sporadic-to-bursty: **~$5–60/mo**

## Architecture

```
  Galaxy backend (per region)
       │  MODAL_REGULATORY_LLM_ENDPOINT=https://…modal.run
       │  MODAL_REGULATORY_LLM_KEY=<from modal secret>
       ▼
  Modal app "biomate-regulatory-llm"
   ├── @modal.asgi_app → FastAPI mounting /v1/chat/completions
   ├── L4 GPU, 32 GB RAM, 4 vCPU, 5-min idle keep-warm
   ├── Volume "biomate-adapters" mounted at /adapters
   │    └── <name>/lora_adapter/ → registered as vLLM LoRARequest at @modal.enter()
   └── Volume "biomate-hf-cache" mounted at /hf-cache
        └── Qwen3-8B weights survive container restarts
```

Same OpenAI-compatible `/v1/chat/completions` surface as the ASG vLLM plan
— Galaxy backend's `_call_openai_compat_regulatory_llm` helper handles
both with one code path.

## Backend selection order

`_call_local_regulatory_llm` picks the first available backend:

1. **Modal** if `MODAL_REGULATORY_LLM_ENDPOINT` is set
2. **Dedicated vLLM** if `VLLM_BASE_URL` is set
3. **Local HF transformers** path (Phase 0 — workstation only)

If Modal returns empty (cold-start timeout, bad adapter, vol corruption),
the helper falls through to the vLLM path; if that's also empty, the
final fallback is the Gemini Flash path already wired in the section
generators. No user-visible outage.

## First-time deploy

```bash
# 1. Install + auth (operator workstation)
pip install modal
modal token new                  # opens browser

# 2. Optional bearer-token secret
modal secret create biomate-vllm-secret BIOMATE_VLLM_API_KEY=$(openssl rand -hex 32)

# 3. Seed adapters into the Modal volume from local models/
modal volume create biomate-adapters     # idempotent
modal volume put biomate-adapters \
    models/regulatory_llm_v6/lora_adapter regulatory_llm_v6/lora_adapter
# Repeat for any per-org adapters (regulatory_llm_v6_<orgid>/lora_adapter)

# 4. Deploy the app
modal deploy infra/modal/regulatory_llm_app.py

# Modal prints the public URL; copy that to Galaxy backend env:
#   export MODAL_REGULATORY_LLM_ENDPOINT=https://<workspace>--biomate-regulatory-llm-serve.modal.run
#   export MODAL_REGULATORY_LLM_KEY=<the bearer secret if you set one>

# 5. Smoke check
curl -fsS $MODAL_REGULATORY_LLM_ENDPOINT/health
curl -fsS $MODAL_REGULATORY_LLM_ENDPOINT/v1/models
```

## Smoke test from Galaxy backend

After setting `MODAL_REGULATORY_LLM_ENDPOINT`, hit any IND prose
generation flow (e.g. `/ind-report` → regenerate §2.6.1). Galaxy backend
logs should show:

```
[modal] regulatory_llm_v6 call failed: …  (if cold start exceeds timeout)
```
or no warning at all (success — the chosen backend returned content).

To verify which backend was used, grep the latest sign-audit row's
`adapter_versions` field — it includes the adapter name resolved by
`_resolve_adapter_name`.

## Adapter deploy (new LoRA or new org)

```bash
# Push a new adapter into the volume
modal volume put biomate-adapters \
    models/regulatory_llm_v7/lora_adapter regulatory_llm_v7/lora_adapter

# Restart the app so @modal.enter re-globs the volume
modal app restart biomate-regulatory-llm
```

No ASG instance refresh, no IAM, no EFS, no ALB. Adapter is hot within
~30s of the first request after restart (Qwen3-8B base weights stay
warm in the hf-cache volume).

## Cost guardrails

- **Modal usage alerts:** set in the Modal web UI at $50, $100, $200
  monthly. If billing crosses $200/mo, the ASG plan
  (`docs/20260528_VLLM_DEPLOY_RUNBOOK.md`) is cheaper.
- **Per-request budget:** the `timeout=10 * 60` on the `@app.cls`
  decorator caps a hung request at 10 min × $0.000222 = $0.13. A
  runaway loop bills at ~$0.80/h.
- **`container_idle_timeout=300`:** after 5 min idle the container
  scales to zero. Reducing to 60s drops idle cost; raising to 1800s
  smooths bursty traffic. 300s is the bursty-default sweet spot.

## Files

| File | Purpose |
|---|---|
| `infra/modal/regulatory_llm_app.py` | Modal app: image, volumes, `RegulatoryLLM` class with `@modal.enter` adapter glob + `@modal.asgi_app` FastAPI mount |
| `backend/lib/galaxy/ai/drug_discovery/ind_assembly.py` | `_call_openai_compat_regulatory_llm` helper (shared with vLLM) + Modal branch in `_call_local_regulatory_llm` |
| `docs/20260601_MODAL_REGULATORY_LLM_DEPLOY.md` | This runbook |
| `infra/vllm/` (unchanged) | ASG plan preserved for the day Modal billing crosses ~$200/mo |
