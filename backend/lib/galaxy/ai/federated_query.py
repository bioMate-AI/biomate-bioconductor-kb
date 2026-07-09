"""
federated_query.py — parallel multi-source biological database queries.

Replaces the single-dispatch query_database() pattern with fan-out execution:
  federated_query("BRCA1") → hits all relevant DBs in parallel, merges results.

Entity types detected automatically:
  gene, protein, compound, variant, pathway, structure, disease, literature

New sources added beyond the existing 16:
  europepmc  — 4M open-access full-text papers (EBI)
  semantic_scholar — citation graph + PDFs (Semantic Scholar API)
  openalex   — 250M works, institution/concept tagging

Redis caching: 24h TTL for stable data (UniProt, PDB), 1h for literature.
Gracefully degrades to no cache if Redis is unavailable.
"""

from __future__ import annotations

import json
import logging
import re
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed, TimeoutError as FuturesTimeout
from typing import Any, Dict, List, Optional, Tuple

log = logging.getLogger(__name__)

_TIMEOUT = 10  # seconds per external call
_POOL_SIZE = 12
_CACHE_TTL_STABLE = 86400   # 24h — UniProt, PDB, AlphaFold, etc.
_CACHE_TTL_LITERATURE = 3600  # 1h — PubMed, EuropePMC, Semantic Scholar

# ── Entity-type → sources fan-out map ─────────────────────────────────────────
# Order within each list doesn't matter (all run in parallel).
# "primary" sources are always included; callers can restrict via `sources=`.

ENTITY_SOURCES: Dict[str, List[str]] = {
    "gene":       ["ncbi_gene", "ensembl", "uniprot", "string", "kegg",
                   "go", "gnomad", "pubmed", "semantic_scholar"],
    "protein":    ["uniprot", "pdb", "alphafold", "interpro", "string",
                   "go", "chembl", "pubmed", "semantic_scholar"],
    "compound":   ["chembl", "chebi", "kegg", "pubmed", "semantic_scholar"],
    "variant":    ["dbsnp", "clinvar", "gnomad", "pubmed", "semantic_scholar"],
    "pathway":    ["kegg", "reactome", "go", "pubmed"],
    "structure":  ["pdb", "alphafold", "interpro"],
    "disease":    ["hpo", "clinvar", "pubmed", "europepmc", "semantic_scholar"],
    "literature": ["pubmed", "europepmc", "semantic_scholar", "openalex"],
}

# ── Redis cache ────────────────────────────────────────────────────────────────

_redis_client = None

def _get_redis():
    global _redis_client
    if _redis_client is not None:
        return _redis_client
    try:
        import os, redis
        url = os.environ.get("REDIS_URL", "")
        if not url:
            return None
        _redis_client = redis.from_url(url, socket_connect_timeout=1, socket_timeout=1)
        _redis_client.ping()
        return _redis_client
    except Exception:
        return None

def _cache_get(key: str) -> Optional[Dict]:
    r = _get_redis()
    if not r:
        return None
    try:
        raw = r.get(key)
        return json.loads(raw) if raw else None
    except Exception:
        return None

def _cache_set(key: str, value: Dict, ttl: int) -> None:
    r = _get_redis()
    if not r:
        return
    try:
        r.setex(key, ttl, json.dumps(value, default=str))
    except Exception:
        pass

# ── HTTP helper ────────────────────────────────────────────────────────────────

def _get(url: str, headers: Optional[Dict] = None) -> Optional[Any]:
    h = {"User-Agent": "BioMate/1.0 (biomate.ai; federated-query)"}
    if headers:
        h.update(headers)
    req = urllib.request.Request(url, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=_TIMEOUT) as resp:
            return json.loads(resp.read().decode())
    except Exception as e:
        log.debug("[federated_query] GET %s → %s", url, e)
        return None

def _post_json(url: str, payload: Dict) -> Optional[Any]:
    body = json.dumps(payload).encode()
    req = urllib.request.Request(
        url, data=body,
        headers={"Content-Type": "application/json",
                 "User-Agent": "BioMate/1.0 (biomate.ai; federated-query)"}
    )
    try:
        with urllib.request.urlopen(req, timeout=_TIMEOUT) as resp:
            return json.loads(resp.read().decode())
    except Exception as e:
        log.debug("[federated_query] POST %s → %s", url, e)
        return None

# ── Entity type detection ──────────────────────────────────────────────────────

def detect_entity_type(query: str) -> str:
    q = query.strip()
    ql = q.lower()

    # Exact-format patterns (highest confidence)
    if re.match(r'^rs\d+$', q, re.I):                          return "variant"
    if re.match(r'^[A-Z][0-9][A-Z0-9]{3}[0-9]$', q.upper()):  return "protein"   # UniProt acc
    if re.match(r'^[A-Za-z0-9]{4}$', q) and not q.isalpha():   return "structure" # PDB ID
    if re.match(r'^GO:\d+$', q, re.I):                         return "pathway"
    if re.match(r'^HP:\d+$', q, re.I):                         return "disease"
    if re.match(r'^CHEMBL\d+$', q, re.I):                      return "compound"
    if re.match(r'^CHEBI:\d+$', q, re.I):                      return "compound"
    if re.match(r'^NM_|^NP_|^NC_|^NG_', q, re.I):             return "gene"
    # SMILES-like: contains brackets + = signs
    if re.search(r'[=#@\[\]()]+', q) and len(q) > 8:          return "compound"

    # Keyword patterns
    if any(w in ql for w in ("variant", "snp", "mutation", "indel", "vus")):
        return "variant"
    if any(w in ql for w in ("drug", "compound", "smiles", "molecule", "inhibitor",
                               "agonist", "antagonist", "ic50", "admet")):
        return "compound"
    if any(w in ql for w in ("pathway", "signaling", "metabolism", "cascade")):
        return "pathway"
    if any(w in ql for w in ("protein", "enzyme", "receptor", "kinase", "domain",
                               "fold", "structure", "crystal")):
        return "protein"
    if any(w in ql for w in ("disease", "syndrome", "disorder", "phenotype",
                               "symptom", "diagnosis")):
        return "disease"
    if any(w in ql for w in ("paper", "article", "publication", "literature",
                               "review", "study", "doi", "pmid")):
        return "literature"

    # All-caps short token → likely gene symbol
    if re.match(r'^[A-Z][A-Z0-9]{1,9}$', q):
        return "gene"

    return "gene"  # sensible default

# ── Per-source fetch functions ─────────────────────────────────────────────────

def _fetch_ncbi_gene(query: str) -> Dict:
    q = urllib.parse.quote(query)
    search = _get(f"https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi"
                  f"?db=gene&term={q}+[gene]+Homo+sapiens[organism]&retmax=5&retmode=json")
    ids = (search or {}).get("esearchresult", {}).get("idlist", [])
    if not ids:
        return {"source": "ncbi_gene", "results": []}
    summary = _get(f"https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi"
                   f"?db=gene&id={','.join(ids)}&retmode=json")
    results = []
    for uid in ids[:3]:
        doc = (summary or {}).get("result", {}).get(uid, {})
        if doc:
            results.append({"gene_id": uid, "symbol": doc.get("name"),
                            "description": doc.get("description"),
                            "organism": doc.get("organism", {}).get("scientificname")})
    return {"source": "ncbi_gene", "results": results}

def _fetch_uniprot(query: str) -> Dict:
    q = urllib.parse.quote(query)
    data = _get(f"https://rest.uniprot.org/uniprotkb/search"
                f"?query={q}+AND+reviewed:true&format=json&size=5")
    results = []
    for e in (data or {}).get("results", [])[:5]:
        names = e.get("proteinDescription", {})
        full = (names.get("recommendedName") or names.get("submissionNames", [{}])[0])
        results.append({
            "accession": e.get("primaryAccession"),
            "id": e.get("uniProtkbId"),
            "name": (full.get("fullName") or {}).get("value"),
            "organism": e.get("organism", {}).get("scientificName"),
            "function": next(
                (c.get("texts", [{}])[0].get("value")
                 for c in e.get("comments", []) if c.get("commentType") == "FUNCTION"),
                None),
        })
    return {"source": "uniprot", "results": results}

def _fetch_pdb(query: str) -> Dict:
    # Try direct 4-char PDB ID first
    if re.match(r'^[A-Za-z0-9]{4}$', query.strip()):
        pdb_id = query.strip().upper()
        data = _get(f"https://data.rcsb.org/rest/v1/core/entry/{pdb_id}")
        if data:
            struct = data.get("struct", {})
            return {"source": "pdb", "results": [
                {"pdb_id": pdb_id, "title": struct.get("title"),
                 "method": data.get("exptl", [{}])[0].get("method"),
                 "resolution": data.get("reflns", {}).get("d_resolution_high")}
            ]}
    # Text search
    payload = {
        "query": {"type": "terminal", "service": "full_text",
                  "parameters": {"value": query}},
        "return_type": "entry", "request_options": {"results_slice": {"start": 0, "rows": 5}}
    }
    data = _post_json("https://search.rcsb.org/rcsbsearch/v2/query", payload)
    ids = [r["identifier"] for r in (data or {}).get("result_set", [])[:5]]
    return {"source": "pdb", "results": [{"pdb_id": i} for i in ids]}

def _fetch_alphafold(query: str) -> Dict:
    # Requires UniProt accession
    if re.match(r'^[A-Z][0-9][A-Z0-9]{3}[0-9]$', query.strip().upper()):
        acc = query.strip().upper()
        data = _get(f"https://alphafold.ebi.ac.uk/api/prediction/{acc}")
        if data and isinstance(data, list):
            d = data[0]
            return {"source": "alphafold", "results": [
                {"uniprot": acc, "model_url": d.get("pdbUrl"),
                 "pae_image_url": d.get("paeImageUrl"),
                 "confidence": "pLDDT"}
            ]}
    return {"source": "alphafold", "results": [],
            "note": "Provide UniProt accession for direct AlphaFold lookup"}

def _fetch_ensembl(query: str) -> Dict:
    if re.match(r'^[A-Z][A-Z0-9]+$', query.strip()):
        url = (f"https://rest.ensembl.org/xrefs/symbol/homo_sapiens/"
               f"{urllib.parse.quote(query)}?content-type=application/json")
        data = _get(url)
        if data:
            return {"source": "ensembl",
                    "results": [{"id": e.get("id"), "type": e.get("type")} for e in data[:5]]}
    return {"source": "ensembl", "results": []}

def _fetch_string(query: str) -> Dict:
    q = urllib.parse.quote(query)
    data = _get(f"https://string-db.org/api/json/get_string_ids"
                f"?identifiers={q}&species=9606&limit=5&caller_identity=biomate")
    results = [{"protein_id": p.get("stringId"), "gene": p.get("preferredName"),
                "score": p.get("score")} for p in (data or [])[:5]]
    return {"source": "string", "results": results}

def _fetch_kegg(query: str) -> Dict:
    q = urllib.parse.quote(query)
    try:
        with urllib.request.urlopen(
            f"https://rest.kegg.jp/find/pathway/{q}", timeout=_TIMEOUT
        ) as resp:
            text = resp.read().decode()
            results = []
            for line in text.strip().split("\n")[:5]:
                if "\t" in line:
                    pid, name = line.split("\t", 1)
                    results.append({"pathway_id": pid, "name": name})
            return {"source": "kegg", "results": results}
    except Exception:
        return {"source": "kegg", "results": []}

def _fetch_reactome(query: str) -> Dict:
    q = urllib.parse.quote(query)
    data = _get(f"https://reactome.org/ContentService/search/query"
                f"?query={q}&types=Pathway&pageSize=5&page=1")
    results = []
    for r in (data or {}).get("results", [])[:5]:
        for e in r.get("entries", [])[:3]:
            results.append({"id": e.get("stId"), "name": e.get("name"),
                            "species": (e.get("species") or ["Homo sapiens"])[0]})
    return {"source": "reactome", "results": results}

def _fetch_go(query: str) -> Dict:
    if re.match(r'^GO:\d+$', query.strip(), re.I):
        data = _get(f"https://api.geneontology.org/api/ontology/term/{query.strip().upper()}")
        if data:
            return {"source": "go", "results": [
                {"go_id": query.upper(), "name": data.get("label"),
                 "definition": (data.get("definition") or {}).get("val")}
            ]}
    q = urllib.parse.quote(query)
    data = _get(f"https://api.geneontology.org/api/search/entity/autocomplete/{q}"
                f"?rows=5&ontology=go")
    results = [{"go_id": d.get("id"), "name": d.get("label")}
               for d in (data or {}).get("docs", [])[:5]]
    return {"source": "go", "results": results}

def _fetch_hpo(query: str) -> Dict:
    q = urllib.parse.quote(query)
    data = _get(f"https://hpo.jax.org/api/hpo/search?q={q}&max=5&offset=0&category=terms")
    results = [{"hpo_id": t.get("id"), "name": t.get("name"),
                "definition": t.get("definition")}
               for t in (data or {}).get("terms", [])[:5]]
    return {"source": "hpo", "results": results}

def _fetch_chebi(query: str) -> Dict:
    q = urllib.parse.quote(query)
    data = _get(f"https://www.ebi.ac.uk/chebi/searchId.do?chebiId={q}&format=json")
    if not data:
        data = _get(f"https://www.ebi.ac.uk/webservices/chebi/2.0/lite?search={q}&max_results=5")
    return {"source": "chebi", "results": data or []}

def _fetch_chembl(query: str) -> Dict:
    q = urllib.parse.quote(query)
    data = _get(f"https://www.ebi.ac.uk/chembl/api/data/molecule/search"
                f"?q={q}&format=json&limit=5")
    results = []
    for m in (data or {}).get("molecules", [])[:5]:
        props = m.get("molecule_properties") or {}
        results.append({"chembl_id": m.get("molecule_chembl_id"),
                        "name": m.get("pref_name"),
                        "formula": props.get("full_molformula"),
                        "mw": props.get("full_mwt")})
    return {"source": "chembl", "results": results}

def _fetch_interpro(query: str) -> Dict:
    q = urllib.parse.quote(query)
    data = _get(f"https://www.ebi.ac.uk/interpro/api/entry/?search={q}&format=json&page_size=5")
    results = [{"accession": e.get("metadata", {}).get("accession"),
                "name": e.get("metadata", {}).get("name"),
                "type": e.get("metadata", {}).get("type")}
               for e in (data or {}).get("results", [])[:5]]
    return {"source": "interpro", "results": results}

def _fetch_gnomad(query: str) -> Dict:
    gql = """query($term:String!){search(query:$term){
        ...on GeneSearchResult{gene{gene_id gene_name}}
        ...on VariantSearchResult{variant{variant_id}}}}"""
    data = _post_json("https://gnomad.broadinstitute.org/api",
                      {"query": gql, "variables": {"term": query}})
    results = (data or {}).get("data", {}).get("search", [])[:5]
    return {"source": "gnomad", "results": results}

def _fetch_ncbi_entrez(query: str, db: str) -> Dict:
    q = urllib.parse.quote(query)
    search = _get(f"https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi"
                  f"?db={db}&term={q}&retmax=5&retmode=json")
    ids = (search or {}).get("esearchresult", {}).get("idlist", [])
    if not ids:
        return {"source": db, "results": []}
    summary = _get(f"https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi"
                   f"?db={db}&id={','.join(ids)}&retmode=json")
    results = []
    for uid in ids[:5]:
        doc = (summary or {}).get("result", {}).get(uid, {})
        if doc:
            results.append({"id": uid, "title": doc.get("title") or doc.get("name"),
                            "source": db})
    return {"source": db, "results": results}

# ── New literature sources ─────────────────────────────────────────────────────

def _fetch_europepmc(query: str) -> Dict:
    """Europe PMC — 4M open-access full-text papers."""
    q = urllib.parse.quote(query)
    data = _get(f"https://www.ebi.ac.uk/europepmc/webservices/rest/search"
                f"?query={q}&format=json&pageSize=5&resultType=core")
    results = []
    for p in (data or {}).get("resultList", {}).get("result", [])[:5]:
        results.append({
            "pmid": p.get("pmid"),
            "title": p.get("title"),
            "authors": p.get("authorString"),
            "year": p.get("pubYear"),
            "journal": p.get("journalTitle"),
            "is_open_access": p.get("isOpenAccess") == "Y",
            "full_text_url": p.get("fullTextUrlList", {}).get("fullTextUrl", [{}])[0].get("url"),
            "abstract": (p.get("abstractText") or "")[:500],
        })
    return {"source": "europepmc", "results": results}

def _fetch_semantic_scholar(query: str) -> Dict:
    """Semantic Scholar — citation graph, influential papers, open-access PDFs."""
    q = urllib.parse.quote(query)
    fields = "title,authors,year,citationCount,openAccessPdf,abstract"
    data = _get(f"https://api.semanticscholar.org/graph/v1/paper/search"
                f"?query={q}&limit=5&fields={fields}")
    results = []
    for p in (data or {}).get("data", [])[:5]:
        results.append({
            "paper_id": p.get("paperId"),
            "title": p.get("title"),
            "authors": [a.get("name") for a in (p.get("authors") or [])[:3]],
            "year": p.get("year"),
            "citations": p.get("citationCount"),
            "pdf_url": (p.get("openAccessPdf") or {}).get("url"),
            "abstract": (p.get("abstract") or "")[:500],
        })
    return {"source": "semantic_scholar", "results": results}

def _fetch_openalex(query: str) -> Dict:
    """OpenAlex — 250M works, concept tagging, institution filtering."""
    q = urllib.parse.quote(query)
    fields = "title,authorships,publication_year,cited_by_count,open_access,concepts"
    data = _get(f"https://api.openalex.org/works"
                f"?search={q}&per-page=5&select={fields}",
                headers={"User-Agent": "BioMate/1.0 (biomate.ai; mailto:admin@biomate.ai)"})
    results = []
    for w in (data or {}).get("results", [])[:5]:
        authors = [a.get("author", {}).get("display_name")
                   for a in (w.get("authorships") or [])[:3]]
        concepts = [c.get("display_name") for c in (w.get("concepts") or [])[:5]]
        results.append({
            "title": w.get("title"),
            "authors": authors,
            "year": w.get("publication_year"),
            "citations": w.get("cited_by_count"),
            "is_open_access": (w.get("open_access") or {}).get("is_oa"),
            "concepts": concepts,
        })
    return {"source": "openalex", "results": results}

# ── Source dispatch table ──────────────────────────────────────────────────────

_FETCHERS = {
    "ncbi_gene":        _fetch_ncbi_gene,
    "uniprot":          _fetch_uniprot,
    "pdb":              _fetch_pdb,
    "alphafold":        _fetch_alphafold,
    "ensembl":          _fetch_ensembl,
    "string":           _fetch_string,
    "kegg":             _fetch_kegg,
    "reactome":         _fetch_reactome,
    "go":               _fetch_go,
    "hpo":              _fetch_hpo,
    "chebi":            _fetch_chebi,
    "chembl":           _fetch_chembl,
    "interpro":         _fetch_interpro,
    "gnomad":           _fetch_gnomad,
    "dbsnp":            lambda q: _fetch_ncbi_entrez(q, "snp"),
    "clinvar":          lambda q: _fetch_ncbi_entrez(q, "clinvar"),
    "pubmed":           lambda q: _fetch_ncbi_entrez(q, "pubmed"),
    # New sources
    "europepmc":        _fetch_europepmc,
    "semantic_scholar": _fetch_semantic_scholar,
    "openalex":         _fetch_openalex,
}

_LITERATURE_SOURCES = {"pubmed", "europepmc", "semantic_scholar", "openalex"}

# ── Main entry point ───────────────────────────────────────────────────────────

def federated_query(
    query: str,
    entity_type: Optional[str] = None,
    sources: Optional[List[str]] = None,
    timeout: float = 15.0,
    max_results_per_source: int = 5,
) -> Dict:
    """
    Fan-out query to all relevant databases in parallel.

    Args:
        query:       Free-text query or accession (BRCA1, rs12345, P04637, …)
        entity_type: Override auto-detection. One of: gene, protein, compound,
                     variant, pathway, structure, disease, literature.
        sources:     Explicit list of sources to query (skips entity detection).
        timeout:     Wall-clock seconds to wait for all parallel calls.
        max_results_per_source: Trim each source's result list to this length.

    Returns:
        {
          "query": str,
          "entity_type": str,
          "sources_queried": [str, ...],
          "sources_succeeded": [str, ...],
          "sources_failed": [str, ...],
          "results": { source_name: {source, results, ...}, ... },
          "merged": [unified result dicts, sorted by relevance],
        }
    """
    detected = entity_type or detect_entity_type(query)
    target_sources = sources or ENTITY_SOURCES.get(detected, ENTITY_SOURCES["gene"])
    # Filter to known sources only
    target_sources = [s for s in target_sources if s in _FETCHERS]

    cache_key = f"bm:fq:{detected}:{query.lower().strip()}"
    cached = _cache_get(cache_key)
    if cached:
        cached["_cached"] = True
        return cached

    results: Dict[str, Dict] = {}
    succeeded: List[str] = []
    failed: List[str] = []

    with ThreadPoolExecutor(max_workers=_POOL_SIZE) as pool:
        future_to_source = {
            pool.submit(_FETCHERS[src], query): src
            for src in target_sources
        }
        try:
            for future in as_completed(future_to_source, timeout=timeout):
                src = future_to_source[future]
                try:
                    result = future.result()
                    # Trim results
                    if "results" in result and isinstance(result["results"], list):
                        result["results"] = result["results"][:max_results_per_source]
                    results[src] = result
                    succeeded.append(src)
                except Exception as e:
                    log.warning("[federated_query] %s failed: %s", src, e)
                    failed.append(src)
                    results[src] = {"source": src, "error": str(e), "results": []}
        except FuturesTimeout:
            # Sources that didn't finish in time
            for future, src in future_to_source.items():
                if not future.done():
                    failed.append(src)
                    results[src] = {"source": src, "error": "timeout", "results": []}

    merged = _merge_results(results, detected)

    out = {
        "query": query,
        "entity_type": detected,
        "sources_queried": target_sources,
        "sources_succeeded": succeeded,
        "sources_failed": failed,
        "results": results,
        "merged": merged,
    }

    ttl = _CACHE_TTL_LITERATURE if detected == "literature" else _CACHE_TTL_STABLE
    _cache_set(cache_key, out, ttl)
    return out

# ── Result merging ─────────────────────────────────────────────────────────────

def _merge_results(results: Dict[str, Dict], entity_type: str) -> List[Dict]:
    """
    Produce a unified flat list across all sources, deduped by name/id,
    each item annotated with its source.
    """
    seen_names: set = set()
    merged: List[Dict] = []

    # Source priority order for merge (most trusted first)
    priority = {
        "gene":       ["uniprot", "ncbi_gene", "ensembl", "string", "kegg",
                       "go", "gnomad", "pubmed", "semantic_scholar"],
        "protein":    ["uniprot", "pdb", "alphafold", "interpro", "string",
                       "go", "chembl", "pubmed", "semantic_scholar"],
        "compound":   ["chembl", "chebi", "kegg", "pubmed", "semantic_scholar"],
        "variant":    ["clinvar", "dbsnp", "gnomad", "pubmed", "semantic_scholar"],
        "pathway":    ["reactome", "kegg", "go", "pubmed"],
        "structure":  ["pdb", "alphafold", "interpro"],
        "disease":    ["hpo", "clinvar", "europepmc", "pubmed", "semantic_scholar"],
        "literature": ["pubmed", "europepmc", "semantic_scholar", "openalex"],
    }
    ordered = priority.get(entity_type, list(results.keys()))
    remaining = [s for s in results if s not in ordered]

    for src in ordered + remaining:
        if src not in results:
            continue
        for item in (results[src].get("results") or []):
            # Dedup key: prefer explicit id fields, fall back to name/title
            dedup_key = (
                item.get("accession") or item.get("gene_id") or item.get("pdb_id") or
                item.get("pmid") or item.get("chembl_id") or item.get("paper_id") or
                (item.get("title") or item.get("name") or "").lower()[:60]
            )
            if not dedup_key or dedup_key in seen_names:
                continue
            seen_names.add(dedup_key)
            merged.append({"_source": src, **item})

    return merged


def iterative_literature_search(
    query: str,
    max_depth: int = 3,
    min_results: int = 10,
) -> Dict:
    """
    Open Deep Research-style iterative loop over literature sources.

    Searches PubMed + EuropePMC + Semantic Scholar + OpenAlex in parallel,
    detects gaps, and deepens with refined queries until min_results are
    found or max_depth is reached.

    Returns all collected results + the search trace.
    """
    collected: List[Dict] = []
    seen_ids: set = set()
    trace: List[Dict] = []
    current_query = query

    for depth in range(1, max_depth + 1):
        r = federated_query(current_query, entity_type="literature")
        new_items = []
        for item in r.get("merged", []):
            uid = (item.get("pmid") or item.get("paper_id") or
                   (item.get("title") or "").lower()[:60])
            if uid and uid not in seen_ids:
                seen_ids.add(uid)
                new_items.append(item)

        trace.append({
            "depth": depth,
            "query": current_query,
            "sources": r.get("sources_succeeded", []),
            "new_results": len(new_items),
        })
        collected.extend(new_items)

        if len(collected) >= min_results:
            break

        # Gap detection: if fewer than 3 new results, refine the query
        if len(new_items) < 3 and depth < max_depth:
            current_query = f"{query} mechanism review"  # simple refinement
            log.info("[federated_query] depth %d: only %d new results, refining query",
                     depth, len(new_items))

    return {
        "query": query,
        "depth_reached": len(trace),
        "total_results": len(collected),
        "results": collected,
        "trace": trace,
    }


# ── Chemical name → SMILES resolution ─────────────────────────────────────────
# Used by the parameter extraction pipeline to auto-resolve drug/compound names
# to valid SMILES strings before passing them to ADMET or docking workflows.

# Param names that hold SMILES values (checked case-insensitively)
_SMILES_PARAM_NAMES = {
    "smiles", "ligand_smiles", "molecule_smiles", "compound_smiles",
    "query_smiles", "input_smiles", "smiles_string", "smile",
    "ligand", "molecule", "compound",  # common aliases
}

# A value is a chemical name (not SMILES) when it:
#   1. Has no SMILES structural characters
#   2. Looks like a word / drug name
_SMILES_CHARS = re.compile(r'[=\#\(\)\[\]@\+\-/\\%]')
_WORD_LIKE = re.compile(r'^[a-zA-Z0-9\s\-,]+$')


def _looks_like_chemical_name(value: str) -> bool:
    """Return True if value is probably a drug/compound name rather than a SMILES string."""
    v = value.strip()
    if len(v) < 2 or len(v) > 120:
        return False
    if _SMILES_CHARS.search(v):
        return False          # contains SMILES structural notation → it's a SMILES
    if v.startswith("InChI="):
        return False          # InChI string
    return bool(_WORD_LIKE.match(v))


def resolve_chemical_name(name: str) -> Optional[str]:
    """
    Given a compound/drug name (e.g. "imatinib", "aspirin", "caffeine"),
    return its canonical isomeric SMILES string via PubChem PUG REST.

    Returns None if not found or on error (caller should keep original value).
    Cached in Redis for 7 days (compound→SMILES is stable).
    """
    name = name.strip()
    cache_key = f"bm:chem2smi:{name.lower()}"
    cached = _cache_get(cache_key)
    if cached:
        return cached.get("smiles")

    encoded = urllib.parse.quote(name)
    # PubChem name lookup — returns canonical + isomeric SMILES
    url = (f"https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/name/"
           f"{encoded}/property/IsomericSMILES,CanonicalSMILES,IUPACName/JSON")
    data = _get(url)
    if not data:
        return None

    props = (data.get("PropertyTable") or {}).get("Properties") or []
    if not props:
        return None

    p0 = props[0]
    # PubChem returns the SMILES field under different key names depending on query
    smi = (p0.get("IsomericSMILES") or p0.get("CanonicalSMILES")
           or p0.get("SMILES") or p0.get("ConnectivitySMILES"))
    if smi:
        _cache_set(cache_key, {"smiles": smi, "iupac": props[0].get("IUPACName")}, 604800)
        log.info("[resolve_chemical_name] %r → %s", name, smi[:60])
    return smi or None


def resolve_smiles_params(params: List[Dict]) -> List[Dict]:
    """
    Post-process a list of extracted workflow parameters.
    For any parameter whose name is a known SMILES field and whose value
    looks like a chemical name rather than a SMILES string, resolve it via
    PubChem and replace the value in-place.

    Each item in params is expected to be {"name": str, "value": str, ...}.
    Returns the same list with SMILES values resolved where possible.
    """
    resolved: List[Dict] = []
    for param in params:
        p = dict(param)
        pname = (p.get("name") or "").lower().strip()
        pval = str(p.get("value") or "").strip()

        if pname in _SMILES_PARAM_NAMES and pval and _looks_like_chemical_name(pval):
            smi = resolve_chemical_name(pval)
            if smi:
                p["value"] = smi
                p["_resolved_from"] = pval   # keep original for display
                log.info("[resolve_smiles_params] %s: %r → SMILES resolved", pname, pval)
            else:
                log.warning("[resolve_smiles_params] %s: %r — PubChem returned no SMILES", pname, pval)
        resolved.append(p)
    return resolved
