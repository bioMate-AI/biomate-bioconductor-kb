"""RCSB metadata for the complex library (workstream K3): UniProt accessions per receptor chain, primary citation (DOI, title,
year), resolution/method, and PDB-deposited binding affinities. Source: RCSB Data API GraphQL (open, no credentials).
Everything fetched is stored verbatim with the retrieval date; nothing is inferred."""
from __future__ import annotations

import json
import time
import urllib.request
from typing import Dict, List

GQL = "https://data.rcsb.org/graphql"
QUERY = """
query($ids:[String!]!){ entries(entry_ids:$ids){
  rcsb_id
  struct{ title }
  exptl{ method }
  rcsb_entry_info{ resolution_combined }
  rcsb_primary_citation{ pdbx_database_id_DOI pdbx_database_id_PubMed title year journal_abbrev }
  rcsb_binding_affinity{ comp_id type value unit provenance_code }
  polymer_entities{
    rcsb_polymer_entity{ pdbx_description }
    entity_poly{ pdbx_seq_one_letter_code_can rcsb_entity_polymer_type }
    rcsb_polymer_entity_container_identifiers{ auth_asym_ids reference_sequence_identifiers{ database_name database_accession } }
    rcsb_entity_source_organism{ ncbi_scientific_name }
  }
}}"""


def fetch_meta(ids: List[str], retries: int = 3) -> List[Dict]:
    body = json.dumps({"query": QUERY, "variables": {"ids": ids}}).encode()
    for k in range(retries):
        try:
            req = urllib.request.Request(GQL, data=body, headers={"Content-Type": "application/json"})
            d = json.load(urllib.request.urlopen(req, timeout=60))
            if "errors" in d and not d.get("data"):
                raise RuntimeError(str(d["errors"])[:200])
            return [e for e in (d.get("data", {}).get("entries") or []) if e]
        except Exception:
            if k == retries - 1:
                raise
            time.sleep(2 * (k + 1))
    return []


def chain_uniprot(entry: Dict) -> Dict[str, List[str]]:
    """auth chain id -> sorted UniProt accessions (database_name == 'UniProt')."""
    out: Dict[str, List[str]] = {}
    for pe in entry.get("polymer_entities") or []:
        ci = pe.get("rcsb_polymer_entity_container_identifiers") or {}
        accs = sorted({r["database_accession"] for r in (ci.get("reference_sequence_identifiers") or []) if r.get("database_name") == "UniProt"})
        for ch in ci.get("auth_asym_ids") or []:
            out[ch] = accs
    return out


def chain_desc(entry: Dict) -> Dict[str, str]:
    out: Dict[str, str] = {}
    for pe in entry.get("polymer_entities") or []:
        ci = pe.get("rcsb_polymer_entity_container_identifiers") or {}
        desc = ((pe.get("rcsb_polymer_entity") or {}).get("pdbx_description")) or ""
        for ch in ci.get("auth_asym_ids") or []:
            out[ch] = desc
    return out


def fetch_all(ids: List[str], batch: int = 50) -> Dict[str, Dict]:
    out: Dict[str, Dict] = {}
    for i in range(0, len(ids), batch):
        for e in fetch_meta(ids[i:i + batch]):
            out[e["rcsb_id"].upper()] = e
        time.sleep(0.2)
    return out


def text_search(query: str, rows: int = 100) -> List[str]:
    """RCSB full-text search -> entry ids (used for targets without a reference structure, e.g. a GPCR)."""
    q = {"query": {"type": "terminal", "service": "full_text", "parameters": {"value": query}},
         "return_type": "entry", "request_options": {"paginate": {"start": 0, "rows": rows}}}
    url = "https://search.rcsb.org/rcsbsearch/v2/query?json=" + urllib.parse.quote(json.dumps(q))
    d = json.load(urllib.request.urlopen(url, timeout=60))
    return [r["identifier"] for r in d.get("result_set", [])]


import urllib.parse  # noqa: E402  (kept at bottom: used by text_search only)
