#!/usr/bin/env python3
"""Default whole cell model parameters."""
import sys
import json

def default_whole_cell_model():
    """Return default whole cell model parameters.
    """
    return {
        "cell_volume": 1e-15,  # L (1 fL)
        "membrane_area": 1e-12,  # m^2
        "cytoplasm_viscosity": 1e-3,  # Pa.s
        "temperature": 310.15,  # K (37C)
        "ph": 7.2,
        "ionic_strength": 0.15,  # M
        "atp_concentration": 1e-3,  # M
        "note": "Default E. coli whole cell parameters"
    }

def main():
    args = {}
    i = 1
    while i < len(sys.argv):
        if sys.argv[i].startswith('--'):
            key = sys.argv[i][2:]
            if i + 1 < len(sys.argv) and not sys.argv[i + 1].startswith('--'):
                args[key] = sys.argv[i + 1]
                i += 2
            else:
                i += 1
        else:
            i += 1
    output_path = args.pop('output', '/dev/stdout')
    result = default_whole_cell_model(**args)
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == '__main__':
    main()
