#!/usr/bin/env python3
"""Download model weights for Biomate AI Tools

This script downloads model weights from HuggingFace Hub for local tools.

Usage:
    python download_models.py --tool profam
    python download_models.py --tool state
    python download_models.py --all

Requirements:
    pip install huggingface_hub
"""
import argparse
import os
import sys
from pathlib import Path

try:
    from huggingface_hub import snapshot_download, hf_hub_download
except ImportError:
    print("ERROR: huggingface_hub required. Install with: pip install huggingface_hub")
    sys.exit(1)

# Model registry
MODELS = {
    "profam": {
        "repo_id": "judewells/ProFam-1",
        "size": "~1 GB",
        "description": "ProFam-1: 251M protein family language model",
        "target_dir": "profam",
    },
    "state": {
        "repo_id": "arcinstitute/SE-600M",
        "size": "~3 GB",
        "description": "STATE SE-600M: Cell state embedding model",
        "target_dir": "state",
    },
    "state_st": {
        "repo_id": "arcinstitute/ST-Tahoe100M",
        "size": "~2 GB",
        "description": "STATE ST: State transition model (Tahoe-100M)",
        "target_dir": "state/st",
    },
}

# Base model directory
DEFAULT_MODEL_DIR = os.environ.get(
    "BIOMATE_MODELS_DIR",
    "/home/yzhang/biomate/models"
)


def print_header(text):
    print("\n" + "=" * 60)
    print(text)
    print("=" * 60)


def print_available_models():
    print_header("Available Models")
    print()
    for name, info in MODELS.items():
        print(f"  {name:12} - {info['description']}")
        print(f"               Size: {info['size']}, Repo: {info['repo_id']}")
        print()


def download_model(name, model_dir=None):
    """Download a specific model."""
    if name not in MODELS:
        print(f"ERROR: Unknown model '{name}'")
        print(f"Available: {', '.join(MODELS.keys())}")
        return False

    info = MODELS[name]
    target_dir = Path(model_dir or DEFAULT_MODEL_DIR) / info["target_dir"]

    print_header(f"Downloading: {info['description']}")
    print(f"Repository: {info['repo_id']}")
    print(f"Size: {info['size']}")
    print(f"Target: {target_dir}")
    print()

    # Check if already downloaded
    if target_dir.exists() and any(target_dir.iterdir()):
        print(f"Model directory already exists: {target_dir}")
        response = input("Re-download? [y/N]: ").strip().lower()
        if response != 'y':
            print("Skipped.")
            return True

    target_dir.mkdir(parents=True, exist_ok=True)

    try:
        print("Downloading from HuggingFace Hub...")
        local_dir = snapshot_download(
            repo_id=info["repo_id"],
            local_dir=str(target_dir),
            local_dir_use_symlinks=False,
            ignore_patterns=["*.git*", "*.DS_Store"],
        )
        print(f"\nSUCCESS: Downloaded to {local_dir}")
        return True

    except Exception as e:
        print(f"\nERROR: Download failed: {e}")
        print("\nTroubleshooting:")
        print("  1. Check your internet connection")
        print("  2. Some models may require HuggingFace login:")
        print("     huggingface-cli login")
        print(f"  3. Check the repo exists: https://huggingface.co/{info['repo_id']}")
        return False


def download_all(model_dir=None):
    """Download all models."""
    print_header("Downloading All Models")

    total_size = sum(
        float(info['size'].replace('~', '').replace(' GB', ''))
        for info in MODELS.values()
    )
    print(f"Total estimated size: ~{total_size:.1f} GB")
    print()

    response = input("Continue? [y/N]: ").strip().lower()
    if response != 'y':
        print("Cancelled.")
        return

    results = {}
    for name in MODELS:
        results[name] = download_model(name, model_dir)

    print_header("Download Summary")
    for name, success in results.items():
        status = "✅" if success else "❌"
        print(f"  {status} {name}")


def main():
    parser = argparse.ArgumentParser(
        description="Download model weights for Biomate AI Tools"
    )
    parser.add_argument(
        "--tool",
        choices=list(MODELS.keys()),
        help="Specific tool to download"
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Download all models"
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List available models"
    )
    parser.add_argument(
        "--model-dir",
        default=DEFAULT_MODEL_DIR,
        help=f"Model directory (default: {DEFAULT_MODEL_DIR})"
    )

    args = parser.parse_args()

    if args.list:
        print_available_models()
    elif args.all:
        download_all(args.model_dir)
    elif args.tool:
        download_model(args.tool, args.model_dir)
    else:
        print("Usage:")
        print("  python download_models.py --list           # List models")
        print("  python download_models.py --tool profam    # Download specific")
        print("  python download_models.py --all            # Download all")
        print()
        print_available_models()


if __name__ == "__main__":
    main()
