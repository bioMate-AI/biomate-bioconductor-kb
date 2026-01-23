#!/usr/bin/env python3
"""Pharmacokinetics ODE system."""
import sys
import json
import numpy as np

def pk_ode_system(c, ka, ke, vd):
    """PK ODE: dC/dt = (ka*dose/Vd)*exp(-ka*t) - ke*C
    Args: c: concentration, ka: absorption rate, ke: elimination rate, vd: volume of distribution
    """
    dcdt = -ke * c  # Simplified elimination phase
    return {"dC_dt": float(dcdt), "C": c, "ka": ka, "ke": ke, "Vd": vd}

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
    result = pk_ode_system(**args)
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == '__main__':
    main()
