#!/usr/bin/env python3
"""pick_first - lab automation helper."""
import sys
import json

def pick_first(**kwargs):
    """Lab automation helper: pick_first
    """
    return {"function": "pick_first", "status": "executed", "args": kwargs}

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
    result = pick_first(**args)
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == '__main__':
    main()
