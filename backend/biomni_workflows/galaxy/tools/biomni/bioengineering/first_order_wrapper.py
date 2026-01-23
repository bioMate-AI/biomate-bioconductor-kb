#!/usr/bin/env python3
"""
Wrapper script for first_order tool.
Reimplemented directly - no biomni dependency.
Drug release kinetics model.
"""
import sys
import json
import numpy as np

def first_order(t, k1, q0):
    """First-order drug release kinetics: Q = Q0 * (1 - exp(-k1*t))
    Args: t: time, k1: first-order rate constant, q0: initial amount
    """
    return {"release": float(q0 * (1 - np.exp(-k1 * t))), "t": t, "k1": k1, "q0": q0}


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
