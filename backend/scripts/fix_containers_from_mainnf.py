#!/usr/bin/env python3
"""
Extract container references from main.nf files for remaining :latest tools.
"""

import re
from pathlib import Path

class MainNfContainerFixer:
    def __init__(self, tools_dir: str = "tools/nfcore_generated",
                 modules_dir: str = "/tmp/nfcore-modules/modules/nf-core"):
        self.tools_dir = Path(tools_dir)
        self.modules_dir = Path(modules_dir)
        self.fixed_count = 0
        self.failed_count = 0

    def extract_container_from_mainnf(self, module_path: Path) -> str:
        """Extract container from main.nf file."""
        main_nf = module_path / "main.nf"
        if not main_nf.exists():
            return None

        try:
            with open(main_nf) as f:
                content = f.read()

            # Find container line - formats:
            # container "docker.io/teambraker/braker3:v3.0.7.5"
            # container "${ workflow.containerEngine == 'singularity' ... }"
            # container "community.wave.seqera.io/library/..."

            # Look for simple quoted container
            match = re.search(r'container\s+"([^"]+)"', content)
            if match:
                container = match.group(1)

                # Skip wave containers and variable substitutions
                if '${' in container or 'community.wave.seqera.io' in container:
                    return None

                # Convert docker.io URLs to simple format
                container = container.replace('docker.io/', '')

                # Convert to biocontainers format if not already
                if not container.startswith('biocontainers/'):
                    # teambraker/braker3:v3.0.7.5 -> teambraker/braker3:v3.0.7.5
                    # (keep original if it's a proper docker image)
                    return container

                return container

        except Exception as e:
            print(f"  Error reading main.nf: {e}")

        return None

    def fix_tool(self, xml_file: Path) -> bool:
        """Fix a single tool's container reference."""
        try:
            with open(xml_file) as f:
                content = f.read()

            # Check if it has :latest
            if ':latest' not in content:
                return False

            # Extract tool ID (e.g., nfcore_braker3)
            match = re.search(r'<tool id="nfcore_([^"]+)"', content)
            if not match:
                return False

            tool_id = match.group(1)  # e.g., braker3 or anndata/barcodes

            # Get module path
            module_path = self.modules_dir / tool_id.replace('/', '/')
            if not module_path.exists():
                print(f"  Module not found: {module_path}")
                return False

            # Extract container from main.nf
            new_container = self.extract_container_from_mainnf(module_path)
            if not new_container:
                return False

            # Find old container pattern
            old_pattern = re.search(r'biocontainers/[^:]+:latest', content)
            if not old_pattern:
                return False

            old_container = old_pattern.group(0)

            # Replace container references
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
        print("FIXING CONTAINERS FROM MAIN.NF FILES")
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
        if len(tools_with_latest) > 0:
            print(f"Success rate:    {self.fixed_count/len(tools_with_latest)*100:.1f}%")
        print("=" * 80)

if __name__ == "__main__":
    fixer = MainNfContainerFixer()
    fixer.run()
