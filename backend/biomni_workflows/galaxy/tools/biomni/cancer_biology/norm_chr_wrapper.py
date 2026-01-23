#!/usr/bin/env python3
"""Normalize chromosome names."""
import sys
import json

def norm_chr(chrom):
    """Normalize chromosome name to standard format.
    Args: chrom: chromosome name (chr1, 1, Chr1, etc.)
    """
    chrom = str(chrom).strip()
    if chrom.lower().startswith('chr'):
        chrom = chrom[3:]
    # Handle special cases
    chrom = chrom.upper()
    if chrom in ['23', 'X']:
        normalized = 'chrX'
    elif chrom in ['24', 'Y']:
        normalized = 'chrY'
    elif chrom in ['25', 'M', 'MT']:
        normalized = 'chrM'
    else:
        normalized = f'chr{chrom}'
    return {"original": str(chrom), "normalized": normalized}

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
    result = norm_chr(**args)
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == '__main__':
    main()
