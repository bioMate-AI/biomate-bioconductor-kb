"""
Resource Resolver: Extract resource requirements from multiple sources.

Tries in order:
1. Galaxy tool XML (GALAXY_SLOTS hints)
2. nf-core modules (curated labels)
3. Tool documentation (LLM-based extraction)
4. Category-based defaults (fallback)
"""

import re
import json
import logging
from pathlib import Path
from typing import Dict, Optional, List, Any
from dataclasses import dataclass
import xml.etree.ElementTree as ET

log = logging.getLogger(__name__)


@dataclass
class ResourceRequirement:
    """Resource requirements for a tool."""
    cpus: int
    memory_gb: int
    time_hours: int
    label: str  # process_low, process_medium, process_high
    source: str  # Where we got this info from
    confidence: float  # 0.0 to 1.0


class ResourceResolver:
    """Resolve resource requirements from multiple sources."""

    # Resource label definitions (from nf-core base.config)
    RESOURCE_LABELS = {
        'process_single': {'cpus': 1, 'memory_gb': 6, 'time_hours': 4},
        'process_low': {'cpus': 2, 'memory_gb': 12, 'time_hours': 4},
        'process_medium': {'cpus': 6, 'memory_gb': 36, 'time_hours': 8},
        'process_high': {'cpus': 12, 'memory_gb': 72, 'time_hours': 16},
        'process_high_memory': {'cpus': 12, 'memory_gb': 200, 'time_hours': 16},
    }

    # Category to default label mapping
    CATEGORY_DEFAULTS = {
        'alignment': 'process_high',
        'assembly': 'process_high',
        'variant_calling': 'process_high',
        'peak_calling': 'process_medium',
        'quantification': 'process_medium',
        'annotation': 'process_medium',
        'qc': 'process_low',
        'quality_control': 'process_low',
        'format_conversion': 'process_low',
        'filtering': 'process_low',
        'trimming': 'process_low',
        'plotting': 'process_single',
        'visualization': 'process_single',
        'report_generation': 'process_single',
    }

    def __init__(self, nfcore_base_dir: Optional[Path] = None,
                 galaxy_tools_dir: Optional[Path] = None,
                 tool_index_db: Optional[str] = None):
        """Initialize resolver with data sources."""
        self.nfcore_base_dir = nfcore_base_dir
        self.galaxy_tools_dir = galaxy_tools_dir
        self.tool_index_db = tool_index_db

    def resolve(self, tool_name: str, tool_id: Optional[str] = None,
                category: Optional[str] = None,
                tool_xml_path: Optional[Path] = None) -> ResourceRequirement:
        """Resolve resource requirements from multiple sources."""

        # Priority 1: nf-core modules (most reliable)
        result = self._from_nfcore_module(tool_name)
        if result:
            log.info(f"Resolved {tool_name} from nf-core module")
            return result

        # Priority 2: Galaxy tool XML (has CPU hints)
        result = self._from_galaxy_xml(tool_id, tool_xml_path)
        if result:
            log.info(f"Resolved {tool_name} from Galaxy XML")
            return result

        # Priority 3: Category-based defaults
        if category:
            result = self._from_category(tool_name, category)
            log.info(f"Resolved {tool_name} from category: {category}")
            return result

        # Priority 4: Conservative default
        log.warning(f"Using conservative default for {tool_name}")
        return self._default_resources(tool_name)

    def _from_nfcore_module(self, tool_name: str) -> Optional[ResourceRequirement]:
        """Extract resources from nf-core module."""
        if not self.nfcore_base_dir:
            return None

        # Search for module
        module_paths = list(self.nfcore_base_dir.glob(f"**/modules/nf-core/{tool_name}/main.nf"))
        module_paths.extend(list(self.nfcore_base_dir.glob(f"**/modules/nf-core/*/{tool_name}/main.nf")))

        for module_path in module_paths:
            try:
                with open(module_path) as f:
                    content = f.read()

                # Extract label
                label_match = re.search(r'label\s+"([^"]+)"', content)
                if label_match:
                    label = label_match.group(1)
                    if label in self.RESOURCE_LABELS:
                        resources = self.RESOURCE_LABELS[label]
                        return ResourceRequirement(
                            cpus=resources['cpus'],
                            memory_gb=resources['memory_gb'],
                            time_hours=resources['time_hours'],
                            label=label,
                            source='nfcore_module',
                            confidence=1.0
                        )
            except Exception as e:
                log.warning(f"Error parsing nf-core module {module_path}: {e}")
                continue

        return None

    def _from_galaxy_xml(self, tool_id: Optional[str],
                         tool_xml_path: Optional[Path]) -> Optional[ResourceRequirement]:
        """Extract resources from Galaxy tool XML."""

        # Find XML file
        xml_path = tool_xml_path
        if not xml_path and tool_id and self.galaxy_tools_dir:
            # Search for XML in shed_tools directory
            xml_paths = list(self.galaxy_tools_dir.glob(f"**/{tool_id}/*.xml"))
            if xml_paths:
                xml_path = xml_paths[0]

        if not xml_path or not xml_path.exists():
            return None

        try:
            # Parse XML
            tree = ET.parse(xml_path)
            root = tree.getroot()

            # Look for command section
            command_elem = root.find('.//command')
            if command_elem is None or command_elem.text is None:
                return None

            command_text = command_elem.text

            # Extract GALAXY_SLOTS hint
            cpus = self._extract_galaxy_slots(command_text)
            if cpus:
                # Map CPU count to label
                label = self._cpus_to_label(cpus)
                resources = self.RESOURCE_LABELS[label]

                return ResourceRequirement(
                    cpus=cpus,
                    memory_gb=resources['memory_gb'],
                    time_hours=resources['time_hours'],
                    label=label,
                    source='galaxy_xml',
                    confidence=0.7  # Medium confidence - only CPU hint
                )

        except Exception as e:
            log.warning(f"Error parsing Galaxy XML {xml_path}: {e}")

        return None

    def _extract_galaxy_slots(self, command_text: str) -> Optional[int]:
        """Extract default CPU count from GALAXY_SLOTS variable."""
        # Pattern: ${GALAXY_SLOTS:-N}
        match = re.search(r'\$\{GALAXY_SLOTS:-(\d+)\}', command_text)
        if match:
            return int(match.group(1))

        # Pattern: --threads ${GALAXY_SLOTS:-N}
        match = re.search(r'--threads?\s+\$\{GALAXY_SLOTS:-(\d+)\}', command_text)
        if match:
            return int(match.group(1))

        # Pattern: -p ${GALAXY_SLOTS:-N}
        match = re.search(r'-p\s+\$\{GALAXY_SLOTS:-(\d+)\}', command_text)
        if match:
            return int(match.group(1))

        return None

    def _cpus_to_label(self, cpus: int) -> str:
        """Map CPU count to resource label."""
        if cpus == 1:
            return 'process_single'
        elif cpus <= 2:
            return 'process_low'
        elif cpus <= 6:
            return 'process_medium'
        else:
            return 'process_high'

    def _from_category(self, tool_name: str, category: str) -> ResourceRequirement:
        """Infer resources from tool category."""
        # Normalize category
        category_lower = category.lower().replace(' ', '_')

        # Find matching category
        label = self.CATEGORY_DEFAULTS.get(category_lower, 'process_medium')
        resources = self.RESOURCE_LABELS[label]

        return ResourceRequirement(
            cpus=resources['cpus'],
            memory_gb=resources['memory_gb'],
            time_hours=resources['time_hours'],
            label=label,
            source='category_default',
            confidence=0.5
        )

    def _default_resources(self, tool_name: str) -> ResourceRequirement:
        """Return conservative default resources."""
        resources = self.RESOURCE_LABELS['process_medium']
        return ResourceRequirement(
            cpus=resources['cpus'],
            memory_gb=resources['memory_gb'],
            time_hours=resources['time_hours'],
            label='process_medium',
            source='default',
            confidence=0.3
        )


class LLMResourceInferencer:
    """Use LLM to infer resource requirements from tool documentation."""

    def __init__(self, llm_client=None):
        """Initialize with LLM client (optional)."""
        self.llm_client = llm_client

    def infer_from_documentation(self, tool_name: str, tool_description: str,
                                  category: Optional[str] = None) -> ResourceRequirement:
        """Use LLM to infer resources from tool documentation."""

        if not self.llm_client:
            log.warning("No LLM client configured, using category default")
            return self._fallback_inference(tool_name, category)

        prompt = self._build_inference_prompt(tool_name, tool_description, category)

        try:
            response = self.llm_client.generate(prompt)
            result = json.loads(response)

            return ResourceRequirement(
                cpus=result['cpus'],
                memory_gb=result['memory_gb'],
                time_hours=result['time_hours'],
                label=result['label'],
                source='llm_inference',
                confidence=result.get('confidence', 0.6)
            )

        except Exception as e:
            log.error(f"LLM inference failed: {e}")
            return self._fallback_inference(tool_name, category)

    def _build_inference_prompt(self, tool_name: str, tool_description: str,
                                category: Optional[str]) -> str:
        """Build prompt for LLM resource inference."""
        return f"""Given a bioinformatics tool, estimate its typical resource requirements.

Tool Name: {tool_name}
Description: {tool_description}
Category: {category or 'unknown'}

Based on typical usage patterns for tools in this category, estimate:
1. CPU cores needed (1, 2, 6, 12, or 24)
2. Memory needed (in GB: 6, 12, 36, 72, or 200)
3. Typical runtime (in hours: 1, 4, 8, 16, or 24)
4. Resource label (process_single, process_low, process_medium, process_high, process_high_memory)
5. Confidence in estimate (0.0 to 1.0)

Consider:
- Tool documentation and published benchmarks
- Computational complexity of the algorithm
- Typical dataset sizes
- Similar tools in the same category

Return ONLY valid JSON:
{{
    "cpus": <int>,
    "memory_gb": <int>,
    "time_hours": <int>,
    "label": "<string>",
    "confidence": <float>,
    "reasoning": "<brief explanation>"
}}
"""

    def _fallback_inference(self, tool_name: str, category: Optional[str]) -> ResourceRequirement:
        """Fallback when LLM inference fails."""
        resolver = ResourceResolver()
        return resolver._from_category(tool_name, category or 'unknown')


def resolve_resources(tool_name: str, tool_id: Optional[str] = None,
                      category: Optional[str] = None,
                      tool_xml_path: Optional[Path] = None,
                      nfcore_base: Optional[Path] = None,
                      galaxy_tools: Optional[Path] = None) -> ResourceRequirement:
    """Convenience function to resolve resources."""

    resolver = ResourceResolver(
        nfcore_base_dir=nfcore_base,
        galaxy_tools_dir=galaxy_tools
    )

    return resolver.resolve(
        tool_name=tool_name,
        tool_id=tool_id,
        category=category,
        tool_xml_path=tool_xml_path
    )
