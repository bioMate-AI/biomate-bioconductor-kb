# Chinese-UI → BioMate Backend Safety Analysis

**Date:** 2026-09-23
**Scope:** Does Chinese-language user input (via the i18n UI) degrade or break BioMate's backend execution?
**Verified out of scope (given, not re-checked):** the frontend i18n is display-only — `t()` (`frontend/client/src/lib/i18n.ts`) wraps only display strings; example chips send an English `query`; the chat sends `message: content` (raw user text) to `/api/chat/stream`. The only Chinese that reaches the backend is text a user **types** in chat.

---

## Verdict

**Chinese UI does NOT corrupt workflow execution, but it does degrade input-quality on typed Chinese and leaves an output-localization gap.**

Execution safety holds: every extracted parameter value passes through a schema guardrail (`_validate_extracted_params`, `ai_assistant.py:1476-1564`) that drops or canonicalizes any value not in the workflow schema's `allowed_values` (or the genome/strandedness canonical maps) before it can become a Nextflow param. Chinese free-text cannot leak into a typed/enum param — it is dropped, not passed through. There is no crash path: the FTS tokenizer strips CJK and falls back gracefully; the LLM extraction path returns `[]` on any failure. So a Chinese user gets a runnable, canonical workflow.

What *does* degrade: (1) the entire **rule-based (deterministic) inference layer is English-regex-keyed** (`_rule_based_param_inference`, `ai_assistant.py:1567-1930+`), so Chinese phrasings like "人类" (human), "单端" (single-end), "去除线粒体" (remove mito), "100纳秒" (100 ns) match **nothing** — the deterministic pre-fill silently produces zero results and the system leans entirely on the LLM (which handles Chinese, but loses the zero-cost, exact, testable determinism the CLAUDE.md hybrid rule-first design depends on). (2) **Workflow routing** uses an English-only embedding model (`BAAI/bge-small-en-v1.5`) plus FTS5 that strips CJK, plus a 200+ entry **English keyword-weight table** — so a pure-Chinese query routes materially worse. (3) **Output localization gap**: the LLM system prompts contain *no* language directive, so the model mirrors the input language (Chinese in → Chinese out) — good — but DB-sourced workflow names/domains/descriptions and are rendered raw (never through `t()`), so a Chinese user sees a Chinese AI narrative wrapped around English workflow names and an English UI chrome. Cosmetic, not an execution bug.

---

## Issues Table

| ID | Description | Severity | Evidence (file:line) | Trigger |
|----|-------------|----------|----------------------|---------|
| C-1 | Rule-based param inference is 100% English regex on `user_intent.lower()`. Organism→genome ("human"→GRCh38), strandedness kit maps, negation ("remove mito"→keep_mito=false), single/paired-end, WES/UMI/peak/region, unit conversion (ns/fs→n_steps/dt). None match Chinese. | degradation | `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py:1567` (fn), `:1574` (`text = user_intent.lower()`), genome patterns `:1579-1607`, strandedness `:1609-1662`, unit-conv `:1680-1708`, coverage `:1710-1716`, negation `:1718-1723`, single/paired-end `:1725-1737`, WES `:1739-1742`, tools `:1744-1751`, aligner `:1753-1758`, peak `:1760-1769`, region `:1771-1775`, UMI `:1777+` | User types params in Chinese, e.g. "对人类样本做RNA-seq，单端测序，去除线粒体，模拟100纳秒" — deterministic layer extracts nothing; falls through to LLM only. |
| C-2 | Genome/strandedness canonical alias maps in the guardrail are English-only. "human/mouse/rat/yeast" etc. normalize; "人类/小鼠/大鼠/酵母" do not → dropped. | degradation | `ai_assistant.py:1499-1523` (`_genome_canonical`, `_strand_canonical`) | LLM extracts `genome="人类"`; guardrail can't map it → **dropped** (`:1535`). Safe (no bad value) but the param goes unfilled. |
| C-3 | Workflow routing embedding model is English-only (`BAAI/bge-small-en-v1.5`). Chinese query embeds poorly → worse dense ranking. Chain search uses `all-MiniLM-L6-v2` (also English). | degradation | `backend/lib/galaxy/ai/unified_workflow_search.py:87` (bge-small-en), `:38` (all-MiniLM), `backend/lib/galaxy/ai/vector_search.py:92` (bge-small-en) | Any Chinese-only intent → dense prefilter/rank operates on a language the model wasn't trained for. |
| C-4 | FTS5 query builder strips all non-ASCII: `re.findall(r"[a-z0-9]+", query.lower())`. A pure-CJK query yields zero tokens → falls back to raw string (`return query`), which matches nothing in FTS. | degradation | `unified_workflow_search.py:1585` (regex), `:1610-1612` (empty→`return query` fallback) | Chinese-only query → FTS contributes 0 matches; routing relies solely on the (English) dense score. No crash. |
| C-5 | 200+ entry keyword-weight table (`'rna-seq':3.0`, `'variant':3.0`, `'admet':3.0`, `'docking':3.0`, …) is English-only; substring-matched on the lowercased query. Chinese domain terms score 0 keyword weight. | degradation | `unified_workflow_search.py:356-556` (weights), applied `:1710-1817` | Chinese intent gets no keyword boost → correct workflow may rank below a spurious dense hit. |
| C-6 | Output localization gap: workflow name/domain/description come from the (English) DB and are rendered raw in the viewer — never through `t()`. | cosmetic | render: `frontend/client/src/components/nextflow-workflow-viewer.tsx:1865` (`workflow_name: workflowDefinition?.name`), domain `:1470`; source `backend/.../ai_assistant.py` `workflow_ga.name/domain/description` | Chinese UI + any workflow → panel shows English workflow name/domain amid Chinese chrome. |
| C-7 | No language/locale hint reaches the backend. `/api/chat/stream` reads only `{ message, context }`; the assistant system prompts carry **no** language directive. LLM mirrors input language (Chinese in → Chinese out) by default — not deterministically controlled. | cosmetic (mostly desirable) | route body `frontend/server/routes.ts:5680` (`const { message, context } = req.body`); prompts with no lang rule: `frontend/server/galaxy-assistant.ts:2662-2664` (research/general), `:8178-8255` (research), `:8256+` (workflow) | User types Chinese → AI narrative/findings return in Chinese (relies on model behavior, not enforced). English typed → English out. No override to force UI language. |
| C-8 | Partial, ad-hoc Chinese support already exists for Interactive-Tool launch detection only (启动/打开/jupyter/交互工具), proving the codebase can localize intent — but it's a one-off, not a general layer. | (context) | `frontend/server/galaxy-assistant.ts:3452-3469` | "帮我启动一个交互工具" correctly launches Jupyter. Nothing analogous for workflow params/routing. |

**No crash-severity issue found.** Both the FTS fallback (C-4) and the LLM extraction path (`ai_assistant.py:2869-2871`, returns `[]` on any exception) fail safe.

---

## Execution-safety confirmation (the key question)

The value guardrail is the safety net and it is sound:

- `_validate_extracted_params(extracted, all_params)` runs as the **last step** of every extraction (`ai_assistant.py:2081-2083`, called from the merged rule+LLM result).
- For a param with schema `allowed_values`, an extracted value not in that set (case-insensitive) is **dropped with a warning**, never passed through (`:1548-1559`).
- `genome` and `strandedness` are always normalized via canonical maps; unrecognized values (including Chinese) are **dropped** (`:1529-1546`).
- `allowed_values` themselves are parsed from the workflow schema / pipe-separated comment options (`ai_assistant.py:1220-1274`), i.e. from English canonical enums.

Net: Chinese free-text can cause an *unfilled* param (which the prereq-validation surfaces to the user as "missing", `_build_prereq_validation`, `ai_assistant.py:2626-2648`), but it **cannot** become a garbage Nextflow param value. Execution integrity is preserved.

---

## Fix Plan (phased)

### (A) Input normalization — RECOMMENDED: detect-Chinese → translate-to-English for the rule/routing layer; keep the original for the LLM + display

Two options were considered:

- **Option A1 — add Chinese aliases to every rule table** (C-1, C-2, C-5). Rejected as the primary fix: the English rule surface is large and growing (organism maps, ~15 kit regexes, negation, unit conversion, ~200 keyword weights). Duplicating each into Chinese (and Japanese/etc. later) is high-maintenance, error-prone, and every new rule would need a parallel translation. It also can't fix the **embedding** model (C-3) at all.
- **Option A2 — normalize once at the boundary: detect CJK in `user_intent`; if present, produce an English-translated copy used ONLY for (a) `_rule_based_param_inference`, (b) `_build_fts_query`, (c) keyword-weight matching, and (d) the dense embedding. Keep the ORIGINAL Chinese text for the LLM param-extractor and for the chat response.** RECOMMENDED.

**Rationale for A2:** it fixes C-1..C-5 with one component instead of N translated tables; it is the smaller, more testable change; it degrades gracefully (translation failure → today's behavior); and it aligns with CLAUDE.md's "rule-based inference first, LLM fallback" principle by *restoring* the deterministic layer for Chinese rather than abandoning it. The rule layer stays exact and English-keyed (its strength); we just feed it English.

- **What to change:** add a `normalize_query_for_rules(text) -> str` helper (detect CJK via a Unicode-range check; translate via the existing resilient `LLMClient` fast model, cached). Route its output into the four English-only consumers; leave the LLM extractor and response prompt on the original text.
- **Files:** new helper + call sites in `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py` (before `_rule_based_param_inference` at the `extract_params` caller) and `backend/lib/galaxy/ai/unified_workflow_search.py` (`search()` before `_dense_workflow_prefilter` and `_build_fts_query`).
- **Effort:** ~1 day (helper + wiring + unit tests: "对人类样本…单端…去除线粒体…100纳秒" must yield `genome=GRCh38, single_end=true, keep_mito=false, n_steps=…`).
- **Risk:** medium. Translation adds latency (mitigate: only when CJK detected; cache; fast model) and could mistranslate a gene/SMILES token — mitigate by keeping identifiers (already handled by the LLM path on the *original* text, and by C-3-safe: never send the translated copy to the LLM extractor).
- **Cheaper complement (optional):** for the highest-frequency terms, also add a small static Chinese→English token map (人类→human, 小鼠→mouse, 单端→single-end, 双端→paired-end, 去除→remove) as a pre-pass so common cases don't even need the translation call. This is C-1/C-2/C-5 relief with zero LLM cost; layer it under A2, not instead of it.

### (B) Output localization — pass a `uiLanguage` hint + a display-name map

- **B1 — language directive:** thread the client's active i18n language into the chat request and into the assistant system prompts. Frontend already knows it (`i18n.ts:905-910`, stored preference → navigator.language). Add `context.uiLanguage` in the chat POST body and inject `"Respond in <language>."` into the system prompts (`galaxy-assistant.ts:2662`, `:8178`, `:8256`). This makes Chinese output **deterministic** instead of relying on the model mirroring input (C-7).
  - Files: `frontend/client/src/components/chat-with-artifacts.tsx` (add `uiLanguage` to the POST context), `frontend/server/routes.ts:5680` (read it), `frontend/server/galaxy-assistant.ts` (inject into the 3 prompts).
  - Effort: ~0.5 day. Risk: low.
- **B2 — workflow display-name map (optional):** DB names/domains are English (C-6). If a localized panel is desired, add a `t()`-backed display map keyed by canonical workflow name/domain for the viewer (`nextflow-workflow-viewer.tsx:1865`, `:1470`), falling back to the English name. Do **not** translate the underlying value used for execution.
  - Effort: ~0.5–1 day for the common workflows/domains. Risk: low (display-only; execution untouched).

### (C) Execution-safety hardening — no gap to close, add regression coverage

The guardrail already prevents Chinese leakage into params. The only hardening is defensive:

- **C-fix:** add a unit test asserting `_validate_extracted_params` drops a Chinese `genome`/`strandedness`/enum value and an integration test asserting a Chinese-typed workflow request yields either canonical params or an unfilled-required prompt — never a non-canonical Nextflow param. Guards against a future edit that bypasses the guardrail.
  - File: `backend/tests/` (new test alongside existing param-extraction tests).
  - Effort: ~0.5 day. Risk: none.

**Suggested order:** C (cheap regression lock) → B1 (deterministic Chinese output, highest user-visible win, low risk) → A2 (restores deterministic Chinese input quality) → B2 (polish).

---

## Five-bullet summary of issues found

- **No execution corruption / no crash:** the schema guardrail (`_validate_extracted_params`, `ai_assistant.py:1476-1564`, called `:2081-2083`) drops any Chinese value not in the workflow's `allowed_values`/canonical maps, so Chinese free-text can never become a Nextflow param — it fails safe as an *unfilled* param, and the FTS/LLM paths fall back gracefully.
- **Rule-based inference is entirely English-regex-keyed** (`ai_assistant.py:1567-1930+`, on `user_intent.lower()`): Chinese "人类/单端/去除线粒体/100纳秒" match nothing, so the deterministic pre-fill (the exact, zero-cost layer CLAUDE.md relies on) silently no-ops for Chinese and the system leans wholly on the LLM.
- **Workflow routing degrades on Chinese:** English-only embedding model `BAAI/bge-small-en-v1.5` (`unified_workflow_search.py:87`, `vector_search.py:92`), FTS5 tokenizer that strips all CJK (`unified_workflow_search.py:1585`, empty→raw fallback `:1610-1612`), and a 200+ entry English keyword-weight table (`:356-556`) — a pure-Chinese query routes materially worse but does not error.
- **Output-localization gap (cosmetic):** DB-sourced workflow name/domain/description render raw, never via `t()` (`nextflow-workflow-viewer.tsx:1865`, `:1470`); combined with the language-neutral system prompts (`galaxy-assistant.ts:2662-2664`, `:8178+`) the user sees a Chinese AI narrative around English workflow names + English chrome.
- **No language hint reaches the backend** (`routes.ts:5680` reads only `{message, context}`; no `uiLanguage`): Chinese output today depends on the LLM mirroring input language rather than an enforced directive — reliable-ish but not deterministic (recommended fix: thread `uiLanguage` into the 3 system prompts).

**Doc path:** `/Users/kky/biomate-review/docs/20260923_CHINESE_UI_BACKEND_SAFETY.md`
