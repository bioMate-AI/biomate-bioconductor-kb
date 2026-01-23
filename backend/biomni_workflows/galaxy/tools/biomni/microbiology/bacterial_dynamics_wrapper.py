#!/usr/bin/env python3
"""Bacterial population dynamics ODE."""
import sys
import json
import numpy as np

def bacterial_dynamics(n, r, k, d):
    """Bacterial dynamics: dN/dt = r*N*(1-N/K) - d*N
    Args: n: population, r: growth rate, k: carrying capacity, d: death rate
    """
    dndt = r * n * (1 - n / k) - d * n
    return {"dN_dt": float(dndt), "N": n, "r": r, "K": k, "d": d}

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
    result = bacterial_dynamics(**args)
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == '__main__':
    main()
