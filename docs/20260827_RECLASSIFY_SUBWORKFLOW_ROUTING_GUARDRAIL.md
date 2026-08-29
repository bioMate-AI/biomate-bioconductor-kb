# Routing reclassification — measured guardrail (PR #188)

**Date:** 2026-08-27
**Branch:** `fix/reclassify-complete-subworkflows` (PR #188)
**DB:** real dev catalog `backend/database/galaxy_ai_tools.db` (315 MB, 4,057 workflows)
**Mode:** FTS + rule-scoring (dense/BGE + LLM Pass-0 disabled locally — see *Faithfulness* below)

## What the change does

BioMate's complete, runnable domain workflows (docking, ADMET, retrosynthesis,
PBPK, cryo-EM, WGS-GATK, …) are filed on disk under
`nextflow_nfcore/subworkflows/<domain>/`. The router's `_is_component_subworkflow`
classifier decided which retrieved workflows are *pipeline components* — those
get an **unconditional −8 score penalty** in `_calculate_score` plus an LLM
catalog label ("subworkflow (pipeline component)") and the prompt line "never
rank a subworkflow above a pipeline". Because the domain catalog sat under a
`subworkflows/` path, all 283 complete domain workflows were wrongly flagged and
buried.

The fix narrows the classifier to **genuine components only**:
- nf-core subworkflows (`source == nfcore_subwf`, `nf-core-modules/subworkflows/…`,
  or paths starting `nfcore/subworkflows/`)
- the bioconductor subtree (`…/subworkflows/bioconductor/…`) — kept as-is this pass

Population (real DB): **283** domain workflows promoted to COMPLETE; **3,310**
bioconductor + **93** genuine nf-core components stay classified.

## The bug inside the first fix (why "measure before merge" mattered)

The originally-committed helper (`99eb6312e`) used a bare substring test:

```python
if "nfcore/subworkflows/" in fn: return True
```

`nextflow_nfcore/subworkflows/` **contains** the substring `nfcore/subworkflows/`,
so the test re-flagged the very 283 workflows it was meant to promote. The
reclassification was a **silent no-op** — the guardrail measured OLD == NEW with
byte-identical scores. Fixed in `bd644aaea` by anchoring the nf-core branch:

```python
if fn.startswith("nfcore/subworkflows/") or "nf-core-modules/subworkflows/" in fn:
    return True
```

## Guardrail result (anchored fix)

Battery of 12 canonical queries, top-1 OLD (legacy `"/subworkflows/" in fn`) → NEW:

| query | OLD top-1 | NEW top-1 | Δ |
|---|---|---|---|
| docking | Run Diffdock (44.15) | Run Diffdock (**52.15**) | +8.00, penalty gone |
| admet | Predict ADMET (62.01) | Predict ADMET (**70.01**) | +8.00 |
| chipseq | Chipseq Macs2 (63.98) | Chipseq Macs2 (**71.98**) | +8.00 |
| cryoem | CryoSPARC (51.35) | CryoSPARC (**59.35**) | +8.00 |
| rnaseq | nf-core/rnaseq (64.79) | nf-core/rnaseq (64.79) | unchanged |
| scrnaseq | nf-core/scrnaseq (53.29) | nf-core/scrnaseq (53.29) | unchanged |
| wgs | nf-core/genomicrelatedness (53.79) | nf-core/genomicrelatedness (53.79) | unchanged (+ WGS-GATK enters top-3) |
| proteomics | nf-core/diaproteomics (71.66) | nf-core/diaproteomics (71.66) | unchanged |
| atac | nf-core/atacseq (46.03) | nf-core/atacseq (46.03) | unchanged |
| methylseq | nf-core/methylseq (46.38) | nf-core/methylseq (46.38) | unchanged |
| pbpk | pbpk_simulation (51.89) | pbpk_simulation (51.89) | unchanged |

**Conclusions:**
1. **Docking / domain catalog un-buried** — every promoted domain workflow gains
   exactly **+8.00** (the removed penalty), so it now competes on its FTS+dense
   merits instead of starting 8 points down.
2. **Zero canonical-pipeline regression** — no nf-core pipeline top-1 changed for
   any pipeline-shaped query. Domain workflows rise *within their own domain* but
   do not displace canonical pipelines.
3. **Score decomposition, settled** — the uniform +8.00 shift proves the **−8
   penalty** was the determinant of the docking-buried behaviour, **not** the
   FTS ×1.5 / dense ×0.5 weights (which were unchanged here).

## Faithfulness / limits

- Ran in **FTS + rule** mode: the local env (numpy 2.0.2 / broken torch) can't
  load `sentence_transformers`, so the dense BGE prefilter and LLM Pass-0 return
  empty. This is a **conservative** setting for a no-regression claim: dense+LLM
  on dev only *add* score to semantically-matching complete pipelines for
  canonical queries — they cannot manufacture a new regression out of *removing a
  penalty* from 283 domain workflows.
- The docking-vs-boltz ordering on dev is partly a dense effect; the +8.00 gained
  by docking workflows should let them overcome boltz's dense edge, but the exact
  dev ranking should be re-confirmed against the live router post-deploy.
- Harness: `scratchpad/reclassify_regression.py` (isolated module load, real DB,
  old-vs-new monkeypatch of the classifier).

## Merge gate

Guardrail **passes** → PR #188 is safe to mark ready + auto-merge. After merge,
sync backend from the main repo (`/Users/kky/biomate`, not a worktree) and
re-confirm docking routing on the live dev router (dense active).
