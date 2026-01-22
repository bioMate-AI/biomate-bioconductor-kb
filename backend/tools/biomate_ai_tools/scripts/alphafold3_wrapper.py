#!/usr/bin/env python3
"""AlphaFold 3 local wrapper - Structure prediction

AlphaFold 3 predicts structures of biomolecular complexes.
Officially supports only A100/H100 - GB10 compatibility needs testing.

Local repo: /home/yzhang/biomate/tools_repos/alphafold3
"""
import argparse
import json
import os
import subprocess
import sys

# AlphaFold 3 installation directory
AF3_DIR = os.environ.get("ALPHAFOLD3_DIR", "/home/yzhang/biomate/tools_repos/alphafold3")
AF3_DATA = os.environ.get("ALPHAFOLD3_DATA", "/home/yzhang/biomate/data/alphafold3")

def run_prediction(args):
    """Run AlphaFold 3 structure prediction locally."""
    print("Running AlphaFold 3 structure prediction locally...")
    print(f"Input: {args.input}")
    print("WARNING: Only A100/H100 officially supported. GB10 needs testing.")

    # Read input JSON
    with open(args.input, 'r') as f:
        input_data = json.load(f)

    # Build command
    cmd = [
        sys.executable, os.path.join(AF3_DIR, "run_alphafold.py"),
        "--json_path", args.input,
        "--output_dir", os.path.dirname(args.output) or ".",
        "--db_dir", AF3_DATA,
        "--model_dir", os.path.join(AF3_DIR, "models")
    ]

    if args.num_seeds:
        cmd.extend(["--num_seeds", str(args.num_seeds)])

    if args.flash_attention:
        cmd.append("--flash_attention_implementation=triton")

    env = os.environ.copy()
    env["PYTHONPATH"] = f"{AF3_DIR}:{env.get('PYTHONPATH', '')}"
    env["XLA_PYTHON_CLIENT_MEM_FRACTION"] = "0.9"

    print(f"Command: {' '.join(cmd)}")

    result = subprocess.run(cmd, capture_output=True, text=True, env=env, cwd=AF3_DIR)

    if result.returncode != 0:
        print(f"Error: {result.stderr}", file=sys.stderr)
        print("\nNote: AlphaFold 3 requires:")
        print("  - A100 or H100 GPU (GB10 not officially supported)")
        print("  - ~1 TB genetic database files")
        print("  - CUDA 12.3+")
        print("\nConsider using AlphaFold Server (alphafoldserver.com) instead.")
        sys.exit(1)

    print(result.stdout)
    print(f"Structure prediction complete! Output: {args.output}")

def main():
    parser = argparse.ArgumentParser(description="AlphaFold 3: Local structure prediction")
    parser.add_argument("--input", required=True, help="Input JSON specification")
    parser.add_argument("--output", required=True, help="Output CIF file")
    parser.add_argument("--num_seeds", type=int, default=1, help="Number of random seeds")
    parser.add_argument("--flash_attention", action="store_true", help="Use flash attention")

    args = parser.parse_args()
    run_prediction(args)

if __name__ == "__main__":
    main()
