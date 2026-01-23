#!/usr/bin/env python3
"""Hamming distance between sequences."""
import sys
import json

def hamming_distance(seq1, seq2):
    """Count positions where sequences differ.
    Args: seq1, seq2: sequences of equal length
    """
    if len(seq1) != len(seq2):
        return {"error": "Sequences must be same length", "distance": -1}
    distance = sum(c1 != c2 for c1, c2 in zip(seq1, seq2))
    return {"distance": distance, "length": len(seq1), "identity": 1 - distance/len(seq1)}

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
    result = hamming_distance(**args)
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == '__main__':
    main()
