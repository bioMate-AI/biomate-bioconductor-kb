# mock_mode: Process-Level Substitution Pattern (Canonical)

**Date:** 2026-06-01
**Branch:** `integration/next-phase`
**Key commits:** `73071b4f1` (process-level substitution); `4237a8e33` (nullish handling); `ac454c08e` (initial rollout); `857c186a6` (input recipe doc)

## TL;DR

`mock_mode` lets a workflow be fired with zero user-provided parameters and still produce real outputs (substituting canonical placeholder data). Useful for CI smoke tests, framework regression testing, and giving new users a working "try-it" path.

**The canonical pattern requires substitution at the PROCESS script level, NOT inside `workflow{}`.** This non-obvious fact cost ~3 iterations to discover. Documented below so future workflow authors don't repeat it.

## The wrong pattern (looks like it works, silently fails)

```groovy
// file top
params.mock_mode = false
params.smiles    = null

workflow {
    if (params.mock_mode) {
        log.info "MOCK MODE: using aspirin SMILES"
        params.smiles = params.smiles ?: 'CC(=O)Oc1ccccc1C(=O)O'   // ❌ doesn't propagate
    }
    SMILES_VALIDATION()
}

process SMILES_VALIDATION {
    script:
    """
    smiles = '${params.smiles}'   // ❌ resolves to 'null', not aspirin
    ...
    """
}
```

**Symptoms:**
- `nextflow.log` shows `MOCK MODE: using aspirin SMILES` (so the workflow{} block IS running)
- Task `.command.sh` contains `smiles = 'null'`
- Container fails: `ValueError: Invalid SMILES: null`

**Two reasons it fails:**

1. **Nextflow CLI serializes `null` params as the string `"null"`** (truthy in Groovy). The elvis operator `?:` returns `"null"` because it's truthy. No substitution happens.
2. **Even if you fix #1 with an explicit nullish check** (`if (!params.X || params.X in ['null','None','']) params.X = 'mock'`), mutating `params.X` in `workflow{}` doesn't propagate to `${params.X}` in `process script:`. Groovy resolves GStrings at process-script-construction time using the value from the original params Map binding, regardless of in-flight mutation.

## The correct canonical pattern

Substitute INSIDE the process `script:` directive. That's where Groovy resolves the value for interpolation — a local `def` override actually changes what the task sees.

```groovy
// file top
params.mock_mode = false   // CI smoke testing only. Default false. NEVER set true in production unless explicitly requested.
params.smiles    = null    // (other defaults)

workflow {
    if (!params.smiles && !params.mock_mode) {
        error "params.smiles is required (SMILES string of drug candidate)"
    }
    if (params.mock_mode) {
        log.info "MOCK MODE: SMILES_VALIDATION will substitute aspirin (process-level)"
    }
    SMILES_VALIDATION()
}

process SMILES_VALIDATION {
    script:
    // Mock-mode substitution at PROCESS level. params mutation in workflow{}
    // does NOT propagate to GString interpolation here — Groovy resolves
    // `${smiles}` at script construction, using the original params binding.
    def _raw_smiles = params.smiles
    def smiles = (params.mock_mode && (_raw_smiles == null || _raw_smiles.toString() in ['null', 'None', '']))
        ? 'CC(=O)Oc1ccccc1C(=O)O'   // canonical test compound (aspirin)
        : _raw_smiles
    """
    smiles = '${smiles}'   // uses local def, not params
    ...
    """
}
```

Why this works:
- `def _raw_smiles = params.smiles` captures the actual current value at script-construction time
- The ternary checks all three nullish forms: Groovy null, the string `"null"`, the string `"None"`
- `${smiles}` interpolates the LOCAL `smiles` def, not the params one — so the substitution sticks
- No need for `${params.smiles}` anywhere in the script body

## Validation evidence

End-to-end test (commit `73071b4f1` + dev fire `75da05a8-2d0a-41b0-bdd4-079466d6bdcd`):

```bash
curl -X POST .../api/workflows/execute -d '{
  "workflowDefinition": {
    "nextflow_path": "...cyp_ddi_panel/main.nf",
    "parameters": {"mock_mode": true}     # ← no smiles, no anything else
  }
}'
```

Output `validated_compound.json`:
```json
{
  "compound_name": "drug_candidate",
  "input_smiles": "CC(=O)Oc1ccccc1C(=O)O",   ← aspirin substituted
  "canonical_smiles": "CC(=O)Oc1ccccc1C(=O)O",
  "inchikey": "BSYNRYMUTXBXSQ-UHFFFAOYSA-N",  ← matches canonical aspirin
  "descriptors": {
    "molecular_weight": 180.16,
    "cLogP": 1.31,
    "TPSA": 63.6,
    ...
  },
  "lipinski": {"pass": true, "violations": 0}
}
```

Real chemistry computed end-to-end with zero user input. The full pipeline (SMILES_VALIDATION → CYP_INHIBITION → HEPATIC_CLEARANCE → DDI_RISK_ASSESSMENT → DDI_REPORT) runs against the substituted compound.

## Three iterations to discover this (lesson notes)

| Try | Pattern | Result | Why |
|---|---|---|---|
| v17 | `params.smiles ?: 'aspirin'` in workflow{} | `'null'` passed to RDKit, ValueError | `?:` doesn't substitute because `"null"` is truthy |
| v19 | Explicit nullish check in workflow{}, then `params.smiles = 'aspirin'` | Same — task still got `'null'` | params mutation doesn't propagate to process `${params.X}` |
| **v20** | **Substitution inside process `script:`** | **Worked** — aspirin chemistry produced | Local `def` override actually changes what `${X}` interpolates |

Each iteration cost a full AWS Batch firing + diagnosis (~10 min × $0.10). The fix is one-line cheaper once you know the pattern.

## Companion: DB indexer cleanup

Discovered as part of this work: the workflow DB's `input_types` column had hallucinated `mock_mode` for ~12 workflows that didn't actually implement it. The indexer skipped re-extraction on hash match, so stale entries from earlier versions lingered.

Fix: `backend/scripts/refresh_workflow_input_types.py` — walks current `.nf` files on disk and refreshes the DB. Run after any bulk workflow edits.

```bash
python3 backend/scripts/refresh_workflow_input_types.py --dry-run   # preview
python3 backend/scripts/refresh_workflow_input_types.py             # commit
```

This session's refresh corrected 1848 rows.

## Where to apply mock_mode next

From `docs/20260529_WORKFLOW_INPUT_RECIPE.md`, the 23 workflows with explicit required-input guards are the natural priority candidates. Of those, current mock_mode status:

| Workflow | mock_mode | Notes |
|---|---|---|
| cyp_ddi_panel | ✅ working (v20) | canonical example |
| pharmacophore_filtering | ⚠ workflow{}-level only (broken) | needs process-level migration |
| nca_pknca | ⚠ guard-bypass only (no substitution) | needs sample input data shipped |
| cryosparc_standard_spa | ✅ working | original canonical (pre-existing) |
| wgs_germline_gatk | ❌ no impl | not yet rolled out |
| ...18 more... | ❌ no impl | candidates |

Estimated effort: ~15-30 min per workflow (apply the canonical pattern to each required-input's process). About 6-12 hours total to cover all 23.

## Production safety guarantee

- **Default value:** `params.mock_mode = false` on every workflow that implements it.
- **Activation:** ONLY when the API caller explicitly passes `parameters: {mock_mode: true}`.
- **Comment on every declaration:** `// CI smoke testing only. Default false. NEVER set true in production unless explicitly requested.`
- **Workflow-level log line:** every mock_mode-enabled run logs `MOCK MODE: ...` so operators can verify in production runs that mock is NOT silently active.
- **No env-var fallback / config override:** the only path to `mock_mode = true` is the explicit API payload.

If we ever need to disable mock_mode entirely in production, set in `nextflow.config`:
```groovy
params.mock_mode = false  // override any per-workflow default
```
…which would still be overridable by `--mock_mode true` at CLI. Tighter lock requires removing the param altogether.

## Commit ledger (mock_mode work this session)

| Commit | Fix |
|---|---|
| `857c186a6` | Workflow input recipe doc (per-workflow required params + DB hallucination audit) |
| `ac454c08e` | Initial rollout: DB indexer refresh tool + mock_mode v1 (workflow{}-level) on 3 workflows |
| `46ff9513a` | Pharma closure hoist for parser-v2 |
| `4237a8e33` | Nullish-handling fix (`?:` → explicit check for `'null'`/`'None'`) |
| `73071b4f1` | **Canonical fix: substitution at process script level** |
| (this doc) | `docs/20260601_MOCK_MODE_CANONICAL_PATTERN.md` |
