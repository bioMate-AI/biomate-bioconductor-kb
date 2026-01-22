#!/usr/bin/env python3
"""Evo 2 local wrapper - DNA foundation model

Evo 2 is a 40B parameter DNA foundation model trained on 9 trillion nucleotides.
WARNING: Low accuracy reported on Blackwell hardware (GB10) - use 7B model instead!

Local repo: /home/yzhang/biomate/tools_repos/evo2
"""
import argparse
import os
import subprocess
import sys

# Evo 2 installation directory
EVO2_DIR = os.environ.get("EVO2_DIR", "/home/yzhang/biomate/tools_repos/evo2")

def run_generation(args):
    """Run Evo 2 DNA generation."""
    print("Running Evo 2 DNA generation locally...")
    print(f"Model: {args.model}")

    if args.model == "evo2_40b" and "blackwell" in os.popen("nvidia-smi").read().lower():
        print("WARNING: Low accuracy reported on Blackwell hardware for 40B model!")
        print("Consider using evo2_7b instead.")

    # Read input sequence if provided
    prompt_seq = ""
    if args.input:
        with open(args.input, 'r') as f:
            for line in f:
                if not line.startswith('>'):
                    prompt_seq += line.strip()

    cmd = [
        sys.executable, "-c",
        f"""
import sys
sys.path.insert(0, '{EVO2_DIR}')
from evo2 import Evo2

model = Evo2('{args.model}')
sequence = model.generate(
    prompt='{prompt_seq}',
    n_tokens={args.n_tokens},
    temperature={args.temperature},
    top_k={args.top_k}
)
print(sequence)
"""
    ]

    env = os.environ.copy()
    env["PYTHONPATH"] = f"{EVO2_DIR}:{env.get('PYTHONPATH', '')}"

    print(f"Generating {args.n_tokens} nucleotides...")

    result = subprocess.run(cmd, capture_output=True, text=True, env=env, cwd=EVO2_DIR)

    if result.returncode != 0:
        print(f"Error: {result.stderr}", file=sys.stderr)
        sys.exit(1)

    # Write output
    with open(args.output, 'w') as f:
        f.write(f">evo2_generated\n")
        f.write(result.stdout.strip())

    print(f"Generated sequence written to {args.output}")

def run_scoring(args):
    """Score DNA sequences with Evo 2."""
    print("Running Evo 2 sequence scoring...")

    cmd = [
        sys.executable, "-c",
        f"""
import sys
sys.path.insert(0, '{EVO2_DIR}')
from evo2 import Evo2

model = Evo2('{args.model}')

# Read sequences
sequences = []
with open('{args.input}', 'r') as f:
    current_id = None
    current_seq = []
    for line in f:
        line = line.strip()
        if line.startswith('>'):
            if current_id:
                sequences.append((current_id, ''.join(current_seq)))
            current_id = line[1:]
            current_seq = []
        else:
            current_seq.append(line)
    if current_id:
        sequences.append((current_id, ''.join(current_seq)))

# Score sequences
with open('{args.output}', 'w') as f:
    f.write('seq_id\\tscore\\tperplexity\\n')
    for seq_id, seq in sequences:
        score = model.score(seq)
        f.write(f'{{seq_id}}\\t{{score:.4f}}\\t{{2**(-score):.4f}}\\n')
"""
    ]

    env = os.environ.copy()
    env["PYTHONPATH"] = f"{EVO2_DIR}:{env.get('PYTHONPATH', '')}"

    result = subprocess.run(cmd, capture_output=True, text=True, env=env, cwd=EVO2_DIR)

    if result.returncode != 0:
        print(f"Error: {result.stderr}", file=sys.stderr)
        sys.exit(1)

    print(result.stdout)
    print(f"Scores written to {args.output}")

def main():
    parser = argparse.ArgumentParser(description="Evo 2: DNA foundation model")
    parser.add_argument("--mode", choices=["generate", "score"], default="generate",
                        help="Operation mode")
    parser.add_argument("--model", choices=["evo2_7b", "evo2_40b", "evo2_1b_base"],
                        default="evo2_7b", help="Model variant (use 7b on GB10!)")
    parser.add_argument("--input", help="Input FASTA file (optional for generation)")
    parser.add_argument("--output", required=True, help="Output file")
    parser.add_argument("--n_tokens", type=int, default=1000, help="Number of tokens to generate")
    parser.add_argument("--temperature", type=float, default=1.0, help="Sampling temperature")
    parser.add_argument("--top_k", type=int, default=50, help="Top-k sampling")

    args = parser.parse_args()

    if args.mode == "generate":
        run_generation(args)
    else:
        if not args.input:
            print("ERROR: --input required for scoring mode", file=sys.stderr)
            sys.exit(1)
        run_scoring(args)

if __name__ == "__main__":
    main()
