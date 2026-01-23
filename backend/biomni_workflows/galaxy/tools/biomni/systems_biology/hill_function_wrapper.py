#!/usr/bin/env python3
"""Hill function for cooperative binding/regulation."""
import sys
import json

def hill_function(x, n, ec50):
    """Hill function: x^n / (ec50^n + x^n)
    Args: x: concentration, n: Hill coefficient, ec50: half-maximal concentration
    """
    return {"response": float((x ** n) / (ec50 ** n + x ** n)), "x": x, "n": n, "ec50": ec50}

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
    result = hill_function(**args)
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == '__main__':
    main()
