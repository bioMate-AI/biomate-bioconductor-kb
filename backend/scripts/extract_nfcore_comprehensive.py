#!/usr/bin/env python3
"""
Extract comprehensive metadata from nf-core modules, subworkflows, and workflows.

This script enhances tool metadata by extracting:
- Module metadata: Tool-specific information from meta.yml
- Subworkflow metadata: Multi-step workflow patterns
- Workflow metadata: Complete pipeline documentation and use cases

Sources:
- /opt/biomate/backend/nf-core-modules/modules/nf-core/*/meta.yml (755 modules)
- /opt/biomate/backend/nf-core-modules/subworkflows/nf-core/*/meta.yml (93 subworkflows)
- /opt/biomate/backend/nf-core-workflows/*/README.md (7+ workflows)
"""

import os
import sqlite3
import json
import yaml
from pathlib import Path
from typing import Dict, List, Optional
from collections import defaultdict


# Paths
NF_CORE_MODULES = Path("/opt/biomate/backend/nf-core-modules/modules/nf-core")
NF_CORE_SUBWORKFLOWS = Path("/opt/biomate/backend/nf-core-modules/subworkflows/nf-core")
NF_CORE_WORKFLOWS = Path("/opt/biomate/backend/nf-core-workflows")


def extract_module_metadata(module_path: Path) -> Optional[Dict]:
    """Extract metadata from nf-core module meta.yml."""
    meta_file = module_path / "meta.yml"
    if not meta_file.exists():
        return None

    try:
        with open(meta_file) as f:
            data = yaml.safe_load(f)

        metadata = {
            'type': 'module',
            'name': data.get('name', ''),
            'description': data.get('description', ''),
            'keywords': data.get('keywords', []),
            'tools': {},
            'input_spec': [],
            'output_spec': [],
            'edam_operations': [],
            'edam_topics': []
        }

        # Extract tool information with DOIs
        if 'tools' in data:
            tools_data = data['tools']
            # Handle both dict and list formats
            if isinstance(tools_data, dict):
                for tool_name, tool_info in tools_data.items():
                    metadata['tools'][tool_name] = {
                        'description': tool_info.get('description', ''),
                        'homepage': tool_info.get('homepage', ''),
                        'documentation': tool_info.get('documentation', ''),
                        'doi': tool_info.get('doi', ''),
                        'licence': tool_info.get('licence', []),
                        'identifier': tool_info.get('identifier', '')
                    }
            elif isinstance(tools_data, list):
                # Some modules use list format
                for tool_item in tools_data:
                    if isinstance(tool_item, dict):
                        for tool_name, tool_info in tool_item.items():
                            if isinstance(tool_info, dict):
                                metadata['tools'][tool_name] = {
                                    'description': tool_info.get('description', ''),
                                    'homepage': tool_info.get('homepage', ''),
                                    'documentation': tool_info.get('documentation', ''),
                                    'doi': tool_info.get('doi', ''),
                                    'licence': tool_info.get('licence', []),
                                    'identifier': tool_info.get('identifier', '')
                                }

        # Extract input/output specifications
        def parse_io_spec(io_list):
            specs = []
            if isinstance(io_list, list):
                for item in io_list:
                    if isinstance(item, list):
                        for subitem in item:
                            if isinstance(subitem, dict):
                                for key, value in subitem.items():
                                    if isinstance(value, dict):
                                        spec = {
                                            'name': key,
                                            'type': value.get('type', ''),
                                            'description': value.get('description', ''),
                                            'pattern': value.get('pattern', ''),
                                            'ontologies': value.get('ontologies', [])
                                        }
                                        specs.append(spec)
                                        # Extract EDAM ontologies
                                        for onto in value.get('ontologies', []):
                                            if isinstance(onto, dict) and 'edam' in onto:
                                                metadata['edam_operations'].append(onto['edam'])
            return specs

        metadata['input_spec'] = parse_io_spec(data.get('input', []))
        metadata['output_spec'] = parse_io_spec(data.get('output', []))

        return metadata

    except Exception as e:
        print(f"  Error parsing {meta_file}: {str(e)}")
        return None


def extract_subworkflow_metadata(subworkflow_path: Path) -> Optional[Dict]:
    """Extract metadata from nf-core subworkflow meta.yml."""
    meta_file = subworkflow_path / "meta.yml"
    if not meta_file.exists():
        return None

    try:
        with open(meta_file) as f:
            data = yaml.safe_load(f)

        metadata = {
            'type': 'subworkflow',
            'name': data.get('name', ''),
            'description': data.get('description', ''),
            'keywords': data.get('keywords', []),
            'components': data.get('components', []),  # List of modules used
            'input_spec': [],
            'output_spec': []
        }

        # Parse I/O similar to modules
        def parse_io_spec(io_list):
            specs = []
            if isinstance(io_list, list):
                for item in io_list:
                    if isinstance(item, dict):
                        for key, value in item.items():
                            if isinstance(value, dict):
                                specs.append({
                                    'name': key,
                                    'type': value.get('type', ''),
                                    'description': value.get('description', ''),
                                    'pattern': value.get('pattern', '')
                                })
            return specs

        metadata['input_spec'] = parse_io_spec(data.get('input', []))
        metadata['output_spec'] = parse_io_spec(data.get('output', []))

        return metadata

    except Exception as e:
        print(f"  Error parsing {meta_file}: {str(e)}")
        return None


def extract_workflow_metadata(workflow_path: Path) -> Optional[Dict]:
    """Extract metadata from complete nf-core workflow README."""
    readme_file = workflow_path / "README.md"
    if not readme_file.exists():
        return None

    try:
        with open(readme_file) as f:
            content = f.read()

        metadata = {
            'type': 'workflow',
            'name': workflow_path.name,
            'description': '',
            'use_cases': [],
            'input_types': [],
            'output_types': [],
            'steps': [],
            'citations': []
        }

        # Extract description (usually after first header, before Quick Start)
        lines = content.split('\n')
        in_intro = False
        for i, line in enumerate(lines):
            if '## Introduction' in line or '## Quick Start' in line:
                if not in_intro:
                    in_intro = True
                    continue
                else:
                    break
            if in_intro and line.strip() and not line.startswith('#'):
                metadata['description'] += line.strip() + ' '

        # Extract pipeline steps
        if '## Pipeline Summary' in content or 'Pipeline overview' in content:
            for line in lines:
                if line.strip().startswith('*') and (' (' in line or "'" in line):
                    step = line.strip().lstrip('*').strip()
                    metadata['steps'].append(step)

        # Extract citations
        if '## Citation' in content:
            in_citations = False
            for line in lines:
                if '## Citation' in line:
                    in_citations = True
                elif in_citations and line.startswith('## '):
                    break
                elif in_citations and 'doi:' in line.lower():
                    metadata['citations'].append(line.strip())

        return metadata

    except Exception as e:
        print(f"  Error parsing {readme_file}: {str(e)}")
        return None


def build_nfcore_index():
    """Build comprehensive index of nf-core modules, subworkflows, and workflows."""
    print("=" * 80)
    print("Building nf-core Comprehensive Index")
    print("=" * 80)
    print()

    index = {
        'modules': {},
        'subworkflows': {},
        'workflows': {},
        'tool_to_modules': defaultdict(list),  # Map tool name to modules
        'keyword_to_items': defaultdict(list)  # Map keywords to items
    }

    # Extract modules
    print("📦 Extracting modules...")
    if NF_CORE_MODULES.exists():
        for module_dir in NF_CORE_MODULES.iterdir():
            if module_dir.is_dir():
                metadata = extract_module_metadata(module_dir)
                if metadata:
                    index['modules'][module_dir.name] = metadata

                    # Build reverse index for tools
                    for tool_name in metadata['tools'].keys():
                        index['tool_to_modules'][tool_name.lower()].append(module_dir.name)

                    # Index by keywords
                    for keyword in metadata['keywords']:
                        index['keyword_to_items'][keyword.lower()].append({
                            'type': 'module',
                            'name': module_dir.name
                        })

        print(f"   Found {len(index['modules'])} modules")

    # Extract subworkflows
    print("🔗 Extracting subworkflows...")
    if NF_CORE_SUBWORKFLOWS.exists():
        for subworkflow_dir in NF_CORE_SUBWORKFLOWS.iterdir():
            if subworkflow_dir.is_dir():
                metadata = extract_subworkflow_metadata(subworkflow_dir)
                if metadata:
                    index['subworkflows'][subworkflow_dir.name] = metadata

                    # Index by keywords
                    for keyword in metadata['keywords']:
                        index['keyword_to_items'][keyword.lower()].append({
                            'type': 'subworkflow',
                            'name': subworkflow_dir.name
                        })

        print(f"   Found {len(index['subworkflows'])} subworkflows")

    # Extract workflows
    print("🔬 Extracting workflows...")
    if NF_CORE_WORKFLOWS.exists():
        for workflow_dir in NF_CORE_WORKFLOWS.iterdir():
            if workflow_dir.is_dir() and not workflow_dir.name.startswith('.'):
                metadata = extract_workflow_metadata(workflow_dir)
                if metadata:
                    index['workflows'][workflow_dir.name] = metadata

        print(f"   Found {len(index['workflows'])} workflows")

    print()
    print("=" * 80)
    print("✅ nf-core Index Built")
    print("=" * 80)
    print(f"   Modules: {len(index['modules'])}")
    print(f"   Subworkflows: {len(index['subworkflows'])}")
    print(f"   Workflows: {len(index['workflows'])}")
    print(f"   Unique tools: {len(index['tool_to_modules'])}")
    print(f"   Unique keywords: {len(index['keyword_to_items'])}")
    print()

    return index


def enrich_tool_metadata_with_nfcore(db_path: str, nfcore_index: Dict):
    """
    Enrich existing tool metadata with nf-core information.

    For each tool in the database:
    1. Find matching nf-core modules
    2. Extract rich metadata (DOIs, EDAM, input/output specs)
    3. Find related subworkflows
    4. Find related complete workflows
    5. Add as nfcore_metadata field
    """
    print("=" * 80)
    print("Enriching Tool Metadata with nf-core Information")
    print("=" * 80)
    print()

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    # Check if nfcore_metadata column exists
    cursor.execute("PRAGMA table_info(tools)")
    columns = [row[1] for row in cursor.fetchall()]

    if 'nfcore_metadata' not in columns:
        print("Adding nfcore_metadata column...")
        cursor.execute("ALTER TABLE tools ADD COLUMN nfcore_metadata TEXT")
        conn.commit()

    # Get all tools
    cursor.execute("SELECT id, name, tool_id, category, description FROM tools")
    tools = cursor.fetchall()

    stats = {
        'total': len(tools),
        'enriched': 0,
        'with_modules': 0,
        'with_subworkflows': 0,
        'with_workflows': 0,
        'with_dois': 0
    }

    print(f"Processing {len(tools)} tools...")
    print()

    for i, tool in enumerate(tools, 1):
        tool_name_lower = tool['name'].lower().replace(' ', '').replace('-', '').replace('_', '')

        nfcore_data = {
            'modules': [],
            'subworkflows': [],
            'workflows': [],
            'related_tools': [],
            'dois': [],
            'edam_operations': [],
            'typical_inputs': [],
            'typical_outputs': []
        }

        # Find matching modules
        for module_name, module_meta in nfcore_index['modules'].items():
            module_name_norm = module_name.lower().replace(' ', '').replace('-', '').replace('_', '')

            # Check if names match
            if tool_name_lower in module_name_norm or module_name_norm in tool_name_lower:
                nfcore_data['modules'].append({
                    'name': module_name,
                    'description': module_meta['description'],
                    'keywords': module_meta['keywords'],
                    'tools': module_meta['tools'],
                    'edam_operations': module_meta['edam_operations']
                })

                stats['with_modules'] += 1

                # Collect DOIs
                for tool_info in module_meta['tools'].values():
                    if tool_info.get('doi'):
                        nfcore_data['dois'].append(tool_info['doi'])
                        stats['with_dois'] += 1

                # Collect EDAM operations
                nfcore_data['edam_operations'].extend(module_meta['edam_operations'])

                # Collect typical I/O
                for inp in module_meta['input_spec']:
                    if inp['pattern'] and inp['pattern'] not in nfcore_data['typical_inputs']:
                        nfcore_data['typical_inputs'].append(inp['pattern'])

                for out in module_meta['output_spec']:
                    if out['pattern'] and out['pattern'] not in nfcore_data['typical_outputs']:
                        nfcore_data['typical_outputs'].append(out['pattern'])

        # Find related subworkflows (by keywords or components)
        for subworkflow_name, subworkflow_meta in nfcore_index['subworkflows'].items():
            # Check if tool appears in subworkflow components
            for component in subworkflow_meta['components']:
                component_norm = component.lower().replace('/', '').replace('-', '').replace('_', '')
                if tool_name_lower in component_norm:
                    nfcore_data['subworkflows'].append({
                        'name': subworkflow_name,
                        'description': subworkflow_meta['description'],
                        'keywords': subworkflow_meta['keywords'],
                        'used_with': subworkflow_meta['components']
                    })
                    stats['with_subworkflows'] += 1
                    break

        # Find related workflows (by keywords or description)
        tool_category_lower = (tool['category'] or '').lower()
        for workflow_name, workflow_meta in nfcore_index['workflows'].items():
            workflow_desc_lower = workflow_meta['description'].lower()

            # Match by category or tool name in workflow description
            if (tool_category_lower and tool_category_lower in workflow_name.lower()) or \
               (tool_name_lower in workflow_desc_lower):
                nfcore_data['workflows'].append({
                    'name': workflow_name,
                    'description': workflow_meta['description'][:200],  # Truncate
                    'pipeline_steps': workflow_meta['steps'][:5],  # First 5 steps
                    'citations': workflow_meta['citations'][:3]  # First 3 citations
                })
                stats['with_workflows'] += 1

        # Update database if we found anything useful
        if nfcore_data['modules'] or nfcore_data['subworkflows'] or nfcore_data['workflows']:
            cursor.execute(
                "UPDATE tools SET nfcore_metadata = ? WHERE id = ?",
                (json.dumps(nfcore_data), tool['id'])
            )
            stats['enriched'] += 1

        # Progress
        if i % 500 == 0:
            print(f"  Processed {i}/{len(tools)} tools... ({stats['enriched']} enriched)")
            conn.commit()

    conn.commit()
    conn.close()

    # Summary
    print()
    print("=" * 80)
    print("✅ Enrichment Complete")
    print("=" * 80)
    print(f"   Total tools: {stats['total']}")
    print(f"   Enriched with nf-core data: {stats['enriched']} ({stats['enriched']/stats['total']*100:.1f}%)")
    print(f"   With matching modules: {stats['with_modules']}")
    print(f"   With subworkflow references: {stats['with_subworkflows']}")
    print(f"   With workflow references: {stats['with_workflows']}")
    print(f"   With DOIs: {stats['with_dois']}")
    print()

    return stats


def main():
    """Main function."""
    import argparse

    parser = argparse.ArgumentParser(description='Extract nf-core comprehensive metadata')
    parser.add_argument('--db', help='Database path', default=None)
    parser.add_argument('--index-only', action='store_true', help='Only build index, don\'t update database')

    args = parser.parse_args()

    # Determine database path
    if args.db:
        db_path = Path(args.db)
    else:
        db_path = Path(__file__).parent.parent / "database" / "galaxy_ai_tools.db"

    if not args.index_only and not db_path.exists():
        print(f"❌ Database not found at {db_path}")
        return 1

    try:
        # Build nf-core index
        nfcore_index = build_nfcore_index()

        # Save index to JSON for inspection
        index_file = Path(__file__).parent.parent / "nfcore_index.json"
        with open(index_file, 'w') as f:
            # Convert defaultdict to dict for JSON serialization
            serializable_index = {
                'modules': nfcore_index['modules'],
                'subworkflows': nfcore_index['subworkflows'],
                'workflows': nfcore_index['workflows'],
                'tool_to_modules': dict(nfcore_index['tool_to_modules']),
                'keyword_to_items': dict(nfcore_index['keyword_to_items'])
            }
            json.dump(serializable_index, f, indent=2)

        print(f"💾 Index saved to: {index_file}")
        print()

        if not args.index_only:
            # Enrich database
            enrich_tool_metadata_with_nfcore(str(db_path), nfcore_index)

        print("✅ Done! Tools now have comprehensive nf-core metadata.")
        print()
        print("This enrichment provides:")
        print("  • Module-level metadata with DOIs and EDAM ontologies")
        print("  • Subworkflow patterns showing how tools are combined")
        print("  • Complete workflow examples for end-to-end use cases")
        print("  • Typical input/output file patterns")
        print("  • Related tools and components")

        return 0

    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == '__main__':
    import sys
    sys.exit(main())
