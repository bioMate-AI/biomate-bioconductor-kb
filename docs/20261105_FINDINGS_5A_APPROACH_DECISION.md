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

## 2026-11-05 LIVE PROBE — corrects the emphasis above (the timeout is necessary, NOT the cure)
Probed dev directly (fixture login) on the CAR-T run `dc9f3235` (`in_vivo_cart_codesign`,
status completed, 11 outputs). The findings endpoint reached **`status: ready` quickly — no
hang** — yet returned the **raw output samples** (`cart_construct.fasta → {filename, content}`,
`design_report.txt`, `fratricide_check.json`, …) with **no `summary` and no `key_results`**. So
for this run the timeout is irrelevant; it never reached the LLM path.

Root cause for THIS class = the S3 sidecar read path (`routes.ts` ~15660-15665):
```js
const structured = await dataResp.json();
return res.json({ ...structured, status: 'ready', runId, reportUrl });
```
It trusts whatever `findings_data.json` holds and stamps `status: 'ready'` **without validating
the shape**. CAR-T's sidecar contains echoed output samples, not a findings object → "ready but
empty". (Early polls also showed shape inconsistency across workers — in-memory `_findingsCache`
is per-worker — but the dominant, stable behaviour is the bad S3 sidecar.)

**Three independent long-tail failure modes (not one):**
- **A. Poisoned/mis-shaped sidecar, trusted un-validated** → `ready` + empty. DOMINANT for
  CAR-T; NOT previously scoped. Fix: (i) on the sidecar read, require a findings shape
  (`summary` or non-empty `key_results`) before returning `ready`; if it fails, ignore the
  sidecar and regenerate (or mark unavailable) — never stamp `ready` over non-findings JSON;
  (ii) find + stop whatever wrote output samples into `findings_data.json` (audit every
  `persistFindingsSidecar` caller and the Python analyzer path A).
- **B. Unbounded LLM fetch → hang → `pending` forever.** The shipped 90s race (commit
  3995fc1b2) fixes this; verified at source that the backend fetch in `llm-client.ts:93` has
  no `signal` and the module has zero timeout handling. Real, but only bites runs with NO
  sidecar that actually reach the LLM.
- **C. Guardrail emptying + sampling** (bugs 2/3 above) — only reachable once A and B are
  past and the LLM actually returns JSON.

**Corrected takeaway:** a timeout does not make findings appear — it only bounds the wait and
triggers recovery. Producing real findings for the long tail requires, in priority order:
A (validate/repair the sidecar) → B (bound the LLM, done) → C (guardrail/sampling). The #5a
decision (hybrid; invest in the generic path, parsers only for gate numbers) stands; the work
is A→B→C, not writing per-domain parsers.

## Fix A — SHIPPED (read-side sidecar/cache shape validation)
**Writer audit first:** both CURRENT writers of `findings_data.json` are well-shaped — Node
`persistFindingsSidecar` writes the real findings object, and the Python analyze-outputs path
(`nextflow_executor.py:12481`) always emits `structured_payload` with `summary`/`key_results`
keys. Neither produces the filename-keyed samples map, so CAR-T's bad sidecar is a **historical
artifact** from an older code version. No writer change is needed: read-side validation +
regeneration is **self-healing** (a reopen rejects the stale sidecar, regenerates, and
`persistFindingsSidecar` overwrites it with a well-shaped payload).

**Change (`routes.ts`, `GET /api/workflows/runs/:id/findings`):** added `isFindingsShaped(o)` and
gated all three "ready" return sites — local sidecar (2a), S3 sidecar (2b), in-memory cache (3).
A payload is trusted only if it has `summary:string` OR `key_results:array` OR a
`findings_document` object OR `reportMd:string`; otherwise it's logged and ignored, and control
falls through to regeneration. **Loop-safe:** the check accepts a well-formed-but-EMPTY result
(summary `""`, key_results `[]`) — only a payload with no findings field at all (the samples
map) is rejected, so a legitimately low-signal run is not re-generated forever.

Gate: `tsc` clean; full `vitest run` 2177 passed / 42 skipped / 0 failed.
Live check: reopen CAR-T `dc9f3235` on dev after sync — it must stop returning the filename-keyed
samples map as `ready` and instead regenerate (real summary, or a non-empty "unavailable" note).

## Fix C — SHIPPED (guardrail transparency + sampling coverage)
Two changes in `runAsync` (`routes.ts`):
- **C-1 guardrail transparency** — when the numeric grounding guardrail drops key_results
  (values whose numbers aren't verbatim in the sampled files), add a caveat stating how many
  were withheld (and, when it empties the list, that all were withheld — "open the Outputs
  tab"). **Never re-admits the dropped unverified numbers** — grounding is unchanged; only the
  silent-empty failure mode is fixed, so a run whose result numbers the sampler missed no longer
  looks like it produced nothing.
- **C-2 sampling coverage** — the few files actually read are now **ranked** (report/summary/
  result/structured/`toxic`/`qc` first; Nextflow bookkeeping sunk) before the cap, instead of a
  raw slice that could sample logs and miss the results. Cap raised 6→8 so the proven ADMET/DE
  **deterministic-parser** path (which reads the same `outputSamples`) can never lose its target
  file; initial scan widened 30→40 candidates. Read budget stays bounded (8 files × 8000 chars).

Gate: `tsc` clean; full `vitest run` 2177 passed / 42 skipped / 0 failed.

## 2026-11-05 POST-SYNC LIVE PROBE — the REAL long-tail blocker (not A/B/C)
Synced A+B+C to dev and probed CAR-T `dc9f3235` live. Result: it stopped returning the
samples map (fix A working) but sat on `pending` forever. Dev frontend logs
(`docker logs biomate-dev-frontend`) gave the actual cause:
```
[Findings] llm returned: length=5550 firstChar="[" ... preview="[ { \"filename\": \"phaseA_summary.txt\", \"content\": \"Phase A — Atlas Safety Check...\" } ]"
[Findings] persisted sidecar s3://.../findings_data.json
[Findings] dropping non-findings cache for dc9f3235 (keys: 0,1,2,3,4,5)
```
**The LLM ignores the findings prompt and returns a JSON ARRAY that echoes the input files**
(`[{filename, content}, …]`). It's valid JSON, so `JSON.parse` succeeded and the parse branch
cached + persisted the ARRAY as "findings" — no `summary`/`key_results`. Post fix A, the read
path then (correctly) rejects it as non-findings → regenerate → the model echoes again →
**infinite loop → perpetual `pending`.** ADMET avoids all of this via the deterministic parser
(verified live: real summary + 9 key_results). So the long-tail blocker was never the hang or
the sidecar trust — it was **LLM response non-adherence with no shape gate in the generate path.**

### Fix D — SHIPPED (response-contract gate + convergence)
`routes.ts` `runAsync`:
1. **Shape gate on the primary LLM parse** — after JSON.parse + unwrap, if the result isn't
   `isFindingsShaped` (e.g. an array/echo), throw → fall to the Claude fallback instead of
   caching garbage.
2. **Same gate on the Claude fallback** — a non-findings Claude response throws to the
   "unavailable" note rather than caching garbage.
3. **Persist the fallback note** — both the Claude-failed and outer-catch minimal summaries now
   call `persistFindingsSidecar`, so the stale garbage S3 sidecar gets overwritten with a
   findings-shaped payload and cross-worker reads CONVERGE (no more regenerate-forever).
4. **Prompt hardening** — SYSTEM now demands a single JSON OBJECT, never an array, and never
   echoing/re-serializing the inputs.

Net: a non-parser run now converges to EITHER real findings (if the model adheres — Claude
fallback adheres better than the dev primary) OR a clean, non-empty "AI synthesis unavailable —
see Outputs" note. Never the echoed-array garbage, never perpetual pending.

## 2026-11-05 POST-FIX-D PROBE — converges, but to the "unavailable" note (not real findings yet)
Synced D and re-probed CAR-T: poll 1 `pending`, then **stable `ready`** across 7 polls with a
non-empty summary + 1 caveat ("AI synthesis was unavailable… see Outputs"), no samples-map, no
loop. **The pipeline now converges** — no garbage, no hang, no perpetual pending. BUT it landed
on the fallback note, not real findings. Dev logs showed why:
```
[Findings] Gemini JSON parse failed: findings LLM returned non-findings JSON (array — likely echoed inputs) — retrying with Claude
[Findings] Claude fallback also failed: 401 {"type":"authentication_error","message":"invalid x-api-key"}
```
Primary model echoes the inputs (fix D rejects it) → Claude fallback **401s** → clean note.

### Fix E — SHIPPED (Claude fallback used the wrong API key)
The fallback built its Anthropic client from the outer `apiKey` cascade
(`GEMINI || GOOGLE || ANTHROPIC || …`), which is only meant to gate "is any LLM configured".
On dev `GEMINI_API_KEY` wins, so the Anthropic SDK got a Gemini key → `401 invalid x-api-key` →
the adherent fallback never ran. Fix: authenticate with `process.env.ANTHROPIC_API_KEY`
specifically; when absent (and not on the local shim), skip to the clean note instead of a
doomed 401. (`routes.ts`; tsc + full vitest green.)

### The one unknown I could not verify
Whether fix E yields REAL findings for the long tail on dev depends on dev having a valid
`ANTHROPIC_API_KEY`. The auto-mode classifier blocked reading dev env (Credential
Materialization), so this is unconfirmed. Two outcomes after E deploys:
- dev HAS an Anthropic key → Claude Haiku runs, adheres, produces real findings. ✓ long tail solved.
- dev has NO Anthropic key → fallback cleanly skips → the "unavailable" note persists (no 401,
  faster). Then real long-tail findings need either an Anthropic key on dev OR an adherent model
  in the backend chain (`llm_providers.yml`) whose findings output is a JSON object, not an
  echoed array. That's an infra/config decision, not more app code.

## Status: A, B, C, D, E all shipped on the branch
All three long-tail findings failure modes are addressed in code:
- **A** — sidecar/cache shape validation (commit c3096f51a).
- **B** — 90s bound on the generic LLM call (commit 3995fc1b2).
- **C** — guardrail transparency + sampling ranking (this commit).

Remaining is **live verification after sync to dev**, not more code: reopen non-parser runs
(CAR-T `dc9f3235`, clinical, QSAR) and confirm findings resolve to a real summary — or a
non-empty, self-explaining caveat — instead of hanging, echoing samples, or silently emptying.
If findings still come back thin, the next lever is prompt/schema tuning per domain, NOT
per-domain parsers (the #5a decision holds).
