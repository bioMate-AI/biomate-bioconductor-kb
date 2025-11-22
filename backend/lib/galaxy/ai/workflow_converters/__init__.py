"""
Workflow Converters

Bidirectional conversion between:
- Galaxy .ga format
- Nextflow .nf format
- BioMate Unified Workflow Format (BUWF)

Converters:
- GalaxyToUnifiedConverter: Galaxy .ga → BUWF
- UnifiedToGalaxyConverter: BUWF → Galaxy .ga
- NextflowToUnifiedConverter: Nextflow .nf → BUWF
- UnifiedToNextflowConverter: BUWF → Nextflow .nf

Workflow Grouping:
- WorkflowGrouper: Intelligently group detailed steps into high-level steps
- group_workflow_steps: Convenience function for workflow grouping
"""

from .base_converter import BaseConverter
from .galaxy_converter import GalaxyToUnifiedConverter, UnifiedToGalaxyConverter
from .nextflow_converter import NextflowToUnifiedConverter, UnifiedToNextflowConverter
from .nextflow_parser import NextflowParser, parse_nextflow_file, parse_nextflow_string
from .workflow_grouper import WorkflowGrouper, group_workflow_steps, GroupingStrategy
from .serialization import serialize_buwf, deserialize_buwf

__all__ = [
    "BaseConverter",
    "GalaxyToUnifiedConverter",
    "UnifiedToGalaxyConverter",
    "NextflowToUnifiedConverter",
    "UnifiedToNextflowConverter",
    "NextflowParser",
    "parse_nextflow_file",
    "parse_nextflow_string",
    "WorkflowGrouper",
    "group_workflow_steps",
    "GroupingStrategy",
    "serialize_buwf",
    "deserialize_buwf",
]
