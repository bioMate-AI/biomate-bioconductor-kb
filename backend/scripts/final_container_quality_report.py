#!/usr/bin/env python3
"""
Generate final quality report for all tool containers.
"""

import re
from pathlib import Path
from collections import defaultdict

def analyze_containers():
    tools_dir = Path("tools/nfcore_generated")

    total = 0
    with_latest = []
    with_version = []
    container_types = defaultdict(int)

    for xml_file in sorted(tools_dir.glob("*.xml")):
        total += 1

        try:
            with open(xml_file) as f:
                content = f.read()

            # Find container reference
            match = re.search(r'<container type="docker">([^<]+)</container>', content)
            if match:
                container = match.group(1)

                if ':latest' in container:
                    with_latest.append(xml_file.stem)
                else:
                    with_version.append(xml_file.stem)

                # Categorize by tool type
                if 'cellranger' in container:
                    container_types['CellRanger (10X Genomics)'] += 1
                elif 'parabricks' in container:
                    container_types['Parabricks (NVIDIA)'] += 1
                elif 'spaceranger' in container:
                    container_types['SpaceRanger (10X Genomics)'] += 1
                elif 'xeniumranger' in container:
                    container_types['XeniumRanger (10X Genomics)'] += 1
                elif 'deepvariant' in container or 'deepsomatic' in container:
                    container_types['DeepVariant (Google)'] += 1
                elif 'ensemblvep' in container:
                    container_types['Ensembl VEP'] += 1
                elif 'biocontainers/' in container and ':latest' not in container:
                    container_types['Biocontainers (versioned)'] += 1
                elif ':latest' in container:
                    container_types['Biocontainers (:latest)'] += 1
                else:
                    container_types['Other'] += 1

        except Exception as e:
            print(f"Error processing {xml_file}: {e}")

    # Print report
    print("=" * 80)
    print("FINAL CONTAINER QUALITY REPORT")
    print("=" * 80)
    print(f"\nTotal tools: {total}")
    print(f"With versioned containers: {len(with_version)} ({len(with_version)/total*100:.1f}%)")
    print(f"With :latest tag: {len(with_latest)} ({len(with_latest)/total*100:.1f}%)")

    print("\n" + "=" * 80)
    print("CONTAINER BREAKDOWN")
    print("=" * 80)
    for container_type, count in sorted(container_types.items(), key=lambda x: -x[1]):
        print(f"{container_type:40s}: {count:4d} ({count/total*100:5.1f}%)")

    print("\n" + "=" * 80)
    print("TOOLS WITH :LATEST TAG")
    print("=" * 80)
    print(f"Total: {len(with_latest)}\n")

    # Group by type
    proprietary = []
    other_latest = []

    for tool in with_latest:
        if any(x in tool for x in ['cellranger', 'parabricks', 'spaceranger', 'xeniumranger',
                                     'deepvariant', 'deepsomatic']):
            proprietary.append(tool)
        else:
            other_latest.append(tool)

    print(f"Proprietary tools (no biocontainers available): {len(proprietary)}")
    for tool in sorted(proprietary):
        print(f"  - {tool}")

    print(f"\nOther tools (fixable): {len(other_latest)}")
    for tool in sorted(other_latest):
        print(f"  - {tool}")

    print("\n" + "=" * 80)
    print("SUMMARY")
    print("=" * 80)
    print(f"✓ Successfully versioned: {len(with_version)}/{ total} ({len(with_version)/total*100:.1f}%)")
    print(f"⚠ Proprietary tools with :latest: {len(proprietary)} ({len(proprietary)/total*100:.1f}%)")
    print(f"✗ Fixable tools with :latest: {len(other_latest)} ({len(other_latest)/total*100:.1f}%)")
    print("=" * 80)

if __name__ == "__main__":
    analyze_containers()
