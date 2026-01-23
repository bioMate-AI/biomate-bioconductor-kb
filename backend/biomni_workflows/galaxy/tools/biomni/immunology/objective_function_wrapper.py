#!/usr/bin/env python3
"""Objective function for optimization."""
import sys
import json
import numpy as np

def objective_function(params, data, model_type="sum_squared"):
    """Objective function for fitting.
    Args: params: model parameters, data: observed values, model_type: SSE or other
    """
    if isinstance(params, str):
        params = [float(x.strip()) for x in params.split(',')]
    if isinstance(data, str):
        data = [float(x.strip()) for x in data.split(',')]
    # Simple SSE
    residuals = np.array(data) - np.array(params[:len(data)])
    sse = np.sum(residuals**2)
    return {"objective": float(sse), "residuals": residuals.tolist()}

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
    result = objective_function(**args)
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == '__main__':
    main()
