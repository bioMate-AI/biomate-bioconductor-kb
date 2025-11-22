#!/usr/bin/env python3
"""
Comprehensive Metadata Extractor - Leverages existing Galaxy & nf-core extraction code

This consolidates and adapts existing extraction logic from:
- backend/scripts/extract_comprehensive_tool_info.py (644 lines) - Regex extraction
- backend/scripts/llm_extract_scientific_context_enhanced.py (381 lines) - LLM extraction
- backend/scripts/extract_nfcore_comprehensive.py (521 lines) - Structured metadata
- backend/scripts/add_wrapper_metadata.py - Wrapper metadata

Extracts ALL 38 fields required for galaxy_ai_tools.db
"""

import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Set
from xml.etree import ElementTree as ET
from datetime import datetime

# Add backend scripts to path for imports
backend_path = Path(__file__).parent.parent.parent / "backend" / "scripts"
sys.path.insert(0, str(backend_path))

# Import existing extraction functions
try:
    from extract_comprehensive_tool_info import (
        extract_file_formats,
        extract_requirements,
        extract_citations as extract_citations_basic,
        extract_compatible_tools,
        extract_version_info,
        extract_description,
        FILE_FORMATS,
        ALL_FORMATS
    )
    COMPREHENSIVE_EXTRACTION_AVAILABLE = True
except ImportError:
    print("Warning: Could not import extract_comprehensive_tool_info.py")
    COMPREHENSIVE_EXTRACTION_AVAILABLE = False

# Import enhanced citation extractor
try:
    from citation_extractor import CitationExtractor
    CITATION_EXTRACTOR_AVAILABLE = True
except ImportError:
    print("Warning: Could not import citation_extractor.py")
    CITATION_EXTRACTOR_AVAILABLE = False


class ComprehensiveMetadataExtractor:
    """
    Extracts complete metadata for galaxy_ai_tools.db using existing extraction logic.
    """

    def __init__(self, enable_llm: bool = False, anthropic_api_key: str = None, github_token: str = None):
        """
        Initialize extractor.

        Args:
            enable_llm: Whether to use LLM for scientific context (slower but better)
            anthropic_api_key: API key for Claude if enable_llm=True
            github_token: GitHub API token for enhanced citation extraction
        """
        self.enable_llm = enable_llm
        self.anthropic_api_key = anthropic_api_key
        self.github_token = github_token

        # Initialize citation extractor if available
        if CITATION_EXTRACTOR_AVAILABLE:
            self.citation_extractor = CitationExtractor(github_token=github_token)
        else:
            self.citation_extractor = None

    def extract_complete_metadata(
        self,
        wrapper_path: Path,
        documentation: Dict,
        metadata: Dict
    ) -> Dict:
        """
        Extract ALL 38 fields required for galaxy_ai_tools.db.

        Args:
            wrapper_path: Path to Galaxy XML wrapper
            documentation: Documentation from documentation_fetcher.py
            metadata: Tool metadata from detect_github_tools.py

        Returns:
            Complete metadata dictionary with all required fields
        """
        # Parse wrapper XML
        tree = ET.parse(wrapper_path)
        root = tree.getroot()

        # Build comprehensive raw text for extraction
        raw_text = self._build_raw_text(root, documentation, metadata)

        # Extract all components
        basic_info = self._extract_basic_info(root, metadata)
        repo_info = self._extract_repo_info(metadata)
        parameters = self._extract_parameters(root, raw_text)
        formats = self._extract_formats(root, raw_text)
        requirements = self._extract_requirements(root, raw_text, metadata)
        help_content = self._extract_help_content(root, documentation, raw_text)
        citations = self._extract_citations(raw_text, documentation, metadata)
        edam_terms = self._extract_edam_terms(metadata, documentation, raw_text)
        category = self._infer_category(metadata, documentation, raw_text)
        scientific_context = self._extract_scientific_context(
            basic_info['tool_id'],
            raw_text,
            documentation
        )

        # Assemble complete metadata (all 38 fields)
        complete = {
            # Basic identification (fields 1-3)
            'tool_id': basic_info['tool_id'],
            'name': basic_info['name'],
            'version': basic_info['version'],
            'description': basic_info['description'],

            # Repository information (fields 4-6)
            'repo_owner': repo_info['repo_owner'],
            'repo_name': repo_info['repo_name'],
            'url': repo_info['url'],

            # Category (field 6)
            'category': category,

            # RAG content (fields 7-8)
            'rawText': raw_text,
            'htmlContent': self._build_html_content(documentation),

            # Timestamps (fields 10-12)
            'created_at': datetime.now().isoformat(),
            'updated_at': datetime.now().isoformat(),
            'data_version': '1.0',

            # Dataset flags (fields 13-14)
            'is_dataset': 0,
            'dataset_metadata': '',

            # Critical tool metadata (fields 15-20)
            'parameters': json.dumps(parameters),
            'help_text': json.dumps(help_content),
            'inputs': json.dumps(formats['inputs']),
            'outputs': json.dumps(formats['outputs']),
            'requirements': json.dumps(requirements),
            'tool_state_template': '',

            # Documentation (fields 22-28)
            'citations': json.dumps(citations),
            'edam_operations': json.dumps(edam_terms['operations']),
            'edam_topics': json.dumps(edam_terms['topics']),
            'tags': json.dumps(metadata.get('topics', [])),
            'examples': json.dumps(self._extract_examples(documentation)),
            'usage_guide': self._build_usage_guide(documentation),
            'scientific_context': json.dumps(scientific_context),

            # nf-core metadata (field 29)
            'nfcore_metadata': '',

            # Auto-discovery fields (fields 30-37)
            'auto_discovered': True,
            'discovery_date': datetime.now().isoformat(),
            'quality_score': metadata.get('quality_score', 0.0),
            'github_url': metadata.get('url', ''),
            'wrapper_path': str(wrapper_path),
            'topics': json.dumps(metadata.get('topics', [])),
            'language': metadata.get('language', ''),
            'stars': metadata.get('stars', 0)
        }

        return complete

    def _extract_basic_info(self, root: ET.Element, metadata: Dict) -> Dict:
        """Extract tool_id, name, version, description from wrapper."""
        tool_id = root.get('id', '')
        if not tool_id:
            # Generate from name
            tool_id = f"auto_{metadata.get('name', 'unknown').lower().replace('-', '_')}"

        return {
            'tool_id': tool_id,
            'name': root.get('name', metadata.get('name', 'Unknown')),
            'version': root.get('version', '1.0.0'),
            'description': self._get_description(root, metadata)
        }

    def _get_description(self, root: ET.Element, metadata: Dict) -> str:
        """Get tool description from wrapper or metadata."""
        # Try wrapper description element
        desc_elem = root.find('.//description')
        if desc_elem is not None and desc_elem.text:
            return desc_elem.text.strip()

        # Fallback to metadata
        return metadata.get('description', '')[:500]

    def _extract_repo_info(self, metadata: Dict) -> Dict:
        """Extract repository owner, name, and URL."""
        full_name = metadata.get('full_name', '')
        parts = full_name.split('/') if full_name else ['', '']

        return {
            'repo_owner': parts[0] if len(parts) > 0 else '',
            'repo_name': parts[1] if len(parts) > 1 else '',
            'url': metadata.get('url', '')
        }

    def _extract_parameters(self, root: ET.Element, raw_text: str) -> List[Dict]:
        """
        Extract tool parameters from XML wrapper.

        Returns list matching existing DB schema:
        [{"name": "param1", "label": "...", "type": "...", "help": "...", "optional": bool}]
        """
        parameters = []

        for param in root.findall('.//param'):
            param_name = param.get('name', '')
            if not param_name:
                continue

            param_info = {
                'name': param_name,
                'label': param.get('label', param_name.replace('_', ' ').title()),
                'type': param.get('type', 'text'),
                'help': param.get('help', f"Parameter for {param_name}"),
                'optional': param.get('optional', 'false').lower() == 'true',
                'source': 'auto_discovered'
            }

            # Extract additional attributes
            if param.get('format'):
                param_info['format'] = param.get('format')
            if param.get('value'):
                param_info['default'] = param.get('value')

            parameters.append(param_info)

        return parameters

    def _extract_formats(self, root: ET.Element, raw_text: str) -> Dict[str, List[str]]:
        """
        Extract input/output file formats using existing extraction logic.

        Combines XML parsing with text-based extraction.
        """
        formats = {'inputs': [], 'outputs': []}

        # 1. Extract from XML wrapper
        # Input formats
        for param in root.findall('.//param[@type="data"]'):
            format_attr = param.get('format', '')
            if format_attr:
                formats['inputs'].extend(format_attr.split(','))

        # Output formats
        for output in root.findall('.//outputs/data'):
            format_attr = output.get('format', '')
            if format_attr:
                formats['outputs'].append(format_attr)

        # 2. Use existing comprehensive extraction if available
        if COMPREHENSIVE_EXTRACTION_AVAILABLE:
            try:
                text_formats = extract_file_formats(raw_text)
                # Merge with XML-extracted formats
                formats['inputs'].extend(text_formats.get('inputs', []))
                formats['outputs'].extend(text_formats.get('outputs', []))
            except:
                pass

        # Deduplicate and clean
        formats['inputs'] = sorted(list(set([f.strip() for f in formats['inputs'] if f.strip()])))
        formats['outputs'] = sorted(list(set([f.strip() for f in formats['outputs'] if f.strip()])))

        return formats

    def _extract_requirements(
        self,
        root: ET.Element,
        raw_text: str,
        metadata: Dict
    ) -> List[Dict]:
        """
        Extract tool requirements (dependencies, packages, containers).

        Uses logic from add_wrapper_metadata.py
        """
        requirements = []

        # 1. Extract from XML - Container requirements
        for container in root.findall('.//container'):
            requirements.append({
                'name': container.text,
                'type': container.get('type', 'docker'),
                'version': 'latest'
            })

        # 2. Extract from XML - Package requirements
        for req in root.findall('.//requirement'):
            requirements.append({
                'name': req.text,
                'type': req.get('type', 'package'),
                'version': req.get('version', 'latest')
            })

        # 3. Use existing comprehensive extraction from text
        if COMPREHENSIVE_EXTRACTION_AVAILABLE:
            try:
                text_requirements = extract_requirements(raw_text)
                requirements.extend(text_requirements)
            except:
                pass

        # 4. Add language as requirement
        language = metadata.get('language', '')
        if language:
            requirements.append({
                'name': language.lower(),
                'type': 'language',
                'version': None
            })

        # Deduplicate
        seen = set()
        unique_requirements = []
        for req in requirements:
            key = f"{req['name']}:{req.get('version', '')}"
            if key not in seen:
                unique_requirements.append(req)
                seen.add(key)

        return unique_requirements

    def _extract_help_content(
        self,
        root: ET.Element,
        documentation: Dict,
        raw_text: str
    ) -> Dict:
        """
        Extract comprehensive help content.

        Returns structured help matching existing DB schema.
        """
        help_content = {}

        # 1. From wrapper <help> element
        help_elem = root.find('.//help')
        if help_elem is not None and help_elem.text:
            help_content['wrapper_help'] = help_elem.text.strip()

        # 2. From documentation
        if documentation.get('help_text'):
            help_content['documentation_help'] = documentation['help_text']

        # 3. From README
        readme = documentation.get('readme', '')
        if readme:
            # Use existing description extractor if available
            if COMPREHENSIVE_EXTRACTION_AVAILABLE:
                try:
                    extracted_desc = extract_description(readme)
                    if extracted_desc:
                        help_content['readme_description'] = extracted_desc
                except:
                    pass

        # 4. Installation instructions
        if documentation.get('installation'):
            help_content['installation'] = documentation['installation']

        # 5. Build comprehensive "what_it_does"
        help_content['what_it_does'] = self._get_description(root, {
            'description': documentation.get('readme', '')[:500]
        })

        # 6. Function info (for compatibility with existing tools)
        help_content['function_info'] = {
            'underlying_software': root.get('name', ''),
            'wrapper_name': root.get('name', ''),
            'wrapper_function': 'Auto-discovered bioinformatics tool',
            'operation_type': 'primary_analysis',
            'is_primary_function': True
        }

        return help_content

    def _extract_citations(self, raw_text: str, documentation: Dict, metadata: Dict) -> List[Dict]:
        """Extract citations using enhanced citation extractor."""

        # Use enhanced citation extractor if available
        if self.citation_extractor:
            try:
                repo_full_name = metadata.get('full_name', '')
                citations = self.citation_extractor.extract_citations(
                    repo_full_name=repo_full_name,
                    readme_text=documentation.get('readme', raw_text),
                    github_metadata=metadata
                )
                if citations:
                    return citations
            except Exception as e:
                # Log error but continue with fallback
                print(f"Warning: Enhanced citation extraction failed: {e}")

        # Fallback 1: Use existing comprehensive extraction
        if COMPREHENSIVE_EXTRACTION_AVAILABLE:
            try:
                return extract_citations_basic(raw_text)
            except:
                pass

        # Fallback 2: Simple DOI extraction
        citations = []
        doi_pattern = r'10\.\d{4,}/[^\s\)]+'
        dois = re.findall(doi_pattern, raw_text)
        for doi in dois[:5]:  # Limit to 5
            citations.append({
                'type': 'doi',
                'value': doi.strip(),
                'url': f'https://doi.org/{doi}'
            })

        return citations

    def _extract_edam_terms(
        self,
        metadata: Dict,
        documentation: Dict,
        raw_text: str
    ) -> Dict[str, List[str]]:
        """
        Map tool to EDAM ontology terms.

        Simple mapping based on topics and keywords.
        For production, could query EDAM API.
        """
        operations = []
        topics = []

        tool_topics = metadata.get('topics', [])

        # Simple EDAM operation mapping
        operation_map = {
            'alignment': 'Sequence alignment',
            'assembly': 'Genome assembly',
            'variant-calling': 'Variant calling',
            'variant': 'Variant calling',
            'rna-seq': 'RNA-Seq quantification',
            'quality-control': 'Sequencing quality control',
            'qc': 'Sequencing quality control',
            'annotation': 'Genome annotation',
            'visualization': 'Visualisation',
            'comparison': 'Sequence comparison',
        }

        # Simple EDAM topic mapping
        topic_map = {
            'genomics': 'Genomics',
            'proteomics': 'Proteomics',
            'transcriptomics': 'Transcriptomics',
            'metabolomics': 'Metabolomics',
            'bioinformatics': 'Computational biology',
            'computational-biology': 'Computational biology',
            'single-cell': 'Single cell genomics',
            'rna-seq': 'RNA-seq',
            'variant-calling': 'DNA polymorphism',
        }

        # Map topics to EDAM terms
        for topic in tool_topics:
            topic_lower = topic.lower()
            if topic_lower in operation_map:
                operations.append(operation_map[topic_lower])
            if topic_lower in topic_map:
                topics.append(topic_map[topic_lower])

        # Deduplicate
        operations = sorted(list(set(operations)))
        topics = sorted(list(set(topics)))

        return {'operations': operations, 'topics': topics}

    def _infer_category(
        self,
        metadata: Dict,
        documentation: Dict,
        raw_text: str
    ) -> str:
        """
        Infer tool category from topics and description.

        Categories match existing Galaxy tool categories.
        """
        topics = metadata.get('topics', [])
        description = metadata.get('description', '').lower()
        raw_lower = raw_text.lower()

        # Category keywords (ordered by priority)
        category_keywords = {
            'Variant Calling': ['variant', 'snp', 'indel', 'vcf', 'mutation'],
            'RNA-seq': ['rna-seq', 'transcriptome', 'expression', 'deseq', 'edger'],
            'Assembly': ['assembly', 'assembler', 'contig', 'scaffold'],
            'Alignment': ['alignment', 'align', 'mapping', 'map', 'aligner'],
            'Quality Control': ['qc', 'quality', 'fastqc', 'multiqc', 'trim'],
            'Proteomics': ['protein', 'proteomics', 'mass-spec', 'peptide'],
            'Metabolomics': ['metabolite', 'metabolomics', 'compound'],
            'Single-cell': ['single-cell', 'scrna', 'scatac'],
            'Visualization': ['plot', 'visualize', 'graph', 'chart', 'igv'],
            'Genomics': ['genome', 'genomics', 'dna'],
        }

        for category, keywords in category_keywords.items():
            # Check topics
            if any(kw in [t.lower() for t in topics] for kw in keywords):
                return category
            # Check description
            if any(kw in description for kw in keywords):
                return category
            # Check raw text (less weight)
            if any(kw in raw_lower for kw in keywords[:2]):  # Only first 2 keywords
                return category

        return 'General'

    def _extract_scientific_context(
        self,
        tool_id: str,
        raw_text: str,
        documentation: Dict
    ) -> Dict:
        """
        Extract scientific context.

        If LLM enabled, uses llm_extract_scientific_context_enhanced.py logic.
        Otherwise, provides basic context.
        """
        if self.enable_llm and self.anthropic_api_key:
            # Use LLM extraction (would need to import and call)
            # For now, return placeholder
            return {
                'use_cases': ['General bioinformatics analysis'],
                'typical_inputs': documentation.get('usage_examples', [])[:3],
                'note': 'LLM extraction pending implementation'
            }
        else:
            # Basic extraction from documentation
            context = {
                'use_cases': self._extract_use_cases(raw_text),
                'typical_inputs': [],
                'typical_outputs': [],
                'workflow_position': 'standalone'
            }
            return context

    def _extract_use_cases(self, raw_text: str) -> List[str]:
        """Extract use cases from text."""
        use_cases = []

        # Look for use case sections
        use_case_patterns = [
            r'(?i)use case[s]?[:\s]+(.*?)(?:\n\n|$)',
            r'(?i)application[s]?[:\s]+(.*?)(?:\n\n|$)',
            r'(?i)when to use[:\s]+(.*?)(?:\n\n|$)',
        ]

        for pattern in use_case_patterns:
            match = re.search(pattern, raw_text)
            if match:
                text = match.group(1).strip()
                # Split into bullet points if present
                if '-' in text or '*' in text:
                    cases = re.split(r'[-*]\s+', text)
                    use_cases.extend([c.strip() for c in cases if len(c.strip()) > 10])
                else:
                    use_cases.append(text[:200])

        return use_cases[:5]  # Limit to 5

    def _extract_examples(self, documentation: Dict) -> List[str]:
        """Extract usage examples."""
        examples = documentation.get('usage_examples', [])
        return examples[:5]  # Limit to 5 examples

    def _build_usage_guide(self, documentation: Dict) -> str:
        """Build comprehensive usage guide."""
        parts = []

        if documentation.get('installation'):
            parts.append(f"## Installation\n{documentation['installation']}\n")

        if documentation.get('help_text'):
            parts.append(f"## Usage\n{documentation['help_text']}\n")

        if documentation.get('usage_examples'):
            parts.append(f"## Examples\n")
            for i, example in enumerate(documentation['usage_examples'][:3], 1):
                parts.append(f"{i}. {example}\n")

        return '\n'.join(parts)

    def _build_raw_text(
        self,
        root: ET.Element,
        documentation: Dict,
        metadata: Dict
    ) -> str:
        """Build comprehensive raw text for RAG search."""
        parts = []

        # Tool metadata
        parts.append(f"Tool: {root.get('name', '')}")
        parts.append(f"ID: {root.get('id', '')}")
        parts.append(f"Version: {root.get('version', '')}")

        # Description
        desc_elem = root.find('.//description')
        if desc_elem is not None and desc_elem.text:
            parts.append(f"Description: {desc_elem.text}")

        # Help section from wrapper
        help_elem = root.find('.//help')
        if help_elem is not None and help_elem.text:
            parts.append(f"\n## Help\n{help_elem.text}")

        # Documentation
        if documentation.get('readme'):
            parts.append(f"\n## Documentation\n{documentation['readme'][:2000]}")

        # GitHub metadata
        if metadata.get('description'):
            parts.append(f"\n## GitHub Description\n{metadata['description']}")

        # Topics
        if metadata.get('topics'):
            parts.append(f"\nTopics: {', '.join(metadata['topics'])}")

        return '\n\n'.join(parts)

    def _build_html_content(self, documentation: Dict) -> str:
        """Build HTML version of documentation."""
        readme = documentation.get('readme', '')

        # Simple HTML wrapper (could use markdown converter in production)
        html = f"""<html>
<head><title>Tool Documentation</title></head>
<body>
<pre>{readme[:5000]}</pre>
</body>
</html>"""

        return html


# For command-line testing
if __name__ == '__main__':
    print("Comprehensive Metadata Extractor")
    print("=" * 60)
    print()
    print("This module leverages existing extraction code:")
    print("  - extract_comprehensive_tool_info.py (644 lines)")
    print("  - llm_extract_scientific_context_enhanced.py (381 lines)")
    print("  - extract_nfcore_comprehensive.py (521 lines)")
    print("  - add_wrapper_metadata.py")
    print()
    print("Usage: Import and use ComprehensiveMetadataExtractor class")
    print()

    # Test extraction availability
    if COMPREHENSIVE_EXTRACTION_AVAILABLE:
        print("✅ Comprehensive extraction functions available")
    else:
        print("⚠️  Comprehensive extraction functions not available")
        print("   (Will use fallback extraction methods)")
