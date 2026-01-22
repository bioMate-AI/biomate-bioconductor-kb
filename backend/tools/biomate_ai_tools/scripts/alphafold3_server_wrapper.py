#!/usr/bin/env python3
"""AlphaFold 3 Server wrapper - FREE structure prediction (20 jobs/day)

AlphaFold Server: https://alphafoldserver.com
- FREE to use
- 20 jobs per day limit
- No API key required
- Supports proteins, DNA, RNA, ligands, ions
"""
import argparse
import json
import os
import sys
import time

# Note: AlphaFold Server is web-based, this wrapper provides instructions
# and formats input for manual submission or future API integration

def format_for_server(args):
    """Format input for AlphaFold Server submission."""

    print("=" * 60)
    print("AlphaFold 3 Server - FREE Structure Prediction")
    print("=" * 60)
    print()
    print("Website: https://alphafoldserver.com")
    print("Limit: 20 jobs per day (FREE)")
    print()

    # Read input
    if args.input.endswith('.json'):
        with open(args.input, 'r') as f:
            input_data = json.load(f)
    elif args.input.endswith('.fasta') or args.input.endswith('.fa'):
        # Convert FASTA to JSON format
        sequences = []
        current_id = None
        current_seq = []

        with open(args.input, 'r') as f:
            for line in f:
                line = line.strip()
                if line.startswith('>'):
                    if current_id:
                        sequences.append({
                            "protein": {
                                "id": current_id,
                                "sequence": ''.join(current_seq)
                            }
                        })
                    current_id = line[1:].split()[0]
                    current_seq = []
                else:
                    current_seq.append(line)

            if current_id:
                sequences.append({
                    "protein": {
                        "id": current_id,
                        "sequence": ''.join(current_seq)
                    }
                })

        input_data = {"sequences": sequences}
    else:
        # Assume raw sequence
        with open(args.input, 'r') as f:
            seq = f.read().strip().replace('\n', '')
        input_data = {
            "sequences": [{"protein": {"id": "A", "sequence": seq}}]
        }

    # Display formatted input
    print("Input for AlphaFold Server:")
    print("-" * 40)

    for i, item in enumerate(input_data.get("sequences", []), 1):
        if "protein" in item:
            print(f"Chain {item['protein']['id']}: Protein")
            seq = item['protein']['sequence']
            print(f"  Sequence ({len(seq)} aa): {seq[:50]}...")
        elif "dna" in item:
            print(f"Chain {item['dna']['id']}: DNA")
            seq = item['dna']['sequence']
            print(f"  Sequence ({len(seq)} nt): {seq[:50]}...")
        elif "rna" in item:
            print(f"Chain {item['rna']['id']}: RNA")
            seq = item['rna']['sequence']
            print(f"  Sequence ({len(seq)} nt): {seq[:50]}...")
        elif "ligand" in item:
            print(f"Ligand {item['ligand']['id']}: {item['ligand'].get('smiles', item['ligand'].get('ccd', 'N/A'))}")

    print()
    print("Instructions:")
    print("1. Go to https://alphafoldserver.com")
    print("2. Sign in with Google account")
    print("3. Click 'New prediction'")
    print("4. Add entities (protein/DNA/RNA/ligand)")
    print("5. Paste sequences shown above")
    print("6. Click 'Predict' and wait for results")
    print()
    print("Results will be emailed when complete (usually minutes to hours)")
    print()

    # Save formatted input for reference
    output_json = args.output.replace('.cif', '_input.json')
    with open(output_json, 'w') as f:
        json.dump(input_data, f, indent=2)

    print(f"Input saved to: {output_json}")

    # Create placeholder output
    with open(args.output, 'w') as f:
        f.write("# AlphaFold 3 Server prediction\n")
        f.write("# Submit job at: https://alphafoldserver.com\n")
        f.write(f"# Input file: {output_json}\n")
        f.write("# Download result CIF from server when complete\n")

    print(f"Placeholder output: {args.output}")
    print()
    print("After downloading results from AlphaFold Server,")
    print(f"replace {args.output} with the downloaded CIF file.")

def main():
    parser = argparse.ArgumentParser(description="AlphaFold 3 Server (FREE)")
    parser.add_argument("--input", required=True,
                        help="Input file (JSON, FASTA, or raw sequence)")
    parser.add_argument("--output", required=True,
                        help="Output CIF file (placeholder until server result)")

    args = parser.parse_args()
    format_for_server(args)

if __name__ == "__main__":
    main()
