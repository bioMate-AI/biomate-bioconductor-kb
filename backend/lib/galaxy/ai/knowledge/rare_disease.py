"""
Rare disease gene prioritization for BioMate AI assistant.

Uses HPO (Human Phenotype Ontology) IDF-weighted phenotype overlap to rank
candidate genes by how well their associated diseases match a patient's
phenotype profile.

Data sources:
- genes_to_phenotype.txt (HPO): gene → HPO term set (direct gene-phenotype mapping)
- phenotype.hpoa (HPO): disease → HPO term set
- UniProt: gene → OMIM disease list
- MyGene.info: gene function summaries

Usage:
    from backend.lib.galaxy.ai.knowledge.rare_disease import RareDiseaseRanker
    ranker = RareDiseaseRanker()
    context = ranker.rank_genes(
        patient_hpo_terms=["HP:0001250", "HP:0000648"],
        candidate_genes=["SCN1A", "KCNQ2", "CDKL5"]
    )
"""

from __future__ import annotations

import logging
import math
from collections import Counter
from pathlib import Path
from typing import Dict, List, Optional, Set, Any

logger = logging.getLogger(__name__)

# HPO data paths — prefer local copies, fall back to live download
_HPO_DATA_DIR = Path(__file__).parent.parent.parent.parent.parent / "database" / "knowledge_cache"
_GENES_TO_PHENOTYPE_PATH = _HPO_DATA_DIR / "genes_to_phenotype.txt"
_PHENOTYPE_HPOA_PATH = _HPO_DATA_DIR / "phenotype.hpoa"

# Also check evaluation datasets (may already be downloaded from benchmarks)
_EVAL_HPO_DIR = (
    Path(__file__).parent.parent.parent.parent.parent.parent
    / "evaluation" / "datasets" / "hpo"
)

# Module-level caches
_GENE_HPO_INDEX: Optional[Dict[str, Set[str]]] = None
_GENE_HPO_IDF: Optional[Dict[str, float]] = None
_HPO_DISEASE_PHENOTYPES: Optional[Dict[str, List[str]]] = None
_HPO_DISEASE_NAMES: Optional[Dict[str, str]] = None
_HPO_IDF: Optional[Dict[str, float]] = None
_UNIPROT_GENE_DISEASES: Dict[str, List[Dict]] = {}


def _resolve_hpo_path(filename: str) -> Optional[Path]:
    """Find HPO file: prefer production cache, fall back to eval datasets."""
    prod = _HPO_DATA_DIR / filename
    if prod.exists():
        return prod
    eval_path = _EVAL_HPO_DIR / filename
    if eval_path.exists():
        return eval_path
    return None


def _ensure_gene_hpo_index() -> Dict[str, Set[str]]:
    """Load genes_to_phenotype.txt into gene_symbol → set(HPO_terms)."""
    global _GENE_HPO_INDEX
    if _GENE_HPO_INDEX is not None:
        return _GENE_HPO_INDEX
    _GENE_HPO_INDEX = {}

    path = _resolve_hpo_path("genes_to_phenotype.txt")
    if path:
        lines = path.read_text(encoding="utf-8").splitlines()
    else:
        try:
            import requests as _req
            r = _req.get(
                "https://purl.obolibrary.org/obo/hp/hpoa/genes_to_phenotype.txt",
                timeout=(10, 60), allow_redirects=True,
            )
            r.raise_for_status()
            lines = r.text.splitlines()
            # Cache for future runs
            _HPO_DATA_DIR.mkdir(parents=True, exist_ok=True)
            (_HPO_DATA_DIR / "genes_to_phenotype.txt").write_text(r.text)
        except Exception as exc:
            logger.warning("Failed to download genes_to_phenotype.txt: %s", exc)
            return _GENE_HPO_INDEX

    for line in lines:
        if line.startswith("#") or line.startswith("ncbi_gene_id"):
            continue
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        gene_sym = parts[1].strip().upper()
        hpo_id = parts[2].strip()
        if not gene_sym or not hpo_id.startswith("HP:"):
            continue
        if gene_sym not in _GENE_HPO_INDEX:
            _GENE_HPO_INDEX[gene_sym] = set()
        _GENE_HPO_INDEX[gene_sym].add(hpo_id)

    logger.debug("Gene HPO index loaded: %d genes", len(_GENE_HPO_INDEX))
    return _GENE_HPO_INDEX


def _ensure_gene_hpo_idf() -> Dict[str, float]:
    """IDF weights per HPO term computed across all genes."""
    global _GENE_HPO_IDF
    if _GENE_HPO_IDF is not None:
        return _GENE_HPO_IDF
    gene_index = _ensure_gene_hpo_index()
    term_freq: Counter = Counter()
    N = len(gene_index)
    if N == 0:
        _GENE_HPO_IDF = {}
        return _GENE_HPO_IDF
    for hpo_terms in gene_index.values():
        for t in hpo_terms:
            term_freq[t] += 1
    _GENE_HPO_IDF = {t: math.log(N / (1.0 + freq)) for t, freq in term_freq.items()}
    return _GENE_HPO_IDF


def gene_hpo_overlap_score(patient_hpo: Set[str], gene_sym: str) -> float:
    """IDF-weighted HPO overlap between patient phenotypes and a gene's disease phenotypes."""
    gene_index = _ensure_gene_hpo_index()
    idf = _ensure_gene_hpo_idf()
    gene_hpo = gene_index.get(gene_sym.upper(), set())
    shared = patient_hpo & gene_hpo
    return sum(idf.get(t, 0.0) for t in shared)


def _fetch_gene_omim_diseases(gene_symbol: str, timeout: int = 6) -> List[Dict]:
    """Return [{omim_id, name}] for diseases linked to gene_symbol via UniProt."""
    key = gene_symbol.upper()
    if key in _UNIPROT_GENE_DISEASES:
        return _UNIPROT_GENE_DISEASES[key]

    diseases: List[Dict] = []
    try:
        import requests as _req

        # Step 1: Find UniProt accession
        r = _req.get(
            "https://rest.uniprot.org/uniprotkb/search",
            params={
                "query": f"gene_exact:{gene_symbol} AND organism_id:9606 AND reviewed:true",
                "fields": "accession",
                "format": "json",
                "size": 1,
            },
            timeout=(timeout, timeout),
        )
        uniprot_id = None
        if r.status_code == 200:
            results = r.json().get("results", [])
            if results:
                uniprot_id = results[0].get("primaryAccession", "")

        if not uniprot_id:
            _UNIPROT_GENE_DISEASES[key] = diseases
            return diseases

        # Step 2: Get phenotype MIM IDs from cross-references
        r2 = _req.get(
            f"https://rest.uniprot.org/uniprotkb/{uniprot_id}.json",
            timeout=(timeout, timeout),
        )
        if r2.status_code == 200:
            pheno_mims = []
            for ref in r2.json().get("uniProtKBCrossReferences", []):
                if ref.get("database") == "MIM":
                    mim_id = ref.get("id", "")
                    props = ref.get("properties", [])
                    type_val = next((p.get("value", "") for p in props if p.get("key") == "Type"), "")
                    if type_val.lower() in ("phenotype", ""):
                        pheno_mims.append(mim_id)

            if pheno_mims:
                r3 = _req.get(
                    "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi",
                    params={"db": "omim", "id": ",".join(pheno_mims), "retmode": "json"},
                    timeout=(timeout, timeout),
                )
                if r3.status_code == 200:
                    result_data = r3.json().get("result", {})
                    for mim_id in pheno_mims:
                        entry = result_data.get(mim_id, {})
                        title = entry.get("title", "")
                        diseases.append({
                            "omim_id": mim_id,
                            "name": title.title() if title else f"OMIM:{mim_id}",
                        })
    except Exception as exc:
        logger.debug("UniProt/OMIM fetch failed for %s: %s", gene_symbol, exc)

    _UNIPROT_GENE_DISEASES[key] = diseases
    return diseases


def _get_gene_summary(gene_symbol: str, timeout: int = 4) -> str:
    """Return one-line gene function summary from MyGene.info."""
    try:
        import requests as _req
        r = _req.get(
            "https://mygene.info/v3/query",
            params={"q": gene_symbol, "fields": "name,summary", "species": "human", "size": 1},
            timeout=(timeout, timeout),
        )
        r.raise_for_status()
        hits = r.json().get("hits", [])
        if hits:
            summary = (hits[0].get("summary") or "")[:160]
            return summary
    except Exception:
        pass
    return ""


class RareDiseaseRanker:
    """
    Rank candidate genes by phenotype overlap with a patient's HPO profile.

    Core method: rank_genes() returns formatted context for AI injection.
    """

    def rank_genes(
        self,
        patient_hpo_terms: List[str],
        candidate_genes: List[str],
        include_disease_list: bool = True,
        include_gene_summaries: bool = False,
        max_diseases: int = 5,
    ) -> str:
        """
        Rank candidate genes by IDF-weighted HPO phenotype overlap.

        Returns formatted context block for injection into AI assistant prompt.
        """
        if not patient_hpo_terms or not candidate_genes:
            return ""

        _ensure_gene_hpo_index()
        idf = _ensure_gene_hpo_idf()
        patient_set = set(patient_hpo_terms)

        # Score each gene
        scores: List[tuple] = []
        for gene in candidate_genes:
            score = gene_hpo_overlap_score(patient_set, gene)
            scores.append((gene, score))

        scores.sort(key=lambda x: x[1], reverse=True)

        lines = ["[Gene-Phenotype Match — HPO IDF-weighted overlap]"]
        lines.append(f"Patient HPO terms: {', '.join(patient_hpo_terms[:8])}")
        lines.append("Genes ranked by phenotype match (highest score = best match):")

        for gene, score in scores[:10]:
            gene_index = _ensure_gene_hpo_index()
            gene_hpo = gene_index.get(gene.upper(), set())
            shared = patient_set & gene_hpo
            raw_overlap = len(shared)
            lines.append(f"  {gene}: score={score:.2f}, shared HPO terms={raw_overlap}/{len(patient_hpo_terms)}")

        if include_disease_list:
            top_gene = scores[0][0] if scores else None
            if top_gene and scores[0][1] > 0:
                diseases = _fetch_gene_omim_diseases(top_gene)
                if diseases:
                    lines.append(f"\nTop gene {top_gene} associated diseases:")
                    for d in diseases[:max_diseases]:
                        lines.append(f"  - {d.get('name', '')} (OMIM:{d.get('omim_id', '')})")

        return "\n".join(lines)

    def lookup_gene_for_disease(
        self,
        gene_symbol: str,
        patient_hpo_terms: Optional[List[str]] = None,
    ) -> str:
        """
        Look up OMIM diseases for a single gene with optional patient phenotype scoring.
        Returns formatted evidence block.
        """
        result_parts = []

        # Gene summary
        summary = _get_gene_summary(gene_symbol)
        if summary:
            result_parts.append(f"{gene_symbol.upper()}: {summary}")

        # OMIM diseases
        diseases = _fetch_gene_omim_diseases(gene_symbol)
        if diseases and patient_hpo_terms:
            _ensure_gene_hpo_index()
            patient_set = set(patient_hpo_terms)
            for entry in diseases:
                gene_index = _ensure_gene_hpo_index()
                gene_hpo = gene_index.get(gene_symbol.upper(), set())
                score = gene_hpo_overlap_score(patient_set, gene_symbol)
                entry["overlap"] = score
            diseases.sort(key=lambda e: e.get("overlap", 0.0), reverse=True)

        if diseases:
            disease_lines = []
            for entry in diseases[:8]:
                line = f"  - {entry.get('name', '')} (OMIM:{entry.get('omim_id', '')})"
                if patient_hpo_terms and "overlap" in entry:
                    line += f" [phenotype score={entry['overlap']:.2f}]"
                disease_lines.append(line)
            result_parts.append(
                "Associated OMIM diseases:\n" + "\n".join(disease_lines)
            )

        return "\n".join(result_parts)
