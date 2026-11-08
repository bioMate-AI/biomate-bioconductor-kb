# Phantom param row ("CN1C") — root cause + general fix (2026-10-20)

## Symptom
The 3-SMILES ADMET demo query

> Screen these SMILES for ADMET liabilities and rank them by developability:
> `CC(=O)Oc1ccccc1C(=O)O, CN1C=NC2=C1C(=O)N(C(=O)N2C)C, CC(C)Cc1ccc(cc1)C(C)C(=O)O`

rendered a **spurious "CN1C — Recommended" param row** in the workflow panel
(screenshot `e2e_review_20261020/05-prerun-panel.png`), alongside the real
`Smiles List` and `Admet Model Type` params.

## Root cause (general, not SMILES-specific)
1. The pre-selection inline-data extractor (`extractInlineDataWithLLM`,
   `galaxy-assistant.ts`) is told it may return "any other scientific parameter
   you recognize". Caffeine's SMILES `CN1C=NC2=…` contains `=`, so the LLM
   mis-reads the `CN1C=` prefix as a `key=value` pair and emits a bogus
   `{"CN1C": "NC2=…, <ibuprofen>"}`.
2. That key survives on the **base** `inline_parameters` map (the camelCase
   overlay is schema-filtered via `groundInlineParameters`, but the base map
   echoed onto `workflow_ga.inline_parameters` was not).
3. The viewer (`nextflow-workflow-viewer.tsx:326-338`, `extraInline`) renders a
   param row for **every** `inline_parameters` key not already in the structured
   schema — so `CN1C` became a phantom "Recommended" row.

The defect is that **param rows were not authoritative from the workflow
schema**: any hallucinated / mis-parsed inline key became a row. This is a
general parameter-identification gap, not a missing per-value-type rule.

## Fix shipped (commit `0b6b721b2`)
**Schema-authoritative param rows** — at the `GalaxyAssistant.generateWorkflow`
response chokepoint, intersect `workflow_ga.inline_parameters` (on both
`workflow_ga` and the response root) with the workflow's real schema
(`required_params ∪ optional_params`). Any key the schema does not declare is
dropped before the viewer renders. Only declared params can prefill; no
hallucinated key — `CN1C` or any future one — can become a row.

- Forward-compat preserved: when a workflow ships **no** schema metadata
  (`_schemaNames.size === 0`), the filter is skipped (same policy as the
  existing overlay filter at `groundInlineParameters`).
- Also hardened `normalizeAdmetSmiles` to parse JSON-array / comma-separated
  SMILES values without first-token truncation or double-wrapping, so a
  correctly extracted multi-SMILES value survives intact.
- Regression suite: `server/smiles-list-misparse-20261020.test.ts` (7/7).
  tsc clean; full vitest 1872 passed / 22 skipped.

## Follow-up: correct VALUE (general)
Dropping the phantom row does not, by itself, guarantee the SMILES **value** is
complete — the upstream mis-split put ibuprofen inside the dropped `CN1C` value.
The general mechanism for correct values already exists but is flag-gated:

**`SCHEMA_GROUNDED_EXTRACTION=1`** (`schemaGroundedExtractor.ts`) feeds the LLM
the workflow's canonical param schema and instructs it to "use ONLY the
canonical key names listed — do NOT invent keys" and to return a list for
list-typed params. This structurally prevents `CN1C` AND returns
`smiles_list=[A,B,C]` cleanly. Staged since 2026-06-12 with per-call fallback to
the legacy alias path on any error; the dev-soak stage was never performed.

Decision pending empirical verification (`e2e/admet-prerun-verify.e2e.ts`,
prerun-only, no Batch spend): if the panel still shows a truncated / fragmented
SMILES value after the row fix, enable schema-grounded extraction as the general
value fix rather than adding SMILES-specific parsing rules.

## CORRECTION — the real root cause was CLIENT-SIDE (commit `9592d63aa`)
The server probes below were all clean because the phantom row was **never** a
server-extraction artifact. It came from the **client-side workflow-edit
extractor** (`client/src/lib/workflow-edits-extract.ts`, wired in
`chat-with-artifacts.tsx`): after a workflow card opens, the client reads
`<key>=<value>` / `<key>: <value>` edits from the user message and applies them
as `set_param`. The SMILES `CN1C=NC2=C1C(=O)N(C(=O)N2C)C` matches the `=`
pattern → param `CN1C` = `NC2=…`, which `applyWorkflowEdits` injects as a
"Recommended" row (the `✓ CN1C: … [Undo]` toast visible in the capture). The
single-workflow path (`steps===null` → `stepId='single'`) and the single-step
fallback emitted the edit **without checking the param exists**.

**Fix:** a schema gate — only emit a `set_param` for a name the workflow actually
declares (step params ∪ `inline_parameters` ∪ `required_params` ∪
`optional_params`, via the new `knownParamNames` helper); fall through to legacy
behaviour only when no param metadata is present (lazy-loaded workflow). The LLM
fallback in `chat-with-artifacts.tsx` is gated identically. Regression tests in
`workflow-edits-extract.test.ts`.

The earlier server-side changes (schema-intersection of `workflow_ga.inline_parameters`;
`normalizeAdmetSmiles` multi-SMILES hardening) remain as sound defense-in-depth and
genuine correctness improvements, but were not the operative fix for this row.

## Empirical verification on dev (2026-10-20, post-deploy)
Direct probes against `https://dev-public.biomate.ai` after the fix deployed:

- `POST /api/ai_assistant/generate_workflow` (no inline extraction): `required_params:[]`,
  `optional_params:[smiles_list, ADMET_model_type, admet_shard_size]`, **no CN1C** — the
  backend never creates CN1C.
- `POST /api/chat/stream` (the real chat path, which DOES run inline extraction),
  **4 distinct fresh queries** (varied SMILES order + phrasing): every one returned
  `required_params:[]`, a single `inlineParameters:{smiles_list: "<all 3 SMILES>"}`
  (rationale "Extracted list of SMILES strings provided explicitly in the query"), and
  **zero `"CN1C"` keys**. Stream completed (`event: done`).

Conclusion: fresh generations are clean. `normalizeAdmetSmiles` folds any mis-split
fragment's SMILES value into `smiles_list` and never keeps the fragment key, so the
grounded `inlineParameters` the viewer reads carry only schema params. The CN1C row seen
in the earlier Playwright capture was a **stale-session rehydration** — the shared fixture
(`lifeifei163361@163.com`) has a cluttered history and `/` reloaded a prior workflow card.
The verify harness (`e2e/admet-prerun-verify.e2e.ts`) now starts a clean chat
(`button-new-chat`) before sending, matching the demo-capture requirement to use a clean
session.

## Related
- Bug B (ADMET run marked FAILED on Graphviz DAG render) — fixed via `dag.html`
  across 277 nextflow.config files (commit `66c0f669f`), workflows sync landed.
