# Local LLM Comparison for BioMate

**Date:** 2026-01-27 21:51
**Purpose:** Evaluate cost-effective local LLM options for HIPAA-compliant self-hosted deployment

---

## Executive Summary

| Model | Recommendation | Why |
|-------|----------------|-----|
| **GLM-4.7-Flash** | **Best for local** | Runs on consumer hardware (RTX 4090/Mac M3+), Apache 2.0 license, top coding benchmarks |
| GLM-4.7 Full | Best performance | Requires 128-200GB RAM, but highest benchmark scores |
| Kimi K2.5 | Too expensive for local | Needs 16x H200 GPUs ($15-60K/mo), better via API/Bedrock |
| DeepSeek V3.2 | Good API alternative | Cheap API ($0.28/1M input), similar hardware needs to Kimi |

---

## Model Comparison

### 1. GLM-4.7 (Zhipu AI / Z.ai)

**Release:** December 22, 2025
**License:** Apache 2.0 (commercial use allowed)
**Architecture:** MoE (Mixture of Experts)

#### Variants

| Model | Total Params | Active Params | Context | Best For |
|-------|--------------|---------------|---------|----------|
| GLM-4.7 (Full) | 355B | ~32B | 200K | Max performance |
| GLM-4.7-Flash | 30B | 3B | 128K | Local/consumer HW |
| GLM-4-9B | 9B | 9B | 128K | Lightweight tasks |

#### Hardware Requirements

| Configuration | VRAM | RAM | Disk | Speed |
|---------------|------|-----|------|-------|
| GLM-4.7-Flash Q4 | 5-6 GB | 16-32 GB | ~15 GB | 60-85 tok/s (M4) |
| GLM-4.7 Full Q4 | 40 GB | 165-205 GB | ~200 GB | ~5 tok/s |
| GLM-4.7 Full Q2 dynamic | 24 GB | 128 GB | 135 GB | ~10 tok/s |
| GLM-4.7 Full FP8 | ~30 GB | - | ~200 GB | Production speed |

#### API Pricing

| Provider | Input (per 1M tokens) | Output (per 1M tokens) |
|----------|----------------------|------------------------|
| Z.ai Direct | $0.10 | $0.10 |

#### Benchmarks

| Benchmark | GLM-4.7 | Notes |
|-----------|---------|-------|
| SWE-bench Verified | 73.8% | Highest among open-source |
| LiveCodeBench | 84.9% | Beats Claude Sonnet 4.5 |
| HLE (Humanity's Last Exam) | 42.8% | 38% improvement over GLM-4.6 |
| AIME 2025 (Math) | 95.7% | Strong reasoning |

#### Resources

- Hugging Face: https://huggingface.co/zai-org/GLM-4.7
- Flash variant: https://huggingface.co/zai-org/GLM-4.7-Flash
- GGUF (llama.cpp): https://huggingface.co/AaryanK/GLM-4.7-GGUF
- 4-bit MLX (Apple): https://huggingface.co/mlx-community/GLM-4.7-4bit

---

### 2. Kimi K2.5 (Moonshot AI)

**Release:** January 27, 2026
**License:** Modified MIT
**Architecture:** MoE (Mixture of Experts)

#### Specifications

| Spec | Value |
|------|-------|
| Total Parameters | 1 Trillion |
| Active Parameters | 32B |
| Context Length | 256K tokens |
| Experts | 384 (8 selected per token) |
| Vision Encoder | MoonViT (400M params) |

#### Hardware Requirements (Self-Hosted)

| Configuration | Hardware | Monthly Cost (AWS) |
|---------------|----------|-------------------|
| vLLM/SGLang (Full) | 16x H200 GPUs | $19K-57K |
| KTransformers (Hybrid) | 768GB RAM + 24GB GPU | ~$10K |
| Quantized (Q4/1-bit) | 256-768GB RAM | ~$5-7K |

#### API Pricing

| Provider | Input (per 1M tokens) | Output (per 1M tokens) |
|----------|----------------------|------------------------|
| Moonshot Direct | $0.60 | $2.50 |
| Moonshot Turbo | $1.15 | $8.00 |
| AWS Bedrock (K2 Thinking) | TBD | TBD |

#### Key Features

- Native multimodal (vision + text)
- Agent Swarm: Up to 100 sub-agents, 1,500 tool calls
- 4.5x faster execution vs single-agent
- Tool calling support in vLLM/SGLang

#### HIPAA Compliance

- **Direct API:** No official HIPAA BAA (Chinese company)
- **AWS Bedrock:** HIPAA eligible under AWS BAA
- **Self-hosted:** You control compliance

#### Resources

- Hugging Face: https://huggingface.co/moonshotai/Kimi-K2.5
- GitHub (docs): https://github.com/MoonshotAI/Kimi-K2
- CLI Agent: https://github.com/MoonshotAI/kimi-cli
- Deployment Guide: reference/Kimi-K2/docs/deploy_guidance.md

---

### 3. DeepSeek V3.2

**License:** Open weights
**Architecture:** MoE

#### API Pricing

| Type | Cost (per 1M tokens) |
|------|---------------------|
| Input (cache miss) | $0.28 |
| Input (cache hit) | $0.014 (90% discount) |
| Output | $0.42 |

#### Benchmarks

| Benchmark | DeepSeek V3.2 |
|-----------|---------------|
| SWE-bench Verified | 73.1% |
| LiveCodeBench | 83.3% |

---

## Cost Comparison Summary

### API Costs (per 1M tokens)

| Model | Input | Output | Notes |
|-------|-------|--------|-------|
| **GLM-4.7** | **$0.10** | **$0.10** | Best value |
| DeepSeek V3.2 | $0.28 | $0.42 | Good with caching |
| Kimi K2 | $0.60 | $2.50 | Expensive |
| Claude Sonnet | $3.00 | $15.00 | Premium |
| GPT-4o | $2.50 | $10.00 | Premium |

### Self-Hosted Monthly Costs (AWS EC2, 24/7)

| Model | Minimum Config | Cost/Month |
|-------|----------------|------------|
| **GLM-4.7-Flash** | RTX 4090 or Mac M3+ | **$0 (own HW)** |
| GLM-4.7 Full | High-memory instance | ~$5-10K |
| Kimi K2.5 | 16x H200 GPUs | $19-57K |

---

## Recommendation for BioMate

### Primary: GLM-4.7-Flash (Local)

**Why:**
1. Runs on consumer hardware (5-6GB VRAM, 16-32GB RAM)
2. Apache 2.0 license - full commercial use
3. 84.9% on LiveCodeBench (beats Claude Sonnet 4.5)
4. 60-85 tokens/sec on Apple M4
5. Free to run locally

**Use cases:**
- Development/testing
- Non-HIPAA workloads
- Cost-sensitive production

### Secondary: AWS Bedrock (Claude/Kimi K2)

**Why:**
1. HIPAA eligible with BAA
2. No infrastructure management
3. Pay-per-use for variable load

**Use cases:**
- HIPAA-compliant production
- Enterprise customers
- Variable/unpredictable load

### Hybrid Approach

```
                    +------------------+
                    |   User Request   |
                    +--------+---------+
                             |
              +--------------+--------------+
              |                             |
    +---------v---------+       +-----------v-----------+
    |  HIPAA Required?  |       |   High Volume/Dev?    |
    |                   |       |                       |
    |  YES: AWS Bedrock |       |  YES: Local GLM-4.7   |
    |  (Claude/Kimi K2) |       |  (Flash or Full)      |
    +-------------------+       +-----------------------+
```

---

## Next Steps

1. [ ] Clone GLM-4.7 repository to reference folder
2. [ ] Test GLM-4.7-Flash on local hardware
3. [ ] Benchmark against current LLM provider for BioMate tasks
4. [ ] Evaluate integration with existing LLM provider architecture
5. [ ] Document HIPAA implications for different deployment modes

---

## References

- GLM-4.7 Hugging Face: https://huggingface.co/zai-org/GLM-4.7
- GLM-4.7 Local Guide: https://unsloth.ai/docs/models/glm-4.7
- Kimi K2 GitHub: https://github.com/MoonshotAI/Kimi-K2
- Kimi K2.5 Hugging Face: https://huggingface.co/moonshotai/Kimi-K2.5
- AWS Bedrock Pricing: https://aws.amazon.com/bedrock/pricing/
- LLM Pricing Comparison: https://pricepertoken.com/
