#!/usr/bin/env python3
"""
Fix Quality Issues in Existing Generated nfcore Tools

Issues to fix:
1. Broken container lines (Nextflow syntax)
2. Improve descriptions from nf-core meta.yml
3. Add proper biocontainer references
4. Better help text
"""

import re
import yaml
from pathlib import Path
from typing import Dict, Optional
import xml.etree.ElementTree as ET


class ToolQualityFixer:
    """Fix quality issues in generated Galaxy tool XMLs."""

    def __init__(self, nfcore_repo_path: str = "/tmp/nfcore-modules"):
        self.nfcore_repo = Path(nfcore_repo_path)
        self.modules_dir = self.nfcore_repo / "modules" / "nf-core"

    def find_nfcore_module(self, tool_name: str) -> Optional[Path]:
        """Find nf-core module directory."""
        # Handle both formats: "tool_name" and "category/tool_name"
        if '/' in tool_name:
            module_path = self.modules_dir / tool_name
        else:
            # Try common patterns
            for module_dir in self.modules_dir.glob(f"*/{tool_name}"):
                if (module_dir / "main.nf").exists():
                    return module_dir
            # Try direct
            module_path = self.modules_dir / tool_name

        if module_path.exists() and (module_path / "main.nf").exists():
            return module_path
        return None

    def extract_container_from_nf(self, main_nf_path: Path) -> Optional[str]:
        """Extract proper biocontainer reference from main.nf."""
        try:
            with open(main_nf_path) as f:
                content = f.read()

            # Look for biocontainers reference
            match = re.search(r"'biocontainers/([^:]+):([^']+)'", content)
            if match:
                tool = match.group(1)
                version = match.group(2)
                return f"quay.io/biocontainers/{tool}:{version}"

            # Look for depot.galaxyproject.org
            match = re.search(r"'depot\.galaxyproject\.org/([^']+)'", content)
            if match:
                return f"https://depot.galaxyproject.org/{match.group(1)}"

        except Exception as e:
            print(f"    ⚠️  Error extracting container: {e}")
        return None

    def get_nfcore_metadata(self, module_path: Path) -> Dict:
        """Extract metadata from nf-core meta.yml."""
        meta_file = module_path / "meta.yml"
        if not meta_file.exists():
            return {}

        try:
            with open(meta_file) as f:
                meta = yaml.safe_load(f)

            # Extract relevant info
            result = {
                'name': meta.get('name', ''),
                'description': meta.get('description', ''),
                'keywords': meta.get('keywords', []),
            }

            # Extract tool info
            tools = meta.get('tools', [])
            if tools:
                if isinstance(tools, list):
                    tool_info = tools[0] if isinstance(tools[0], dict) else {}
                elif isinstance(tools, dict):
                    tool_info = list(tools.values())[0] if tools else {}
                else:
                    tool_info = {}

                result['homepage'] = tool_info.get('homepage', '')
                result['documentation'] = tool_info.get('documentation', '')
                result['tool_dev_url'] = tool_info.get('tool_dev_url', '')
                result['licence'] = tool_info.get('licence', [])

            return result
        except Exception as e:
            print(f"    ⚠️  Error parsing meta.yml: {e}")
            return {}

    def fix_xml(self, xml_path: Path) -> bool:
        """Fix quality issues in a single XML file."""
        try:
            # Parse XML
            tree = ET.parse(xml_path)
            root = tree.getroot()

            # Extract tool name from ID
            tool_id = root.get('id', '')
            tool_name = tool_id.replace('nfcore_', '').replace('_', '/')

            # Find nf-core module
            module_path = self.find_nfcore_module(tool_name)
            if not module_path:
                # Try without slash
                tool_name = tool_id.replace('nfcore_', '')
                module_path = self.find_nfcore_module(tool_name)

            fixed_anything = False

            # Get nf-core metadata
            metadata = {}
            container_ref = None
            if module_path:
                metadata = self.get_nfcore_metadata(module_path)
                container_ref = self.extract_container_from_nf(module_path / "main.nf")

            # Fix requirements/container
            reqs = root.find('requirements')
            if reqs is not None:
                for container in reqs.findall('container'):
                    old_text = container.text or ''
                    # Check if broken (contains Nextflow syntax)
                    if '${' in old_text or 'workflow.' in old_text or not old_text.strip():
                        if container_ref:
                            container.text = container_ref
                            container.set('type', 'docker')
                            fixed_anything = True
                        else:
                            # Use generic container
                            base_tool = tool_name.split('/')[0] if '/' in tool_name else tool_name
                            container.text = f"quay.io/biocontainers/{base_tool}:latest"
                            fixed_anything = True

            # Improve description if we have better metadata
            if metadata.get('description'):
                desc = root.find('description')
                if desc is not None:
                    old_desc = desc.text or ''
                    new_desc = metadata['description']
                    if len(new_desc) > len(old_desc):
                        desc.text = new_desc
                        fixed_anything = True

            # Enhance help section
            if metadata:
                help_elem = root.find('help')
                if help_elem is not None:
                    help_text = help_elem.text or ''

                    # Add homepage and documentation if not present
                    additions = []
                    if metadata.get('homepage') and 'homepage' not in help_text.lower():
                        additions.append(f"Homepage: {metadata['homepage']}")
                    if metadata.get('documentation') and 'documentation' not in help_text.lower():
                        additions.append(f"Documentation: {metadata['documentation']}")

                    if additions:
                        # Add before closing CDATA
                        if ']]>' in help_text:
                            insert_pos = help_text.rfind(']]>')
                            addition_text = '\n\n**Links:**\n' + '\n'.join(f'- {a}' for a in additions) + '\n'
                            help_text = help_text[:insert_pos] + addition_text + help_text[insert_pos:]
                            help_elem.text = help_text
                            fixed_anything = True

            # Save if we fixed anything
            if fixed_anything:
                # Write with proper formatting
                tree.write(xml_path, encoding='utf-8', xml_declaration=True)
                return True

            return False

        except Exception as e:
            print(f"    ❌ Error processing {xml_path.name}: {e}")
            return False


def main():
    print("=" * 80)
    print("FIXING QUALITY ISSUES IN EXISTING NFCORE TOOLS")
    print("=" * 80)

    fixer = ToolQualityFixer()

    # Find all nfcore tool directories
    nfcore_dirs = [
        'backend/tools/nfcore_generated',
        'backend/tools/nfcore_general',
        'backend/tools/nfcore_lcms',
    ]

    total_tools = 0
    fixed_tools = 0
    failed_tools = []

    for dir_name in nfcore_dirs:
        dir_path = Path(dir_name)
        if not dir_path.exists():
            print(f"\n⚠️  Directory not found: {dir_name}")
            continue

        print(f"\n📁 Processing {dir_name}...")
        xml_files = list(dir_path.glob('*.xml'))
        print(f"   Found {len(xml_files)} XML files")

        for i, xml_file in enumerate(xml_files, 1):
            total_tools += 1
            print(f"   [{i}/{len(xml_files)}] {xml_file.name}...", end=" ")

            if fixer.fix_xml(xml_file):
                fixed_tools += 1
                print("✓ Fixed")
            else:
                print("○ No changes needed")

    # Summary
    print("\n" + "=" * 80)
    print("SUMMARY")
    print("=" * 80)
    print(f"Total tools processed: {total_tools}")
    print(f"Tools fixed: {fixed_tools}")
    print(f"Tools unchanged: {total_tools - fixed_tools}")

    if failed_tools:
        print(f"\nFailed tools ({len(failed_tools)}):")
        for tool in failed_tools[:10]:
            print(f"  - {tool}")

    print("\n" + "=" * 80)
    print("✅ QUALITY FIX COMPLETE")
    print("=" * 80)


if __name__ == "__main__":
    main()
