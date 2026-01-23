#!/usr/bin/env python3
"""Gene circuit ODE system for synthetic biology."""
import sys
import json
import numpy as np

def gene_circuit_odes(protein_level, production_rate, degradation_rate, inducer=0, hill_coef=2, k_half=1):
    """Gene circuit: dP/dt = production * (inducer^n / (K^n + inducer^n)) - degradation * P
    Args: protein_level: current level, production_rate, degradation_rate, inducer: inducer conc, hill_coef: cooperativity
    """
    if inducer > 0:
        activation = (inducer ** hill_coef) / (k_half ** hill_coef + inducer ** hill_coef)
    else:
        activation = 0
    dpdt = production_rate * activation - degradation_rate * protein_level
    return {"dP_dt": float(dpdt), "protein_level": protein_level, "activation": float(activation)}

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
    result = gene_circuit_odes(**args)
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == '__main__':
    main()
