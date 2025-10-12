#!/usr/bin/env python3
"""
Galaxy wrapper for BioMni function: docking_autodock_vina
Source module: pharmacology
"""

import argparse
import sys
from biomni.tool.pharmacology import docking_autodock_vina


def main():
    parser = argparse.ArgumentParser(
        description="BioMni docking_autodock_vina wrapper"
    )

    parser.add_argument('--smiles_list', required=False)
    parser.add_argument('--receptor_pdb_file', required=False)
    parser.add_argument('--box_center', required=False)
    parser.add_argument('--box_size', required=False)
    parser.add_argument('--ncpu', required=False)

    args = parser.parse_args()

    # Call BioMni function
    try:
        result = docking_autodock_vina(smiles_list=args.smiles_list, receptor_pdb_file=args.receptor_pdb_file, box_center=args.box_center, box_size=args.box_size, ncpu=args.ncpu)
        print(f"Success: {result}")
        sys.exit(0)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
