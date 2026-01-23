#!/usr/bin/env python3
"""
Wrapper script for reverse_complement tool.
Uses Biopython directly - no biomni dependency.
"""
import sys
import json
from Bio.Seq import Seq


def reverse_complement(seq: str) -> dict:
    """Get the reverse complement of a DNA sequence.

    Args:
        seq: DNA sequence string

    Returns:
        dict with original sequence, reverse complement, and metadata
    """
    seq_obj = Seq(seq.upper())
    rev_comp = str(seq_obj.reverse_complement())

    return {
        "original_sequence": str(seq_obj),
        "reverse_complement": rev_comp,
        "length": len(seq_obj)
    }


def main():
    # Parse arguments
    args = {}
    i = 1
    while i < len(sys.argv):
        if sys.argv[i].startswith('--'):
            key = sys.argv[i][2:]
            if i + 1 < len(sys.argv) and not sys.argv[i + 1].startswith('--'):
                val = sys.argv[i + 1]
                # Type conversion
                if val.lower() == 'true':
                    val = True
                elif val.lower() == 'false':
                    val = False
                else:
                    try:
                        val = int(val)
                    except ValueError:
                        try:
                            val = float(val)
                        except ValueError:
                            pass
                args[key] = val
                i += 2
            else:
                args[key] = True
                i += 1
        else:
            i += 1

    # Get output path and remove from args
    output_path = args.pop('output', '/dev/stdout')

    # Call function
    result = reverse_complement(**args)

    # Write output
    with open(output_path, 'w') as f:
        if isinstance(result, str):
            f.write(result)
        elif isinstance(result, (dict, list)):
            json.dump(result, f, indent=2, default=str)
        else:
            f.write(str(result))

if __name__ == '__main__':
    main()
