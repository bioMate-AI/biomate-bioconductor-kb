#!/usr/bin/env python3
"""
Fix ALL Container References - Extract Real Versions from nf-core

Issues to fix:
1. Containers with :latest tag (1,020 tools)
2. Wrong container paths (biocontainers/tool/subtool:latest)
3. Missing version numbers

Solution:
- Extract actual container references from nf-core main.nf files
- Use proper biocontainer format: biocontainers/tool:version--hash
"""

import re
from pathlib import Path
import xml.etree.ElementTree as ET
from typing import Optional, Dict


class ContainerFixer:
    """Fix container references in all tools."""

    def __init__(self, nfcore_repo: str = "/tmp/nfcore-modules"):
        self.nfcore_repo = Path(nfcore_repo)
        self.modules_dir = self.nfcore_repo / "modules" / "nf-core"
        self.stats = {
            "total_checked": 0,
            "had_latest": 0,
            "had_wrong_path": 0,
            "fixed": 0,
            "failed": 0,
            "no_nfcore_module": 0
        }
        self.failed_tools = []

    def extract_container_from_nfcore(self, module_name: str) -> Optional[str]:
        """
        Extract container reference from nf-core main.nf file.

        Args:
            module_name: e.g., "samtools/sort" or "bwa/mem"

        Returns:
            Container string like "biocontainers/samtools:1.19.2--h50ea8bc_1"
        """
        # Convert module name to path
        if "/" in module_name:
            module_path = self.modules_dir / module_name
        else:
            # Single-level module
            module_path = self.modules_dir / module_name

        main_nf = module_path / "main.nf"

        if not main_nf.exists():
            return None

        try:
            with open(main_nf, 'r') as f:
                content = f.read()

            # Pattern 1: 'biocontainers/tool:version--hash'
            pattern1 = r"'(biocontainers/[^']+)'"
            match = re.search(pattern1, content)
            if match:
                return match.group(1)

            # Pattern 2: "biocontainers/tool:version--hash"
            pattern2 = r'"(biocontainers/[^"]+)"'
            match = re.search(pattern2, content)
            if match:
                return match.group(1)

            # Pattern 3: Look for container = or container:
            pattern3 = r'container\s*[=:]\s*["\']([^"\']+)["\']'
            match = re.search(pattern3, content)
            if match:
                container = match.group(1)
                # Skip Nextflow variables
                if '${' not in container and 'workflow.' not in container:
                    if 'biocontainers' in container:
                        return container
                    else:
                        # Add biocontainers prefix if missing
                        return f"biocontainers/{container}"

            return None

        except Exception as e:
            print(f"  Error reading {main_nf}: {e}")
            return None

    def get_module_name_from_tool_id(self, tool_id: str) -> str:
        """
        Convert tool ID to nf-core module name.

        Examples:
            nfcore_samtools/sort -> samtools/sort
            nfcore_bwa/mem -> bwa/mem
            nfcore_fastqc -> fastqc
        """
        # Remove nfcore_ prefix
        name = tool_id.replace("nfcore_", "")

        # Handle underscores - convert to slashes for nf-core paths
        # samtools_sort -> samtools/sort
        if "_" in name and "/" not in name:
            parts = name.split("_", 1)
            name = f"{parts[0]}/{parts[1]}"

        return name

    def fix_tool_container(self, tool_path: Path) -> bool:
        """Fix container reference in a single tool."""
        self.stats["total_checked"] += 1

        try:
            tree = ET.parse(tool_path)
            root = tree.getroot()

            # Get tool ID
            tool_id = root.get('id', '')

            # Find current container
            reqs = root.find('requirements')
            if reqs is None:
                return False

            container_elem = reqs.find('container')
            if container_elem is None:
                return False

            current_container = (container_elem.text or '').strip()

            # Check if needs fixing
            needs_fix = False
            if ':latest' in current_container:
                self.stats["had_latest"] += 1
                needs_fix = True

            # Check for wrong path format (e.g., biocontainers/tool/subtool:latest)
            if current_container.count('/') > 1:
                self.stats["had_wrong_path"] += 1
                needs_fix = True

            if not needs_fix:
                return True  # Already good

            # Extract module name and get proper container
            module_name = self.get_module_name_from_tool_id(tool_id)
            proper_container = self.extract_container_from_nfcore(module_name)

            if proper_container:
                # Update container
                container_elem.text = proper_container

                # Also update in help section if present
                help_elem = root.find('help')
                if help_elem is not None and help_elem.text:
                    help_text = help_elem.text
                    # Update container reference in help
                    help_text = re.sub(
                        r'- Container: .*',
                        f'- Container: {proper_container}',
                        help_text
                    )
                    help_elem.text = help_text

                # Save
                tree.write(tool_path, encoding='unicode', xml_declaration=True)
                self.stats["fixed"] += 1

                if self.stats["fixed"] % 100 == 0:
                    print(f"  Fixed {self.stats['fixed']} tools...")

                return True
            else:
                self.stats["no_nfcore_module"] += 1
                self.stats["failed"] += 1
                self.failed_tools.append({
                    "tool": tool_path.stem,
                    "tool_id": tool_id,
                    "module": module_name,
                    "current_container": current_container,
                    "reason": "No nf-core module found"
                })
                return False

        except Exception as e:
            self.stats["failed"] += 1
            self.failed_tools.append({
                "tool": tool_path.stem,
                "error": str(e)
            })
            return False

    def fix_all_tools(self, tools_dir: Path):
        """Fix all tools in directory."""
        print("=" * 80)
        print("FIXING ALL CONTAINER REFERENCES")
        print("=" * 80)
        print()

        xml_files = list(tools_dir.glob("*.xml"))
        print(f"Found {len(xml_files)} tools to process\n")

        for tool_file in xml_files:
            self.fix_tool_container(tool_file)

        self._print_report()

    def _print_report(self):
        """Print summary report."""
        print()
        print("=" * 80)
        print("CONTAINER FIX REPORT")
        print("=" * 80)
        print()
        print(f"Total tools checked:         {self.stats['total_checked']}")
        print(f"Tools with :latest tag:      {self.stats['had_latest']}")
        print(f"Tools with wrong path:       {self.stats['had_wrong_path']}")
        print(f"Successfully fixed:          {self.stats['fixed']}")
        print(f"Failed to fix:               {self.stats['failed']}")
        print(f"  (No nf-core module found:  {self.stats['no_nfcore_module']})")

        if self.failed_tools:
            print()
            print("=" * 80)
            print(f"FAILED TOOLS ({len(self.failed_tools)}):")
            print("=" * 80)
            for i, fail in enumerate(self.failed_tools[:20], 1):  # Show first 20
                print(f"\n{i}. {fail.get('tool', 'unknown')}")
                if 'module' in fail:
                    print(f"   Module: {fail['module']}")
                    print(f"   Current: {fail.get('current_container', 'N/A')}")
                    print(f"   Reason: {fail.get('reason', 'unknown')}")
                if 'error' in fail:
                    print(f"   Error: {fail['error']}")

            if len(self.failed_tools) > 20:
                print(f"\n... and {len(self.failed_tools) - 20} more")

        # Calculate success rate
        if self.stats['total_checked'] > 0:
            success_rate = (self.stats['fixed'] / self.stats['total_checked']) * 100
            print()
            print("=" * 80)
            print(f"SUCCESS RATE: {success_rate:.1f}%")
            print("=" * 80)


def main():
    """Main execution."""
    tools_dir = Path(__file__).parent.parent / "tools" / "nfcore_generated"

    if not tools_dir.exists():
        print(f"Error: Tools directory not found: {tools_dir}")
        return 1

    fixer = ContainerFixer()
    fixer.fix_all_tools(tools_dir)

    # Return 0 if most tools were fixed successfully
    success_rate = (fixer.stats['fixed'] / fixer.stats['total_checked']) * 100 if fixer.stats['total_checked'] > 0 else 0

    if success_rate >= 90:
        print("\n✅ Container references fixed successfully!")
        return 0
    elif success_rate >= 70:
        print("\n⚠️  Most containers fixed, but some issues remain")
        return 0
    else:
        print("\n❌ Many containers failed to fix - manual intervention needed")
        return 1


if __name__ == "__main__":
    import sys
    sys.exit(main())
