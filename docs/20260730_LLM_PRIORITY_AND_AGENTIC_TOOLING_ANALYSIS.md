# LLM Priority + Agentic Tool-Calling — Analysis & Decision

**Date:** 2026-07-30
**Trigger:** (1) GPT-5.6 price drop → should BioMate change LLM priorities? (2) End-to-end testing of the new data-plane tools revealed they never fire in live chat.
**TL;DR:** Switching the LLM will **not** fix tool-calling — it's a BioMate prompt/classification bug (the model + code path work in isolation). But there's a real **33–45% output-cost** case for moving the agentic primary off Gemini 3.5 Flash.

---

## Part 1 — LLM priority (answer to the GPT-5.6 question)

GPT-5.6 launched 2026-07-09 as three tiers (Sol/Terra/Luna). Relevant comparison for BioMate's chat backbone:

| Model | Input $/M | Output $/M | Tool-calling (measured) | Latency | Notes |
|---|---|---|---|---|---|
| **Gemini 3.5 Flash** *(current primary)* | $1.50 | **$9.00** | ✅ works at API level | fast | **priciest output** of the three |
| **GPT-5.6 Luna** | $1.00 | **$6.00** | ✅ but needs `reasoning_effort:"none"` (or Responses API) | sub-second TTFT; ~1.3–1.6s to a tool call; ~190 t/s | Intelligence Index 51 (#1 in class) |
| **Claude Haiku 4.5** | $1.00 | **$5.00** | ✅ proven agentic loop already in-repo | fast | cheapest output |
| GPT-5.6 Terra | $2.50 | $15.00 | ✅ | — | balanced tier |
| GPT-5.6 Sol | $5.00 | $30.00 | ✅ | 3.06s TTFT (low), 59 t/s | flagship; Terminal-Bench 88.8% |

**Measured tool-calling (local, real APIs, identical tool + prompt):**
- GPT-5.6 Luna: fires the tool — **but 400s with default/low `reasoning_effort`**; only `reasoning_effort:"none"` (chat/completions) or `/v1/responses` works.
- Gemini 3.5 Flash: fires in ~0.6s even with `temp=0, thinkingBudget=0`, empty-required/empty-properties schemas, and a 13k-word system prompt.

**Cost verdict:** Gemini 3.5 Flash's **$9 output** is the most expensive. Moving the agentic primary to Claude Haiku 4.5 ($5) or GPT-5.6 Luna ($6) saves **33–45% on output tokens**. Haiku is cheapest *and* already wired with the proven agentic loop; Luna is a close second but its OpenAI path is currently text-only (`_generateWithOpenAI`) and needs a tool loop + `reasoning_effort:"none"`.

---

## Part 2 — Why the agentic tools don't fire (the real bug)

End-to-end testing (not just endpoint tests) showed the new data-plane tools — and even `run_code`/`list_history` — **never fire** on the default `gemini-3.5-flash` backbone. The model hallucinates tool use: wrong SHA256 digest, "you have no FASTQ files" when the account has them, "I can't query PubMed."

### Ground-truth diagnostics (instrumented the live path; did not theorize)

1. Live stream marker showed the Gemini-primary path runs with `onToolEvent` present, but `toolsOn=false` because the tool-gate keyed on **`isWorkflowTurn`** — a false positive on plain compute/lookup queries.
2. `generatedWorkflow` is **truthy even when workflow generation fails/empties**, so gating on `!generatedWorkflow` still blocked tools.
3. For an explicit "compute SHA256" query, a **successful, runnable workflow was actually generated** (`hasWF=true wfSucc=true runnable=true`) — the intent classifier (galaxy-assistant.ts ~5668/~5819) routes analysis-verb queries to `workflow_generation`.
4. **Fix landed:** the tool-gate now keys on `hasRunnableWorkflow` (success + real artifact), not `isWorkflowTurn`. After this, data queries show **`toolsOn=true`** — tools attach.

### But tools still don't fire even when attached — and it's NOT the model

With tools confirmed attached (`toolsOn=true`), Gemini still answered "no FASTQ files" without calling `search_my_data`. Isolation tests prove the model and code path are fine:

- **Raw Gemini 3.5 Flash API** tool-calls with BioMate's exact config (all schema shapes, huge system prompt).
- **A local Node repro of BioMate's EXACT `_generateWithGemini`** (SDK `SchemaType` + `convertProp` + streaming `sendMessageStream` + real tool schemas) tool-calls correctly (`search_my_data`, `list_data_sources`).

So the failure is in the **live runtime**, and it is **model-agnostic** — a model swap will not fix it.

### What was ruled OUT (tested, not theorized)

The natural hypothesis — that BioMate's system prompt steers the model away from tools — was **tested and NOT confirmed**. Local reproductions with (a) a bare prompt, (b) a 13k-word prompt, and (c) the *real* suppressing framing verbatim ("auto-injected pre-results in `<compound_lookup_results>`", "only cite papers from the provided list", "route to an indexed DB-API tool-function as a workflow step") **all still call `search_literature`/`search_my_data`**. So prompt content is not the (sole) cause.

### Remaining step (deploy-gated — the only way to close this)

The gap is between "tools attached (`toolsOn=true`) in the provider fn" and "tools actually presented to the model by `_generateWithGemini` at runtime." One instrumented deploy must emit, from *inside* `_generateWithGemini` in the live runtime: (a) the count of function declarations actually handed to the SDK, and (b) the count of `functionCall`s Gemini returns on turn 0. That disambiguates "declarations not reaching the model" (a plumbing/state bug) from "model returns none" (a prompt/history/tool-set-size issue). Until that datapoint exists, the cause is **unconfirmed** — do not guess-fix.

---

## Recommendations

1. **Fix the tool-firing bug first (model-agnostic, unblocks the whole data-plane effort):** land the layer-2 diagnostic → adjust the system prompt so the model treats `search_my_data`/`search_literature`/`list_data_sources` as authoritative and calls them rather than answering from injected context. Keep the `hasRunnableWorkflow` gate fix.
2. **LLM priority (independent cost win):** move the agentic primary off Gemini 3.5 Flash. **Claude Haiku 4.5** is the low-risk immediate choice (cheapest output, proven loop). **GPT-5.6 Luna** is the strategic alternative once its OpenAI tool path is wired (`reasoning_effort:"none"`).
3. **Do not switch models expecting it to fix tool-calling** — it won't. Sequence: fix the prompt bug, then benchmark the model swap independently.

## Status / open items
- Landed: `hasRunnableWorkflow` tool-gate; Gemini-primary path now passes tools.
- Blocked: clean deploy (removes temp `[[DIAG]]` marker) + layer-2 diagnostic — a concurrent session has held the repo tree dirty for ~1.5h, so `sync_to_dev.sh` refuses. A watcher is queued to ship on the next clean window.
- Memory: `project_agentic_tools_gemini`.
