"""
Domain Router Agent

Lightweight router that classifies requests into domains using keyword matching.
NO LLM calls - uses pre-computed domain keywords for speed.

Leverages:
- Biomni domain structure (22 domains)
- Galaxy tool categories (59+ categories)
- User patterns for personalization
"""

import logging
from dataclasses import dataclass, field
from typing import List, Dict, Optional, Set
import re

log = logging.getLogger(__name__)


@dataclass
class RoutingDecision:
    """Result of domain routing."""
    primary_domain: str
    secondary_domains: List[str] = field(default_factory=list)
    confidence: float = 0.0
    complexity: str = "standard"  # simple, standard, complex
    matched_keywords: List[str] = field(default_factory=list)


class DomainRouter:
    """
    Routes queries to appropriate domain specialists using keyword matching.

    Design principles:
    - NO LLM calls (fast, deterministic)
    - Leverage existing Biomni domain taxonomy
    - Boost by user patterns when available
    """

    # Domain keywords mapped to Biomni/Galaxy categories
    # These map to tool_id patterns like 'biomni/genomics/...'
    DOMAIN_KEYWORDS: Dict[str, Set[str]] = {
        # Core omics domains
        "genomics": {
            "genome", "genomic", "dna", "sequencing", "alignment", "mapping", "bwa", "hisat",
            "variant", "snp", "indel", "vcf", "bam", "sam", "fastq", "fasta",
            "chromosome", "exome", "wgs", "wes", "chip-seq", "atac-seq", "dnase",
            "methylation", "epigenetic", "chromatin", "nucleotide", "basepair"
        },
        "transcriptomics": {
            "rna-seq", "rnaseq", "rna", "transcript", "gene expression", "mrna",
            "differential expression", "deseq", "edger", "kallisto", "salmon",
            "star", "featurecounts", "htseq", "cufflinks", "stringtie", "tpm", "fpkm",
            "transcriptome", "transcriptomic", "transcriptomics"
        },
        "proteomics": {
            "protein", "proteome", "proteomics", "proteomic",
            "mass spec", "mass spectrometry", "ms/ms", "peptide",
            "dia", "dda", "maxquant", "skyline", "fragpipe", "openms", "mascot",
            "phospho", "ptm", "itraq", "tmt", "silac", "orbitrap", "maldi"
        },
        "metabolomics": {
            "metabolite", "metabolome", "metabolomics", "metabolomic",
            "xcms", "msdial", "metaboanalyst", "small molecule",
            "lipid", "lipidomics", "mzml", "mzxml", "peak detection",
            "compound identification", "lc-ms", "gc-ms", "nmr spectroscopy",
            "untargeted metabolomics", "targeted metabolomics", "pathway"
        },

        # Specialized domains
        "single-cell": {
            "single-cell", "scrnaseq", "scrna", "10x", "cellranger", "seurat",
            "scanpy", "harmony", "scvi", "cell type", "clustering", "umap",
            "trajectory", "pseudotime", "velocity", "anndata"
        },
        "metagenomics": {
            "metagenome", "microbiome", "16s", "shotgun", "kraken", "metaphlan",
            "humann", "qiime", "dada2", "amplicon", "otu", "asv", "taxonomy"
        },
        "structural_biology": {
            "structure", "pdb", "alphafold", "protein structure", "3d",
            "molecular dynamics", "docking", "binding", "conformation",
            "fold", "domain", "motif", "secondary structure"
        },
        "pharmacology": {
            "drug", "admet", "pharmacokinetics", "toxicity", "binding affinity",
            "compound", "therapeutic", "dose", "clinical", "adverse", "fda"
        },
        "immunology": {
            "immune", "antibody", "antigen", "t-cell", "b-cell", "cytokine",
            "flow cytometry", "facs", "immunophenotyping", "tcr", "bcr"
        },
        "cancer_biology": {
            "cancer", "tumor", "oncology", "mutation", "somatic", "driver",
            "copy number", "cnv", "tcga", "maf", "oncogene", "suppressor"
        },

        # Technical domains
        "bioimaging": {
            "image", "microscopy", "segmentation", "cell counting", "fluorescence",
            "confocal", "nifti", "registration", "nnunet", "cellpose"
        },
        "molecular_biology": {
            "primer", "pcr", "cloning", "plasmid", "restriction", "golden gate",
            "crispr", "guide rna", "knockout", "knockin", "gibson"
        },
        "biochemistry": {
            "enzyme", "kinetics", "michaelis", "binding", "thermodynamics",
            "assay", "spectroscopy", "circular dichroism", "itc"
        },

        # Infrastructure domains
        "database": {
            "database", "query", "uniprot", "ncbi", "ensembl", "pubmed",
            "kegg", "reactome", "go", "interpro", "blast", "fetch"
        },
        "literature": {
            "literature", "paper", "pubmed", "arxiv", "scholar", "citation",
            "search", "review", "abstract", "doi"
        },
    }

    # Map domains to Galaxy categories for tool filtering
    DOMAIN_TO_CATEGORY: Dict[str, List[str]] = {
        "genomics": ["Sequence Analysis", "Variant Analysis", "Next Gen Mappers", "SAM"],
        "transcriptomics": ["RNA", "Transcriptomics", "Sequence Analysis"],
        "proteomics": ["Proteomics", "Mass Spectrometry"],
        "metabolomics": ["Metabolomics", "Mass Spectrometry"],
        "single-cell": ["Single-cell", "RNA", "Transcriptomics"],
        "metagenomics": ["Metagenomics", "Ecology"],
        "structural_biology": ["Structural Biology", "Computational chemistry"],
        "pharmacology": ["Pharmacology", "Computational chemistry"],
        "immunology": ["Immunology"],
        "cancer_biology": ["Cancer Biology", "Variant Analysis"],
        "bioimaging": ["Imaging", "Graphics"],
        "molecular_biology": ["Molecular Biology", "Sequence Analysis"],
        "biochemistry": ["Biochemistry"],
        "database": ["Data Source", "Web Services"],
        "literature": ["Literature"],
    }

    # Complexity indicators
    COMPLEX_INDICATORS = {
        "multi-omics", "integration", "combined", "comprehensive",
        "end-to-end", "pipeline", "workflow", "full analysis"
    }

    SIMPLE_INDICATORS = {
        "what is", "how to", "explain", "help", "list", "show",
        "find", "search", "query", "fetch"
    }

    def __init__(self, user_patterns_service=None):
        """
        Initialize domain router.

        Args:
            user_patterns_service: Optional service to get user preferences
        """
        self.user_patterns = user_patterns_service

        # Build inverted index: keyword -> domains
        self._keyword_index: Dict[str, List[str]] = {}
        for domain, keywords in self.DOMAIN_KEYWORDS.items():
            for keyword in keywords:
                if keyword not in self._keyword_index:
                    self._keyword_index[keyword] = []
                self._keyword_index[keyword].append(domain)

        log.info(f"DomainRouter initialized with {len(self.DOMAIN_KEYWORDS)} domains")

    def route(
        self,
        query: str,
        user_id: Optional[str] = None,
        user_context: Optional[Dict] = None
    ) -> RoutingDecision:
        """
        Route a query to appropriate domains.

        Args:
            query: User's query text
            user_id: Optional user ID for personalization
            user_context: Optional pre-loaded user context

        Returns:
            RoutingDecision with primary/secondary domains
        """
        query_lower = query.lower()

        # Score each domain by keyword matches
        domain_scores: Dict[str, float] = {}
        matched_keywords: List[str] = []

        for domain, keywords in self.DOMAIN_KEYWORDS.items():
            score = 0.0
            for keyword in keywords:
                # Check for keyword in query (word boundary aware)
                if re.search(rf'\b{re.escape(keyword)}\b', query_lower):
                    score += 1.0
                    matched_keywords.append(keyword)
                # Partial match (less weight)
                elif keyword in query_lower:
                    score += 0.5

            if score > 0:
                domain_scores[domain] = score

        # Boost by user patterns if available
        if user_context and user_context.get('domain_preference'):
            pref_domain = user_context['domain_preference']
            if pref_domain in domain_scores:
                domain_scores[pref_domain] *= 1.3
            elif pref_domain in self.DOMAIN_KEYWORDS:
                domain_scores[pref_domain] = 0.5  # Add preferred domain even without match

        # Sort domains by score
        sorted_domains = sorted(domain_scores.items(), key=lambda x: -x[1])

        # Determine primary and secondary domains
        if not sorted_domains:
            # Default to genomics if no matches
            primary = "genomics"
            secondary = []
            confidence = 0.1
        else:
            primary = sorted_domains[0][0]
            confidence = min(1.0, sorted_domains[0][1] / 3.0)  # Normalize

            # Secondary domains (at least 50% of primary score)
            secondary = [
                d for d, s in sorted_domains[1:3]
                if s >= sorted_domains[0][1] * 0.5
            ]

        # Assess complexity
        complexity = self._assess_complexity(query_lower)

        decision = RoutingDecision(
            primary_domain=primary,
            secondary_domains=secondary,
            confidence=confidence,
            complexity=complexity,
            matched_keywords=list(set(matched_keywords))[:10]
        )

        log.info(f"Routed query to {primary} (conf={confidence:.2f}, "
                f"secondary={secondary}, complexity={complexity})")

        return decision

    def _assess_complexity(self, query_lower: str) -> str:
        """Assess query complexity based on indicators."""
        # Check for complex indicators
        complex_count = sum(1 for ind in self.COMPLEX_INDICATORS if ind in query_lower)
        simple_count = sum(1 for ind in self.SIMPLE_INDICATORS if ind in query_lower)

        if complex_count >= 2 or "multi" in query_lower:
            return "complex"
        elif simple_count >= 2 or len(query_lower.split()) <= 5:
            return "simple"
        else:
            return "standard"

    def get_category_filter(self, domain: str) -> List[str]:
        """Get Galaxy categories for a domain."""
        return self.DOMAIN_TO_CATEGORY.get(domain, [])

    def get_all_domains(self) -> List[str]:
        """Get list of all supported domains."""
        return list(self.DOMAIN_KEYWORDS.keys())
