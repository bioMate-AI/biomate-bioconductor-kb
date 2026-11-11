# 2026-11-11 — SYSUCC resource gaps + build plan

Catalog gaps for the hospital's research/clinical profile (NPC/EBV, immuno-oncology,
precision oncology), verified against `backend/database/galaxy_ai_tools.db`
(4,223 workflows). "Gap" = 0 or only mislabeled/stub matches.

## Already covered (no build needed)
- Antibody (scFv, developability, antibody–antigen complex via Boltz-2), ADC
  (`adc_design`), CAR-T (`cart_construct_design`, `in_vivo_cart_codesign`), cyclic
  peptide, HLA typing / `mhc_binding_prediction` / `bcell_epitope_immunogen` /
  `surface_epitope_mapping`, EBV antibody titers, multi-omics (SNF/MOFA2), survival (Cox).
- cfDNA fragmentomics (`cfdnakit`, `cfdnapro`), spatial (`banksy`, `bayesspace`,
  `codex`, RCTD), TME deconvolution (`granulator`, `immune_deconvolution`, RCTD).

## Priority gaps to BUILD

### Tier 1 — highest value, clear gaps, buildable
1. **Radiomics (NPC MRI/CT)** — `0` in catalog. SYSUCC's signature imaging line.
   PyRadiomics feature extraction (first-order, shape, GLCM/GLRLM/GLSZM) from a
   scan + mask → feature matrix → prognostic ML. Container: python + `pyradiomics`
   + `SimpleITK`. Domain `imaging`.
2. **Plasma EBV DNA / ctDNA MRD** — MRD is `0`; cfDNA fragmentomics exists but no
   target-quantification/MRD. EBV-DNA (NPC) + generic ctDNA MRD: copies/mL from
   aligned cfDNA reads over a target panel, LoD/LoB, serial-timepoint MRD call.
   Container: bioconda (`samtools`, `bcftools`, python). Domain `genomics`.
3. **Neoantigen vaccine end-to-end** — pieces exist (`mhcquant`, `immuneapp`) but no
   chain. HLA typing → somatic variants → neoepitope enumeration → class-I/II
   binding → immunogenicity rank → multi-epitope construct. Tool: `pVACtools`.
   Domain `immuno_oncology`.

### Tier 2
4. **Digital pathology — PD-L1 / multiplex IHC** — beyond `wsi_he_nuclei_segmentation`
   (the 2 catalog "matches" are mislabeled scRNA). PD-L1 TPS/CPS + mIHC cell-type
   quantification. Tools: StarDist/HoVer-Net + QuPath scripting. Domain `imaging`.
5. **Real bispecific antibody design** — current `bispecific_antibody_design` is an
   honest stub that refuses. Upgrade to real: format triage → chain pairing/knob-in-
   hole → developability flags. Domain `drug_discovery`.
6. **EBV genomics** — only generic `nf-core/viralintegration`. EBV genome assembly +
   integration-site mapping + type-1/2 subtyping from tumor/plasma reads. Domain `genomics`.

### Tier 3 (follow-up)
7. Variant → therapy matching (OncoKB/CIViC actionable annotation) — only
   `pharmacogenomics_pgx_report` today.
8. TCR/BCR clonality + dynamics for immunotherapy monitoring (some repertoire tools exist).

## DB field contract (every new entry MUST populate)
Required: `name`, `filename` (= `nextflow_path`:
`nextflow_nfcore/subworkflows/<domain>/<name>/main.nf`), `description`, `annotation`,
`tags` (comma-sep), `domain`, `workflow_json` (full `.nf`), `step_count`, `tools_used`
(JSON array), `source`=`biomni_nextflow`, `format`=`nextflow`, `executable`=1,
`docker_image`, `category`, `workflow_hash`, `input_types` (JSON array), `output_types`
(JSON array).
Left NULL until earned: `real_exec_status` / `real_exec_at` / `real_exec_produced`
(set to `ok` ONLY after a real AWS Batch run — never pre-claimed). Enrichment
(`annotation_v2`, `params_schema`, `workflow_json_v2`, `qc_steps`, `input_kinds`)
follows the standard indexing pass.

## Build approach
Parallel subagents, one per Tier-1/2 resource: each writes the `.nf` (modeled on the
validated `mhc_binding_prediction` / `bcell_epitope_immunogen` pattern — built-in demo
defaults, loud-fail on empty output, no backslash escapes in Groovy `"""` Python) +
a JSON field-spec. DB inserts applied **sequentially** by the orchestrator (SQLite =
single writer). `real_exec_status` stays NULL until each is actually run on Batch.
