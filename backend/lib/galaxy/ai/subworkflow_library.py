#!/usr/bin/env python3
"""
Subworkflow Library - Reusable Pattern Storage

Stores and matches subworkflow patterns for reuse across workflows.
Implements semantic caching for converted subworkflows.

Author: BioMate Team
Date: 2025-11-24
"""

import json
import hashlib
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass, asdict
from datetime import datetime


@dataclass
class SubworkflowPattern:
    """Represents a reusable subworkflow pattern."""
    pattern_id: str
    name: str  # e.g., "FASTQ_ALIGN_DNA"
    description: str
    biological_purpose: str
    tools: List[str]  # Tool IDs in order
    tool_signature: str  # Hash of tools for matching
    nextflow_code: str  # Generated Nextflow subworkflow
    quality_score: float
    usage_count: int
    created_at: str
    last_used: str
    # Metadata for matching
    input_types: List[str]
    output_types: List[str]
    category: str  # alignment, qc, assembly, etc.


class SubworkflowLibrary:
    """
    Library of reusable subworkflow patterns.

    Features:
    1. Store converted subworkflows
    2. Match by exact tool signature
    3. Match by structural similarity
    4. Track usage statistics
    5. Prioritize high-quality patterns
    """

    def __init__(self, library_path: Path):
        """
        Initialize library.

        Args:
            library_path: Path to library storage directory
        """
        self.library_path = Path(library_path)
        self.library_path.mkdir(parents=True, exist_ok=True)

        self.index_file = self.library_path / 'index.json'
        self.patterns: Dict[str, SubworkflowPattern] = {}

        # Load existing library
        self._load_library()

    def _load_library(self):
        """Load library from disk."""
        if self.index_file.exists():
            with open(self.index_file) as f:
                data = json.load(f)
                for pattern_data in data.get('patterns', []):
                    pattern = SubworkflowPattern(**pattern_data)
                    self.patterns[pattern.pattern_id] = pattern

    def save_library(self):
        """Save library to disk."""
        data = {
            'version': '1.0',
            'updated_at': datetime.now().isoformat(),
            'patterns': [asdict(p) for p in self.patterns.values()]
        }

        with open(self.index_file, 'w') as f:
            json.dump(data, f, indent=2)

    def add_pattern(self,
                    name: str,
                    description: str,
                    biological_purpose: str,
                    tools: List[str],
                    nextflow_code: str,
                    quality_score: float,
                    input_types: List[str],
                    output_types: List[str],
                    category: str) -> SubworkflowPattern:
        """
        Add a new pattern to the library.

        Args:
            name: Pattern name
            description: Description
            biological_purpose: Biological purpose
            tools: List of tool IDs
            nextflow_code: Generated Nextflow code
            quality_score: Quality score (0-100)
            input_types: Input type signatures
            output_types: Output type signatures
            category: Category (alignment, qc, etc.)

        Returns:
            Created SubworkflowPattern
        """

        # Generate tool signature
        tool_signature = self._compute_signature(tools)

        # Generate pattern ID
        pattern_id = f"{category}_{name}_{tool_signature[:8]}"

        # Check if already exists
        if pattern_id in self.patterns:
            # Update existing
            pattern = self.patterns[pattern_id]
            pattern.usage_count += 1
            pattern.last_used = datetime.now().isoformat()
            # Update if better quality
            if quality_score > pattern.quality_score:
                pattern.nextflow_code = nextflow_code
                pattern.quality_score = quality_score
        else:
            # Create new
            pattern = SubworkflowPattern(
                pattern_id=pattern_id,
                name=name,
                description=description,
                biological_purpose=biological_purpose,
                tools=tools,
                tool_signature=tool_signature,
                nextflow_code=nextflow_code,
                quality_score=quality_score,
                usage_count=1,
                created_at=datetime.now().isoformat(),
                last_used=datetime.now().isoformat(),
                input_types=input_types,
                output_types=output_types,
                category=category
            )
            self.patterns[pattern_id] = pattern

        # Save to disk
        self.save_library()

        return pattern

    def find_exact_match(self, tools: List[str]) -> Optional[SubworkflowPattern]:
        """
        Find exact match by tool signature.

        Args:
            tools: List of tool IDs to match

        Returns:
            Matching pattern or None
        """

        signature = self._compute_signature(tools)

        for pattern in self.patterns.values():
            if pattern.tool_signature == signature:
                # Update usage
                pattern.usage_count += 1
                pattern.last_used = datetime.now().isoformat()
                self.save_library()
                return pattern

        return None

    def find_structural_matches(self,
                               tools: List[str],
                               category: Optional[str] = None,
                               top_k: int = 3) -> List[Tuple[SubworkflowPattern, float]]:
        """
        Find structurally similar patterns.

        Uses Jaccard similarity on tool sets.

        Args:
            tools: List of tool IDs
            category: Optional category filter
            top_k: Number of top matches to return

        Returns:
            List of (pattern, similarity_score) tuples
        """

        tools_set = set(tools)
        matches = []

        for pattern in self.patterns.values():
            if category and pattern.category != category:
                continue

            pattern_tools = set(pattern.tools)

            # Jaccard similarity
            intersection = len(tools_set & pattern_tools)
            union = len(tools_set | pattern_tools)

            if union > 0:
                similarity = intersection / union

                # Boost by quality and usage
                boosted_score = similarity * (1 + pattern.quality_score / 100) * (1 + min(pattern.usage_count, 10) / 10)

                matches.append((pattern, boosted_score))

        # Sort by score
        matches.sort(key=lambda x: x[1], reverse=True)

        return matches[:top_k]

    def get_top_patterns(self, category: Optional[str] = None, limit: int = 10) -> List[SubworkflowPattern]:
        """
        Get top patterns by quality and usage.

        Args:
            category: Optional category filter
            limit: Maximum number of patterns

        Returns:
            List of top patterns
        """

        filtered = [p for p in self.patterns.values()
                   if not category or p.category == category]

        # Sort by combined score
        filtered.sort(key=lambda p: (p.quality_score * p.usage_count), reverse=True)

        return filtered[:limit]

    def get_statistics(self) -> Dict:
        """Get library statistics."""
        total = len(self.patterns)
        by_category = {}
        total_usage = 0

        for pattern in self.patterns.values():
            by_category[pattern.category] = by_category.get(pattern.category, 0) + 1
            total_usage += pattern.usage_count

        avg_quality = sum(p.quality_score for p in self.patterns.values()) / total if total > 0 else 0

        return {
            'total_patterns': total,
            'by_category': by_category,
            'total_reuses': total_usage,
            'average_quality': avg_quality,
            'cache_hit_rate': (total_usage / max(total_usage + total, 1)) * 100
        }

    def _compute_signature(self, tools: List[str]) -> str:
        """Compute deterministic signature for tool list."""
        # Normalize tool IDs and create hash
        normalized = [t.lower().strip() for t in tools]
        signature_str = '|'.join(sorted(normalized))
        return hashlib.sha256(signature_str.encode()).hexdigest()


# ==============================================================================
# CLI for testing
# ==============================================================================

def main():
    """Test the subworkflow library."""
    import sys

    library_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('/tmp/subworkflow_library')

    # Create library
    library = SubworkflowLibrary(library_path)

    print(f"\n{'='*80}")
    print(f"Subworkflow Library: {library_path}")
    print(f"{'='*80}\n")

    # Add sample patterns
    pattern1 = library.add_pattern(
        name="FASTQ_ALIGN_DNA",
        description="Align sequencing reads to reference genome",
        biological_purpose="Sequence alignment",
        tools=["bwa_index", "bwa_mem", "samtools_sort"],
        nextflow_code="workflow FASTQ_ALIGN_DNA { ... }",
        quality_score=95.0,
        input_types=["fastq", "fasta"],
        output_types=["bam"],
        category="alignment"
    )
    print(f"Added pattern: {pattern1.name} ({pattern1.pattern_id})")

    pattern2 = library.add_pattern(
        name="BAM_SORT_STATS",
        description="Sort BAM and generate statistics",
        biological_purpose="BAM processing",
        tools=["samtools_sort", "samtools_index", "samtools_stats"],
        nextflow_code="workflow BAM_SORT_STATS { ... }",
        quality_score=92.0,
        input_types=["bam"],
        output_types=["bam", "bai", "stats"],
        category="qc"
    )
    print(f"Added pattern: {pattern2.name} ({pattern2.pattern_id})")

    # Test exact match
    print(f"\n--- Exact Match Test ---")
    match = library.find_exact_match(["bwa_index", "bwa_mem", "samtools_sort"])
    if match:
        print(f"✅ Found exact match: {match.name} (used {match.usage_count} times)")
    else:
        print(f"❌ No exact match found")

    # Test structural match
    print(f"\n--- Structural Match Test ---")
    matches = library.find_structural_matches(["bwa_index", "bwa_mem", "picard_sort"], category="alignment")
    for i, (pattern, score) in enumerate(matches, 1):
        print(f"{i}. {pattern.name} (similarity: {score:.2f})")

    # Statistics
    print(f"\n--- Library Statistics ---")
    stats = library.get_statistics()
    for key, value in stats.items():
        print(f"{key}: {value}")


if __name__ == '__main__':
    main()
