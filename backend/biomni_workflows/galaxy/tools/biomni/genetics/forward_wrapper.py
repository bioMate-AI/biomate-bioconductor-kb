#!/usr/bin/env python3
"""Forward pass for neural network."""
import sys
import json
import numpy as np

def forward(x, weights, bias, activation="relu"):
    """Simple forward pass: y = activation(W*x + b)
    Args: x: input (comma-sep), weights: matrix (JSON), bias: vector (comma-sep), activation: relu/sigmoid/tanh
    """
    if isinstance(x, str):
        x = np.array([float(v.strip()) for v in x.split(',')])
    if isinstance(weights, str):
        weights = np.array(json.loads(weights))
    if isinstance(bias, str):
        bias = np.array([float(v.strip()) for v in bias.split(',')])
    
    z = np.dot(weights, x) + bias
    if activation == "relu":
        y = np.maximum(0, z)
    elif activation == "sigmoid":
        y = 1 / (1 + np.exp(-z))
    elif activation == "tanh":
        y = np.tanh(z)
    else:
        y = z
    return {"output": y.tolist(), "pre_activation": z.tolist()}

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
    result = forward(**args)
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == '__main__':
    main()
