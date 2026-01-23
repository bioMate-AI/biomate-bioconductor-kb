#!/usr/bin/env python3
"""Check if region is fully covered."""
import sys
import json

def is_region_fully_covered(query_start, query_end, regions):
    """Check if query region is fully covered by other regions.
    Args: query_start, query_end, regions: list of (start, end)
    """
    if isinstance(regions, str):
        regions = json.loads(regions)
    # Merge regions first
    sorted_regions = sorted(regions, key=lambda x: x[0])
    merged = [list(sorted_regions[0])]
    for start, end in sorted_regions[1:]:
        if start <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], end)
        else:
            merged.append([start, end])
    
    for start, end in merged:
        if start <= query_start and end >= query_end:
            return {"fully_covered": True, "query": [query_start, query_end]}
    return {"fully_covered": False, "query": [query_start, query_end]}

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
    result = is_region_fully_covered(**args)
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == '__main__':
    main()
