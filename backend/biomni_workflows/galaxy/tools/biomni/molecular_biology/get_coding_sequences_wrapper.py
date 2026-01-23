#!/usr/bin/env python3
"""Extract coding sequences from DNA."""
import sys
import json
from Bio.Seq import Seq

def get_coding_sequences(sequence, min_length=100):
    """Extract all potential coding sequences (ORFs).
    Args: sequence: DNA, min_length: minimum CDS length
    """
    seq = sequence.upper()
    cds_list = []
    start_codon = "ATG"
    stop_codons = ["TAA", "TAG", "TGA"]
    
    for frame in range(3):
        i = frame
        while i < len(seq) - 2:
            if seq[i:i+3] == start_codon:
                for j in range(i+3, len(seq)-2, 3):
                    if seq[j:j+3] in stop_codons:
                        cds = seq[i:j+3]
                        if len(cds) >= min_length:
                            protein = str(Seq(cds).translate())
                            cds_list.append({"start": i, "end": j+3, "frame": frame+1, "cds": cds, "protein": protein})
                        break
            i += 3
    return {"coding_sequences": cds_list, "count": len(cds_list)}

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
    result = get_coding_sequences(**args)
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == '__main__':
    main()
