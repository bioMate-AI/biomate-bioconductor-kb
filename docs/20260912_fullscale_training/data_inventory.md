# Full-scale immune data inventory — 2026-09-12

Live S3 metadata confirms substantial raw data remains beyond all previously trained caches. This inventory is a launch input, not a statement that ingestion or training is complete. All sizes below are decimal GB.

| Dataset group | Objects | Stored GB | Eligible objectives | Ingestion requirements |
|---|---:|---:|---|---|
| RNA source spine | 810 | 2422.859 | RNA reconstruction; study-aware annotation and nuisance objectives where metadata permits | Deduplicate accession/cell identity across source mirrors and derived arms; species/tissue/count-layer QC; do not cap cells per study. |
| RNA derived arms | 306 | 305.086 | Optional canonical representatives after source reconciliation | curated and curated_annot are duplicate views, not extra subjects; avoid counting both. |
| Paired modalities | 5 | 4.148 | RNA/ADT or RNA/ATAC reconstruction and same-cell modality losses | Do not invent triple-paired cells. BMMC CITE and multiome are different cells. Peak coordinate/genome reconciliation and donor grouping required. |
| Protein acquisition | 96 | 11.145 | Protein reconstruction on observed antibody entries; RNA/protein consistency on verified matched barcodes | GSE164378 and Hao reference may duplicate; panels differ and absent markers are unobserved, not zero. Raw formats require ingestion. |
| Chromatin acquisition | 33 | 147.962 | ATAC reconstruction; cross-modal objective only for actual paired samples | GSE129785 is ATAC-only. GSE243917 requires raw RNA/peak barcode intersection restricted to truly paired subset. GSE312129 tar may contain mixed spatial/multiome assets. Common intervals must be re-counted from fragments, not zero-filled unmatched peaks. |
| Primary T-cell perturbation | 47 | 107.821 | H1/state-conditioned response on individual donor/condition/target guide pseudobulk and independent controls | 44.567 GB pseudobulk is aggregated data, not 22M individual cells. DE stats missingness remains masked. by_donors contains overlapping donor pairs, not independent donors. |
| Other perturbation | 73 | 54.683 | Response objectives with controls and held-out perturbations/studies; paired protein response where demonstrated | Separate immune/primary from nonimmune cell-line auxiliary tasks; retain cell type/species context; RNA/protein filenames alone do not establish pairing. |
| Knowledge graph and pathways | 28 | 0.894 | Graph priors, gene/drug embeddings, signed regulatory and pathway objectives | Gene graph alone omits drug-gene edges; full rebakeoff graph identified separately. Keep relation type/sign/confidence and source provenance; knowledge-derived labels are not independent experimental targets. |
| Literature | 26 | 1.588 | Evidence retrieval or separately audited text/biology alignment | 24 compressed fulltext shards. Published 722M token estimate is historical, not independently recounted. Text is not a count matrix or direct mechanistic ground truth. |
| Presentation | 272 | 71.131 | H4 peptide presentation/abundance only with sample/HLA/perturbation mappings | PXD056426 HAP1 and PXD054491 held; processed peptides and search outputs require condition-aware ingestion. Missing detected peptide is not necessarily true biological absence; no generic immune-state/presentation pairing established. |
| Repertoire and spatial | 29 | 26.798 | Optional receptor/sequence or spatial objectives only when actual chains/coordinates and linkage exist | RNA-derived mirrors may lack receptor chains; manifest-only files are not observations. Spatial is not interchangeable with per-cell RNA. |
| Clinical | 38 | 23.319 | Response/stratification with independently curated patient labels | Group by patient, accession and treatment context. Unlabeled expression alone cannot supervise response. |

## Full-source accounting

The RNA spine contains **537 base-corpus objects / 2.152 TB** and **273 immune-expanded objects / 270.438 GB**. These cannot simply be added to curated/harmonized arms because derivatives and mirrors overlap.

The prior `assembled_v7_capT100_capVT800.npz` is 3.489 GB and explicitly capped. It is not the complete source corpus. Full-data training must enumerate uncapped sources, apply documented QC exclusions, and save consumed cell/example counts per dataset and split.

## Knowledge source distinctions

The complete landed MAP-KG candidate is `immunology_sc_corpus_broad/immune_llm_models/rebakeoff_stage/A_mapkg_full_edges.parquet` (2,725,405 bytes); the similarly named `A_mapkg_edges.parquet` and `tracks/structured_knowledge/mapkg/mapkg_genenet.parquet` are smaller gene-network views. Validate node/edge semantics before configuring all-knowledge training. CollecTRI, STRING, Reactome, GO, KEGG, immunologic signatures, DICE expression references, genetics priors, PrimeKG and text shards are separately present; do not silently collapse them to three relation types or a 256-gene pilot vocabulary.

The top-level Tahoe mirror holds 428.807 GB and `external/` includes another large Tahoe copy. `replogle_nadig/` holds 36.265 GB. These are auxiliary perturbation sources whose domain and duplicate accounting must remain explicit; cancer-line coverage is not primary immune donor coverage.

## Launch assumptions and outstanding work

1. Build a frozen per-source manifest of actual examples, gene/peak/protein identifiers, measured masks, species, donors/studies and legal split groups. Prefer native-count sources and reject normalized data masquerading as counts.
2. Resolve duplicates globally before held-out study/donor splits; preserve previously used test cohorts as development cohorts. Hold a fresh confirmation cohort when claiming new generalization.
3. Stream or shard on remote storage/compute. Multi-terabyte RNA sources and 44.567 GB CZI pseudobulk do not fit local free storage. Decompression may exceed compressed object sizes considerably.
4. Enumerate each objective’s eligible observations; no missing assay/label can be supervised as zero. Unpaired modality batches may share a backbone but cannot receive paired reconstruction losses.
5. Log source-object identities, coverage, excluded examples/reasons, observed objective counts, gradient activity, checkpoints, and validation predictions. All layers/objectives is not established by a config flag alone.
6. Keep KG/text priors separate from experimental ground truth, and preserve null/shuffled controls. H1–H4 claims require independently held-out outcome labels matching each task.

## Evidence and limits

`s3_metadata_inventory.json` saves every enumerated key, byte size, ETag and modification time; `data_inventory.json` contains machine-readable grouping and exact prefixes. Metadata queries were read-only and no large datasets were downloaded. ETags are object identifiers, not asserted SHA256 content hashes.

Local registries read: DATA_REGISTRY.md, DATASET_MASTER_REGISTRY.md, MODALITY_PROTEIN_CITE_MANIFEST.md, MODALITY_ATAC_MULTIOME_MANIFEST.md, KG_REGISTRY.md and CZI_TCELL_PERTURBSEQ_MANIFEST.md under the program-control worktree. Their August holdings and old PASS/VALIDATED claims are stale; fresh S3 existence does not rehabilitate earlier H4 scientific claims. Counts of cells/documents from those registries were not independently recomputed in this bounded inventory.
