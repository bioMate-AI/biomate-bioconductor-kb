#!/usr/bin/env python3
"""Bi-exponential model for two-compartment PK."""
import sys
import json
import numpy as np

def bi_exp_model(t, a, alpha, b, beta):
    """Bi-exponential: y = A*exp(-alpha*t) + B*exp(-beta*t)
    Args: t: time, a,alpha: fast phase params, b,beta: slow phase params
    """
    y = a * np.exp(-alpha * t) + b * np.exp(-beta * t)
    return {"value": float(y), "t": t, "a": a, "alpha": alpha, "b": b, "beta": beta}

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
    result = bi_exp_model(**args)
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == '__main__':
    main()
