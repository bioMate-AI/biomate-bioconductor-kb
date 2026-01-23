#!/usr/bin/env python3
"""Gompertz growth model."""
import sys
import json
import numpy as np

def gompertz_model(t, a, b, c):
    """Gompertz: y = A * exp(-B * exp(-C*t))
    Args: t: time, a: asymptotic value, b: displacement, c: growth rate
    """
    y = a * np.exp(-b * np.exp(-c * t))
    return {"value": float(y), "t": t, "a": a, "b": b, "c": c}

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
    result = gompertz_model(**args)
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == '__main__':
    main()
