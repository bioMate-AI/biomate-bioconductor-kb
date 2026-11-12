"""Canonical BioMate data-source registry — the single source of truth.

BioMate integrates external data sources (the counts are generated, see ``summary()`` and
``scripts/source_registry_report.py``; do not quote a hand-typed number), historically spread across four
disconnected lists that drifted apart:

  1. ``federated_query._FETCHERS``            — the parallel fan-out (chat / research agent)
  2. ``ai_assistant.query_database`` handlers  — single-source lookups
  3. the MCP ``query_database`` enum           — external clients (ChatGPT connector)
  4. 30 Galaxy native ``data_source/*.xml``    — UCSC / BioMart / InterMine (tool UI only)

Symptoms of the drift this module exists to kill:
  * MCP advertised ``omim`` with **no** backing handler → "Unknown database: omim".
  * ``pubchem`` had a real handler but was **single-source only** — unreachable from
    the fan-out, so chat's federated compound queries silently missed PubChem.

This module declares every source once. Surfaces should be *generated from* or
*checked against* it (see ``registry_drift``) instead of hand-maintained. It is
import-only (no network, no heavy deps) so it is safe to load anywhere, incl.
Python 3.9 on dev.

See docs/20260728_UNIFIED_DATA_SOURCE_REGISTRY.md.
"""
from typing import Dict, List, Optional

# ── Surfaces a source can be reached from ───────────────────────────────────────
SURFACE_FEDERATION = "federation"       # federated_query fan-out (chat + research agent)
SURFACE_SINGLE = "single_source"        # ai_assistant.query_database single handler
SURFACE_MCP = "mcp"                     # MCP query_database enum (external clients)
SURFACE_GALAXY_TOOL = "galaxy_tool"     # Galaxy native data_source XML tool (UI)
SURFACE_DEDICATED = "dedicated_tool"   # reached through its own chat/MCP tool or agent (not the generic fan-out)


class DataSource:
    """One external data source and where it is reachable from."""

    def __init__(self, id, name, category, entity_types, surfaces,
                 status="live", note=""):
        self.id = id
        self.name = name
        self.category = category            # e.g. "literature", "compound", "gene"
        self.entity_types = list(entity_types)
        self.surfaces = list(surfaces)
        self.status = status                # "live" | "planned" | "key_required"
        self.note = note

    def to_dict(self) -> Dict:
        return {
            "id": self.id,
            "name": self.name,
            "category": self.category,
            "entity_types": self.entity_types,
            "surfaces": self.surfaces,
            "status": self.status,
            "note": self.note,
        }


# ── Programmatic (REST) sources — what the assistant can actually CALL ───────────
# entity_types drive federated routing; surfaces record which paths back the source.
_REST: List[DataSource] = [
    DataSource("ncbi_gene", "NCBI Gene", "gene", ["gene"],
               [SURFACE_FEDERATION, SURFACE_SINGLE, SURFACE_MCP]),
    DataSource("ensembl", "Ensembl", "gene", ["gene"],
               [SURFACE_FEDERATION, SURFACE_SINGLE, SURFACE_MCP]),
    DataSource("uniprot", "UniProt", "protein", ["gene", "protein"],
               [SURFACE_FEDERATION, SURFACE_SINGLE, SURFACE_MCP]),
    DataSource("pdb", "RCSB PDB", "structure", ["protein", "structure"],
               [SURFACE_FEDERATION, SURFACE_SINGLE, SURFACE_MCP]),
    DataSource("pdbe", "PDBe", "structure", ["protein", "structure"],
               [SURFACE_FEDERATION, SURFACE_SINGLE, SURFACE_MCP],
               note="best_structures (ranked experimental PDBs by resolution/coverage); "
                    "wired to the fan-out via the shared resolver 2026-11-11."),
    DataSource("alphafold", "AlphaFold DB", "structure", ["protein", "structure"],
               [SURFACE_FEDERATION, SURFACE_SINGLE, SURFACE_MCP]),
    DataSource("interpro", "InterPro", "protein", ["protein", "structure"],
               [SURFACE_FEDERATION, SURFACE_SINGLE, SURFACE_MCP]),
    DataSource("string", "STRING", "interaction", ["gene", "protein"],
               [SURFACE_FEDERATION, SURFACE_SINGLE, SURFACE_MCP]),
    DataSource("kegg", "KEGG", "pathway", ["gene", "compound", "pathway"],
               [SURFACE_FEDERATION, SURFACE_SINGLE, SURFACE_MCP]),
    DataSource("reactome", "Reactome", "pathway", ["pathway"],
               [SURFACE_FEDERATION, SURFACE_SINGLE, SURFACE_MCP]),
    DataSource("go", "Gene Ontology", "function", ["gene", "protein", "pathway"],
               [SURFACE_FEDERATION, SURFACE_SINGLE, SURFACE_MCP]),
    DataSource("hpo", "Human Phenotype Ontology", "disease", ["disease"],
               [SURFACE_FEDERATION, SURFACE_SINGLE, SURFACE_MCP]),
    DataSource("chebi", "ChEBI", "compound", ["compound"],
               [SURFACE_FEDERATION, SURFACE_SINGLE, SURFACE_MCP]),
    DataSource("chembl", "ChEMBL", "compound", ["protein", "compound"],
               [SURFACE_FEDERATION, SURFACE_SINGLE, SURFACE_MCP]),
    DataSource("pubchem", "PubChem", "compound", ["compound"],
               [SURFACE_FEDERATION, SURFACE_SINGLE, SURFACE_MCP],
               note="Wired into the fan-out 2026-07-28 (was single-source only)."),
    DataSource("bindingdb", "BindingDB", "compound", ["compound", "protein"],
               [SURFACE_SINGLE, SURFACE_MCP]),
    DataSource("pharos", "Pharos", "gene", ["gene", "protein", "disease"],
               [SURFACE_SINGLE, SURFACE_MCP]),
    DataSource("gnomad", "gnomAD", "variant", ["gene", "variant"],
               [SURFACE_FEDERATION, SURFACE_SINGLE, SURFACE_MCP]),
    DataSource("dbsnp", "dbSNP", "variant", ["variant"],
               [SURFACE_FEDERATION, SURFACE_SINGLE, SURFACE_MCP]),
    DataSource("clinvar", "ClinVar", "variant", ["variant", "disease"],
               [SURFACE_FEDERATION, SURFACE_SINGLE, SURFACE_MCP]),
    DataSource("pubmed", "PubMed", "literature", ["literature", "disease"],
               [SURFACE_FEDERATION, SURFACE_SINGLE]),
    DataSource("europepmc", "Europe PMC", "literature", ["literature", "disease"],
               [SURFACE_FEDERATION, SURFACE_SINGLE]),
    DataSource("semantic_scholar", "Semantic Scholar", "literature", ["literature"],
               [SURFACE_FEDERATION, SURFACE_SINGLE]),
    DataSource("openalex", "OpenAlex", "literature", ["literature"],
               [SURFACE_FEDERATION, SURFACE_SINGLE]),
    DataSource("crossref", "Crossref", "literature", ["literature"],
               [SURFACE_FEDERATION],
               note="Publisher metadata for ~150M works; also used to check that a cited DOI exists. Declared 2026-11-02: the fetcher was already wired."),
    DataSource("corpus_fs", "Local corpus index (corpus_fs)", "literature", ["literature"],
               [SURFACE_FEDERATION],
               note="Grounded SQLite FTS5 index over documents ingested into this deployment. Returns nothing until a corpus is ingested "
                    "(none is loaded by default). Declared 2026-11-02: the fetcher was already wired."),
    # ── Known gaps — declared as planned so they are visible, not forgotten ──
    DataSource("clinicaltrials", "ClinicalTrials.gov", "clinical", ["disease", "compound"],
               [SURFACE_FEDERATION],
               note="Official API v2 (keyless). Registry records: status, phase, sponsor, stated stop reason; not trial results or outcomes. "
                    "A full local mirror (609,551 studies) also exists in S3 for analysis."),
    DataSource("biorxiv", "bioRxiv / medRxiv", "literature", ["literature"],
               [SURFACE_FEDERATION],
               note="Preprints (not peer reviewed), keyword-searched through Europe PMC with a publisher filter; "
                    "the bioRxiv API itself has no keyword search. Rows carry peer_reviewed=false."),
    DataSource("opentargets", "Open Targets", "gene", ["gene", "disease"],
               [SURFACE_DEDICATED],
               note="Live, but not a federated fetcher: the GraphQL platform API is the primary channel of the target-ID engine "
                    "(identify_targets, target_id/data_channels.py OpenTargetsGeneticsChannel) and supplies gene-disease association and "
                    "locus-to-gene scores to the research agent."),
    DataSource("geo", "NCBI GEO", "dataset", ["dataset"],
               [SURFACE_DEDICATED],
               note="Accession retrieval is live: resolve_accession (GSE/GSM/GDS -> Geo Data Connector workflow with pre-filled params) and the "
                    "GEO fast paths in ai_assistant (platform detection, bulk and scRNA connectors). Keyword search for datasets "
                    "(discovery) is NOT implemented."),
    DataSource("paperclip", "Paperclip (8M+ papers, preprints, FDA, ClinicalTrials.gov)", "literature", ["literature", "gene", "disease"],
               [SURFACE_FEDERATION], status="key_required",
               note="Hosted service (paperclip.gxl.ai); needs PAPERCLIP_API_KEY; disabled in offline/on-prem mode. "
                    "Client: galaxy/ai/paperclip_client.py (MCP over HTTP)."),
    DataSource("omim", "OMIM", "disease", ["disease"],
               [], status="key_required",
               note="MCP enum advertised omim with NO handler — removed 2026-07-28. "
                    "Real integration needs an OMIM API key."),
]

# ── Galaxy native data-source tools (reachable via the Galaxy tool UI) ───────────
# id -> display name. Surfaced as galaxy_tool; not yet bridged to the assistant.
_GALAXY_TOOLS = [
    ("ucsc_tablebrowser", "UCSC Table Browser"),
    ("ucsc_tablebrowser_test", "UCSC Table Browser (test)"),
    ("ucsc_tablebrowser_archaea", "UCSC Table Browser (archaea)"),
    ("biomart", "BioMart"),
    ("biomart_test", "BioMart (test)"),
    ("gramene_mart", "Gramene Mart"),
    ("cbi_rice_mart", "CBI Rice Mart"),
    ("hapmapmart", "HapMap BioMart"),
    ("flymine", "FlyMine"),
    ("flymine_test", "FlyMine (test)"),
    ("modmine", "modMine"),
    ("mousemine", "MouseMine"),
    ("ratmine", "RatMine"),
    ("yeastmine", "YeastMine"),
    ("zebrafishmine", "ZebrafishMine"),
    ("metabolicmine", "MetabolicMine"),
    ("intermine", "InterMine"),
    ("wormbase", "WormBase"),
    ("wormbase_test", "WormBase (test)"),
    ("fly_modencode", "modENCODE (fly)"),
    ("worm_modencode", "modENCODE (worm)"),
    ("eupathdb", "EuPathDB"),
    ("ebi_sra", "EBI SRA"),
    ("sra", "NCBI SRA"),
    ("genbank", "GenBank"),
    ("ncbi_datasets", "NCBI Datasets"),
    ("hbvar", "HbVar"),
    ("diced", "DICED"),
    ("microbial_import", "Microbial Import"),
    ("access_libraries", "Access Libraries"),
]

SOURCES: List[DataSource] = list(_REST) + [
    DataSource(tid, tname, "galaxy_data_source", [], [SURFACE_GALAXY_TOOL])
    for tid, tname in _GALAXY_TOOLS
]


# ── Introspection API (self-awareness — "what does BioMate have?") ───────────────
def list_data_sources(category: Optional[str] = None,
                       entity_type: Optional[str] = None,
                       surface: Optional[str] = None,
                       status: Optional[str] = None) -> List[Dict]:
    """Return the registry (optionally filtered) as plain dicts. This is the
    catalog the assistant introspects instead of guessing what it can reach."""
    out = []
    for s in SOURCES:
        if category and s.category != category:
            continue
        if entity_type and entity_type not in s.entity_types:
            continue
        if surface and surface not in s.surfaces:
            continue
        if status and s.status != status:
            continue
        out.append(s.to_dict())
    return out


def by_id(source_id: str) -> Optional[Dict]:
    for s in SOURCES:
        if s.id == source_id:
            return s.to_dict()
    return None


def summary() -> Dict:
    """One-glance counts by surface + status — for the introspection tool."""
    live = [s for s in SOURCES if s.status == "live"]
    return {
        "total": len(SOURCES),
        "live": len(live),
        "planned": len([s for s in SOURCES if s.status == "planned"]),
        "by_surface": {
            SURFACE_FEDERATION: len([s for s in live if SURFACE_FEDERATION in s.surfaces]),
            SURFACE_SINGLE: len([s for s in live if SURFACE_SINGLE in s.surfaces]),
            SURFACE_MCP: len([s for s in live if SURFACE_MCP in s.surfaces]),
            SURFACE_GALAXY_TOOL: len([s for s in live if SURFACE_GALAXY_TOOL in s.surfaces]),
            SURFACE_DEDICATED: len([s for s in live if SURFACE_DEDICATED in s.surfaces]),
        },
    }


def registry_drift() -> Dict:
    """Compare the registry's declared federation sources against the ACTUAL
    ``federated_query._FETCHERS`` keys. Any mismatch is drift — a source the
    registry claims the fan-out has but doesn't, or vice-versa. Callable from a
    cheap unit test so a future edit that re-introduces drift fails CI.

    Returns {"in_sync": bool, "declared_not_wired": [...], "wired_not_declared": [...]}.
    """
    declared = {s.id for s in SOURCES if SURFACE_FEDERATION in s.surfaces}
    try:
        from galaxy.ai.federated_query import _FETCHERS
        wired = set(_FETCHERS.keys())
    except Exception as e:  # pragma: no cover - import guard
        return {"in_sync": False, "error": "cannot import _FETCHERS: %s" % e}
    declared_not_wired = sorted(declared - wired)
    wired_not_declared = sorted(wired - declared)
    return {
        "in_sync": not declared_not_wired and not wired_not_declared,
        "declared_not_wired": declared_not_wired,
        "wired_not_declared": wired_not_declared,
    }
