#!/usr/bin/env python3
"""Methane yield model for anaerobic digestion."""
import sys
import json

def methane_yield_model(substrate, yield_coefficient, inhibition_constant=None):
    """Methane yield: Y = Ymax * S / (Ks + S) with optional inhibition
    Args: substrate: concentration, yield_coefficient: max yield, inhibition_constant: optional Ki
    """
    if inhibition_constant:
        yield_val = yield_coefficient * substrate / (substrate + inhibition_constant)
    else:
        yield_val = yield_coefficient * substrate
    return {"methane_yield": float(yield_val), "substrate": substrate}

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
    result = methane_yield_model(**args)
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == '__main__':
    main()
