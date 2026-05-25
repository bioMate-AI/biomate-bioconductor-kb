#!/usr/bin/env python3
"""
Convert nf-core subworkflows to Galaxy .ga workflow format.

Hybrid approach:
1. Parse main.nf to extract tools and structure (code)
2. Use LLM to understand data flow and generate Galaxy connections (high accuracy)
3. Map to Galaxy tool IDs from database
"""

import os
import json
import re
import sqlite3
import anthropic
from pathlib import Path
from typing import Dict, List, Optional, Tuple


def parse_nextflow_subworkflow(main_nf_path: Path) -> Dict:
    """Parse main.nf to extract tools and basic structure."""
    with open(main_nf_path) as f:
        content = f.read()

    # Extract includes (tool imports)
    includes = re.findall(r'include\s+{\s+(\w+)(?:\s+as\s+\w+)?\s+}\s+from\s+[\'"]([^\'"]+)[\'"]', content)

    # Extract workflow name
    workflow_match = re.search(r'workflow\s+(\w+)\s+{', content)
    workflow_name = workflow_match.group(1) if workflow_match else "unknown"

    # Extract inputs (take block)
    take_match = re.search(r'take:\s*(.*?)\n\s*main:', content, re.DOTALL)
    inputs = []
    if take_match:
        for line in take_match.group(1).strip().split('\n'):
            match = re.match(r'\s*(\w+)\s*//.*', line)
            if match:
                inputs.append(match.group(1))

    # Extract outputs (emit block)
    emit_match = re.search(r'emit:\s*(.*?)(?:\n}|$)', content, re.DOTALL)
    outputs = []
    if emit_match:
        for line in emit_match.group(1).strip().split('\n'):
            match = re.match(r'\s*(\w+)\s*=', line)
            if match:
                outputs.append(match.group(1))

    # Extract tool calls from main block
    tool_calls = []
    main_match = re.search(r'main:\s*(.*?)\n\s*emit:', content, re.DOTALL)
    if main_match:
        main_block = main_match.group(1)
        # Find tool invocations: TOOL_NAME (...)
        tool_invocations = re.findall(r'(\w+)\s*\(', main_block)
        tool_calls = [t for t in tool_invocations if t.isupper()]

    return {
        'workflow_name': workflow_name,
        'includes': includes,
        'inputs': inputs,
        'outputs': outputs,
        'tool_calls': list(set(tool_calls)),
        'full_content': content
    }


def map_tools_to_galaxy(tool_names: List[str], db_path: str) -> Dict[str, Dict]:
    """Map nf-core tool names to Galaxy tool IDs."""
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    mapping = {}
    for tool_name in tool_names:
        # Try exact match first
        tool_parts = tool_name.lower().split('_')
        search_term = tool_parts[0] if tool_parts else tool_name.lower()

        cursor.execute("""
            SELECT tool_id, name, version, description
            FROM tools
            WHERE LOWER(name) LIKE ? OR LOWER(tool_id) LIKE ?
            ORDER BY
                CASE
                    WHEN LOWER(name) = ? THEN 1
                    WHEN LOWER(tool_id) = ? THEN 2
                    ELSE 3
                END
            LIMIT 1
        """, (f'%{search_term}%', f'%{search_term}%', search_term, search_term))

        result = cursor.fetchone()
        if result:
            mapping[tool_name] = {
                'galaxy_tool_id': result['tool_id'],
                'name': result['name'],
                'version': result['version'],
                'description': result['description']
            }

    conn.close()
    return mapping


def generate_galaxy_workflow_with_llm(
    parsed_workflow: Dict,
    tool_mapping: Dict[str, Dict],
    api_key: str
) -> Optional[Dict]:
    """Use LLM to generate Galaxy workflow with accurate data flow."""

    prompt = f"""You are an expert in Nextflow and Galaxy workflows. Convert this nf-core subworkflow to Galaxy .ga format.

Nextflow Subworkflow: {parsed_workflow['workflow_name']}

Extracted Structure:
- Inputs: {', '.join(parsed_workflow['inputs'])}
- Tools Called: {', '.join(parsed_workflow['tool_calls'])}
- Outputs: {', '.join(parsed_workflow['outputs'])}

Galaxy Tool Mapping:
{json.dumps(tool_mapping, indent=2)}

Full Nextflow Code:
```nextflow
{parsed_workflow['full_content']}
```

Generate a Galaxy workflow in .ga format. Follow these rules:

1. **Data Flow**: Carefully analyze the Nextflow code to understand:
   - Which tool outputs connect to which tool inputs
   - The order of tool execution
   - Any conditional logic (e.g., if/else branches)

2. **Galaxy Format**: Generate JSON with this structure:
{{
  "a_galaxy_workflow": "true",
  "format-version": "0.1",
  "name": "{parsed_workflow['workflow_name']}",
  "annotation": "Converted from nf-core subworkflow",
  "steps": {{
    "0": {{
      "annotation": "Input description",
      "id": 0,
      "input_connections": {{}},
      "inputs": [{{"name": "input_name"}}],
      "name": "Input dataset",
      "type": "data_input",
      "position": {{"left": 10, "top": 10}}
    }},
    "1": {{
      "id": 1,
      "input_connections": {{
        "input_param": {{"id": 0, "output_name": "output"}}
      }},
      "name": "Tool Name",
      "tool_id": "galaxy_tool_id",
      "type": "tool",
      "position": {{"left": 230, "top": 10}}
    }}
  }}
}}

3. **Tool Connections**: For each tool, specify:
   - Which previous step's output connects to which input parameter
   - Use the Galaxy tool IDs from the mapping above

4. **Layout**: Position steps left-to-right based on execution order:
   - Inputs: left=10
   - Each subsequent tool: left += 220
   - Vertical spacing: top = 10 + (step_num * 120)

5. **Conditional Logic**: If there's an if/else (like Salmon vs Kallisto):
   - Create both tool steps
   - Add annotation noting they are alternatives
   - Show both paths in the workflow

Return ONLY valid JSON in Galaxy .ga format. Be precise about input/output connections.
"""

    try:
        client = anthropic.Anthropic(api_key=api_key)
        message = client.messages.create(
            model="claude-haiku-4-5",
            max_tokens=8192,
            temperature=0,
            system=[
                {
                    "type": "text",
                    "text": "You are an expert workflow converter. Generate accurate Galaxy workflows from Nextflow code.",
                    "cache_control": {"type": "ephemeral"}
                }
            ],
            messages=[{"role": "user", "content": prompt}]
        )

        response_text = message.content[0].text

        # Extract JSON
        if "```json" in response_text:
            response_text = response_text.split("```json")[1].split("```")[0]
        elif "```" in response_text:
            response_text = response_text.split("```")[1].split("```")[0]

        workflow = json.loads(response_text.strip())
        return workflow

    except Exception as e:
        print(f"❌ LLM conversion failed: {str(e)[:200]}")
        return None


def convert_subworkflow(
    subworkflow_path: Path,
    db_path: str,
    api_key: str,
    output_dir: Path
) -> bool:
    """Convert a single nf-core subworkflow to Galaxy .ga format."""

    subworkflow_name = subworkflow_path.name
    main_nf = subworkflow_path / "main.nf"

    if not main_nf.exists():
        print(f"⚠️  No main.nf in {subworkflow_name}")
        return False

    print(f"\n{'='*80}")
    print(f"Converting: {subworkflow_name}")
    print('='*80)

    # Step 1: Parse Nextflow code
    print("  📝 Parsing Nextflow structure...")
    parsed = parse_nextflow_subworkflow(main_nf)
    print(f"     - Workflow: {parsed['workflow_name']}")
    print(f"     - Tools: {', '.join(parsed['tool_calls'])}")

    # Step 2: Map to Galaxy tools
    print("  🔍 Mapping to Galaxy tools...")
    tool_mapping = map_tools_to_galaxy(parsed['tool_calls'], db_path)
    print(f"     - Mapped: {len(tool_mapping)}/{len(parsed['tool_calls'])} tools")

    # Step 3: Generate Galaxy workflow with LLM
    print("  🤖 Generating Galaxy workflow with LLM...")
    galaxy_workflow = generate_galaxy_workflow_with_llm(parsed, tool_mapping, api_key)

    if not galaxy_workflow:
        return False

    # Step 4: Save .ga file
    output_file = output_dir / f"{subworkflow_name}.ga"
    with open(output_file, 'w') as f:
        json.dump(galaxy_workflow, f, indent=2)

    print(f"  ✅ Saved: {output_file}")
    return True


def main():
    import argparse

    parser = argparse.ArgumentParser(description='Convert nf-core subworkflows to Galaxy .ga format')
    parser.add_argument('--subworkflows', default='/opt/biomate/backend/nf-core-modules/subworkflows/nf-core',
                       help='Path to nf-core subworkflows directory')
    parser.add_argument('--db', default='/opt/biomate/backend/database/galaxy_ai_tools.db',
                       help='Path to Galaxy tools database')
    parser.add_argument('--output', default='/opt/biomate/backend/galaxy_workflows',
                       help='Output directory for .ga files')
    parser.add_argument('--limit', type=int, help='Limit number of subworkflows to convert')

    args = parser.parse_args()

    api_key = os.environ.get('ANTHROPIC_API_KEY')
    if not api_key:
        print("❌ Error: ANTHROPIC_API_KEY not set")
        return 1

    # Create output directory
    output_dir = Path(args.output)
    output_dir.mkdir(exist_ok=True, parents=True)

    print("=" * 80)
    print("nf-core → Galaxy Workflow Converter")
    print("=" * 80)
    print(f"Source: {args.subworkflows}")
    print(f"Database: {args.db}")
    print(f"Output: {output_dir}")
    print()

    # Find all subworkflows
    subworkflows_path = Path(args.subworkflows)
    subworkflows = [d for d in subworkflows_path.iterdir() if d.is_dir() and not d.name.startswith('.')]

    if args.limit:
        subworkflows = subworkflows[:args.limit]

    print(f"Found {len(subworkflows)} subworkflows to convert")
    print()

    # Convert each subworkflow
    success_count = 0
    fail_count = 0

    for subworkflow in subworkflows:
        if convert_subworkflow(subworkflow, args.db, api_key, output_dir):
            success_count += 1
        else:
            fail_count += 1

    print()
    print("=" * 80)
    print("✅ Conversion Complete")
    print("=" * 80)
    print(f"   Successful: {success_count}")
    print(f"   Failed: {fail_count}")
    print(f"   Output: {output_dir}")

    return 0


if __name__ == '__main__':
    import sys
    sys.exit(main())
