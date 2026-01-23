#!/usr/bin/env python3
"""ELBO loss for variational inference."""
import sys
import json
import numpy as np

def elbo_loss(reconstruction_loss, kl_divergence, beta=1.0):
    """Evidence Lower BOund loss: ELBO = reconstruction_loss + beta * KL_divergence
    Args: reconstruction_loss, kl_divergence, beta: KL weight
    """
    elbo = reconstruction_loss + beta * kl_divergence
    return {"elbo": float(elbo), "reconstruction": reconstruction_loss, "kl": kl_divergence, "beta": beta}

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
    result = elbo_loss(**args)
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == '__main__':
    main()
