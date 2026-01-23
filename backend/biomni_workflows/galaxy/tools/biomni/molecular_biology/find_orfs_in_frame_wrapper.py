#!/usr/bin/env python3
"""Find ORFs in a specific reading frame."""
import sys
import json
from Bio.Seq import Seq

def find_orfs_in_frame(sequence, frame=1, min_length=100):
    """Find ORFs in specified frame.
    Args: sequence: DNA, frame: 1,2,3, min_length: minimum ORF length in nt
    """
    start_codon = "ATG"
    stop_codons = ["TAA", "TAG", "TGA"]
    seq = sequence.upper()
    offset = frame - 1
    orfs = []
    
    i = offset
    while i < len(seq) - 2:
        codon = seq[i:i+3]
        if codon == start_codon:
            for j in range(i+3, len(seq)-2, 3):
                stop = seq[j:j+3]
                if stop in stop_codons:
                    orf_seq = seq[i:j+3]
                    if len(orf_seq) >= min_length:
                        orfs.append({"start": i, "end": j+3, "length": len(orf_seq), "sequence": orf_seq})
                    break
        i += 3
    return {"orfs": orfs, "count": len(orfs), "frame": frame}

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
    result = find_orfs_in_frame(**args)
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == '__main__':
    main()
