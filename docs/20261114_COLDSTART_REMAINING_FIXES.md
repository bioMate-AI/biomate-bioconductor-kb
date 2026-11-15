# Coldstart remaining HONEST_FAIL fixes (post A–H sync)

**Date:** 2026-11-14  
**DEV tip baseline:** `4867407d` (A–H synced). Remeasure owns `/tmp/biomate_coldstart_deep.lock` — do not clear.  
**This batch:** committed-ready local patches; **do not sync** until a coherent announce.

Evidence under `frontend/e2e/execshots/coldstart-analysis-design-deep/` (pre-remeasure tips).

---

## Fail classes → root cause → fix

| # | Class | Cases | Root cause | Fix | Status |
|---|-------|-------|------------|-----|--------|
| 1 | **Script compilation** (JsonSlurper) | `design-fold-complex-bio-0/1`, `design-generate-bio-0`, `design-optimise-*-bio-0/1` (Antibody Antigen Complex) | Top-level `import groovy.json.JsonSlurper` rejected on Batch head | Already FQN on `antibody_antigen_complex` (Batch H). Extended FQN to `cyclic_peptide_cofold`, `surface_epitope_mapping`, `mhc_binding_prediction`, `neoantigen_vaccine_design`. Gromacs already FQN. | **Closed in tree** (verify post-remeasure) |
| 2 | **Structure TRAIN / constraints JSON** | `design-*-bio-*`, pep optimise TRAIN | Kind-aware rebind incomplete when specs lacked structure-set label → `*_constraints.json` still promoted | Spec-less fallback in `rebindFilenameValues`; Prepared seeds `dataset=<PDB>` on biologics/enzyme/peptides | **Closed in tree** |
| 3 | **REINVENT4 CLI/prior → Script compilation** | `design-generate-sm-*`, `optimise-sm-*` | Spot remasure on tip `4867407d`: CLI class closed; run fails **Script compilation** because a comment still contained `"""` inside `script: """` | `de208a32bb` scrubs residual triple-quotes (committed, **not on DEV yet**). Optional ECR rebuild still drops Zenodo egress. | **Closed in tree; needs sync of `de208a` + remasure** |
| 4 | **Antibody developability soft** | `design-predict-filter-bio-0` | Completed run + real outputs, but empty `workflowNames` (session metadata lag) and harness looked for removed Findings tab | `data-testid="workflow-panel-name"`; harness polls panel name; Summary/Report map to findings/params | **Closed in tree** |
| 5 | **pep generate path missing** | `design-generate-pep-0/1` | (a) routed to `gromacs_pmx_fep` for “Design cyclic peptides”; (b) DB path `biomate-ai-tools/cyclic_peptide_design/main.nf` **did not exist** → FileNotFound | Created real `cyclic_peptide_design/main.nf`; generative routing excludes FEP engines; catalog seeds prefer design WF | **Closed in tree** |
| 6 | **DEFINE_EDGE** | `design-predict-filter-pep-3` | `DEFINE_EDGE` ran `python3` inside `gromacs-cuda` (often no Python) → container exit; receptor/edge defaults null | `PY_CONTAINER` for DEFINE/PREPARE/ANALYZE; default receptor=`sample_data/peptides/1BXL.pdb` + peptide_pair edge | **Closed in tree** |

---

## Files changed

| File | Change |
|------|--------|
| `…/cyclic_peptide_cofold/main.nf` (+ immunology siblings) | Drop JsonSlurper import; FQN only |
| `…/antibody_antigen_complex/main.nf` | Already FQN (verified) |
| `nf-core-workflows/modules/biomate-ai-tools/cyclic_peptide_design/main.nf` | **New** — rule-based cyclic design pipeline (`git add -f`; parent tree is gitignored) |
| `nfcore/gromacs_pmx_fep/main.nf` | PY_CONTAINER for Python steps; demo receptor/edge defaults |
| `sample_data/peptides/1BXL.pdb` | Vendored demo receptor |
| `frontend/shared/attachment-binding.ts` (+ test) | Spec-less constraints→PDB rebind |
| `cold-start-demo-catalog.ts` | `dataset=<PDB>` seeds; generate≠FEP wording |
| `backend/lib/galaxy/ai/ai_assistant.py` | Generative hint excludes gromacs/openfe |
| `nextflow-workflow-viewer.tsx` | `data-testid="workflow-panel-name"` |
| `coldstart-analysis-design-deep.e2e.ts` | Panel name + Summary/Report tab mapping |

---

## Verify (local — no sync)

```bash
cd frontend && npx tsc --noEmit -p .
cd frontend && npx vitest run \
  shared/attachment-binding.test.ts \
  client/src/components/cold-start-demo-catalog.test.ts \
  e2e/lib/coldstart-deep-grade.test.ts

# Resolve check for new peptide design path:
python3 -c "
from pathlib import Path
p = Path('backend/nf-core-workflows/modules/biomate-ai-tools/cyclic_peptide_design/main.nf')
assert p.is_file(), p
print('ok', p)
"
```

After PRE_SYNC + one-writer sync (announce separately):

```bash
BIOMATE_DEEP_FILTER='design-fold-complex-bio-0|design-generate-bio-1|design-generate-pep-0|design-predict-filter-bio-0|design-predict-filter-pep-3|design-generate-sm-0' \
  ./e2e/run_coldstart_deep.sh
```

---

## Still open after this batch

- **REINVENT4** Script-compilation fix (`de208a`) must sync to DEV, then remasure (optional `reinvent4-nf:x86` rebuild for Zenodo egress).
- **Wrong-product routing** of some bio design prompts to diffusion *training* (binding PDB unblocks TRAIN; product fit is separate).
- **Full remasure blocked locally** — Data volume ~100% full (~0.5 Gi free); free ≥3 Gi before `./e2e/run_coldstart_deep.sh` on the fail filter.
