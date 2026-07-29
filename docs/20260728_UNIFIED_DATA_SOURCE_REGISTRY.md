# Unified Data-Source Registry — BioMate has 60+ sources across 3 siloed layers

**Date:** 2026-07-28
**Status:** Finding + proposal (Phase-1 data-plane follow-up)
**Related:** `docs/20260727_RFC_ARCHITECTURE_EVOLUTION.md` (self-awareness registry + unified data plane), `docs/20260727_UNIFIED_SEARCH_AND_DATA_INTEGRATION_PLAN.md`

## TL;DR

BioMate already integrates **60+ external data sources**, but they live in **three
disconnected registries** that don't know about each other. The chat assistant's
federated search reaches only **20 of them**. Even among *implemented* sources, the
lists have drifted: MCP exposes `pubchem` + `omim` that the federation lacks, and
"bioRxiv" — which we assumed we had — is **not wired anywhere** (only journal-name
strings in seed data). This is the concrete face of "BioMate doesn't know what it has."

The fix is not "add a few adapters." It is **one canonical source registry** that every
surface (chat federation, MCP, research agent, Galaxy tool UI) routes through, so the
lists can't drift and all 60+ are discoverable from one place.

## Verified inventory (2026-07-28)

| Layer | Count | Reachable from | Sources |
|---|---|---|---|
| Galaxy native data-source tools (`backend/tools/data_source/*.xml`) | **30** | Galaxy tool UI **only** | UCSC Table Browser (main/test/archaea), BioMart (+test), the InterMine family (flymine, mousemine, ratmine, wormbase, yeastmine, zebrafishmine, metabolicmine, modmine, intermine, cbi_rice_mart, gramene_mart, hapmapmart), eupathdb, ebi_sra, sra, genbank, ncbi_datasets, fly/worm modENCODE, hbvar, diced, microbial_import, access_libraries |
| `federated_query.py` `_FETCHERS` | **20** | Research agent + chat literature/federation | ncbi_gene, ensembl, uniprot, pdb, alphafold, interpro, string, kegg, reactome, go, hpo, chebi, chembl, gnomad, dbsnp, clinvar, pubmed, europepmc, semantic_scholar, openalex |
| MCP `query_database` enum (`backend/lib/mcp/tools_manifest.json`) | **14** | MCP clients (ChatGPT connector, etc.) | uniprot, pdb, alphafold, ncbi_gene, dbsnp, clinvar, gnomad, kegg, reactome, chebi, **pubchem**, hpo, **omim**, string |

Deduped across layers: **~55–60 distinct sources**. The three layers are nearly disjoint
— Galaxy's are interactive UCSC/BioMart/InterMine tools; the federation's are programmatic
REST APIs; MCP is its own hand-maintained enum.

## The problem, precisely

1. **Chat sees 20 of 60+.** The 30 Galaxy data-source tools are invisible to the AI —
   a user can only reach UCSC/BioMart/InterMine by clicking in the Galaxy tool UI.
2. **The implemented lists drift.** `query_database` (MCP) lists `pubchem` and `omim`;
   `federated_query.py` does not. Same platform, two hand-maintained lists, already out of sync.
3. **Assumed-present sources are absent.** bioRxiv/medRxiv have **no fetcher** — the exact
   gap behind the PEX literature miss (`long_query.md`). PubChem and Open Targets exist only
   inside the drug-discovery modules (`commercial_availability.py`, `api_router.py`),
   unreachable from general chat.

## Proposal — one registry, generated surfaces

Define a single canonical `SOURCES` registry (one row per source):

```
{ id, display_name, entity_types: [...], surface: {rest_fetcher | galaxy_tool_id | mcp},
  endpoint | tool_ref, auth, rate_limit, status }
```

Then **generate** the per-surface artifacts from it instead of hand-maintaining three lists:
- `federated_query._FETCHERS` + `ENTITY_SOURCES` routing
- MCP `query_database` enum in `tools_manifest.json`
- A `list_data_sources` capability the assistant can introspect (self-awareness)

Adding a source becomes one registry row; every surface picks it up. Divergence becomes
impossible by construction.

### Sequencing
1. **Canonicalize** — lift the 20 federation fetchers + 14 MCP entries into one registry;
   reconcile the drift (add pubchem + omim fetchers to the federation).
2. **Generate** the MCP enum + federation tables from the registry; add a `list_data_sources`
   introspection tool (closes "doesn't know what it has").
3. **Fill the real gaps** — bioRxiv/medRxiv (the PEX gap), Open Targets, GEO/SRA (dataset
   discovery), EMDB/PDBe (cryo-EM). ~1 adapter each.
4. **Bridge Galaxy's 30** — expose the native data-source tools to the assistant via the
   registry (tool_ref surface), so chat can drive UCSC/BioMart/InterMine too.

## Shipped 2026-07-28 (first reconciliation chunk)

The registry now exists and the first drift is reconciled — this is no longer just a proposal:

- **`backend/lib/galaxy/ai/data_sources.py`** — canonical registry. 54 live sources
  (21 federation + 24 single-source + 20 MCP + 30 Galaxy, with overlap) + 3 declared-planned
  gaps (bioRxiv, Open Targets, GEO) + omim marked `key_required`. Import-only, 3.9-safe.
  Exposes `list_data_sources()`, `summary()`, `by_id()`, `registry_drift()`.
- **PubChem wired into the fan-out** — it had a real `_query_pubchem` handler but was
  single-source only, so chat's *federated* compound queries silently missed it. Added
  `_fetch_pubchem` to `_FETCHERS` + `ENTITY_SOURCES["compound"]`. Verified live: aspirin → CID 2244.
- **MCP `omim` drift fixed** — the enum advertised `omim` with **no** backing handler
  (`Unknown database: omim`). Removed it and added the backed handlers the enum was missing
  (pdbe, interpro, ensembl, go, chembl, bindingdb, pharos). All 4 manifest copies regenerated
  from `tools_manifest.py` (the canonical source).
- **Guard against regression** — `registry_drift()` + `backend/tests/test_data_source_registry.py`
  assert the registry's federation set stays exactly `== _FETCHERS` keys, so re-introducing
  silent drift fails CI.

Still open (next chunks): a `list_data_sources` introspection tool so the *assistant* can read
the registry (self-awareness surface); generate the MCP enum + federation tables FROM the
registry (not just check against it); fill the planned gaps (bioRxiv first); bridge Galaxy's 30.

## Relation to Phase-1 work already landed

- `search_literature` (federated external literature) — landed, live.
- `search_my_data` + `/api/data/search` (the user's **own** uploads + run outputs, unified
  cross-project catalog) — landed on `next-phase`, deploying. This is the *internal* half of
  the unified data plane; the source registry above is the *external* half. Together they give
  the assistant one answer to "what data can I reach?" — the client's and the world's.
