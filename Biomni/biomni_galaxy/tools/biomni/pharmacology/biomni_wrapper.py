#!/usr/bin/env python3
"""
Biomni Galaxy Wrapper Script

This script is called by Galaxy tool wrappers to execute Biomni functions.
"""

import argparse
import importlib
import json
import sys
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description='Execute Biomni function')
    parser.add_argument('--function', required=True, help='Function to call (domain.function_name)')
    parser.add_argument('--output', required=True, help='Output file path')

    # Parse known args, rest are function parameters
    args, unknown = parser.parse_known_args()

    # Parse function parameters
    func_args = {}
    i = 0
    while i < len(unknown):
        if unknown[i].startswith('--'):
            param_name = unknown[i][2:]
            if i + 1 < len(unknown) and not unknown[i + 1].startswith('--'):
                value = unknown[i + 1]
                # Try to parse as JSON for lists/dicts
                try:
                    value = json.loads(value)
                except:
                    # Try to convert to int/float/bool
                    if value.lower() == 'true':
                        value = True
                    elif value.lower() == 'false':
                        value = False
                    else:
                        try:
                            value = int(value)
                        except:
                            try:
                                value = float(value)
                            except:
                                pass
                func_args[param_name] = value
                i += 2
            else:
                # Flag without value (boolean)
                func_args[param_name] = True
                i += 1
        else:
            i += 1

    # Import and call the function
    domain, func_name = args.function.split('.')

    try:
        module = importlib.import_module(f'biomni.tool.{domain}')
        func = getattr(module, func_name)

        # Call function
        result = func(**func_args)

        # Write output
        with open(args.output, 'w') as f:
            if isinstance(result, str):
                f.write(result)
            elif isinstance(result, (dict, list)):
                json.dump(result, f, indent=2, default=str)
            else:
                f.write(str(result))

        print(f"Successfully executed {args.function}")

    except Exception as e:
        print(f"Error executing {args.function}: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
