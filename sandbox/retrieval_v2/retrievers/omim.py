"""
OMIM gene → disease retriever.

Productized from `evaluation/adapters/biomni_eval1_adapter.py` (functions
`_get_gene_omim_diseases`, `_deduplicate_omim_diseases`,
`lookup_omim_for_gene`). The benchmark-specific HPO-overlap scoring has been
deliberately omitted — that filtering logic belongs in the caller, not the
retriever. This module just answers "what diseases does OMIM associate with
this gene?" and returns structured data.

Single public entry point:

    lookup_omim_gene("ARL6IP1") -> {
        "gene_symbol": "ARL6IP1",
        "gene_name": "ADP ribosylation factor like GTPase 6 interacting protein 1",
        "gene_mim": "607669",
        "summary": "Predicted to be involved in...",
        "diseases": [
            {"omim_id": "607598", "name": "Spastic Paraplegia 61, Autosomal Recessive"},
            ...
        ],
    }

Returns `{"error": "..."}` shape on irrecoverable failure. Disk-cached.
"""
from __future__ import annotations

import hashlib
import json
import logging
import os
from pathlib import Path
from typing import Dict, List, Any, Optional

import requests

logger = logging.getLogger(__name__)

_DEFAULT_CACHE = (
    os.environ.get("BIOMATE_RETRIEVER_CACHE")
    or os.path.expanduser("~/.cache/biomate/retrievers/omim")
)
CACHE_DIR = Path(_DEFAULT_CACHE)
CACHE_DIR.mkdir(parents=True, exist_ok=True)

_HEADERS = {"User-Agent": "BioMate-Retriever/1.0 (xiaoni5122@gmail.com)"}


def _dedup_diseases(diseases: List[Dict[str, str]]) -> List[Dict[str, str]]:
    seen: Dict[str, Dict[str, str]] = {}
    for d in diseases:
        norm = (d.get("name") or "").lower().strip()
        if not norm:
            continue
        if norm not in seen:
            seen[norm] = d
        else:
            try:
                if int(d["omim_id"]) < int(seen[norm]["omim_id"]):
                    seen[norm] = d
            except (ValueError, KeyError):
                pass
    result = list(seen.values())
    result += [d for d in diseases if not (d.get("name") or "").strip()]
    return result


def _fetch_gene_info(gene_symbol: str, timeout: int) -> Dict[str, str]:
    """Get gene name + summary + gene-entry MIM from MyGene.info."""
    out = {"gene_name": gene_symbol, "gene_mim": "", "summary": ""}
    try:
        r = requests.get(
            "https://mygene.info/v3/query",
            params={"q": gene_symbol, "fields": "name,summary,MIM",
                    "species": "human", "size": 1},
            headers=_HEADERS, timeout=(timeout, timeout),
        )
        r.raise_for_status()
        hits = r.json().get("hits", [])
        if hits:
            hit = hits[0]
            out["gene_name"] = hit.get("name") or gene_symbol
            mim = hit.get("MIM")
            if mim:
                out["gene_mim"] = str(mim) if not isinstance(mim, list) else str(mim[0])
            out["summary"] = (hit.get("summary") or "")[:400]
    except Exception as exc:
        logger.debug("MyGene.info lookup failed for %s: %s", gene_symbol, exc)
    return out


def _fetch_uniprot_phenotype_mims(gene_symbol: str, timeout: int) -> List[str]:
    """Find reviewed human UniProt entry for gene → return phenotype MIM IDs."""
    try:
        r = requests.get(
            "https://rest.uniprot.org/uniprotkb/search",
            params={"query": f"gene_exact:{gene_symbol} AND organism_id:9606 AND reviewed:true",
                    "fields": "accession", "format": "json", "size": 1},
            headers=_HEADERS, timeout=(timeout, timeout),
        )
        if r.status_code != 200:
            return []
        results = r.json().get("results", [])
        if not results:
            return []
        uniprot_id = results[0].get("primaryAccession", "")
        if not uniprot_id:
            return []
    except Exception as exc:
        logger.debug("UniProt search failed for %s: %s", gene_symbol, exc)
        return []

    try:
        r2 = requests.get(
            f"https://rest.uniprot.org/uniprotkb/{uniprot_id}.json",
            headers=_HEADERS, timeout=(timeout, timeout),
        )
        if r2.status_code != 200:
            return []
        data = r2.json()
        pheno_mims = []
        for ref in data.get("uniProtKBCrossReferences", []):
            if ref.get("database") != "MIM":
                continue
            mim_id = ref.get("id", "")
            props = ref.get("properties", [])
            type_val = next((p.get("value", "") for p in props if p.get("key") == "Type"), "")
            # type=phenotype means disease entry; empty type also typically phenotype
            if type_val.lower() in ("phenotype", ""):
                if mim_id:
                    pheno_mims.append(mim_id)
        return pheno_mims
    except Exception as exc:
        logger.debug("UniProt fetch failed for %s/%s: %s", gene_symbol, uniprot_id, exc)
        return []


def _resolve_disease_names(mim_ids: List[str], timeout: int) -> List[Dict[str, str]]:
    """Batch-resolve OMIM IDs → disease names via NCBI esummary."""
    if not mim_ids:
        return []
    try:
        r = requests.get(
            "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi",
            params={"db": "omim", "id": ",".join(mim_ids), "retmode": "json"},
            headers=_HEADERS, timeout=(timeout, timeout),
        )
        if r.status_code != 200:
            return [{"omim_id": m, "name": f"OMIM:{m}"} for m in mim_ids]
        result_data = r.json().get("result", {})
        out = []
        for mim_id in mim_ids:
            entry = result_data.get(mim_id, {})
            title = entry.get("title") or ""
            out.append({"omim_id": mim_id,
                        "name": title.title() if title else f"OMIM:{mim_id}"})
        return out
    except Exception as exc:
        logger.debug("OMIM esummary failed: %s", exc)
        return [{"omim_id": m, "name": f"OMIM:{m}"} for m in mim_ids]


def lookup_omim_gene(gene_symbol: str, *, timeout: int = 6) -> Dict[str, Any]:
    """
    Look up OMIM disease associations for a human gene symbol.

    Returns a dict with `gene_symbol`, `gene_name`, `gene_mim`, `summary`,
    `diseases` (list of {omim_id, name}). Empty `diseases` if the gene has no
    OMIM phenotype xrefs or all lookups failed; that's not an error condition.
    """
    if not gene_symbol or not isinstance(gene_symbol, str):
        return {"error": "gene_symbol must be a non-empty string"}
    key = gene_symbol.upper().strip()

    cache_file = CACHE_DIR / f"{hashlib.md5(key.encode()).hexdigest()[:16]}.json"
    if cache_file.exists():
        try:
            return json.loads(cache_file.read_text(encoding="utf-8"))
        except Exception:
            pass

    gene_info = _fetch_gene_info(key, timeout)
    pheno_mims = _fetch_uniprot_phenotype_mims(key, timeout)
    diseases = _dedup_diseases(_resolve_disease_names(pheno_mims, timeout))

    out: Dict[str, Any] = {
        "gene_symbol": key,
        "gene_name": gene_info["gene_name"],
        "gene_mim": gene_info["gene_mim"],
        "summary": gene_info["summary"],
        "diseases": diseases,
    }
    try:
        cache_file.write_text(json.dumps(out), encoding="utf-8")
    except Exception:
        pass
    return out
