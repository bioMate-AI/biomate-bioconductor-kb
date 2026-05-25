#!/usr/bin/env python3
"""scFv-pMPNN wrapper - Antibody scFv design using ProteinMPNN + AlphaFold2

Pipeline for converting antibodies to functional scFv intrabodies.
Uses ANARCI for CDR identification, ProteinMPNN for framework design, AF2 for validation.

Steps:
1. scFv-ification: Convert antibody to scFv (heavy + linker + light)
2. Framework optimization: Redesign framework using ProteinMPNN
3. Structure validation: Predict structure with AlphaFold2
"""
import argparse
import os
import subprocess
import sys
import tempfile

# Installation directories
SCFV_DIR = os.environ.get("SCFV_PMPNN_DIR", "/opt/biomate/tools_repos/scFv_Pmpnn_AF2")
PMPNN_DIR = os.environ.get("PROTEINMPNN_DIR", "/opt/biomate/tools_repos/ProteinMPNN")

def run_scfv_conversion(args):
    """Convert antibody heavy/light chains to scFv."""
    script = os.path.join(SCFV_DIR, "scripts", "scfv_anarci.py")

    cmd = [
        sys.executable, script,
        args.input,
        "--output", args.output.replace(".fasta", ""),
        "--linker-seq", args.linker
    ]

    print(f"Converting antibody to scFv...")
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=SCFV_DIR)

    if result.returncode != 0:
        print(f"Error: {result.stderr}", file=sys.stderr)
        sys.exit(1)

    print(result.stdout)
    return args.output

def run_framework_design(args):
    """Run ProteinMPNN framework design pipeline."""
    # Set up environment for the bash script
    env = os.environ.copy()
    env["PMPNN"] = PMPNN_DIR

    # Create a config for the pipeline
    config = f"""
folder_with_pdbs="{os.path.dirname(args.input)}"
seqs_per_run={args.num_designs}
determine_CDRs="{args.cdr_method}"
simple_grab=true
output_dir="{os.path.dirname(args.output)}"
to_design="framework"
PMPNN="{PMPNN_DIR}"
"""

    # Write config and run
    with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', delete=False) as f:
        f.write("#!/bin/bash\n")
        f.write(config)
        f.write(f"\nsource {os.path.join(SCFV_DIR, 'af2_pmpnn.sh')}\n")
        config_file = f.name

    print(f"Running ProteinMPNN framework design...")
    print(f"Number of designs: {args.num_designs}")
    print(f"CDR method: {args.cdr_method}")

    result = subprocess.run(["bash", config_file], capture_output=True, text=True, env=env, cwd=SCFV_DIR)

    os.remove(config_file)

    if result.returncode != 0:
        print(f"Error: {result.stderr}", file=sys.stderr)
        sys.exit(1)

    print(result.stdout)
    print("Framework design complete!")

def main():
    parser = argparse.ArgumentParser(description="scFv-pMPNN: Antibody design pipeline")
    parser.add_argument("--mode", choices=["convert", "design", "full"], default="design",
                        help="Pipeline mode")
    parser.add_argument("--input", required=True, help="Input FASTA (antibody) or PDB (structure)")
    parser.add_argument("--output", required=True, help="Output file")
    parser.add_argument("--linker", default="GGGGSGGGGSGGGGS", help="Linker sequence for scFv")
    parser.add_argument("--num_designs", type=int, default=10, help="Number of designs to generate")
    parser.add_argument("--cdr_method", choices=["martin", "kabat", "chothia", "structure"],
                        default="martin", help="CDR identification method")
    parser.add_argument("--temperature", type=float, default=0.1, help="ProteinMPNN sampling temperature")

    args = parser.parse_args()

    if args.mode == "convert":
        run_scfv_conversion(args)
    elif args.mode == "design":
        run_framework_design(args)
    else:  # full pipeline
        # First convert, then design
        scfv_output = args.output.replace(".fasta", "_scfv.fasta")
        args_convert = argparse.Namespace(**vars(args))
        args_convert.output = scfv_output
        run_scfv_conversion(args_convert)

        args.input = scfv_output
        run_framework_design(args)

if __name__ == "__main__":
    main()
