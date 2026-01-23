#!/usr/bin/env python3
"""Search for gene in sequence."""
import sys
import json
import re

def search_gene(sequence, pattern, case_sensitive=False):
    """Search for pattern in sequence.
    Args: sequence: DNA/RNA, pattern: regex or sequence, case_sensitive: bool
    """
    flags = 0 if case_sensitive else re.IGNORECASE
    matches = []
    for m in re.finditer(pattern, sequence, flags):
        matches.append({"start": m.start(), "end": m.end(), "match": m.group()})
    return {"matches": matches, "count": len(matches), "pattern": pattern}

def main():
    args = {}
    i = 1
    while i < len(sys.argv):
        if sys.argv[i].startswith('--'):
            key = sys.argv[i][2:]
            if i + 1 < len(sys.argv) and not sys.argv[i + 1].startswith('--'):
                val = sys.argv[i + 1]
                if val.lower() == 'true':
                    val = True
                elif val.lower() == 'false':
                    val = False
                args[key] = val
                i += 2
            else:
                i += 1
        else:
            i += 1
    output_path = args.pop('output', '/dev/stdout')
    result = search_gene(**args)
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == '__main__':
    main()
