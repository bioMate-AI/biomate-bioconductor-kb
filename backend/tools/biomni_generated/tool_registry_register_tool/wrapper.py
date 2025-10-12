#!/usr/bin/env python3
"""
Galaxy wrapper for BioMni function: register_tool
Source module: tool_registry
"""

import argparse
import sys
from biomni.tool.tool_registry import register_tool


def main():
    parser = argparse.ArgumentParser(
        description="BioMni register_tool wrapper"
    )

    parser.add_argument('--self', required=False)
    parser.add_argument('--tool', required=False)

    args = parser.parse_args()

    # Call BioMni function
    try:
        result = register_tool(self=args.self, tool=args.tool)
        print(f"Success: {result}")
        sys.exit(0)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
