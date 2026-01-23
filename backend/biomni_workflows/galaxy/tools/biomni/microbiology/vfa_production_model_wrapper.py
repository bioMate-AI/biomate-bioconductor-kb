#!/usr/bin/env python3
"""VFA (Volatile Fatty Acids) production model."""
import sys
import json

def vfa_production_model(substrate, max_rate, ks):
    """VFA production: rate = Vmax * S / (Ks + S)
    Args: substrate: concentration, max_rate: Vmax, ks: half-saturation constant
    """
    rate = max_rate * substrate / (ks + substrate)
    return {"vfa_rate": float(rate), "substrate": substrate}

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
    result = vfa_production_model(**args)
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == '__main__':
    main()
