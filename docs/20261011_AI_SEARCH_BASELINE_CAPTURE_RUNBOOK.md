# AI-search baseline — capture runbook (operator-run)

Operational checklist for running the five-provider consumer AI-search baseline yourself. This is the step the model cannot do unattended (it needs your sign-ins and Grok's terms acceptance). The model prepared this runbook and will **score the archived answers afterward** — you only capture.

Companion docs: strategy + fixed prompts in [20261009_AI_SEARCH_VISIBILITY_STRATEGY.md](20261009_AI_SEARCH_VISIBILITY_STRATEGY.md); schema + scoring and what "mention/citation/capability" mean in [20261009_AI_SEARCH_BASELINE_AND_CLAIM_RECONCILIATION.md](20261009_AI_SEARCH_BASELINE_AND_CLAIM_RECONCILIATION.md).

## What you're measuring
Whether the five consumer products **discover, describe, and cite** BioMate correctly. 24 fixed prompts × 5 providers. A full round is 3 repeats = 360 answers; **start with 1 repeat (120 answers) labeled preliminary** — that is enough for a first read and keeps the manual load sane.

- Providers: ChatGPT, Claude, Gemini, Grok, Perplexity (consumer apps, not APIs).
- Prompt set: `node scripts/ai_search_baseline.cjs plan` prints all 24 with ids + categories (4 branded, 8 task, 4 comparison, 4 evidence, 4 Chinese). **Use them verbatim** — do not paraphrase, and never add "BioMate" to a non-branded (task/comparison) prompt; that measures brand lookup, not discovery.

## Pre-flight (once)
- [ ] Sign in to each provider's consumer app. For **Grok**, you must accept its Terms on first message — do that yourself.
- [ ] Turn **web search ON** in each app (ChatGPT: Web search; Gemini/Claude/Perplexity: default; Grok: web search tool). The point is retrieval, not the base model's memory.
- [ ] Prefer a **fresh/temporary chat per prompt** so prior turns don't leak. Note: a ChatGPT temporary chat can still use memory/custom instructions — record that in `accountContext`, don't claim a clean-account baseline.
- [ ] Pick the archive dir: `docs/qa/ai-search/` (already exists). Round file: `docs/qa/ai-search/20261011-observations.jsonl`.

## Per-prompt procedure (repeat for each of the 24 × 5)
1. Open a fresh chat, confirm web search is on, paste the exact prompt.
2. Wait for the full answer. **Note whether search actually ran** (visible "Searching…", source chips/links). If you can't tell, `searchRan` is `null` — do not guess.
3. **Archive the answer**: save the rendered answer text + the list of cited source URLs to
   `docs/qa/ai-search/20261011-<provider>-p<NN>-r<R>.txt` (zero-pad id, e.g. `…-chatgpt-p05-r1.txt`). Paste the citation URLs at the bottom of that file too.
4. **Append one JSONL record** to the round file (template below). One line per cell.
5. Never archive account tokens, cookies, or credentials.

### Record template (one line per cell — fill the CAPS fields)
```json
{"provider":"ChatGPT","interface":"consumer","promptId":1,"repeat":1,"status":"completed","model":"DISPLAYED MODEL LABEL","mode":"web search on; temporary chat","language":"en","region":"US","accountContext":"signed-in <tier>; memory/custom-instructions state","capturedAt":"2026-10-11T00:00:00Z","answerPath":"/Users/kky/biomate-review/docs/qa/ai-search/20261011-chatgpt-p01-r1.txt","searchRan":true,"citations":["https://…"],"review":{"reviewer":"YOU","mentionsBioMate":null,"capabilityAccurate":null,"citationsSupportClaims":null}}
```
- `status`: `completed` (got a real answer), `error` (service error / sign-up wall — give a `reason`, no scored review), or `not_run` (skipped — give a `reason`).
- `searchRan`: `true` / `false` / `null` (unknown). Leave review judgments `null` if you want the model to score them.
- Leave `citations` `[]` if none shown. A homepage link alone is **not** scientific evidence.

### Reviewer rubric (fill now, or leave null for the model to score from the archive)
- `mentionsBioMate`: does the answer name BioMate at all?
- `capabilityAccurate`: are its statements consistent with the current site/evidence? Flag over-claims (e.g. "SOC 2 certified" when the site says "aligned to SOC 2"; presenting cyclic-peptide work as a validated product).
- `citationsSupportClaims`: does the cited page actually back the statement it's attached to?

## After capture
```
node scripts/ai_search_baseline.cjs summarize docs/qa/ai-search/20261011-observations.jsonl
```
It rejects duplicate cells, missing/empty archives, and invalid records; separates branded vs non-branded and consumer vs API; and reports **explicit counts, not zeros for untested cells**. Report branded and non-branded rates separately with denominators shown.

## Hand back to the model
Tell the model the round file path (and the archive dir). It will:
- validate integrity via `summarize`,
- fill any `null` review judgments by reading each archived answer against the evidence registry,
- classify any absent answers by stage (no search / not retrieved / retrieved-not-cited / wrong identity / obsolete / insufficient evidence), and
- write the scored results into the baseline doc with per-category rates.

## Guardrails
- Don't convert untested/error cells into zeros — missing ≠ zero visibility.
- Don't infer an unseen retrieval failure; retrieval-stage labels require visible search traces.
- Don't manufacture engagement/posts to influence results. This runbook authorizes capture only — no paid API runs, no account creation beyond your own sign-ins, no server/WAF/DNS changes.
