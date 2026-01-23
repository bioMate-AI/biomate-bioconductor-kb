#!/usr/bin/env python3
"""
Wrapper script for one_site_model tool.
Reimplemented directly - no biomni dependency.
"""
import sys
import json
import numpy as np


def one_site_model(x, kd, dh, n):
    """One-site binding model for ITC data.

    Args:
        x: Molar ratio [ligand]/[protein]
        kd: Dissociation constant (M)
        dh: Enthalpy change (cal/mol)
        n: Stoichiometry

    Returns:
        Binding parameters and calculated heat
    """
    ka = 1 / kd  # Association constant
    # Simplified binding calculation
    theta = (ka * x) / (1 + ka * x)  # Fraction bound
    q = n * dh * theta  # Heat
    return {"heat": float(q), "fraction_bound": float(theta), "x": x, "kd": kd, "dh": dh, "n": n}


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
    result = one_site_model(**args)

    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2, default=str)

if __name__ == '__main__':
    main()
