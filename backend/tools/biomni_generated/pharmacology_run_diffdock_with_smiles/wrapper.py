#!/usr/bin/env python3
"""
Galaxy wrapper for BioMni function: run_diffdock_with_smiles
Source module: pharmacology
"""

import argparse
import sys
from biomni.tool.pharmacology import run_diffdock_with_smiles


def main():
    parser = argparse.ArgumentParser(
        description="BioMni run_diffdock_with_smiles wrapper"
    )

    parser.add_argument('--pdb_path', required=False)
    parser.add_argument('--smiles_string', required=False)
    parser.add_argument('--local_output_dir', required=False)
    parser.add_argument('--gpu_device', required=False)
    parser.add_argument('--use_gpu', required=False)

    args = parser.parse_args()

    # Call BioMni function
    try:
        result = run_diffdock_with_smiles(pdb_path=args.pdb_path, smiles_string=args.smiles_string, local_output_dir=args.local_output_dir, gpu_device=args.gpu_device, use_gpu=args.use_gpu)
        print(f"Success: {result}")
        sys.exit(0)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
