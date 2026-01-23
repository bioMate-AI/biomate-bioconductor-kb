#!/usr/bin/env python3
"""Simulate cell population dynamics."""
import sys
import json
import numpy as np

def simulate_cell_population(initial_count, growth_rate, death_rate, time_points):
    """Simulate: dN/dt = (growth - death) * N
    Args: initial_count, growth_rate, death_rate, time_points (comma-separated)
    """
    if isinstance(time_points, str):
        time_points = [float(x.strip()) for x in time_points.split(',')]
    
    net_rate = growth_rate - death_rate
    populations = [initial_count * np.exp(net_rate * t) for t in time_points]
    return {"time_points": time_points, "populations": populations, "net_growth_rate": net_rate}

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
    result = simulate_cell_population(**args)
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2, default=str)

if __name__ == '__main__':
    main()
