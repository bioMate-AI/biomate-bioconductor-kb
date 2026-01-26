#!/usr/bin/env python3
"""
Standardize parameter names across all biomni Nextflow workflows.

This script identifies and fixes parameter naming inconsistencies to improve
maintainability and test coverage.

Standard naming conventions:
- Sequences: dna_sequence, protein_sequence, rna_sequence (not seq, sequence)
- Enzymes: enzyme_names (list), enzyme_name (single) - not enzymes
- Genes: gene_names (list), gene_name (single) - not genes, gene_list
- Organism: organism (not species)
- Position: position (not pos)
- Circular: is_circular (not circular)
"""

import os
import re
import json
from pathlib import Path
from collections import defaultdict

NFCORE_DIR = Path(__file__).parent.parent
SUBWORKFLOWS_DIR = NFCORE_DIR / "subworkflows"

# Parameter standardization mappings
# Format: old_name -> new_name (only rename if it improves consistency)
PARAM_RENAMES = {
    # Sequence parameters - standardize to descriptive names
    "seq": "dna_sequence",  # Only for DNA workflows
    "seq_str": "dna_sequence",
    "enzymes": "enzyme_names",  # Standardize to enzyme_names for lists
    "genes": "gene_names",  # Standardize to gene_names for lists
    "gene_list": "gene_names",
    "species": "organism",  # Standardize to organism
    "pos": "position",  # Standardize to position
    "circular": "is_circular",  # Standardize boolean naming
}

# Context-specific renames (only apply in certain workflows)
CONTEXT_RENAMES = {
    # For reverse_complement, seq should become dna_sequence
    "molecular_biology/reverse_complement": {"seq": "dna_sequence"},
    # For find_orfs_in_frame, seq_str should become dna_sequence
    "molecular_biology/find_orfs_in_frame": {"seq_str": "dna_sequence"},
    # For find_restriction_sites, enzymes -> enzyme_names
    "molecular_biology/find_restriction_sites": {"enzymes": "enzyme_names"},
    # For is_position_covered, pos -> position
    "molecular_biology/is_position_covered": {"pos": "position"},
}


def find_param_declarations(content):
    """Find all parameter declarations in a Nextflow file."""
    pattern = r"params\.(\w+)\s*=\s*([^\n]+)"
    matches = re.findall(pattern, content)
    return {name: value.strip() for name, value in matches}


def find_param_usages(content, param_name):
    """Find all usages of a parameter in the file."""
    patterns = [
        rf"params\.{param_name}(?![a-zA-Z0-9_])",  # params.X
        rf'PARAM_{param_name.upper()}',  # PARAM_X environment variable
        rf'"{param_name}"',  # String reference
        rf"'{param_name}'",  # String reference
    ]

    usages = []
    for pattern in patterns:
        usages.extend(re.finditer(pattern, content))
    return usages


def rename_param_in_file(filepath, old_name, new_name, dry_run=True):
    """Rename a parameter in a Nextflow workflow file."""
    with open(filepath, 'r') as f:
        content = f.read()

    original_content = content

    # Replace parameter declaration
    content = re.sub(
        rf"params\.{old_name}(\s*=)",
        f"params.{new_name}\\1",
        content
    )

    # Replace parameter usage
    content = re.sub(
        rf"params\.{old_name}(?![a-zA-Z0-9_])",
        f"params.{new_name}",
        content
    )

    # Replace environment variable name
    content = re.sub(
        rf'PARAM_{old_name.upper()}',
        f'PARAM_{new_name.upper()}',
        content
    )

    # Replace in Python function signature (if present)
    content = re.sub(
        rf'\b{old_name}=auto_convert',
        f'{new_name}=auto_convert',
        content
    )

    # Replace in function definition
    content = re.sub(
        rf'def \w+\([^)]*\b{old_name}:',
        lambda m: m.group(0).replace(f'{old_name}:', f'{new_name}:'),
        content
    )

    if content != original_content:
        if dry_run:
            print(f"  Would rename: {old_name} -> {new_name}")
            return True
        else:
            with open(filepath, 'w') as f:
                f.write(content)
            print(f"  Renamed: {old_name} -> {new_name}")
            return True

    return False


def analyze_workflows():
    """Analyze all workflows and identify parameter inconsistencies."""
    inconsistencies = defaultdict(list)

    for domain_dir in SUBWORKFLOWS_DIR.iterdir():
        if not domain_dir.is_dir():
            continue

        for workflow_dir in domain_dir.iterdir():
            if not workflow_dir.is_dir():
                continue

            main_nf = workflow_dir / "main.nf"
            if not main_nf.exists():
                continue

            workflow_path = f"{domain_dir.name}/{workflow_dir.name}"

            with open(main_nf) as f:
                content = f.read()

            params = find_param_declarations(content)

            for old_name, new_name in PARAM_RENAMES.items():
                if old_name in params:
                    inconsistencies[old_name].append({
                        "workflow": workflow_path,
                        "current": old_name,
                        "suggested": new_name
                    })

    return inconsistencies


def standardize_workflows(dry_run=True):
    """Apply parameter standardization to all workflows."""
    print(f"{'[DRY RUN] ' if dry_run else ''}Standardizing parameters...")
    print("=" * 60)

    changes = []

    for domain_dir in sorted(SUBWORKFLOWS_DIR.iterdir()):
        if not domain_dir.is_dir():
            continue

        for workflow_dir in sorted(domain_dir.iterdir()):
            if not workflow_dir.is_dir():
                continue

            main_nf = workflow_dir / "main.nf"
            if not main_nf.exists():
                continue

            workflow_path = f"{domain_dir.name}/{workflow_dir.name}"

            with open(main_nf) as f:
                content = f.read()

            params = find_param_declarations(content)

            # Apply context-specific renames first
            if workflow_path in CONTEXT_RENAMES:
                for old_name, new_name in CONTEXT_RENAMES[workflow_path].items():
                    if old_name in params:
                        print(f"\n{workflow_path}:")
                        if rename_param_in_file(main_nf, old_name, new_name, dry_run):
                            changes.append({
                                "workflow": workflow_path,
                                "old": old_name,
                                "new": new_name
                            })

            # Then apply general renames
            for old_name, new_name in PARAM_RENAMES.items():
                if old_name in params and workflow_path not in CONTEXT_RENAMES:
                    print(f"\n{workflow_path}:")
                    if rename_param_in_file(main_nf, old_name, new_name, dry_run):
                        changes.append({
                            "workflow": workflow_path,
                            "old": old_name,
                            "new": new_name
                        })

    print("\n" + "=" * 60)
    print(f"Total changes: {len(changes)}")

    return changes


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Standardize parameter names in biomni workflows")
    parser.add_argument("--analyze", action="store_true", help="Only analyze, don't change")
    parser.add_argument("--apply", action="store_true", help="Apply changes (default is dry-run)")
    args = parser.parse_args()

    if args.analyze:
        print("Analyzing parameter inconsistencies...")
        print("=" * 60)
        inconsistencies = analyze_workflows()

        for old_name, occurrences in sorted(inconsistencies.items()):
            print(f"\n{old_name} -> {PARAM_RENAMES.get(old_name, '?')} ({len(occurrences)} workflows)")
            for occ in occurrences[:5]:  # Show first 5
                print(f"  - {occ['workflow']}")
            if len(occurrences) > 5:
                print(f"  ... and {len(occurrences) - 5} more")
    else:
        dry_run = not args.apply
        changes = standardize_workflows(dry_run)

        if dry_run and changes:
            print("\nRun with --apply to make these changes")


if __name__ == "__main__":
    main()
