#!/usr/bin/env python3
"""
Wrapper script for Biomni analyze_enzyme_kinetics_assay tool.
Auto-generated to fix inline Python code issues in Galaxy.
"""
import sys
import json
from biomni.tool.biochemistry import analyze_enzyme_kinetics_assay

def main():
    # Parse arguments
    args = {}
    i = 1
    while i < len(sys.argv):
        if sys.argv[i].startswith('--'):
            key = sys.argv[i][2:]
            if i + 1 < len(sys.argv) and not sys.argv[i + 1].startswith('--'):
                val = sys.argv[i + 1]
                # Type conversion
                if val.lower() == 'true':
                    val = True
                elif val.lower() == 'false':
                    val = False
                else:
                    try:
                        val = int(val)
                    except ValueError:
                        try:
                            val = float(val)
                        except ValueError:
                            pass
                args[key] = val
                i += 2
            else:
                args[key] = True
                i += 1
        else:
            i += 1

    # Get output path and remove from args
    output_path = args.pop('output', '/dev/stdout')

    # Handle list parameters - substrate_concentrations should be a list of floats
    if 'substrate_concentrations' in args and isinstance(args['substrate_concentrations'], str):
        args['substrate_concentrations'] = [float(x.strip()) for x in args['substrate_concentrations'].split(',')]

    # Handle time_points as list of floats
    if 'time_points' in args and isinstance(args['time_points'], str):
        args['time_points'] = [float(x.strip()) for x in args['time_points'].split(',')]

    # Handle modulators as JSON dict
    if 'modulators' in args and isinstance(args['modulators'], str):
        try:
            args['modulators'] = json.loads(args['modulators'])
        except json.JSONDecodeError:
            args['modulators'] = None

    # Call function
    result = analyze_enzyme_kinetics_assay(**args)

    # Write output
    with open(output_path, 'w') as f:
        if isinstance(result, str):
            f.write(result)
        elif isinstance(result, (dict, list)):
            json.dump(result, f, indent=2, default=str)
        else:
            f.write(str(result))

if __name__ == '__main__':
    main()
