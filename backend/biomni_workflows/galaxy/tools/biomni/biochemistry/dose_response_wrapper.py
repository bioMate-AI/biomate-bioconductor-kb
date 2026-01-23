#!/usr/bin/env python3
"""
Wrapper script for dose_response tool.
Reimplemented directly - no biomni dependency.
"""
import sys
import json
import numpy as np


def dose_response(x, ic50, hill):
    """Dose-response curve (Hill equation).

    Args:
        x: Concentration/dose
        ic50: Half-maximal inhibitory concentration
        hill: Hill coefficient (slope)

    Returns:
        Response value (0-1 scale, 1 = no inhibition, 0 = full inhibition)
    """
    response = 1 / (1 + (x / ic50) ** hill)
    return {"response": float(response), "x": x, "ic50": ic50, "hill": hill}


def main():
    args = {}
    i = 1
    while i < len(sys.argv):
        if sys.argv[i].startswith('--'):
            key = sys.argv[i][2:]
            if i + 1 < len(sys.argv) and not sys.argv[i + 1].startswith('--'):
                val = sys.argv[i + 1]
                if val.lower() == 'true':
                    val = True
                elif val.lower() == 'false':
                    val = False
                else:
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

    output_path = args.pop('output', '/dev/stdout')
    result = dose_response(**args)

    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2, default=str)

if __name__ == '__main__':
    main()
