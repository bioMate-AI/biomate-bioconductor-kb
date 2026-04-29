#!/usr/bin/env python3
"""
Prepare cryoDRGN inputs from EMPIAR-10059 RELION star file.
Filters star file to only rows whose mrcs stack was downloaded (150 stacks),
then runs cryodrgn parse_star to produce particles.mrcs + ctf.pkl.

Usage:
  python prepare_cryodrgn_inputs.py \
    --star    /tmp/cryo_pilot/empiar/10059/particles.star \
    --stacks  /tmp/cryo_pilot/empiar/10059/particles/ \
    --outdir  /tmp/cryo_pilot/cryodrgn_inputs/
"""

import argparse, os, subprocess, sys, re
from pathlib import Path


def filter_star(star_path: str, stacks_dir: str, out_star: str):
    """Keep only rows whose mrcs file exists locally."""
    downloaded = {f.name for f in Path(stacks_dir).glob("*.mrcs")}
    print(f"  Downloaded stacks: {len(downloaded)}")

    with open(star_path) as f:
        lines = f.readlines()

    header, data = [], []
    in_loop = False
    img_col = None

    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith('_rln') or stripped.startswith('data_') \
                or stripped.startswith('loop_') or stripped == '':
            header.append(line)
            if '_rlnImageName' in stripped:
                # column index from the #N suffix
                m = re.search(r'#(\d+)', stripped)
                img_col = int(m.group(1)) - 1 if m else None
            if stripped.startswith('loop_'):
                in_loop = True
        elif in_loop:
            data.append(line)

    if img_col is None:
        sys.exit("Could not find _rlnImageName column in star file")

    kept = []
    for line in data:
        parts = line.split()
        if len(parts) <= img_col:
            continue
        # format: NNNNNN@Particles/micrographs/stack_XXXX_particles.mrcs
        img_ref = parts[img_col]
        mrcs_name = Path(img_ref.split('@')[-1]).name
        if mrcs_name in downloaded:
            # Rewrite path to local absolute path
            local_path = os.path.join(stacks_dir, mrcs_name)
            parts[img_col] = img_ref.split('@')[0] + '@' + local_path
            kept.append('\t'.join(parts) + '\n')

    print(f"  Particles kept: {len(kept)}")

    with open(out_star, 'w') as f:
        f.writelines(header)
        f.writelines(kept)
    print(f"  Filtered star written: {out_star}")


def run_parse_star(out_star: str, outdir: str, datadir: str):
    """Run cryodrgn parse_star to produce particles.txt + ctf.pkl."""
    os.makedirs(outdir, exist_ok=True)
    cmd = [
        "cryodrgn", "parse_star", out_star,
        "--datadir", datadir,
        "-o", os.path.join(outdir, "particles.txt"),
        "--ctf", os.path.join(outdir, "ctf.pkl"),
        "--Apix", "3.768",   # pixel size from EMPIAR-10059 metadata
    ]
    print(f"  Running: {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  WARN cryodrgn parse_star stderr: {result.stderr[-500:]}")
    else:
        print(f"  parse_star complete")
        print(result.stdout[-300:] if result.stdout else "")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--star',    required=True)
    ap.add_argument('--stacks',  required=True, help='Directory containing downloaded .mrcs files')
    ap.add_argument('--outdir',  required=True)
    args = ap.parse_args()

    os.makedirs(args.outdir, exist_ok=True)
    out_star = os.path.join(args.outdir, 'particles_filtered.star')

    print("Step 1: Filter star file to downloaded stacks ...")
    filter_star(args.star, args.stacks, out_star)

    print("Step 2: Run cryodrgn parse_star ...")
    run_parse_star(out_star, args.outdir, args.stacks)

    # Upload to S3 for cryoDRGN Batch job
    s3_dest = "s3://biomate-nextflow-work/pilot/cryodrgn_inputs/trpv1/"
    print(f"Step 3: Upload inputs to {s3_dest} ...")
    subprocess.run(["aws", "s3", "sync", args.outdir, s3_dest, "--quiet"], check=True)
    print(f"Done. Inputs at: {s3_dest}")


if __name__ == '__main__':
    main()
