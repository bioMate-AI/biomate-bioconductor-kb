#!/usr/bin/env python3
"""Cosinor model for circadian rhythm analysis."""
import sys
import json
import numpy as np

def cosinor_model(t, mesor, amplitude, acrophase, period=24):
    """Cosinor: y = mesor + amplitude * cos(2*pi*(t-acrophase)/period)
    Args: t: time, mesor: mean level, amplitude: oscillation amplitude, acrophase: peak time, period: cycle length
    """
    y = mesor + amplitude * np.cos(2 * np.pi * (t - acrophase) / period)
    return {"value": float(y), "t": t, "mesor": mesor, "amplitude": amplitude, "acrophase": acrophase}

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
    result = cosinor_model(**args)
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == '__main__':
    main()
