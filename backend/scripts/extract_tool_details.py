#!/usr/bin/env python3
"""
Extract detailed tool information for chemical/biological database tools
"""
import sqlite3
import json
import sys

def extract_tool_details(db_path, databases_to_check):
    """Extract full details for tools matching database names"""

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    tool_details = {}

    for db_name in databases_to_check:
        cursor.execute("""
            SELECT id, name, category, description, inputs, outputs, parameters, help_text,
                   version, requirements, repo_owner, repo_name
            FROM tools
            WHERE name LIKE ? OR description LIKE ? OR id LIKE ?
        """, (f'%{db_name}%', f'%{db_name}%', f'%{db_name}%'))

        results = cursor.fetchall()

        for row in results:
            tool_id, name, category, desc, inputs_str, outputs_str, params_str, help_str, \
            version, reqs_str, repo_owner, repo_name = row

            # Parse JSON fields
            try:
                inputs = json.loads(inputs_str) if inputs_str else []
            except:
                inputs = []

            try:
                outputs = json.loads(outputs_str) if outputs_str else []
            except:
                outputs = []

            try:
                parameters = json.loads(params_str) if params_str else []
            except:
                parameters = []

            try:
                help_text = json.loads(help_str) if help_str else {}
            except:
                help_text = {}

            try:
                requirements = json.loads(reqs_str) if reqs_str else []
            except:
                requirements = []

            tool_details[tool_id] = {
                'id': tool_id,
                'name': name,
                'category': category,
                'description': desc,
                'version': version,
                'repo_owner': repo_owner,
                'repo_name': repo_name,
                'inputs': inputs,
                'outputs': outputs,
                'parameters': parameters,
                'help_text': help_text,
                'requirements': requirements
            }

    conn.close()
    return tool_details

if __name__ == '__main__':
    databases = [
        'PubChem', 'ChEMBL', 'KEGG', 'UniProt', 'Reactome', 'HMDB',
        'DrugBank', 'MetaboAnalyst', 'Golm', 'LIPID'
    ]

    db_path = '/Users/jingqiwang/biomate/backend/galaxy_ai_tools.db'

    print("Extracting tool details...")
    tools = extract_tool_details(db_path, databases)

    print(f"\nExtracted {len(tools)} tools")

    # Write to JSON file
    output_file = '/Users/jingqiwang/biomate/backend/data_tools_detailed.json'
    with open(output_file, 'w') as f:
        json.dump(tools, f, indent=2)

    print(f"Saved to: {output_file}")
