#!/usr/bin/env python3
"""Merge overlapping genomic regions."""
import sys
import json

def merge_overlapping_regions(regions):
    """Merge overlapping regions.
    Args: regions: list of (start, end) tuples or JSON string
    """
    if isinstance(regions, str):
        regions = json.loads(regions)
    if not regions:
        return {"merged": [], "count": 0}
    
    sorted_regions = sorted(regions, key=lambda x: x[0])
    merged = [sorted_regions[0]]
    
    for start, end in sorted_regions[1:]:
        if start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
        else:
            merged.append((start, end))
    
    return {"merged": merged, "count": len(merged), "original_count": len(regions)}

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
    result = merge_overlapping_regions(**args)
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == '__main__':
    main()
