#!/usr/bin/env python3
"""RAS signaling pathway ODE system."""
import sys
import json

def ras_ode_system(ras_gdp, ras_gtp, gef_rate, gap_rate):
    """RAS cycle: RAS-GDP <-> RAS-GTP with GEF activation and GAP inactivation
    Args: ras_gdp, ras_gtp: concentrations, gef_rate: activation, gap_rate: inactivation
    """
    d_gdp = -gef_rate * ras_gdp + gap_rate * ras_gtp
    d_gtp = gef_rate * ras_gdp - gap_rate * ras_gtp
    return {"dRAS_GDP_dt": float(d_gdp), "dRAS_GTP_dt": float(d_gtp), "RAS_GDP": ras_gdp, "RAS_GTP": ras_gtp}

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
    result = ras_ode_system(**args)
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == '__main__':
    main()
