# License-free MHC binding prediction (MHCflurry 2)

**Date:** 2026-11-09
**Workflow:** `backend/biomni_workflows/nextflow_nfcore/subworkflows/immunology/mhc_binding_prediction/main.nf`
**Context:** BioMate's peptide×HLA binding path currently runs through `nf-core/epitopeprediction` + `immunology/antigen_resolution`, which use **NetMHCpan / NetMHCIIpan** — gated behind the DTU academic tarball (the executor blocks unlicensed runs). This workflow adds a **license-free class-I alternative** so the cell-therapy / epitope / neoantigen path runs with no license, mapping onto SYSUCC's TCR-T / CAR-T and EBV-antibody work.

## What it does

Predicts peptide×MHC **class I** binding with **MHCflurry 2** (O'Donnell et al., *Cell Systems* 2020; Apache-2.0, `pip install mhcflurry`). It fans out **one task per allele** (parallel on AWS Batch); each task scores every peptide against its allele with MHCflurry's `Class1PresentationPredictor`, then a merge step combines all alleles.

Per peptide×allele it reports MHCflurry's own scores (never fabricated):
- `affinity_nM` — predicted binding affinity (nM; lower = stronger)
- `affinity_percentile` — %rank vs a random-peptide background (the NetMHC %rank analogue)
- `presentation_score` — combined affinity + antigen-processing score (0..1)
- `processing_score` — cleavage/processing score (0..1)
- `binder` — strong (%rank ≤ 2) / weak (≤ 10) / none, the Reynisson-2020 thresholds `antigen_resolution` already uses

## Inputs / outputs

**Inputs (params):**
- `params.peptides` — JSON list of peptide strings, e.g. `["GILGFVFTL","SIINFEKL"]`
- `params.alleles` — JSON list of class-I alleles → one parallel task each, e.g. `["HLA-A*02:01","HLA-B*07:02"]`
- `params.sample_id` — label (metadata)
- `params.strong_rank` / `params.weak_rank` — %rank thresholds (default 2.0 / 10.0)
- `params.outdir`

**Outputs:**
- per allele: `predictions.csv`, `summary.json`
- merged: `mhc_binding_predictions.csv`, `mhc_binding_summary.json` (with `top_strong_binders`)
- `versions.yml`

## How it complements the NetMHC gate

`antigen_resolution` consumes an epitope CSV with columns `peptide, hla_allele, binding_score|rank`. This workflow's `mhc_binding_predictions.csv` carries exactly `peptide, hla_allele, affinity_percentile` (a %rank) — so it is a **drop-in replacement for the NetMHC `epitope_file`** feeding antigen-resolution, with no license. NetMHC stays available for users who have the tarball; this is the open path.

## Class II — stated gap (not silently covered)

MHCflurry 2 is **class I only**. There is no mature, pip-installable, redistributable (BSD/MIT/Apache) class-II predictor equivalent to NetMHCIIpan. **HLA-DR/DP/DQ prediction therefore still requires the gated NetMHCIIpan path** and is NOT provided here. The workflow says so in its header and `summary.json.note`; it does not emit class-II numbers. Closing class II license-free is a separate build (candidate tools to evaluate: MixMHC2pred — check its license terms carefully, which are non-commercial-restricted, not Apache/MIT).

## Container — MUST BE BUILT (does not yet exist)

No existing BioMate image carries MHCflurry: `biomate/workflow-tools` has no `mhcflurry`/`tensorflow`. The workflow references `biomate/mhcflurry` (ECR `:x86` on AWS, `:latest` local) which **must be built and pushed before the first run**, same honest pattern as the MLIP MD image. If the image lacks MHCflurry the task fails with a clear message — it never fabricates scores.

Build recipe (bake the models in — AWS Batch has no reliable network to fetch them at run time):
```dockerfile
FROM mambaorg/micromamba:1.5.8
RUN micromamba install -y -n base -c conda-forge python=3.11 pip tensorflow && micromamba clean -a -y
RUN pip install --no-cache-dir mhcflurry && \
    mhcflurry-downloads fetch models_class1_presentation
# smoke: the predictor loads and scores a known epitope
RUN python -c "from mhcflurry import Class1PresentationPredictor as P; \
    d=P.load().predict(peptides=['GILGFVFTL'], alleles=['HLA-A*02:01'], verbose=0); \
    assert d['affinity'].iloc[0] < 500, d; print('mhcflurry smoke ok', float(d['affinity'].iloc[0]))"
```
Build it on a spot builder (same pattern as `scripts/build_mlip_md_image.sh`) and push to `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/mhcflurry:x86`.

## Validation

**Done (static only):**
- `nextflow lint -o concise` → only 2 error lines, both accepted strict-syntax classes (`import groovy.json.JsonSlurper not supported`, `JsonSlurper is not defined`) — identical in kind to the known-good `antibody_antigen_complex` / `cyclic_peptide_cofold`. No new error class.
- Both embedded `python3` blocks parse under `ast.parse` after Groovy-escape rendering.

**Pending (runtime — not run):**
1. Build + push the `biomate/mhcflurry` image.
2. Register the workflow in the DB (metadata block below) + rebuild FTS.
3. Run on dev against known pairs (e.g. GILGFVFTL / HLA-A*02:01 should be a strong binder, affinity < 50 nM) and confirm `affinity_nM` + `affinity_percentile` populate and the merged CSV feeds `antigen_resolution`.

## Registration metadata (for the DB insert — paste block)

```
name:         MHC Binding Prediction
filename:     nextflow_nfcore/subworkflows/immunology/mhc_binding_prediction/main.nf
description:  License-free peptide-MHC class I binding prediction with MHCflurry 2 (open-source, Apache-2.0) — the no-license alternative to the gated NetMHCpan/NetMHCIIpan path. Fans out one task per HLA allele (parallel on AWS Batch, CPU); each scores all peptides against its allele with MHCflurry's Class1PresentationPredictor. Reports predicted binding affinity (nM), %rank (affinity_percentile), presentation and processing scores per peptide x allele, with strong/weak binder calls (Reynisson 2020 thresholds). Output CSV (peptide, hla_allele, affinity_percentile) is a drop-in for the NetMHC epitope file consumed by immunology/antigen_resolution. Class II (DR/DP/DQ) is NOT covered (MHCflurry is class I only). Input: peptides + class-I HLA alleles. Output: predictions CSV + summary JSON + versions.
annotation:   peptides x HLA class-I alleles -> MHCflurry 2 affinity (nM) + %rank + presentation score (license-free NetMHC alternative)
tags:         mhc,mhc class i,hla,peptide binding,epitope,neoantigen,mhcflurry,mhcflurry2,binding affinity,percentile rank,presentation,immunopeptidome,tcr-t,car-t,vaccine,license-free,netmhcpan alternative,immunology
domain:       immunology
category:     Epitope Prediction
docker_image: biomate/mhcflurry:latest
input_types:  ["peptides","alleles","sample_id"]
output_types: ["csv","json"]
tools_used:   ["MHCflurry 2","Class1PresentationPredictor"]
```

Related: `docs/20261109_SYSUCC_MODALITY_CAPABILITY_AND_ANTIBODY_COMPLEX.md` (SOTA gap #4), `immunology/antigen_resolution` (downstream consumer).
