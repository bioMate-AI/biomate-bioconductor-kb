# 2026-10-21 — Knowledge-utilization audit: evidence, DBs, and live-chat tool firing

Driven by the question "we have so many knowledge pieces — did BioMate waste
them?" Findings are verified against the live dev product, not inferred.

## 1. Citations — built but never surfaced (FIXED)
`_build_workflow_citations` builds real curated citations (tool_knowledge DB +
domain-landmark papers: DESeq2, GATK, cryoSPARC, AlphaFold…), but the after-run
Citations section was always empty because the route the frontend calls
(`/api/workflows/:name/citations`) proxied to a **non-existent** Galaxy path.
Fix: added `POST /api/ai_assistant/workflow_citations` (resolves workflow by
name, tolerant of the UI display-name vs DB-name mismatch) and pointed the
existing Node route at it. **Verified live:** a transcriptomics workflow now
returns DESeq2 (Love 2014), apeglm (Zhu 2019), clusterProfiler (Yu 2012) with
DOIs. (I also added a duplicate route by mistake, then removed it.)

## 2. WhyAnchor / WorkflowRationale — void, but NOT a data gap
Commented out (`chat-message.tsx:472`) and its test `describe.skip`. The void is
a **wiring/storage gap**, not missing knowledge: tool knowledge is well-populated
(83% of 12,312 tools have `scientific_context`, 64% have `citations`). The
rationale is computed (`_build_scientific_rationale_from_tools`) but not
persisted/emitted with a retrievable id → `/api/rationale/:id` returns nothing.
Same class as the citations bug; fixable by wiring the store/emit path.

## 3. The 60+ DB connectors + literature — DEAD in live chat (confabulated)
**Empirical probe** (`POST /api/chat/stream`, query: "Look up the Open Targets
genetic association score between TNF and rheumatoid arthritis, and search PubMed
… query the databases directly"):
- Stream = `ready → progress:intent → text deltas`. **Zero `tool_call` events.**
  No data-plane tool, no literature search, nothing reached a database.
- Yet the model's text said *"I'll query Open Targets and PubMed directly… Now
  querying PubMed…"* and produced an **"Open Targets genetic association score of
  0.98"** + specific PubMed findings — **fabricated, not retrieved.**

### Root cause (verified in code)
For a non-Claude backbone, `_processMessageInner` runs a provider fallback chain
(`galaxy-assistant.ts:8793-8848`): **only the Gemini branch attaches tools**, and
it is `available` only for `gemini-*` models. The live model `gpt-5.6-luna`
(OpenRouter → the OpenAI branch) therefore gets **no tools**, and line 8865 skips
the Claude agentic loop entirely. → all 60+ data-plane tools, literature search,
`run_code`, and MCP tools are structurally dead for the live model, and the gap
is masked by confabulation.

### Fixes
- **#2 integrity guard (DONE):** in the tool-less path, if the answer narrates a
  live DB/literature lookup (`/I'll query … Open Targets|PubMed|ChEMBL…/`),
  append + stream an honesty note that no live query ran and values are
  unverified. `galaxy-assistant.ts` ~8884. tsc + vitest green.
- **#1 real fix (SCOPED, not yet done):** give the OpenAI/OpenRouter path a
  real tool-calling loop (mirror the Gemini `functionDeclarations` loop in
  `_generateWithGemini`/`_processWithGeminiTools`), or route tool-eligible turns
  through a tool-capable backbone. This is the cure; the guard is the band-aid.

## Implication for demos
Any demo that shows BioMate "looking up a database" or citing evidence may depict
behavior the **live product fabricates** rather than performs. Reconcile the
m1-search-and-evidence / drug-dev evidence scenes against this.
