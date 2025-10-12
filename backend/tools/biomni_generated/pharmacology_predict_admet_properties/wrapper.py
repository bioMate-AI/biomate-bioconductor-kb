#!/usr/bin/env python3
"""
Galaxy wrapper for BioMni function: predict_admet_properties
Source module: pharmacology
"""

import argparse
import sys
from biomni.tool.pharmacology import predict_admet_properties


def main():
    parser = argparse.ArgumentParser(
        description="BioMni predict_admet_properties wrapper"
    )

    parser.add_argument('--smiles_list', required=False)
    parser.add_argument('--ADMET_model_type', required=False)

    args = parser.parse_args()

    # Call BioMni function
    try:
        result = predict_admet_properties(smiles_list=args.smiles_list, ADMET_model_type=args.ADMET_model_type)
        print(f"Success: {result}")
        sys.exit(0)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
