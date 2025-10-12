#!/usr/bin/env python3
"""
Galaxy wrapper for BioMni function: retrieve_topk_repurposing_drugs_from_disease_txgnn
Source module: pharmacology
"""

import argparse
import sys
from biomni.tool.pharmacology import retrieve_topk_repurposing_drugs_from_disease_txgnn


def main():
    parser = argparse.ArgumentParser(
        description="BioMni retrieve_topk_repurposing_drugs_from_disease_txgnn wrapper"
    )

    parser.add_argument('--disease_name', required=False)
    parser.add_argument('--k', required=False)

    args = parser.parse_args()

    # Call BioMni function
    try:
        result = retrieve_topk_repurposing_drugs_from_disease_txgnn(disease_name=args.disease_name, k=args.k)
        print(f"Success: {result}")
        sys.exit(0)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
