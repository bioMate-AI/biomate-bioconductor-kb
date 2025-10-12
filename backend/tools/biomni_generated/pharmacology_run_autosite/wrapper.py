#!/usr/bin/env python3
"""
Galaxy wrapper for BioMni function: run_autosite
Source module: pharmacology
"""

import argparse
import sys
from biomni.tool.pharmacology import run_autosite


def main():
    parser = argparse.ArgumentParser(
        description="BioMni run_autosite wrapper"
    )

    parser.add_argument('--pdb_file', required=False)
    parser.add_argument('--output_dir', required=False)
    parser.add_argument('--spacing', required=False)

    args = parser.parse_args()

    # Call BioMni function
    try:
        result = run_autosite(pdb_file=args.pdb_file, output_dir=args.output_dir, spacing=args.spacing)
        print(f"Success: {result}")
        sys.exit(0)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
