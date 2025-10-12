#!/usr/bin/env python3
"""
Galaxy wrapper for BioMni function: get_tool_by_id
Source module: tool_registry
"""

import argparse
import sys
from biomni.tool.tool_registry import get_tool_by_id


def main():
    parser = argparse.ArgumentParser(
        description="BioMni get_tool_by_id wrapper"
    )

    parser.add_argument('--self', required=False)
    parser.add_argument('--tool_id', required=False)

    args = parser.parse_args()

    # Call BioMni function
    try:
        result = get_tool_by_id(self=args.self, tool_id=args.tool_id)
        print(f"Success: {result}")
        sys.exit(0)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
