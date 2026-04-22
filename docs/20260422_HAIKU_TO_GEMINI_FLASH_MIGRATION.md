# Haiku → Gemini 3 Flash Migration

**Date:** 2026-04-22  
**Status:** Complete  

## Overview

Replaced all `claude-haiku-*` model usages throughout the BioMate system with `gemini-3-flash-preview` (Gemini 3 Flash). These were the "fast/cheap" inference calls — classification, extraction, summarization, and error analysis — not the main Sonnet-powered reasoning path.

Two new thin wrappers were created to isolate the Gemini call pattern from Anthropic SDK usage:

- `backend/lib/galaxy/ai/gemini_flash.py` — Python helper
- `frontend/server/gemini-flash.ts` — TypeScript helper

## Changed Files

### Backend Python

| File | Change |
|------|--------|
| `webapps/galaxy/api/nextflow_executor.py` | Error log parsing call |
| `webapps/galaxy/api/autofix3.py` | Error summary endpoint call + docstring |
| `ai/workflow_modification_classifier.py` | Workflow modification classification call |
| `ai/agents/research_agent.py` | Vision/figure reading → `call_gemini_flash_vision` |
| `ai/workflow_ops/query_agent.py` | Model string in `llm_client.call()` |
| `ai/workflow_ops/auto_healer.py` | Model string in `llm_client.call()` |
| `ai/workflow_ops/llm_client.py` | Default model param (×2) + added Gemini pricing |
| `ai/cost_log.py` | Added `gemini-3-flash-preview` pricing entry |
| `ai/billing/core/cost_calculator.py` | Added Gemini Flash pricing entry |
| `ai/cryo_em_knowledge/rag_index.py` | Model string (dead code path, always falls to mock) |

### Frontend TypeScript

| File | Change |
|------|--------|
| `server/routes.ts` | 5 call sites: methods report, error analysis, session title, findings, `llm/classify`; added import |
| `server/galaxy-assistant.ts` | 6 call sites: session memory, inline data extraction, clarification question, domain inference, coverage check, session summary; import + `HAIKU_MODEL` constant + `toolRankingModel` default + comments |

## Model Selection

**`gemini-2.5-flash-lite`** was chosen as the replacement after testing:
- `gemini-3-flash-preview` — model name does not exist  
- `gemini-2.5-flash` / `gemini-2.5-flash-lite` — have thinking tokens that consume `max_output_tokens` budget; use `max_tokens≥1024` to ensure complete responses
- `gemini-2.0-flash` / `gemini-2.0-flash-lite` — available but rate-limited in free tier

`gemini-2.5-flash-lite` is selected as the default: capable, fast, and produces complete responses at `max_tokens=1024`.

## Pricing

| Model | Input (per 1M tok) | Output (per 1M tok) |
|-------|-------------------|---------------------|
| `claude-haiku-4-5-20251001` | $0.25 | $1.25 |
| `gemini-2.5-flash-lite` | $0.075 | $0.30 |

~3–4× cheaper per call for the same lightweight tasks.

## Call Pattern

### Python
```python
from galaxy.ai.gemini_flash import call_gemini_flash

text = call_gemini_flash(
    messages=[{"role": "user", "content": prompt}],
    system="You are ...",
    max_tokens=512,
    temperature=0.0,
    json_mode=True,  # sets response_mime_type = application/json
)
```

### TypeScript
```typescript
import { callGeminiFlash } from './gemini-flash';

const text = await callGeminiFlash({
  messages: [{ role: 'user', content: prompt }],
  system: 'You are ...',
  maxTokens: 512,
  temperature: 0.0,
  jsonMode: true,
  signal: AbortSignal.timeout(15_000),
});
```

## What Was NOT Changed

- Main conversation model remains **Claude Sonnet 4.6** (`claude-sonnet-4-6`)
- Billing test fixtures in `billing/tests/` still reference haiku model string (tests billing logic, not inference)
- `model-test-harness.ts` — standalone comparison tool, kept for reference
- `workflow_ops/llm_client.py` pricing table retains historical haiku entries for backward compatibility
- `cost_log.py` retains haiku pricing entries for backward compatibility with any logged runs

## Verification

- `tsc --noEmit` clean on frontend
- `python -m py_compile` clean on all modified backend files
- `grep` scan confirms no remaining active `claude-haiku-*` model call sites in production paths
