# Complete collected-knowledge coverage ledger

The bounded compiled-inventory audit now tracks **61 knowledge-related S3 objects and 169 local raw skill payloads**. Six parsed sources are not all collected knowledge. No source in this ledger is marked verified optimized without a run exposure record. Inventoried duplicates/derived exports are retained for reconciliation, not counted as independent evidence.

Current states: six downloaded/parsed adapters; one audited MAP-KG projection; 24 text shards with streaming adapters; one full typed graph with verified schema and streaming preparation; 29 objects still awaiting adapter reconciliation. The JSON preserves every key, original classification, byte count and reason.

The full graph `biomni_data_lake/kg.csv.gz` is 92,004,058 compressed bytes and was incorrectly classified as unsupported metadata by the compiled manifest. Three streamed rows verify relation plus typed source/target IDs, names and namespaces. The `primekg_stream_prepare.py` adapter retains all columns and emits bounded parquet chunks without a row/graph cap. It must run on the training host, then its chunks must enter a typed graph loss. Only the three-row schema was inspected here; full relation/drug coverage is not yet empirically counted. One streaming-schema/reciprocal-group test passed.

## Still pending adapter reconciliation

These are explicit pending sources, not exclusions from the user’s current-model scope:

- biomni_data_lake/BindingDB_All_202409.tsv.gz
- biomni_data_lake/proteinatlas.tsv.gz
- immunology_sc_corpus_broad/genetics_db/eqtl_catalogue/dataset_metadata_r8.tsv
- immunology_sc_corpus_broad/genetics_db/gwas_catalog/associations_full.zip
- immunology_sc_corpus_broad/genetics_linked/onek1k/onek1k.h5ad
- immunology_sc_corpus_broad/immune_llm_models/rebakeoff_stage/A_mapkg_edges.parquet
- immunology_sc_corpus_broad/immune_llm_models/rebakeoff_stage/A_ppi_edges.parquet
- immunology_sc_corpus_broad/immune_llm_models/rebakeoff_stage/A_tf_edges.parquet
- immunology_sc_corpus_broad/immune_llm_models/rebakeoff_stage/collectri_human.tsv
- immunology_sc_corpus_broad/tracks/structured_knowledge/dice/B_CELL_NAIVE_TPM.csv
- immunology_sc_corpus_broad/tracks/structured_knowledge/dice/CD4_NAIVE_TPM.csv
- immunology_sc_corpus_broad/tracks/structured_knowledge/dice/CD4_STIM_TPM.csv
- immunology_sc_corpus_broad/tracks/structured_knowledge/dice/CD8_NAIVE_TPM.csv
- immunology_sc_corpus_broad/tracks/structured_knowledge/dice/CD8_STIM_TPM.csv
- immunology_sc_corpus_broad/tracks/structured_knowledge/dice/M2_TPM.csv
- immunology_sc_corpus_broad/tracks/structured_knowledge/dice/MONOCYTES_TPM.csv
- immunology_sc_corpus_broad/tracks/structured_knowledge/dice/NK_TPM.csv
- immunology_sc_corpus_broad/tracks/structured_knowledge/dice/TFH_TPM.csv
- immunology_sc_corpus_broad/tracks/structured_knowledge/dice/TH17_TPM.csv
- immunology_sc_corpus_broad/tracks/structured_knowledge/dice/TH1_TPM.csv
- immunology_sc_corpus_broad/tracks/structured_knowledge/dice/TH2_TPM.csv
- immunology_sc_corpus_broad/tracks/structured_knowledge/dice/THSTAR_TPM.csv
- immunology_sc_corpus_broad/tracks/structured_knowledge/dice/TREG_MEM_TPM.csv
- immunology_sc_corpus_broad/tracks/structured_knowledge/dice/TREG_NAIVE_TPM.csv
- immunology_sc_corpus_broad/tracks/structured_knowledge/dice/mean_tpm_merged.csv
- immunology_sc_corpus_broad/tracks/structured_knowledge/mapkg/mapkg_genenet.parquet
- immunology_sc_corpus_broad/tracks/structured_knowledge/msigdb_c7/c7.immunesigdb.v2025.1.Hs.symbols.gmt
- immunology_sc_corpus_broad/tracks/structured_knowledge/ppi/string_ppi_hc.parquet
- immunology_sc_corpus_broad/tracks/structured_knowledge/vdjdb/vdjdb-2026-06-03.zip

The 169 targeted asthma raw payloads preserve previous skill outputs but require source/entity/license normalization and deduplication before training use. Their presence is not exposure, and target-prioritization conclusions must not silently become factual ranking labels. Text, graph and priors require separate processed/optimized/retrieved statuses. Full source-specific licensing/release reconciliation remains necessary.
