#!/usr/bin/env python3
"""Protein dimerization ODE system."""
import sys
import json

def dimerization_odes(monomer, dimer, kon, koff):
    """Dimerization: 2M <-> D with kon, koff
    Args: monomer: M conc, dimer: D conc, kon: association rate, koff: dissociation rate
    """
    dm_dt = -2 * kon * monomer**2 + 2 * koff * dimer
    dd_dt = kon * monomer**2 - koff * dimer
    return {"dM_dt": float(dm_dt), "dD_dt": float(dd_dt), "M": monomer, "D": dimer}

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
    result = dimerization_odes(**args)
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == '__main__':
    main()
