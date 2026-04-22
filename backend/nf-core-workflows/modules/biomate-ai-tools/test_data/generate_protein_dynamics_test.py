#!/usr/bin/env python3
"""
generate_protein_dynamics_test.py

Generates a minimal synthetic protein test dataset for the protein_dynamics_ensemble
workflow validation:
  - protein_dynamics_test.pdb  : 50-residue synthetic alpha-helix in PDB format

Usage:
    python generate_protein_dynamics_test.py [--outdir test_data/]

Then upload to S3 and run on AWS Batch:
    nextflow run workflows/protein_dynamics_ensemble.nf \\
        -profile aws \\
        --pdb    s3://biomate-nextflow-work/test-inputs/protein-dynamics/protein_dynamics_test.pdb \\
        --n_samples 50 \\
        --outdir s3://biomate-nextflow-work/test-outputs/protein-dynamics/
"""

import argparse
import math
import os
import sys


def build_helix_pdb(n_residues: int = 50) -> str:
    """
    Generate a PDB-format string for a synthetic poly-alanine alpha-helix.

    Alpha-helix geometry:
        rise per residue: 1.5 Å
        radius:           2.3 Å
        twist per residue: 100°
    """
    lines = ["REMARK  Synthetic poly-Ala alpha-helix for BioMate test suite"]
    residues = ["ALA"] * n_residues

    # Backbone atom offsets within a residue (relative coords, Å)
    # N, CA, C, O positions along ideal helix
    backbone_atoms = [
        ("N",  -0.51, -0.77, 0.00),
        ("CA",  0.00,  0.00, 0.00),
        ("C",   1.52,  0.00, 0.00),
        ("O",   2.10,  1.06, 0.00),
        ("CB", -0.53,  0.78, -1.21),
    ]

    atom_serial = 1
    rise    = 1.5      # Å per residue along z-axis
    radius  = 2.3      # Å from helix axis
    twist   = math.radians(100.0)  # radians per residue

    for res_idx, res_name in enumerate(residues):
        angle = twist * res_idx
        cx = radius * math.cos(angle)
        cy = radius * math.sin(angle)
        cz = rise * res_idx

        for atom_name, dx, dy, dz in backbone_atoms:
            # Rotate local offset by helix angle around z
            local_x = dx * math.cos(angle) - dy * math.sin(angle)
            local_y = dx * math.sin(angle) + dy * math.cos(angle)
            local_z = dz

            x = cx + local_x
            y = cy + local_y
            z = cz + local_z

            element = atom_name[0]
            line = (
                f"ATOM  {atom_serial:5d} {atom_name:<4s} {res_name} A{res_idx+1:4d}    "
                f"{x:8.3f}{y:8.3f}{z:8.3f}  1.00  0.00          {element:>2s}  "
            )
            lines.append(line)
            atom_serial += 1

    lines.append("END")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--outdir",     default="test_data",
                        help="Output directory (default: test_data/)")
    parser.add_argument("--n-residues", type=int, default=50,
                        help="Number of residues in synthetic helix (default: 50)")
    args = parser.parse_args()

    os.makedirs(args.outdir, exist_ok=True)

    pdb_content = build_helix_pdb(args.n_residues)
    pdb_path    = os.path.join(args.outdir, "protein_dynamics_test.pdb")

    with open(pdb_path, "w") as fh:
        fh.write(pdb_content)

    atom_count = pdb_content.count("\nATOM")
    print(f"  Wrote {pdb_path}  ({args.n_residues} residues, {atom_count} atoms)")

    print()
    print("=" * 65)
    print("PROTEIN DYNAMICS TEST DATASET READY")
    print("=" * 65)
    print()
    print("AWS Batch (after uploading to S3):")
    print(f"  nextflow run workflows/protein_dynamics_ensemble.nf \\")
    print(f"    -profile aws \\")
    print(f"    --input_pdb s3://biomate-nextflow-work/test-inputs/protein-dynamics/protein_dynamics_test.pdb \\")
    print(f"    --n_samples 50 \\")
    print(f"    --outdir    s3://biomate-nextflow-work/test-outputs/protein-dynamics/")


if __name__ == "__main__":
    main()
