"""
Genomic variant knowledge enrichment for BioMate AI assistant.

Provides context about genetic variants (rsIDs) for user queries about:
- GWAS associations for a phenotype
- Variant functional annotation
- Nearest protein-coding genes

Data sources (in priority order):
1. Local GWAS Catalog index (pre-built, 424K rsIDs, no rate limits)
2. GWAS Catalog REST API (persistent HTTP cache, avoids rate limits)
3. Ensembl REST API (batch variant → gene annotation, persistently cached)
4. ClinVar (clinical significance for pathogenic variants)

Usage:
    from backend.lib.galaxy.ai.knowledge.variant_enrichment import VariantEnricher
    enricher = VariantEnricher()
    context = enricher.enrich_variants(phenotype="Homocysteine", rsids=["rs1801133", "rs4244285"])
"""

from __future__ import annotations

import json
import logging
import re
from pathlib import Path
from typing import Dict, List, Optional, Any

from .api_cache import PersistentAPICache

logger = logging.getLogger(__name__)

# Shared persistent caches — one process-level instance per cache
_gwas_cache = PersistentAPICache("gwas_catalog")
_clinvar_cache = PersistentAPICache("clinvar")

# Ensembl gene annotation: rsid → "GENE1, GENE2" (nearest protein-coding genes)
_ENSEMBL_GENE_CACHE: Dict[str, str] = {}
_ENSEMBL_GENE_CACHE_PATH: Optional[Path] = None
_ENSEMBL_GENE_CACHE_DIRTY = False

# Local GWAS Catalog index (pre-built pickle, 424K rsIDs)
_GWAS_LOCAL_INDEX: Optional[Dict[str, list]] = None


def _get_ensembl_cache_path() -> Path:
    global _ENSEMBL_GENE_CACHE_PATH
    if _ENSEMBL_GENE_CACHE_PATH is None:
        base = Path(__file__).parent.parent.parent.parent.parent / "database" / "knowledge_cache"
        base.mkdir(parents=True, exist_ok=True)
        _ENSEMBL_GENE_CACHE_PATH = base / "ensembl_gene_cache.json"
        # Also check evaluation datasets location (may already be populated from benchmarks)
        eval_path = (
            Path(__file__).parent.parent.parent.parent.parent.parent
            / "evaluation" / "datasets" / "hpo" / "ensembl_gene_cache.json"
        )
        if eval_path.exists() and not _ENSEMBL_GENE_CACHE_PATH.exists():
            import shutil
            shutil.copy(eval_path, _ENSEMBL_GENE_CACHE_PATH)
    return _ENSEMBL_GENE_CACHE_PATH


def _load_ensembl_cache() -> None:
    global _ENSEMBL_GENE_CACHE
    if _ENSEMBL_GENE_CACHE:
        return
    p = _get_ensembl_cache_path()
    if p.exists():
        try:
            with open(p) as f:
                _ENSEMBL_GENE_CACHE.update(json.load(f))
            logger.debug("Ensembl gene cache loaded: %d entries", len(_ENSEMBL_GENE_CACHE))
        except Exception as exc:
            logger.debug("Failed to load Ensembl gene cache: %s", exc)


def _save_ensembl_cache() -> None:
    global _ENSEMBL_GENE_CACHE_DIRTY
    if not _ENSEMBL_GENE_CACHE_DIRTY:
        return
    p = _get_ensembl_cache_path()
    try:
        with open(p, "w") as f:
            json.dump(_ENSEMBL_GENE_CACHE, f)
        _ENSEMBL_GENE_CACHE_DIRTY = False
    except Exception as exc:
        logger.debug("Failed to save Ensembl gene cache: %s", exc)


def annotate_variants_with_genes(rsids: List[str], window: int = 25000) -> Dict[str, str]:
    """
    For each rsID, return nearby protein-coding genes via Ensembl REST.
    Results cached persistently. Returns {rsid: "GENE1, GENE2"}.

    Pre-populate before parallel processing:
        annotate_variants_with_genes(all_rsids)  # sequential, fills cache
        # now parallel calls hit cache instantly
    """
    global _ENSEMBL_GENE_CACHE_DIRTY
    _load_ensembl_cache()

    need_pos = [r for r in rsids if r not in _ENSEMBL_GENE_CACHE]
    if not need_pos:
        return {r: _ENSEMBL_GENE_CACHE.get(r, "") for r in rsids}

    positions: Dict[str, tuple] = {}
    try:
        import requests as _req
        r = _req.post(
            "https://rest.ensembl.org/variation/human",
            json={"ids": need_pos[:200]},
            headers={"Content-Type": "application/json", "Accept": "application/json"},
            timeout=(5, 15),
        )
        if r.ok:
            for rsid, data in r.json().items():
                mappings = data.get("mappings", [])
                if mappings:
                    loc = mappings[0]
                    positions[rsid] = (loc.get("seq_region_name", ""), loc.get("start", 0))
    except Exception as exc:
        logger.debug("Ensembl variant batch failed: %s", exc)

    for rsid, (chrom, pos) in positions.items():
        if not chrom or not pos:
            _ENSEMBL_GENE_CACHE[rsid] = ""
            _ENSEMBL_GENE_CACHE_DIRTY = True
            continue
        try:
            import requests as _req
            r2 = _req.get(
                f"https://rest.ensembl.org/overlap/region/human/{chrom}:{max(1,pos-window)}-{pos+window}",
                params={"feature": "gene", "content-type": "application/json"},
                timeout=(4, 10),
            )
            if r2.ok:
                genes = r2.json()
                names = [g.get("external_name", "") for g in genes
                         if g.get("external_name") and g.get("biotype") == "protein_coding"]
                gene_set = list(dict.fromkeys(n for n in names if n))[:4]
                _ENSEMBL_GENE_CACHE[rsid] = ", ".join(gene_set)
            else:
                _ENSEMBL_GENE_CACHE[rsid] = ""
            _ENSEMBL_GENE_CACHE_DIRTY = True
        except Exception as exc:
            logger.debug("Ensembl gene overlap failed for %s: %s", rsid, exc)
            _ENSEMBL_GENE_CACHE[rsid] = ""

    for rsid in need_pos:
        if rsid not in _ENSEMBL_GENE_CACHE:
            _ENSEMBL_GENE_CACHE[rsid] = ""
            _ENSEMBL_GENE_CACHE_DIRTY = True

    if _ENSEMBL_GENE_CACHE_DIRTY:
        _save_ensembl_cache()

    return {r: _ENSEMBL_GENE_CACHE.get(r, "") for r in rsids}


def _trait_relevance_score(gwas_trait: str, query_phenotype: str) -> float:
    """
    Score how relevant a GWAS Catalog trait name is to the query phenotype.
    Returns 1.0 for exact/near match, lower for partial, 0.0 for unrelated.
    Handles metabolite/biomarker measurement synonyms.
    """
    qt = query_phenotype.lower().strip()
    gt = gwas_trait.lower().strip()

    if qt in gt or gt in qt:
        return 1.0

    _MEASUREMENT_SUFFIXES = (
        " measurement", " levels", " level", " concentration", " concentrations",
        " amount", " amounts", " blood", " serum", " plasma", " urinary",
        " circulating", " fasting", " total", " free",
    )
    qt_clean = qt
    gt_clean = gt
    for suffix in _MEASUREMENT_SUFFIXES:
        if gt_clean.endswith(suffix):
            gt_clean = gt_clean[: -len(suffix)].strip()
        if qt_clean.endswith(suffix):
            qt_clean = qt_clean[: -len(suffix)].strip()

    if qt_clean == gt_clean or qt_clean in gt_clean or gt_clean in qt_clean:
        return 1.0

    def _normalize_chem(s: str) -> set:
        parts = re.split(r"\s*/\s*|\s+or\s+", s, flags=re.IGNORECASE)
        tokens = set()
        for part in parts:
            part = re.sub(r"^[LDNld]-", "", part.strip())
            for tok in re.split(r"[-\s,]+", part):
                tok = tok.lower().strip()
                if len(tok) >= 3:
                    tokens.add(tok)
        return tokens

    stops = {"of", "the", "a", "an", "and", "or", "in", "for", "to", "with", "by",
              "amount", "level", "levels", "measurement", "blood", "serum", "plasma"}
    qt_words = _normalize_chem(qt_clean) - stops
    gt_words = _normalize_chem(gt_clean) - stops
    if not qt_words:
        return 0.0
    return len(qt_words & gt_words) / len(qt_words)


def enrich_variants_gwas(
    phenotype: str,
    candidate_rsids: List[str],
    timeout: int = 5,
) -> str:
    """
    Fetch GWAS Catalog associations for each candidate rsID, filtered to the
    query phenotype. Returns formatted context block or empty string.

    Uses persistent HTTP cache — the first run may hit the API, subsequent
    runs are instant (cache hit). Never rate-limited after warm-up.
    """
    if not candidate_rsids or not phenotype:
        return ""

    scored: List[tuple] = []  # (rsid, p_float, gwas_trait, relevance)

    for rsid in candidate_rsids:
        url = (
            f"https://www.ebi.ac.uk/gwas/rest/api/singleNucleotidePolymorphisms/"
            f"{rsid}/associations?projection=associationBySnp"
        )
        data = _gwas_cache.fetch(url, timeout=timeout)
        if data is None:
            continue
        try:
            assoc_list = data.get("_embedded", {}).get("associations", [])
            for assoc in assoc_list[:20]:
                traits = (
                    [t.get("trait", "") for t in assoc.get("efoTraits", [])]
                    or [t.get("trait", "") for t in assoc.get("diseaseTrait", [{"trait": ""}])]
                )
                traits = [t for t in traits if t]
                if not traits:
                    continue
                best_rel = max(_trait_relevance_score(t, phenotype) for t in traits)
                _pheno_words = len([w for w in phenotype.replace("/", " ").split() if len(w) >= 3])
                _rel_threshold = 0.15 if _pheno_words <= 2 else 0.3
                if best_rel < _rel_threshold:
                    continue
                pval = assoc.get("pvalue") or assoc.get("pvalueMantissa")
                pexp = assoc.get("pvalueExponent")
                p_float = None
                if pval is not None and pexp is not None:
                    try:
                        pval_f = float(pval)
                        p_float = pval_f if 'e' in str(pval).lower() else pval_f * (10 ** int(pexp))
                    except Exception:
                        pass
                elif pval is not None:
                    try:
                        p_float = float(pval)
                    except Exception:
                        pass
                if p_float is not None:
                    best_trait = max(traits, key=lambda t: _trait_relevance_score(t, phenotype))
                    scored.append((rsid, p_float, best_trait, best_rel))
        except Exception as exc:
            logger.debug("GWAS trait-filtered lookup error for %s: %s", rsid, exc)

    if not scored:
        return ""

    best: Dict[str, tuple] = {}
    for rsid, p_float, trait, rel in scored:
        if rsid not in best or p_float < best[rsid][1]:
            best[rsid] = (rsid, p_float, trait, rel)

    ranked = sorted(best.values(), key=lambda x: x[1])
    lines = [f"[GWAS Catalog — {phenotype}-specific variant rankings]"]
    lines.append(f"Ranked by {phenotype} association (lowest p = most significant):")
    for rsid, p_float, trait, rel in ranked:
        lines.append(f"  {rsid}: p={p_float:.2e} [{trait}]")
    no_data = [r for r in candidate_rsids if r not in best]
    if no_data:
        lines.append(f"  No {phenotype}-specific data: {', '.join(no_data[:8])}")
    return "\n".join(lines)


def enrich_variants_genes(rsids: List[str]) -> str:
    """
    Return a formatted block of nearest protein-coding genes for each rsID.
    Uses Ensembl REST (persistently cached).
    """
    if not rsids:
        return ""
    ann = annotate_variants_with_genes(rsids)
    lines = [f"  {rsid}: {genes}" for rsid, genes in ann.items() if genes]
    if not lines:
        return ""
    return "[Nearest protein-coding genes via Ensembl]\n" + "\n".join(lines)


def get_clinvar_significance(rsid: str, timeout: int = 4) -> str:
    """
    Query NCBI ClinVar for clinical significance of a variant.
    Returns "Pathogenic", "Likely_Pathogenic", "Uncertain_Significance",
    "Benign", "Likely_Benign", or "" (not in ClinVar).
    """
    cached = _clinvar_cache.get(rsid)
    if cached is not None:
        return cached

    sig = ""
    try:
        import requests as _req
        search_r = _req.get(
            "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi",
            params={"db": "clinvar", "term": f"{rsid}[RS]", "retmode": "json", "retmax": "5"},
            timeout=(timeout, timeout),
        )
        search_r.raise_for_status()
        ids = search_r.json().get("esearchresult", {}).get("idlist", [])
        if ids:
            sum_r = _req.get(
                "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi",
                params={"db": "clinvar", "id": ids[0], "retmode": "json"},
                timeout=(timeout, timeout),
            )
            sum_r.raise_for_status()
            doc = sum_r.json().get("result", {}).get(ids[0], {})
            for field in ("germline_classification", "clinical_significance"):
                clin = doc.get(field, {})
                sig = clin.get("description", "") if isinstance(clin, dict) else clin
                if sig:
                    break
    except Exception as exc:
        logger.debug("ClinVar fetch failed for %s: %s", rsid, exc)

    _clinvar_cache.set(rsid, sig)
    return sig


class VariantEnricher:
    """
    High-level interface for variant context enrichment.

    Used by ai_assistant.py to inject rich GWAS + gene context when the user
    asks about genetic variants, GWAS hits, or variant prioritization.
    """

    def enrich_variants(
        self,
        phenotype: str,
        rsids: List[str],
        include_genes: bool = True,
        include_clinvar: bool = False,
    ) -> str:
        """
        Build a context block for the AI assistant containing:
        1. GWAS Catalog phenotype-specific rankings
        2. Nearest protein-coding genes (optional)
        3. ClinVar significance for pathogenic-looking variants (optional)

        Returns formatted multi-section string or empty string if no data.
        """
        parts = []

        gwas_ctx = enrich_variants_gwas(phenotype, rsids)
        if gwas_ctx:
            parts.append(gwas_ctx)

        if include_genes:
            gene_ctx = enrich_variants_genes(rsids)
            if gene_ctx:
                parts.append(gene_ctx)

        if include_clinvar:
            clinvar_lines = []
            for rsid in rsids[:5]:  # limit to avoid rate limiting
                sig = get_clinvar_significance(rsid)
                if sig:
                    clinvar_lines.append(f"  {rsid}: {sig}")
            if clinvar_lines:
                parts.append("[ClinVar Clinical Significance]\n" + "\n".join(clinvar_lines))

        return "\n\n".join(parts)

    def get_format_instruction(self, phenotype: str) -> str:
        """
        Return format instruction for the AI to use GWAS context correctly.
        Prevents the model from ignoring the provided context.
        """
        return (
            f"PRIORITY ORDER for selecting the most promising {phenotype} variant:\n"
            f"1. GWAS CATALOG RANK: If the context contains phenotype-specific GWAS rankings, "
            f"the variant ranked #1 (lowest p-value) IS the answer.\n"
            f"2. GENE-PATHWAY MATCH: If no GWAS data is available for most candidates, use the "
            f"nearest gene list to identify variants in genes with a direct biochemical role "
            f"in {phenotype} metabolism. CAUTION: only for specific chemical entities (amino "
            f"acids, phospholipids, organic acids), NOT complex traits.\n"
            f"3. TRAINING KNOWLEDGE: Fallback when no external data is available.\n"
            f"Respond with ONLY the rsID. Nothing else."
        )
