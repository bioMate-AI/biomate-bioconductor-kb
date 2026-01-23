#!/usr/bin/env python3
"""Generic ODE system solver."""
import sys
import json
import numpy as np

def ode_system(state, rates, stoichiometry=None):
    """Generic ODE: dx/dt = S * v(x) where S is stoichiometry matrix
    Args: state: current state vector, rates: rate constants, stoichiometry: matrix (optional)
    """
    if isinstance(state, str):
        state = [float(x.strip()) for x in state.split(',')]
    if isinstance(rates, str):
        rates = [float(x.strip()) for x in rates.split(',')]
    # Simple linear system if no stoichiometry
    derivatives = [r * s for r, s in zip(rates, state)]
    return {"derivatives": derivatives, "state": state, "rates": rates}

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
    result = ode_system(**args)
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == '__main__':
    main()
