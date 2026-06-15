# Deterministic Chat Routing — Audit + Plan

**Date:** 2026-06-10
**Status:** Plan only — no code shipped yet. Awaiting review.
**Trigger:** the same chat query ("Run DESeq2 on the airway example dataset") sometimes returns a workflow card and sometimes responds *"Please upload the raw counts matrix"*. This affects real users, not just the e2e suite.

## TL;DR

BioMate's chat orchestrator already has most of the infrastructure for deterministic routing. The gap is narrow: the system prompt doesn't tell the LLM that `airway`, `pasilla`, `pbmc3k`, etc. are *canonical built-in datasets* — equivalent to how it already tells the LLM that SMILES strings are valid ADMET input and PDB ids are valid pocket-detection input. Adding a small registry + a short system-prompt rule + one few-shot example should take the recurring "ask for files" failure mode from ~30% of bioc queries to <5%.

## 1) Audit: what BioMate already has

| Mechanism | Where | What it does |
|---|---|---|
| **Clarification suppression regex** | `frontend/server/galaxy-assistant.ts:5457` | `/do not ask|no (further )?clarification|use (the )?provided|use default/i` — when the user message matches, the clarification gate is bypassed. This is why the test workaround "All parameters are provided — proceed directly" routes deterministically. |
| **Per-domain auto-resolve rules** | `galaxy-assistant.ts:650, 684, 3893` | System prompt explicitly tells the LLM `do NOT ask for a file upload` for: ADMET when SMILES is provided, pocket detection when a 4-letter PDB ID is provided, allometric scaling when species CL/Vd values are provided. The pattern works. |
| **"demo / example / synthetic data" exception** | `galaxy-assistant.ts:5689` | If the user uses the phrases "demo data", "example data", "use defaults", "synthetic data", "with defaults" etc., the chat generates the workflow card immediately. Works when the user spells it out. Doesn't fire on `airway` because the LLM doesn't know `airway` *is* an example dataset. |
| **Routing-LLM temperature = 0** | `galaxy-assistant.ts:1421, 1501, 1540, 4721, 5853` | All routing-decision LLM calls already use temperature 0. Sampling nondeterminism isn't the issue. |
| **`_clarificationGate()`** | `galaxy-assistant.ts:1999, 2580` | The clarification gate has structured exits and a regex-based override. Designed to be extended. |
| **Search-confidence machinery** | `galaxy-assistant.ts:323/332/941` | Search returns confidence scores per workflow candidate. Today they go *into* the LLM as ranked context, not as a *bypass* signal. |

## 2) Where the bug actually lives

For "Run DESeq2 on airway":

1. Routing-search returns `nf-core/differentialabundance` with confidence ~0.6–0.8 (decent match).
2. The LLM call assembles the workflow-generation response with the system prompt that says "ask for input data if missing".
3. The LLM looks at "airway" and — because nothing in the system prompt tells it `airway` is a valid resolved input — concludes a counts matrix is missing and asks for one.
4. The exception at line 5689 doesn't fire because the user didn't use the magic words "example data" or "demo".

The four per-domain auto-resolve rules (ADMET, pocket, allometric, demo-exception) are the proven design. The gap is just that *bioinformatics canonical fixtures* aren't enumerated like SMILES and PDB ids are.

## 3) Plan (ranked by impact ÷ effort)

### A. Canonical-fixture registry + system-prompt rule **[do first]**

- **Effort:** ~50 lines in `galaxy-assistant.ts` (data table + prompt section).
- **Win:** Eliminates the "ask for counts matrix when user named airway" failure mode for the top-50 most-mentioned datasets in production chat logs.

Plan:
- Add a structured array `CANONICAL_FIXTURES: { name, alias, workflowHint, paramName, paramValue }[]` in a new module `frontend/server/canonical-fixtures.ts`.
- Seed with: `airway`, `pasilla`, `iris`, `mtcars`, `pbmc3k`, `pbmc8k`, `pbmc10k`, `TCGA-*` accessions, `GSE\d+` accessions, `SRR\d+` accessions, nf-core `test` profiles for each pipeline, `airway` test for differentialabundance.
- Inject into the workflow-generation system prompt as a table (same shape as the ADMET-SMILES rule at line 650).
- Add the explicit forbidden response patterns: `"Please upload the raw counts matrix"`, `"I need the underlying dataset"`, `"Could you share the metadata CSV"` — must not appear in any reply where the user's message contains a fixture name.

### B. One few-shot example for the airway case **[do with A]**

- **Effort:** 5 lines in the prompt.
- **Win:** Few-shot examples consistently outperform abstract rules. A single `user: "Run DESeq2 on airway" → assistant: <workflow card with input=airway>` demo trains the LLM stronger than the rule alone.

### C. Wire the canonical-fixture registry into pre-LLM detection **[do after A+B are validated]**

- **Effort:** ~30 lines — add a regex pass before the LLM call. If `message.match(FIXTURE_REGEX)` and the routing-search top candidate has `confidence >= 0.7`, set `inlineParameters.dataset = matched_fixture`, suppress the clarification gate explicitly (don't rely on the LLM to honor the system-prompt rule).
- **Win:** Defense-in-depth. Even if the LLM ignores the prompt, the rule-based layer still routes correctly. Same belt-and-suspenders pattern as the existing PBPK-prereq gate that runs before `_clarificationGate()`.

### D. Confidence-based bypass for high-score routing **[medium-term]**

- **Effort:** ~80 lines + a feature flag.
- **Win:** When the search confidence is >= 0.85 *and* a single dominant candidate exists, skip the chatty LLM entirely and emit the workflow card from the search-result metadata. Removes both nondeterminism and the LLM cost for clear-intent cases. Adds risk: any pre-LLM-call enrichment (param prefill, context injection) needs to be ported.
- Defer until A+B+C have measured the residual nondeterminism rate.

### E. Test-only deterministic-routing toggle **[do NOT do]**

- **Effort:** small.
- **Why skip:** This is precisely the workaround pattern CLAUDE.md forbids. If the production system needs deterministic routing, the production system gets the fix — not a test escape hatch. A's structured fix makes the test naturally pass.

## 4) Local verification before any sync (per CLAUDE.md pre-sync checklist)

- `cd frontend && npx tsc --noEmit -p .` ✅ (passed for the test edit just now in 13.7s)
- `cd frontend && npx vitest run` — run after the registry + prompt code is added; the test file `safety-guardrails.test.ts` references `airway organoids` so I want to confirm no semantic regression.
- Hand-test 5 chat queries (curl `/api/chat/stream`) on a local Node before any `sync_to_dev.sh`:
  1. `"Run DESeq2 on airway"` — must return `state: workflow_ready`.
  2. `"Run DESeq2"` (no dataset) — should still ask for input (proves we didn't over-route).
  3. `"Run DESeq2 on my counts matrix from this paper"` (genuine unknown) — should ask for the file (proves the rule only fires on canonical fixtures).
  4. `"Run fpocket on 1IEP"` — regression check (existing PDB-id rule still works).
  5. `"Run ADMET on aspirin SMILES CC(=O)OC1=CC=CC=C1C(=O)O"` — regression check (existing SMILES rule still works).

Only after all 5 give the expected outcome locally, commit + sync.

## 5) Open questions for review

1. **Production telemetry:** do we have logs of how often chat responses contain "Please upload" / "I need" / "Could you share"? If yes, that's the metric to track pre/post. If no, this PR should add it.
2. **Should the canonical-fixture registry live in code or DB?** Code: simpler, immediate. DB: extensible by ops without redeploy. My recommendation: code-first for the seed list; promote to DB when the list exceeds ~100 entries.
3. **Do we want a UI signal that the request was auto-resolved?** Today the workflow card just appears with `dataset = airway`. We could add a small badge: "Auto-resolved built-in dataset: airway". This builds user trust that the system understood the request correctly.

## 6) Non-goals

- This plan does **not** address the LLM occasionally generating a malformed workflow_ga (separate concern — see existing `_clarificationGate` logic for that).
- This plan does **not** touch the cost-side bypass (D in the plan above). That's intentionally deferred.
- This plan does **not** introduce any test-only knob; the test must pass against the same code path real users hit.
