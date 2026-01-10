#!/usr/bin/env python3
"""
Extract docstrings and parameter information from Biomni functions.
This enriches tool/workflow descriptions with comprehensive documentation.
"""

import ast
import json
import re
import sqlite3
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass
class FunctionDoc:
    """Documentation extracted from a function."""
    name: str
    domain: str
    docstring: str = ""
    summary: str = ""  # First line of docstring
    parameters: list = field(default_factory=list)
    returns: str = ""
    examples: list = field(default_factory=list)
    notes: str = ""


def parse_docstring(docstring: str) -> dict:
    """Parse numpy/sphinx style docstring into components."""
    if not docstring:
        return {}

    result = {
        'summary': '',
        'description': '',
        'parameters': [],
        'returns': '',
        'examples': [],
        'notes': '',
    }

    lines = docstring.strip().split('\n')

    # First line is summary
    if lines:
        result['summary'] = lines[0].strip()

    # Parse sections
    current_section = 'description'
    current_content = []

    section_markers = {
        'Parameters': 'parameters',
        'Args': 'parameters',
        'Arguments': 'parameters',
        'Returns': 'returns',
        'Return': 'returns',
        'Examples': 'examples',
        'Example': 'examples',
        'Notes': 'notes',
        'Note': 'notes',
        'Raises': 'raises',
    }

    for i, line in enumerate(lines[1:], 1):
        stripped = line.strip()

        # Check for section header
        for marker, section in section_markers.items():
            if stripped.startswith(marker) and (stripped.endswith(':') or stripped == marker or
                                                  (i + 1 < len(lines) and lines[i + 1].strip().startswith('---'))):
                if current_content:
                    if current_section == 'description':
                        result['description'] = '\n'.join(current_content).strip()
                    elif current_section == 'parameters':
                        result['parameters'] = parse_parameters('\n'.join(current_content))
                    elif current_section in result:
                        result[current_section] = '\n'.join(current_content).strip()
                current_section = section
                current_content = []
                break
        else:
            # Skip separator lines
            if not stripped.startswith('---'):
                current_content.append(line)

    # Handle last section
    if current_content:
        if current_section == 'description':
            result['description'] = '\n'.join(current_content).strip()
        elif current_section == 'parameters':
            result['parameters'] = parse_parameters('\n'.join(current_content))
        elif current_section in result:
            result[current_section] = '\n'.join(current_content).strip()

    return result


def parse_parameters(params_text: str) -> list:
    """Parse parameters section into list of dicts."""
    params = []
    current_param = None
    current_desc = []

    for line in params_text.split('\n'):
        # Match parameter definition: "param_name : type" or "param_name (type)"
        match = re.match(r'^[\s-]*(\w+)\s*[:\(]\s*(.+?)[\)]*\s*$', line)
        if match and not line.startswith('    '):
            if current_param:
                params.append({
                    'name': current_param['name'],
                    'type': current_param['type'],
                    'description': ' '.join(current_desc).strip()
                })
            current_param = {'name': match.group(1), 'type': match.group(2).strip()}
            current_desc = []
        elif current_param and line.strip():
            current_desc.append(line.strip())

    if current_param:
        params.append({
            'name': current_param['name'],
            'type': current_param['type'],
            'description': ' '.join(current_desc).strip()
        })

    return params


class DocstringExtractor(ast.NodeVisitor):
    """Extract docstrings and signatures from Python functions."""

    def __init__(self, domain: str):
        self.domain = domain
        self.functions = []

    def visit_FunctionDef(self, node):
        # Skip private/helper functions
        if node.name.startswith('_'):
            self.generic_visit(node)
            return

        # Get docstring
        docstring = ast.get_docstring(node) or ""
        parsed = parse_docstring(docstring)

        # Get parameters from function signature
        sig_params = []
        for arg in node.args.args:
            param_name = arg.arg
            param_type = ""
            if arg.annotation:
                try:
                    param_type = ast.unparse(arg.annotation)
                except:
                    param_type = str(arg.annotation)
            sig_params.append({'name': param_name, 'type': param_type})

        # Merge signature params with docstring params
        params = []
        doc_params = {p['name']: p for p in parsed.get('parameters', [])}
        for sp in sig_params:
            if sp['name'] in doc_params:
                params.append({
                    'name': sp['name'],
                    'type': sp['type'] or doc_params[sp['name']].get('type', ''),
                    'description': doc_params[sp['name']].get('description', '')
                })
            else:
                params.append(sp)

        func_doc = FunctionDoc(
            name=node.name,
            domain=self.domain,
            docstring=docstring,
            summary=parsed.get('summary', ''),
            parameters=params,
            returns=parsed.get('returns', ''),
            examples=parsed.get('examples', []),
            notes=parsed.get('notes', '')
        )

        self.functions.append(func_doc)
        self.generic_visit(node)


def extract_all_docstrings(tool_dir: Path) -> dict[str, list[FunctionDoc]]:
    """Extract docstrings from all Biomni tool files."""
    skip_files = {'__init__.py', 'tool_registry.py', 'support_tools.py'}
    all_docs = {}

    for py_file in sorted(tool_dir.glob("*.py")):
        if py_file.name in skip_files:
            continue

        domain = py_file.stem
        try:
            with open(py_file, 'r') as f:
                source = f.read()
            tree = ast.parse(source)
            extractor = DocstringExtractor(domain)
            extractor.visit(tree)
            all_docs[domain] = extractor.functions
        except Exception as e:
            print(f"Error parsing {py_file}: {e}")

    return all_docs


def update_database_with_docstrings(db_path: Path, docs: dict[str, list[FunctionDoc]]):
    """Update database with enriched descriptions."""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Add new columns if they don't exist
    try:
        cursor.execute("ALTER TABLE biomni_workflows ADD COLUMN docstring TEXT")
    except:
        pass
    try:
        cursor.execute("ALTER TABLE biomni_workflows ADD COLUMN parameters TEXT")
    except:
        pass
    try:
        cursor.execute("ALTER TABLE biomni_workflows ADD COLUMN returns TEXT")
    except:
        pass

    updated = 0
    for domain, funcs in docs.items():
        for func in funcs:
            workflow_id = f"biomni/{domain}/{func.name}"

            # Update description with summary
            description = func.summary or func.docstring[:200] if func.docstring else ""

            cursor.execute("""
                UPDATE biomni_workflows
                SET description = ?,
                    docstring = ?,
                    parameters = ?,
                    returns = ?
                WHERE workflow_id = ?
            """, (
                description,
                func.docstring,
                json.dumps(func.parameters),
                func.returns,
                workflow_id
            ))

            if cursor.rowcount > 0:
                updated += 1

    conn.commit()
    conn.close()
    return updated


def generate_docstring_report(docs: dict[str, list[FunctionDoc]]) -> str:
    """Generate a report of all extracted docstrings."""
    report = []
    report.append("# Biomni Function Documentation Report\n")

    total_funcs = 0
    funcs_with_docstring = 0
    funcs_with_params = 0

    for domain in sorted(docs.keys()):
        funcs = docs[domain]
        report.append(f"\n## {domain.title()} ({len(funcs)} functions)\n")

        for func in funcs:
            total_funcs += 1
            has_docstring = bool(func.docstring)
            has_params = bool(func.parameters)

            if has_docstring:
                funcs_with_docstring += 1
            if has_params:
                funcs_with_params += 1

            report.append(f"\n### `{func.name}`\n")

            if func.summary:
                report.append(f"**Summary**: {func.summary}\n")

            if func.parameters:
                report.append("\n**Parameters**:\n")
                for p in func.parameters:
                    type_str = f" ({p['type']})" if p.get('type') else ""
                    desc_str = f": {p['description']}" if p.get('description') else ""
                    report.append(f"- `{p['name']}`{type_str}{desc_str}\n")

            if func.returns:
                report.append(f"\n**Returns**: {func.returns}\n")

            # Documentation quality indicator
            quality = "Complete" if has_docstring and has_params else "Partial" if has_docstring else "Missing"
            report.append(f"\n*Documentation quality*: {quality}\n")

    # Summary statistics
    summary = f"""
---

## Summary Statistics

| Metric | Count | Percentage |
|--------|-------|------------|
| Total functions | {total_funcs} | 100% |
| With docstrings | {funcs_with_docstring} | {100*funcs_with_docstring/total_funcs:.1f}% |
| With parameters | {funcs_with_params} | {100*funcs_with_params/total_funcs:.1f}% |
| Missing docs | {total_funcs - funcs_with_docstring} | {100*(total_funcs-funcs_with_docstring)/total_funcs:.1f}% |

"""
    report.insert(1, summary)

    return ''.join(report)


def main():
    tool_dir = Path("/home/yzhang/biomate/Biomni/biomni/tool")
    db_path = Path("/home/yzhang/biomate/Biomni/biomni_tools_v2.db")
    output_dir = Path("/home/yzhang/biomate/Biomni/biomni_galaxy")

    print("=" * 80)
    print("BIOMNI DOCSTRING EXTRACTION")
    print("=" * 80)

    # Extract all docstrings
    print("\nExtracting docstrings from Biomni code...")
    docs = extract_all_docstrings(tool_dir)

    total_funcs = sum(len(funcs) for funcs in docs.values())
    print(f"Extracted documentation for {total_funcs} functions across {len(docs)} domains")

    # Count documentation quality
    with_docs = sum(1 for funcs in docs.values() for f in funcs if f.docstring)
    with_params = sum(1 for funcs in docs.values() for f in funcs if f.parameters)

    print(f"  - Functions with docstrings: {with_docs} ({100*with_docs/total_funcs:.1f}%)")
    print(f"  - Functions with parameters: {with_params} ({100*with_params/total_funcs:.1f}%)")

    # Update database
    if db_path.exists():
        print(f"\nUpdating database {db_path}...")
        updated = update_database_with_docstrings(db_path, docs)
        print(f"  - Updated {updated} workflow records")

    # Generate report
    print("\nGenerating documentation report...")
    report = generate_docstring_report(docs)

    report_path = output_dir / "BIOMNI_FUNCTION_DOCUMENTATION.md"
    with open(report_path, 'w') as f:
        f.write(report)
    print(f"  - Report saved to: {report_path}")

    # Save as JSON for programmatic access
    json_data = {}
    for domain, funcs in docs.items():
        json_data[domain] = [
            {
                'name': f.name,
                'summary': f.summary,
                'docstring': f.docstring,
                'parameters': f.parameters,
                'returns': f.returns,
            }
            for f in funcs
        ]

    json_path = output_dir / "biomni_function_docs.json"
    with open(json_path, 'w') as f:
        json.dump(json_data, f, indent=2)
    print(f"  - JSON saved to: {json_path}")

    print("\n" + "=" * 80)
    print("EXTRACTION COMPLETE")
    print("=" * 80)


if __name__ == "__main__":
    main()
