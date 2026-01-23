#!/usr/bin/env python3
"""Mass action kinetics for chemical reactions."""
import sys
import json

def mass_action_kinetics(k, concentrations):
    """Mass action kinetics: rate = k * product(concentrations)
    Args: k: rate constant, concentrations: list of reactant concentrations
    """
    import numpy as np
    if isinstance(concentrations, str):
        concentrations = [float(x.strip()) for x in concentrations.split(',')]
    rate = k * np.prod(concentrations)
    return {"rate": float(rate), "k": k, "concentrations": concentrations}

def main():
    args = {}
    i = 1
    while i < len(sys.argv):
        if sys.argv[i].startswith('--'):
            key = sys.argv[i][2:]
            if i + 1 < len(sys.argv) and not sys.argv[i + 1].startswith('--'):
                val = sys.argv[i + 1]
                try:
                    val = float(val)
                except ValueError:
                    pass
                args[key] = val
                i += 2
            else:
                i += 1
        else:
            i += 1
    output_path = args.pop('output', '/dev/stdout')
    result = mass_action_kinetics(**args)
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == '__main__':
    main()
