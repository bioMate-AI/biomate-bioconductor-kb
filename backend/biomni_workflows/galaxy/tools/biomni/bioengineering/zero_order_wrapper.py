#!/usr/bin/env python3
"""
Wrapper script for zero_order tool.
Reimplemented directly - no biomni dependency.
Drug release kinetics model.
"""
import sys
import json
import numpy as np

def zero_order(t, k0):
    """Zero-order drug release kinetics: Q = k0 * t
    Args: t: time, k0: zero-order rate constant
    """
    return {"release": float(k0 * t), "t": t, "k0": k0}


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
    func_name = list(globals().keys())
    for name in ['zero_order', 'first_order', 'higuchi', 'korsmeyer_peppas', 'exp_decay']:
        if name in globals():
            result = globals()[name](**args)
            break

    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2, default=str)

if __name__ == '__main__':
    main()
