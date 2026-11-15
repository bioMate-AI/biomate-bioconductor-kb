# pep-3 gromacs_pmx_fep — receptor path / `.nextflow.log` HONEST_FAIL

**Date:** 2026-11-15  
**DEV tip baseline:** `aaaf2a6b` (fix already in tip: PY_CONTAINER + peptide defaults; path still broken)

## Cause

`design-predict-filter-pep-3` fails at launch with redacted  
`No such file or directory: [path] — Check '.nextflow.log'`.

Two stacked inputs:

1. **Prepared seed** (`cold-start-demo-catalog` peptides) tells the extractor  
   `receptor=1BXL.pdb` (bare basename). That **overrides** the `.nf` default and  
   is treated as “required filled”, so attachments often stay unbound  
   (“workflow does not read your PDB…”).
2. Tip default was `${projectDir}/../../sample_data/peptides/1BXL.pdb`.  
   Nextflow `Channel.fromPath(..., checkIfExists: true)` runs on the launch host  
   against **projectDir = the staged workflow directory**. Sibling  
   `biomni_workflows/sample_data/` is **not** part of that staging → path miss  
   (same class as Batch D chipseq/demo paths, but gromacs lived under shallow  
   `nfcore/` so `../../sample_data` looks right in a full checkout and wrong once  
   only the workflow tree is present).

UI diagnosis text that names `.nextflow.log` is a redaction/parse artifact of the  
missing path, not a claim that `.nextflow.log` is the input.

## Fix

| Change | Why |
|--------|-----|
| Vendor `nfcore/gromacs_pmx_fep/assets/1BXL.pdb` | Receptor lives **under** projectDir |
| Default `params.receptor = ${projectDir}/assets/1BXL.pdb` | Staging-safe |
| `_resolveReceptor()` maps bare `1BXL.pdb` / old sample_data / empty → assets | Catalog seed + CLI echo no longer miss |
| Schema defaults: receptor / peptide_pair / BAK\|G1A edge | Confirm without force-fill |
| Catalog wording: prefer bind attached PDB; bare name still OK | Align seed with resolver |
| `tests/test_engine.py::test_pep3_receptor_bundled_under_project_dir` | Guard against regressing to sibling-only path |

Did **not** touch Module/TRAIN / attachment-binding Batch F paths.

## Remeasure pep-3 alone

After PRE_SYNC + `scripts/sync_to_dev.sh` (one-writer):

```bash
cd frontend
BIOMATE_DEEP_FILTER='^design-predict-filter-pep-3$' ./e2e/run_coldstart_deep.sh
```

Expect: Confirm launches without force-Confirm for missing receptor; DEFINE_EDGE  
starts on `workflow-tools` (not CUDA-without-python); no  
`No such file or directory` at fromPath. Setup/smoke mode may still honest-fail  
later on GPU/tool gates — that is a different class.
