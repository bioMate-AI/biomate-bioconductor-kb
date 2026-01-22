#!/usr/bin/env python3
"""DrugCLIP local wrapper - Virtual screening

DrugCLIP is a contrastive learning framework for ultra-fast virtual screening.
10 million times faster than traditional docking methods.

Local repo: /home/yzhang/biomate/tools_repos/DrugCLIP
"""
import argparse
import os
import subprocess
import sys

# DrugCLIP installation directory
DRUGCLIP_DIR = os.environ.get("DRUGCLIP_DIR", "/home/yzhang/biomate/tools_repos/DrugCLIP")

def run_screening(args):
    """Run DrugCLIP virtual screening."""
    print("Running DrugCLIP virtual screening locally...")
    print(f"Target protein: {args.protein}")
    print(f"Compound library: {args.library}")

    cmd = [
        sys.executable, "-c",
        f"""
import sys
sys.path.insert(0, '{DRUGCLIP_DIR}')
from drugclip import DrugCLIP

model = DrugCLIP()
model.load_pretrained()

# Load protein
protein_embedding = model.encode_protein('{args.protein}')

# Screen compounds
results = model.screen(
    protein_embedding=protein_embedding,
    compound_file='{args.library}',
    top_k={args.top_k}
)

# Write results
with open('{args.output}', 'w') as f:
    f.write('rank\\tsmiles\\tscore\\n')
    for i, (smiles, score) in enumerate(results, 1):
        f.write(f'{{i}}\\t{{smiles}}\\t{{score:.4f}}\\n')

print(f'Screened {{len(results)}} compounds')
"""
    ]

    env = os.environ.copy()
    env["PYTHONPATH"] = f"{DRUGCLIP_DIR}:{env.get('PYTHONPATH', '')}"

    result = subprocess.run(cmd, capture_output=True, text=True, env=env, cwd=DRUGCLIP_DIR)

    if result.returncode != 0:
        print(f"Error: {result.stderr}", file=sys.stderr)
        sys.exit(1)

    print(result.stdout)
    print(f"Screening results written to {args.output}")

def run_embedding(args):
    """Generate embeddings for proteins or compounds."""
    print(f"Generating {args.embed_type} embeddings...")

    cmd = [
        sys.executable, "-c",
        f"""
import sys
import numpy as np
sys.path.insert(0, '{DRUGCLIP_DIR}')
from drugclip import DrugCLIP

model = DrugCLIP()
model.load_pretrained()

if '{args.embed_type}' == 'protein':
    embedding = model.encode_protein('{args.input}')
else:
    embedding = model.encode_compound('{args.input}')

np.save('{args.output}', embedding)
print(f'Embedding shape: {{embedding.shape}}')
"""
    ]

    env = os.environ.copy()
    env["PYTHONPATH"] = f"{DRUGCLIP_DIR}:{env.get('PYTHONPATH', '')}"

    result = subprocess.run(cmd, capture_output=True, text=True, env=env, cwd=DRUGCLIP_DIR)

    if result.returncode != 0:
        print(f"Error: {result.stderr}", file=sys.stderr)
        sys.exit(1)

    print(result.stdout)
    print(f"Embeddings saved to {args.output}")

def main():
    parser = argparse.ArgumentParser(description="DrugCLIP: Virtual screening")
    parser.add_argument("--mode", choices=["screen", "embed"], default="screen",
                        help="Operation mode")
    parser.add_argument("--protein", help="Target protein (PDB file or sequence)")
    parser.add_argument("--library", help="Compound library (SMILES file)")
    parser.add_argument("--input", help="Input file for embedding")
    parser.add_argument("--output", required=True, help="Output file")
    parser.add_argument("--top_k", type=int, default=100, help="Top K hits to return")
    parser.add_argument("--embed_type", choices=["protein", "compound"], default="protein",
                        help="Type of embedding")

    args = parser.parse_args()

    if args.mode == "screen":
        if not args.protein or not args.library:
            print("ERROR: --protein and --library required for screening", file=sys.stderr)
            sys.exit(1)
        run_screening(args)
    else:
        if not args.input:
            print("ERROR: --input required for embedding", file=sys.stderr)
            sys.exit(1)
        run_embedding(args)

if __name__ == "__main__":
    main()
