#!/usr/bin/env python3
"""
Workflow Deduplication Script

This script deduplicates Galaxy workflows by keeping only the latest version
of each workflow type. It also raises the quality threshold to be more selective.

Author: AI Assistant (Claude)
Date: 2025-11-18
"""

import json
import os
import re
import shutil
from pathlib import Path
from datetime import datetime
from collections import defaultdict
from typing import Dict, List, Tuple

# Configuration
CURATED_DIR = "/home/yzhang/biomate/research/curated_workflows"
FINAL_DIR = "/home/yzhang/biomate/research/final_curated_workflows"
REPORT_DIR = "/home/yzhang/biomate/research"

# Quality threshold - keep good workflows, not just excellent
STRICT_THRESHOLD = 60  # Keep workflows with reasonable quality


def extract_base_name_and_version(filename: str) -> Tuple[str, str]:
    """
    Extract base workflow name and version from filename.

    Examples:
    - "165_chipseq_pe_release_v08.ga" -> ("chipseq_pe", "08")
    - "165_atacseq_release_v014.ga" -> ("atacseq", "014")
    - "120_ref-guided_wps_processing_whole_data.ga" -> ("ref-guided_wps_processing_whole_data", "0")
    """

    # Remove score prefix and .ga extension
    name = re.sub(r'^\d+_', '', filename)
    name = name.replace('.ga', '')

    # Look for version patterns
    version_patterns = [
        r'_release_v(\d+(?:_\d+)*)',  # release_v08, release_v0_10_2
        r'_v(\d+(?:_\d+)*)',           # _v08
        r'_release_(\d+(?:_\d+)*)',    # release_08
    ]

    version = "0"
    base_name = name

    for pattern in version_patterns:
        match = re.search(pattern, name)
        if match:
            version = match.group(1)
            base_name = re.sub(pattern, '', name)
            break

    # Normalize base name (remove trailing underscores/numbers)
    base_name = re.sub(r'_+$', '', base_name)
    base_name = base_name.lower()

    return base_name, version


def version_to_tuple(version: str) -> tuple:
    """
    Convert version string to tuple for comparison.

    Examples:
    - "08" -> (8,)
    - "0_10_2" -> (0, 10, 2)
    """
    parts = version.replace('.', '_').split('_')
    return tuple(int(p) for p in parts if p.isdigit())


def deduplicate_workflows():
    """Main deduplication logic."""

    print("=" * 60)
    print("Workflow Deduplication")
    print("=" * 60)
    print()

    # Group workflows by base name
    workflow_groups = defaultdict(list)

    ga_files = list(Path(CURATED_DIR).glob("*.ga"))
    print(f"Found {len(ga_files)} curated workflows")

    for filepath in ga_files:
        filename = filepath.name

        # Extract score from filename
        score_match = re.match(r'^(\d+)_', filename)
        score = int(score_match.group(1)) if score_match else 0

        # Skip if below strict threshold
        if score < STRICT_THRESHOLD:
            continue

        base_name, version = extract_base_name_and_version(filename)

        workflow_groups[base_name].append({
            'filepath': filepath,
            'filename': filename,
            'version': version,
            'version_tuple': version_to_tuple(version),
            'score': score,
        })

    # Select latest version of each workflow
    selected = []
    duplicates = []

    for base_name, versions in workflow_groups.items():
        # Sort by version (highest first), then by score
        versions.sort(key=lambda x: (x['version_tuple'], x['score']), reverse=True)

        # Keep the latest (first after sorting)
        selected.append(versions[0])

        # Track duplicates
        if len(versions) > 1:
            duplicates.extend(versions[1:])

    print(f"\nAfter applying strict threshold ({STRICT_THRESHOLD}) and deduplication:")
    print(f"  - Selected: {len(selected)} unique latest-version workflows")
    print(f"  - Duplicates removed: {len(duplicates)}")
    print(f"  - Below threshold: {len(ga_files) - len(selected) - len(duplicates)}")

    # Create final directory
    os.makedirs(FINAL_DIR, exist_ok=True)

    # Copy selected workflows with clean names
    print(f"\nCopying to {FINAL_DIR}...")

    for wf in selected:
        # Create cleaner filename
        base_name, version = extract_base_name_and_version(wf['filename'])

        # Add version back if it exists
        if version != "0":
            clean_name = f"{base_name}_v{version.replace('_', '.')}.ga"
        else:
            clean_name = f"{base_name}.ga"

        dest_path = os.path.join(FINAL_DIR, clean_name)

        # Handle duplicates in final dir
        counter = 1
        while os.path.exists(dest_path):
            if version != "0":
                clean_name = f"{base_name}_v{version.replace('_', '.')}_{counter}.ga"
            else:
                clean_name = f"{base_name}_{counter}.ga"
            dest_path = os.path.join(FINAL_DIR, clean_name)
            counter += 1

        shutil.copy(wf['filepath'], dest_path)

    # Generate report
    generate_report(selected, duplicates, len(ga_files))

    print(f"\n" + "=" * 60)
    print("Deduplication Complete!")
    print("=" * 60)
    print(f"\nFinal collection: {len(selected)} workflows")
    print(f"Output directory: {FINAL_DIR}")


def generate_report(selected: List[Dict], duplicates: List[Dict], total: int):
    """Generate deduplication report."""

    timestamp = datetime.now().strftime("%Y%m%d_%H%M")
    report_path = os.path.join(REPORT_DIR, f"{timestamp}_DEDUPLICATED_WORKFLOW_REPORT.md")

    report = []
    report.append("# Deduplicated Workflow Collection Report\n\n")
    report.append(f"**Date:** {datetime.now().strftime('%Y-%m-%d %H:%M')}\n")
    report.append(f"**Input Workflows:** {total}\n")
    report.append(f"**Quality Threshold:** {STRICT_THRESHOLD}/100\n")
    report.append(f"**Final Selection:** {len(selected)} unique workflows\n")
    report.append(f"**Duplicates Removed:** {len(duplicates)}\n\n")

    report.append("---\n\n")
    report.append("## Final Curated Collection\n\n")
    report.append("| Score | Workflow Name | Version |\n")
    report.append("|-------|---------------|----------|\n")

    # Sort by score descending
    selected.sort(key=lambda x: x['score'], reverse=True)

    for wf in selected:
        base_name, version = extract_base_name_and_version(wf['filename'])
        version_display = f"v{version.replace('_', '.')}" if version != "0" else "-"
        report.append(f"| {wf['score']} | {base_name} | {version_display} |\n")

    report.append("\n---\n\n")
    report.append("## Domain Coverage\n\n")

    # Count domains from filenames
    domains = defaultdict(int)
    domain_keywords = {
        'chip': 'ChIP-seq',
        'atac': 'ATAC-seq',
        'cut': 'CUT&RUN/CUT&Tag',
        'rna': 'RNA-seq',
        'vgp': 'Genome Assembly (VGP)',
        'assembly': 'Assembly',
        'covid': 'COVID-19',
        'bacterial': 'Bacterial Genomics',
        'metaproteomic': 'Metaproteomics',
        'scrna': 'Single-cell RNA-seq',
        'hic': 'Hi-C',
        'methylation': 'Methylation',
        'variant': 'Variant Calling',
    }

    for wf in selected:
        name_lower = wf['filename'].lower()
        for keyword, domain in domain_keywords.items():
            if keyword in name_lower:
                domains[domain] += 1

    for domain, count in sorted(domains.items(), key=lambda x: -x[1]):
        report.append(f"- **{domain}:** {count}\n")

    report.append("\n---\n\n")
    report.append("## Removed Duplicates (Older Versions)\n\n")
    report.append("These are older versions that were superseded by newer releases:\n\n")

    for wf in duplicates[:50]:  # Show first 50
        base_name, version = extract_base_name_and_version(wf['filename'])
        report.append(f"- {base_name} v{version} (score: {wf['score']})\n")

    if len(duplicates) > 50:
        report.append(f"\n... and {len(duplicates) - 50} more\n")

    # Write report
    with open(report_path, 'w') as f:
        f.write(''.join(report))

    print(f"\nReport saved to: {report_path}")


if __name__ == "__main__":
    deduplicate_workflows()
