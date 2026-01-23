#!/usr/bin/env python3
"""Generalized Lotka-Volterra equations."""
import sys
import json
import numpy as np

def glv_equations(populations, growth_rates, interaction_matrix):
    """GLV: dxi/dt = xi * (ri + sum_j(aij * xj))
    Args: populations: list, growth_rates: list, interaction_matrix: 2D list (as JSON string)
    """
    if isinstance(populations, str):
        populations = [float(x.strip()) for x in populations.split(',')]
    if isinstance(growth_rates, str):
        growth_rates = [float(x.strip()) for x in growth_rates.split(',')]
    if isinstance(interaction_matrix, str):
        interaction_matrix = json.loads(interaction_matrix)
    
    populations = np.array(populations)
    growth_rates = np.array(growth_rates)
    interaction_matrix = np.array(interaction_matrix)
    
    derivatives = populations * (growth_rates + interaction_matrix @ populations)
    return {"derivatives": derivatives.tolist(), "populations": populations.tolist()}

def main():
    args = {}
    i = 1
    while i < len(sys.argv):
        if sys.argv[i].startswith('--'):
            key = sys.argv[i][2:]
            if i + 1 < len(sys.argv) and not sys.argv[i + 1].startswith('--'):
                args[key] = sys.argv[i + 1]
                i += 2
            else:
                i += 1
        else:
            i += 1
    output_path = args.pop('output', '/dev/stdout')
    result = glv_equations(**args)
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == '__main__':
    main()
