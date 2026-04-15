#!/usr/bin/env python3
"""
inject_qc_defects.py — Build the QC Governance benchmark dataset.

Workflow:
    1. Download base datasets (GEO/ENCODE accessions)
    2. Inject controlled defects into FASTQ files
    3. Run QC tools (FastQC + MultiQC, nf-core QC pipeline, BioMate)
    4. Validate inter-rater labeling agreement
    5. Compute benchmark scores

Usage:
    python scripts/inject_qc_defects.py --download-only
    python scripts/inject_qc_defects.py --inject-all
    python scripts/inject_qc_defects.py --inject --dataset D1
    python scripts/inject_qc_defects.py --run-qc
    python scripts/inject_qc_defects.py --validate-labels labels.yaml
    python scripts/inject_qc_defects.py --all   # full pipeline

Requirements:
    - Docker (all tools run in containers — no local installs needed)
    - Python: pyyaml, requests

Docker images used (arm64 host — local images preferred):
    seqtk:        biomate/biotools:arm64-comprehensive   (arm64-native, /usr/local/bin/seqtk)
    multiqc:      biomate/biotools:comprehensive         (arm64-native, multiqc 1.32)
    fastqc:       quay.io/biocontainers/fastqc:0.12.1   (amd64/QEMU — Java works fine)
    fasterq-dump: biocontainers/mulled-v2-...            (amd64/QEMU — one-time download)
    sra-tools:    biocontainers/sra-tools:3.1.0          (amd64/QEMU — one-time download)

Output:
    evaluation/datasets/qc_governance/
    ├── samples/          FASTQ files (or symlinks if large — upload to S3)
    ├── qc_results/
    │   ├── multiqc/      MultiQC HTML + JSON per sample
    │   ├── nfcore/       nf-core QC stats
    │   └── biomate/      BioMate QC decisions (JSONL)
    └── labels.yaml       Expert ground truth (fill manually after running QC)
"""

import argparse
import os
import json
import subprocess
import sys
import textwrap
from pathlib import Path
from typing import Optional

import yaml


QC_DIR = Path(__file__).parent.parent / "datasets" / "qc_governance"
SAMPLES_DIR = QC_DIR / "samples"

# ─── Docker images for QC tools (ARM64 host) ──────────────────────────────────
#
# This machine is arm64. Images are chosen in preference order:
#   1. local arm64-native BioMate builds (no emulation, fastest)
#   2. public biocontainers under amd64 emulation (QEMU — slower but functional)
#
# seqtk: biomate/biotools:arm64-comprehensive is arm64-native, seqtk at /usr/local/bin/seqtk
#   confirmed: docker run --entrypoint /bin/bash biomate/biotools:arm64-comprehensive -c "which seqtk"
DOCKER_SEQTK = "biomate/biotools:arm64-comprehensive"
#
# MultiQC: biomate/biotools:comprehensive is arm64-native, multiqc 1.32 at /usr/local/bin/multiqc
#   confirmed: docker run --rm biomate/biotools:comprehensive multiqc --version
DOCKER_MULTIQC = "biomate/biotools:comprehensive"
#
# FastQC: no arm64-native local image has fastqc. Use the already-pulled amd64 image
#   under QEMU emulation — FastQC is Java-based and works fine under emulation.
#   Already on disk (614MB): docker images | grep fastqc
DOCKER_FASTQC = "quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0"
#
# fasterq-dump / sra-tools: not in any local image (arm64 or otherwise).
#   Run under amd64 QEMU emulation — acceptable since downloads are one-time.
#   Source: backend/nf-core-modules/modules/nf-core/sratools/fasterqdump/main.nf
DOCKER_FASTERQDUMP = (
    "biocontainers/mulled-v2-5f89fe0cd045cb1d615630b9261a1d17943a9b6a"
    ":2f4a4c900edd6801ff0068c2b3048b4459d119eb-0"
)
# backend/nf-core-modules/modules/nf-core/sratools/prefetch/main.nf
DOCKER_SRA_TOOLS = "biocontainers/sra-tools:3.1.0--h9f5acd7_0"


def docker_run(image: str, cmd: list[str], mounts: dict[str, str],
               env: dict[str, str] | None = None,
               workdir: str | None = None) -> subprocess.CompletedProcess:
    """
    Run a command inside a Docker container with the given bind mounts.

    Args:
        image:    Docker image name:tag
        cmd:      Command + args to run inside the container
        mounts:   {host_path: container_path} bind mounts (both must be absolute)
        env:      Optional environment variables to pass
        workdir:  Optional working directory inside the container

    Returns:
        CompletedProcess result
    """
    docker_cmd = ["docker", "run", "--rm"]

    for host_path, container_path in mounts.items():
        docker_cmd += ["-v", f"{host_path}:{container_path}"]

    if env:
        for k, v in env.items():
            docker_cmd += ["-e", f"{k}={v}"]

    if workdir:
        docker_cmd += ["-w", workdir]

    docker_cmd.append(image)
    docker_cmd.extend(cmd)

    return subprocess.run(docker_cmd, capture_output=False)
QC_RESULTS_DIR = QC_DIR / "qc_results"


# ─── Base datasets ────────────────────────────────────────────────────────────

BASE_DATASETS = {
    "D1": {
        "accession": "ENCSR000AED",
        "type": "rna_seq",
        "description": "RNA-seq GM12878 — clean reference; establishes baseline",
        "source": "ENCODE",
        "srr_ids": ["SRR628582", "SRR628583"],  # representative runs
    },
    "D2": {
        "accession": "GSE68086",
        "type": "ffpe_rna_seq",
        "description": "FFPE RNA-seq — protocol edge case: high degradation expected",
        "source": "GEO",
        "srr_ids": ["SRR2055010", "SRR2055011"],
    },
    "D3": {
        "accession": "GSE121893",
        "type": "scrna_seq",
        "description": "scRNA-seq cardiac — protocol edge case: low UMI expected",
        "source": "GEO",
        "srr_ids": ["SRR8206734", "SRR8206735"],
    },
    "D4": {
        "accession": "SRP047083",
        "type": "metagenomics_16s",
        "description": "Metagenomics soil — rRNA contamination risk",
        "source": "SRA",
        "srr_ids": ["SRR1519901", "SRR1519902"],
    },
    "D5": {
        "accession": "ENCSR356LIU",
        "type": "atac_seq",
        "description": "ATAC-seq — already flagged in original paper",
        "source": "ENCODE",
        "srr_ids": ["SRR3224798"],
    },
}


# ─── Defect injection specs ───────────────────────────────────────────────────

DEFECTS = [
    # Category A: Silent quality failures
    {
        "id": "rRNA_contamination_30pct",
        "category": "A",
        "description": "rRNA contamination at 30% of reads",
        "expected_action": "FAIL",
        "expected_fix": "Run rRNA depletion (RiboZero or similar)",
        "inject": lambda fq, out, tmp: _inject_rrna(fq, out, frac=0.30, tmp=tmp),
    },
    {
        "id": "adapter_dimers_15pct",
        "category": "A",
        "description": "Adapter dimers at 15% of reads",
        "expected_action": "FAIL",
        "expected_fix": "Apply adapter trimming (Trim Galore or fastp)",
        "inject": lambda fq, out, tmp: _inject_adapter_dimers(fq, out, frac=0.15),
    },
    {
        "id": "protocol_switch_3samples",
        "category": "A",
        "description": "Mid-cohort library prep label swap (3 samples mislabeled)",
        "expected_action": "WARN",
        "expected_fix": "Investigate batch effects; check library prep metadata",
        "inject": lambda fq, out, tmp: _inject_protocol_switch(fq, out),
    },
    # Category B: Near-threshold ambiguity
    {
        "id": "duplication_95pct_threshold",
        "category": "B",
        "description": "Duplication rate at 95% of threshold (should WARN not FAIL)",
        "expected_action": "WARN",
        "expected_fix": None,
        "inject": lambda fq, out, tmp: _inject_duplication(fq, out, pct=0.95),
    },
    {
        "id": "gc_content_2pct_above",
        "category": "B",
        "description": "GC content 2% above expected range",
        "expected_action": "WARN",
        "expected_fix": None,
        "inject": lambda fq, out, tmp: _inject_gc_skew(fq, out, delta=0.02),
    },
]


# ─── Download functions ───────────────────────────────────────────────────────

def download_dataset(dataset_id: str, dry_run: bool = False):
    """Download a base dataset using fasterq-dump in Docker."""
    ds = BASE_DATASETS[dataset_id]
    out_dir = SAMPLES_DIR / dataset_id / "raw"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_dir_abs = str(out_dir.resolve())

    print(f"  Downloading {dataset_id} ({ds['accession']})...")

    # SRA cache dir so prefetch/fasterq-dump can share the cache
    sra_cache = out_dir / ".sra_cache"
    sra_cache.mkdir(exist_ok=True)

    for srr in ds["srr_ids"]:
        fq_path = out_dir / f"{srr}_1.fastq.gz"
        if fq_path.exists():
            print(f"    {srr}: already downloaded")
            continue

        if dry_run:
            print(f"    [DRY RUN] docker run {DOCKER_FASTERQDUMP} fasterq-dump {srr}")
            continue

        # Step 1: prefetch SRA file (faster than streaming)
        print(f"    Prefetching {srr}...")
        prefetch_ret = docker_run(
            image=DOCKER_SRA_TOOLS,
            cmd=["prefetch", srr, "--output-directory", "/data/sra_cache"],
            mounts={out_dir_abs: "/data"},
        )
        if prefetch_ret.returncode != 0:
            print(f"    WARNING: prefetch failed for {srr} — trying fasterq-dump directly")

        # Step 2: fasterq-dump (uses mulled image with both fasterq-dump + pigz)
        print(f"    Running fasterq-dump {srr}...")
        fasterq_ret = docker_run(
            image=DOCKER_FASTERQDUMP,
            cmd=[
                "fasterq-dump", srr,
                "--outdir", "/data",
                "--split-files",
                "--threads", "4",
                "--progress",
            ],
            mounts={out_dir_abs: "/data"},
            workdir="/data",
        )
        if fasterq_ret.returncode != 0:
            print(f"    ERROR: fasterq-dump failed for {srr}")
            continue

        # Step 3: compress with gzip (available in the fasterq-dump mulled image)
        for f in out_dir.glob(f"{srr}*.fastq"):
            print(f"    Compressing {f.name}...")
            docker_run(
                image=DOCKER_FASTERQDUMP,
                cmd=["gzip", "-f", f"/data/{f.name}"],
                mounts={out_dir_abs: "/data"},
            )
            print(f"    {f.name}.gz")

    # Downsample to 1M reads using seqtk for faster QC testing
    for fq in sorted(out_dir.glob("*.fastq.gz")):
        if ".1M." in fq.name or fq.name.endswith(".1M.fastq.gz"):
            continue
        stem = fq.name.replace(".fastq.gz", "")
        small = out_dir / f"{stem}.1M.fastq.gz"
        if small.exists():
            continue
        if dry_run:
            print(f"    [DRY RUN] seqtk sample {fq.name} 1000000")
            continue

        print(f"    Downsampling {fq.name} → 1M reads...")
        # seqtk writes to stdout; pipe through gzip on the host.
        # biomate/biotools:arm64-comprehensive has a custom entrypoint — use --entrypoint.
        cmd = (
            f"docker run --rm --entrypoint seqtk -v {out_dir_abs}:/data {DOCKER_SEQTK} "
            f"sample -s 42 /data/{fq.name} 1000000 | gzip > {small}"
        )
        subprocess.run(cmd, shell=True)
        print(f"    {small.name}")


# ─── Defect injection functions ───────────────────────────────────────────────

def _inject_rrna(fastq_in: Path, fastq_out: Path, frac: float, tmp: Path):
    """Inject rRNA reads by replacing frac% of reads with simulated rRNA sequence."""
    # Use seqtk to sample reads to replace, then swap their sequences
    rRNA_seq = "AACGAACGCTGGCGGCATGCCTAACACATGCAAGTCGAACGGTAACAGGAAGCAGCTTGCTGCTTTGCTGACGAGTGGCGGACGGGTGAGTAATGTCTGG"

    cmd = f"""
    python3 -c "
import gzip, random, sys
random.seed(42)
frac = {frac}
with gzip.open('{fastq_in}', 'rt') as fin, gzip.open('{fastq_out}', 'wt') as fout:
    while True:
        lines = [fin.readline() for _ in range(4)]
        if not lines[0]:
            break
        if random.random() < frac:
            # Replace with rRNA-like sequence
            seq = '{rRNA_seq}'[:len(lines[1].strip())]
            qual = 'I' * len(seq)
            fout.write(lines[0])
            fout.write(seq + '\\n')
            fout.write('+\\n')
            fout.write(qual + '\\n')
        else:
            for l in lines:
                fout.write(l)
"
    """
    subprocess.run(cmd, shell=True, check=True)
    print(f"    Injected rRNA contamination ({frac:.0%}) → {fastq_out.name}")


def _inject_adapter_dimers(fastq_in: Path, fastq_out: Path, frac: float):
    """Inject adapter dimer reads."""
    adapter = "AGATCGGAAGAGCACACGTCTGAACTCCAGTCACNNNNNNATCTCGTATGCCGTCTTCTGCTTG"

    cmd = f"""
    python3 -c "
import gzip, random
random.seed(42)
frac = {frac}
adapter = '{adapter}'
with gzip.open('{fastq_in}', 'rt') as fin, gzip.open('{fastq_out}', 'wt') as fout:
    while True:
        lines = [fin.readline() for _ in range(4)]
        if not lines[0]:
            break
        if random.random() < frac:
            read_len = len(lines[1].strip())
            seq = (adapter * 2)[:read_len]
            qual = 'I' * read_len
            fout.write(lines[0])
            fout.write(seq + '\\n')
            fout.write('+\\n')
            fout.write(qual + '\\n')
        else:
            for l in lines:
                fout.write(l)
"
    """
    subprocess.run(cmd, shell=True, check=True)
    print(f"    Injected adapter dimers ({frac:.0%}) → {fastq_out.name}")


def _inject_protocol_switch(fastq_in: Path, fastq_out: Path):
    """Swap library prep metadata to simulate protocol switch."""
    import shutil
    shutil.copy2(fastq_in, fastq_out)
    # The 'defect' here is a metadata annotation swap, not sequence change
    meta_file = fastq_out.parent / "metadata_protocol_switch.json"
    meta_file.write_text(json.dumps({
        "injected_defect": "protocol_switch",
        "swapped_samples": ["sample_3", "sample_4", "sample_5"],
        "claimed_protocol": "poly_A_selection",
        "actual_protocol": "ribo_depletion",
        "note": "Samples 3-5 were processed with a different protocol but mislabeled",
    }, indent=2))
    print(f"    Injected protocol switch metadata → {meta_file.name}")


def _inject_duplication(fastq_in: Path, fastq_out: Path, pct: float = 0.95):
    """Create high-duplication sample by duplicating reads to ~95% of threshold."""
    cmd = f"""
    python3 -c "
import gzip
pct = {pct}
threshold = 0.50  # typical duplication threshold
target_dup = threshold * pct  # ~0.475 duplicate rate
with gzip.open('{fastq_in}', 'rt') as fin, gzip.open('{fastq_out}', 'wt') as fout:
    reads = []
    for _ in range(10000):
        lines = [fin.readline() for _ in range(4)]
        if not lines[0]:
            break
        reads.append(lines)
    n_reads = len(reads)
    n_dup = int(n_reads * target_dup)
    import random; random.seed(42)
    seed_reads = reads[:max(1, n_reads - n_dup)]
    dup_reads = random.choices(seed_reads, k=n_dup)
    all_reads = seed_reads + dup_reads
    random.shuffle(all_reads)
    for r in all_reads:
        for l in r:
            fout.write(l)
"
    """
    subprocess.run(cmd, shell=True, check=True)
    print(f"    Injected high duplication ({pct:.0%} of threshold) → {fastq_out.name}")


def _inject_gc_skew(fastq_in: Path, fastq_out: Path, delta: float = 0.02):
    """Replace delta fraction of reads with GC-skewed synthetic reads."""
    cmd = f"""
    python3 -c "
import gzip, random
random.seed(42)
delta = {delta}
# GC-skewed: 70% G/C, 30% A/T
def gc_read(length):
    return ''.join(random.choices('GCGCGCAT', k=length))
with gzip.open('{fastq_in}', 'rt') as fin, gzip.open('{fastq_out}', 'wt') as fout:
    while True:
        lines = [fin.readline() for _ in range(4)]
        if not lines[0]:
            break
        if random.random() < delta:
            read_len = len(lines[1].strip())
            seq = gc_read(read_len)
            qual = 'I' * read_len
            fout.write(lines[0])
            fout.write(seq + '\\n')
            fout.write('+\\n')
            fout.write(qual + '\\n')
        else:
            for l in lines:
                fout.write(l)
"
    """
    subprocess.run(cmd, shell=True, check=True)
    print(f"    Injected GC skew (+{delta:.0%}) → {fastq_out.name}")


# ─── QC pipeline functions ────────────────────────────────────────────────────

def run_fastqc_multiqc(sample_dir: Path, out_dir: Path):
    """Run FastQC + MultiQC on all FASTQ files in sample_dir using Docker."""
    fastqc_out = out_dir / "fastqc"
    fastqc_out.mkdir(parents=True, exist_ok=True)
    multiqc_out = out_dir / "multiqc"
    multiqc_out.mkdir(parents=True, exist_ok=True)

    fastqs = list(sample_dir.glob("*.fastq.gz"))
    if not fastqs:
        print(f"    No FASTQ files found in {sample_dir}")
        return

    sample_dir_abs = str(sample_dir.resolve())
    fastqc_out_abs = str(fastqc_out.resolve())
    multiqc_out_abs = str(multiqc_out.resolve())

    # FastQC — one container call per file (FastQC doesn't parallelise well across containers)
    print(f"    Running FastQC on {len(fastqs)} files (docker: {DOCKER_FASTQC})...")
    for fq in fastqs:
        ret = docker_run(
            image=DOCKER_FASTQC,
            cmd=[
                "fastqc",
                f"/input/{fq.name}",
                "--outdir", "/output",
                "--threads", "2",
            ],
            mounts={
                sample_dir_abs: "/input",
                fastqc_out_abs: "/output",
            },
        )
        if ret.returncode != 0:
            print(f"    FastQC failed for {fq.name}")

    # MultiQC — aggregate FastQC results
    print(f"    Running MultiQC (docker: {DOCKER_MULTIQC})...")
    ret = docker_run(
        image=DOCKER_MULTIQC,
        cmd=["multiqc", "/fastqc", "--outdir", "/output", "--force"],
        mounts={
            fastqc_out_abs: "/fastqc",
            multiqc_out_abs: "/output",
        },
    )
    if ret.returncode == 0:
        print(f"    MultiQC report: {multiqc_out / 'multiqc_report.html'}")
    else:
        print(f"    MultiQC failed (returncode={ret.returncode})")


def run_biomate_qc(sample_dir: Path, out_dir: Path, config: dict):
    """Submit samples to BioMate and collect QC decisions as JSONL audit trail."""
    import requests

    host = config.get("biomate", {}).get("host", "http://localhost:8080")
    email = config.get("biomate", {}).get("eval_user", {}).get("email", "eval@biomate.test")
    password = config.get("biomate", {}).get("eval_user", {}).get("password", "")

    biomate_out = out_dir / "biomate"
    biomate_out.mkdir(parents=True, exist_ok=True)

    # Login
    try:
        r = requests.post(f"{host}/api/auth/login", json={"email": email, "password": password})
        token = r.json().get("token") or r.json().get("access_token")
    except Exception as e:
        print(f"    Cannot connect to BioMate: {e}")
        return

    # For each FASTQ, ask BioMate to run QC
    fastqs = list(sample_dir.glob("*.fastq.gz"))
    for fq in fastqs:
        print(f"    Submitting {fq.name} to BioMate QC...")
        # In practice: upload file, ask BioMate to run QC workflow, collect audit trail
        # This is a placeholder — real implementation uploads the file and polls for completion
        audit_path = biomate_out / (fq.stem + "_audit.jsonl")
        if audit_path.exists():
            print(f"      Already done: {audit_path.name}")
            continue
        # TODO: implement file upload + QC workflow execution
        print(f"      TODO: upload {fq.name} → run QC → save audit trail to {audit_path.name}")


# ─── Labels validation ────────────────────────────────────────────────────────

def validate_labels(labels_path: Path):
    """Check inter-rater agreement and flag discrepancies."""
    with open(labels_path) as f:
        labels = yaml.safe_load(f)

    total = len(labels)
    agree = 0
    disagree = []

    for item in labels:
        r1 = item.get("rater_1_decision")
        r2 = item.get("rater_2_decision")
        if r1 and r2:
            if r1 == r2:
                agree += 1
            else:
                disagree.append(item["sample_id"])
        else:
            print(f"  WARNING: Missing rater decision for {item['sample_id']}")

    rated = agree + len(disagree)
    pct = 100 * agree // rated if rated else 0

    print(f"\nInter-rater agreement: {agree}/{rated} ({pct}%)")
    print(f"Target: ≥85% agreement (kappa > 0.8)")

    if disagree:
        print(f"\nDisagreements ({len(disagree)}) — require adjudication:")
        for sid in disagree:
            item = next(i for i in labels if i["sample_id"] == sid)
            print(f"  {sid}: {item.get('rater_1_decision')} vs {item.get('rater_2_decision')}")

    if pct < 85:
        print(f"\nWARNING: Agreement {pct}% < 85% — review labeling protocol")
    else:
        print(f"\nOK: Agreement {pct}% ≥ 85%")

    # Check coverage
    expected_ids = set()
    for ds_id in BASE_DATASETS:
        for defect in DEFECTS:
            expected_ids.add(f"{ds_id}_{defect['id']}")
        expected_ids.add(f"{ds_id}_control")  # unmodified

    labeled_ids = {item["sample_id"] for item in labels}
    missing = expected_ids - labeled_ids
    if missing:
        print(f"\nMissing labels ({len(missing)}):")
        for sid in sorted(missing):
            print(f"  {sid}")


# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="QC Governance dataset construction")
    parser.add_argument("--download-only", action="store_true",
                        help="Download base datasets only")
    parser.add_argument("--inject-all", action="store_true",
                        help="Inject defects into all base datasets")
    parser.add_argument("--inject", action="store_true",
                        help="Inject defects (use with --dataset)")
    parser.add_argument("--dataset", choices=list(BASE_DATASETS.keys()),
                        help="Target dataset ID (D1-D5)")
    parser.add_argument("--defect", choices=[d["id"] for d in DEFECTS],
                        help="Specific defect to inject")
    parser.add_argument("--run-qc", action="store_true",
                        help="Run QC tools on all samples")
    parser.add_argument("--validate-labels", metavar="LABELS_YAML",
                        help="Validate inter-rater agreement")
    parser.add_argument("--all", action="store_true",
                        help="Full pipeline: download → inject → run-qc")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--config", default="config.yaml")
    args = parser.parse_args()

    config_path = Path(__file__).parent.parent / args.config
    config = {}
    if config_path.exists():
        with open(config_path) as f:
            config = yaml.safe_load(f)

    SAMPLES_DIR.mkdir(parents=True, exist_ok=True)
    QC_RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    (QC_RESULTS_DIR / "multiqc").mkdir(exist_ok=True)
    (QC_RESULTS_DIR / "nfcore").mkdir(exist_ok=True)
    (QC_RESULTS_DIR / "biomate").mkdir(exist_ok=True)

    if args.validate_labels:
        validate_labels(Path(args.validate_labels))
        return

    datasets_to_process = [args.dataset] if args.dataset else list(BASE_DATASETS.keys())
    defects_to_inject = ([d for d in DEFECTS if d["id"] == args.defect]
                         if args.defect else DEFECTS)

    if args.download_only or args.all:
        print("=== Step 1: Downloading base datasets ===")
        for ds_id in datasets_to_process:
            download_dataset(ds_id, dry_run=args.dry_run)

    if args.inject or args.inject_all or args.all:
        print("\n=== Step 2: Injecting defects ===")
        for ds_id in datasets_to_process:
            raw_dir = SAMPLES_DIR / ds_id / "raw"
            if not raw_dir.exists():
                print(f"  {ds_id}: raw data not found — run --download-only first")
                continue

            raw_fastqs = list(raw_dir.glob("*.1M.fastq.gz")) or list(raw_dir.glob("*.fastq.gz"))
            if not raw_fastqs:
                print(f"  {ds_id}: no FASTQ files in {raw_dir}")
                continue

            for defect in defects_to_inject:
                defect_dir = SAMPLES_DIR / ds_id / defect["id"]
                defect_dir.mkdir(parents=True, exist_ok=True)

                for fq in raw_fastqs[:1]:  # inject into first file for speed
                    out_fq = defect_dir / fq.name
                    if out_fq.exists() and not args.dry_run:
                        print(f"  {ds_id}/{defect['id']}: already injected")
                        continue
                    if args.dry_run:
                        print(f"  [DRY RUN] inject {defect['id']} → {ds_id}/{fq.name}")
                        continue
                    print(f"  Injecting {defect['id']} into {ds_id}/{fq.name}...")
                    defect["inject"](fq, out_fq, defect_dir)

            # Write unmodified control
            ctrl_dir = SAMPLES_DIR / ds_id / "control"
            ctrl_dir.mkdir(exist_ok=True)
            for fq in raw_fastqs[:1]:
                ctrl_fq = ctrl_dir / fq.name
                if not ctrl_fq.exists() and not args.dry_run:
                    import shutil
                    shutil.copy2(fq, ctrl_fq)
                    print(f"  {ds_id}/control: copied unmodified sample")

    if args.run_qc or args.all:
        print("\n=== Step 3: Running QC tools ===")
        for ds_id in datasets_to_process:
            for variant_dir in sorted((SAMPLES_DIR / ds_id).iterdir()) if (SAMPLES_DIR / ds_id).exists() else []:
                if not variant_dir.is_dir():
                    continue
                out = QC_RESULTS_DIR / "multiqc" / ds_id / variant_dir.name
                print(f"  FastQC+MultiQC: {ds_id}/{variant_dir.name}")
                if not args.dry_run:
                    run_fastqc_multiqc(variant_dir, out)

        print("\n  BioMate QC:")
        for ds_id in datasets_to_process:
            for variant_dir in sorted((SAMPLES_DIR / ds_id).iterdir()) if (SAMPLES_DIR / ds_id).exists() else []:
                if not variant_dir.is_dir():
                    continue
                out = QC_RESULTS_DIR / "biomate" / ds_id / variant_dir.name
                if not args.dry_run:
                    run_biomate_qc(variant_dir, out, config)

    # Print labels template if needed
    if not (QC_DIR / "labels.yaml").exists():
        print("\n=== Generating labels template ===")
        template_entries = []
        for ds_id in BASE_DATASETS:
            for defect in DEFECTS:
                template_entries.append({
                    "sample_id": f"{ds_id}_{defect['id']}",
                    "base_dataset": BASE_DATASETS[ds_id]["accession"],
                    "defect_category": defect["category"],
                    "defect_type": defect["id"],
                    "correct_action": defect["expected_action"],
                    "correct_suggested_fix": defect.get("expected_fix") or "N/A",
                    "confidence": "HIGH",
                    "rater_1": "yzhang",
                    "rater_2": "<second_rater>",
                    "rater_1_decision": "<PASS|WARN|FAIL>",
                    "rater_2_decision": "<PASS|WARN|FAIL>",
                    "agreement": None,
                    "notes": "",
                })
            # Unmodified control
            template_entries.append({
                "sample_id": f"{ds_id}_control",
                "base_dataset": BASE_DATASETS[ds_id]["accession"],
                "defect_category": "control",
                "defect_type": "none",
                "correct_action": "PASS",
                "correct_suggested_fix": "N/A",
                "confidence": "HIGH",
                "rater_1": "yzhang",
                "rater_2": "<second_rater>",
                "rater_1_decision": "<PASS>",
                "rater_2_decision": "<PASS>",
                "agreement": None,
                "notes": "Unmodified control — should always PASS",
            })

        template_path = QC_DIR / "labels_template.yaml"
        with open(template_path, "w") as f:
            yaml.dump(template_entries, f, default_flow_style=False, allow_unicode=True)
        print(f"  Template written: {template_path}")
        print(f"  Copy to labels.yaml and fill in rater decisions")
        print(f"  Then: python scripts/inject_qc_defects.py --validate-labels labels.yaml")

    print("\nDone.")


if __name__ == "__main__":
    main()
