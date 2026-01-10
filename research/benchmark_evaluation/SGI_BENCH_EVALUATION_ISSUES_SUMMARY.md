# SGI-Bench: Typical Issues Found in LLM Scientific Evaluation

**Source**: arXiv:2512.16969 - "Probing Scientific General Intelligence of LLMs with Scientist-Aligned Workflows"
**Date**: December 2025
**Benchmark**: SGI-Bench by Shanghai AI Laboratory

---

## Overview

SGI-Bench evaluates **Scientific General Intelligence (SGI)** across 4 dimensions aligned with the Practical Inquiry Model (PIM):
- **Deliberation** (Deep Research)
- **Conception** (Idea Generation)
- **Action** (Dry/Wet Experiments)
- **Perception** (Experimental Reasoning)

**Key Finding**: Best model (Gemini-3-Pro) achieves only **33.83/100 SGI-Score**, far from being a "qualified scientist."

---

## 1. Deliberation (Scientific Deep Research) Issues

### Problem: "Long-chain Conclusion Collapse"
- **Step accuracy**: 50-65%
- **Final answer strict match**: Only 10-20%

### Typical Issues:
| Issue | Description |
|-------|-------------|
| **Error propagation** | Errors in early steps cascade to corrupt final conclusions |
| **Numerical aggregation failures** | Difficulty in cross-literature precise retrieval and numerical aggregation |
| **Data/property questions hardest** | Require cross-document retrieval and numerical synthesis |

### Agent Enhancement:
- Tool-augmented multi-agent systems show slightly better step-level accuracy
- But gap with pure models is **not significant**

---

## 2. Conception (Idea Generation) Issues

### Problem: "Novelty vs Feasibility Gap"
- High novelty scores but **low feasibility**
- Example: GPT-5 achieves Novelty=76.08, Feasibility=18.87

### Typical Defects:
| Defect | Description |
|--------|-------------|
| **Missing data acquisition plans** | No concrete data collection or preprocessing strategy |
| **Workflow interface misalignment** | Input/output interfaces don't connect properly |
| **Ambiguous step dependencies** | Step order and dependencies unclear |
| **"Idea→Blueprint→Execution" loop broken** | Cannot close the loop from concept to implementation |

### Open-source ceiling:
- Feasibility upper bound ~20 points (e.g., Qwen3-Max: 20.98)
- Most models: 14-20 points
- Clear gap between "can articulate" and "can implement"

---

## 3. Action: Dry Experiment (Code Generation) Issues

### Problem: "Runnable ≠ Scientifically Correct"
- **Smooth execution rate**: 90%+ (code runs without errors)
- **Strict pass rate** (all 5 unit tests): Only 36.64% (best: Gemini-3-Pro)
- **Relaxed pass rate** (at least 1 test): 41.98%

### Typical Issues:
| Issue | Description |
|-------|-------------|
| **Partial correctness** | Can write parts correctly but fail complete strict correctness |
| **Numerical calculation weakest** | Discretization, stability, constraint handling errors |
| **Simulation failures** | Scientific simulations especially problematic |
| **Algorithm instability** | Lack of numerical analysis priors |

### Example - Gravitational Wave Volume Estimation:
- Forward accumulation (`np.cumsum`) vs adaptive integration (`scipy.integrate.quad`) produce vastly different results
- Cumulative errors via χ(z) affect dV/dz, causing severe volume deviation

### Weakness by Task Type:
- **Most stable**: Data processing, predictive modeling
- **Weakest**: Numerical calculation, simulation

---

## 4. Action: Wet Experiment (Lab Protocol) Issues

### Problem: "Action Timing, Branching & Parameter Selection"
- **Sequence similarity**: Low (~35.5 best closed-source)
- **Parameter accuracy**: Max ~40.6%
- Some closed-source models drop to ~20.7% parameter accuracy

### High-frequency Errors:
| Error Type | Description |
|------------|-------------|
| **Extra step insertion** | Adding unnecessary steps |
| **Missing critical steps** | Omitting key experimental steps |
| **Step order scrambling** | Disrupting valid step sequences |
| **Temporal coordination failure** | Poor timing across workflow branches |
| **Branch planning weakness** | Cannot handle parallel/conditional branches |
| **Sample management errors** | Mixing samples between genomic sequencing and immunophenotyping |

### NSCLC Anti-PD-1 Protocol Example Errors:
- Simplifying longitudinal sampling to single blood draw
- PBMC separation at single timepoint only
- Functional assays not grouped by time/stimulation
- Mixed sample usage between genomic sequencing and immunophenotype workflows

---

## 5. Perception (Experimental Reasoning) Issues

### Problem: "Comparative Reasoning Most Difficult"
- **Best closed-source answer accuracy**: ~41.9%
- **Best reasoning validity**: ~71.3%

### Reasoning Validity > Answer Accuracy:
- Models struggle to achieve completely correct reasoning chains
- Even valid reasoning often leads to incorrect final answers

### Performance by Reasoning Type:
| Type | Performance |
|------|-------------|
| **Causal inference** | Relatively stable |
| **Perception/identification** | Relatively stable |
| **Comparative reasoning** | **Weakest** - requires cross-sample fine-grained comparison |

### Performance by Discipline:
| Discipline | Performance |
|------------|-------------|
| **Astronomy** | Best |
| **Physics, Life Sciences** | More challenging |

---

## Summary: Systematic Gaps in Current LLMs

| Dimension | Core Issue | Gap |
|-----------|------------|-----|
| **Deep Research** | Long-chain error propagation | Step accuracy high, final answer low |
| **Idea Generation** | Novelty without feasibility | Can conceive but cannot execute |
| **Dry Experiment** | Syntax correct, science wrong | Runs but incorrect results |
| **Wet Experiment** | Protocol logic failures | Timing, branching, parameters |
| **Reasoning** | Comparative analysis weakness | Cross-sample discrimination |

---

## Roadmap for Improvement (from SGI-Bench)

1. **Deep Research**: Strengthen evidence aggregation and numerical robustness
2. **Idea Generation**: Introduce planning awareness and structured supervision
3. **Code Generation**: Training beyond syntax - focus on numerical analysis priors and algorithm stability
4. **Wet Protocol**: Combine state simulation, focus on temporal logic and complex branching
5. **Multimodal Reasoning**: Fine-grained visual grounding and contrastive training for comparative reasoning

---

## Resources

- **Paper**: https://arxiv.org/pdf/2512.16969
- **Homepage**: https://InternScience.github.io/SGI-Page/
- **Code**: https://github.com/InternScience/SGI-Bench
- **Data**: https://huggingface.co/collections/InternScience/sgi-bench

---

## Datasets Downloaded

Location: `/home/yzhang/biomate/research/benchmark_evaluation/sgi_bench_datasets/`

| Dataset | Description |
|---------|-------------|
| `SGI-DeepResearch` | Scientific deep research tasks (meta-analysis, multi-hop retrieval) |
| `SGI-IdeaGeneration` | Idea generation tasks (novelty, feasibility evaluation) |
| `SGI-DryExperiment` | Code generation tasks (scientific code synthesis) |
| `SGI-WetExperiment` | Lab protocol generation tasks (wet lab procedures) |
| `SGI-Reasoning` | Multimodal experimental reasoning tasks |

Repository cloned to: `/home/yzhang/biomate/research/benchmark_evaluation/SGI-Bench/`
