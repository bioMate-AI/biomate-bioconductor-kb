# #5a findings generation — approach decision + the hang fix

Date: 2026-11-05. Decides the open #5a item from `docs/20261104_DEEP_E2E_BUG_FIXSPEC.md`:
**per-domain parsers vs a generic LLM summarizer** for the ~13 non-parser workflow types
whose findings are currently empty or stuck pending.

## Decision
**Keep the hybrid; invest in the generic LLM summarizer. Do NOT write per-domain parsers
for the long tail.** The 4 existing deterministic parsers (`_parseAdmetOutput`,
`_parseDeseq2Output`, `_parseEnrichGoOutput`, `_parseRarediseaseOutput`) stay exactly where
they are — they feed **QC-gate numbers that must be exact**. Every other (interpretation-only)
domain is served by the generic LLM fallback, which already exists and already covers the
whole catalog — it just has concrete, bounded bugs.

### Why they are not rivals (the essential difference)
They are a division of labor, not two candidates for the same slot:
- **Deterministic parser** — exact, zero-cost, testable; the right source **only** when a
  number drives a QC gate or a safety verdict (ADMET hERG/DILI, DE padj, enrichment q-value).
  Cost: a bespoke extractor + tests per output schema, forever; silent breakage on schema drift.
  Does not scale to 36 domains / thousands of workflows.
- **Generic LLM summarizer** — one path, covers the entire catalog **and future workflows**,
  already built; non-deterministic, so it must be grounded (guardrails already present),
  bounded (timeout), and degrade gracefully. **Not** the place to source gate numbers.

The code is already hybrid: deterministic-first (`routes.ts` ~15915, returns and skips the LLM
when a parser matches), LLM-fallback after. The question was never "which one" — it is
"where does each belong," answered above.

### Effort
- Per-domain parsers for the remaining ~13 types: **heavy and perpetual** — weeks, then an
  ongoing tax; workflow #14 still wouldn't be covered.
- Fixing the generic path: **light and bounded** — three concrete bugs (below). Fixes 1+2
  make the long tail reliable in hours.

## Root cause (read from source, not inferred)
`GET /api/workflows/runs/:id/findings` → `runAsync()` (`routes.ts` ~15660+) generates findings
on-demand, caching in `_findingsCache`. After the deterministic-parser short-circuit it calls
an LLM. The provider split (~15969):
- **Gemini branch** (`callGeminiFlash`): bounded by `signal: AbortSignal.timeout(90_000)`.
- **Generic branch** (`llmGenerate`, the else — this is the dev path: GLM-5.3 via OpenRouter):
  passed **no** signal, and **`server/llm-client.ts` has zero timeout/abort handling** (grep:
  0 occurrences of `timeout|AbortSignal|signal`). So a slow/stalled provider made the `await`
  hang indefinitely → cache stuck on `{_generating:true}` → the endpoint returns `pending`
  forever → the UI shows "Analysis in progress…" with no recovery. **This is the #5a "stays
  pending" symptom.**

Separately, **"ready but empty"** (observed live on CAR-T `dc9f3235`) is a *different* cause:
the numeric guardrail (`routes.ts` ~16029-16037) drops every `key_result` whose numbers do not
appear verbatim in the sampled output files. For low-number / qualitative outputs (sequence
designs, FASTA, categorical results) this empties `key_results` even though the run succeeded.

## Fix shipped here (bug 1 — the hang)
`routes.ts`, the `llmGenerate` else-branch: wrap the call in `Promise.race` against a 90s
deadline (parity with the Gemini branch) inside a try/catch. On timeout/error, `rawText` stays
empty → the existing JSON-parse failure path fires the Claude (Haiku) short-context fallback →
worst case a **non-empty** "synthesis unavailable — see Outputs" summary. No more permanent
`_generating`. (The orphaned llmGenerate promise is harmless for this fire-and-forget path;
true cancellation would need an AbortSignal plumbed into `llm-client` — see follow-up.)

## Follow-up (bugs 2 and 3 — scoped, NOT shipped here)
2. **Guardrail emptying** — when the numeric guardrail would drop **all** `key_results`, keep
   the summary + any textual (non-numeric) results + an explicit "values unverified against
   output files" caveat, rather than emitting an empty card. **Never** by re-admitting
   unverified numbers — the guardrail's grounding purpose is correct; only its all-or-nothing
   failure mode is wrong. Needs a per-domain check that sampling actually included the
   number-bearing file (bug 3) before deciding a dropped number is a hallucination vs a
   sampling miss.
3. **Sampling + timing** — widen/curate which output files are sampled (the result-bearing
   file is sometimes absent from the sample), and optionally generate findings at run
   completion rather than only on first view, so the first open is never a cold `pending`.
4. **AbortSignal in `llm-client`** — add real timeout/abort support so the generic path can be
   truly cancelled (not just raced), and so other callers inherit the bound.

## Verification
- `tsc --noEmit` clean; full `vitest run` green (no regressions).
- Live check needed on dev: open findings for a non-parser workflow (clinical / CAR-T /
  QSAR) and confirm it resolves within ~90s to a real summary (or a non-empty "unavailable"
  note) instead of hanging on "Analysis in progress…".
