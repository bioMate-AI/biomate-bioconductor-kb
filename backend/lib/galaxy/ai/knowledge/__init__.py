"""
BioMate AI knowledge enrichment modules.

Provides real-time biomedical database lookups that inject evidence into
the AI assistant's context, improving answer quality for:

- Genomic variant queries (GWAS, Ensembl gene annotation, ClinVar)
- Rare disease diagnosis (HPO IDF-weighted gene-phenotype overlap)
- CRISPR screen analysis (BioGRID ORCS ranked hits)
- General API caching (prevents rate limiting for all external APIs)

All modules use persistent caching so repeated queries are instant.
"""

from .api_cache import PersistentAPICache
from .variant_enrichment import VariantEnricher, enrich_variants_gwas, annotate_variants_with_genes
from .rare_disease import RareDiseaseRanker, gene_hpo_overlap_score
from .crispr_screens import CRISPRScreenKnowledge, lookup_screen

__all__ = [
    "PersistentAPICache",
    "VariantEnricher",
    "enrich_variants_gwas",
    "annotate_variants_with_genes",
    "RareDiseaseRanker",
    "gene_hpo_overlap_score",
    "CRISPRScreenKnowledge",
    "lookup_screen",
]
