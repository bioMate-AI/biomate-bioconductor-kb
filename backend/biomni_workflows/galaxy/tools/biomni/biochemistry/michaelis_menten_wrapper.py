#!/usr/bin/env python3
"""
Wrapper script for michaelis_menten tool.
Reimplemented directly - no biomni dependency.
"""
import sys
import json


def michaelis_menten(s, vmax, km):
    """Michaelis-Menten equation for enzyme kinetics.

    Args:
        s: Substrate concentration
        vmax: Maximum reaction velocity
        km: Michaelis constant

    Returns:
        Reaction velocity v = vmax * s / (km + s)
    """
    return {"velocity": vmax * s / (km + s), "s": s, "vmax": vmax, "km": km}

def main():
    # Parse arguments
    args = {}
    i = 1
    while i < len(sys.argv):
        if sys.argv[i].startswith('--'):
            key = sys.argv[i][2:]
            if i + 1 < len(sys.argv) and not sys.argv[i + 1].startswith('--'):
                val = sys.argv[i + 1]
                # Type conversion
                if val.lower() == 'true':
                    val = True
                elif val.lower() == 'false':
                    val = False
                else:
                    try:
                        val = int(val)
                    except ValueError:
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

    # Get output path and remove from args
    output_path = args.pop('output', '/dev/stdout')

    # Call function
    result = michaelis_menten(**args)

    # Write output
    with open(output_path, 'w') as f:
        if isinstance(result, str):
            f.write(result)
        elif isinstance(result, (dict, list)):
            json.dump(result, f, indent=2, default=str)
        else:
            f.write(str(result))

if __name__ == '__main__':
    main()
