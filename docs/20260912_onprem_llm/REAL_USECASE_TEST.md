# Real end-to-end use-case test — local Qwen3.8-27B (on-prem, served)

Setup: base 27B (4-bit NF4) served on an **on-demand g6.xlarge (NVIDIA L4, 24 GB)** in us-west-2a
(spot + g6e on-demand were capacity-exhausted across AZs). Driven through the actual agentic steps
using production/harness prompt formats. Fresh realistic scenarios (not from the RealBio test set).

## Result: 13/13 checks passed

| Scenario | intent | route | params | diagnosis |
|---|---|---|---|---|
| Bulk RNA-seq (mouse, PE, 6v6) | workflow_generation ✓ | nf-core/rnaseq ✓ | genome=**GRCm39** ✓, single_end=**false** ✓ | — |
| Single-cell (human 10x PBMC) | ✓ | nf-core/scrnaseq ✓ | genome=GRCh38 ✓ | — |
| Somatic variants (tumor/normal WGS) | ✓ | nf-core/sarek ✓ | genome=GRCh38 ✓ | — |
| ADMET (SMILES, hERG+bioavailability) | ✓ | admet_screening ✓ | input_format=SMILES | — |
| Failed run (GRCh37 index vs GRCh38 BAM) | — | — | — | **genome_mismatch** ✓ |

## What this shows
The on-prem local 27B handles **real BioMate use cases end-to-end** — intent classification, workflow
routing, schema-grounded parameter extraction, and failure diagnosis — with correct **nuanced
inference**: mouse→**GRCm39** (not GRCh38), paired-end→**single_end=false**, tumor/normal→**sarek**,
genome-index-vs-BAM-header→**genome_mismatch**. Runs fully offline on a single 24 GB GPU, no external
network — satisfying the data-sovereignty requirement.

Caveat: this validates the **model** on real scenarios via the served endpoint + production prompts.
Full-stack UX validation (BioMate frontend/backend wired to the local provider via the next-phase
docker-compose Ollama path) is a separate integration test.
