"""
Enhanced Domain Router

Hybrid router combining fast keyword matching with LLM semantic analysis.
Uses LLM only when keyword confidence is low, with caching to minimize API calls.

Features:
- Fast path: Keyword matching for high-confidence routing (<10ms)
- LLM path: Semantic analysis for ambiguous queries (~500ms)
- User pattern boosting for personalization
- LRU cache for LLM decisions
- Learned keywords from user corrections
"""

import json
import logging
import hashlib
import time
import re
import sqlite3
from dataclasses import dataclass, field
from typing import List, Dict, Optional, Set, Any
from datetime import datetime, timedelta
from collections import OrderedDict

log = logging.getLogger(__name__)


@dataclass
class EnhancedRoutingDecision:
    """Result of enhanced domain routing."""
    primary_domain: str
    secondary_domains: List[str] = field(default_factory=list)
    confidence: float = 0.0
    complexity: str = "standard"  # simple, standard, complex
    matched_keywords: List[str] = field(default_factory=list)
    routing_method: str = "keyword"  # 'keyword', 'llm', 'hybrid'
    llm_reasoning: Optional[str] = None
    latency_ms: int = 0
    user_boost_applied: bool = False


class LRUCache:
    """Simple LRU cache for routing decisions."""

    def __init__(self, max_size: int = 1000, ttl_seconds: int = 3600):
        self.max_size = max_size
        self.ttl_seconds = ttl_seconds
        self._cache: OrderedDict = OrderedDict()
        self._timestamps: Dict[str, float] = {}

    def get(self, key: str) -> Optional[Any]:
        """Get item from cache if not expired."""
        if key not in self._cache:
            return None

        # Check TTL
        if time.time() - self._timestamps[key] > self.ttl_seconds:
            del self._cache[key]
            del self._timestamps[key]
            return None

        # Move to end (most recently used)
        self._cache.move_to_end(key)
        return self._cache[key]

    def put(self, key: str, value: Any):
        """Add item to cache."""
        if key in self._cache:
            self._cache.move_to_end(key)
        else:
            if len(self._cache) >= self.max_size:
                # Remove oldest
                oldest = next(iter(self._cache))
                del self._cache[oldest]
                del self._timestamps[oldest]

        self._cache[key] = value
        self._timestamps[key] = time.time()

    def clear(self):
        """Clear the cache."""
        self._cache.clear()
        self._timestamps.clear()


class EnhancedDomainRouter:
    """
    Enhanced domain router with hybrid keyword + LLM routing.

    Design principles:
    - Fast path for high confidence (>0.7) keyword matches
    - LLM analysis for low confidence or ambiguous queries
    - User pattern boosting for personalization
    - Caching to minimize LLM costs
    - Learned keywords from user corrections
    """

    # LLM confidence threshold - below this, use LLM
    LLM_THRESHOLD = 0.7

    # Domain keywords (same as original DomainRouter)
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

    # Complexity indicators
    COMPLEX_INDICATORS = {
        "multi-omics", "integration", "combined", "comprehensive",
        "end-to-end", "pipeline", "workflow", "full analysis"
    }

    SIMPLE_INDICATORS = {
        "what is", "how to", "explain", "help", "list", "show",
        "find", "search", "query", "fetch"
    }

    # LLM routing prompt template
    ROUTING_PROMPT = """You are a bioinformatics domain classifier. Classify the following user query into the most appropriate domain.

Available Domains:
- genomics: DNA sequencing, alignment, variants, methylation, chromatin
- transcriptomics: RNA-seq, gene expression, differential expression
- proteomics: Mass spectrometry, protein analysis, PTMs
- metabolomics: Metabolites, lipidomics, LC-MS/GC-MS
- single-cell: scRNA-seq, cell type annotation, trajectory analysis
- metagenomics: Microbiome, 16S, taxonomic analysis
- structural_biology: Protein structures, AlphaFold, docking
- pharmacology: Drug analysis, ADMET, pharmacokinetics
- immunology: Immune cells, flow cytometry, antibodies
- cancer_biology: Tumor analysis, mutations, CNV
- bioimaging: Microscopy, image segmentation
- molecular_biology: PCR, cloning, CRISPR, primers
- biochemistry: Enzyme kinetics, binding assays
- database: Database queries, data retrieval
- literature: Literature search, paper analysis

User Query: {query}
User Expertise Level: {expertise_level}
Recent Domains Used: {recent_domains}
Keyword Hint (low confidence): {keyword_hint}

Respond ONLY with valid JSON (no markdown, no explanation):
{{"primary_domain": "domain_name", "secondary_domains": ["domain1", "domain2"], "confidence": 0.85, "complexity": "standard", "reasoning": "brief explanation"}}"""

    DEFAULT_DB_PATH = "/home/yzhang/biomate/backend/database/galaxy_ai_tools.db"

    def __init__(
        self,
        llm_client=None,
        user_patterns_adapter=None,
        audit_service=None,
        db_path: str = None
    ):
        """
        Initialize enhanced domain router.

        Args:
            llm_client: LLM client for semantic routing
            user_patterns_adapter: Adapter for user preferences
            audit_service: Audit service for recording decisions
            db_path: Path to SQLite database
        """
        self.llm_client = llm_client
        self.patterns = user_patterns_adapter
        self.audit = audit_service
        self.db_path = db_path or self.DEFAULT_DB_PATH

        # Initialize LRU cache for LLM decisions
        self._routing_cache = LRUCache(max_size=1000, ttl_seconds=3600)

        # Build inverted keyword index
        self._keyword_index: Dict[str, List[str]] = {}
        for domain, keywords in self.DOMAIN_KEYWORDS.items():
            for keyword in keywords:
                if keyword not in self._keyword_index:
                    self._keyword_index[keyword] = []
                self._keyword_index[keyword].append(domain)

        # Load learned keywords from database
        self._learned_keywords: Dict[str, Set[str]] = {}
        self._load_learned_keywords()

        log.info(f"EnhancedDomainRouter initialized with {len(self.DOMAIN_KEYWORDS)} domains, "
                f"LLM threshold: {self.LLM_THRESHOLD}")

    def _load_learned_keywords(self):
        """Load learned keywords from database."""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.execute("""
                SELECT domain, keyword, weight
                FROM learned_domain_keywords
                WHERE weight >= 0.5
                ORDER BY weight DESC
            """)

            for row in cursor.fetchall():
                domain = row[0]
                keyword = row[1]
                if domain not in self._learned_keywords:
                    self._learned_keywords[domain] = set()
                self._learned_keywords[domain].add(keyword)

            conn.close()
            total = sum(len(kws) for kws in self._learned_keywords.values())
            log.info(f"Loaded {total} learned keywords from database")

        except Exception as e:
            log.warning(f"Could not load learned keywords: {e}")

    def route(
        self,
        query: str,
        user_id: Optional[str] = None,
        user_context: Optional[Dict] = None
    ) -> EnhancedRoutingDecision:
        """
        Route a query to appropriate domains using hybrid approach.

        Args:
            query: User's query text
            user_id: Optional user ID for personalization
            user_context: Optional pre-loaded user context

        Returns:
            EnhancedRoutingDecision with routing details
        """
        start_time = time.time()

        # Get user context if needed
        if user_id and not user_context and self.patterns:
            try:
                user_context = self.patterns.get_routing_context(user_id)
            except Exception as e:
                log.warning(f"Failed to get user context: {e}")
                user_context = {}

        # Step 1: Fast keyword routing
        keyword_result = self._keyword_route(query)

        # Step 2: Decide routing method based on confidence
        if keyword_result.confidence >= self.LLM_THRESHOLD:
            # High confidence - use keyword result with user boost
            result = self._apply_user_boost(keyword_result, user_context)
            result.routing_method = "keyword"
        elif self.llm_client:
            # Low confidence - use LLM
            result = self._llm_route(query, keyword_result, user_context)
            result.routing_method = "llm" if keyword_result.confidence < 0.3 else "hybrid"
        else:
            # No LLM available - use keyword result with user boost
            result = self._apply_user_boost(keyword_result, user_context)
            result.routing_method = "keyword"

        # Calculate latency
        result.latency_ms = int((time.time() - start_time) * 1000)

        log.info(f"Routed query to {result.primary_domain} via {result.routing_method} "
                f"(conf={result.confidence:.2f}, latency={result.latency_ms}ms)")

        return result

    def _keyword_route(self, query: str) -> EnhancedRoutingDecision:
        """
        Fast keyword-based routing.

        Args:
            query: Query text

        Returns:
            Routing decision based on keyword matching
        """
        query_lower = query.lower()

        # Score each domain by keyword matches
        domain_scores: Dict[str, float] = {}
        matched_keywords: List[str] = []

        # Check standard keywords
        for domain, keywords in self.DOMAIN_KEYWORDS.items():
            score = 0.0
            for keyword in keywords:
                # Word boundary match (higher weight)
                if re.search(rf'\b{re.escape(keyword)}\b', query_lower):
                    score += 1.0
                    matched_keywords.append(keyword)
                # Partial match (lower weight)
                elif keyword in query_lower:
                    score += 0.5

            if score > 0:
                domain_scores[domain] = score

        # Check learned keywords (with boost)
        for domain, keywords in self._learned_keywords.items():
            for keyword in keywords:
                if re.search(rf'\b{re.escape(keyword)}\b', query_lower):
                    if domain not in domain_scores:
                        domain_scores[domain] = 0
                    domain_scores[domain] += 1.2  # Slightly higher weight for learned
                    matched_keywords.append(f"[learned]{keyword}")

        # Sort domains by score
        sorted_domains = sorted(domain_scores.items(), key=lambda x: -x[1])

        # Determine primary and secondary domains
        if not sorted_domains:
            primary = "genomics"  # Default
            secondary = []
            confidence = 0.1
        else:
            primary = sorted_domains[0][0]
            confidence = min(1.0, sorted_domains[0][1] / 3.0)

            # Secondary domains (at least 50% of primary score)
            secondary = [
                d for d, s in sorted_domains[1:3]
                if s >= sorted_domains[0][1] * 0.5
            ]

        # Assess complexity
        complexity = self._assess_complexity(query_lower)

        return EnhancedRoutingDecision(
            primary_domain=primary,
            secondary_domains=secondary,
            confidence=confidence,
            complexity=complexity,
            matched_keywords=list(set(matched_keywords))[:10]
        )

    def _llm_route(
        self,
        query: str,
        keyword_hint: EnhancedRoutingDecision,
        user_context: Optional[Dict]
    ) -> EnhancedRoutingDecision:
        """
        LLM-based semantic routing for ambiguous queries.

        Args:
            query: Query text
            keyword_hint: Result from keyword routing
            user_context: User context for personalization

        Returns:
            Enhanced routing decision from LLM
        """
        # Check cache first
        cache_key = self._get_cache_key(query, user_context)
        cached = self._routing_cache.get(cache_key)
        if cached:
            log.debug(f"Using cached LLM routing for query")
            return cached

        # Build prompt
        expertise = user_context.get('expertise_level', 'intermediate') if user_context else 'intermediate'
        recent_domains = user_context.get('recent_domains', []) if user_context else []

        prompt = self.ROUTING_PROMPT.format(
            query=query,
            expertise_level=expertise,
            recent_domains=', '.join(recent_domains[:3]) if recent_domains else 'none',
            keyword_hint=f"{keyword_hint.primary_domain} ({keyword_hint.confidence:.2f})"
        )

        try:
            # Call LLM
            response = self.llm_client.generate(
                prompt,
                max_tokens=300,
                temperature=0.0  # Low temperature for deterministic routing
            )

            # Parse JSON response
            result = self._parse_llm_response(response, keyword_hint)

            # Apply user boost
            result = self._apply_user_boost(result, user_context)

            # Cache result
            self._routing_cache.put(cache_key, result)

            return result

        except Exception as e:
            log.error(f"LLM routing failed: {e}, falling back to keyword routing")
            # Fallback to keyword routing with user boost
            return self._apply_user_boost(keyword_hint, user_context)

    def _parse_llm_response(
        self,
        response: str,
        keyword_fallback: EnhancedRoutingDecision
    ) -> EnhancedRoutingDecision:
        """
        Parse LLM JSON response.

        Args:
            response: LLM response text
            keyword_fallback: Fallback if parsing fails

        Returns:
            Parsed routing decision
        """
        try:
            # Try to extract JSON from response
            response = response.strip()

            # Handle markdown code blocks
            if '```json' in response:
                response = response.split('```json')[1].split('```')[0]
            elif '```' in response:
                response = response.split('```')[1].split('```')[0]

            data = json.loads(response)

            # Validate domain
            primary = data.get('primary_domain', 'genomics')
            if primary not in self.DOMAIN_KEYWORDS:
                log.warning(f"LLM returned invalid domain: {primary}, using keyword fallback")
                primary = keyword_fallback.primary_domain

            secondary = [d for d in data.get('secondary_domains', [])
                        if d in self.DOMAIN_KEYWORDS][:2]

            return EnhancedRoutingDecision(
                primary_domain=primary,
                secondary_domains=secondary,
                confidence=min(1.0, max(0.0, float(data.get('confidence', 0.8)))),
                complexity=data.get('complexity', 'standard'),
                llm_reasoning=data.get('reasoning'),
                matched_keywords=keyword_fallback.matched_keywords
            )

        except (json.JSONDecodeError, KeyError, ValueError) as e:
            log.warning(f"Failed to parse LLM response: {e}")
            return keyword_fallback

    def _apply_user_boost(
        self,
        decision: EnhancedRoutingDecision,
        user_context: Optional[Dict]
    ) -> EnhancedRoutingDecision:
        """
        Apply user preference boost to routing decision.

        Creates a copy to avoid mutating cached results.

        Args:
            decision: Current routing decision
            user_context: User context with preferences

        Returns:
            Boosted routing decision (new copy if modified)
        """
        if not user_context:
            return decision

        # Check if user has domain preference
        pref_domain = user_context.get('domain_preference')
        pref_confidence = user_context.get('domain_confidence', 0)

        if pref_domain and pref_confidence > 0.5:
            # Create a copy to avoid mutating cached results
            result = EnhancedRoutingDecision(
                primary_domain=decision.primary_domain,
                secondary_domains=list(decision.secondary_domains),  # Copy list
                confidence=decision.confidence,
                complexity=decision.complexity,
                matched_keywords=list(decision.matched_keywords),  # Copy list
                routing_method=decision.routing_method,
                llm_reasoning=decision.llm_reasoning,
                latency_ms=decision.latency_ms,
                user_boost_applied=decision.user_boost_applied
            )

            # If preference matches secondary or is close to primary, boost it
            if pref_domain in result.secondary_domains:
                # Promote preferred domain to primary if close enough
                if result.confidence < 0.8:
                    result.primary_domain = pref_domain
                    result.user_boost_applied = True
                    log.debug(f"Boosted user-preferred domain {pref_domain} to primary")

            elif pref_domain != result.primary_domain:
                # Add to secondary domains
                if pref_domain not in result.secondary_domains:
                    result.secondary_domains.insert(0, pref_domain)
                    result.secondary_domains = result.secondary_domains[:2]

            return result

        return decision

    def _assess_complexity(self, query_lower: str) -> str:
        """Assess query complexity."""
        complex_count = sum(1 for ind in self.COMPLEX_INDICATORS if ind in query_lower)
        simple_count = sum(1 for ind in self.SIMPLE_INDICATORS if ind in query_lower)

        if complex_count >= 2 or "multi" in query_lower:
            return "complex"
        elif simple_count >= 2 or len(query_lower.split()) <= 5:
            return "simple"
        else:
            return "standard"

    def _get_cache_key(self, query: str, user_context: Optional[Dict]) -> str:
        """Generate cache key for query and context."""
        context_str = ""
        if user_context:
            context_str = f":{user_context.get('domain_preference', '')}:{user_context.get('expertise_level', '')}"

        key_str = f"{query.lower().strip()}{context_str}"
        return hashlib.md5(key_str.encode()).hexdigest()

    def add_learned_keywords(
        self,
        domain: str,
        keywords: List[str],
        source: str = 'user_correction',
        user_id: str = None
    ):
        """
        Add keywords learned from user corrections.

        Args:
            domain: Target domain
            keywords: Keywords to add
            source: Source of learning
            user_id: User who triggered learning
        """
        if domain not in self.DOMAIN_KEYWORDS:
            log.warning(f"Cannot add keywords for unknown domain: {domain}")
            return

        # Add to in-memory cache
        if domain not in self._learned_keywords:
            self._learned_keywords[domain] = set()

        for kw in keywords:
            kw_lower = kw.lower().strip()
            if kw_lower:
                self._learned_keywords[domain].add(kw_lower)

        # Persist to database via patterns adapter
        if self.patterns:
            for kw in keywords:
                self.patterns.add_learned_keyword(
                    domain=domain,
                    keyword=kw,
                    source=source,
                    user_id=user_id
                )

        log.info(f"Added {len(keywords)} learned keywords for domain '{domain}'")

    def get_all_domains(self) -> List[str]:
        """Get list of all supported domains."""
        return list(self.DOMAIN_KEYWORDS.keys())

    def get_domain_keywords(self, domain: str) -> Set[str]:
        """Get all keywords (standard + learned) for a domain."""
        keywords = set(self.DOMAIN_KEYWORDS.get(domain, set()))
        keywords.update(self._learned_keywords.get(domain, set()))
        return keywords

    def clear_cache(self):
        """Clear the routing cache."""
        self._routing_cache.clear()
        log.info("Routing cache cleared")

    def reload_learned_keywords(self):
        """Reload learned keywords from database."""
        self._learned_keywords.clear()
        self._load_learned_keywords()
