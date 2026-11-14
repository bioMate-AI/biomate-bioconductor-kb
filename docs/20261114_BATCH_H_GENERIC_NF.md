# Batch H — generic Nextflow coldstart fails (inventory §6)

**Date:** 2026-11-14  
**Evidence tip:** `0b63d793` / `d258bd32` / `5dd9b6fb` JSON under `frontend/e2e/execshots/coldstart-analysis-design-deep/`  
**Inventory:** `docs/20261114_COLDSTART_FAILED_WORKFLOWS_INVENTORY.md` §6  
**Scope:** HONEST_FAIL generic NF fails **excluding** Batch D path/storage/PRODUCTION_MD (`try-sample-data-0/3/8`), reinvent4*, structure-set (F), bioconductor R exits (G), soft-pass harness (A), prepared-inputs Cryo/openfe block seeds owned by C where noted.

---

## Case → root cause → fix / skip

| Case | Workflow | Observed | Root cause | Decision |
|------|----------|----------|------------|----------|
| `analysis-validated-workflows-1`, `analysis-domain-txn-0`, `analysis-domain-clin-2` | Bulk RNA-seq Differential Expression Analysis (`bulk_rnaseq_de_analysis`) | Pipeline failed; empty outputs | Count-matrix coldstart (airway / MG) routed to **FASTQ** chain (nf-core/rnaseq → DE → GSEA). No FASTQ → early abort. | **Fixed** — remap `bulk_rnaseq_de_analysis` → `bioc_bulk_rnaseq_de_v2` when counts attached; seed `de`/`submission` Prepared inputs to prefer count-matrix chain + `matrix=` / `input=`. |
| `analysis-domain-gen-2` | seqvartools | Nextflow run failed; no stderr | R body hard-required `file.vcf` + `pedigree_data.RData`; demo is `*.vcf.gz` + PLINK `.ped`. Freestyle bioc staging also omitted VCF/ped extensions. | **Fixed** — discover `.vcf/.vcf.gz` + build pedigree from `.ped` in `main.nf`; bioc wrapper freestyle + role hints + keep original basename for ped/vcf.gz. |
| `analysis-try-sample-data-5` | Bcell Epitope Immunogen | Nextflow run failed; no stderr | Default was synthetic antigen; LLM often left/overwrote `antigens` poorly; top-level `import groovy.json.JsonSlurper` is a compile landmine on some Nextflow heads. | **Fixed** — default `params.antigens` = UniProt P03200 gp350 JSON (vendored `sample_data/ebv/`); FQN JsonSlurper; coldstart example attaches `P03200_gp350.fasta` + Prepared notes. |
| `design-predict-filter-sm-2`, `design-fold-complex-sm-0` | Docking Autodock Vina | Nextflow run failed; no stderr (`dd-1` REAL_PASS on older tip) | Empty `receptor_pdb_file` default + ghost DB path `…/drug_discovery/docking_autodock_vina` (no file; alias existed but Confirm often left receptor blank). | **Fixed** — default `receptor_pdb_file=1IEP`, `site_ligand=STI`; symlink `drug_discovery/docking_autodock_vina` → pharmacology twin; molecules/docking Prepared seeds for receptor + smiles. |
| `design-predict-filter-sm-1`, `design-rank-candidates-pep-0`, `design-predict-filter-bio-1` | Prompt-as-name DAG / pipeline | Panel title = user prompt; run fails | `dagPlanName` preferred the user question as the card name; multi-intent DAGs resolved to weak/wrong steps. | **Fixed** — question-like goals prefer catalog `workflow_label`s; post-`plan_dag` rename when title still looks like a prompt. |
| `design-fold-complex-bio-0/1` | Antibody Antigen Complex | Script compilation error — file : `[path]` | Top-level `import groovy.json.JsonSlurper` rejected as script compile error on Batch head (same class as other Boltz JSON workflows). | **Fixed** — remove import; use `new groovy.json.JsonSlurper()`; biologics context documents demo param defaults (attachments are not file inputs). |
| `design-fold-complex-bio-2` | (structure-set / ML) | structure-set pointer JSON | Batch **F** | **Skip** (owned by F) |
| `design-predict-filter-pep-3` | gromacs_pmx_fep `DEFINE_EDGE` | DEFINE_EDGE container exit | Missing `receptor` / `edge_spec` after clarify (peptide RBFE). Inventory labelled “openfe”; live card is **gromacs_pmx_fep**. | **Fixed (seed)** — peptides Prepared inputs set `receptor=1BXL.pdb edge_kind=peptide_pair edge_spec=BAK\|G1A`. |
| `design-predict-filter-sm-3` | openfe_rbfe | BLOCKED_REQUIRED | Batch **C** ligand SDF seed | **Skip** (owned by C) |
| `analysis-try-sample-data-0/3/8` | differentialabundance / flow / MACS | storage / PRODUCTION_MD / path | Batch **D** | **Skip** (owned by D) |
| Pure `NO_LAUNCH` (§3) | various | No Confirm | Routing/UX | **Document only** — out of Batch H |

---

## Files changed

| File | Change |
|------|--------|
| `…/bioconductor/seqvartools/main.nf` | Discover VCF/vcf.gz; PLINK `.ped` → pedigree table |
| `…/api/nextflow_executor.py` (lib⇄packages hardlink) | Freestyle VCF/ped; role hints; keep basename for ped/vcf.gz |
| `…/antibody_antigen_complex/main.nf` | Drop JsonSlurper import; FQN + empty-list guard |
| `…/bcell_epitope_immunogen/main.nf` | P03200 default antigens; FQN JsonSlurper |
| `…/sample_data/ebv/*` | Vendored P03200 FASTA + antigens JSON + PROVENANCE |
| `frontend/client/public/demo/cold-start/P03200_gp350.fasta` | Coldstart attachable copy |
| `…/pharmacology/docking_autodock_vina/main.nf` | Default receptor `1IEP`, `site_ligand=STI` |
| `…/drug_discovery/docking_autodock_vina` | Symlink → pharmacology twin (ghost path) |
| `frontend/server/library-triage-sequential.ts` (+ tests) | Count-matrix detect + chain remap |
| `frontend/server/galaxy-assistant.ts` | Remap wire-in; prompt-as-name `dagPlanName` + post-plan rename |
| `frontend/server/dag-plan-routing.test.ts` | Prompt-as-name title test |
| `frontend/client/src/components/cold-start-demo-catalog.ts` | Prepared KV seeds (DE, relatedness, vina, gromacs, biologics) |
| `frontend/client/src/components/cold-start-examples.ts` | Bcell FASTA + hiddenContext |

**Not edited (per Batch H boundary):** reinvent4*, attachment-binding samplesheet, soft-pass harness, PRODUCTION_MD/chip-seq (D), structure-set (F), bioconductor R exits beyond seqvartools input discovery (G), prepared-inputs Cryo/openfe block path (C), `_PER_PROCESS_CONTAINER_WORKFLOWS`.

---

## Verify

```bash
cd frontend && npx tsc --noEmit -p .
cd frontend && npx vitest run \
  server/library-triage-sequential.test.ts \
  server/dag-plan-routing.test.ts \
  client/src/components/cold-start-demo-catalog.test.ts \
  client/src/components/cold-start-examples.test.ts

# After PRE_SYNC + sync_to_dev (one-writer):
BIOMATE_DEEP_FILTER='analysis-validated-workflows-1|analysis-domain-txn-0|analysis-domain-gen-2|analysis-try-sample-data-5|design-fold-complex-bio-0|design-predict-filter-sm-2|design-predict-filter-pep-3|design-predict-filter-sm-1' \
  ./e2e/run_coldstart_deep.sh
```

Expect: Bulk RNA-seq cards show **bioc** count-matrix chain (not rnaseq FASTQ); seqvartools/bcell/vina/antibody launch past prior abort classes; prompt-as-name titles are catalog names when labels exist; gromacs Confirm enabled with receptor/edge_spec seeded.
