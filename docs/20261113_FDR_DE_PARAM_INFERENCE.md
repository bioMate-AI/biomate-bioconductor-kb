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
| E2E: (b) genome on rnaseq; (c) hard FDR assert on DE route | `instructions-obedience.e2e.ts` |
| Unit tests for extract + schema projection + apply | `test_fdr_param_inference.py` |

Project rules were already threaded into generate (`_intentForBackend`) and
param extraction (`_paramExtractQuery`); no frontend projection change needed.

## Tests

- `lib/galaxy/ai/tests/test_fdr_param_inference.py`
- Live: `frontend/e2e/instructions-obedience.e2e.ts` parts (a)(b)(c)

## Intentionally left open

- Instruction-panel UX (edit/delete rules UI) outside this obedience proof.
- Soft `|log2FC|` e2e assert — conversion is covered in unit tests; live case
  hard-asserts FDR only (FC default already matches `\|log2FC\| >= 1` → 2.0).
