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
import os
import re
import threading
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed, TimeoutError as FuturesTimeout
from typing import Any, Dict, List, Optional, Tuple

log = logging.getLogger(__name__)

_TIMEOUT = 10  # seconds per external call

# Registry (authoritative source catalog) — used to drop category-mismatched sources
# for a given entity type. Degrade gracefully (keep all sources) if unavailable.
try:  # pragma: no cover - import guard
    from galaxy.ai import data_sources as _registry
except Exception:  # pragma: no cover
    _registry = None

# Entity-type classes for the mismatch filter. A gene symbol names a protein target,
# so gene and protein are one class; "compound" is the other. A source is dropped only
# when its entity_types are a subset of the OTHER class (e.g. PubChem/ChEBI = compound-
# only, dropped for a gene/protein query). Dual-class and cross-cutting sources survive.
_MACRO_TYPES = frozenset({"gene", "protein"})
_COMPOUND_TYPES = frozenset({"compound"})

# Sources that need an API key we may not hold. Keyless they return HTTP 429 on nearly
# every call (Semantic Scholar's shared pool), so querying them just wastes a request
# and slows the answer. Drop them unless the key is present; they re-enable the moment
# the env var is set — no code change. PubMed / Europe PMC / OpenAlex cover literature.
_KEY_GATED_SOURCES = {"semantic_scholar": "SEMANTIC_SCHOLAR_API_KEY"}


def _drop_unauthenticated_sources(srcs: List[str]) -> List[str]:
    return [s for s in srcs
            if s not in _KEY_GATED_SOURCES
            or os.environ.get(_KEY_GATED_SOURCES[s], "").strip()]


def _drop_mismatched_sources(srcs: List[str], detected: str) -> List[str]:
    """Remove sources whose registry entity_types serve EXCLUSIVELY the other class.

    Only filters when the detected type is cleanly gene/protein or compound; for
    structure/variant/disease/pathway/literature it is a no-op (those are either
    cross-cutting or already selected deliberately). Unknown sources are kept so the
    filter never silently reduces coverage.
    """
    if detected in _MACRO_TYPES:
        other = _COMPOUND_TYPES
    elif detected in _COMPOUND_TYPES:
        other = _MACRO_TYPES
    else:
        return srcs
    if _registry is None:
        return srcs
    kept: List[str] = []
    for sid in srcs:
        rec = None
        try:
            rec = _registry.by_id(sid)
        except Exception:
            rec = None
        et = set((rec or {}).get("entity_types") or [])
        # keep when we can't classify it, or it is not exclusively the other class
        if not et or not et.issubset(other):
            kept.append(sid)
    return kept

# ── Air-gap / offline mode ──────────────────────────────────────────────────────
# In a no-egress (air-gapped) on-prem deployment, every external resolver call would
# hang for _TIMEOUT before failing. BIOMATE_OFFLINE_MODE short-circuits them: a registered
# local mirror (e.g. a ChEMBL SQLite for name→SMILES) answers if present, else we fast-fail
# to None so the harness degrades gracefully instead of stalling. A local-mirror module
# wires itself in via set_local_resolver(). Default (unset) = unchanged cloud behavior.
_OFFLINE = os.environ.get("BIOMATE_OFFLINE_MODE", "").lower() in ("1", "true", "yes")
_LOCAL_RESOLVER = None  # Optional[Callable[[str, Optional[Dict]], Optional[Any]]]


def set_local_resolver(fn) -> None:
    """Register a local-mirror resolver for air-gap: fn(url, payload=None) -> dict|None."""
    global _LOCAL_RESOLVER
    _LOCAL_RESOLVER = fn


def _offline_lookup(url: str, payload: Optional[Dict] = None) -> Optional[Any]:
    if _LOCAL_RESOLVER is not None:
        try:
            r = _LOCAL_RESOLVER(url, payload)
            if r is not None:
                return r
        except Exception as e:
            log.debug("[federated_query] local resolver failed for %s → %s", url, e)
    chembl_path = os.environ.get("BIOMATE_CHEMBL_SQLITE")
    if chembl_path:
        try:
            from .local_compound_resolver import resolve
            result = resolve(chembl_path, url, payload)
            if result is not None:
                return result
        except Exception as e:
            log.warning("[federated_query] local ChEMBL mirror unavailable: %s", e)
    literature_path = os.environ.get("BIOMATE_LITERATURE_SQLITE")
    if literature_path:
        try:
            from .local_literature import resolve
            result = resolve(literature_path, url, payload)
            if result is not None:
                return result
        except Exception as e:
            log.warning("[federated_query] local literature mirror unavailable: %s", e)
    log.debug("[federated_query] OFFLINE_MODE — skipping external call %s", url)
    return None
_POOL_SIZE = 16  # >= facet router max_sources (14) so all selected sources run concurrently
_CACHE_TTL_STABLE = 86400   # 24h — UniProt, PDB, AlphaFold, etc.
_CACHE_TTL_LITERATURE = 3600  # 1h — PubMed, EuropePMC, Semantic Scholar
_CACHE_TTL_DURABLE = 30 * 86400  # 30d — "last-known-good" for outage fallback (stale-while-error)

# ── Entity-type → sources fan-out map ─────────────────────────────────────────
# Order within each list doesn't matter (all run in parallel).
# "primary" sources are always included; callers can restrict via `sources=`.

ENTITY_SOURCES: Dict[str, List[str]] = {
    "gene":       ["ncbi_gene", "ensembl", "uniprot", "string", "kegg",
                   "go", "gnomad", "opentargets", "pharos", "pubmed", "semantic_scholar"],
    "protein":    ["uniprot", "pdb", "pdbe", "alphafold", "interpro", "string",
                   "go", "chembl", "bindingdb", "pharos", "pubmed", "semantic_scholar"],
    "compound":   ["chembl", "pubchem", "chebi", "kegg", "clinicaltrials", "pubmed", "semantic_scholar"],
    "variant":    ["dbsnp", "clinvar", "gnomad", "pubmed", "semantic_scholar"],
    "pathway":    ["kegg", "reactome", "go", "pubmed"],
    "structure":  ["pdb", "pdbe", "alphafold", "interpro"],
    "disease":    ["hpo", "clinvar", "opentargets", "clinicaltrials", "pubmed", "europepmc", "semantic_scholar"],
    "literature": ["corpus_fs", "paperclip", "pubmed", "europepmc", "biorxiv", "semantic_scholar", "openalex", "crossref"],
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

_tls = threading.local()   # last HTTP failure seen by the current fetcher thread (so a failure is not reported as "no results")


def _note_failure(url: str, exc: Exception) -> None:
    code = getattr(exc, "code", None)
    host = urllib.parse.urlparse(url).netloc
    _tls.last_error = ("HTTP %s from %s" % (code, host)) if code else ("%s from %s: %s" % (type(exc).__name__, host, str(exc)[:120]))


def _run_fetcher(fn, query: str) -> Dict:
    """Run one fetcher and surface HTTP failures. A fetcher that swallowed an error and found nothing is an ERROR
    (rate limit, timeout, outage), never "ok, 0 results". If it found something, the failure is kept as a warning."""
    _tls.last_error = None
    res = fn(query)
    err = getattr(_tls, "last_error", None)
    if err and isinstance(res, dict):
        if res.get("results"):
            res = {**res, "warnings": (res.get("warnings") or []) + [err]}
        else:
            res = {**res, "error": err, "status": "error"}
    return res


def _get(url: str, headers: Optional[Dict] = None) -> Optional[Any]:
    if _OFFLINE:
        return _offline_lookup(url)
    h = {"User-Agent": "BioMate/1.0 (biomate.ai; federated-query)"}
    if headers:
        h.update(headers)
    req = urllib.request.Request(url, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=_TIMEOUT) as resp:
            return json.loads(resp.read().decode())
    except Exception as e:
        log.debug("[federated_query] GET %s → %s", url, e)
        _note_failure(url, e)
        return None

def _post_json(url: str, payload: Dict) -> Optional[Any]:
    if _OFFLINE:
        return _offline_lookup(url, payload)
    body = json.dumps(payload).encode()
    req = urllib.request.Request(
        url, data=body,
        headers={"Content-Type": "application/json",
                 "User-Agent": "BioMate/1.0 (biomate.ai; federated-query)"}
    )
    try:
        with urllib.request.urlopen(req, timeout=_TIMEOUT) as resp:
            data = json.loads(resp.read().decode())
    except Exception as e:
        log.debug("[federated_query] POST %s → %s", url, e)
        _note_failure(url, e)
        return None
    # A GraphQL endpoint (gnomAD, Open Targets) signals failure as HTTP 200 with a
    # top-level `errors` array and `data: null` — a transport-success body that still
    # means "no answer." Without this, a field rename or schema break reads as "the
    # gene just has no data" (empty results, no `_tls.last_error`), dropping evidence
    # catalog-wide while the fetcher reports "ok, 0 results". Surface it as a failure.
    # (committee review, 2026-11-11)
    if isinstance(data, dict) and data.get("errors"):
        _errs = data.get("errors")
        _msg = ""
        if isinstance(_errs, list) and _errs and isinstance(_errs[0], dict):
            _msg = str(_errs[0].get("message") or "")[:200]
        log.debug("[federated_query] POST %s → GraphQL errors: %s", url, _msg)
        _note_failure(url, RuntimeError("graphql error: %s" % (_msg or "unspecified")))
        return None
    return data

# ── Shared identifier resolver ──────────────────────────────────────────────────

def resolve_gene(symbol: str) -> Dict[str, Any]:
    """Resolve a gene symbol/alias → canonical ids: {symbol, entrez, ensembl, uniprot}.

    The KEYSTONE: most sources don't accept a bare symbol — AlphaFold/PDBe need a UniProt
    accession, gnomAD/Open Targets need an ENSG, KEGG needs an Entrez id. One cached,
    alias-safe mygene call (p53→TP53, BCR-ABL→ABL1) that every id-needing fetcher shares,
    so a plain "ABL1" reaches all of them (ABL1 → 25 / ENSG00000097007 / P00519). 24h
    cache. Returns {} (not an error) when unresolvable."""
    sym = (symbol or "").strip()
    if not sym:
        return {}
    ck = f"bm:resolve:{sym.lower()}"
    cached = _cache_get(ck)
    if cached is not None:
        return cached
    out: Dict[str, Any] = {}
    r = _post_json("https://mygene.info/v3/query",
                   {"q": [sym], "scopes": "symbol,alias,retired",
                    "fields": "symbol,entrezgene,ensembl.gene,uniprot.Swiss-Prot",
                    "species": "human"})
    # `_post_json` returns None ONLY on a transport/HTTP failure (and has already
    # called `_note_failure`); a successful call returns a list (with a
    # `{"notfound": true}` entry when the term is genuinely not a gene). Caching the
    # empty `{}` from a TRANSIENT failure the same as a real "not a gene" would
    # poison this shared keystone for the whole TTL — every id-needing fetcher then
    # reads `{}` with no network call, so `_tls.last_error` is unset and they report
    # "ok, 0 results" instead of surfacing the error. So only cache when the call
    # actually completed; on failure, return {} WITHOUT caching so the next call
    # retries. (committee review, 2026-11-11)
    if r is None:
        return {}
    hit = r[0] if isinstance(r, list) and r and not r[0].get("notfound") else {}
    if hit:
        ens = hit.get("ensembl")
        if isinstance(ens, list):
            ens = ens[0] if ens else {}
        up = (hit.get("uniprot") or {}).get("Swiss-Prot")
        if isinstance(up, list):
            up = up[0] if up else None
        out = {
            "symbol": hit.get("symbol") or sym,
            "entrez": str(hit["entrezgene"]) if hit.get("entrezgene") else None,
            "ensembl": (ens or {}).get("gene"),
            "uniprot": up,
        }
    # cache even a resolved-empty result briefly so a non-gene term isn't re-queried
    # every call; a real resolution gets the full stable TTL.
    _cache_set(ck, out, _CACHE_TTL_STABLE if out else 3600)
    return out


# Official UniProt accession grammar: the OPQ branch (6-char) OR the [A-NR-Z]
# branch (6- and 10-char). The earlier collapsed form `[A-NR-Z0-9]...` DROPPED
# the OPQ branch — silently rejecting P04637 (TP53), P00519 (ABL1), P38398
# (BRCA1) and every O/P/Q accession, so a by-accession structure query fell
# back to mygene (which notfound's accessions) and returned nothing. It also
# wrongly admitted a leading digit. (committee review, 2026-11-11)
_UNIPROT_ACC_RE = re.compile(
    r'^([OPQ][0-9][A-Z0-9]{3}[0-9]|[A-NR-Z][0-9]([A-Z][A-Z0-9]{2}[0-9]){1,2})$',
    re.I,
)


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
    # A bare symbol search returns many reviewed ORTHOLOGS and UniProt's relevance order can
    # surface a non-human one first (e.g. PCSK9 → Plecturocebus/Colobus ahead of human),
    # polluting the grounded evidence for a human-centric research question. Stable-sort the
    # human entry to the top; keep the rest so a genuinely non-human query still surfaces its
    # organisms (end-to-end smoke finding, 2026-11-12).
    results.sort(key=lambda r: (r.get("organism") != "Homo sapiens"))
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
    # For a gene/protein symbol, resolve → UniProt and search RCSB BY that accession.
    # A bare full_text search for "ABL1" returned the newest entries matching the string
    # anywhere (9F00, 9KTJ …), NOT ABL1 structures — noise that made the synthesis distrust
    # the structure evidence and fall back to general knowledge (dev finding, 2026-11-12).
    _acc = resolve_gene(query).get("uniprot") if not _UNIPROT_ACC_RE.match(query.strip()) else query.strip().upper()
    if _acc:
        payload = {
            "query": {"type": "group", "logical_operator": "and", "nodes": [
                {"type": "terminal", "service": "text", "parameters": {
                    "attribute": "rcsb_polymer_entity_container_identifiers.reference_sequence_identifiers.database_accession",
                    "operator": "exact_match", "value": _acc}},
                {"type": "terminal", "service": "text", "parameters": {
                    "attribute": "rcsb_polymer_entity_container_identifiers.reference_sequence_identifiers.database_name",
                    "operator": "exact_match", "value": "UniProt"}}]},
            "return_type": "entry", "request_options": {"paginate": {"start": 0, "rows": 5}},
        }
    else:
        # Non-gene free text (e.g. a complex/ligand phrase): full-text fallback.
        payload = {
            "query": {"type": "terminal", "service": "full_text", "parameters": {"value": query}},
            "return_type": "entry", "request_options": {"paginate": {"start": 0, "rows": 5}},
        }
    data = _post_json("https://search.rcsb.org/rcsbsearch/v2/query", payload)
    ids = [r["identifier"] for r in (data or {}).get("result_set", [])[:5]]
    return {"source": "pdb", "results": [{"pdb_id": i} for i in ids]}

def _fetch_alphafold(query: str) -> Dict:
    # AlphaFold is keyed by UniProt accession. A bare gene symbol used to return nothing;
    # resolve it first (ABL1 → P00519) via the shared resolver (dev finding, 2026-11-11).
    q = query.strip()
    acc = q.upper() if _UNIPROT_ACC_RE.match(q) else (resolve_gene(q).get("uniprot") or "")
    if not acc:
        return {"source": "alphafold", "results": []}
    data = _get(f"https://alphafold.ebi.ac.uk/api/prediction/{acc}")
    if data and isinstance(data, list):
        d = data[0]
        return {"source": "alphafold", "results": [
            {"uniprot": acc, "model_url": d.get("pdbUrl"),
             "pae_image_url": d.get("paeImageUrl"), "confidence": "pLDDT"}
        ]}
    return {"source": "alphafold", "results": []}


def _fetch_pdbe(query: str) -> Dict:
    # PDBe best_structures: ranked EXPERIMENTAL structures for a target (ABL1 → P00519 →
    # 1opl@3.42Å). Needs a UniProt acc, so resolve a bare symbol. pdbe was in the registry
    # with NO fetcher — its best endpoint was entirely unused (dev finding, 2026-11-11).
    q = query.strip()
    acc = q.upper() if _UNIPROT_ACC_RE.match(q) else (resolve_gene(q).get("uniprot") or "")
    if not acc:
        return {"source": "pdbe", "results": []}
    data = _get(f"https://www.ebi.ac.uk/pdbe/api/mappings/best_structures/{acc}")
    entries = (data or {}).get(acc) or []
    results = [{"pdb_id": e.get("pdb_id"), "chain": e.get("chain_id"),
                "resolution": e.get("resolution"), "coverage": e.get("coverage"),
                "method": e.get("experimental_method")}
               for e in entries[:5]]
    return {"source": "pdbe", "results": results}

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
    # Return the actual interaction NETWORK (partners + combined confidence). The old fetcher
    # only called get_string_ids, which resolves the id but has no 'score' key (so score was
    # always None) and returns NO partners — the network evidence never arrived (dev finding,
    # 2026-11-11). interaction_partners accepts the symbol directly; required_score=700 = high.
    q = urllib.parse.quote(query)
    data = _get(f"https://string-db.org/api/json/interaction_partners"
                f"?identifiers={q}&species=9606&required_score=700&limit=10&caller_identity=biomate")
    results = [{"partner": p.get("preferredName_B"), "string_id": p.get("stringId_B"),
                "score": p.get("score")} for p in (data or [])[:10]]
    return {"source": "string", "results": results}

def _fetch_kegg(query: str) -> Dict:
    q = urllib.parse.quote(query)
    # KEGG's find endpoint returns TAB-separated text, not JSON, so it can't go
    # through _get(). It must still record a transport failure via _note_failure
    # so _run_fetcher distinguishes "KEGG errored (429/timeout/outage)" from a
    # genuine "0 pathways" — otherwise a rate-limit is reported as "ok, 0 results".
    url = f"https://rest.kegg.jp/find/pathway/{q}"
    if _OFFLINE:
        return {"source": "kegg", "results": []}
    try:
        with urllib.request.urlopen(url, timeout=_TIMEOUT) as resp:
            text = resp.read().decode()
            results = []
            for line in text.strip().split("\n")[:5]:
                if "\t" in line:
                    pid, name = line.split("\t", 1)
                    results.append({"pathway_id": pid, "name": name})
            return {"source": "kegg", "results": results}
    except Exception as e:
        log.debug("[federated_query] GET %s → %s", url, e)
        _note_failure(url, e)
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
    # QuickGO returns clean GO terms; the old api.geneontology.org autocomplete returned
    # GENE PRODUCTS (often non-human) with hex-blob ids, not GO: terms.
    q = urllib.parse.quote(query)
    data = _get(f"https://www.ebi.ac.uk/QuickGO/services/ontology/go/search?query={q}&limit=5",
                headers={"Accept": "application/json"})
    results = [{"go_id": d.get("id"), "name": d.get("name"),
                "definition": (d.get("definition") or {}).get("text")}
               for d in (data or {}).get("results", [])[:5]]
    return {"source": "go", "results": results}

def _fetch_hpo(query: str) -> Dict:
    # ontology.jax.org is the live HPO API; the old hpo.jax.org/api/hpo/search now serves a
    # single-page-app HTML shell (not JSON) → every call failed. Same terms[].{id,name,definition}.
    q = urllib.parse.quote(query)
    data = _get(f"https://ontology.jax.org/api/hp/search?q={q}&limit=5")
    results = [{"hpo_id": t.get("id"), "name": t.get("name"),
                "definition": t.get("definition")}
               for t in (data or {}).get("terms", [])[:5]]
    return {"source": "hpo", "results": results}

def _fetch_chebi(query: str) -> Dict:
    # Live ChEBI search is the backend ES endpoint; searchId.do + webservices/chebi/2.0/lite
    # are retired (return HTML / 301) → the old fetcher returned [] for every query.
    q = urllib.parse.quote(query)
    data = _get(f"https://www.ebi.ac.uk/chebi/backend/api/public/es_search/?term={q}&size=5")
    results = []
    for hit in (data or {}).get("results", [])[:5]:
        src = hit.get("_source") or {}
        results.append({"chebi_id": src.get("chebi_accession"),
                        "name": src.get("name"),
                        "definition": src.get("definition"),
                        "stars": src.get("stars")})
    return {"source": "chebi", "results": results}

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
                        "mw": props.get("full_mwt"),
                        "smiles": (m.get("molecule_structures") or {}).get("canonical_smiles")})
    # No molecule by that name → treat the query as a TARGET (gene/protein). This is
    # the SAR/potency case: "ABL1" is not a molecule, so molecule/search is empty and
    # the old fetcher returned nothing. Resolve the ChEMBL target so the answer grounds
    # on real target annotation (dev finding, 2026-11-11: ABL1 → CHEMBL1862).
    if not results:
        tq = urllib.parse.quote(query)
        tdata = _get(f"https://www.ebi.ac.uk/chembl/api/data/target/search"
                     f"?q={tq}&format=json&limit=3")
        _human_tid = None
        for t in (tdata or {}).get("targets", [])[:3]:
            results.append({"chembl_target_id": t.get("target_chembl_id"),
                            "name": t.get("pref_name"),
                            "target_type": t.get("target_type"),
                            "organism": t.get("organism")})
            if t.get("organism") == "Homo sapiens" and not _human_tid:
                _human_tid = t.get("target_chembl_id")
        # The SAR answer is the ACTIVITY table: pull the most potent IC50s against the
        # human target (pChEMBL desc) so the answer can cite real nM potencies, not just
        # the target record (dev finding 2026-11-11: fetcher stopped at the target name).
        if _human_tid:
            adata = _get(f"https://www.ebi.ac.uk/chembl/api/data/activity"
                         f"?target_chembl_id={_human_tid}&standard_type=IC50"
                         f"&pchembl_value__isnull=false&order_by=-pchembl_value&limit=5&format=json")
            for a in (adata or {}).get("activities", [])[:5]:
                results.append({"chembl_id": a.get("molecule_chembl_id"),
                                "activity_type": a.get("standard_type"),
                                "value": a.get("standard_value"),
                                "units": a.get("standard_units"),
                                "pchembl_value": a.get("pchembl_value")})
    return {"source": "chembl", "results": results}

def _fetch_pubchem(query: str) -> Dict:
    # PubChem PUG-REST compound lookup (keyless). Mirrors ai_assistant._query_pubchem
    # lookup mode so the federated fan-out reaches PubChem too — previously PubChem
    # was only reachable via the single-source query_database path, never the fan-out.
    import re
    term = query.strip()
    selector = "cid" if re.match(r"^\d+$", term) else "name"
    enc = urllib.parse.quote(term, safe="")
    url = (f"https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/{selector}/{enc}/property/"
           f"IUPACName,MolecularFormula,MolecularWeight,ConnectivitySMILES/JSON")
    data = _get(url)
    props = (((data or {}).get("PropertyTable") or {}).get("Properties") or [])
    results = [{"cid": p.get("CID"),
                "name": p.get("IUPACName"),
                "formula": p.get("MolecularFormula"),
                "mw": p.get("MolecularWeight"),
                "smiles": p.get("ConnectivitySMILES") or p.get("CanonicalSMILES")}
               for p in props[:5]]
    return {"source": "pubchem", "results": results}

def _fetch_interpro(query: str) -> Dict:
    # /entry/interpro?search= returns real domain entries with results[].metadata; the old
    # /entry/?search= returned only a DB-counts summary (no results[]) → always empty.
    q = urllib.parse.quote(query)
    data = _get(f"https://www.ebi.ac.uk/interpro/api/entry/interpro?search={q}&format=json&page_size=5")
    results = [{"accession": e.get("metadata", {}).get("accession"),
                "name": e.get("metadata", {}).get("name"),
                "type": e.get("metadata", {}).get("type")}
               for e in (data or {}).get("results", [])[:5]]
    return {"source": "interpro", "results": results}

def _fetch_gnomad(query: str) -> Dict:
    # gnomAD is keyed by Ensembl gene id. Resolve a symbol, then pull the gene CONSTRAINT
    # (LoF intolerance: pLI, LOEUF, missense-z) — the compact, high-value gnomAD gene fact.
    # The old generic `search` returned only an id, no frequency or constraint (dev finding
    # 2026-11-12: _fetch_gnomad gave no allele-frequency / no usable signal).
    q = query.strip()
    ensg = q if re.match(r'^ENSG\d+$', q, re.I) else resolve_gene(q).get("ensembl")
    if not ensg:
        return {"source": "gnomad", "results": []}
    gql = ('{gene(gene_id:"%s",reference_genome:GRCh38){gene_id symbol '
           'gnomad_constraint{pli oe_lof oe_lof_upper mis_z}}}' % ensg)
    data = _post_json("https://gnomad.broadinstitute.org/api", {"query": gql})
    g = (((data or {}).get("data") or {}).get("gene")) or {}
    c = g.get("gnomad_constraint") or {}
    if not c:
        return {"source": "gnomad", "results": []}
    return {"source": "gnomad", "results": [{
        "gene_id": g.get("gene_id"), "symbol": g.get("symbol"),
        "pLI": c.get("pli"), "LOEUF": c.get("oe_lof_upper"),
        "oe_lof": c.get("oe_lof"), "missense_z": c.get("mis_z")}]}


def _fetch_opentargets(query: str) -> Dict:
    # Open Targets GraphQL: target → disease associations (genetic/druggability evidence,
    # scored 0-1). Keyed by Ensembl gene id; resolve a symbol first. The registry listed
    # opentargets but it had NO fan-out fetcher (dev finding 2026-11-12).
    q = query.strip()
    ensg = q if re.match(r'^ENSG\d+$', q, re.I) else resolve_gene(q).get("ensembl")
    if not ensg:
        return {"source": "opentargets", "results": []}
    gql = ('{target(ensemblId:"%s"){approvedSymbol '
           'associatedDiseases(page:{index:0,size:5}){rows{disease{name} score}}}}' % ensg)
    data = _post_json("https://api.platform.opentargets.org/api/v4/graphql", {"query": gql})
    t = (((data or {}).get("data") or {}).get("target")) or {}
    rows = ((t.get("associatedDiseases") or {}).get("rows")) or []
    results = [{"target": t.get("approvedSymbol"),
                "disease": (r.get("disease") or {}).get("name"),
                "association_score": round(r.get("score") or 0, 3)}
               for r in rows[:5] if r.get("disease")]
    return {"source": "opentargets", "results": results}

def _fetch_bindingdb(query: str) -> Dict:
    # BindingDB measured binding affinities (Ki/Kd/IC50/EC50, in nM) for a TARGET, keyed by
    # UniProt accession — the experimental SAR/affinity answer the bioactivity facet
    # advertised but never served (no fan-out fetcher; committee review 2026-11-11). Resolve
    # a symbol → accession, then surface the most POTENT measurements (lowest nM). NB: the
    # upstream response key is the vendor typo "getLindsByUniprotResponse".
    q = query.strip()
    acc = q.upper() if _UNIPROT_ACC_RE.match(q) else (resolve_gene(q).get("uniprot") or "")
    if not acc:
        return {"source": "bindingdb", "results": []}
    data = _get("https://www.bindingdb.org/rest/getLigandsByUniprot"
                "?uniprot=%s&cutoff=10000&response=application/json" % urllib.parse.quote(acc))
    resp = (data or {}).get("getLindsByUniprotResponse") or {}
    affs = resp.get("bdb.affinities") or []
    if isinstance(affs, dict):      # single hit comes back as an object, not a list
        affs = [affs]

    def _nm(a):
        try:
            return float(str(a.get("bdb.affinity", "")).strip())
        except Exception:
            return float("inf")     # unparseable affinity sorts last

    ranked = sorted((a for a in affs if isinstance(a, dict)), key=_nm)[:5]
    results = [{"target_uniprot": acc,
                "monomer_id": a.get("bdb.monomerid"),
                "affinity_type": a.get("bdb.affinity_type"),
                "affinity_nm": str(a.get("bdb.affinity", "")).strip(),
                "smiles": a.get("bdb.smile")}
               for a in ranked]
    return {"source": "bindingdb", "results": results}


def _fetch_pharos(query: str) -> Dict:
    # Pharos (NCATS) target development level — the druggability/tractability tier
    # (Tclin > Tchem > Tbio > Tdark) plus protein family + novelty — the 'target' facet's
    # tractability answer. GraphQL by gene symbol; the facet map advertised pharos but there
    # was no fan-out fetcher (committee review 2026-11-11).
    q = query.strip()
    sym = (resolve_gene(q).get("symbol") or q).replace('"', '')
    if not sym:
        return {"source": "pharos", "results": []}
    gql = '{target(q:{sym:"%s"}){name sym tdl fam novelty}}' % sym
    data = _post_json("https://pharos-api.ncats.io/graphql", {"query": gql})
    t = (((data or {}).get("data") or {}).get("target")) or {}
    if not t:
        return {"source": "pharos", "results": []}
    return {"source": "pharos", "results": [{
        "symbol": t.get("sym"), "name": t.get("name"),
        "development_level": t.get("tdl"), "family": t.get("fam"),
        "novelty": t.get("novelty")}]}


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
            "evidence_kind": p.get("evidence_kind", "abstract"),
            "pmcid": p.get("pmcid"),
            "licence": p.get("licence"),
        })
    return {"source": "europepmc", "results": results}

def _fetch_biorxiv(query: str) -> Dict:
    """bioRxiv + medRxiv preprints, searched through Europe PMC (which indexes every bioRxiv/medRxiv preprint and,
    unlike the bioRxiv API, supports keyword search). Preprints are NOT peer reviewed; each row says so."""
    scoped = f'({query}) AND SRC:PPR AND (PUBLISHER:"bioRxiv" OR PUBLISHER:"medRxiv")'
    q = urllib.parse.quote(scoped)
    data = _get(f"https://www.ebi.ac.uk/europepmc/webservices/rest/search"
                f"?query={q}&format=json&pageSize=5&resultType=core")
    results = []
    for p in (data or {}).get("resultList", {}).get("result", [])[:5]:
        doi = p.get("doi")
        server = ((p.get("bookOrReportDetails") or {}).get("publisher") or "bioRxiv/medRxiv")
        if not doi or not p.get("title"):
            continue
        results.append({
            "doi": doi,
            "title": p.get("title"),
            "authors": p.get("authorString"),
            "year": (p.get("firstPublicationDate") or "")[:4] or p.get("pubYear"),
            "published": p.get("firstPublicationDate"),
            "server": server,
            "url": f"https://doi.org/{doi}",
            "abstract": (p.get("abstractText") or "")[:500],
            "evidence_kind": "preprint_abstract",
            "peer_reviewed": False,
            "europepmc_id": p.get("id"),
        })
    return {"source": "biorxiv", "results": results}


def _fetch_clinicaltrials(query: str) -> Dict:
    """ClinicalTrials.gov (official API v2, keyless): registered trials matching a disease, drug, target or free-text
    query. Registry records, not results: status, phase, sponsor and (when stopped) the stated reason."""
    q = urllib.parse.quote(query)
    fields = ("NCTId,BriefTitle,OverallStatus,Phase,Condition,InterventionName,LeadSponsorName,"
              "StartDate,WhyStopped,HasResults")
    data = _get(f"https://clinicaltrials.gov/api/v2/studies?query.term={q}&pageSize=8&format=json&fields={fields}")
    results = []
    for st in (data or {}).get("studies", [])[:8]:
        ps = st.get("protocolSection") or {}
        nct = (ps.get("identificationModule") or {}).get("nctId")
        if not nct:
            continue
        status = ps.get("statusModule") or {}
        results.append({
            "nct_id": nct,
            "title": (ps.get("identificationModule") or {}).get("briefTitle"),
            "status": status.get("overallStatus"),
            "why_stopped": status.get("whyStopped"),
            "start": (status.get("startDateStruct") or {}).get("date"),
            "phases": (ps.get("designModule") or {}).get("phases"),
            "conditions": ((ps.get("conditionsModule") or {}).get("conditions") or [])[:6],
            "interventions": [i.get("name") for i in ((ps.get("armsInterventionsModule") or {}).get("interventions") or [])[:6]],
            "sponsor": ((ps.get("sponsorCollaboratorsModule") or {}).get("leadSponsor") or {}).get("name"),
            "has_results": bool(st.get("hasResults")),
            "url": f"https://clinicaltrials.gov/study/{nct}",
            "evidence_kind": "registry_record",
        })
    return {"source": "clinicaltrials", "results": results}


def _fetch_semantic_scholar(query: str) -> Dict:
    """Semantic Scholar — citation graph, influential papers, open-access PDFs."""
    q = urllib.parse.quote(query)
    fields = "title,authors,year,citationCount,openAccessPdf,abstract"
    key = os.environ.get("SEMANTIC_SCHOLAR_API_KEY", "").strip()   # without a key the shared limit often returns HTTP 429
    data = _get(f"https://api.semanticscholar.org/graph/v1/paper/search"
                f"?query={q}&limit=5&fields={fields}", headers=({"x-api-key": key} if key else None))
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

def _fetch_corpus_fs(query: str) -> Dict:
    """Grounded local corpus-as-filesystem source (Option B).

    SAFE / opt-in by design: this joins the literature fan-out only when a local
    corpus index is explicitly configured AND present on disk. With no corpus
    configured it returns ``[]`` immediately -- it never errors, never performs a
    network call, and never blocks the rest of the fan-out. Every returned result
    is grounded by construction (a literal snippet that exists in the store, with
    full provenance), so this source cannot confabulate citations.
    """
    import os

    db = os.environ.get("CORPUS_INDEX_DB")
    backend = (os.environ.get("CORPUS_INDEX_BACKEND") or "fts5").strip().lower()
    # Only the embedded fts5 backend is file-backed + opt-in here; without an
    # explicit, existing DB path there is no in-perimeter corpus to query.
    if backend != "fts5" or not db or not os.path.exists(db):
        return {"source": "corpus_fs", "results": []}

    try:
        from .corpus_fs import get_corpus_index, key_terms  # lazy, additive
    except Exception:
        try:  # loose/script import context (ai dir on sys.path)
            from corpus_fs import get_corpus_index, key_terms  # type: ignore
        except Exception as e:  # pragma: no cover - import guard
            log.debug("[federated_query] corpus_fs unavailable: %s", e)
            return {"source": "corpus_fs", "results": []}

    try:
        index = get_corpus_index(db)
        terms = key_terms(query) or [query.strip()]
        results: List[Dict] = []
        seen = set()
        for term in terms:
            if not term:
                continue
            for hit in index.grep(term, limit=10):
                dedup = (hit.get("doc_id"), hit.get("path"), hit.get("line_start"))
                if dedup in seen:
                    continue
                seen.add(dedup)
                meta = {}
                try:
                    meta = index.doc_meta(hit.get("doc_id")) or {}
                except Exception:
                    meta = {}
                results.append({
                    "doc_id": hit.get("doc_id"),
                    "title": meta.get("title"),
                    "year": meta.get("year"),
                    "section": hit.get("section"),
                    "path": hit.get("path"),
                    "line_start": hit.get("line_start"),
                    "line_end": hit.get("line_end"),
                    "snippet": hit.get("snippet"),
                    "url": meta.get("url"),
                    "licence": meta.get("licence"),
                    "_grounded": True,
                    "_term": term,
                })
        return {"source": "corpus_fs", "results": results}
    except Exception as e:  # must never break the fan-out
        log.debug("[federated_query] corpus_fs query failed: %s", e)
        return {"source": "corpus_fs", "results": []}


def _fetch_openalex(query: str) -> Dict:
    """OpenAlex — 250M works, concept tagging, institution filtering."""
    q = urllib.parse.quote(query)
    fields = "title,authorships,publication_year,cited_by_count,open_access,concepts"
    # mailto MUST be a query param (not just the UA) to reach OpenAlex's polite pool.
    data = _get(f"https://api.openalex.org/works"
                f"?search={q}&per-page=5&select={fields}&mailto=admin@biomate.ai",
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

def _fetch_crossref(query: str) -> Dict:
    """Crossref — cross-publisher scholarly metadata (~150M works across all
    journals/publishers). Broadens peer-reviewed coverage well beyond the
    bibliographic trio (EuropePMC/Semantic Scholar/OpenAlex); JSON REST."""
    # mailto → polite pool (1→3 req/s, verified); query.bibliographic is more precise than
    # the generic query= (which matches any field loosely).
    q = urllib.parse.quote(query)
    data = _get(
        f"https://api.crossref.org/works?query.bibliographic={q}&rows=5&mailto=admin@biomate.ai"
        f"&select=title,author,issued,abstract,DOI,URL,container-title"
    )
    results = []
    for it in (((data or {}).get("message") or {}).get("items") or [])[:5]:
        title = (it.get("title") or [""])[0]
        if not title:
            continue
        authors = ", ".join(
            " ".join(p for p in [a.get("given"), a.get("family")] if p)
            for a in (it.get("author") or [])[:3]
        )
        date_parts = ((it.get("issued") or {}).get("date-parts") or [[None]])
        year = date_parts[0][0] if date_parts and date_parts[0] else None
        journal = (it.get("container-title") or [""])[0]
        # Crossref abstracts are JATS-XML fragments — strip tags for a clean snippet.
        abstract = re.sub(r"<[^>]+>", "", it.get("abstract") or "")[:500]
        results.append({
            "title": title,
            "authors": authors,
            "year": year,
            "journal": journal,
            "doi": it.get("DOI"),
            "url": it.get("URL") or (f"https://doi.org/{it.get('DOI')}" if it.get("DOI") else None),
            "abstract": abstract,
        })
    return {"source": "crossref", "results": results}

def _fetch_paperclip(query: str) -> Dict:
    """Paperclip (8M+ papers/preprints/FDA/ClinicalTrials.gov as a searchable filesystem). Hosted third-party service:
    returns an empty, labelled result unless PAPERCLIP_API_KEY is set and the deployment is not offline."""
    from galaxy.ai.paperclip_client import fetch_for_federation
    return fetch_for_federation(query)


# ── Source dispatch table ──────────────────────────────────────────────────────

_FETCHERS = {
    "paperclip":        _fetch_paperclip,
    "biorxiv":          _fetch_biorxiv,
    "clinicaltrials":   _fetch_clinicaltrials,
    "ncbi_gene":        _fetch_ncbi_gene,
    "uniprot":          _fetch_uniprot,
    "pdb":              _fetch_pdb,
    "pdbe":             _fetch_pdbe,
    "alphafold":        _fetch_alphafold,
    "ensembl":          _fetch_ensembl,
    "string":           _fetch_string,
    "kegg":             _fetch_kegg,
    "reactome":         _fetch_reactome,
    "go":               _fetch_go,
    "hpo":              _fetch_hpo,
    "chebi":            _fetch_chebi,
    "chembl":           _fetch_chembl,
    "pubchem":          _fetch_pubchem,
    "interpro":         _fetch_interpro,
    "gnomad":           _fetch_gnomad,
    "opentargets":      _fetch_opentargets,
    "bindingdb":        _fetch_bindingdb,
    "pharos":           _fetch_pharos,
    "dbsnp":            lambda q: _fetch_ncbi_entrez(q, "snp"),
    "clinvar":          lambda q: _fetch_ncbi_entrez(q, "clinvar"),
    "pubmed":           lambda q: _fetch_ncbi_entrez(q, "pubmed"),
    # New sources
    "europepmc":        _fetch_europepmc,
    "semantic_scholar": _fetch_semantic_scholar,
    "openalex":         _fetch_openalex,
    "crossref":         _fetch_crossref,
    # Grounded local corpus-as-filesystem (Option B). Opt-in: returns [] unless
    # a local corpus index is configured + present (see _fetch_corpus_fs).
    "corpus_fs":        _fetch_corpus_fs,
}

_LITERATURE_SOURCES = {"corpus_fs", "pubmed", "europepmc", "semantic_scholar", "openalex", "crossref"}

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
    # Drop category-mismatched sources for the detected entity type. A gene/protein
    # target must NOT be looked up in a COMPOUND-only database (PubChem/ChEBI return
    # 404 for "ABL1" and burn a shared rate-limit slot), and a compound must not be
    # looked up in a GENE-only database. Registry `entity_types` are the source of
    # truth; a source is dropped only when it serves EXCLUSIVELY the other class, so
    # dual-class sources (ChEMBL = protein+compound) and cross-cutting ones
    # (literature/pathway/variant/disease/structure) always survive. This runs even
    # when the caller passes an explicit `sources=` list, because that intent-selected
    # list (facet-based) is exactly what over-includes compound DBs for a target
    # (live dev finding, 2026-11-11: ABL1 SAR hit PubChem/ChEBI/PDB-by-id).
    target_sources = _drop_mismatched_sources(target_sources, detected)
    # Drop sources whose required API key we don't hold (keyless → 429 waste).
    target_sources = _drop_unauthenticated_sources(target_sources)

    # The cache key MUST include the (filtered) source set: an intent-selected fan-out
    # (e.g. sources=[chembl,pdb,…] for a SAR question) and a default entity-type fan-out
    # share the same detected type + query text but query DIFFERENT sources. Keying on
    # type+query alone let a prior default query serve a later source-restricted one from
    # cache with the WRONG merged set — silently dropping the sources the caller asked for
    # (committee review, 2026-11-11).
    _src_key = ",".join(sorted(target_sources))
    cache_key = f"bm:fq:{detected}:{query.lower().strip()}:{_src_key}"
    cached = _cache_get(cache_key)
    if cached:
        cached["_cached"] = True
        return cached

    results: Dict[str, Dict] = {}
    succeeded: List[str] = []
    failed: List[str] = []

    with ThreadPoolExecutor(max_workers=_POOL_SIZE) as pool:
        future_to_source = {
            pool.submit(_run_fetcher, _FETCHERS[src], query): src
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
                    if isinstance(result, dict) and result.get("error") and not result.get("results"):
                        failed.append(src)
                    else:
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

    merged = _merge_results(results, detected, source_order=target_sources)

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
    _durable_key = cache_key + ":durable"
    if not failed:   # never cache a partial answer: a rate limit would persist for the whole TTL
        _cache_set(cache_key, out, ttl)
        # Keep a long-lived last-known-good for outage fallback (stale-while-error).
        _cache_set(_durable_key, out, _CACHE_TTL_DURABLE)
        return out
    # Degraded: one or more sources failed (outage / rate limit / maintenance — the exact
    # pain this session: EBI 500s, NCBI maintenance, S2 429s). Serve last-known-good
    # NARROWLY — overlay the durable copy ONLY for the sources that failed THIS run, and
    # keep every fresh source that succeeded. The earlier heuristic compared total merged
    # COUNT and, if the 30-day durable copy was merely bigger, discarded the ENTIRE fresh
    # fan-out — so one minor source blipping (an S2 429) threw away fresh, authoritative
    # gnomAD/Open Targets evidence in favour of a stale snapshot, and reported the old
    # run's `sources_failed: []` while flagging `_stale`. (committee review, 2026-11-11)
    _stale = _cache_get(_durable_key)
    _stale_results = (_stale or {}).get("results") if isinstance(_stale, dict) else None
    if _stale_results:
        _merged_results = dict(results)
        _recovered: List[str] = []
        for _src in failed:
            _old = _stale_results.get(_src)
            if isinstance(_old, dict) and _old.get("results"):
                _merged_results[_src] = {**_old, "_stale": True}
                _recovered.append(_src)
        if _recovered:
            _still_failed = [s for s in failed if s not in _recovered]
            return {
                "query": query,
                "entity_type": detected,
                "sources_queried": target_sources,
                "sources_succeeded": succeeded,       # fresh, live successes only
                "sources_failed": _still_failed,      # what we could NOT recover
                "sources_stale": _recovered,          # served from last-known-good
                "results": _merged_results,
                "merged": _merge_results(_merged_results, detected, source_order=target_sources),
                "_stale": True,
                "_stale_reason": "served last-known-good for %s (live unavailable); %s"
                                 % (",".join(_recovered[:6]),
                                    ("%d source(s) still unavailable" % len(_still_failed))
                                    if _still_failed else "all other sources fresh"),
            }
    return out

# ── Result merging ─────────────────────────────────────────────────────────────

def _merge_results(results: Dict[str, Dict], entity_type: str,
                   source_order: Optional[List[str]] = None) -> List[Dict]:
    """
    Produce a unified flat list across all sources, deduped by name/id,
    each item annotated with its source.

    `source_order`, when given, is the INTENT-selected source list from the facet
    router (e.g. chembl/bindingdb/pharos first for a SAR query, pdb/pdbe/alphafold
    first for a structure query). The merge round-robins in THAT order so the top-N
    cap downstream surfaces the sources the QUESTION needs. Without it, a generic
    entity-type priority is used (fallback for callers that don't pass a source list).
    """
    seen_names: set = set()
    merged: List[Dict] = []

    # Generic entity-type priority — FALLBACK only, used when the caller did not pass an
    # intent-selected `source_order` (most trusted first).
    priority = {
        # bindingdb/pharos are placed among the high-value sources (BEFORE literature) so
        # their top row survives the round-robin + merged[:8] cap in a broad multi-source
        # query — omitting them relegated them to `remaining`, cutting BindingDB affinities
        # out of synthesis on a broad ABL1 query (dev verify finding, 2026-11-12).
        "gene":       ["uniprot", "ncbi_gene", "ensembl", "string", "kegg",
                       "go", "gnomad", "pharos", "pubmed", "semantic_scholar"],
        "protein":    ["uniprot", "pdb", "pdbe", "alphafold", "interpro", "string",
                       "go", "chembl", "bindingdb", "pharos", "pubmed", "semantic_scholar"],
        "compound":   ["chembl", "pubchem", "chebi", "kegg", "pubmed", "semantic_scholar"],
        "variant":    ["clinvar", "dbsnp", "gnomad", "pubmed", "semantic_scholar"],
        "pathway":    ["reactome", "kegg", "go", "pubmed"],
        "structure":  ["pdb", "pdbe", "alphafold", "interpro"],
        "disease":    ["hpo", "clinvar", "europepmc", "pubmed", "semantic_scholar"],
        "literature": ["corpus_fs", "pubmed", "europepmc", "semantic_scholar", "openalex", "crossref"],
    }
    # Prefer the intent-selected order (facet router) over the generic entity-type priority:
    # the facet router already ranked the sources the QUESTION needs first, so a broad SAR
    # query's bindingdb/chembl/pharos are no longer buried behind structure/identity sources
    # and cut by the downstream top-N cap (dev finding 2026-11-12: broad ABL1 returned
    # literature-only because bindingdb landed at merge position ~9 → cut by merged[:8]).
    if source_order:
        ordered = [s for s in source_order if s in results]
    else:
        ordered = priority.get(entity_type, list(results.keys()))
    remaining = [s for s in results if s not in ordered]
    src_order = [s for s in (ordered + remaining) if s in results]

    # ROUND-ROBIN across sources: take each source's top result first, then each source's
    # 2nd, etc. A strict per-source drain let a high-volume identity source (uniprot/
    # ncbi_gene) fill all the prompt's top-8 slots and bury structure/activity records
    # from pdb/pdbe/alphafold/chembl — so a gene-typed target in a STRUCTURE question
    # fetched the structures but never rendered them (dev finding, 2026-11-12). Priority
    # order still breaks ties within a rank.
    _lists = {s: (results[s].get("results") or []) for s in src_order}
    _maxlen = max((len(v) for v in _lists.values()), default=0)
    for _rank in range(_maxlen):
        for src in src_order:
            _items = _lists[src]
            if _rank >= len(_items):
                continue
            item = _items[_rank]
            if not isinstance(item, dict):
                continue
            # Two-tier dedup (committee review, 2026-11-11). The earlier single key mixed
            # true unique IDs with human-readable NAMES and truncated a json fallback to 90
            # chars — which both over-merged (two distinct rows sharing a long early field,
            # or two different "Part I/II" papers sharing a 60-char title prefix, collapsed
            # → silent drop) and mis-collapsed distinct cross-source evidence (two sources'
            # rows about the same disease/partner keyed on the bare name → one source's
            # evidence lost).
            #   Tier 1 — a STABLE globally-unique identifier: same id = same entity across
            #   sources, so merge globally.
            _stable_id = (
                item.get("accession") or item.get("gene_id") or item.get("pdb_id") or
                item.get("pmid") or item.get("doi") or item.get("chembl_id") or
                item.get("chembl_target_id") or item.get("paper_id") or item.get("nct_id") or
                item.get("variant_id") or item.get("patent_id") or item.get("hpo_id") or
                item.get("go_id") or item.get("pathway_id")
            )
            if _stable_id:
                dedup_key = "id:%s" % _stable_id
            else:
                # Tier 2 — no stable id (Open Targets disease+score, STRING partner+score,
                # other score-only rows). These are SOURCE-SPECIFIC evidence: two sources'
                # rows about the same disease are DIFFERENT evidence and must both survive,
                # so scope the key to the source + the FULL canonical content (no truncation).
                # This still gives every content-bearing record a stable non-empty key (the
                # original "Open Targets/STRING dropped, LLM said 'records do not contain'"
                # fix), while an exact duplicate row within one source still collapses.
                dedup_key = "%s:%s" % (
                    src, json.dumps({k: v for k, v in item.items() if k != "_source"},
                                    sort_keys=True, default=str))
            if dedup_key in seen_names:
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

        # Gap detection: too few NEW results → BROADEN. The trailing terms of a
        # multi-keyword query are usually the most specific and over-constrain the
        # implicit-AND match on PubMed/Europe PMC (e.g. a query ending in
        # "…import oligomerization handover" returns almost nothing, while
        # "…import oligomerization" returns a full set). Drop the most specific
        # trailing term each deepening step so coverage widens monotonically; only
        # when the query is already short fall back to a generic widener. (The old
        # behaviour appended "mechanism review" and reset to the original query
        # every depth, so depths 2+ re-ran an identical narrow search and found
        # nothing new.)
        if len(new_items) < 3 and depth < max_depth:
            toks = current_query.split()
            current_query = " ".join(toks[:-1]) if len(toks) > 3 else f"{query} review"
            log.info("[federated_query] depth %d: %d new results, broadening to %r",
                     depth, len(new_items), current_query)

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
    "smiles_list",  # ADMET/docking workflows pass compound lists as smiles_list
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
