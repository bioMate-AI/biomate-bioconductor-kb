#!/usr/bin/env python3
"""ProTrek local wrapper - Trimodal protein language model

ProTrek unifies sequence, structure, and function through contrastive learning.
Enables advanced protein searches across 5B+ proteins.

Local repo: /opt/biomate/tools_repos/ProTrek
"""
import argparse
import os
import subprocess
import sys

# ProTrek installation directory
PROTREK_DIR = os.environ.get("PROTREK_DIR", "/opt/biomate/tools_repos/ProTrek")

def run_embedding(args):
    """Generate protein embeddings with ProTrek."""
    print(f"Generating {args.modality} embeddings...")

    cmd = [
        sys.executable, "-c",
        f"""
import sys
import numpy as np
sys.path.insert(0, '{PROTREK_DIR}')
from protrek import ProTrek

model = ProTrek()
model.load_pretrained()

# Read input
with open('{args.input}', 'r') as f:
    content = f.read()

if '{args.modality}' == 'sequence':
    embedding = model.encode_sequence(content)
elif '{args.modality}' == 'structure':
    embedding = model.encode_structure(content)
else:  # function
    embedding = model.encode_function(content)

np.save('{args.output}', embedding)
print(f'Embedding shape: {{embedding.shape}}')
"""
    ]

    env = os.environ.copy()
    env["PYTHONPATH"] = f"{PROTREK_DIR}:{env.get('PYTHONPATH', '')}"

    result = subprocess.run(cmd, capture_output=True, text=True, env=env, cwd=PROTREK_DIR)

    if result.returncode != 0:
        print(f"Error: {result.stderr}", file=sys.stderr)
        sys.exit(1)

    print(result.stdout)
    print(f"Embeddings saved to {args.output}")

def run_search(args):
    """Search proteins by function, sequence, or structure."""
    print(f"Searching proteins by {args.search_type}...")

    cmd = [
        sys.executable, "-c",
        f"""
import sys
sys.path.insert(0, '{PROTREK_DIR}')
from protrek import ProTrek

model = ProTrek()
model.load_pretrained()

# Read query
with open('{args.query}', 'r') as f:
    query = f.read().strip()

results = model.search(
    query=query,
    modality='{args.search_type}',
    database='{args.database}',
    top_k={args.top_k}
)

with open('{args.output}', 'w') as f:
    f.write('rank\\tprotein_id\\tscore\\tdescription\\n')
    for i, hit in enumerate(results, 1):
        f.write(f'{{i}}\\t{{hit["id"]}}\\t{{hit["score"]:.4f}}\\t{{hit.get("description", "")}}\\n')

print(f'Found {{len(results)}} proteins')
"""
    ]

    env = os.environ.copy()
    env["PYTHONPATH"] = f"{PROTREK_DIR}:{env.get('PYTHONPATH', '')}"

    result = subprocess.run(cmd, capture_output=True, text=True, env=env, cwd=PROTREK_DIR)

    if result.returncode != 0:
        print(f"Error: {result.stderr}", file=sys.stderr)
        sys.exit(1)

    print(result.stdout)
    print(f"Search results saved to {args.output}")

def main():
    parser = argparse.ArgumentParser(description="ProTrek: Trimodal protein model")
    parser.add_argument("--mode", choices=["embed", "search"], default="embed",
                        help="Operation mode")
    parser.add_argument("--input", help="Input file for embedding")
    parser.add_argument("--query", help="Query file for search")
    parser.add_argument("--output", required=True, help="Output file")
    parser.add_argument("--modality", choices=["sequence", "structure", "function"],
                        default="sequence", help="Modality for embedding")
    parser.add_argument("--search_type", choices=["function", "sequence", "structure"],
                        default="function", help="Search type")
    parser.add_argument("--database", choices=["uniprot", "ncbi", "mgnify"],
                        default="uniprot", help="Database to search")
    parser.add_argument("--top_k", type=int, default=100, help="Number of results")

    args = parser.parse_args()

    if args.mode == "embed":
        if not args.input:
            print("ERROR: --input required for embedding", file=sys.stderr)
            sys.exit(1)
        run_embedding(args)
    else:
        if not args.query:
            print("ERROR: --query required for search", file=sys.stderr)
            sys.exit(1)
        run_search(args)

if __name__ == "__main__":
    main()
