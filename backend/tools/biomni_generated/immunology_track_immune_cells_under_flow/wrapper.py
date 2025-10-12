#!/usr/bin/env python3
"""
Galaxy wrapper for BioMni function: track_immune_cells_under_flow
Source module: immunology
"""

import argparse
import sys
from biomni.tool.immunology import track_immune_cells_under_flow


def main():
    parser = argparse.ArgumentParser(
        description="BioMni track_immune_cells_under_flow wrapper"
    )

    parser.add_argument('--image_sequence_path', required=False)
    parser.add_argument('--output_dir', required=False)
    parser.add_argument('--pixel_size_um', required=False)
    parser.add_argument('--time_interval_sec', required=False)
    parser.add_argument('--flow_direction', required=False)

    args = parser.parse_args()

    # Call BioMni function
    try:
        result = track_immune_cells_under_flow(image_sequence_path=args.image_sequence_path, output_dir=args.output_dir, pixel_size_um=args.pixel_size_um, time_interval_sec=args.time_interval_sec, flow_direction=args.flow_direction)
        print(f"Success: {result}")
        sys.exit(0)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
