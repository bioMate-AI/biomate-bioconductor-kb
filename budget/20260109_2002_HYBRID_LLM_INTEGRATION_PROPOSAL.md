# Hybrid LLM Integration Proposal

**Date**: 2026-01-09 20:02
**Status**: Proposed (not implemented)
**Related**: `20260109_1836_HYBRID_LLM_ROUTER_IMPLEMENTATION.md`

---

## Current State

### What's Implemented
- `lib/galaxy/ai/llm_router.py` - Hybrid router (standalone)
- `lib/galaxy/ai/llm_client.py` - Ollama + Zhipu providers added
- `lib/galaxy/ai/config.py` - Hybrid routing config options
- `lib/galaxy/ai/test_ollama.py` - Test script
- Ollama running with `qwen3:32b` (20GB, tested & working)

### What's NOT Connected
- `ai_assistant.py` still uses direct `LLMClient`
- `galaxy_workflow_generator.py` not using router
- `enhanced_workflow_generator.py` not using router
- API endpoints not aware of hybrid routing

---

## Proposal 1: Simple Router Integration

Replace direct LLMClient usage with HybridLLMRouter.

### Changes Required

**File: `lib/galaxy/ai/ai_assistant.py`**
```python
# Before
from .llm_client import LLMClient
self.llm_client = LLMClient(config)
response = self.llm_client.generate(prompt)

# After
from .llm_router import create_hybrid_router
self.router = create_hybrid_router(prefer_local=True)
response, decision = await self.router.generate(prompt)
log.info(f"Used {decision.provider}/{decision.model}: {decision.reason}")
```

**Files to modify:**
1. `lib/galaxy/ai/ai_assistant.py`
2. `lib/galaxy/ai/galaxy_workflow_generator.py`
3. `lib/galaxy/ai/enhanced_workflow_generator.py`
4. `lib/galaxy/webapps/galaxy/api/ai_assistant.py`

**Estimated effort**: Small (replace LLMClient calls with router calls)

---

## Proposal 2: Dual-Model Architecture (Orchestrator + Expert)

More advanced architecture separating concerns.

### Architecture
```
┌─────────────────────────────────────────────────────────┐
│                    ORCHESTRATOR                         │
│              qwen3:32b (base, not fine-tuned)          │
│                                                         │
│  Responsibilities:                                      │
│  • User interaction & clarification                     │
│  • Task decomposition & planning                        │
│  • Workflow coordination                                │
│  • Result synthesis & explanation                       │
└─────────────────────┬───────────────────────────────────┘
                      │ domain queries
                      ▼
┌─────────────────────────────────────────────────────────┐
│                  DOMAIN EXPERT                          │
│           qwen3:32b + LoRA (fine-tuned on bio)         │
│                                                         │
│  Responsibilities:                                      │
│  • Tool selection with precise parameters               │
│  • Protocol-specific knowledge                          │
│  • Domain terminology & conventions                     │
│  • Error diagnosis for bio workflows                    │
└─────────────────────────────────────────────────────────┘
```

### Implementation Phases

**Phase 1: Dual-model infrastructure**
- Create `DualModelRouter` class
- Support loading two models (or same model with LoRA swap)
- Define query routing protocol between orchestrator/expert

**Phase 2: Fine-tune domain expert**
- Curate training data from:
  - Biomni tool XMLs + usage examples
  - Successful workflow generations
  - User queries → correct tool mappings
- LoRA fine-tune qwen3:32b (or smaller qwen3:8b)
- Evaluate on held-out test set

**Phase 3: Integration**
- Wire dual-model system into ai_assistant.py
- Add monitoring/logging for model usage
- A/B test against single-model baseline

### Training Data Sources
| Source | Use For | Volume |
|--------|---------|--------|
| `biomni_workflows/galaxy/tools/biomni/**/*.xml` | Tool knowledge | 397 tools |
| Successful workflow logs | Input/output pairs | TBD |
| User feedback (corrections) | Error patterns | TBD |
| Protocol documentation | Domain knowledge | TBD |

### Resource Requirements
- Fine-tuning: 128GB sufficient for LoRA on qwen3:32b
- Inference: ~24GB per model, or ~24GB with LoRA swapping
- Storage: ~1GB for LoRA adapter weights

---

## Proposal 3: Hybrid with RAG Enhancement

Keep single model, but enhance RAG with router.

### Architecture
```
User Query
    │
    ▼
┌─────────────┐    ┌─────────────┐
│   Router    │───▶│  Classify   │
│             │    │  Complexity │
└─────────────┘    └──────┬──────┘
                          │
         ┌────────────────┼────────────────┐
         ▼                ▼                ▼
    ┌─────────┐     ┌──────────┐     ┌──────────┐
    │ Simple  │     │ Moderate │     │ Complex  │
    │ No RAG  │     │ Tool RAG │     │ Full RAG │
    │ qwen3   │     │ + qwen3  │     │ + Claude │
    └─────────┘     └──────────┘     └──────────┘
```

### Benefits
- Simple queries: fast, no retrieval overhead
- Moderate: retrieve only tool docs
- Complex: full RAG + fallback to Claude if needed

---

## Recommendation

| Scenario | Recommended Approach |
|----------|---------------------|
| Quick win, minimal changes | Proposal 1 (Simple Integration) |
| Performance gaps with current RAG | Proposal 2 (Dual-Model) |
| Want adaptive RAG depth | Proposal 3 (Hybrid + RAG) |

### Suggested Path
1. **Now**: Keep router standalone, use for testing
2. **Next sprint**: Implement Proposal 1 (simple integration)
3. **If needed**: Evaluate Proposal 2 (dual-model) based on performance data

---

## Files Reference

### Created (not integrated)
- `lib/galaxy/ai/llm_router.py` - HybridLLMRouter
- `lib/galaxy/ai/test_ollama.py` - Test script

### Modified (providers added)
- `lib/galaxy/ai/llm_client.py`
- `lib/galaxy/ai/config.py`

### To Be Modified (integration)
- `lib/galaxy/ai/ai_assistant.py`
- `lib/galaxy/ai/galaxy_workflow_generator.py`
- `lib/galaxy/ai/enhanced_workflow_generator.py`
- `lib/galaxy/webapps/galaxy/api/ai_assistant.py`

---

## Environment Setup (for reference)

```bash
# Ollama with qwen3:32b
ollama serve  # Already running
ollama list   # Shows qwen3:32b (20GB)

# Test router standalone
cd /home/yzhang/biomate/backend
python lib/galaxy/ai/test_ollama.py

# Environment variables for API fallback
export ANTHROPIC_API_KEY="..."  # Claude fallback
export GOOGLE_API_KEY="..."     # Gemini fallback
export ZHIPU_API_KEY="..."      # GLM-4.7
```

---

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-01-09 | Created router, not integrated | Test standalone first |
| 2026-01-09 | Focus on qwen3:32b only | 128GB ARM supercomputer, GLM-4.6V-Flash not on Ollama yet |
| 2026-01-09 | Defer dual-model architecture | Need to evaluate if RAG gaps exist first |
