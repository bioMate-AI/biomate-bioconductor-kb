#!/usr/bin/env python3
"""STATE wrapper - Virtual cell model for perturbation response prediction

STATE (State Transition) from Arc Institute predicts cellular responses to perturbations.
Uses pre-trained models from HuggingFace: arcinstitute/STATE

CLI: state tx infer (for perturbation prediction)
     state emb transform (for embedding)
"""
import argparse
import os
import subprocess
import sys

# Model paths (downloaded from HuggingFace)
MODEL_DIR = os.environ.get("STATE_MODEL_DIR", "/opt/biomate/models/state")
CHECKPOINT = os.environ.get("STATE_CHECKPOINT", "se600m_epoch16.ckpt")

# Virtual environment state CLI (prefer venv if available)
VENV_STATE = "/opt/biomate/backend/tools/biomate_ai_tools/.venv/bin/state"
STATE_CLI = VENV_STATE if os.path.exists(VENV_STATE) else "state"


def print_error(error_type, message, suggestion=None):
    """Print formatted error message."""
    print("\n" + "=" * 60, file=sys.stderr)
    print(f"ERROR: {error_type}", file=sys.stderr)
    print("=" * 60, file=sys.stderr)
    print(f"\n{message}\n", file=sys.stderr)
    if suggestion:
        print("WHAT TO DO:", file=sys.stderr)
        print(f"  {suggestion}\n", file=sys.stderr)


def run_perturbation_prediction(args):
    """Run STATE transition model for perturbation prediction."""
    # Build command
    cmd = [
        STATE_CLI, "tx", "infer",
        "--adata", args.input,
        "--model-dir", MODEL_DIR,
    ]

    # Output file
    if args.output:
        cmd.extend(["--output", args.output])

    # Checkpoint (use downloaded model)
    checkpoint_path = os.path.join(MODEL_DIR, CHECKPOINT)
    if os.path.exists(checkpoint_path):
        cmd.extend(["--checkpoint", checkpoint_path])

    # Perturbation column
    if args.perturbation_col:
        cmd.extend(["--pert-col", args.perturbation_col])

    # Cell type column
    if args.cell_type:
        cmd.extend(["--celltype-col", args.cell_type])

    # Embedding key
    if args.embed_key:
        cmd.extend(["--embed-key", args.embed_key])

    print(f"Running STATE perturbation prediction...")
    print(f"Command: {' '.join(cmd)}")

    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        stderr = result.stderr
        if "FileNotFoundError" in stderr or "not found" in stderr.lower():
            print_error(
                "Model Not Found",
                f"STATE model files not found in: {MODEL_DIR}",
                "Download the model with:\n"
                "  python download_models.py --tool state"
            )
        elif "KeyError" in stderr or "column" in stderr.lower():
            print_error(
                "Input Data Error",
                "Required columns not found in input AnnData file.\n\n"
                f"Details: {stderr[:500]}",
                "Check that your h5ad file has the expected columns.\n"
                "  Use --perturbation_col to specify the perturbation column."
            )
        elif "OutOfMemory" in stderr or "CUDA" in stderr:
            print_error(
                "GPU Memory Error",
                "Not enough GPU memory to run STATE.",
                "Try reducing batch size or using a smaller model."
            )
        else:
            print_error("STATE Error", stderr[:1000])
        sys.exit(1)

    print(result.stdout)
    print("Perturbation prediction complete!")


def run_embedding(args):
    """Run STATE embedding model to transform single-cell data."""
    cmd = [
        STATE_CLI, "emb", "transform",
        "--model-folder", MODEL_DIR,
        "--input", args.input,
        "--output", args.output
    ]

    # Checkpoint
    checkpoint_path = os.path.join(MODEL_DIR, CHECKPOINT)
    if os.path.exists(checkpoint_path):
        cmd.extend(["--checkpoint", checkpoint_path])

    # Gene column
    if args.gene_column:
        cmd.extend(["--gene-column", args.gene_column])

    print(f"Running STATE embedding...")
    print(f"Command: {' '.join(cmd)}")

    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        stderr = result.stderr
        if "FileNotFoundError" in stderr or "not found" in stderr.lower():
            print_error(
                "Model Not Found",
                f"STATE model files not found in: {MODEL_DIR}",
                "Download the model with:\n"
                "  python download_models.py --tool state"
            )
        else:
            print_error("STATE Error", stderr[:1000])
        sys.exit(1)

    print(result.stdout)
    print("Embedding complete!")


def main():
    parser = argparse.ArgumentParser(
        description="STATE: Virtual cell model for perturbation response prediction",
        epilog="""
Examples:
  # Perturbation prediction
  python state_wrapper.py --mode perturbation --input data.h5ad --output result.h5ad

  # Cell embedding
  python state_wrapper.py --mode embedding --input data.h5ad --output embeddings.h5ad
"""
    )
    parser.add_argument("--mode", choices=["perturbation", "embedding"], default="perturbation",
                        help="Analysis mode (default: perturbation)")
    parser.add_argument("--input", required=True, help="Input h5ad file")
    parser.add_argument("--output", required=True, help="Output h5ad file")
    parser.add_argument("--perturbation_col", help="Column containing perturbation labels")
    parser.add_argument("--cell_type", help="Cell type column for grouping")
    parser.add_argument("--embed_key", help="Key in adata.obsm for input features")
    parser.add_argument("--gene_column", help="Gene column name for embedding mode")

    args = parser.parse_args()

    # Verify model directory exists
    if not os.path.exists(MODEL_DIR):
        print_error(
            "Model Not Installed",
            f"STATE model directory not found: {MODEL_DIR}",
            "Download the model with:\n"
            "  python download_models.py --tool state"
        )
        sys.exit(1)

    if args.mode == "perturbation":
        run_perturbation_prediction(args)
    else:
        run_embedding(args)


if __name__ == "__main__":
    main()
