#!/usr/bin/env python3
"""
Fix missing definitions in Nextflow workflows.
Adds missing constants, imports, and simple function definitions.
"""

import os
import re
from pathlib import Path

SUBWORKFLOWS_DIR = Path('subworkflows')

# Common fixes for missing definitions
FIXES = {
    '_MAX_DOC_CHARS': 'MAX_DOC_CHARS = 50000  # Maximum documentation characters',
    'logger': 'import logging\nlogger = logging.getLogger(__name__)',
    'parse_hpo_obo': '''def parse_hpo_obo(obo_file):
    """Parse HPO OBO file."""
    return {}  # Placeholder - needs full implementation''',
}


def fix_workflow(wf_path):
    """Fix missing definitions in a workflow."""
    main_nf = wf_path / 'main.nf'
    if not main_nf.exists():
        return None, "No main.nf"

    content = main_nf.read_text()
    original_content = content
    fixes_applied = []

    # Check for common missing definitions and add them
    for pattern, fix in FIXES.items():
        # Check if pattern is used but not defined
        if pattern in content:
            # Check if it's already defined
            if f'{pattern} =' not in content and f'def {pattern}' not in content and f'import {pattern}' not in content and f'MAX_DOC_CHARS' not in content:
                # Add fix after imports section
                if 'import json' in content:
                    content = content.replace(
                        'import json\nimport os',
                        f'import json\nimport os\n\n{fix}'
                    )
                    fixes_applied.append(pattern)

    # Add logger if used but not defined
    if 'logger.' in content and 'logging.getLogger' not in content:
        content = content.replace(
            'import json\nimport os',
            'import json\nimport os\nimport logging\nlogger = logging.getLogger(__name__)'
        )
        fixes_applied.append('logger')

    # Fix "name 'ImageRegistrationTool' is not defined" by stubbing the class
    if 'ImageRegistrationTool' in content and 'class ImageRegistrationTool' not in content:
        stub = '''
class ImageRegistrationTool:
    """Stub for ImageRegistrationTool - requires SimpleITK."""
    def __init__(self):
        raise NotImplementedError("ImageRegistrationTool requires SimpleITK and full biomni installation")
    def load_image(self, path):
        pass
    def calculate_similarity_metrics(self, img1, img2):
        return {"error": "ImageRegistrationTool not available"}
'''
        content = content.replace(
            'def auto_convert(val):',
            stub + '\n\ndef auto_convert(val):'
        )
        fixes_applied.append('ImageRegistrationTool stub')

    # Fix "name 'SegmentationTool' is not defined"
    if 'SegmentationTool' in content and 'class SegmentationTool' not in content:
        stub = '''
class SegmentationTool:
    """Stub for SegmentationTool - requires nnU-Net."""
    def __init__(self):
        raise NotImplementedError("SegmentationTool requires nnU-Net and full biomni installation")
'''
        content = content.replace(
            'def auto_convert(val):',
            stub + '\n\ndef auto_convert(val):'
        )
        fixes_applied.append('SegmentationTool stub')

    # Fix MutableMapping import for Python 3.10+
    if "collections.MutableMapping" in content or "'MutableMapping'" in content:
        content = content.replace(
            'import json\nimport os',
            'import json\nimport os\nfrom collections.abc import MutableMapping'
        )
        content = content.replace('collections.MutableMapping', 'MutableMapping')
        fixes_applied.append('MutableMapping import')

    if content != original_content:
        main_nf.write_text(content)
        return True, f"Applied fixes: {', '.join(fixes_applied)}"

    return False, "No fixes needed"


def main():
    fixed = []
    skipped = []
    errors = []

    for domain in sorted(os.listdir(SUBWORKFLOWS_DIR)):
        domain_path = SUBWORKFLOWS_DIR / domain
        if not domain_path.is_dir():
            continue

        for wf in sorted(os.listdir(domain_path)):
            wf_path = domain_path / wf
            if not wf_path.is_dir():
                continue

            wf_key = f"{domain}/{wf}"
            result, msg = fix_workflow(wf_path)

            if result is None:
                errors.append(f"{wf_key}: {msg}")
            elif result:
                fixed.append(f"{wf_key}: {msg}")
                print(f"✓ {wf_key}: {msg}")
            else:
                skipped.append(wf_key)

    print(f"\n{'='*60}")
    print(f"Fixed: {len(fixed)}")
    print(f"Skipped: {len(skipped)}")
    print(f"Errors: {len(errors)}")


if __name__ == '__main__':
    main()
