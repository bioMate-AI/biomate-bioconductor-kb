#!/usr/bin/env python3
"""ProFam wrapper - Protein family language model for fitness prediction

ProFam-1 is a 251M-parameter autoregressive protein family language model.
Trained on concatenated, unaligned protein sequences from the same family.

CLI: python scripts/score_sequences.py (for scoring)
     python scripts/generate_sequences.py (for generation)
"""
import argparse
import os
import subprocess
import sys

# ProFam installation directory
PROFAM_DIR = os.environ.get("PROFAM_DIR", "/home/yzhang/biomate/tools_repos/profam")
CHECKPOINT_DIR = os.environ.get("PROFAM_CHECKPOINT", "/home/yzhang/biomate/models/profam")

# Virtual environment Python (prefer venv if available)
VENV_PYTHON = "/home/yzhang/biomate/backend/tools/biomate_ai_tools/.venv/bin/python"
PYTHON_EXE = VENV_PYTHON if os.path.exists(VENV_PYTHON) else sys.executable


def print_error(error_type, message, suggestion=None):
    """Print formatted error message."""
    print("\n" + "=" * 60, file=sys.stderr)
    print(f"ERROR: {error_type}", file=sys.stderr)
    print("=" * 60, file=sys.stderr)
    print(f"\n{message}\n", file=sys.stderr)
    if suggestion:
        print("WHAT TO DO:", file=sys.stderr)
        print(f"  {suggestion}\n", file=sys.stderr)


def run_score(args):
    """Score sequences using ProFam."""
    script = os.path.join(PROFAM_DIR, "scripts", "score_sequences.py")

    if not os.path.exists(script):
        print_error(
            "ProFam Not Installed",
            f"ProFam scripts not found at: {script}",
            "Clone the ProFam repository:\n"
            "  git clone https://github.com/judewells/ProFam-1.git"
        )
        sys.exit(1)

    cmd = [
        PYTHON_EXE, script,
        "--checkpoint_dir", CHECKPOINT_DIR,
        "--conditioning_fasta", args.input,
        "--save_dir", os.path.dirname(args.output) or ".",
    ]

    if args.candidates:
        cmd.extend(["--candidates_file", args.candidates])

    if args.device:
        cmd.extend(["--device", args.device])

    print(f"Running ProFam scoring...")
    print(f"Command: {' '.join(cmd)}")

    env = os.environ.copy()
    env["PYTHONPATH"] = f"{PROFAM_DIR}/src:{env.get('PYTHONPATH', '')}"

    result = subprocess.run(cmd, capture_output=True, text=True, env=env, cwd=PROFAM_DIR)

    if result.returncode != 0:
        stderr = result.stderr
        if "FileNotFoundError" in stderr or "checkpoint" in stderr.lower():
            print_error(
                "Model Not Found",
                f"ProFam checkpoint not found in: {CHECKPOINT_DIR}",
                "Download the model with:\n"
                "  python download_models.py --tool profam"
            )
        elif "OutOfMemory" in stderr or "CUDA" in stderr:
            print_error(
                "GPU Memory Error",
                "Not enough GPU memory to run ProFam.",
                "Try using --device cpu or reducing sequence length."
            )
        elif "ModuleNotFoundError" in stderr:
            print_error(
                "Missing Dependencies",
                f"Required Python packages not installed.\n\n{stderr[:500]}",
                "Install dependencies with:\n"
                "  pip install -r requirements.txt"
            )
        else:
            print_error("ProFam Error", stderr[:1000])
        sys.exit(1)

    print(result.stdout)
    print("Scoring complete!")


def run_generate(args):
    """Generate sequences using ProFam."""
    script = os.path.join(PROFAM_DIR, "scripts", "generate_sequences.py")

    if not os.path.exists(script):
        print_error(
            "ProFam Not Installed",
            f"ProFam scripts not found at: {script}",
            "Clone the ProFam repository:\n"
            "  git clone https://github.com/judewells/ProFam-1.git"
        )
        sys.exit(1)

    cmd = [
        PYTHON_EXE, script,
        "--checkpoint_dir", CHECKPOINT_DIR,
        "--conditioning_fasta", args.input,
        "--save_dir", os.path.dirname(args.output) or ".",
        "--num_sequences", str(args.num_sequences)
    ]

    if args.temperature:
        cmd.extend(["--temperature", str(args.temperature)])

    if args.device:
        cmd.extend(["--device", args.device])

    print(f"Running ProFam generation...")
    print(f"Command: {' '.join(cmd)}")

    env = os.environ.copy()
    env["PYTHONPATH"] = f"{PROFAM_DIR}/src:{env.get('PYTHONPATH', '')}"

    result = subprocess.run(cmd, capture_output=True, text=True, env=env, cwd=PROFAM_DIR)

    if result.returncode != 0:
        stderr = result.stderr
        if "FileNotFoundError" in stderr or "checkpoint" in stderr.lower():
            print_error(
                "Model Not Found",
                f"ProFam checkpoint not found in: {CHECKPOINT_DIR}",
                "Download the model with:\n"
                "  python download_models.py --tool profam"
            )
        elif "OutOfMemory" in stderr or "CUDA" in stderr:
            print_error(
                "GPU Memory Error",
                "Not enough GPU memory to run ProFam.",
                "Try using --device cpu or reducing num_sequences."
            )
        else:
            print_error("ProFam Error", stderr[:1000])
        sys.exit(1)

    print(result.stdout)
    print("Generation complete!")


def main():
    parser = argparse.ArgumentParser(
        description="ProFam: Protein family language model for fitness prediction",
        epilog="""
Examples:
  # Score protein variants
  python profam_wrapper.py --mode score --input family.fasta --candidates variants.fasta --output scores.csv

  # Generate new sequences
  python profam_wrapper.py --mode generate --input family.fasta --output generated.fasta --num_sequences 100
"""
    )
    parser.add_argument("--mode", choices=["score", "generate"], default="score",
                        help="Analysis mode (default: score)")
    parser.add_argument("--input", required=True, help="Input FASTA file (conditioning sequences)")
    parser.add_argument("--output", required=True, help="Output directory/file")
    parser.add_argument("--candidates", help="Candidate sequences to score (for score mode)")
    parser.add_argument("--num_sequences", type=int, default=10,
                        help="Number of sequences to generate (default: 10)")
    parser.add_argument("--temperature", type=float, default=1.0,
                        help="Sampling temperature (default: 1.0)")
    parser.add_argument("--device", default="cuda",
                        help="Device to use: cuda or cpu (default: cuda)")

    args = parser.parse_args()

    # Verify checkpoint directory exists
    if not os.path.exists(CHECKPOINT_DIR):
        print_error(
            "Model Not Installed",
            f"ProFam checkpoint directory not found: {CHECKPOINT_DIR}",
            "Download the model with:\n"
            "  python download_models.py --tool profam"
        )
        sys.exit(1)

    if args.mode == "score":
        run_score(args)
    else:
        run_generate(args)


if __name__ == "__main__":
    main()
