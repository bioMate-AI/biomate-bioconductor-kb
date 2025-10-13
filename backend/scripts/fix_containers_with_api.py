#!/usr/bin/env python3
"""
Fix Container References Using Biocontainers API

Approach:
1. Extract tool and version from environment.yml
2. Query biocontainers API to find real container with hash
3. Update container references in tool XML
"""

import re
import requests
import time
from pathlib import Path
import xml.etree.ElementTree as ET
import yaml
from typing import Optional, Dict


class BiocontainerAPIFixer:
    """Fix containers using biocontainers API."""

    def __init__(self, nfcore_repo: str = "/tmp/nfcore-modules"):
        self.nfcore_repo = Path(nfcore_repo)
        self.modules_dir = self.nfcore_repo / "modules" / "nf-core"
        self.cache = {}  # Cache API results
        self.stats = {
            "total": 0,
            "fixed_from_api": 0,
            "fixed_from_env": 0,
            "kept_latest": 0,
            "failed": 0
        }

    def query_biocontainers_api(self, package_name: str, version: str = None) -> Optional[str]:
        """
        Query biocontainers API for container.

        API: https://api.biocontainers.pro/ga4gh/trs/v2/tools/{tool}/versions
        """
        cache_key = f"{package_name}:{version}" if version else package_name
        if cache_key in self.cache:
            return self.cache[cache_key]

        try:
            # Try direct package lookup
            url = f"https://api.biocontainers.pro/ga4gh/trs/v2/tools/{package_name}/versions"
            response = requests.get(url, timeout=10)

            if response.status_code == 200:
                versions = response.json()

                if version:
                    # Find specific version
                    for v in versions:
                        v_name = v.get('name', '')
                        if version in v_name:
                            # Extract container path
                            images = v.get('images', [])
                            for img in images:
                                img_name = img.get('image_name', '')
                                if 'biocontainers' in img_name:
                                    # Format: quay.io/biocontainers/tool:version--hash
                                    container = img_name.replace('quay.io/', '')
                                    self.cache[cache_key] = container
                                    return container
                else:
                    # Get latest
                    if versions:
                        v = versions[0]
                        images = v.get('images', [])
                        for img in images:
                            img_name = img.get('image_name', '')
                            if 'biocontainers' in img_name:
                                container = img_name.replace('quay.io/', '')
                                self.cache[cache_key] = container
                                return container

            # Fallback: construct from version
            if version:
                container = f"biocontainers/{package_name}:{version}"
                self.cache[cache_key] = container
                return container

        except Exception as e:
            print(f"    API error for {package_name}: {e}")

        self.cache[cache_key] = None
        return None

    def extract_tool_from_environment(self, module_path: Path) -> Optional[Dict]:
        """Extract main tool and version from environment.yml."""
        env_file = module_path / "environment.yml"

        if not env_file.exists():
            return None

        try:
            with open(env_file, 'r') as f:
                env = yaml.safe_load(f)

            dependencies = env.get('dependencies', [])

            # Find the main tool (usually first bioconda package)
            for dep in dependencies:
                if isinstance(dep, str) and 'bioconda::' in dep:
                    # Format: bioconda::bcftools=1.22
                    parts = dep.replace('bioconda::', '').split('=')
                    if len(parts) == 2:
                        tool_name = parts[0]
                        version = parts[1]
                        return {
                            "name": tool_name,
                            "version": version
                        }
                    elif len(parts) == 1:
                        return {"name": parts[0], "version": None}

        except Exception as e:
            print(f"    Error reading environment.yml: {e}")

        return None

    def fix_tool_container(self, tool_path: Path) -> bool:
        """Fix container reference in tool."""
        self.stats["total"] += 1

        try:
            tree = ET.parse(tool_path)
            root = tree.getroot()

            tool_id = root.get('id', '')
            module_name = tool_id.replace("nfcore_", "")

            # Find container element
            reqs = root.find('requirements')
            if reqs is None:
                return False

            container_elem = reqs.find('container')
            if container_elem is None:
                return False

            current_container = (container_elem.text or '').strip()

            # Skip if already has proper version (not :latest)
            if ':latest' not in current_container and current_container.count('/') == 1:
                return True

            # Get module path
            module_path = self.modules_dir / module_name.replace('/', '/')
            if not module_path.exists():
                # Try without subdirectory
                parts = module_name.split('/')
                if len(parts) > 1:
                    module_path = self.modules_dir / parts[0]

            if not module_path.exists():
                self.stats["kept_latest"] += 1
                return False

            # Extract from environment.yml
            tool_info = self.extract_tool_from_environment(module_path)

            if tool_info:
                # Query API for container
                container = self.query_biocontainers_api(
                    tool_info['name'],
                    tool_info['version']
                )

                if container:
                    container_elem.text = container

                    # Update help section
                    help_elem = root.find('help')
                    if help_elem is not None and help_elem.text:
                        help_text = help_elem.text
                        help_text = re.sub(
                            r'- Container: .*',
                            f'- Container: {container}',
                            help_text
                        )
                        help_elem.text = help_text

                    # Save
                    tree.write(tool_path, encoding='unicode', xml_declaration=True)

                    if ':' in container and '--' in container:
                        self.stats["fixed_from_api"] += 1
                    else:
                        self.stats["fixed_from_env"] += 1

                    if self.stats["fixed_from_api"] % 50 == 0:
                        print(f"  Fixed {self.stats['fixed_from_api']} tools from API...")

                    return True

            self.stats["kept_latest"] += 1
            return False

        except Exception as e:
            print(f"  Error fixing {tool_path.name}: {e}")
            self.stats["failed"] += 1
            return False

    def fix_all_tools(self, tools_dir: Path):
        """Fix all tools."""
        print("=" * 80)
        print("FIXING CONTAINERS USING BIOCONTAINERS API")
        print("=" * 80)
        print()

        xml_files = sorted(list(tools_dir.glob("*.xml")))
        print(f"Found {len(xml_files)} tools\n")

        for i, tool_file in enumerate(xml_files, 1):
            if i % 100 == 0:
                print(f"Processing {i}/{len(xml_files)}...")

            self.fix_tool_container(tool_file)

            # Rate limit API calls
            if i % 10 == 0:
                time.sleep(0.5)

        self._print_report()

    def _print_report(self):
        """Print report."""
        print()
        print("=" * 80)
        print("FIX REPORT")
        print("=" * 80)
        print(f"Total tools:              {self.stats['total']}")
        print(f"Fixed from API:           {self.stats['fixed_from_api']}")
        print(f"Fixed from env only:      {self.stats['fixed_from_env']}")
        print(f"Kept :latest (no fix):    {self.stats['kept_latest']}")
        print(f"Failed:                   {self.stats['failed']}")

        fixed_total = self.stats['fixed_from_api'] + self.stats['fixed_from_env']
        if self.stats['total'] > 0:
            success_rate = (fixed_total / self.stats['total']) * 100
            print()
            print(f"Success rate: {success_rate:.1f}%")
            print("=" * 80)

            return success_rate >= 50


def main():
    """Main."""
    tools_dir = Path(__file__).parent.parent / "tools" / "nfcore_generated"

    fixer = BiocontainerAPIFixer()
    fixer.fix_all_tools(tools_dir)

    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())
