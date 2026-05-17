# Plan A (protein / VLP) vaccine — in silico publication checklist

**Scope:** computational / simulation / prediction workflows available **through BioMate** (Nextflow + Batch). **No** wet lab, animal work, or GMP claims.

**Companion:** `ANDV_VACCINE_PLAN_A_PROTEIN_VLP_IMPLEMENTATION.md`, `BIOMATE_CAPABILITY_GAP.md`, `runs/plan_a_exec_20260512T184220Z/EXECUTION_REPORT.md`, `scripts/run_plan_a_epitopeprediction_batch.py`.

Registry IDs below are from `docs/20260419_WORKFLOW_REGISTRY.csv` unless noted.

---

## A. Done or demonstrably runnable in-repo

| Publication claim (in silico) | Workflow / entry | Evidence / script |
|------------------------------|-------------------|-------------------|
| MHC / epitope panel on peptide or protein FASTA | **nf-core/epitopeprediction** — Galaxy path `nfcore/epitopeprediction/main.nf`, registry **12700** | Batch run **succeeded** (`runs/PARALLEL_EPITOPE_LOG.txt`, `run_plan_a_epitopeprediction_batch.py`); samplesheet template `runs/plan_a_epitope_samplesheet_template/samplesheet_s3_batch.csv` |
| Structure download for antigen models | RCSB fetch scripts + `plan_a_exec` structures | `runs/plan_a_exec_20260512T184220Z/EXECUTION_REPORT.md` §1 |
| Multi-structure comparison (conformational context) | **compare_protein_structures** — id **10815** | `nextflow_nfcore/subworkflows/systems_biology/compare_protein_structures/main.nf` |
| MSA for conservation narratives | **bioconductor/msa** | `nextflow_nfcore/subworkflows/bioconductor/msa/main.nf` |
| Broader structure / complex prediction (optional “stretch”) | **Boltz-2** id **12853**, **Chai-1** id **12854**, combined **structure_prediction_docking** id **10644** | Heavy GPU / multi-container; scope explicitly in Methods limitations |

---

## B. Remaining in silico steps (recommended order)

| # | Claim block | BioMate / nf-core path | Status | Capture |
|---|-------------|------------------------|--------|---------|
| 1 | **Population / allele coverage** for chosen peptides | Extend epitopeprediction with additional alleles in samplesheet; or document fixed panel (e.g. supertypes) as limitation | **Authoring** | Supplementary table: alleles vs peptides |
| 2 | **Immunogen sequence** design (mosaic / consensus) | MSA + manual or scripted merge; optional **scfv_antibody_design** (**12856**) only if framing as **binder** design, not VLP scaffold | **Partial** | FASTA of final immunogen candidates |
| 3 | **VLP / nanoparticle display** geometry | No dedicated “VLP builder” in registry — use **Chai / Boltz** for oligomer hypotheses **or** cite external VLP tools as gap | **Gap** | Methods: “structural hypothesis only” |
| 4 | **Solvent exposure / disorder** of epitope segments | Custom RDKit notebooks **or** add small wrapper workflow (not yet in repo) | **Gap / optional** | Per-residue metrics figure |
| 5 | **Immunogenicity risk** (autoimmunity / toxicity of peptide) | Overlap with **ADMET_pred** / `predict_admet_properties` on short peptides (off-label; document limits) | **Optional** | Same caveats as small-molecule ADMET |
| 6 | **Manufacturing / developability** | **SynCraft** synthesizability (**12857**) on any SMILES-like linker chemistries if applicable | **Optional** | Only if non-natural linkers appear in design |

---

## C. Gaps that imply **new** BioMate tools (if you want automation)

1. **VLP oligomer symmetry builder + coarse input for MD** — today: manual / external; could be a thin Nextflow wrapper around an open tool + export PDB.
2. **Population HLA frequency-weighted epitope score** — today: post-process epitopeprediction TSV in R/Python; a dedicated “coverage report” module would be new.
3. **Glycan-aware epitope surface masking** — largely missing unless folded into Chai/Boltz inputs explicitly.

---

## D. Explicit non-goals (do not claim from this stack)

- Animal immunogenicity, neutralization IC50, clinical correlates of protection.
- GMP CMC, release testing, stability in human cold chain without measured data.

---

## E. One-command Plan A epitope re-run (Batch)

```bash
python3 research/anti-virus/scripts/run_plan_a_epitopeprediction_batch.py \
  --outdir s3://biomate-nextflow-work/nextflow/outputs/plan_a_epitope_rerun/$(date -u +%Y%m%dT%H%M%SZ)/ \
  --ensure-worktree
```

If the client died on **HTTP 500** while polling but Batch is still running, **resume poll only** (no second submit):

```bash
python3 research/anti-virus/scripts/run_plan_a_epitopeprediction_batch.py \
  --poll-run-id '<run_id_from_log>' \
  --timeout 7200
```

See **`docs/ANDV_CAMPAIGN_LESSONS_LEARNED.md`** for profile, samplesheet, and polling rules.
