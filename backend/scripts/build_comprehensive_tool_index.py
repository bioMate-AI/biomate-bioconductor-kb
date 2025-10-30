#!/usr/bin/env python3
"""
Build comprehensive tool search index from Galaxy ToolShed crawled data.

This script:
1. Loads all unique tools from the collected data
2. Extracts parameters and help text from rawText and htmlContent
3. Populates the galaxy_ai_tools.db with comprehensive tool information
4. Creates FTS5 search index for fast tool discovery
"""

import json
import sqlite3
import re
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Any, Optional
import html


def extract_parameters_from_text(raw_text: str, html_content: str = "") -> List[Dict[str, Any]]:
    """
    Extract parameter information from tool rawText and htmlContent.

    Looks for patterns like:
    - "Input file:"
    - "P-value threshold:"
    - "Upload data:"
    - Form field descriptions
    """
    parameters = []
    seen_params = set()  # Track parameters we've already added

    # Common parameter patterns
    patterns = [
        r'([A-Z][a-z\s]+(?:file|data|dataset|input|output|threshold|value|parameter|cutoff|score)):\s*',
        r'<label[^>]*>([^<]+)</label>',
        r'name="([^"]+)"[^>]*label="([^"]+)"',
    ]

    # Parse from rawText
    if raw_text:
        # Split into lines and look for parameter-like entries
        lines = raw_text.split('\n')
        for i, line in enumerate(lines):
            line = line.strip()

            # Pattern: "Label:" followed by description
            if ':' in line and len(line) < 100:
                parts = line.split(':', 1)
                if len(parts) == 2:
                    label = parts[0].strip()
                    # Skip common non-parameter labels
                    skip_labels = ['Repository Actions', 'What it does', 'How to use', 'Input', 'Output',
                                   'Example', 'Note', 'Warning', 'Reference', 'Citation', 'Version', 'License',
                                   'Author', 'Contact', 'URL', 'Description']
                    if label and label not in skip_labels and len(label) < 50:
                        # Get next few lines as help text
                        help_text = parts[1].strip()
                        if i + 1 < len(lines):
                            next_line = lines[i + 1].strip()
                            if next_line and not ':' in next_line[:20]:
                                help_text += ' ' + next_line

                        param_name = label.lower().replace(' ', '_').replace('-', '_').replace('(', '').replace(')', '')

                        # Avoid duplicates
                        if param_name not in seen_params:
                            param_type = infer_parameter_type(label, help_text)
                            param = {
                                'name': param_name,
                                'label': label,
                                'type': param_type,
                                'help': help_text[:200] if help_text else '',
                                'optional': 'optional' in help_text.lower(),
                                'source': 'rawText'
                            }

                            # Add type-specific attributes
                            if param_type == 'select':
                                # Try to extract options from help text
                                options = extract_select_options(help_text)
                                if options:
                                    param['options'] = options

                            parameters.append(param)
                            seen_params.add(param_name)

    return parameters


def extract_select_options(help_text: str) -> List[Dict[str, str]]:
    """Extract select options from help text if present"""
    options = []

    # Look for patterns like "Choose from: A, B, C" or "Options: A | B | C"
    import re
    patterns = [
        r'(?:choose|select|options?|values?)[\s:]+([A-Za-z0-9,\s\|]+)',
        r'\(([A-Za-z0-9,\s\|]+)\)',
    ]

    for pattern in patterns:
        match = re.search(pattern, help_text, re.IGNORECASE)
        if match:
            options_text = match.group(1)
            # Split by comma or pipe
            option_values = [opt.strip() for opt in re.split(r'[,\|]', options_text) if opt.strip()]

            # Limit to reasonable number of options (max 10)
            if 2 <= len(option_values) <= 10:
                options = [{'value': opt, 'label': opt} for opt in option_values]
                break

    return options


def infer_parameter_type(label: str, help_text: str) -> str:
    """Infer parameter type from label and help text."""
    label_lower = label.lower()
    help_lower = help_text.lower()

    if any(word in label_lower for word in ['file', 'dataset', 'data', 'input', 'upload']):
        return 'data'
    elif any(word in label_lower for word in ['threshold', 'value', 'score', 'cutoff', 'pvalue', 'p-value']):
        return 'float'
    elif any(word in label_lower for word in ['count', 'number', 'length', 'size']):
        return 'integer'
    elif any(word in label_lower for word in ['enable', 'disable', 'use', 'include']):
        return 'boolean'
    elif 'select' in help_lower or 'choose' in help_lower:
        return 'select'
    else:
        return 'text'


def extract_help_sections(raw_text: str, html_content: str = "") -> Dict[str, str]:
    """
    Extract structured help sections from tool documentation.

    Looks for:
    - "What it does?"
    - "How to use it?"
    - "Input"
    - "Output"
    - Examples
    """
    help_sections = {
        'what_it_does': '',
        'how_to_use': '',
        'input_description': '',
        'output_description': '',
        'examples': '',
        'full_text': raw_text[:2000] if raw_text else ''
    }

    if not raw_text:
        return help_sections

    # Find "What it does" section
    what_match = re.search(r'What it does\??:?\s*\n(.*?)(?=\n\n|How to use|Input:|Output:|$)',
                          raw_text, re.IGNORECASE | re.DOTALL)
    if what_match:
        help_sections['what_it_does'] = what_match.group(1).strip()[:500]

    # Find "How to use" section
    how_match = re.search(r'How to use(?: it)?\??:?\s*\n(.*?)(?=\n\n|What it does|Input:|Output:|$)',
                         raw_text, re.IGNORECASE | re.DOTALL)
    if how_match:
        help_sections['how_to_use'] = how_match.group(1).strip()[:500]

    # Find Input section
    input_match = re.search(r'Input:?\s*\n(.*?)(?=\n\n|Output:|Example:|$)',
                           raw_text, re.IGNORECASE | re.DOTALL)
    if input_match:
        help_sections['input_description'] = input_match.group(1).strip()[:300]

    # Find Output section
    output_match = re.search(r'Output:?\s*\n(.*?)(?=\n\n|Input:|Example:|$)',
                            raw_text, re.IGNORECASE | re.DOTALL)
    if output_match:
        help_sections['output_description'] = output_match.group(1).strip()[:300]

    # Find Example section
    example_match = re.search(r'Example:?\s*\n(.*?)(?=\n\n|$)',
                             raw_text, re.IGNORECASE | re.DOTALL)
    if example_match:
        help_sections['examples'] = example_match.group(1).strip()[:500]

    return help_sections


def init_database(db_path: str):
    """Initialize or recreate the database with enhanced schema."""
    with sqlite3.connect(db_path) as conn:
        cursor = conn.cursor()

        # Drop existing tables to rebuild from scratch
        cursor.execute("DROP TABLE IF EXISTS tool_compatibility")
        cursor.execute("DROP TABLE IF EXISTS tool_usage_patterns")
        cursor.execute("DROP TABLE IF EXISTS tools")

        # Create enhanced tools table
        cursor.execute("""
            CREATE TABLE tools (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                version TEXT,
                description TEXT,
                category TEXT,
                repo_owner TEXT,
                repo_name TEXT,
                repo_url TEXT,
                tool_url TEXT,
                is_installable BOOLEAN DEFAULT 1,
                inputs TEXT,  -- JSON array
                outputs TEXT, -- JSON array
                requirements TEXT, -- JSON array
                parameters TEXT, -- JSON array of parameter templates
                help_text TEXT, -- JSON object with structured help
                edam_operations TEXT, -- JSON array
                edam_topics TEXT, -- JSON array
                citations TEXT, -- JSON array
                popularity_score REAL DEFAULT 0.0,
                usage_count INTEGER DEFAULT 0,
                last_updated TIMESTAMP,
                semantic_embedding TEXT, -- JSON for future vector embeddings
                tags TEXT -- JSON array
            )
        """)

        # Create tool compatibility table
        cursor.execute("""
            CREATE TABLE tool_compatibility (
                tool_id TEXT,
                data_type TEXT,
                compatibility_type TEXT, -- 'input' or 'output'
                confidence REAL,
                FOREIGN KEY (tool_id) REFERENCES tools (id)
            )
        """)

        # Create tool usage patterns table
        cursor.execute("""
            CREATE TABLE tool_usage_patterns (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                tool_sequence TEXT, -- JSON array of tool IDs
                frequency INTEGER DEFAULT 1,
                context TEXT,
                task_type TEXT,
                success_rate REAL DEFAULT 1.0,
                last_used TIMESTAMP
            )
        """)

        # Create indexes
        cursor.execute("CREATE INDEX idx_tools_category ON tools (category)")
        cursor.execute("CREATE INDEX idx_tools_popularity ON tools (popularity_score)")
        cursor.execute("CREATE INDEX idx_tools_repo ON tools (repo_owner, repo_name)")
        cursor.execute("CREATE INDEX idx_compatibility_tool ON tool_compatibility (tool_id)")
        cursor.execute("CREATE INDEX idx_compatibility_type ON tool_compatibility (data_type)")

        # Commit happens automatically on successful exit

    print("✓ Database schema initialized")


def build_tool_index(tools_data: List[Dict[str, Any]], db_path: str):
    """Build the comprehensive tool index."""

    init_database(db_path)

    print(f"\nIndexing {len(tools_data)} tools...")
    print("="*80)

    indexed = 0
    skipped = 0
    errors = 0

    with sqlite3.connect(db_path) as conn:
        cursor = conn.cursor()

        for tool_data in tools_data:
            try:
                tool_id = tool_data['tool_id']
                name = tool_data['name']
                version = tool_data['version']
                category = tool_data['category']
                repo_owner = tool_data['repo_owner']
                repo_name = tool_data['repo_name']
                raw_text = tool_data.get('rawText', '')
                html_content = tool_data.get('htmlContent', '')

                # Extract parameters
                parameters = extract_parameters_from_text(raw_text, html_content)

                # Extract help sections
                help_sections = extract_help_sections(raw_text, html_content)

                # Generate description from synopsis or help
                description = tool_data.get('repo_synopsis', '')
                if not description and help_sections['what_it_does']:
                    description = help_sections['what_it_does'][:200]

                # Insert tool
                cursor.execute("""
                    INSERT INTO tools (
                        id, name, version, description, category, repo_owner, repo_name,
                        repo_url, tool_url, is_installable, parameters, help_text,
                        last_updated, inputs, outputs, requirements, tags
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    tool_id,
                    name,
                    version,
                    description,
                    category,
                    repo_owner,
                    repo_name,
                    tool_data.get('repo_url', ''),
                    tool_data.get('url', ''),
                    tool_data.get('is_installable', True),
                    json.dumps(parameters),
                    json.dumps(help_sections),
                    datetime.now().isoformat(),
                    json.dumps([]),  # inputs - will be populated from parameters
                    json.dumps([]),  # outputs
                    json.dumps([]),  # requirements
                    json.dumps([category, repo_owner])  # tags
                ))

                # Index data type compatibility (inferred from parameters)
                for param in parameters:
                    if param['type'] == 'data':
                        cursor.execute("""
                            INSERT INTO tool_compatibility (tool_id, data_type, compatibility_type, confidence)
                            VALUES (?, ?, 'input', 1.0)
                        """, (tool_id, 'input_data'))

                indexed += 1

                if indexed % 500 == 0:
                    conn.commit()
                    print(f"  Indexed {indexed} tools...")

            except Exception as e:
                errors += 1
                if errors <= 5:  # Show first 5 errors
                    print(f"  Error indexing tool {tool_data.get('name', 'unknown')[:50]}: {str(e)[:100]}")

        # Final commit happens automatically on successful exit

    print("="*80)
    print(f"✅ Indexing complete:")
    print(f"   Successfully indexed: {indexed}")
    print(f"   Errors: {errors}")

    return indexed, errors


def create_fts_index(db_path: str):
    """Create FTS5 full-text search index."""
    with sqlite3.connect(db_path) as conn:
        cursor = conn.cursor()

        print("\nCreating FTS5 search index...")

        # Drop existing FTS index if exists
        cursor.execute("DROP TABLE IF EXISTS tools_fts")

        # Create FTS5 virtual table (tool_id is now searchable - Fix #3)
        # Note: Not using content=tools to avoid trigger issues
        cursor.execute("""
            CREATE VIRTUAL TABLE tools_fts USING fts5(
                tool_id,
                name,
                description,
                category,
                parameters,
                help_text
            )
        """)

        # Populate FTS index
        cursor.execute("""
            INSERT INTO tools_fts (tool_id, name, description, category, parameters, help_text)
            SELECT id, name, description, category, parameters, help_text
            FROM tools
        """)

        # Commit happens automatically on successful exit

    print("✓ FTS5 search index created")


def main():
    """Main function."""
    # Paths
    backend_dir = Path(__file__).parent.parent
    tools_json = backend_dir / "database" / "all_unique_tools.json"
    db_path = backend_dir / "galaxy_ai_tools.db"

    print("="*80)
    print("Building Comprehensive Galaxy Tool Search Index")
    print("="*80)
    print(f"Input: {tools_json}")
    print(f"Database: {db_path}")

    # Load tools data
    print(f"\nLoading tools from {tools_json}...")
    with open(tools_json, 'r', encoding='utf-8') as f:
        tools_data = json.load(f)

    print(f"✓ Loaded {len(tools_data)} unique tools")

    # Build index
    indexed, errors = build_tool_index(tools_data, str(db_path))

    # Create FTS search index
    create_fts_index(str(db_path))

    # Print summary
    print("\n" + "="*80)
    print("🎉 INDEX BUILD COMPLETE")
    print("="*80)
    print(f"Database: {db_path}")
    print(f"Size: {db_path.stat().st_size / (1024*1024):.1f} MB")
    print(f"Tools indexed: {indexed}")
    print(f"\nNext steps:")
    print(f"1. Test search: sqlite3 {db_path} \"SELECT * FROM tools_fts WHERE tools_fts MATCH 'metabolomics' LIMIT 5\"")
    print(f"2. Update galaxy_tool_rag.py to use this comprehensive index")
    print(f"3. Add custom external tools to the database")


if __name__ == '__main__':
    main()