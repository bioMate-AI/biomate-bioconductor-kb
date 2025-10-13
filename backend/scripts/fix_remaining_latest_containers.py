#!/usr/bin/env python3
"""
Fix remaining 132 tools that have :latest containers with wrong paths.
These tools have containers like biocontainers/tool/subtool:latest
Should be biocontainers/tool:version
"""

import re
from pathlib import Path
import yaml
from typing import Optional, Dict

class LatestContainerFixer:
    def __init__(self, tools_dir: str = "tools/nfcore_generated",
                 modules_dir: str = "/tmp/nfcore-modules/modules/nf-core"):
        self.tools_dir = Path(tools_dir)
        self.modules_dir = Path(modules_dir)
        self.fixed_count = 0
        self.failed_count = 0

    def extract_tool_from_environment(self, module_path: Path) -> Optional[Dict]:
        """Extract main tool and version from environment.yml."""
        env_file = module_path / "environment.yml"
        if not env_file.exists():
            return None

        try:
            with open(env_file) as f:
                env_data = yaml.safe_load(f)

            if not env_data or 'dependencies' not in env_data:
                return None

            # Find bioconda packages (primary tools)
            for dep in env_data['dependencies']:
                if isinstance(dep, str) and 'bioconda::' in dep:
                    # Format: bioconda::tool=version
                    parts = dep.split('::')[1].split('=')
                    if len(parts) == 2:
                        return {"name": parts[0], "version": parts[1]}
                    elif len(parts) == 1:
                        return {"name": parts[0], "version": None}

                # Also check for format without channel prefix: bwa-mem2=2.3
                if isinstance(dep, str) and '=' in dep and '::' not in dep and not dep.startswith('#'):
                    parts = dep.strip().split('=')
                    if len(parts) == 2:
                        return {"name": parts[0], "version": parts[1]}

            # Fall back to conda-forge packages
            for dep in env_data['dependencies']:
                if isinstance(dep, str) and 'conda-forge::' in dep:
                    parts = dep.split('::')[1].split('=')
                    if len(parts) == 2:
                        return {"name": parts[0], "version": parts[1]}

        except Exception as e:
            print(f"  Error reading environment.yml: {e}")

        return None

    def fix_tool(self, xml_file: Path) -> bool:
        """Fix a single tool's container reference."""
        try:
            with open(xml_file) as f:
                content = f.read()

            # Check if it has :latest
            if ':latest' not in content:
                return False

            # Extract tool ID (e.g., nfcore_anndata/barcodes)
            match = re.search(r'<tool id="nfcore_([^"]+)"', content)
            if not match:
                return False

            tool_id = match.group(1)  # e.g., anndata/barcodes

            # Get module path
            module_path = self.modules_dir / tool_id.replace('/', '/')
            if not module_path.exists():
                print(f"  Module not found: {module_path}")
                return False

            # Extract tool info from environment.yml
            tool_info = self.extract_tool_from_environment(module_path)
            if not tool_info:
                print(f"  No tool info for {tool_id}")
                return False

            # Build correct container reference
            tool_name = tool_info['name']
            version = tool_info['version']

            if version:
                new_container = f"biocontainers/{tool_name}:{version}"
            else:
                new_container = f"biocontainers/{tool_name}:latest"

            # Find old container pattern - could be like biocontainers/tool/subtool:latest
            old_pattern = re.search(r'biocontainers/[^:]+:latest', content)
            if not old_pattern:
                return False

            old_container = old_pattern.group(0)

            # Replace container references (appears twice - in requirements and help)
            content = content.replace(old_container, new_container)

            # Write back
            with open(xml_file, 'w') as f:
                f.write(content)

            print(f"  Fixed: {xml_file.name}")
            print(f"    {old_container} -> {new_container}")
            return True

        except Exception as e:
            print(f"  Error fixing {xml_file.name}: {e}")
            return False

    def run(self):
        """Fix all tools with :latest containers."""
        print("FIXING REMAINING :LATEST CONTAINERS")
        print("=" * 80)

        # Find all tools with :latest
        tools_with_latest = []
        for xml_file in self.tools_dir.glob("*.xml"):
            try:
                with open(xml_file) as f:
                    if ':latest' in f.read():
                        tools_with_latest.append(xml_file)
            except Exception as e:
                print(f"Error reading {xml_file}: {e}")

        print(f"Found {len(tools_with_latest)} tools with :latest containers\n")

        for i, xml_file in enumerate(tools_with_latest, 1):
            if i % 10 == 0:
                print(f"Processing {i}/{len(tools_with_latest)}...")

            if self.fix_tool(xml_file):
                self.fixed_count += 1
            else:
                self.failed_count += 1

        print("\n" + "=" * 80)
        print("FIX REPORT")
        print("=" * 80)
        print(f"Total tools:     {len(tools_with_latest)}")
        print(f"Fixed:           {self.fixed_count}")
        print(f"Failed:          {self.failed_count}")
        print(f"Success rate:    {self.fixed_count/len(tools_with_latest)*100:.1f}%")
        print("=" * 80)

if __name__ == "__main__":
    fixer = LatestContainerFixer()
    fixer.run()
