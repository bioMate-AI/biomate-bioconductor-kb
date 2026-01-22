#!/usr/bin/env python3
"""Boltz-2 local wrapper - Structure prediction on GB10

Boltz-2 is a biomolecular foundation model for structure prediction.
Requires: 48+ GB GPU VRAM (GB10 with 120GB unified memory is sufficient)

Local repo: /home/yzhang/biomate/tools_repos/boltz
"""
import argparse
import os
import subprocess
import sys
import yaml

# Boltz installation directory
BOLTZ_DIR = os.environ.get("BOLTZ_DIR", "/home/yzhang/biomate/tools_repos/boltz")

def run_prediction(args):
    """Run Boltz-2 structure prediction locally."""

    # Read input YAML
    with open(args.input, 'r') as f:
        input_data = yaml.safe_load(f)

    print("Running Boltz-2 structure prediction locally...")
    print(f"Input: {args.input}")

    # Build command
    cmd = [
        sys.executable, "-m", "boltz",
        args.input,
        "--output-dir", os.path.dirname(args.output) or ".",
        "--output-name", os.path.basename(args.output).replace(".cif", "")
    ]

    if args.recycling_steps:
        cmd.extend(["--recycling-steps", str(args.recycling_steps)])

    if args.use_msa:
        cmd.append("--use-msa")

    env = os.environ.copy()
    env["PYTHONPATH"] = f"{BOLTZ_DIR}:{env.get('PYTHONPATH', '')}"

    print(f"Command: {' '.join(cmd)}")

    result = subprocess.run(cmd, capture_output=True, text=True, env=env, cwd=BOLTZ_DIR)

    if result.returncode != 0:
        print(f"Error: {result.stderr}", file=sys.stderr)
        sys.exit(1)

    print(result.stdout)
    print(f"Structure prediction complete! Output: {args.output}")

def main():
    parser = argparse.ArgumentParser(description="Boltz-2: Local structure prediction")
    parser.add_argument("--input", required=True, help="Input YAML specification")
    parser.add_argument("--output", required=True, help="Output CIF file")
    parser.add_argument("--recycling_steps", type=int, default=3, help="Number of recycling steps")
    parser.add_argument("--use_msa", action="store_true", help="Use MSA for prediction")

    args = parser.parse_args()
    run_prediction(args)

if __name__ == "__main__":
    main()
