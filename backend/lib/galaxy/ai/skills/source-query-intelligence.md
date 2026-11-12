---
name: source-query-intelligence
title: Source Query Intelligence
triggers: [database, data source, which source, retrieve, look up, lookup, query, chembl, uniprot, clinvar, gnomad, interpro, surechembl, open targets, sar, structure-activity, potency, affinity, ic50, ki, binding, inhibitor, ligand, target, druggable, pathway, signalling, signaling, interaction, interaction partner, network, variant, mutation, allele, allele frequency, phenotype, protein domain, structure, ortholog, accession, identifier, patent, mechanism, activity]
domains: [drug_discovery, pharmacology, biochemistry, genomics, systems_biology, structural_biology, clinical_genomics]
---

# Source Query Intelligence

**Companion to `evidence-source-selection.md`.** That skill picks *which* sources a
question needs (facet → source). This skill says *how to query each source well* —
the right endpoint per use case, the identifier it expects, and the pitfalls — so the
federated layer stops querying databases naively and getting empty/garbage back.

Every endpoint below was verified live (curl) on 2026-11-11. Full per-source audits:
`docs/20261111_SOURCE_QUERY_INTELLIGENCE/source_intel_*.md`.

## The core principle: resolve, then route

Most databases do **not** accept a bare gene symbol. A target like `ABL1` must first be
resolved to the identifier each source consumes, then the use-case-specific endpoint is
called. One shared, cached resolver should produce the whole identity chain once:

```
symbol → { entrez, ensembl_gene (ENSG), uniprot_acc, string_id, chembl_target_id }
```

Verified chain: `ABL1 → Entrez 25 / ENSG00000097007 / UniProt P00519 / CHEMBL1862`, which
then unlocks AlphaFold (`/prediction/P00519`), PDBe best structures (`1opl`@3.42Å),
InterPro domains, STRING partners, ChEMBL activities, gnomAD, and Open Targets. Without the
resolver, all of those return **empty** for a bare symbol. Build/caller: thread the
resolved ids into each fetcher; never re-resolve per source.

## Per-source query recipes (use case → endpoint)

### Chemistry / drug discovery
- **ChEMBL** — target SAR is a 2-step: `target/search?q={gene}` → filter `organism=Homo sapiens`
  → `target_chembl_id`, then `activity?target_chembl_id={id}&standard_type=IC50&pchembl_value__gte=6`
  (the IC50/Ki table IS the medchem answer). `molecule/search?q=` only for a compound *name*.
- **PubChem** — compound name/CID only: `/rest/pug/compound/name/{name}/property/...`. Never a gene.
- **ChEBI** — live endpoint is `/chebi/backend/api/public/es_search/?term={q}&size=5` (the old
  `searchId.do` / `webservices/chebi/2.0/lite` are retired → HTML). Compound ontology only.
- **BindingDB** — `getLigandsByUniprot` (singular; the plural `…proTS` 404s); response nested
  under the typo key `getLindsByUniprotResponse.bdb.affinities[]`. Keyed by UniProt acc.
- **SureChEMBL** — free-text is pure noise (`ABL1` → 95M junk). Patents only via chemistry:
  ChEMBL target → active compound SMILES → structure search → patents. Do NOT free-text it.
- **Pharos** — GraphQL `pharos-api.ncats.io`; druggability tier (Tclin/Tchem/…) by target.

### Structure / protein
- **UniProt** — gene→acc: `search?query=gene_exact:{sym}+AND+organism_id:9606+AND+reviewed:true&fields=accession`.
- **PDB (RCSB)** — a bare symbol is NOT a PDB id (real ids are `^[1-9][A-Za-z0-9]{3}$`). For a
  target, resolve→UniProt then PDBe best_structures; text search uses `request_options.paginate`.
  Read resolution from `rcsb_entry_info.resolution_combined[0]`.
- **PDBe** — `/pdbe/api/mappings/best_structures/{uniprot_acc}` returns ranked experimental
  structures (killer endpoint; currently unused — add the fetcher).
- **AlphaFold** — needs a UniProt acc: `/api/prediction/{acc}`. Empty for a bare symbol.
- **InterPro** — domains: `/entry/interpro?search={q}&page_size=5` (the `/entry/?search=` path
  returns a counts summary with no `results[]` → always empty).

### Gene / genomics
- **mygene.info** — alias-safe resolution is a POST to `/v3/query` with
  `scopes=symbol,alias,retired` (plain `q=symbol:` misses `p53`, `BCR-ABL`, `HER2`, `CD20`);
  batch all symbols in one call; `fields=entrezgene,ensembl.gene,uniprot.Swiss-Prot,homologene`.
- **NCBI Gene** — E-utils; pass `&api_key=` + tool/email; don't hardcode human.
- **Ensembl** — `xrefs/symbol/{species}/{sym}` (filter out `LRG_*`); supports non-human.
- **STRING** — after resolving to a STRING id, call
  `interaction_partners?identifiers={id}&species={taxid}&required_score=700&caller_identity=biomate`
  (resolution alone returns no partners and no score).

### Pathway / function / ontology
- **KEGG** — gene→pathway chain: `conv/hsa/ncbi-geneid:{entrez}` → `link/pathway/{hsa:id}`
  (bare `find/pathway/{text}` gives generic `map#####`). TSV, ~3 req/s, academic-only licence.
- **Reactome** — `data/mapping/UniProt/{acc}/pathways?species=9606`; strip `<span>` markup from names.
- **GO** — use QuickGO `/QuickGO/services/ontology/go/search?query={q}&limit=5` (the
  `api.geneontology.org/.../autocomplete` path returns non-human gene products + garbage ids).
- **HPO** — `ontology.jax.org/api/hp/search?q={q}&limit=5` (the old `hpo.jax.org/api/hpo/search`
  now serves SPA HTML → every call fails). Phenotype→gene via Monarch v3
  `entity/{HP:id}/biolink:GeneToPhenotypicFeatureAssociation`.

### Variant / clinical
- **ClinVar** — route the fan-out through `lookup_clinvar_gene(pathogenic_only=False)`; keep
  clinical_significance + condition from the esummary (don't discard them). CLNSIG filter is
  needed for risk-factor/benign/VUS (e.g. LRRK2 G2385R "risk factor").
- **dbSNP** — parse gene/MAF/clinsig from the esummary you already fetch (not just `title`).
- **gnomAD** — GraphQL `variant(variantId:"{chr-pos-ref-alt}",dataset:gnomad_r4){genome{af ac an populations}}`;
  popmax over TOP-LEVEL populations only (the array mixes in `_XX`/`_XY` sex subpops). Mind assembly.
- **Open Targets** — GraphQL `api.platform.opentargets.org/api/v4/graphql`; target→disease
  association + L2G; reach it from the fan-out, not only the target_id path.
- **ClinicalTrials.gov** — API **v2** (`query.cond`/`query.intr`/`filter.overallStatus`), not v1.
- **OMIM** — needs a registered key; keyless Monarch/mygene cover IDs/phenotypes, not OMIM text.

### Literature
- **Europe PMC** should be the PRIMARY recall source (keyless, PubMed superset): `resultType=lite`,
  `sort=CITED desc` or `P_PDATE_D`, field tags `TITLE:`/`ABSTRACT:`, `SRC:PPR` for preprints (bioRxiv).
- **Crossref** — add `&mailto=` (polite pool 1→3 req/s, verified) and `query.bibliographic=`.
- **OpenAlex** — add `&mailto=` as a query param (UA alone doesn't guarantee the polite pool).
- **PubMed (E-utils)** — gene symbols need `[tiab]`, not `[MeSH Terms]` (`"BRCA1"[MeSH]`→0).
  Add a shared token-bucket (3 req/s keyless, 10 with `NCBI_API_KEY`) + Retry-After backoff.
- **Semantic Scholar** — keyless `paper/search` 429s constantly; gated OFF until
  `SEMANTIC_SCHOLAR_API_KEY` is set (3 call sites: literature client, federated fetcher,
  `_fetch_s2_paper` enrichment).
- Dedup across sources by normalized DOI/PMID (title[:60] lets a paper survive 3×).

## Cross-cutting rules
- One shared **identifier resolver** (symbol→Entrez/ENSG/UniProt/StringID), cached 24h.
- Enforce **species/assembly** discipline (taxid, GRCh37/38, gnomad_r2/r4) — don't hardcode human.
- Rate-limited/keyless sources (NCBI, Crossref, OpenAlex) share a **token bucket + backoff**.
- Keep each source to the entity class it serves (the registry `entity_types` + the
  `_drop_mismatched_sources` / key-gate filters already enforce this).
