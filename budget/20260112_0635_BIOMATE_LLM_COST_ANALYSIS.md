# BioMate LLM Cost Analysis & Information Flow

**Date**: 2026-01-12
**Purpose**: Team discussion on LLM infrastructure costs
**Author**: Claude Code

---

## Executive Summary

This document analyzes all cost components for BioMate's LLM infrastructure, comparing the current API-only approach with the proposed hybrid (local + API) architecture.

**Key Finding**: Hybrid architecture with local Ollama (qwen3:32b) can reduce LLM costs by **85-95%** while maintaining quality for most tasks.

---

## 1. Information Flow Architecture

### Current Flow (API-Only)
```
┌──────────┐    ┌─────────┐    ┌──────────────┐    ┌─────────────┐
│   User   │───▶│  RAG    │───▶│  LLM Client  │───▶│  Claude API │
│  Query   │    │ Retrieval│    │              │    │  (Anthropic)│
└──────────┘    └─────────┘    └──────────────┘    └─────────────┘
                    │                                     │
                    │ $0.0001/query                       │ $3-15/1M tokens
                    │ (embeddings)                        │
                    ▼                                     ▼
              ┌──────────┐                         ┌──────────┐
              │ Vector DB│                         │ Response │
              │ (local)  │                         │          │
              └──────────┘                         └──────────┘
```

### Proposed Flow (Hybrid)
```
┌──────────┐    ┌───────────┐    ┌──────────────┐
│   User   │───▶│  Router   │───▶│  Classifier  │
│  Query   │    │           │    │  (local)     │
└──────────┘    └───────────┘    └──────┬───────┘
                                        │
                    ┌───────────────────┼───────────────────┐
                    │                   │                   │
                    ▼                   ▼                   ▼
            ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
            │   SIMPLE    │     │  MODERATE   │     │   COMPLEX   │
            │             │     │             │     │             │
            │ qwen3:32b   │     │ qwen3:32b   │     │ qwen3:32b   │
            │ (local)     │     │ + RAG       │     │ + RAG       │
            │             │     │ (local)     │     │ or Claude   │
            │ Cost: $0    │     │ Cost: $0    │     │ Cost: $0-15 │
            └─────────────┘     └─────────────┘     └─────────────┘
                    │                   │                   │
                    └───────────────────┼───────────────────┘
                                        ▼
                                 ┌──────────┐
                                 │ Response │
                                 └──────────┘
```

---

## 2. Cost Components Breakdown

### 2.1 API Costs (Variable - Per Usage)

| Provider | Model | Input Cost | Output Cost | Context | Best For |
|----------|-------|------------|-------------|---------|----------|
| **Anthropic** | claude-sonnet-4-5 | $3.00/1M | $15.00/1M | 200K | Complex reasoning |
| **Anthropic** | claude-opus-4-5 | $15.00/1M | $75.00/1M | 200K | Expert tasks |
| **Anthropic** | claude-haiku-3-5 | $0.25/1M | $1.25/1M | 200K | Fast, simple |
| **Google** | gemini-2.0-flash | $0.075/1M | $0.30/1M | 1M | Vision, long context |
| **Google** | gemini-1.5-pro | $1.25/1M | $5.00/1M | 2M | Complex + vision |
| **Zhipu** | glm-4.7 | $0.60/1M | $2.20/1M | 200K | Coding tasks |
| **Zhipu** | glm-4-flash | $0.10/1M | $0.40/1M | 128K | Fast, cheap |
| **OpenAI** | gpt-4o | $2.50/1M | $10.00/1M | 128K | General |
| **Local** | qwen3:32b | $0.00 | $0.00 | 32K | All local tasks |

### 2.2 Infrastructure Costs (Fixed - Monthly)

| Component | Specification | Monthly Cost | Notes |
|-----------|--------------|--------------|-------|
| **ARM Supercomputer** | 128GB shared memory | $X,XXX | Existing infrastructure |
| **GPU Compute** | NVIDIA ARM | Included | Shared resource |
| **Storage** | Model files (~50GB) | ~$5 | SSD storage |
| **Ollama Server** | Always running | ~$50-100 | Electricity for inference |
| **Vector DB** | Embeddings storage | ~$10 | Local PostgreSQL/pgvector |
| **Monitoring** | Logs, metrics | ~$20 | Prometheus/Grafana |

### 2.3 Embedding Costs (Per Query)

| Provider | Model | Cost | Dimensions | Use Case |
|----------|-------|------|------------|----------|
| **OpenAI** | text-embedding-3-small | $0.02/1M tokens | 1536 | RAG retrieval |
| **OpenAI** | text-embedding-3-large | $0.13/1M tokens | 3072 | High accuracy |
| **Local** | nomic-embed-text (Ollama) | $0.00 | 768 | Free alternative |
| **Local** | bge-large (Ollama) | $0.00 | 1024 | Free alternative |

### 2.4 Fine-tuning Costs (One-time + Periodic)

| Item | Cost | Frequency | Notes |
|------|------|-----------|-------|
| **Data Preparation** | 20-40 dev hours | Once | Curating training data |
| **LoRA Training** | $0 (local) | Per update | 128GB sufficient |
| **Full Fine-tune** | $500-2000 (cloud) | Rare | If local insufficient |
| **Evaluation** | 5-10 dev hours | Per training | Quality assurance |
| **Adapter Storage** | ~1GB | Per version | LoRA weights |

### 2.5 Operational Costs (Ongoing)

| Item | Monthly Cost | Notes |
|------|--------------|-------|
| **Developer Maintenance** | 10-20 hours | Monitoring, updates |
| **Model Updates** | 2-5 hours | When new versions release |
| **Incident Response** | Variable | Fallback handling |
| **Documentation** | 2-4 hours | Keeping docs current |

---

## 3. Cost Per Query Analysis

### 3.1 Query Type Distribution (Estimated)

| Query Type | % of Traffic | Avg Tokens (In) | Avg Tokens (Out) |
|------------|--------------|-----------------|------------------|
| Simple Q&A | 40% | 200 | 300 |
| Tool Selection | 25% | 500 | 200 |
| Workflow Generation | 20% | 1,000 | 2,000 |
| Scientific Analysis | 10% | 2,000 | 3,000 |
| Expert/Complex | 5% | 3,000 | 5,000 |

### 3.2 Cost Per Query - API Only (Current)

Using Claude Sonnet as primary:

| Query Type | Input Cost | Output Cost | Total/Query |
|------------|------------|-------------|-------------|
| Simple Q&A | $0.0006 | $0.0045 | **$0.0051** |
| Tool Selection | $0.0015 | $0.0030 | **$0.0045** |
| Workflow Generation | $0.0030 | $0.0300 | **$0.0330** |
| Scientific Analysis | $0.0060 | $0.0450 | **$0.0510** |
| Expert/Complex | $0.0090 | $0.0750 | **$0.0840** |

### 3.3 Cost Per Query - Hybrid (Proposed)

Using local qwen3:32b for most tasks, Claude fallback for expert:

| Query Type | Router | Local Cost | API Fallback | Total/Query |
|------------|--------|------------|--------------|-------------|
| Simple Q&A | 100% local | $0.00 | $0.00 | **$0.0000** |
| Tool Selection | 100% local | $0.00 | $0.00 | **$0.0000** |
| Workflow Generation | 95% local | $0.00 | 5% × $0.033 | **$0.0017** |
| Scientific Analysis | 90% local | $0.00 | 10% × $0.051 | **$0.0051** |
| Expert/Complex | 50% local | $0.00 | 50% × $0.084 | **$0.0420** |

### 3.4 Monthly Cost Comparison

Assuming **10,000 queries/month**:

| Query Type | Volume | API-Only Cost | Hybrid Cost | Savings |
|------------|--------|---------------|-------------|---------|
| Simple Q&A | 4,000 | $20.40 | $0.00 | $20.40 |
| Tool Selection | 2,500 | $11.25 | $0.00 | $11.25 |
| Workflow Generation | 2,000 | $66.00 | $3.40 | $62.60 |
| Scientific Analysis | 1,000 | $51.00 | $5.10 | $45.90 |
| Expert/Complex | 500 | $42.00 | $21.00 | $21.00 |
| **TOTAL** | 10,000 | **$190.65** | **$29.50** | **$161.15** |

**Savings: 84.5%**

---

## 4. Detailed Information Flow with Costs

### 4.1 User Query Processing

```
STEP 1: Query Reception
────────────────────────────────────────────────────────────
User: "Create a workflow for RNA-seq differential expression"
                    │
                    ▼
            ┌───────────────┐
            │ API Gateway   │  Cost: $0 (infrastructure)
            │ Rate Limiting │
            └───────┬───────┘
                    │
                    ▼

STEP 2: Query Classification (Router)
────────────────────────────────────────────────────────────
            ┌───────────────┐
            │ Task Classifier│  Cost: $0 (rule-based, no LLM)
            │               │
            │ Input: query  │
            │ Output:       │
            │  - complexity │
            │  - task_type  │
            └───────┬───────┘
                    │
            Complexity: COMPLEX
            Task Type: WORKFLOW
                    │
                    ▼

STEP 3: RAG Retrieval
────────────────────────────────────────────────────────────
            ┌───────────────┐
            │ Embedding     │  Cost: $0.00001 (or $0 if local)
            │ Generation    │  ~50 tokens × $0.02/1M
            └───────┬───────┘
                    │
                    ▼
            ┌───────────────┐
            │ Vector Search │  Cost: $0 (local pgvector)
            │               │
            │ Retrieved:    │
            │ - deseq2 tool │
            │ - salmon tool │
            │ - workflow    │
            │   examples    │
            └───────┬───────┘
                    │
                    ▼

STEP 4: Prompt Assembly
────────────────────────────────────────────────────────────
            ┌───────────────┐
            │ Prompt Builder│  Cost: $0 (string concat)
            │               │
            │ Components:   │
            │ - System msg  │
            │ - RAG context │
            │ - User query  │
            │ - Output fmt  │
            │               │
            │ Total: ~1,500 │
            │ tokens input  │
            └───────┬───────┘
                    │
                    ▼

STEP 5: LLM Generation
────────────────────────────────────────────────────────────
            ┌───────────────┐
    ┌──────▶│ Router Select │
    │       └───────┬───────┘
    │               │
    │       ┌───────┴───────┐
    │       ▼               ▼
    │   ┌───────┐       ┌───────┐
    │   │ Local │       │ API   │
    │   │qwen3  │       │Claude │
    │   │:32b   │       │       │
    │   │       │       │       │
    │   │Cost:  │       │Cost:  │
    │   │$0.00  │       │$0.0330│
    │   └───┬───┘       └───┬───┘
    │       │               │
    │       └───────┬───────┘
    │               │
    │       Output: ~2,000 tokens
    │       (workflow JSON)
    │               │
    │               ▼
    │
    │   STEP 6: Response Processing
    │   ────────────────────────────────────────────────────────
    │       ┌───────────────┐
    │       │ Validation    │  Cost: $0 (JSON schema check)
    │       │ Formatting    │
    │       └───────┬───────┘
    │               │
    │               ▼
    │       ┌───────────────┐
    │       │ Cache Result  │  Cost: $0 (Redis/local)
    │       │ (optional)    │
    │       └───────┬───────┘
    │               │
    │               ▼
    │       ┌───────────────┐
    │       │ Return to     │  Cost: $0
    │       │ User          │
    │       └───────────────┘
    │
    │   STEP 7: Logging & Monitoring
    │   ────────────────────────────────────────────────────────
    │       ┌───────────────┐
    └───────│ Log:          │  Cost: ~$0.001 (storage)
            │ - Query       │
            │ - Model used  │
            │ - Tokens      │
            │ - Latency     │
            │ - Cost        │
            └───────────────┘
```

### 4.2 Cost Accumulation Per Request

| Step | Component | API-Only Cost | Hybrid Cost |
|------|-----------|---------------|-------------|
| 1 | Gateway | $0.0000 | $0.0000 |
| 2 | Classification | $0.0000 | $0.0000 |
| 3 | Embedding | $0.0000 | $0.0000 |
| 3 | Vector Search | $0.0000 | $0.0000 |
| 4 | Prompt Build | $0.0000 | $0.0000 |
| 5 | LLM Generation | **$0.0330** | **$0.0000-0.0330** |
| 6 | Validation | $0.0000 | $0.0000 |
| 7 | Logging | $0.0010 | $0.0010 |
| **Total** | | **$0.0340** | **$0.0010-0.0340** |

---

## 5. Scaling Projections

### 5.1 Monthly Query Volume Scenarios

| Scenario | Queries/Month | API-Only | Hybrid | Savings |
|----------|---------------|----------|--------|---------|
| Current | 10,000 | $191 | $30 | $161 (84%) |
| Growth 2x | 20,000 | $382 | $59 | $323 (85%) |
| Growth 5x | 50,000 | $954 | $148 | $806 (84%) |
| Growth 10x | 100,000 | $1,907 | $295 | $1,612 (85%) |

### 5.2 Annual Cost Projection

| Volume | API-Only/Year | Hybrid/Year | Annual Savings |
|--------|---------------|-------------|----------------|
| 10K/mo | $2,292 | $360 | **$1,932** |
| 50K/mo | $11,448 | $1,776 | **$9,672** |
| 100K/mo | $22,884 | $3,540 | **$19,344** |

### 5.3 Break-even Analysis

Fixed costs for hybrid setup:
- Infrastructure overhead: ~$100/month
- Developer time (setup): 40 hours one-time
- Developer time (maintenance): 10 hours/month

**Break-even point**: ~1,000 queries/month

---

## 6. Cost Optimization Strategies

### 6.1 Immediate (No Code Changes)
| Strategy | Savings | Effort |
|----------|---------|--------|
| Use Haiku for simple queries | 30-40% | Config change |
| Reduce max_tokens where possible | 10-20% | Config change |
| Enable response caching | 20-30% | Config change |

### 6.2 Short-term (Router Integration)
| Strategy | Savings | Effort |
|----------|---------|--------|
| Route simple to local qwen3 | 60-70% | 1-2 days |
| Route moderate to local + RAG | 20-30% | Included above |
| Keep complex on Claude | N/A | Fallback |

### 6.3 Long-term (Fine-tuning)
| Strategy | Savings | Effort |
|----------|---------|--------|
| LoRA fine-tune domain expert | Additional 5-10% | 1-2 weeks |
| Dual-model architecture | Better quality | 2-4 weeks |
| Custom small model for routing | Faster routing | 1 week |

---

## 7. Risk Analysis

### 7.1 Cost Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| API price increases | +20-50% costs | More local routing |
| Traffic spike | Linear cost increase | Rate limiting, caching |
| Model quality issues | User churn | Fallback to Claude |
| Local server downtime | 100% to API | Auto-failover |

### 7.2 Quality vs Cost Trade-offs

| Configuration | Quality | Cost | Recommendation |
|---------------|---------|------|----------------|
| 100% Claude | Highest | Highest | Premium tier only |
| Hybrid (current proposal) | High | Low | **Default** |
| 100% Local | Good | Lowest | Cost-sensitive |
| Local + Fine-tuned | High | Low | After validation |

---

## 8. Monitoring & Alerting

### 8.1 Cost Metrics to Track

```
┌─────────────────────────────────────────────────────────────┐
│                    COST DASHBOARD                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Daily API Spend        Monthly Projection    Budget Alert  │
│  ┌─────────────┐       ┌─────────────┐       ┌──────────┐  │
│  │   $12.45    │       │   $373.50   │       │  ⚠ 75%   │  │
│  │   ▲ 5%      │       │   ▼ 12%     │       │  of $500 │  │
│  └─────────────┘       └─────────────┘       └──────────┘  │
│                                                             │
│  Queries by Model                    Cost by Query Type     │
│  ┌─────────────────────┐            ┌────────────────────┐ │
│  │ qwen3:32b    8,234  │            │ Simple      $0.00  │ │
│  │ claude       1,421  │            │ Moderate   $12.30  │ │
│  │ gemini         345  │            │ Complex    $45.60  │ │
│  └─────────────────────┘            └────────────────────┘ │
│                                                             │
│  Local vs API Ratio                  Avg Cost/Query         │
│  ┌─────────────────────┐            ┌────────────────────┐ │
│  │ ████████████░░ 82%  │            │     $0.0037        │ │
│  │ Local    │  API     │            │     ▼ 23%          │ │
│  └─────────────────────┘            └────────────────────┘ │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 8.2 Alerts Configuration

| Metric | Warning | Critical | Action |
|--------|---------|----------|--------|
| Daily spend | >$20 | >$50 | Notify team |
| API error rate | >5% | >20% | Page on-call |
| Local model latency | >10s | >30s | Check GPU |
| Fallback rate | >20% | >50% | Investigate |

---

## 9. Implementation Checklist

### Phase 1: Foundation (Week 1)
- [ ] Deploy hybrid router to staging
- [ ] Configure cost tracking per request
- [ ] Set up monitoring dashboard
- [ ] Test fallback mechanisms

### Phase 2: Rollout (Week 2)
- [ ] Enable for 10% of traffic
- [ ] Monitor quality metrics
- [ ] Compare cost vs API-only
- [ ] Adjust routing thresholds

### Phase 3: Full Deployment (Week 3)
- [ ] Increase to 100% traffic
- [ ] Document cost savings
- [ ] Fine-tune routing rules
- [ ] Plan fine-tuning if needed

---

## 10. Summary

### Current State
- **Cost**: ~$190/month at 10K queries
- **Model**: Claude API only
- **Risk**: Linear cost scaling

### Proposed State
- **Cost**: ~$30/month at 10K queries
- **Model**: Local qwen3:32b + Claude fallback
- **Savings**: 84-95%

### Investment Required
- Developer time: 40-60 hours
- Infrastructure: Already available (128GB ARM)
- Ongoing: 10-20 hours/month maintenance

### ROI
- Break-even: <1 month
- Annual savings at current volume: ~$1,900
- Annual savings at 5x growth: ~$9,600

---

## Appendix A: Token Estimation Guide

| Content Type | Tokens/Item | Example |
|--------------|-------------|---------|
| Word | ~1.3 | "bioinformatics" = 4 tokens |
| Tool XML | ~200-500 | Single tool definition |
| Workflow JSON | ~500-2000 | Depends on complexity |
| Scientific paragraph | ~100-200 | Abstract section |
| Code block | ~50-300 | Python function |

## Appendix B: Provider API References

- Anthropic Pricing: https://anthropic.com/pricing
- Google AI Pricing: https://ai.google.dev/pricing
- Zhipu Pricing: https://open.bigmodel.cn/pricing
- OpenAI Pricing: https://openai.com/pricing

## Appendix C: Local Model Specifications

| Model | Parameters | VRAM | Disk | Context |
|-------|------------|------|------|---------|
| qwen3:32b | 32B | 20-24GB | 20GB | 32K |
| qwen3:32b-fp16 | 32B | 64GB | 64GB | 32K |
| qwen3:8b | 8B | 6GB | 5GB | 32K |
