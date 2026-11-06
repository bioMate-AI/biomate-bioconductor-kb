# Versioned knowledge acquisition and current-integration handoff

Six **previously collected** structured sources were downloaded and parsed during this task (9,288,771 raw bytes). In accordance with the user correction, these are for the **CURRENT model**, despite this directory's earlier `vnext` name. No newly sourced external catalog was acquired by this lane. No optimizer run or checkpoint exposure is claimed.

`acquisition_manifest.json` records source URIs, object identity before/after download, SHA-256, raw and prepared paths, coverage and training status. `raw/` preserves all six payloads. `current_prepared/` provides unfiltered parquet tables ready for schema-aware adapters:

- Reactome: 2,868 pathways / 142,657 memberships.
- KEGG: 186 pathways / 12,797 memberships.
- GO biological process: 7,647 terms / 627,225 memberships.
- CollecTRI: 42,990 regulator-target rows. **21,699 use default activation**, so preserve `sign_decision`; do not call all signs experimentally established. References and resources remain intact.
- Genetics: 1,842 disease/gene rows, nine diseases and 1,014 genes. Disease identity and separate association components are preserved; no maximum-over-diseases collapse.
- PrimeKG immune subgraph: 115,424 typed rows, 12 relation categories including disease/protein and exposure links. **No drug node type exists in this collected subgraph**, so it does not repair drug-graph coverage. Names lack canonical node IDs; retain types and normalize with provenance before joins.

No source top-K restriction, expression-based filter or deduplication was imposed. These six tables have no exact duplicate records under the tested source schemas. Overlap across resources and reciprocal graph relations still require explicit handling; absence of exact duplicates does not establish independent evidence. Source catalogs are whole as collected in S3, not verified complete contemporary upstream releases.

Prior skills evidence exists in `../20260911_asthma_target_prioritization/`: its audit records Life Science Research cached-script execution, and six lane JSON files preserve targeted results. This is stronger than merely naming skills, but those three-target results are not whole catalogs and have no demonstrated optimizer exposure. They should remain provenance-aware evidence/retrieval material rather than be silently converted into target-ranking labels. Installing/querying a skill, storing a payload, parsing it, retrieving it in a response and optimizing model weights are separate statuses.

Source release/licensing terms were not recovered from these objects. S3 availability does not establish redistribution or training rights. Preserve source-specific terms and provenance before deployment or redistribution; no cloud writes occurred. The next integration step is wiring these full collected tables to current structural priors with explicit coverage/exposure counts, relation-aware losses and held-out leakage controls, while newly acquired catalogs are separately versioned for the subsequent model.
