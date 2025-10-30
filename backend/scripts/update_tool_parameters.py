#!/usr/bin/env python3
"""
Update existing tools database to extract and populate parameters
from the rawText and htmlContent fields that are already stored.

This script processes the existing database and adds structured parameter
information to enable parameter editing at the frontend.
"""

import json
import sqlite3
import re
from pathlib import Path
from typing import Dict, List, Any


def extract_select_options(help_text: str) -> List[Dict[str, str]]:
    """Extract select options from help text if present"""
    options = []

    # Look for patterns like "Choose from: A, B, C" or "Options: A | B | C"
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
                                   'Author', 'Contact', 'URL', 'Description', 'Tool', 'Synopsis', 'Repository']
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


def update_database_parameters(db_path: str, batch_size: int = 100):
    """Update tools database with extracted parameters"""

    print(f"Opening database: {db_path}")
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    # Get total count
    cursor.execute("SELECT COUNT(*) FROM tools WHERE rawText IS NOT NULL AND rawText != ''")
    total = cursor.fetchone()[0]

    print(f"Processing {total} tools with rawText...")
    print("="*80)

    updated = 0
    with_params = 0
    processed = 0

    # Process in batches - fetch all rows first to avoid cursor issues
    cursor.execute("""
        SELECT tool_id, name, rawText, htmlContent
        FROM tools
        WHERE rawText IS NOT NULL AND rawText != ''
    """)
    all_tools = cursor.fetchall()

    batch = []
    for row in all_tools:
        tool_id = row['tool_id']
        name = row['name']
        raw_text = row['rawText'] or ''
        html_content = row['htmlContent'] or ''

        # Extract parameters
        parameters = extract_parameters_from_text(raw_text, html_content)
        help_sections = extract_help_sections(raw_text, html_content)

        batch.append((
            json.dumps(parameters),
            json.dumps(help_sections),
            tool_id
        ))

        if parameters:
            with_params += 1

        processed += 1

        # Update in batches
        if len(batch) >= batch_size:
            update_cursor = conn.cursor()
            update_cursor.executemany('''
                UPDATE tools
                SET parameters = ?, help_text = ?
                WHERE tool_id = ?
            ''', batch)
            update_cursor.close()
            conn.commit()
            updated += len(batch)
            batch = []

            if updated % 500 == 0:
                print(f"  Processed {updated}/{total} tools ({with_params} with parameters)...")

    # Final batch
    if batch:
        update_cursor = conn.cursor()
        update_cursor.executemany('''
            UPDATE tools
            SET parameters = ?, help_text = ?
            WHERE tool_id = ?
        ''', batch)
        update_cursor.close()
        conn.commit()
        updated += len(batch)

    conn.close()

    print("="*80)
    print(f"✅ Parameter extraction complete:")
    print(f"   Total processed: {processed}")
    print(f"   Total updated: {updated}")
    print(f"   With parameters: {with_params} ({with_params/processed*100:.1f}%)")

    return updated, with_params


def main():
    """Main function"""
    db_path = Path(__file__).parent.parent / "galaxy_ai_tools.db"

    if not db_path.exists():
        print(f"❌ Database not found at {db_path}")
        return 1

    print("="*80)
    print("Galaxy AI Tools - Parameter Extraction Update")
    print("="*80)
    print(f"Database: {db_path}")
    print(f"Size: {db_path.stat().st_size / (1024*1024):.1f} MB")
    print()

    try:
        updated, with_params = update_database_parameters(str(db_path))

        print()
        print("="*80)
        print("✅ UPDATE COMPLETE")
        print("="*80)
        print()
        print("Next steps:")
        print("  1. Verify parameters: python3 scripts/test_tool_schema_simple.py")
        print("  2. Start backend: ./run.sh")
        print("  3. Test endpoint: curl http://localhost:8080/api/tool_search/{tool_id}/schema")
        print("  4. Test frontend parameter editor")

        return 0

    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == '__main__':
    import sys
    sys.exit(main())
