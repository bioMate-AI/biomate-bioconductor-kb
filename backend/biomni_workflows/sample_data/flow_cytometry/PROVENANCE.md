# Flow cytometry sample data — provenance

## `Accuri_C6_A01_H2O.fcs`

- **What:** A real, small, public flow-cytometry data file (FCS 3.0).
  - Instrument: BD Accuri C6 (`$CYT = Accuri C6`)
  - Sample: H2O blank (well A01)
  - 14 channels: `FSC-A, SSC-A, FL1-A, FL2-A, FL3-A, FL4-A, FSC-H, SSC-H, FL1-H, FL2-H, FL3-H, FL4-H, Width, Time`
  - 191 events (`$TOT = 191`), `$MODE = L`, `$DATATYPE = I`, `$BYTEORD = 4,3,2,1`
  - Size: 13,603 bytes — md5 `1d0d0060b2422b6b93ad6c45f80c5afa`
- **Source:** The Galaxy project's own datatypes test corpus
  (`galaxyproject/galaxy` → `lib/galaxy/datatypes/test/Accuri_C6_A01_H2O.fcs`),
  which is vendored into this repo at
  `backend/lib/galaxy/datatypes/test/Accuri_C6_A01_H2O.fcs`. This copy is
  byte-identical to that file.
- **License:** Galaxy is distributed under the Academic Free License v3.0
  (parts MIT). Its bundled datatype test data is intended for redistribution
  and testing — openly redistributable. Not synthetic; not fabricated.

## Usage

Wired as the default `params.fcs_file_path` for the flow-cytometry
immunophenotyping subworkflow so it is one-click runnable with no upload:
`backend/biomni_workflows/nextflow/subworkflows/cell_biology/analyze_flow_cytometry_immunophenotyping.nf`.
The subworkflow declares it as a staged `path` input (so Nextflow copies it
into the S3 work dir and mounts it inside the isolated AWS Batch container),
and applies a default scatter gating strategy on the `FSC-A` / `SSC-A`
channels that are present in this file.
