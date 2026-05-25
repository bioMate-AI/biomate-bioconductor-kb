#!/usr/bin/env python3
"""Chai-1 local wrapper - Structure prediction on GB10

Chai-1 is a multi-modal foundation model for molecular structure prediction.
Requires: 40-80 GB GPU VRAM (GB10 with 120GB unified memory is sufficient)

Set CHAI_DIR env var to the chai-lab repo path on the host.
"""
import argparse
import os
import subprocess
import sys

# Chai-lab installation directory — must be set per environment, no dev-path default.
CHAI_DIR = os.environ.get("CHAI_DIR", "/opt/biomate/tools_repos/chai-lab")

def run_prediction(args):
    """Run Chai-1 structure prediction locally."""
    print("Running Chai-1 structure prediction locally...")
    print(f"Input FASTA: {args.input}")

    # Build command using chai_lab module
    cmd = [
        sys.executable, "-m", "chai_lab",
        "--fasta", args.input,
        "--output-dir", os.path.dirname(args.output) or "."
    ]

    if args.num_trunk_recycles:
        cmd.extend(["--num-trunk-recycles", str(args.num_trunk_recycles)])

    if args.num_diffusion_timesteps:
        cmd.extend(["--num-diffusion-timesteps", str(args.num_diffusion_timesteps)])

    env = os.environ.copy()
    env["PYTHONPATH"] = f"{CHAI_DIR}:{env.get('PYTHONPATH', '')}"

    print(f"Command: {' '.join(cmd)}")

    result = subprocess.run(cmd, capture_output=True, text=True, env=env, cwd=CHAI_DIR)

    if result.returncode != 0:
        print(f"Error: {result.stderr}", file=sys.stderr)
        # Try alternative invocation
        print("Trying alternative invocation...")
        alt_cmd = [
            sys.executable, "-c",
            f"""
import sys
sys.path.insert(0, '{CHAI_DIR}')
from chai_lab.chai1 import run_inference
run_inference(
    fasta_file='{args.input}',
    output_dir='{os.path.dirname(args.output) or "."}',
    num_trunk_recycles={args.num_trunk_recycles or 3}
)
"""
        ]
        result = subprocess.run(alt_cmd, capture_output=True, text=True, env=env)
        if result.returncode != 0:
            print(f"Error: {result.stderr}", file=sys.stderr)
            sys.exit(1)

    print(result.stdout)
    print(f"Structure prediction complete! Output: {args.output}")

def main():
    parser = argparse.ArgumentParser(description="Chai-1: Local structure prediction")
    parser.add_argument("--input", required=True, help="Input FASTA file")
    parser.add_argument("--output", required=True, help="Output CIF file")
    parser.add_argument("--num_trunk_recycles", type=int, default=3, help="Number of trunk recycles")
    parser.add_argument("--num_diffusion_timesteps", type=int, default=200, help="Diffusion timesteps")

    args = parser.parse_args()
    run_prediction(args)

if __name__ == "__main__":
    main()
