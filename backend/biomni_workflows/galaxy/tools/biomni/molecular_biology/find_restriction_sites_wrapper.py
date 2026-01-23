#!/usr/bin/env python3
"""
Wrapper script for find_restriction_sites tool.
Uses Biopython directly - no biomni dependency.
"""
import sys
import json
from Bio.Seq import Seq
from Bio import Restriction


def find_restriction_sites(dna_sequence: str, enzymes: list, is_circular: bool = True) -> dict:
    """Identifies restriction enzyme sites in a given DNA sequence for specified enzymes."""
    # Convert string to Bio.Seq object
    seq = Seq(dna_sequence.upper())

    # Create Analysis batch with specified enzymes
    rb = Restriction.RestrictionBatch(enzymes)

    # Analyze sequence for restriction sites, considering topology
    analysis = rb.search(seq, linear=not is_circular)

    results = {
        "explanation": (
            "Output fields:\n"
            "- sequence_info: Information about the input sequence\n"
            "  * length: Length of the sequence in base pairs\n"
            "  * is_circular: Whether sequence is circular or linear\n"
            "- restriction_sites: Dictionary of enzymes and their sites, where each contains:\n"
            "  * recognition_sequence: The DNA sequence the enzyme recognizes\n"
            "  * cut_positions: Details about where enzyme cuts relative to site\n"
            "    - 5_prime: Cut position on 5' strand relative to start of recognition site\n"
            "    - 3_prime: Cut position on 3' strand relative to start of recognition site\n"
            "    - overhang: Length of overhang produced (negative for 3' overhang)\n"
            "    - overhang_type: 'sticky' for overhanging cuts, 'blunt' for even cuts\n"
            "  * sites: List of positions where enzyme cuts in the sequence (0-based)"
        ),
        "sequence_info": {
            "length": len(seq),
            "is_circular": is_circular,
        },
        "restriction_sites": {},
    }

    for enzyme, positions in analysis.items():
        if positions:
            enzyme_info = {
                "recognition_sequence": str(enzyme.elucidate()),
                "cut_positions": {
                    "5_prime": enzyme.fst5,
                    "3_prime": enzyme.fst3,
                    "overhang": enzyme.ovhg,
                    "overhang_type": "sticky" if enzyme.ovhg != 0 else "blunt",
                },
                "sites": sorted(positions),
            }
            results["restriction_sites"][str(enzyme)] = enzyme_info
        else:
            results["restriction_sites"][str(enzyme)] = {
                "recognition_sequence": str(enzyme.elucidate()),
                "cut_positions": {
                    "5_prime": enzyme.fst5,
                    "3_prime": enzyme.fst3,
                    "overhang": enzyme.ovhg,
                    "overhang_type": "sticky" if enzyme.ovhg != 0 else "blunt",
                },
                "sites": [],
            }

    return results


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

    # Handle list parameters - enzymes should be a list
    if 'enzymes' in args and isinstance(args['enzymes'], str):
        args['enzymes'] = [e.strip() for e in args['enzymes'].split(',')]

    # Call function
    result = find_restriction_sites(**args)

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
