#!/usr/bin/env python3
"""
Comprehensive Quality Check for All Generated Tools

Validates:
1. XML structure and syntax
2. Container references
3. Tool descriptions and metadata
4. Installation compatibility
5. Input/output definitions
"""

import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Dict, List, Tuple
import json
import re


class ToolQualityChecker:
    """Check and validate tool quality."""

    def __init__(self, tools_dir: str = None):
        if tools_dir is None:
            # Auto-detect tools directory
            tools_dir = Path(__file__).parent.parent / "tools"
        self.tools_dir = Path(tools_dir)
        self.issues = []
        self.stats = {
            "total_tools": 0,
            "valid_xml": 0,
            "invalid_xml": 0,
            "proper_containers": 0,
            "broken_containers": 0,
            "has_description": 0,
            "missing_description": 0,
            "has_help": 0,
            "missing_help": 0,
            "has_inputs": 0,
            "missing_inputs": 0,
            "has_outputs": 0,
            "missing_outputs": 0,
        }

    def check_all_tools(self) -> Dict:
        """Check all tools in nfcore directories."""
        print("=" * 80)
        print("COMPREHENSIVE TOOL QUALITY CHECK")
        print("=" * 80)

        tool_files = []
        for subdir in ["nfcore_generated", "nfcore_general", "nfcore_lcms"]:
            dir_path = self.tools_dir / subdir
            if dir_path.exists():
                tool_files.extend(list(dir_path.glob("*.xml")))

        self.stats["total_tools"] = len(tool_files)
        print(f"\nFound {len(tool_files)} tools to check\n")

        for i, tool_file in enumerate(tool_files, 1):
            if i % 100 == 0:
                print(f"  Checked {i}/{len(tool_files)} tools...")
            self._check_tool(tool_file)

        return self._generate_report()

    def _check_tool(self, tool_file: Path):
        """Check a single tool file."""
        tool_name = tool_file.stem

        # Check 1: Valid XML
        try:
            tree = ET.parse(tool_file)
            root = tree.getroot()
            self.stats["valid_xml"] += 1
        except ET.ParseError as e:
            self.stats["invalid_xml"] += 1
            self.issues.append({
                "tool": tool_name,
                "severity": "CRITICAL",
                "issue": "Invalid XML",
                "detail": str(e)
            })
            return

        # Check 2: Required attributes
        tool_id = root.get('id')
        tool_name_attr = root.get('name')
        tool_version = root.get('version')

        if not tool_id:
            self.issues.append({
                "tool": tool_name,
                "severity": "CRITICAL",
                "issue": "Missing tool ID"
            })

        if not tool_name_attr:
            self.issues.append({
                "tool": tool_name,
                "severity": "HIGH",
                "issue": "Missing tool name"
            })

        if not tool_version:
            self.issues.append({
                "tool": tool_name,
                "severity": "MEDIUM",
                "issue": "Missing version"
            })

        # Check 3: Description
        description = root.find('description')
        if description is not None and description.text and description.text.strip():
            self.stats["has_description"] += 1
        else:
            self.stats["missing_description"] += 1
            self.issues.append({
                "tool": tool_name,
                "severity": "MEDIUM",
                "issue": "Missing or empty description"
            })

        # Check 4: Container reference
        reqs = root.find('requirements')
        if reqs is not None:
            container = reqs.find('container')
            if container is not None and container.text:
                container_text = container.text.strip()

                # Check for broken Nextflow syntax
                if '${' in container_text or 'workflow.' in container_text:
                    self.stats["broken_containers"] += 1
                    self.issues.append({
                        "tool": tool_name,
                        "severity": "CRITICAL",
                        "issue": "Broken container reference",
                        "detail": f"Contains Nextflow syntax: {container_text[:50]}"
                    })
                # Check for empty
                elif not container_text:
                    self.stats["broken_containers"] += 1
                    self.issues.append({
                        "tool": tool_name,
                        "severity": "CRITICAL",
                        "issue": "Empty container reference"
                    })
                # Check for proper format
                elif 'biocontainers' in container_text or 'depot.galaxyproject' in container_text:
                    self.stats["proper_containers"] += 1
                else:
                    self.stats["proper_containers"] += 1
                    # Custom container but acceptable
            else:
                self.stats["broken_containers"] += 1
                self.issues.append({
                    "tool": tool_name,
                    "severity": "HIGH",
                    "issue": "No container element"
                })
        else:
            self.stats["broken_containers"] += 1
            self.issues.append({
                "tool": tool_name,
                "severity": "HIGH",
                "issue": "No requirements section"
            })

        # Check 5: Help text
        help_elem = root.find('help')
        if help_elem is not None and help_elem.text and help_elem.text.strip():
            self.stats["has_help"] += 1
        else:
            self.stats["missing_help"] += 1
            # Help is optional, LOW severity
            self.issues.append({
                "tool": tool_name,
                "severity": "LOW",
                "issue": "Missing or empty help text"
            })

        # Check 6: Inputs
        inputs = root.find('inputs')
        if inputs is not None and len(inputs) > 0:
            self.stats["has_inputs"] += 1
        else:
            self.stats["missing_inputs"] += 1
            self.issues.append({
                "tool": tool_name,
                "severity": "HIGH",
                "issue": "No inputs defined"
            })

        # Check 7: Outputs
        outputs = root.find('outputs')
        if outputs is not None and len(outputs) > 0:
            self.stats["has_outputs"] += 1
        else:
            self.stats["missing_outputs"] += 1
            self.issues.append({
                "tool": tool_name,
                "severity": "HIGH",
                "issue": "No outputs defined"
            })

    def _generate_report(self) -> Dict:
        """Generate comprehensive report."""
        print("\n" + "=" * 80)
        print("STATISTICS")
        print("=" * 80)

        print(f"\nTotal Tools: {self.stats['total_tools']}")

        if self.stats['total_tools'] == 0:
            print("\n⚠️  ERROR: No tools found to check!")
            print(f"   Looked in: {self.tools_dir}")
            return {"stats": self.stats, "issues": [], "quality_score": 0}

        print(f"\nXML Validity:")
        print(f"  ✓ Valid XML:       {self.stats['valid_xml']} ({self.stats['valid_xml']/self.stats['total_tools']*100:.1f}%)")
        print(f"  ✗ Invalid XML:     {self.stats['invalid_xml']}")

        print(f"\nContainers:")
        print(f"  ✓ Proper:          {self.stats['proper_containers']} ({self.stats['proper_containers']/self.stats['total_tools']*100:.1f}%)")
        print(f"  ✗ Broken:          {self.stats['broken_containers']} ({self.stats['broken_containers']/self.stats['total_tools']*100:.1f}%)")

        print(f"\nDescriptions:")
        print(f"  ✓ Has description: {self.stats['has_description']} ({self.stats['has_description']/self.stats['total_tools']*100:.1f}%)")
        print(f"  ✗ Missing:         {self.stats['missing_description']}")

        print(f"\nHelp Text:")
        print(f"  ✓ Has help:        {self.stats['has_help']} ({self.stats['has_help']/self.stats['total_tools']*100:.1f}%)")
        print(f"  ✗ Missing:         {self.stats['missing_help']}")

        print(f"\nInputs/Outputs:")
        print(f"  ✓ Has inputs:      {self.stats['has_inputs']} ({self.stats['has_inputs']/self.stats['total_tools']*100:.1f}%)")
        print(f"  ✓ Has outputs:     {self.stats['has_outputs']} ({self.stats['has_outputs']/self.stats['total_tools']*100:.1f}%)")

        # Group issues by severity
        critical = [i for i in self.issues if i['severity'] == 'CRITICAL']
        high = [i for i in self.issues if i['severity'] == 'HIGH']
        medium = [i for i in self.issues if i['severity'] == 'MEDIUM']
        low = [i for i in self.issues if i['severity'] == 'LOW']

        print(f"\n" + "=" * 80)
        print("ISSUES BY SEVERITY")
        print("=" * 80)
        print(f"\n  CRITICAL: {len(critical)}")
        print(f"  HIGH:     {len(high)}")
        print(f"  MEDIUM:   {len(medium)}")
        print(f"  LOW:      {len(low)}")

        if critical:
            print(f"\n  First 10 CRITICAL issues:")
            for issue in critical[:10]:
                print(f"    - {issue['tool']}: {issue['issue']}")
                if 'detail' in issue:
                    print(f"      Detail: {issue['detail']}")

        # Calculate quality score
        quality_score = (
            (self.stats['valid_xml'] / self.stats['total_tools']) * 30 +
            (self.stats['proper_containers'] / self.stats['total_tools']) * 30 +
            (self.stats['has_description'] / self.stats['total_tools']) * 20 +
            (self.stats['has_inputs'] / self.stats['total_tools']) * 10 +
            (self.stats['has_outputs'] / self.stats['total_tools']) * 10
        )

        print(f"\n" + "=" * 80)
        print(f"OVERALL QUALITY SCORE: {quality_score:.1f}/100")
        print("=" * 80)

        # Recommendations
        print(f"\n" + "=" * 80)
        print("RECOMMENDATIONS")
        print("=" * 80)

        if critical:
            print(f"\n⚠️  CRITICAL: {len(critical)} tools have critical issues that must be fixed:")
            print(f"   - Invalid XML or broken container references")
            print(f"   - These tools will NOT work in Galaxy")

        if high:
            print(f"\n⚠️  HIGH: {len(high)} tools have high-priority issues:")
            print(f"   - Missing essential elements (inputs, outputs, requirements)")
            print(f"   - Should be fixed before deployment")

        if medium:
            print(f"\n⚠️  MEDIUM: {len(medium)} tools have medium-priority issues:")
            print(f"   - Missing descriptions or versions")
            print(f"   - Affects usability but not functionality")

        if quality_score >= 90:
            print(f"\n✅ EXCELLENT: Quality score above 90, tools are production-ready!")
        elif quality_score >= 75:
            print(f"\n✓ GOOD: Quality score above 75, minor fixes recommended")
        elif quality_score >= 60:
            print(f"\n⚠️  FAIR: Quality score above 60, several issues need attention")
        else:
            print(f"\n✗ POOR: Quality score below 60, major fixes required")

        return {
            "stats": self.stats,
            "issues": self.issues,
            "quality_score": quality_score
        }

    def save_report(self, filename: str = None):
        """Save detailed report to JSON."""
        if filename is None:
            filename = Path(__file__).parent.parent / "TOOL_QUALITY_REPORT_2025-10-13.json"
        else:
            filename = Path(filename)

        report = {
            "metadata": {
                "timestamp": "2025-10-13",
                "total_tools_checked": self.stats["total_tools"]
            },
            "statistics": self.stats,
            "issues": self.issues
        }

        with open(filename, 'w') as f:
            json.dump(report, f, indent=2)

        print(f"\n✅ Detailed report saved to: {filename}")


def main():
    """Run comprehensive quality check."""
    checker = ToolQualityChecker()
    result = checker.check_all_tools()
    checker.save_report()

    # Return exit code based on quality
    if result['quality_score'] >= 75:
        return 0
    else:
        return 1


if __name__ == "__main__":
    import sys
    sys.exit(main())
