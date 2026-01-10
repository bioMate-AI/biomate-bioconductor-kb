"""
UnifiedIntentRouter - Intent classification for AI Assistant queries

Routes user queries to the appropriate handler based on intent:
- workflow_generation → AgentOrchestrator
- research_question → ResearchAgent
- result_comparison → ResearchAgent + BenchmarkKnowledge
- tool_search → UnifiedToolSearch
- conclusion_drawing → ResearchAgent
- benchmark_query → BenchmarkKnowledgeDB (direct)

Uses a hybrid approach:
1. Fast keyword matching for common patterns
2. LLM fallback for ambiguous cases

This addresses the SGI-Bench finding that proper intent classification
is crucial for scientific accuracy.
"""

import logging
import re
from dataclasses import dataclass, field
from typing import List, Dict, Optional, Any, Tuple
from enum import Enum

log = logging.getLogger(__name__)


class UserIntent(Enum):
    """Types of user intents."""
    WORKFLOW_GENERATION = "workflow_generation"
    RESEARCH_QUESTION = "research_question"
    RESULT_COMPARISON = "result_comparison"
    TOOL_SEARCH = "tool_search"
    TOOL_RECOMMENDATION = "tool_recommendation"
    CONCLUSION_DRAWING = "conclusion_drawing"
    BENCHMARK_QUERY = "benchmark_query"
    LITERATURE_SURVEY = "literature_survey"
    PARAMETER_HELP = "parameter_help"
    GENERAL_QUESTION = "general_question"


@dataclass
class IntentClassification:
    """Result of intent classification."""
    primary_intent: UserIntent
    confidence: float
    secondary_intents: List[UserIntent] = field(default_factory=list)
    extracted_entities: Dict[str, Any] = field(default_factory=dict)
    routing_method: str = "keyword"  # "keyword" or "llm"
    requires_workflow: bool = False
    requires_literature: bool = False
    requires_benchmark: bool = False


class UnifiedIntentRouter:
    """
    Routes user queries to appropriate handlers based on intent.

    Uses keyword matching for speed with LLM fallback for accuracy.
    """

    # Keyword patterns for each intent
    INTENT_PATTERNS: Dict[UserIntent, List[str]] = {
        UserIntent.WORKFLOW_GENERATION: [
            r'\b(create|build|generate|make|design)\b.*\b(workflow|pipeline|analysis)\b',
            r'\b(run|perform|do|execute)\b.*\b(analysis|sequencing|alignment)\b',
            r'\b(analyze|process)\b.*\b(data|samples|reads|files)\b',
            r'\bworkflow\s+for\b',
            r'\bpipeline\s+to\b',
            r'\bwant\s+to\s+(analyze|process|align|quantify)\b',
        ],
        UserIntent.RESEARCH_QUESTION: [
            r'^(what|why|how|when|where)\s+(is|are|does|do|should|would|can)\b',
            r'\bexplain\b.*\b(how|why|what)\b',
            r'\bwhat\s+(is|are)\s+the\s+(best|recommended|optimal)\b',
            r'\bhow\s+(does|do|should|can|to)\b',
            r'\bwhy\s+(is|are|does|do)\b',
        ],
        UserIntent.RESULT_COMPARISON: [
            r'\b(compare|comparison|versus|vs\.?|better|best)\b',
            r'\b(difference|differences)\s+between\b',
            r'\bwhich\s+(is|are)\s+(better|faster|more accurate)\b',
            r'\b(\w+)\s+vs\.?\s+(\w+)\b',
            r'\bhow\s+does\s+(\w+)\s+compare\b',
        ],
        UserIntent.TOOL_SEARCH: [
            r'\b(find|search|look\s+for|list)\b.*\b(tool|tools)\b',
            r'\bwhat\s+tools?\s+(can|are|do)\b',
            r'\btools?\s+for\b',
            r'\bavailable\s+tools?\b',
        ],
        UserIntent.TOOL_RECOMMENDATION: [
            r'\b(recommend|suggest|best)\b.*\b(tool|software|method)\b',
            r'\bwhat\s+(tool|software|method)\s+should\b',
            r'\bwhich\s+(tool|aligner|caller|method)\b',
            r'\bbest\s+(tool|aligner|caller|method)\s+for\b',
        ],
        UserIntent.BENCHMARK_QUERY: [
            r'\bbenchmark\b',
            r'\bperformance\s+(comparison|data|results)\b',
            r'\baccuracy\s+(comparison|of)\b',
            r'\b(precision|recall|f1|auc)\s+(of|for|comparison)\b',
        ],
        UserIntent.CONCLUSION_DRAWING: [
            r'\b(interpret|conclude|mean|implication|significance)\b',
            r'\bwhat\s+(does|do)\s+(this|these|the)\s+result',
            r'\bbased\s+on\s+(this|these|the)\s+result',
            r'\binterpret\s+(this|these|the)\b',
        ],
        UserIntent.LITERATURE_SURVEY: [
            r'\b(literature|papers|studies|research|publications)\b',
            r'\bwhat\s+(studies|research|papers)\b',
            r'\breview\s+(of|the)\s+(literature|research)\b',
            r'\brecent\s+(studies|research|papers)\b',
        ],
        UserIntent.PARAMETER_HELP: [
            r'\b(parameter|setting|option|configure|configuration)\b',
            r'\bhow\s+to\s+set\b',
            r'\bwhat\s+(value|setting)\s+(for|should)\b',
            r'\bdefault\s+(value|parameter|setting)\b',
        ],
    }

    # Keywords that strongly indicate specific intents
    STRONG_KEYWORDS: Dict[UserIntent, List[str]] = {
        UserIntent.WORKFLOW_GENERATION: [
            'workflow', 'pipeline', 'run analysis', 'process my', 'analyze my',
            'create a', 'build a', 'generate a'
        ],
        UserIntent.RESEARCH_QUESTION: [
            'explain', 'understand', 'learn about', 'tell me about',
            'what is', 'how does', 'why is'
        ],
        UserIntent.RESULT_COMPARISON: [
            'compare', 'versus', 'vs', 'better than', 'difference between',
            'which is better', 'pros and cons'
        ],
        UserIntent.TOOL_RECOMMENDATION: [
            'best tool', 'recommend', 'suggest', 'which tool should',
            'what tool for', 'best aligner', 'best caller'
        ],
        UserIntent.BENCHMARK_QUERY: [
            'benchmark', 'performance comparison', 'accuracy comparison',
            'benchmark results', 'benchmark data'
        ],
    }

    # Tool names for entity extraction
    KNOWN_TOOLS = [
        'star', 'hisat2', 'hisat', 'bowtie', 'bowtie2', 'bwa', 'bwa-mem',
        'salmon', 'kallisto', 'rsem', 'featurecounts', 'htseq',
        'deseq2', 'edger', 'limma', 'mast', 'scde',
        'scanpy', 'seurat', 'scvi', 'harmony', 'scanorama', 'bbknn',
        'gatk', 'deepvariant', 'freebayes', 'strelka', 'mutect',
        'macs2', 'homer', 'spp', 'gem',
        'spades', 'megahit', 'canu', 'flye', 'hifiasm'
    ]

    # Analysis types for entity extraction
    ANALYSIS_TYPES = [
        'rna-seq', 'rnaseq', 'rna seq', 'transcriptomics',
        'dna-seq', 'dnaseq', 'wgs', 'wes', 'exome',
        'chip-seq', 'chipseq', 'atac-seq', 'atacseq',
        'single-cell', 'scrna-seq', 'scrnaseq', 'scatac',
        'variant calling', 'snp calling', 'mutation detection',
        'differential expression', 'de analysis',
        'alignment', 'mapping', 'read alignment',
        'assembly', 'genome assembly', 'de novo assembly',
        'metagenomics', 'microbiome', '16s'
    ]

    def __init__(self, llm_client: Optional[Any] = None):
        """
        Initialize UnifiedIntentRouter.

        Args:
            llm_client: Optional LLM client for ambiguous cases
        """
        self.llm_client = llm_client
        self._compile_patterns()

    def _compile_patterns(self):
        """Compile regex patterns for performance."""
        self._compiled_patterns: Dict[UserIntent, List[re.Pattern]] = {}
        for intent, patterns in self.INTENT_PATTERNS.items():
            self._compiled_patterns[intent] = [
                re.compile(p, re.IGNORECASE) for p in patterns
            ]

    def classify(
        self,
        query: str,
        context: Optional[Dict[str, Any]] = None,
        use_llm_fallback: bool = True
    ) -> IntentClassification:
        """
        Classify the intent of a user query.

        Args:
            query: User's query text
            context: Optional context (previous messages, domain, etc.)
            use_llm_fallback: Whether to use LLM for ambiguous cases

        Returns:
            IntentClassification with primary intent and metadata
        """
        # Step 1: Try keyword matching
        keyword_result = self._keyword_classify(query)

        # Step 2: Extract entities
        entities = self._extract_entities(query)
        keyword_result.extracted_entities = entities

        # Step 3: Determine additional requirements
        keyword_result.requires_workflow = self._requires_workflow(query, keyword_result)
        keyword_result.requires_literature = self._requires_literature(query, keyword_result)
        keyword_result.requires_benchmark = self._requires_benchmark(query, keyword_result)

        # Step 4: Use LLM for low-confidence cases
        if keyword_result.confidence < 0.6 and use_llm_fallback and self.llm_client:
            llm_result = self._llm_classify(query, context)
            if llm_result and llm_result.confidence > keyword_result.confidence:
                llm_result.extracted_entities = entities
                llm_result.requires_workflow = keyword_result.requires_workflow
                llm_result.requires_literature = keyword_result.requires_literature
                llm_result.requires_benchmark = keyword_result.requires_benchmark
                return llm_result

        return keyword_result

    def _keyword_classify(self, query: str) -> IntentClassification:
        """Classify using keyword patterns."""
        scores: Dict[UserIntent, float] = {intent: 0.0 for intent in UserIntent}
        query_lower = query.lower()

        # Check compiled patterns
        for intent, patterns in self._compiled_patterns.items():
            for pattern in patterns:
                if pattern.search(query):
                    scores[intent] += 0.3

        # Check strong keywords
        for intent, keywords in self.STRONG_KEYWORDS.items():
            for keyword in keywords:
                if keyword.lower() in query_lower:
                    scores[intent] += 0.4

        # Find top intents
        sorted_intents = sorted(scores.items(), key=lambda x: x[1], reverse=True)
        primary_intent = sorted_intents[0][0]
        primary_score = sorted_intents[0][1]

        # Normalize confidence
        confidence = min(primary_score, 1.0)

        # Get secondary intents
        secondary = [
            intent for intent, score in sorted_intents[1:4]
            if score > 0.2
        ]

        # Default to general question if no matches
        if confidence < 0.2:
            primary_intent = UserIntent.GENERAL_QUESTION
            confidence = 0.5

        return IntentClassification(
            primary_intent=primary_intent,
            confidence=confidence,
            secondary_intents=secondary,
            routing_method="keyword"
        )

    def _extract_entities(self, query: str) -> Dict[str, Any]:
        """Extract entities from the query."""
        entities = {
            'tools': [],
            'analysis_types': [],
            'organisms': [],
            'data_types': []
        }

        query_lower = query.lower()

        # Extract tool names
        for tool in self.KNOWN_TOOLS:
            if tool.lower() in query_lower:
                entities['tools'].append(tool)

        # Extract analysis types
        for analysis in self.ANALYSIS_TYPES:
            if analysis.lower() in query_lower:
                entities['analysis_types'].append(analysis)

        # Common organisms
        organisms = ['human', 'mouse', 'rat', 'zebrafish', 'drosophila', 'yeast', 'e. coli', 'arabidopsis']
        for org in organisms:
            if org.lower() in query_lower:
                entities['organisms'].append(org)

        # Data types
        data_types = ['fastq', 'bam', 'sam', 'vcf', 'bed', 'gtf', 'gff', 'fasta', 'h5ad', 'loom']
        for dt in data_types:
            if dt.lower() in query_lower:
                entities['data_types'].append(dt)

        return entities

    def _requires_workflow(self, query: str, classification: IntentClassification) -> bool:
        """Determine if the query requires workflow generation."""
        if classification.primary_intent == UserIntent.WORKFLOW_GENERATION:
            return True

        workflow_indicators = ['run', 'execute', 'process', 'analyze my', 'my data', 'my samples']
        return any(ind in query.lower() for ind in workflow_indicators)

    def _requires_literature(self, query: str, classification: IntentClassification) -> bool:
        """Determine if the query requires literature search."""
        literature_intents = [
            UserIntent.RESEARCH_QUESTION,
            UserIntent.LITERATURE_SURVEY,
            UserIntent.CONCLUSION_DRAWING
        ]
        if classification.primary_intent in literature_intents:
            return True

        literature_indicators = ['papers', 'studies', 'research', 'literature', 'published']
        return any(ind in query.lower() for ind in literature_indicators)

    def _requires_benchmark(self, query: str, classification: IntentClassification) -> bool:
        """Determine if the query requires benchmark data."""
        benchmark_intents = [
            UserIntent.RESULT_COMPARISON,
            UserIntent.TOOL_RECOMMENDATION,
            UserIntent.BENCHMARK_QUERY
        ]
        if classification.primary_intent in benchmark_intents:
            return True

        benchmark_indicators = ['benchmark', 'performance', 'accuracy', 'best', 'compare', 'vs']
        return any(ind in query.lower() for ind in benchmark_indicators)

    def _llm_classify(
        self,
        query: str,
        context: Optional[Dict[str, Any]] = None
    ) -> Optional[IntentClassification]:
        """Classify using LLM for ambiguous cases."""
        if not self.llm_client:
            return None

        try:
            prompt = f"""Classify the following user query into one of these intent categories:

1. workflow_generation - User wants to create/run an analysis pipeline
2. research_question - User is asking a scientific question
3. result_comparison - User wants to compare tools, methods, or results
4. tool_search - User is looking for available tools
5. tool_recommendation - User wants a recommendation for which tool to use
6. benchmark_query - User wants benchmark/performance data
7. conclusion_drawing - User wants to interpret results
8. literature_survey - User wants information from scientific literature
9. parameter_help - User needs help with tool parameters
10. general_question - General question that doesn't fit above categories

Query: "{query}"

Respond with just the category name and confidence (0-1), e.g.:
workflow_generation 0.9
"""
            # This would call the LLM - for now return None
            # response = self.llm_client.generate(prompt, max_tokens=50)
            # Parse response...
            return None

        except Exception as e:
            log.warning(f"LLM classification failed: {e}")
            return None

    def get_handler_for_intent(self, intent: UserIntent) -> str:
        """Get the handler name for an intent."""
        handler_map = {
            UserIntent.WORKFLOW_GENERATION: "agent_orchestrator",
            UserIntent.RESEARCH_QUESTION: "research_agent",
            UserIntent.RESULT_COMPARISON: "research_agent",  # Uses benchmark evidence
            UserIntent.TOOL_SEARCH: "unified_tool_search",
            UserIntent.TOOL_RECOMMENDATION: "research_agent",  # Uses benchmark evidence
            UserIntent.BENCHMARK_QUERY: "benchmark_knowledge",
            UserIntent.CONCLUSION_DRAWING: "research_agent",
            UserIntent.LITERATURE_SURVEY: "research_agent",
            UserIntent.PARAMETER_HELP: "tool_search",  # Tool docs
            UserIntent.GENERAL_QUESTION: "research_agent",
        }
        return handler_map.get(intent, "research_agent")


# Factory function
def create_intent_router(llm_client: Optional[Any] = None) -> UnifiedIntentRouter:
    """Create a UnifiedIntentRouter instance."""
    return UnifiedIntentRouter(llm_client)
