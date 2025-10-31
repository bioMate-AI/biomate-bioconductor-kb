#!/usr/bin/env python3
"""
Extract comprehensive information from nf-core modules meta.yml files
and add them to the Galaxy AI Tools database.

nf-core modules have excellent structured documentation:
- Descriptions
- Keywords
- Input/output formats
- Dependencies (from environment.yml)
- Documentation URLs
- Examples (from main.nf)
- EDAM ontology terms
- Citations/licenses
"""

import json
import sqlite3
import yaml
import re
from pathlib import Path
from typing import Dict, List, Any, Optional


def parse_meta_yml(meta_path: Path) -> Dict[str, Any]:
    """Parse nf-core module meta.yml file."""
    with open(meta_path, 'r') as f:
        data = yaml.safe_load(f)
    return data


def parse_environment_yml(env_path: Path) -> List[Dict[str, str]]:
    """Parse environment.yml for dependencies."""
    if not env_path.exists():
        return []

    with open(env_path, 'r') as f:
        data = yaml.safe_load(f)

    requirements = []
    if 'dependencies' in data:
        for dep in data['dependencies']:
            if isinstance(dep, str):
                # Format: "package=version" or "package"
                parts = dep.split('=')
                requirements.append({
                    'name': parts[0].strip(),
                    'version': parts[1].strip() if len(parts) > 1 else None,
                    'type': 'conda'
                })
            elif isinstance(dep, dict):
                # pip dependencies
                for key, value in dep.items():
                    if key == 'pip' and isinstance(value, list):
                        for pip_dep in value:
                            parts = pip_dep.split('==')
                            requirements.append({
                                'name': parts[0].strip(),
                                'version': parts[1].strip() if len(parts) > 1 else None,
                                'type': 'pip'
                            })

    return requirements


def parse_main_nf(main_path: Path) -> Dict[str, Any]:
    """Extract command examples and usage from main.nf."""
    if not main_path.exists():
        return {'examples': [], 'command': ''}

    with open(main_path, 'r') as f:
        content = f.read()

    examples = []
    command = ''

    # Extract command template
    script_match = re.search(r'script:\s*"""(.*?)"""', content, re.DOTALL)
    if script_match:
        command = script_match.group(1).strip()
        # Clean up Nextflow variables
        command = re.sub(r'\$\{.*?\}', '<input>', command)
        command = re.sub(r'\$\w+', '<param>', command)
        if len(command) > 20:
            examples.append(command[:500])

    # Extract when clauses as usage conditions
    when_matches = re.findall(r'when:\s*(.*?)(?:\n\n|$)', content, re.DOTALL)
    for when in when_matches:
        if len(when) < 200:
            examples.append(f"Usage condition: {when.strip()}")

    return {
        'examples': examples[:3],  # Keep top 3
        'command': command[:1000] if command else ''
    }


def extract_inputs_outputs(meta: Dict) -> Dict[str, List]:
    """Extract structured input/output information."""
    inputs = []
    outputs = []

    # Parse inputs
    if 'input' in meta:
        for input_group in meta['input']:
            for item in input_group:
                if isinstance(item, dict):
                    for name, spec in item.items():
                        if name != 'meta' and isinstance(spec, dict):
                            input_info = {
                                'name': name,
                                'type': spec.get('type', 'file'),
                                'description': spec.get('description', '').strip(),
                                'pattern': spec.get('pattern', ''),
                                'ontologies': spec.get('ontologies', [])
                            }
                            inputs.append(input_info)

                            # Extract file formats from pattern
                            if 'pattern' in spec:
                                formats = extract_formats_from_pattern(spec['pattern'])
                                input_info['formats'] = formats

    # Parse outputs
    if 'output' in meta:
        for output_name, output_group in meta['output'].items():
            if isinstance(output_group, list):
                for item in output_group:
                    if isinstance(item, dict):
                        for key, spec in item.items():
                            if key != 'meta' and isinstance(spec, dict):
                                output_info = {
                                    'name': output_name,
                                    'type': spec.get('type', 'file'),
                                    'description': spec.get('description', '').strip(),
                                    'pattern': spec.get('pattern', ''),
                                    'ontologies': spec.get('ontologies', [])
                                }
                                outputs.append(output_info)

                                # Extract file formats
                                if 'pattern' in spec:
                                    formats = extract_formats_from_pattern(spec['pattern'])
                                    output_info['formats'] = formats

    return {
        'inputs': inputs,
        'outputs': outputs
    }


def extract_formats_from_pattern(pattern: str) -> List[str]:
    """Extract file format extensions from pattern string."""
    formats = []

    # Pattern: "*.{bam,sam,cram}"
    brace_match = re.search(r'\*\.?\{([^}]+)\}', pattern)
    if brace_match:
        formats.extend(brace_match.group(1).split(','))

    # Pattern: "*.fastq" or "*.fastq.gz"
    ext_matches = re.findall(r'\*\.([a-z0-9]+(?:\.[a-z0-9]+)?)', pattern)
    formats.extend(ext_matches)

    # Clean and deduplicate
    formats = [f.strip().lower() for f in formats]
    return list(set(formats))


def extract_comprehensive_nfcore_info(module_dir: Path) -> Optional[Dict[str, Any]]:
    """Extract all comprehensive information from nf-core module directory."""
    meta_path = module_dir / 'meta.yml'
    env_path = module_dir / 'environment.yml'
    main_path = module_dir / 'main.nf'

    if not meta_path.exists():
        return None

    try:
        # Parse meta.yml
        meta = parse_meta_yml(meta_path)

        # Extract tool information
        tool_info = {}
        if 'tools' in meta and meta['tools']:
            # tools is a list containing dicts
            if isinstance(meta['tools'], list) and len(meta['tools']) > 0:
                first_tool = meta['tools'][0]
                if isinstance(first_tool, dict):
                    tool_name = list(first_tool.keys())[0]
                    tool_info = first_tool[tool_name]
            elif isinstance(meta['tools'], dict):
                # Handle legacy format if it exists
                tool_name = list(meta['tools'].keys())[0]
                tool_info = meta['tools'][tool_name]

        # Parse dependencies
        requirements = parse_environment_yml(env_path)

        # Parse examples from main.nf
        nf_info = parse_main_nf(main_path)

        # Extract inputs/outputs
        io_info = extract_inputs_outputs(meta)

        # Extract EDAM terms from ontologies
        edam_terms = []
        for output in io_info['outputs']:
            if 'ontologies' in output:
                for onto in output['ontologies']:
                    if isinstance(onto, dict):
                        for key, value in onto.items():
                            if 'edam' in key.lower() and isinstance(value, str):
                                edam_terms.append(value)

        # Extract input/output formats
        input_formats = []
        for inp in io_info['inputs']:
            if 'formats' in inp:
                input_formats.extend(inp['formats'])

        output_formats = []
        for out in io_info['outputs']:
            if 'formats' in out:
                output_formats.extend(out['formats'])

        # Build tool ID
        tool_id = f"nfcore_{meta.get('name', module_dir.name)}"

        return {
            'tool_id': tool_id,
            'name': meta.get('name', module_dir.name),
            'description': tool_info.get('description', meta.get('description', '')).strip(),
            'version': None,  # Version is in conda package
            'category': 'nf-core',
            'keywords': meta.get('keywords', []),
            'examples': nf_info['examples'],
            'usage_guide': nf_info['command'],
            'inputs': input_formats,
            'outputs': output_formats,
            'inputs_detailed': io_info['inputs'],
            'outputs_detailed': io_info['outputs'],
            'requirements': requirements,
            'homepage': tool_info.get('homepage', ''),
            'documentation': tool_info.get('documentation', ''),
            'license': tool_info.get('licence', []),
            'identifier': tool_info.get('identifier', ''),
            'edam_operations': edam_terms,
            'authors': meta.get('authors', []),
            'maintainers': meta.get('maintainers', []),
            'citations': [],  # Will extract from license/identifier
        }

    except Exception as e:
        print(f"Error processing {module_dir}: {e}")
        return None


def insert_nfcore_tools_to_db(db_path: str, nfcore_modules_path: str):
    """Insert nf-core tools into the database."""

    print(f"Opening database: {db_path}")
    print(f"Scanning nf-core modules: {nfcore_modules_path}")
    print("="*80)

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Find all nf-core modules
    modules_dir = Path(nfcore_modules_path) / "modules" / "nf-core"
    all_modules = [d for d in modules_dir.iterdir() if d.is_dir()]

    print(f"Found {len(all_modules)} nf-core modules")
    print()

    stats = {
        'processed': 0,
        'inserted': 0,
        'skipped': 0,
        'errors': 0
    }

    batch = []
    batch_size = 50

    for module_dir in all_modules:
        try:
            info = extract_comprehensive_nfcore_info(module_dir)

            if not info:
                stats['skipped'] += 1
                continue

            # Check if already exists
            cursor.execute("SELECT tool_id FROM tools WHERE tool_id = ?", (info['tool_id'],))
            if cursor.fetchone():
                print(f"  Skipping {info['name']} (already exists)")
                stats['skipped'] += 1
                continue

            # Prepare data for insertion
            batch.append((
                None,  # id (auto-increment)
                info['tool_id'],
                info['name'],
                info['version'],
                'nf-core',  # repo_owner
                info['name'],  # repo_name
                info['category'],
                '',  # rawText
                '',  # htmlContent
                info['homepage'],  # url
                None,  # created_at
                None,  # updated_at
                None,  # data_version
                0,  # is_dataset
                None,  # dataset_metadata
                json.dumps([]),  # parameters (empty for now)
                json.dumps({
                    'what_it_does': info['description'],
                    'keywords': info['keywords'],
                    'homepage': info['homepage'],
                    'documentation': info['documentation']
                }),  # help_text
                json.dumps(info['inputs_detailed']),  # inputs
                json.dumps(info['outputs_detailed']),  # outputs
                json.dumps(info['requirements']),  # requirements
                None,  # tool_state_template
                info['description'][:500],  # description
                json.dumps(info['citations']),  # citations
                json.dumps(info['edam_operations']),  # edam_operations
                None,  # edam_topics
                json.dumps(info['keywords'] + info['authors']),  # tags
                json.dumps(info['examples']),  # examples
                info['usage_guide'][:1000] if info['usage_guide'] else None,  # usage_guide
            ))

            stats['inserted'] += 1
            stats['processed'] += 1

            # Batch insert
            if len(batch) >= batch_size:
                cursor.executemany('''
                    INSERT INTO tools (
                        id, tool_id, name, version, repo_owner, repo_name, category,
                        rawText, htmlContent, url, created_at, updated_at, data_version,
                        is_dataset, dataset_metadata, parameters, help_text, inputs, outputs,
                        requirements, tool_state_template, description, citations,
                        edam_operations, edam_topics, tags, examples, usage_guide
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ''', batch)
                conn.commit()
                batch = []

                if stats['inserted'] % 100 == 0:
                    print(f"  Inserted {stats['inserted']} nf-core tools...")

        except Exception as e:
            stats['errors'] += 1
            if stats['errors'] <= 5:
                print(f"  Error processing {module_dir.name}: {str(e)[:100]}")

    # Final batch
    if batch:
        cursor.executemany('''
            INSERT INTO tools (
                id, tool_id, name, version, repo_owner, repo_name, category,
                rawText, htmlContent, url, created_at, updated_at, data_version,
                is_dataset, dataset_metadata, parameters, help_text, inputs, outputs,
                requirements, tool_state_template, description, citations,
                edam_operations, edam_topics, tags, examples, usage_guide
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', batch)
        conn.commit()

    conn.close()

    print("="*80)
    print(f"✅ nf-core module extraction complete:")
    print(f"   Total processed: {stats['processed']}")
    print(f"   Successfully inserted: {stats['inserted']}")
    print(f"   Skipped (already exists): {stats['skipped']}")
    print(f"   Errors: {stats['errors']}")

    return stats


def main():
    """Main function."""
    db_path = Path(__file__).parent.parent / "database" / "galaxy_ai_tools.db"
    nfcore_path = Path(__file__).parent.parent / "nf-core-modules"

    if not db_path.exists():
        print(f"❌ Database not found at {db_path}")
        return 1

    if not nfcore_path.exists():
        print(f"❌ nf-core-modules not found at {nfcore_path}")
        print("Clone it first: git clone https://github.com/nf-core/modules.git nf-core-modules")
        return 1

    print("="*80)
    print("nf-core Modules - Comprehensive Information Extraction")
    print("="*80)
    print(f"Database: {db_path}")
    print(f"nf-core modules: {nfcore_path}")
    print()
    print("Extracting:")
    print("  • Descriptions and keywords")
    print("  • Input/output formats and structures")
    print("  • Dependencies from environment.yml")
    print("  • Command examples from main.nf")
    print("  • EDAM ontology terms")
    print("  • Documentation URLs")
    print("  • Authors and maintainers")
    print()

    try:
        stats = insert_nfcore_tools_to_db(str(db_path), str(nfcore_path))

        print()
        print("="*80)
        print("✅ EXTRACTION COMPLETE")
        print("="*80)
        print()
        print(f"Database now includes {stats['inserted']} nf-core modules")
        print()
        print("Next steps:")
        print("  1. Restart Galaxy backend")
        print("  2. Test nf-core tool schemas")
        print("  3. Verify nf-core tools appear in search")

        return 0

    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == '__main__':
    import sys
    sys.exit(main())
