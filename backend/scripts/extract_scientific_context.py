#!/usr/bin/env python3
"""
Extract scientific context from tool documentation for ACE learning system.

This module enhances the existing extraction pipeline by adding:
- data_types_supported/not_supported (e.g., DDA, DIA, targeted, label-free)
- typical_use_cases
- common_mistakes
- best_for (strengths)
- limitations
- compatibility_notes
"""

import re
import json
from typing import Dict, List, Set, Any, Optional
from pathlib import Path


# Domain-specific terminology patterns
PROTEOMICS_DATA_TYPES = {
    'DDA': ['data-dependent acquisition', 'dda', 'shotgun proteomics', 'data dependent'],
    'DIA': ['data-independent acquisition', 'dia', 'swath', 'swath-ms', 'data independent'],
    'targeted': ['targeted proteomics', 'srm', 'mrm', 'prm', 'parallel reaction monitoring', 'selected reaction monitoring'],
    'label_free': ['label-free', 'label free', 'lfq', 'intensity-based'],
    'labeled': ['tmt', 'itraq', 'silac', 'isotopic labeling', 'chemical labeling'],
    'top_down': ['top-down', 'intact protein', 'native proteomics'],
    'bottom_up': ['bottom-up', 'peptide-based', 'digested protein']
}

GENOMICS_DATA_TYPES = {
    'WGS': ['whole genome sequencing', 'wgs', 'genome-wide'],
    'WES': ['whole exome sequencing', 'wes', 'exome'],
    'RNA_seq': ['rna-seq', 'rna sequencing', 'transcriptome'],
    'ChIP_seq': ['chip-seq', 'chromatin immunoprecipitation'],
    'ATAC_seq': ['atac-seq', 'open chromatin'],
    'single_cell': ['single-cell', 'single cell', 'scrnaseq', 'scrna-seq']
}

METABOLOMICS_DATA_TYPES = {
    'targeted': ['targeted metabolomics', 'quantitative'],
    'untargeted': ['untargeted', 'discovery', 'metabolite profiling'],
    'lipidomics': ['lipidomics', 'lipid analysis']
}


def extract_data_types(text: str, category: str = None) -> Dict[str, List[str]]:
    """
    Extract supported and not supported data types from tool documentation.

    Args:
        text: Raw text from tool documentation
        category: Tool category (Proteomics, Genomics, etc.)

    Returns:
        {
            'supported': ['DIA', 'SWATH'],
            'not_supported': ['DDA'],
            'inferred': True/False  # Whether types were inferred vs explicitly stated
        }
    """
    text_lower = text.lower()
    supported = set()
    not_supported = set()
    explicit = False

    # Select relevant data type dictionary
    if category == 'Proteomics':
        data_types = PROTEOMICS_DATA_TYPES
    elif category == 'Genomics':
        data_types = GENOMICS_DATA_TYPES
    elif category == 'Metabolomics':
        data_types = METABOLOMICS_DATA_TYPES
    else:
        # Try all categories
        data_types = {**PROTEOMICS_DATA_TYPES, **GENOMICS_DATA_TYPES, **METABOLOMICS_DATA_TYPES}

    # Pattern 1: Explicit support statements
    for data_type, patterns in data_types.items():
        for pattern in patterns:
            # Look for explicit support statements
            support_patterns = [
                rf'\b(support|designed for|built for|optimized for|specialized for|specific to|compatible with).*?{pattern}\b',
                rf'\b{pattern}.*?(support|data|analysis|workflow)\b',
                rf'\b(for|with)\s+{pattern}\b'
            ]

            for sp in support_patterns:
                if re.search(sp, text_lower):
                    supported.add(data_type)
                    explicit = True
                    break

    # Pattern 2: Explicit incompatibility statements
    for data_type, patterns in data_types.items():
        for pattern in patterns:
            incompatible_patterns = [
                rf'\b(not compatible|incompatible|not support|does not support|cannot|not suitable|not designed for|not work).*?{pattern}\b',
                rf'\b{pattern}.*?(not support|incompatible|cannot|not suitable)\b',
                rf'\bonly.*?(dda|dia|targeted).*?not.*?{pattern}\b',
                rf'\b{pattern}.*?only\b'  # e.g., "DDA only"
            ]

            for ip in incompatible_patterns:
                if re.search(ip, text_lower):
                    not_supported.add(data_type)
                    explicit = True
                    break

    # Pattern 3: Exclusive statements (e.g., "DDA only" implies not DIA)
    if category == 'Proteomics':
        if re.search(r'\b(dda|data-dependent).*?only\b', text_lower):
            supported.add('DDA')
            not_supported.add('DIA')
            explicit = True
        elif re.search(r'\b(dia|data-independent|swath).*?only\b', text_lower):
            supported.add('DIA')
            not_supported.add('DDA')
            explicit = True

    return {
        'supported': sorted(list(supported)),
        'not_supported': sorted(list(not_supported)),
        'explicit': explicit
    }


def extract_use_cases(text: str, tool_name: str = "") -> List[str]:
    """Extract typical use cases from tool documentation."""
    use_cases = []
    text_lower = text.lower()

    # Pattern 1: "Used for X", "Designed for X"
    use_case_patterns = [
        r'(?:used|designed|optimized|intended|suitable)\s+(?:for|to)\s+([^.!?\n]{10,100})',
        r'(?:performs|provides|enables|allows)\s+([^.!?\n]{10,100})',
        r'(?:typical|common)\s+(?:use cases?|applications?|workflows?).*?:\s*([^.!?\n]{10,200})',
    ]

    for pattern in use_case_patterns:
        matches = re.findall(pattern, text_lower, re.IGNORECASE)
        for match in matches[:3]:  # Limit to top 3
            cleaned = match.strip()
            if len(cleaned) > 15 and len(cleaned) < 150:
                use_cases.append(cleaned)

    # Pattern 2: Task-specific keywords
    task_keywords = {
        'quality control': ['quality control', 'qc', 'quality assessment', 'quality check'],
        'variant calling': ['variant calling', 'snp detection', 'mutation detection'],
        'quantification': ['quantification', 'abundance estimation', 'expression quantification'],
        'alignment': ['sequence alignment', 'mapping', 'read alignment'],
        'differential expression': ['differential expression', 'differential abundance', 'dea'],
        'identification': ['peptide identification', 'protein identification', 'compound identification'],
        'visualization': ['visualization', 'plotting', 'graphical representation']
    }

    for task, keywords in task_keywords.items():
        if any(keyword in text_lower for keyword in keywords):
            use_cases.append(f"{task.title()}")

    # Deduplicate and limit
    unique_cases = []
    seen = set()
    for uc in use_cases:
        uc_norm = uc.lower().strip()
        if uc_norm not in seen and len(unique_cases) < 5:
            unique_cases.append(uc)
            seen.add(uc_norm)

    return unique_cases


def extract_common_mistakes(text: str) -> List[str]:
    """Extract common mistakes and pitfalls from tool documentation."""
    mistakes = []

    # Patterns for common mistake descriptions
    mistake_patterns = [
        r'(?:common mistake|common error|pitfall|caution|warning|note).*?:\s*([^.!?\n]{15,200})',
        r'(?:do not|don\'t|should not|avoid|never).*?([^.!?\n]{15,150})',
        r'(?:incorrect|wrong|improper).*?(?:use|usage|application).*?([^.!?\n]{15,150})',
        r'(?:not suitable|not compatible|incompatible|not designed).*?(?:for|with).*?([^.!?\n]{15,150})'
    ]

    for pattern in mistake_patterns:
        matches = re.findall(pattern, text, re.IGNORECASE)
        for match in matches[:3]:
            cleaned = match.strip()
            if len(cleaned) > 20:
                mistakes.append(cleaned)

    return mistakes[:5]  # Limit to top 5


def extract_limitations(text: str) -> List[str]:
    """Extract tool limitations from documentation."""
    limitations = []

    limitation_patterns = [
        r'(?:limitation|constraint|restriction).*?:\s*([^.!?\n]{15,200})',
        r'(?:cannot|unable to|does not support|limited to).*?([^.!?\n]{15,150})',
        r'(?:only support|only work|only available).*?([^.!?\n]{15,150})',
        r'(?:requires|needs|depends on|prerequisite).*?([^.!?\n]{15,150})'
    ]

    for pattern in limitation_patterns:
        matches = re.findall(pattern, text, re.IGNORECASE)
        for match in matches[:3]:
            cleaned = match.strip()
            if len(cleaned) > 20:
                limitations.append(cleaned)

    return limitations[:5]


def extract_best_for(text: str, tool_name: str = "") -> List[str]:
    """Extract what the tool is best suited for (strengths)."""
    strengths = []

    strength_patterns = [
        r'(?:best|excellent|optimal|superior|ideal|perfect)\s+(?:for|at)\s+([^.!?\n]{10,100})',
        r'(?:strength|advantage|benefit).*?:\s*([^.!?\n]{15,150})',
        r'(?:excels at|specializes in|focused on).*?([^.!?\n]{15,150})',
        r'(?:high|fast|accurate|robust|scalable|efficient)\s+([^.!?\n]{10,100})'
    ]

    for pattern in strength_patterns:
        matches = re.findall(pattern, text, re.IGNORECASE)
        for match in matches[:3]:
            cleaned = match.strip()
            if len(cleaned) > 15 and len(cleaned) < 150:
                strengths.append(cleaned)

    return strengths[:5]


def extract_scientific_context(
    tool_name: str,
    category: str,
    raw_text: str,
    help_text: str = "",
    description: str = ""
) -> Dict[str, Any]:
    """
    Main function to extract complete scientific context from tool documentation.

    Args:
        tool_name: Name of the tool
        category: Tool category (Proteomics, Genomics, etc.)
        raw_text: Raw text documentation
        help_text: Structured help text (JSON)
        description: Short description

    Returns:
        Dictionary with scientific context for ACE learning system
    """
    # Combine all text sources
    combined_text = f"{raw_text}\n{description}\n"
    if help_text:
        try:
            help_obj = json.loads(help_text) if isinstance(help_text, str) else help_text
            if isinstance(help_obj, dict):
                combined_text += "\n".join(help_obj.values())
        except:
            combined_text += str(help_text)

    # Extract all components
    data_types = extract_data_types(combined_text, category)
    use_cases = extract_use_cases(combined_text, tool_name)
    mistakes = extract_common_mistakes(combined_text)
    limitations = extract_limitations(combined_text)
    strengths = extract_best_for(combined_text, tool_name)

    # Build context object
    context = {
        'data_types': {
            'supported': data_types['supported'],
            'not_supported': data_types['not_supported'],
            'explicit': data_types['explicit']
        },
        'typical_use_cases': use_cases,
        'common_mistakes': mistakes,
        'limitations': limitations,
        'best_for': strengths,
        'has_rich_context': (
            len(data_types['supported']) > 0 or
            len(use_cases) > 0 or
            len(mistakes) > 0 or
            len(strengths) > 0
        )
    }

    return context


def extract_nfcore_metadata(meta_yml_path: Path) -> Dict[str, Any]:
    """
    Extract metadata from nf-core meta.yml file.

    Args:
        meta_yml_path: Path to meta.yml file

    Returns:
        Dictionary with extracted metadata
    """
    try:
        import yaml
        with open(meta_yml_path) as f:
            data = yaml.safe_load(f)

        # Extract relevant fields
        metadata = {
            'name': data.get('name', ''),
            'description': data.get('description', ''),
            'keywords': data.get('keywords', []),
            'tools': {},
            'input_formats': [],
            'output_formats': [],
            'edam_ontologies': []
        }

        # Extract tool information
        if 'tools' in data:
            for tool_name, tool_info in data['tools'].items():
                metadata['tools'][tool_name] = {
                    'description': tool_info.get('description', ''),
                    'homepage': tool_info.get('homepage', ''),
                    'doi': tool_info.get('doi', ''),
                    'licence': tool_info.get('licence', [])
                }

        # Extract input/output formats and EDAM ontologies
        def extract_formats(io_list):
            formats = []
            ontologies = []
            if isinstance(io_list, list):
                for item in io_list:
                    if isinstance(item, list):
                        for subitem in item:
                            if isinstance(subitem, dict):
                                # Look for file patterns
                                for key, value in subitem.items():
                                    if isinstance(value, dict):
                                        if 'pattern' in value:
                                            pattern = value['pattern']
                                            # Extract file extensions
                                            exts = re.findall(r'\*\.(\w+)', pattern)
                                            formats.extend(exts)
                                        if 'ontologies' in value:
                                            ontologies.extend(value.get('ontologies', []))
            return formats, ontologies

        if 'input' in data:
            metadata['input_formats'], input_ontos = extract_formats(data['input'])
            metadata['edam_ontologies'].extend(input_ontos)

        if 'output' in data:
            metadata['output_formats'], output_ontos = extract_formats(data['output'])
            metadata['edam_ontologies'].extend(output_ontos)

        return metadata

    except Exception as e:
        return {'error': str(e)}


def main():
    """Test the extraction functions on sample tools."""
    import sqlite3

    db_path = Path(__file__).parent.parent / "database" / "galaxy_ai_tools.db"

    if not db_path.exists():
        print(f"❌ Database not found at {db_path}")
        return 1

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    # Test on a few proteomics tools
    test_tools = ['MaxQuant', 'DIA-NN', 'MSstats']

    print("=" * 80)
    print("Testing Scientific Context Extraction")
    print("=" * 80)
    print()

    for tool_name_pattern in test_tools:
        cursor.execute("""
            SELECT name, category, description, rawText, help_text
            FROM tools
            WHERE name LIKE ?
            LIMIT 1
        """, (f'%{tool_name_pattern}%',))

        row = cursor.fetchone()
        if not row:
            print(f"⚠️  Tool '{tool_name_pattern}' not found")
            continue

        print(f"\n{'='*80}")
        print(f"Tool: {row['name']}")
        print(f"Category: {row['category']}")
        print(f"{'='*80}")

        context = extract_scientific_context(
            tool_name=row['name'],
            category=row['category'],
            raw_text=row['rawText'] or '',
            help_text=row['help_text'] or '',
            description=row['description'] or ''
        )

        print("\n📊 Scientific Context Extracted:")
        print(json.dumps(context, indent=2))

    conn.close()
    return 0


if __name__ == '__main__':
    import sys
    sys.exit(main())
