# vLLM Local Smoke Test — Pre-ASG Validation

Date: 2026-05-29
Scope: validate the vLLM HTTP-client path end-to-end on a workstation GPU
before paying for the production ASG (`g5.xlarge` Spot, ~$0.30/hr +
on-demand fallback).

## What this proves

The local stack runs the **same image, same entrypoint, same LoRA discovery
logic** as the production ASG (see `infra/vllm/Dockerfile` +
`start-vllm.sh`). If the smoke test passes locally, the only remaining
production-only risks are:

- IAM / SSM parameter access (covered by `cloud-init.yaml`)
- ALB target-group registration (covered by spot-monitor + ALB health checks)
- EFS mount semantics (mirrored locally via bind mount)

All of which are AWS-side wiring, not code paths in our image. A green
local smoke means "the container does the right thing once it boots."

## Files

| Path | Role |
|---|---|
| `infra/vllm/docker-compose.local.yml` | Brings up the image with GPU passthrough; binds `./models` as `/mnt/efs/biomate-adapters` |
| `infra/vllm/smoke-test.sh` | `up` → wait `/health` → assert `regulatory_llm_v6` in `/v1/models` → POST chat completion → `down` |
| `tests/integration/test_vllm_client_path.py` | pytest that calls `_call_vllm_regulatory_llm` against the running endpoint and asserts §2.6.1 prose looks real |

## Run

```bash
# 1. Image + boot + protocol-level smoke (tears down at the end)
./infra/vllm/smoke-test.sh

# 2. Keep the stack up and run the Python client path integration test
KEEP_UP=1 ./infra/vllm/smoke-test.sh
pytest tests/integration/test_vllm_client_path.py -v

# 3. Tear down
docker compose -f infra/vllm/docker-compose.local.yml down
```

First run cold-pulls `vllm/vllm-openai:v0.6.4` (~6 GB) and loads Qwen3-8B
+ LoRA — expect 5–10 minutes before `/health` returns 200. Subsequent runs
boot in ~60–90 s thanks to the host HF cache bind.

## Pass / fail semantics

| Outcome | Meaning |
|---|---|
| `smoke-test.sh` exit 0 | Image boots, LoRA discovered, OpenAI API serves the adapter. Safe to bump the ASG. |
| `/health` timeout | Usually OOM (drop `GPU_MEM_UTIL` to 0.70) or NVIDIA driver mismatch. Check `docker compose logs vllm`. |
| `adapter not in /v1/models` | `models/regulatory_llm_v6/lora_adapter/` missing or `start-vllm.sh` glob mismatch. Do not deploy. |
| pytest skipped | Endpoint not reachable; bring up compose first. Not a failure. |
| pytest fail on prefix/length/citation | The HTTP wire is fine but the adapter is generating off-distribution prose. Re-check adapter version and `enable_thinking=false`. |

## Why this is cheaper than a "just deploy and see"

A failed ASG deploy costs ~$0.30/hr × debug-time + ECR push + instance
refresh churn (~10 min per cycle). Local cycle is free GPU time, image
layers are cached, and we can iterate on `start-vllm.sh` without rebuilding
the launch template. Per the engineering discipline rule in CLAUDE.md:
**review and validate locally first; do not speculate-deploy expensive
infrastructure.**
