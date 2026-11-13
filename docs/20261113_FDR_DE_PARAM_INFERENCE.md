# FDR / fold-change rule inference for DE workflows (2026-11-13)

## Symptom

`instructions-obedience.e2e.ts` soft-skipped FDR: rnaseq has no significance
parameter, so project rule ``FDR (adjusted p) < 0.01`` only appeared in reply
prose. Genome→GRCh38 on rnaseq was already fixed
(`docs/20261113_IGENOME_GENOME_PARAM_PROJECTION.md`); FDR still soft.

## Root cause

1. **Wrong workflow for the assert.** nf-core/rnaseq correctly has no
   `differential_max_qval` / padj slot. FDR belongs on DE workflows such as
   nf-core/differentialabundance (`differential_max_qval`, default 0.05).
2. **Regex gap.** Backend rule-based fill already ran when a significance
   param existed, but the pattern
   ``(?:FDR|…)\s*[<≤=:]?\s*(0?\.\d+)`` failed on the standing project-rule
   phrasing ``FDR (adjusted p) < 0.01`` (parenthetical gloss between token
   and operator). Gate matched `\bFDR\b`; value extract returned `None`;
   schema default 0.05 remained.

Projection was fine — `differential_max_qval` is not in
`_NEXTFLOW_INTERNAL_PARAMS` and surfaces from `nextflow_schema.json`.

## Fix

| Change | Where |
|--------|--------|
| `_extract_fdr_threshold` — parenthetical gloss + `<=` / `<` / `=` / `:` | `ai_assistant.py` |
| `_pick_significance_param_name` — prefer `*max_qval*`/`*fdr*` over bare `alpha` | same |
| `_extract_abs_fold_change` — `\|log2FC\| >= 1` → absolute FC `2.0` | same |
| Wire both into `_return_nextflow_match` rule suggestions | same |
| Rule fills outrank LLM param suggestions (filter + re-assert) | same |
| E2E: (b) genome on rnaseq; (c) hard FDR assert on differentialabundance | `instructions-obedience.e2e.ts` |
| Unit tests for extract + schema projection + apply | `test_fdr_param_inference.py` |

Project rules were already threaded into generate (`_intentForBackend`) and
param extraction (`_paramExtractQuery`).

**Frontend class close (2026-11-13):** with `SCHEMA_GROUNDED_EXTRACTION=1` on
dev, `groundInlineParameters` often re-emits schema defaults
(`differential_max_qval=0.05`, `|log2FC|→1`) *after* the backend rule fill.
Spreading grounded after `_backendFilledParams` clobbered obedience in
`metadata.inlineParameters` (live reprobe: backend `qval=0.01`/`FC=2` with
`autoFilled` rule-based rationale, but meta FC became `1`). Fix:
`mergeInlineParamsPreferringRuleFills` re-asserts rule-backed backend fills
last. Guard: `server/merge-inline-params-rule-fills.test.ts`.

**Note (2026-11-13 probe):** an empty / literal `projectId` (failed create, or
a quoted heredoc that never expands `$PID`) yields schema default
`differential_max_qval=0.05` with no rules in `user_intent` — that is not an
inference miss. With a real project + rules, backend sets 0.01; frontend must
not let grounded LLM defaults overwrite it.

## Tests

- `lib/galaxy/ai/tests/test_fdr_param_inference.py`
- Live: `frontend/e2e/instructions-obedience.e2e.ts` parts (a)(b)(c)

## Intentionally left open

- Instruction-panel UX (edit/delete rules UI) outside this obedience proof.
- Soft `|log2FC|` e2e assert — conversion is covered in unit tests; live case
  hard-asserts FDR only (FC default already matches `|log2FC| >= 1` → 2.0).

## Pre-sync note (auth-service vitest)

Full `npx vitest run` under multi-worktree CPU contention once timed out
`server/auth-service.test.ts` → `verifyCredentials` (default 5s). FDR commit
`5ce97d49b9` touches none of auth (`ai_assistant.py`, FDR unit test, docs,
`instructions-obedience.e2e.ts` only). Isolated re-run of that case alone:
**PASS in ~1.1s** (`bcrypt.hash(..., 12)` + two compares). Unrelated env flake
— do not treat the full suite as green for that run; do not block FDR sync.
