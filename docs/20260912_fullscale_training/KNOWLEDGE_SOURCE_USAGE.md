# Are the added knowledge skills being used?

Audit date: 2026-09-12. Answer: some named sources have existing code/artifacts, but execution through the newly mentioned skills is not verified; comprehensive source-to-training or source-to-response integration is not verified. A skill provides querying instructions/tools. Its availability does not establish ingestion, retrieval invocation, optimizer exposure or checkpoint influence.

| Source group | Verified implementation evidence | What remains unproven |
|---|---|---|
| Reactome, KEGG, GO; genetic prior artifact | b2_train_encoder.py implements GMT/prior loading and support reporting; missing sources may be silently skipped or replaced with a zero prior | Complete vocabularies, full-source coverage and actual exposure in a new full-scale run |
| OpenTargets | genetics_priors.py, target_selection.py, curate_immune_targets.py; BioMate adapter searches target descriptions, not disease-association evidence | Broad disease coverage and checkpoint-level contribution; target-curation output is not automatically training data |
| ChEMBL | Target/drug/mechanism curation code | Consumption of resulting atlas by biological objectives |
| Literature / NCBI | L2_knowledge.py implements corpus-to-gene text embeddings and NCBI fallback; BioMate literature/citation clients exist | Full corpus consumed, live success and evidence use in every response |
| PubMed, OpenTargets, STRING retrieval | frontend/server/evidence-routes.ts and tests implement retrieval adapters | Current deployed invocation/success and findings grounded in returned evidence |
| CELLxGENE | Landed RNA sources and source-acquisition/signature code | Complete, deduplicated corpus training; source storage alone is not training |
| GWAS Catalog, GTEx | Acquisition inventory / BioMate database workflow routing references | End-to-end source-specific training integration and live response verification |
| FinnGen, UKB/TOPMed, BioBank Japan, TPMI, gnomAD, PharmGKB | No demonstrated training consumption found in this code audit | Adapters, versioned payloads, phenotype mappings and consumption ledger |
| HPA, Bgee, EFO, ClinicalTrials, bioRxiv, PMC, NCBI Datasets, ArrayExpress skills | Earlier requested source list does not establish execution or integration | Source-by-source installation/query/ingestion/usage audit; do not count as used merely because named |

## Required integration in the full-scale system

Use one evidence registry with source-specific adapters and two consumers. The biological training pipeline consumes frozen, licensed, typed evidence snapshots as graph/pathway/genetic priors or independently audited alignment examples. BioMate reasoning queries the same registry plus live tools for current, cited evidence. There is no need for a separately trained LLM or an isolated RAG system for each source. Different indexes can share the same schema/router.

For each source record: source release/query/date, raw payload hash, entity/phenotype identifiers, evidence type, direct disease versus adjacent phenotype, confidence/provenance, deduplication family, allowed use, processed artifact hash, training run/objective/exposure count, and retrieval invocation/citations. Treat correlated resources (for example a GWAS study redistributed through OpenTargets) as overlapping evidence, not two independent replications.

Clinical/regulatory status and changing literature belong primarily in retrieval. Genomics/regulatory/pathway priors can constrain representations. Measured omics and matched perturbations supervise H1–H4. Neither publications nor association scores substitute for measured translation or presentation outcomes.

## New concrete knowledge coverage defect

Opening A_mapkg_full_edges.parquet revealed 233,773 rows with only gene/protein interaction families, no explicit drug/disease node types, and 11,765 exact duplicate rows. Its `full` name was misleading as a claim of heterogeneous knowledge coverage. See real_mapkg_audit.md. Training cannot be called all-knowledge until the broader graph sources are resolved and their consumed relations are counted.

This is a static code/artifact audit, not a live integration test. No full-scale training is running yet. The execution plan and implementation work continue; the missing source integrations are part of that scope.


## Independent source-code verification and limitations

The following references were inspected locally; none constitute a deployed request trace or new optimizer run.

- [GMT loader](/Users/kky/biomate-audit-fix/research/immune_llm_baseline/b2_train_encoder.py:255) selects pathways with at least five mapped genes, ranks by size, and retains at most K (default512). Download failures are skipped. Thus even successful invocation does not mean full pathway coverage. [Genetic-prior loader](/Users/kky/biomate-audit-fix/research/immune_llm_baseline/b2_train_encoder.py:287) reduces disease-specific rows to each gene's maximum prior and returns zeros on failure. The resulting prior is not a disease-specific evidence collection. [Call sites](/Users/kky/biomate-audit-fix/research/immune_llm_baseline/b2_train_encoder.py:548) establish wiring, not actual source exposure in a particular checkpoint.
- [ChEMBL mechanism curation](/Users/kky/biomate-audit-fix/research/immune_llm_baseline/curate_immune_targets.py:170) and [target-linked drug lookup](/Users/kky/biomate-audit-fix/research/immune_llm_baseline/curate_immune_targets.py:209) establish acquisition capabilities; their output needs a separate typed training consumer and artifact/run ledger.
- [Corpus gene-text construction](/Users/kky/biomate-audit-fix/research/immune_llm_baseline/L2_knowledge.py:258), [NCBI summary fallback](/Users/kky/biomate-audit-fix/research/immune_llm_baseline/L2_knowledge.py:297), and [representation construction](/Users/kky/biomate-audit-fix/research/immune_llm_baseline/L2_knowledge.py:332) are bounded representation routines. They do not prove all documents were consumed, or that text supplied measured H1–H4 supervision.
- [PubMed adapter](/Users/kky/biomate-review/frontend/server/evidence-routes.ts:173) uses search and summary APIs; this does not establish full-text retrieval. [OpenTargets adapter](/Users/kky/biomate-review/frontend/server/evidence-routes.ts:229) searches the first extracted gene and returns target-name/description hits. It does not query disease associations or underlying GWAS evidence. Its source string contains `v24`, but the called URL is `/api/v4/graphql`; neither label proves a pinned dataset release. [STRING adapter](/Users/kky/biomate-review/frontend/server/evidence-routes.ts:262) fetches a network. [Route registration](/Users/kky/biomate-review/frontend/server/routes.ts:1405) verifies server wiring in this checkout; it does not verify deployment, invocation by general findings generation, external success, or citation-grounded synthesis.

Use separate status fields for **inventoried** (an available source/object), **ingested** (a parsed/versioned local artifact), **optimized** (verified batches/losses exposed an identified checkpoint to that artifact), and **retrieved** (a recorded request returned evidence used in a response). Add **skill executed** separately if plugin usage itself matters. These stages are not interchangeable and need not occur in that order: live retrieval need not train the model, and a training prior need not be queried live. Mark unknown stages unknown rather than infer them from filenames, function names or the presence of a source on the requested skills list.
