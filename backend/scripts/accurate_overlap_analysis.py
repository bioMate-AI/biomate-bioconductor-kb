#!/usr/bin/env python3
"""
Accurate overlap analysis between nf-core tools and Galaxy ToolShed tools.
Carefully handles tool name normalization to avoid false matches.
"""

import sqlite3
from pathlib import Path
import re
from collections import defaultdict

class AccurateOverlapAnalysis:
    def __init__(self,
                 db_path: str = "galaxy_ai_tools.db",
                 nfcore_tools_dir: str = "tools/nfcore_generated"):
        self.db_path = Path(db_path)
        self.nfcore_tools_dir = Path(nfcore_tools_dir)

    def normalize_tool_name(self, name: str) -> str:
        """
        Normalize tool name for comparison.
        Handles various formats: FastQC, fastqc, fast_qc, etc.
        """
        if not name:
            return ""

        # Convert to lowercase
        name = name.lower()

        # Remove common prefixes
        for prefix in ['nfcore_', 'toolshed_', 'galaxy_']:
            if name.startswith(prefix):
                name = name[len(prefix):]

        # Remove version numbers
        name = re.sub(r'_v?\d+(\.\d+)*', '', name)

        # Remove underscores and hyphens for comparison
        name = name.replace('_', '').replace('-', '').replace(' ', '')

        return name.strip()

    def extract_tool_components(self, name: str) -> dict:
        """
        Extract tool name components for more accurate matching.
        Returns: base_name, subcommand (if any)
        """
        name = name.lower()

        # Handle nf-core format: tool/subcommand
        if '/' in name:
            parts = name.split('/')
            return {
                'base': parts[0],
                'subcommand': parts[1] if len(parts) > 1 else None,
                'full': name
            }

        # Handle underscore format: tool_subcommand
        if '_' in name:
            parts = name.split('_', 1)
            return {
                'base': parts[0],
                'subcommand': parts[1] if len(parts) > 1 else None,
                'full': name
            }

        return {
            'base': name,
            'subcommand': None,
            'full': name
        }

    def get_galaxy_tools(self):
        """Get all tools from Galaxy database."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        cursor.execute("""
            SELECT DISTINCT name, tool_id, repo_owner, repo_name, category
            FROM tools
            WHERE is_dataset = 0 OR is_dataset IS NULL
            ORDER BY name
        """)

        tools = []
        for row in cursor.fetchall():
            name, tool_id, repo_owner, repo_name, category = row

            # Skip if no name or if it's metadata/junk
            if not name:
                continue

            # Filter out non-tool entries
            skip_patterns = [
                'Repository Actions',
                'Suite',
                'package_',
                'data_manager',
                'Workflow',
                'workflow',
            ]

            if any(pattern in name for pattern in skip_patterns):
                continue

            # Skip if name is too short (likely junk)
            if len(name) < 2:
                continue

            tools.append({
                'name': name,
                'tool_id': tool_id,
                'repo_owner': repo_owner,
                'repo_name': repo_name,
                'category': category,
                'normalized': self.normalize_tool_name(name),
                'components': self.extract_tool_components(name)
            })

        conn.close()
        return tools

    def get_nfcore_tools(self):
        """Get all nf-core tools from XML files."""
        tools = []

        for xml_file in self.nfcore_tools_dir.glob("*.xml"):
            # Use filename as the primary tool name (it's clean)
            tool_name = xml_file.stem

            # Also extract from XML for display
            try:
                import xml.etree.ElementTree as ET
                tree = ET.parse(xml_file)
                root = tree.getroot()
                tool_id = root.get('id', '')
                tool_display_name = root.get('name', '')

                tools.append({
                    'filename': xml_file.stem,
                    'name': tool_name,  # Use filename, not parsed ID
                    'display_name': tool_display_name,
                    'tool_id': tool_id,
                    'normalized': self.normalize_tool_name(tool_name),
                    'components': self.extract_tool_components(tool_name)
                })
            except Exception as e:
                print(f"Error reading {xml_file}: {e}")

        return tools

    def find_matches(self, galaxy_tools, nfcore_tools):
        """Find matching tools between Galaxy and nf-core."""
        matches = {
            'exact': [],           # Exact name match
            'base_match': [],      # Base tool name matches
            'normalized': [],      # Normalized name matches
            'fuzzy': []           # Fuzzy/partial matches
        }

        unmatched_nfcore = []
        unmatched_galaxy = set(range(len(galaxy_tools)))

        for nfc in nfcore_tools:
            found = False
            nfc_norm = nfc['normalized']
            nfc_base = nfc['components']['base']

            for i, gal in enumerate(galaxy_tools):
                gal_norm = gal['normalized']
                gal_base = gal['components']['base']

                # Exact normalized match
                if nfc_norm == gal_norm:
                    matches['exact'].append({
                        'nfcore': nfc,
                        'galaxy': gal,
                        'match_type': 'exact_normalized'
                    })
                    if i in unmatched_galaxy:
                        unmatched_galaxy.remove(i)
                    found = True
                    break

                # Base name match (tool without subcommand)
                elif nfc_base == gal_base:
                    matches['base_match'].append({
                        'nfcore': nfc,
                        'galaxy': gal,
                        'match_type': 'base_name'
                    })
                    if i in unmatched_galaxy:
                        unmatched_galaxy.remove(i)
                    found = True
                    break

                # Fuzzy match (one contains the other)
                elif (len(nfc_norm) > 3 and len(gal_norm) > 3 and
                      (nfc_norm in gal_norm or gal_norm in nfc_norm)):
                    matches['fuzzy'].append({
                        'nfcore': nfc,
                        'galaxy': gal,
                        'match_type': 'fuzzy_partial'
                    })
                    found = True
                    # Don't break, continue looking for better match

            if not found:
                unmatched_nfcore.append(nfc)

        unmatched_galaxy_list = [galaxy_tools[i] for i in sorted(unmatched_galaxy)]

        return matches, unmatched_nfcore, unmatched_galaxy_list

    def run(self):
        """Run the overlap analysis."""
        print("=" * 80)
        print("ACCURATE OVERLAP ANALYSIS: nf-core vs Galaxy ToolShed")
        print("=" * 80)
        print()

        # Get tools
        print("Loading Galaxy tools from database...")
        galaxy_tools = self.get_galaxy_tools()
        print(f"  Found {len(galaxy_tools)} Galaxy tools\n")

        print("Loading nf-core tools from XML files...")
        nfcore_tools = self.get_nfcore_tools()
        print(f"  Found {len(nfcore_tools)} nf-core tools\n")

        # Find matches
        print("Analyzing overlaps...")
        matches, unmatched_nfcore, unmatched_galaxy = self.find_matches(
            galaxy_tools, nfcore_tools
        )

        # Calculate statistics
        exact_matches = len(matches['exact'])
        base_matches = len(matches['base_match'])
        fuzzy_matches = len(matches['fuzzy'])
        total_matched = exact_matches + base_matches

        print("\n" + "=" * 80)
        print("OVERLAP STATISTICS")
        print("=" * 80)
        print()
        print(f"Galaxy ToolShed:  {len(galaxy_tools):,} tools")
        print(f"nf-core:          {len(nfcore_tools):,} tools")
        print()
        print(f"Exact matches:    {exact_matches:,} ({exact_matches/len(nfcore_tools)*100:.1f}% of nf-core)")
        print(f"Base matches:     {base_matches:,} ({base_matches/len(nfcore_tools)*100:.1f}% of nf-core)")
        print(f"Total matches:    {total_matched:,} ({total_matched/len(nfcore_tools)*100:.1f}% of nf-core)")
        print(f"Fuzzy matches:    {fuzzy_matches:,} (may include false positives)")
        print()
        print(f"nf-core only:     {len(unmatched_nfcore):,} tools")
        print(f"Galaxy only:      {len(unmatched_galaxy):,} tools")

        # Show example matches
        print("\n" + "=" * 80)
        print("EXAMPLE EXACT MATCHES (first 20)")
        print("=" * 80)
        for i, match in enumerate(matches['exact'][:20], 1):
            nfc = match['nfcore']
            gal = match['galaxy']
            print(f"{i:2d}. nf-core: {nfc['name']:30s} <-> Galaxy: {gal['name']}")

        if matches['base_match']:
            print("\n" + "=" * 80)
            print("EXAMPLE BASE MATCHES (first 20)")
            print("=" * 80)
            for i, match in enumerate(matches['base_match'][:20], 1):
                nfc = match['nfcore']
                gal = match['galaxy']
                print(f"{i:2d}. nf-core: {nfc['name']:30s} <-> Galaxy: {gal['name']}")

        # Show unmatched nf-core tools
        print("\n" + "=" * 80)
        print("UNMATCHED NF-CORE TOOLS (first 50)")
        print("=" * 80)
        for i, tool in enumerate(sorted(unmatched_nfcore, key=lambda x: x['name'])[:50], 1):
            print(f"{i:3d}. {tool['name']}")

        if len(unmatched_nfcore) > 50:
            print(f"\n... and {len(unmatched_nfcore) - 50} more")

        # Save detailed report
        self.save_detailed_report(matches, unmatched_nfcore, unmatched_galaxy)

        print("\n" + "=" * 80)
        print(f"Detailed report saved to: ACCURATE_OVERLAP_REPORT_2025-10-13.txt")
        print("=" * 80)

    def save_detailed_report(self, matches, unmatched_nfcore, unmatched_galaxy):
        """Save detailed report to file."""
        with open("ACCURATE_OVERLAP_REPORT_2025-10-13.txt", "w") as f:
            f.write("ACCURATE OVERLAP ANALYSIS: nf-core vs Galaxy ToolShed\n")
            f.write("=" * 80 + "\n")
            f.write("Generated: 2025-10-13\n\n")

            # Exact matches
            f.write(f"\nEXACT MATCHES ({len(matches['exact'])} tools)\n")
            f.write("=" * 80 + "\n")
            for match in sorted(matches['exact'], key=lambda x: x['nfcore']['name']):
                nfc = match['nfcore']
                gal = match['galaxy']
                f.write(f"\nnf-core: {nfc['name']}\n")
                f.write(f"  Tool ID: {nfc['tool_id']}\n")
                f.write(f"  Display: {nfc['display_name']}\n")
                f.write(f"Galaxy:  {gal['name']}\n")
                f.write(f"  Tool ID: {gal['tool_id']}\n")
                f.write(f"  Owner:   {gal['repo_owner']}/{gal['repo_name']}\n")

            # Base matches
            if matches['base_match']:
                f.write(f"\n\nBASE NAME MATCHES ({len(matches['base_match'])} tools)\n")
                f.write("=" * 80 + "\n")
                for match in sorted(matches['base_match'], key=lambda x: x['nfcore']['name']):
                    nfc = match['nfcore']
                    gal = match['galaxy']
                    f.write(f"\nnf-core: {nfc['name']}\n")
                    f.write(f"Galaxy:  {gal['name']}\n")

            # Unmatched nf-core
            f.write(f"\n\nUNMATCHED NF-CORE TOOLS ({len(unmatched_nfcore)} tools)\n")
            f.write("=" * 80 + "\n")
            for tool in sorted(unmatched_nfcore, key=lambda x: x['name']):
                f.write(f"{tool['name']}\n")

            # Unmatched Galaxy (sample)
            f.write(f"\n\nUNMATCHED GALAXY TOOLS (first 500 of {len(unmatched_galaxy)})\n")
            f.write("=" * 80 + "\n")
            for tool in sorted(unmatched_galaxy, key=lambda x: x['name'])[:500]:
                f.write(f"{tool['name']:50s} ({tool['repo_owner']}/{tool['repo_name']})\n")

if __name__ == "__main__":
    analyzer = AccurateOverlapAnalysis()
    analyzer.run()
