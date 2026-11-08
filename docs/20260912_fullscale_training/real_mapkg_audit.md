# Actual MAP-KG artifact audit — 2026-09-12

`A_mapkg_full_edges.parquet` is **not evidence of a complete heterogeneous knowledge graph**. Its actual schema contains only `i_symbol`, `j_symbol`, and `relation` (all strings), with 233,773 rows and 15,250 unique endpoint strings. The relation semantics are entirely gene/protein interaction relations; the file supplies no node-type fields, explicit drug/disease relations, provenance/source fields, signed effects or typed drug entities. The filename `full` does not establish completeness.

| Normalized relation family | Rows |
|---|---:|
| Same protein complex / physically associated | 195,264 |
| Protein–protein interaction | 29,423 |
| Colocalizes | 8,296 |
| Direct interaction | 790 |

There are 62,166 distinct raw relation strings because confidence values are embedded in the prose. A relation encoder must parse relation family and numeric confidence separately; treating all strings as distinct relation types would be a schema error. All confidence values parse, range 0–1, and 968 rows have confidence below 0.5 despite some prose saying “high confidence.” There are 11,765 exact duplicate rows, no nulls and no self-loops. Decide duplicate aggregation explicitly before training; do not silently multiply edge weight by repeated exports. Association/colocalization is not a signed causal regulatory edge.

SHA-256: `a076245408b61c8ee385fd30c92575eabe8fdcf58a6ff11e45897500d48ea647`; size 2,725,405 bytes. Full machine-readable results and inventory provenance are in `real_mapkg_audit.json`; reproducible local audit is `audit_real_mapkg.py`.

The saved S3 metadata inventory identifies these related keys (bucket `knowledge-datasets-1759951976`):

- `immunology_sc_corpus_broad/tracks/structured_knowledge/mapkg/mapkg_genenet.parquet` — 759,628 bytes, a genenet-named candidate.
- `immunology_sc_corpus_broad/immune_llm_models/rebakeoff_stage/A_mapkg_edges.parquet` — 710,270 bytes.
- `immunology_sc_corpus_broad/immune_llm_models/rebakeoff_stage/A_mapkg_full_edges.parquet` — the audited 2,725,405-byte artifact.
- `immunology_sc_corpus_broad/immune_llm_models/rebakeoff_stage/primekg_immune_subgraph.parquet` — 750,313 bytes; a different graph/subgraph candidate whose node/edge schema still needs inspection before claiming drug coverage.

**No original complete heterogeneous MAP-KG object was located in this inventory.** The `structured_knowledge/` top-level listing is empty; the nested tracks location contains only the MAP-KG genenet object above. This is a bounded inventory finding, not proof that the original graph is absent from all storage. Further discovery should inspect acquisition/export provenance or an explicitly identified original graph location, then verify node types and drug/disease relation coverage. No large download or external write was performed for this audit.
