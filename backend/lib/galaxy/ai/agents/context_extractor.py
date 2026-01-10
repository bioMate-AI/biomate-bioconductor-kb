"""
ContextExtractor - Multi-source context collection for benchmark-informed selection

Extracts context from multiple sources to inform tool selection:
1. User text analysis (LLM extracts constraints like "I have limited RAM")
2. Dataset characteristics (auto-detected from uploaded files)
3. User preferences (stored in DB)
4. Benchmark defaults (fallback)

This addresses the SGI-Bench finding that context is crucial for
correct tool recommendations.
"""

import logging
import re
from dataclasses import dataclass, field
from typing import List, Dict, Optional, Any, Tuple
from enum import Enum

log = logging.getLogger(__name__)


class ConstraintType(Enum):
    """Types of computational constraints."""
    MEMORY_LIMITED = "memory_limited"
    SPEED_PRIORITY = "speed_priority"
    ACCURACY_PRIORITY = "accuracy_priority"
    COST_SENSITIVE = "cost_sensitive"
    GPU_AVAILABLE = "gpu_available"
    LARGE_DATASET = "large_dataset"
    SMALL_DATASET = "small_dataset"
    REPRODUCIBILITY_REQUIRED = "reproducibility_required"


@dataclass
class DatasetCharacteristics:
    """Characteristics of a dataset for context extraction."""
    file_count: int = 0
    total_size_gb: float = 0.0
    file_types: List[str] = field(default_factory=list)
    is_paired_end: bool = False
    read_length: Optional[int] = None
    organism: Optional[str] = None
    is_single_cell: bool = False
    estimated_cells: Optional[int] = None


@dataclass
class ExtractedContext:
    """Context extracted from multiple sources."""
    # Computational constraints
    memory_limited: bool = False
    speed_priority: bool = False
    accuracy_priority: bool = False
    cost_sensitive: bool = False
    gpu_available: bool = False

    # Dataset characteristics
    large_dataset: bool = False
    small_dataset: bool = False
    dataset_size_gb: float = 0.0
    is_paired_end: bool = False
    is_single_cell: bool = False
    read_length: Optional[int] = None
    organism: Optional[str] = None

    # Quality requirements
    reproducibility_required: bool = False
    publication_ready: bool = False

    # Source tracking
    sources: List[str] = field(default_factory=list)
    confidence: float = 0.8

    # Raw extracted info
    raw_constraints: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for API compatibility."""
        return {
            'memory_limited': self.memory_limited,
            'speed_priority': self.speed_priority,
            'accuracy_priority': self.accuracy_priority,
            'cost_sensitive': self.cost_sensitive,
            'gpu_available': self.gpu_available,
            'large_dataset': self.large_dataset,
            'small_dataset': self.small_dataset,
            'dataset_size_gb': self.dataset_size_gb,
            'is_paired_end': self.is_paired_end,
            'is_single_cell': self.is_single_cell,
            'read_length': self.read_length,
            'organism': self.organism,
            'reproducibility_required': self.reproducibility_required,
            'publication_ready': self.publication_ready,
            'sources': self.sources,
            'confidence': self.confidence,
        }


class ContextExtractor:
    """
    Extracts context from multiple sources for benchmark-informed tool selection.

    Sources:
    1. User text (keyword matching + optional LLM)
    2. Dataset metadata
    3. User preferences
    4. System defaults
    """

    # Keyword patterns for constraint detection
    CONSTRAINT_PATTERNS: Dict[ConstraintType, List[str]] = {
        ConstraintType.MEMORY_LIMITED: [
            r'\b(limited|low|small)\s*(ram|memory)\b',
            r'\bmemory\s*(limited|constrained|constraint)\b',
            r'\b(only|just)\s*\d+\s*gb\s*(ram|memory)\b',
            r'\blaptop\b',
            r'\bdesktop\s+with\s+limited\b',
        ],
        ConstraintType.SPEED_PRIORITY: [
            r'\b(fast|quick|rapid|urgent)\b',
            r'\b(speed|time)\s*(priority|important|critical)\b',
            r'\bneed\s*(results?|output)\s*(quickly|fast|soon)\b',
            r'\bdeadline\b',
            r'\btime\s*sensitive\b',
        ],
        ConstraintType.ACCURACY_PRIORITY: [
            r'\b(accurate|accurate|precision|quality)\s*(priority|important|critical)\b',
            r'\b(high|best)\s*(quality|accuracy|precision)\b',
            r'\bpublication\s*ready\b',
            r'\b(don\'?t|do\s*not)\s*care\s*about\s*(time|speed)\b',
        ],
        ConstraintType.COST_SENSITIVE: [
            r'\b(cost|budget)\s*(limited|constrained|sensitive)\b',
            r'\bfree\s+tier\b',
            r'\bminimize\s*(cost|expense)\b',
            r'\blow\s*cost\b',
        ],
        ConstraintType.GPU_AVAILABLE: [
            r'\bgpu\s*(available|enabled|present)\b',
            r'\bhave\s*(a\s*)?gpu\b',
            r'\bnvidia|cuda|a100|v100|rtx\b',
        ],
        ConstraintType.LARGE_DATASET: [
            r'\blarge\s*(dataset|data|files?)\b',
            r'\b(hundreds?|thousands?)\s*of\s*(samples?|files?)\b',
            r'\b\d+\s*(tb|terabytes?)\b',
            r'\b(>|more\s*than)\s*100\s*gb\b',
            r'\bwhole\s*genome\b',
        ],
        ConstraintType.SMALL_DATASET: [
            r'\bsmall\s*(dataset|data|sample)\b',
            r'\b(few|couple|handful)\s*(samples?|files?)\b',
            r'\bjust\s*\d+\s*(samples?|files?)\b',
            r'\bpilot\s*(study|data)\b',
        ],
        ConstraintType.REPRODUCIBILITY_REQUIRED: [
            r'\breproducib(le|ility)\b',
            r'\bpeer\s*review\b',
            r'\bpublication\b',
            r'\bauditable\b',
            r'\bdocument(ed|ation)\s*required\b',
        ],
    }

    # Common organisms for detection
    ORGANISM_PATTERNS = {
        'human': r'\b(human|homo\s*sapiens|hg38|hg19|grch38|grch37)\b',
        'mouse': r'\b(mouse|mus\s*musculus|mm10|mm9)\b',
        'rat': r'\b(rat|rattus\s*norvegicus|rn6)\b',
        'zebrafish': r'\b(zebrafish|danio\s*rerio|danrer)\b',
        'drosophila': r'\b(drosophila|fruit\s*fly|dm6)\b',
        'c_elegans': r'\b(c\.?\s*elegans|worm|ce10|ce11)\b',
        'yeast': r'\b(yeast|saccharomyces\s*cerevisiae|s\.?\s*cerevisiae)\b',
        'arabidopsis': r'\b(arabidopsis|tair10)\b',
        'e_coli': r'\b(e\.?\s*coli|escherichia\s*coli)\b',
    }

    def __init__(self, llm_client: Optional[Any] = None):
        """
        Initialize ContextExtractor.

        Args:
            llm_client: Optional LLM client for advanced extraction
        """
        self.llm_client = llm_client
        self._compile_patterns()

    def _compile_patterns(self):
        """Compile regex patterns for performance."""
        self._compiled_constraints: Dict[ConstraintType, List[re.Pattern]] = {}
        for constraint, patterns in self.CONSTRAINT_PATTERNS.items():
            self._compiled_constraints[constraint] = [
                re.compile(p, re.IGNORECASE) for p in patterns
            ]

        self._compiled_organisms = {
            org: re.compile(pattern, re.IGNORECASE)
            for org, pattern in self.ORGANISM_PATTERNS.items()
        }

    def extract_from_text(
        self,
        text: str,
        use_llm: bool = False
    ) -> ExtractedContext:
        """
        Extract context from user text.

        Args:
            text: User's query or message
            use_llm: Whether to use LLM for advanced extraction

        Returns:
            ExtractedContext with detected constraints
        """
        context = ExtractedContext()
        context.sources.append('text_analysis')

        text_lower = text.lower()

        # Extract constraints using patterns
        detected_constraints = []
        for constraint_type, patterns in self._compiled_constraints.items():
            for pattern in patterns:
                if pattern.search(text):
                    detected_constraints.append(constraint_type)
                    break

        # Set context flags based on detected constraints
        for constraint in detected_constraints:
            if constraint == ConstraintType.MEMORY_LIMITED:
                context.memory_limited = True
            elif constraint == ConstraintType.SPEED_PRIORITY:
                context.speed_priority = True
            elif constraint == ConstraintType.ACCURACY_PRIORITY:
                context.accuracy_priority = True
            elif constraint == ConstraintType.COST_SENSITIVE:
                context.cost_sensitive = True
            elif constraint == ConstraintType.GPU_AVAILABLE:
                context.gpu_available = True
            elif constraint == ConstraintType.LARGE_DATASET:
                context.large_dataset = True
            elif constraint == ConstraintType.SMALL_DATASET:
                context.small_dataset = True
            elif constraint == ConstraintType.REPRODUCIBILITY_REQUIRED:
                context.reproducibility_required = True
                context.publication_ready = True

        # Extract organism
        for organism, pattern in self._compiled_organisms.items():
            if pattern.search(text):
                context.organism = organism
                break

        # Detect single-cell context
        if re.search(r'\b(single[\s-]?cell|scRNA|10x|chromium)\b', text, re.IGNORECASE):
            context.is_single_cell = True

        # Detect paired-end
        if re.search(r'\b(paired[\s-]?end|PE|R1.*R2)\b', text, re.IGNORECASE):
            context.is_paired_end = True

        # Extract approximate dataset size mentions
        size_match = re.search(r'(\d+(?:\.\d+)?)\s*(gb|tb|mb)', text, re.IGNORECASE)
        if size_match:
            size = float(size_match.group(1))
            unit = size_match.group(2).lower()
            if unit == 'tb':
                context.dataset_size_gb = size * 1000
                context.large_dataset = True
            elif unit == 'gb':
                context.dataset_size_gb = size
                if size > 100:
                    context.large_dataset = True
                elif size < 1:
                    context.small_dataset = True
            elif unit == 'mb':
                context.dataset_size_gb = size / 1000
                if size < 100:
                    context.small_dataset = True

        # Store raw for debugging
        context.raw_constraints['detected_types'] = [c.value for c in detected_constraints]

        # Adjust confidence based on number of signals
        if len(detected_constraints) > 2:
            context.confidence = 0.9
        elif len(detected_constraints) == 0:
            context.confidence = 0.5

        # Use LLM for advanced extraction if enabled
        if use_llm and self.llm_client:
            llm_context = self._extract_with_llm(text)
            if llm_context:
                context = self._merge_contexts(context, llm_context)

        return context

    def extract_from_dataset(
        self,
        dataset_info: Dict[str, Any]
    ) -> ExtractedContext:
        """
        Extract context from dataset metadata.

        Args:
            dataset_info: Dataset metadata (file_count, total_size, file_types, etc.)

        Returns:
            ExtractedContext with dataset-derived constraints
        """
        context = ExtractedContext()
        context.sources.append('dataset_metadata')

        # Size-based constraints
        total_size_gb = dataset_info.get('total_size_gb', 0)
        context.dataset_size_gb = total_size_gb

        if total_size_gb > 100:
            context.large_dataset = True
        elif total_size_gb < 1:
            context.small_dataset = True

        # File type detection
        file_types = dataset_info.get('file_types', [])
        if 'h5ad' in file_types or 'loom' in file_types or '10x' in str(file_types):
            context.is_single_cell = True

        # Paired-end detection
        file_count = dataset_info.get('file_count', 0)
        if file_count % 2 == 0 and 'fastq' in str(file_types).lower():
            # Likely paired-end if even number of FASTQ files
            context.is_paired_end = True

        # Organism from metadata
        if dataset_info.get('organism'):
            context.organism = dataset_info['organism']

        # Read length
        if dataset_info.get('read_length'):
            context.read_length = dataset_info['read_length']

        context.confidence = 0.9  # High confidence for direct metadata

        return context

    def extract_from_preferences(
        self,
        user_preferences: Dict[str, Any]
    ) -> ExtractedContext:
        """
        Extract context from user preferences.

        Args:
            user_preferences: User's stored preferences

        Returns:
            ExtractedContext with preference-derived constraints
        """
        context = ExtractedContext()
        context.sources.append('user_preferences')

        # Map preference keys to context flags
        pref_mapping = {
            'prefer_fast_tools': 'speed_priority',
            'prefer_accurate_tools': 'accuracy_priority',
            'memory_limited': 'memory_limited',
            'has_gpu': 'gpu_available',
            'budget_conscious': 'cost_sensitive',
            'publication_workflow': 'publication_ready',
        }

        for pref_key, context_key in pref_mapping.items():
            if user_preferences.get(pref_key):
                setattr(context, context_key, True)

        # Default organism from preferences
        if user_preferences.get('default_organism'):
            context.organism = user_preferences['default_organism']

        context.confidence = 0.85

        return context

    def extract_combined(
        self,
        text: Optional[str] = None,
        dataset_info: Optional[Dict[str, Any]] = None,
        user_preferences: Optional[Dict[str, Any]] = None,
        use_llm: bool = False
    ) -> ExtractedContext:
        """
        Extract and combine context from all available sources.

        Args:
            text: User's query text
            dataset_info: Dataset metadata
            user_preferences: User preferences
            use_llm: Whether to use LLM for text analysis

        Returns:
            Combined ExtractedContext from all sources
        """
        combined = ExtractedContext()

        # Extract from each source
        if text:
            text_context = self.extract_from_text(text, use_llm=use_llm)
            combined = self._merge_contexts(combined, text_context)

        if dataset_info:
            dataset_context = self.extract_from_dataset(dataset_info)
            combined = self._merge_contexts(combined, dataset_context)

        if user_preferences:
            pref_context = self.extract_from_preferences(user_preferences)
            combined = self._merge_contexts(combined, pref_context)

        # Apply defaults if nothing detected
        if not combined.sources:
            combined.sources.append('defaults')
            combined.confidence = 0.5

        return combined

    def _merge_contexts(
        self,
        base: ExtractedContext,
        overlay: ExtractedContext
    ) -> ExtractedContext:
        """Merge two contexts, with overlay taking precedence for True values."""
        # Merge boolean flags (OR logic - if either is True, result is True)
        bool_fields = [
            'memory_limited', 'speed_priority', 'accuracy_priority',
            'cost_sensitive', 'gpu_available', 'large_dataset', 'small_dataset',
            'is_paired_end', 'is_single_cell', 'reproducibility_required',
            'publication_ready'
        ]

        for field in bool_fields:
            if getattr(overlay, field, False):
                setattr(base, field, True)

        # Merge optional values (overlay takes precedence if set)
        if overlay.dataset_size_gb > 0:
            base.dataset_size_gb = overlay.dataset_size_gb
        if overlay.read_length:
            base.read_length = overlay.read_length
        if overlay.organism:
            base.organism = overlay.organism

        # Merge sources
        base.sources.extend(overlay.sources)

        # Average confidence
        base.confidence = (base.confidence + overlay.confidence) / 2

        # Merge raw constraints
        base.raw_constraints.update(overlay.raw_constraints)

        return base

    def _extract_with_llm(self, text: str) -> Optional[ExtractedContext]:
        """Use LLM for advanced context extraction."""
        if not self.llm_client:
            return None

        try:
            prompt = f"""Extract computational constraints and context from this text:

"{text}"

Identify:
1. Memory constraints (limited RAM, memory issues)
2. Speed requirements (urgent, deadline, fast)
3. Accuracy requirements (publication, high quality)
4. Dataset size (large, small, specific sizes)
5. Organism (human, mouse, etc.)
6. Data type (single-cell, paired-end, etc.)

Respond in JSON format:
{{
  "memory_limited": true/false,
  "speed_priority": true/false,
  "accuracy_priority": true/false,
  "large_dataset": true/false,
  "small_dataset": true/false,
  "organism": "human" or null,
  "is_single_cell": true/false,
  "is_paired_end": true/false
}}
"""
            # Note: This is a placeholder - actual LLM call would go here
            # response = self.llm_client.generate(prompt, max_tokens=200)
            # parsed = json.loads(response)
            # return ExtractedContext(**parsed)

            return None  # LLM extraction not implemented yet

        except Exception as e:
            log.warning(f"LLM context extraction failed: {e}")
            return None


# Factory function
def create_context_extractor(llm_client: Optional[Any] = None) -> ContextExtractor:
    """Create a ContextExtractor instance."""
    return ContextExtractor(llm_client=llm_client)
