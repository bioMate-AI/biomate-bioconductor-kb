"""
LLM-based Query Analyzer for Tool Search

Uses LLM to understand search queries without hardcoded rules:
- Extract explicit entities (database names, tool names, file formats)
- Infer category from context
- Generate expanded search terms (synonyms)
- Identify task type and expected data types
"""

import json
import logging
from dataclasses import dataclass, field
from typing import List, Optional, Dict, Any
from functools import lru_cache

log = logging.getLogger(__name__)


@dataclass
class QueryAnalysis:
    """Result of LLM-based query analysis."""
    explicit_entities: List[str] = field(default_factory=list)
    inferred_category: Optional[str] = None
    task_type: Optional[str] = None
    expanded_terms: List[str] = field(default_factory=list)
    data_types: List[str] = field(default_factory=list)
    original_query: str = ""

    def to_dict(self) -> Dict[str, Any]:
        return {
            'explicit_entities': self.explicit_entities,
            'inferred_category': self.inferred_category,
            'task_type': self.task_type,
            'expanded_terms': self.expanded_terms,
            'data_types': self.data_types,
            'original_query': self.original_query
        }


# Valid categories from the database
VALID_CATEGORIES = [
    "Alignment", "Assembly", "Biochemistry", "Bioengineering", "Biophysics",
    "Cancer Biology", "Cell Biology", "ChIP-seq", "Chromatin Analysis",
    "Climate Science", "Computational Chemistry", "Convert Formats",
    "CRISPR Analysis", "Data Export", "Data Managers", "Data Source",
    "Ecology", "Epigenetics", "Evolution", "FASTA/FASTQ", "Fetch Alignments",
    "Fetch Sequences", "Flow Cytometry", "Functional Analysis",
    "Genome Diversity", "Genome Editing", "Genomic Interval Operations",
    "Glycoengineering", "Graph/Display Data", "Imaging", "Immunology",
    "Mapping", "Mass Spectrometry", "Metabolomics", "Metagenomics",
    "Microbiology", "Molecular Biology", "Motif Tools", "Nanopore",
    "Neuroscience", "Next Gen Mappers", "Ontology Manipulation",
    "Peak Calling", "Pharmacology", "Phylogenetics", "Population Genetics",
    "Proteomics", "Quality Control", "RNA Analysis", "SAM/BAM",
    "Send Data", "Single-cell", "Statistics", "Structural Biology",
    "Synthetic Biology", "Systems Biology", "Text Manipulation",
    "Transcriptomics", "Variant Analysis", "Variant Calling", "VCF/BCF",
    "Virology", "Visualization"
]


QUERY_ANALYSIS_PROMPT = """Analyze this bioinformatics tool search query.

Query: "{user_query}"

Extract the following in JSON format:
{{
    "explicit_entities": [
        // Database names, tool names, file formats, or specific technologies mentioned
        // Examples: "UniProt", "FASTA", "BLAST", "PDB", "KEGG", "cellpose", "Scanpy"
        // Include abbreviations and full names
    ],
    "inferred_category":
        // Select ONE most appropriate category from this list:
        // {categories}
        // Return null if unclear
    ,
    "task_type":
        // Type of bioinformatics task, e.g.:
        // "database_query", "format_conversion", "sequence_alignment", "variant_calling",
        // "gene_expression", "enrichment_analysis", "image_segmentation", "phylogenetics",
        // "quality_control", "peak_calling", "protein_structure", "drug_discovery"
    ,
    "expanded_terms": [
        // Synonyms and related terms to improve search
        // For "UniProt" add: ["uniprotkb", "swiss-prot", "protein database", "protein sequence"]
        // For "cell segmentation" add: ["nuclei detection", "cellpose", "cellprofiler", "image analysis"]
        // Include common abbreviations and alternative names
    ],
    "data_types": [
        // Input/output data types expected
        // Examples: "protein sequences", "FASTA", "gene list", "microscopy images", "VCF"
    ]
}}

Rules:
1. Extract ALL mentioned databases, tools, and file formats as explicit_entities
2. Be generous with expanded_terms - include synonyms, related tools, and common alternatives
3. Only return valid JSON, no explanation
4. If a specific tool is mentioned (e.g., "cellpose", "DESeq2"), include it in explicit_entities"""


class LLMQueryAnalyzer:
    """Use LLM to understand search queries without hardcoded rules."""

    def __init__(self, llm_client):
        """
        Initialize the query analyzer.

        Args:
            llm_client: LLM client with generate() method
        """
        self.llm = llm_client
        self._cache: Dict[str, QueryAnalysis] = {}

    def analyze(self, query: str, use_cache: bool = True) -> QueryAnalysis:
        """
        Analyze query using LLM.

        Args:
            query: User's search query
            use_cache: Whether to use cached results

        Returns:
            QueryAnalysis with extracted information
        """
        query = query.strip()

        if not query:
            return QueryAnalysis(original_query=query)

        # Check cache
        if use_cache and query in self._cache:
            log.debug(f"Cache hit for query: {query[:50]}...")
            return self._cache[query]

        # Build prompt with valid categories
        categories_str = ", ".join(VALID_CATEGORIES[:30]) + "..."  # Truncate for prompt length
        prompt = QUERY_ANALYSIS_PROMPT.format(
            user_query=query,
            categories=categories_str
        )

        try:
            response = self.llm.generate(prompt, max_tokens=800)
            analysis = self._parse_response(response, query)

            # Cache result
            if use_cache:
                self._cache[query] = analysis

            log.info(f"Query analysis: entities={analysis.explicit_entities}, "
                    f"category={analysis.inferred_category}, "
                    f"expanded={len(analysis.expanded_terms)} terms")

            return analysis

        except Exception as e:
            log.error(f"Query analysis failed: {e}")
            return self._fallback_analysis(query)

    def _parse_response(self, response: str, original_query: str) -> QueryAnalysis:
        """Parse LLM response into QueryAnalysis."""
        # Clean response - extract JSON if wrapped in markdown
        response = response.strip()
        if response.startswith("```"):
            lines = response.split("\n")
            response = "\n".join(lines[1:-1] if lines[-1].startswith("```") else lines[1:])

        try:
            data = json.loads(response)

            # Validate category
            category = data.get('inferred_category')
            if category and category not in VALID_CATEGORIES:
                # Try to find closest match
                category_lower = category.lower()
                for valid_cat in VALID_CATEGORIES:
                    if category_lower in valid_cat.lower() or valid_cat.lower() in category_lower:
                        category = valid_cat
                        break
                else:
                    category = None

            return QueryAnalysis(
                explicit_entities=data.get('explicit_entities', []),
                inferred_category=category,
                task_type=data.get('task_type'),
                expanded_terms=data.get('expanded_terms', []),
                data_types=data.get('data_types', []),
                original_query=original_query
            )
        except json.JSONDecodeError as e:
            log.warning(f"Failed to parse LLM response as JSON: {e}")
            return self._fallback_analysis(original_query)

    def _fallback_analysis(self, query: str) -> QueryAnalysis:
        """
        Fallback analysis when LLM fails.
        Uses simple keyword extraction without hardcoded mappings.
        """
        words = query.lower().split()

        # Extract potential entities (capitalized words, words > 3 chars)
        entities = []
        for word in query.split():
            # Keep original case for proper nouns
            if word[0].isupper() or len(word) > 4:
                clean_word = word.strip('.,;:!?()[]{}')
                if clean_word and len(clean_word) > 2:
                    entities.append(clean_word)

        # Simple expanded terms - just the query words
        expanded = [w for w in words if len(w) > 3]

        return QueryAnalysis(
            explicit_entities=entities[:10],
            inferred_category=None,
            task_type=None,
            expanded_terms=expanded[:15],
            data_types=[],
            original_query=query
        )

    def clear_cache(self):
        """Clear the analysis cache."""
        self._cache.clear()

    def get_cache_stats(self) -> Dict[str, int]:
        """Get cache statistics."""
        return {
            'size': len(self._cache),
            'queries': list(self._cache.keys())[:10]
        }


class SimpleQueryAnalyzer:
    """
    Lightweight query analyzer that doesn't require LLM.
    Uses pattern matching for common bioinformatics terms.
    Useful for testing or when LLM is unavailable.
    """

    # Common bioinformatics databases and their variations
    KNOWN_DATABASES = {
        'uniprot': ['uniprot', 'uniprotkb', 'swiss-prot', 'swissprot', 'trembl'],
        'pdb': ['pdb', 'protein data bank', 'rcsb'],
        'kegg': ['kegg', 'kyoto encyclopedia'],
        'ncbi': ['ncbi', 'genbank', 'refseq', 'sra', 'geo'],
        'ensembl': ['ensembl', 'biomart'],
        'go': ['gene ontology', 'go enrichment', 'go terms'],
        'interpro': ['interpro', 'protein families'],
        'pfam': ['pfam', 'protein families'],
        'blast': ['blast', 'blastn', 'blastp', 'blastx'],
        'clustal': ['clustal', 'clustalw', 'clustalo'],
    }

    # Category inference patterns
    CATEGORY_PATTERNS = {
        'Data Source': ['query', 'database', 'fetch', 'download', 'retrieve', 'search'],
        'Proteomics': ['protein', 'peptide', 'mass spec', 'proteom'],
        'Genomics': ['genome', 'dna', 'sequencing', 'variant', 'snp'],
        'Transcriptomics': ['rna', 'expression', 'transcript', 'rnaseq'],
        'Imaging': ['image', 'microscopy', 'cell', 'segment', 'fluorescence'],
        'Functional Analysis': ['enrichment', 'pathway', 'ontology', 'annotation', 'gsea'],
        'Single-cell': ['single-cell', 'scrna', 'scanpy', 'seurat', '10x'],
        'Alignment': ['align', 'alignment', 'map', 'bowtie', 'bwa', 'hisat'],
        'Quality Control': ['quality', 'qc', 'fastqc', 'trim'],
        'Phylogenetics': ['phylogen', 'tree', 'evolution', 'clade'],
    }

    def analyze(self, query: str) -> QueryAnalysis:
        """Analyze query using pattern matching."""
        query_lower = query.lower()

        # Extract entities
        entities = []
        for db_key, variations in self.KNOWN_DATABASES.items():
            for var in variations:
                if var in query_lower:
                    entities.append(db_key.upper())
                    break

        # Infer category
        category = None
        max_score = 0
        for cat, patterns in self.CATEGORY_PATTERNS.items():
            score = sum(1 for p in patterns if p in query_lower)
            if score > max_score:
                max_score = score
                category = cat

        # Generate expanded terms
        words = query_lower.split()
        expanded = [w for w in words if len(w) > 3]

        return QueryAnalysis(
            explicit_entities=entities,
            inferred_category=category if max_score > 0 else None,
            task_type=None,
            expanded_terms=expanded,
            data_types=[],
            original_query=query
        )
