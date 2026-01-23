#!/usr/bin/env python3
"""Check if position is covered by regions."""
import sys
import json

def is_position_covered(position, regions):
    """Check if position falls within any region.
    Args: position: int, regions: list of (start, end) or JSON
    """
    if isinstance(regions, str):
        regions = json.loads(regions)
    for start, end in regions:
        if start <= position <= end:
            return {"covered": True, "position": position, "covering_region": [start, end]}
    return {"covered": False, "position": position}

def main():
    args = {}
    i = 1
    while i < len(sys.argv):
        if sys.argv[i].startswith('--'):
            key = sys.argv[i][2:]
            if i + 1 < len(sys.argv) and not sys.argv[i + 1].startswith('--'):
                val = sys.argv[i + 1]
                try:
                    val = int(val)
                except ValueError:
                    pass
                args[key] = val
                i += 2
            else:
                i += 1
        else:
            i += 1
    output_path = args.pop('output', '/dev/stdout')
    result = is_position_covered(**args)
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == '__main__':
    main()
