#!/usr/bin/env python3
"""Create tool manifest for Biomni Galaxy tools."""

import json
import os
from pathlib import Path

BIOMNI_HOME = os.environ.get('BIOMNI_HOME', '/opt/biomni')
GALAXY_TOOLS = Path(BIOMNI_HOME) / 'galaxy_tools'

domains = [
    'biochemistry', 'bioengineering', 'biophysics', 'cancer_biology', 'cell_biology',
    'database', 'genetics', 'genomics', 'glycoengineering', 'immunology',
    'lab_automation', 'literature', 'microbiology', 'molecular_biology', 'pathology',
    'pharmacology', 'physiology', 'protocols', 'support_tools', 'synthetic_biology', 'systems_biology'
]

manifest = {
    'version': '1.0.0',
    'description': 'Biomni Galaxy Tools - Bioinformatics tools organized by domain',
    'domains': {}
}

for domain in domains:
    domain_dir = GALAXY_TOOLS / domain
    tools = []
    if domain_dir.exists():
        for py_file in domain_dir.glob('*.py'):
            tools.append({
                'name': py_file.stem,
                'path': str(py_file),
                'xml': str(py_file.with_suffix('.xml'))
            })

    manifest['domains'][domain] = {
        'tools': tools,
        'count': len(tools),
        'status': 'available'
    }

manifest_path = Path(BIOMNI_HOME) / 'tool_manifest.json'
with open(manifest_path, 'w') as f:
    json.dump(manifest, f, indent=2)

print(f'Tool manifest created at {manifest_path}')
print(f'Total domains: {len(domains)}')
print(f'Total tools: {sum(d["count"] for d in manifest["domains"].values())}')
