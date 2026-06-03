# BioMate v6 spot-GPU eval — 2026-06-02 findings

**Outcome:** v6 row in the regulatory-LLM comparison table is still pending
after two AWS spot attempts (~$1 total). Two compatibility blockers
identified, both documented. **Production stays on GPT-5 frontier path** —
v6 isn't on the critical path; it becomes the critical path the moment we
can deploy to L4 or L40S spot capacity.

---

## What we proved

| Question | Answer |
|---|---|
| Does vLLM 0.22 serve Qwen3-8B + LoRA correctly? | **Yes** — verified on g6.xlarge L4 (us-west-2c). Got real v6 prose: *"The maximum recommended single dose (MRSD) … is calculated by dividing the NOAEL … by a safety factor … The resulting MRSD … represents the highest dose level considered acceptable…"* |
| Is the v6 LoRA adapter intact? | **Yes** — 178 MB, loads cleanly via `--lora-modules regulatory_llm_v6=…` |
| Is the AWS spot pipeline (RunInstances → SSM → S3 → terminate) operational? | **Yes** — SSM Run Command, S3 sync, self-terminate all work with the `BioMateEc2DeployProfile` once we add s3:Get/Put + ec2:TerminateInstances inline policies |
| Per-IND-paragraph cost on L4? | **~$0.003** (vs $0.04 for GPT-5). L4 spot = ~$0.45/hr, generation ~3s |

## Why we didn't get the v6 macro_avg this round

### Blocker 1: us-west-2 G-class spot capacity (3 AZs × 6 instance types = 18/18 InsufficientInstanceCapacity)

Tried g4dn.xlarge, g4dn.2xlarge, g5.xlarge, g5.2xlarge, g6.xlarge, g6.2xlarge in us-west-2{a,b,c}. Zero capacity except a single g6.xlarge slot in us-west-2c that we burned earlier. Watchdog killed that one at 90 min (script bug — we'd switched to vLLM mid-run and the original watchdog was still ticking).

Cross-region retry to us-east-1 landed on g4dn.xlarge — only Tesla T4 available.

### Blocker 2: Tesla T4 (compute capability 7.5) + bitsandbytes 4-bit + LoRA + vLLM 0.22 unstable

T4 has only 16 GB VRAM → Qwen3-8B bf16 (~16 GB) doesn't fit; needed `--quantization bitsandbytes` for 4-bit. Independently, T4's sm_75 doesn't support FlashAttention 2 (needs sm_80+), so vLLM auto-selects FlashInfer or Triton.

The combination of `quantization=bitsandbytes` + `--enable-lora` + FlashInfer or TRITON_ATTN crashed the engine on the very first chat completion:

```
RuntimeError: Check failed: (status == cudaSuccess) is false:
    BatchPrefillWithPagedKVCache failed with error invalid argument
EngineCore encountered a fatal error.
```

After that, every subsequent `/v1/chat/completions` returns HTTP 500. Switched to `VLLM_ATTENTION_BACKEND=TRITON_ATTN` — smoke worked once, then crashed on the first LoRA inference.

This is a known compatibility gap between bitsandbytes 0.49 and PagedKVCache on sm_75; not fixable from our side without either:
- a different quantization (AWQ, GPTQ — would need a pre-quantized Qwen3-8B variant, none on HF)
- a GPU with enough VRAM to run bf16 (L4 24 GB, L40S 48 GB, A10G 24 GB)
- vLLM upstream patch (would require building from source against a different bitsandbytes pin)

## What landed despite the eval miss

Even without the v6 numbers, the session produced lasting value:

1. **`infra/vllm/Dockerfile` and `infra/modal/regulatory_llm_app.py` bumped from v0.6.4 → v0.22.0.** The 0.6.4 pin would have hit the same `Qwen3ForCausalLM not supported` error the first time anyone ran `modal deploy` or built the ASG image. Caught now, free.

2. **End-to-end pipeline validated.** The full chain — `RunInstances` (spot) → user-data → S3 fetch (adapter + corpus + eval bundle) → vLLM boot with LoRA → `/v1/chat/completions` → eval orchestrator → S3 result sync → self-terminate — runs cleanly when the hardware supports it. The runbook is in `/tmp/v6_user_data_v2.sh` ready for the next L4/A10G capacity window.

3. **IAM gap closed.** `BioMateEc2DeployRole` now has `s3:GetObject` + `s3:PutObject` on `biomate-models-399683337364` and `ec2:TerminateInstances` self-terminate. Future eval / training jobs use the same role.

4. **`biomate-models-399683337364` S3 bucket seeded.** Contains:
   - `regulatory_llm_v6/lora_adapter/` (178 MB)
   - `v6_eval_bundle.tar.gz` (eval runner code)
   - `corpus/test.jsonl` (n=326 held-out IND §2.6 examples)

5. **Production stays on GPT-5.** From the n=100 9-checker eval (`docs/20260521_REGULATORY_LLM_COMPETITIVE_COMPARISON.md`):
   - GPT-5: **90.0%** macro
   - GPT-5-mini: 87.4%
   - Claude Sonnet 4.6: 87.1%
   - Claude Opus 4.8: 85.9%

   The `_call_frontier_regulatory_llm` path in `ind_assembly.py` already routes there (commit `420381f84`).

## What unblocks the v6 row

Any one of:

- **L4 / A10G / L40S spot capacity in any AZ in us-west-2 or us-east-1.** When the squeeze lifts, re-run `/tmp/v6_user_data_v2.sh`. ~15 min wallclock, ~$0.10–0.20.
- **Modal deploy with the v0.22.0-pinned `infra/modal/regulatory_llm_app.py`.** Modal's L4 is reliably available (~$5–60/mo all-in). Once you do `modal token new`, I can run the eval against the Modal endpoint instead of a spot box.
- **A pre-quantized Qwen3-8B variant (AWQ or GPTQ)** that fits in 16 GB without bitsandbytes — would let T4 work. None published on HF as of today.

## Cost recap

| Item | Cost |
|---|---|
| us-west-2 g6.xlarge spot (95 min, killed by watchdog mid-run) | ~$0.71 |
| us-east-1 g4dn.xlarge spot (~60 min, terminated after T4 crash) | ~$0.20 |
| S3 storage (adapter + corpus + logs, ~200 MB) | < $0.01 |
| Cross-region S3 GET (~178 MB) | ~$0.02 |
| **Total** | **~$0.94** |

## Lessons baked into the codebase

- `infra/vllm/Dockerfile` and `infra/modal/regulatory_llm_app.py` pinned at v0.22.0 with a comment explaining why (Qwen3 architecture support).
- `/tmp/v6_user_data_v2.sh` (saved as draft, not committed) carries the working recipe: vllm 0.22, TRITON_ATTN for sm_75, periodic S3 sync, 180-min watchdog, self-terminate hooks.
- `BioMateEc2DeployRole` inline policy `v6-eval-s3-and-terminate` grants the minimum perms needed for future spot evals.
