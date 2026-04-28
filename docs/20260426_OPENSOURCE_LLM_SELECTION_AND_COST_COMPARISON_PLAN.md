# Open-Source LLM Selection + Comprehensive Cost/Performance Comparison Plan

**Date:** 2026-04-26  
**Status:** Planning → Implementation

---

## Hardware Context (This Machine)

| Component | Spec |
|-----------|------|
| CPU | ARM64 (aarch64), 20 cores, 10 cores/socket |
| GPU | NVIDIA GB10 (Grace Blackwell SoC, unified memory) |
| RAM | 125 GB (unified CPU+GPU) |
| Disk | 3.7 TB NVMe, 2.3 TB free |
| Ollama speed | **8.2 tok/s** for qwen3:32b (measured) |
| Machine cost est. | ~$4,000 (DGX Spark class), 3-yr amortized = ~$0.31/hr |

**Key implication:** At 8.2 tok/s, a 300-token BioMate response takes ~36 seconds.
Smaller models (14-27B) expected ~15-25 tok/s → 12-20 sec/response. Acceptable for async eval
but too slow for interactive production use unless the model is significantly more capable.

---

## Objective 1: Select One Open-Source LLM for BioMate

### Candidate Models

| Model | Ollama tag | Params | Est. RAM | Est. tok/s (this HW) | Status |
|-------|-----------|--------|----------|----------------------|--------|
| qwen3:32b | `qwen3:32b` | 32B dense | 20 GB | 8.2 (measured) | ✅ Installed |
| qwen3:30b-a3b | `qwen3:30b-a3b` | 30B MoE, 3B active | 18.6 GB | ~20-30 est. | ✅ Installed |
| qwen3-nothink:14b | `hoangquan456/qwen3-nothink:14b` | 14B | 9.3 GB | ~18-25 est. | ✅ Installed |
| **Qwen 3.6-27B** | `qwen3.6:27b` | 27B | ~16 GB | ~12-18 est. | ⬇ Pull needed |
| **Gemma 4-26B** | `gemma4:26b` | 26B | ~15 GB | ~12-18 est. | ⬇ Pull needed |
| **DeepSeek-R1-32B** | `deepseek-r1:32b` | 32B | ~19 GB | ~8-10 est. | ⬇ Pull needed |
| DeepSeek-V4-Flash | `deepseek-v4-flash` | 284B MoE, 13B active | ~8 GB | ~25-35 est. | ⬇ Pull needed |

### Selection Benchmark Design

**Why not run full benchmarks?** At 8.2 tok/s, a full BiomniEval1 (223 tasks × ~300 tok output) would
take ~2.2 hours per model, 5 models = 11 hours. Use a **stratified subset** for selection.

**Selection subset: 30 tasks** (runs in ~18 min per model at 8 tok/s)

| Benchmark | N | Sampling strategy | Why |
|-----------|---|-------------------|-----|
| BiomniEval1 gwas_causal | 6 | stratified by difficulty | Tests OT API reasoning |
| BiomniEval1 rare_disease | 6 | stratified | Tests ranking + MANDATORY RULE compliance |
| BiomniEval1 patient_gene | 6 | stratified | Tests ClinVar/OMIM retrieval reasoning |
| LABBench CloningScenarios | 8 | hardest 8 (lowest v22 scores) | Tests cloning logic, most discriminating |
| LABBench ProtocolQA | 4 | random | Tests protocol understanding |

**Selection criteria (weighted):**

| Criterion | Weight | How measured |
|-----------|--------|-------------|
| Accuracy on selection subset | 50% | mean score 0-1 |
| Tokens/sec (throughput) | 25% | measured during eval |
| Instruction-following (MCQ format) | 15% | % tasks with valid letter answer |
| Context window ≥ 32K tokens | 10% | model spec (pass/fail) |

**Decision threshold:** Winner must score ≥ 60% accuracy AND ≥ 12 tok/s to be considered
for BioMate production use. If no model meets both, keep current Claude Sonnet 4.6 as primary
and use winner as cost-reduction fallback for simpler tasks.

---

## Objective 2: Comprehensive Benchmark Comparison vs Publications

### Dimensions to Compare

#### 2a. Performance (accuracy)
- Our BiomniEval1 scores vs published systems
- Our LABBench scores vs published Claude 3.5 Sonnet baseline
- Open-source models vs closed-source on same tasks

#### 2b. Time Efficiency
- **Latency per task** (seconds): from our DB `latency_sec` + Ollama eval timing
- **Throughput** (tokens/sec): measured from Ollama `eval_count / eval_duration`
- **Tasks per hour**: 3600 / latency_sec
- Published papers rarely report latency; where available, include

#### 2c. Financial Cost Per Task
- **Cloud API models**: actual $/task from token counts × pricing
  - Claude Sonnet 4.6: $3/$15 per 1M in/out → ~$0.003-0.008/task
  - Gemini 3 Flash: $0.075/$0.30 per 1M → ~$0.0001-0.0005/task  
  - GPT-4o (published baseline): $5/$15 per 1M → ~$0.005-0.015/task
- **Local Ollama models**: $0 API cost (zero marginal financial cost)
- **Published estimates**: derive from paper's model choice × current pricing × typical token counts

#### 2d. Hardware / Amortized Compute Cost Per Task
- **This machine (GB10 ARM)**: 
  - Machine cost: ~$4,000
  - Lifetime: 3 years, 50% utilization
  - Cost/hour: $4,000 / (3×365×24×0.5) = **$0.305/hr**
  - Cost/task = $0.305/3600 × latency_sec
  - Example: qwen3:32b at 36s/task → **$0.003/task** hardware amortized
- **A100 80GB** (for papers using GPU cluster):
  - AWS spot: ~$2.00/hr
  - At ~100 tok/s for 32B → ~3s/task → $0.0017/task
- **H100 SXM** (frontier GPU):
  - AWS: ~$3.50/hr
  - At ~200 tok/s for 32B → ~1.5s/task → $0.0015/task
- **No hardware cost for cloud API callers** (zero, all infrastructure included in per-token price)

### Published Baselines to Collect

| Publication | System | BiomniEval1 | LABBench CS | SGI | BixBench | Cost reported? |
|------------|---------|------------|------------|-----|---------|---------------|
| BiomniEval1 paper (2024) | GPT-4o | ~65% | — | — | — | No |
| BiomniEval1 paper | Claude 3.5S | ~60% | — | — | — | No |
| BiomniEval1 paper | Gemini 1.5 Pro | ~55% | — | — | — | No |
| BiomniEval1 paper | Biomni | ~70% | — | — | — | No |
| LABBench paper (2024) | Claude 3.5S | — | 60% | — | — | No |
| LABBench paper | GPT-4o | — | ~55% | — | — | No |
| SGI-Bench paper | GPT-4o | — | — | ~35% | — | No |
| BixBench paper | GPT-4o | — | — | — | ~40% | No |
| **BioMate (this work)** | Claude Sonnet 4.6 | **~68-69%** | **93.9%** | 20.9% | 26.7% | **Yes (measured)** |
| **BioMate (this work)** | Gemini 3 Flash | TBD | TBD | TBD | TBD | **Yes** |
| **BioMate (this work)** | qwen3:32b (Ollama) | TBD | TBD | — | — | **$0 + $0.003 hw** |
| **BioMate (this work)** | best OS model | TBD | TBD | — | — | **$0 + hw** |

---

## Implementation Plan

### Phase 1: Infrastructure (today)
1. **`evaluation/core/ollama_eval_client.py`** — Direct Ollama client implementing same `.ask()` interface as `BioMateEvalClient`. Calls `http://localhost:11434/v1/chat/completions` directly. Records tokens/sec from Ollama's `usage` response.
2. **`evaluation/datasets/model_selection/subset.yaml`** — 30-task selection subset (sampled from BiomniEval1 + LABBench)
3. **`evaluation/runners/run_model_selection.py`** — runs all candidate models on the subset, produces comparison table

### Phase 2: Model pulls + speed calibration (same session)
Pull candidate models that aren't installed:
```bash
ollama pull qwen3.6:27b       # ~16 GB
ollama pull gemma4:26b        # ~15 GB
ollama pull deepseek-r1:32b   # ~19 GB
```
Run a 5-prompt speed calibration on each to measure actual tok/s before committing to full eval.

### Phase 3: Selection benchmark run
- Run 30-task subset on all models (including installed ones)
- ~18-25 min per model, ~2 hrs total for 5 models
- Record: score, latency_sec, tokens/sec, instruction-following rate

### Phase 4: Full benchmarks on winner + Gemini
- Run winner (best OS model) on full BiomniEval1 (223) + LABBench (340)
- Run Gemini 3 Flash on same (as agreed primary model)
- Produces complete comparison row for the matrix

### Phase 5: Updated xlsx matrix (v14)
New sheets:
- **Model Comparison**: all systems × all benchmarks × all cost dimensions
- **Cost Analysis**: financial + hardware + time per task per model
- Replace estimated published costs with our actual measurements where available

---

## Key Decision Points

**Q: Should open-source replace Claude for production BioMate?**

Decision framework:
- If best OS model ≥ 85% of Claude's accuracy AND ≥ 15 tok/s → use as primary (zero cost)
- If best OS model 70-85% of Claude AND ≥ 15 tok/s → use for routing/intent classification only (saves ~$0.01/query on cheap tasks)
- If best OS model < 70% of Claude → keep Claude for production, report comparison in paper

**Q: Gemini 3 Flash vs open-source for cost?**
- Gemini 3 Flash: $0.075/$0.30 per 1M → essentially free for eval scale (~$0.0001/task)
- Open-source Ollama: $0 financial, ~$0.003 amortized hardware
- At eval scale, both are negligible; at production scale (1M+ queries/month), OS wins

---

## Cost Formula Reference

```
Financial cost per task = (input_tokens × in_price + output_tokens × out_price) / 1_000_000

Hardware amortized cost per task = (machine_cost_usd / (lifetime_years × 365 × 24 × utilization)) 
                                    / 3600 × latency_sec

Total cost per task = financial + hardware_amortized

This machine (GB10 ARM, $4K, 3yr, 50%):
  = (4000 / (3 × 8760 × 0.5)) / 3600 × latency_sec  
  = $0.000085 × latency_sec

Example qwen3:32b (36s/task): $0.000085 × 36 = $0.0031/task
```
