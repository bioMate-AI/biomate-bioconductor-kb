#!/usr/bin/env python3
"""
Download Arc VCC datasets from HuggingFace to S3.

  tahoebio/Tahoe-100M              → s3://knowledge-datasets-1759951976/tahoe-100m/
  tahoebio/replogle-nadig-de-rhaister → s3://knowledge-datasets-1759951976/replogle_nadig/

Usage:
  python3 download_arc_vcc_data.py [--replogle-only | --tahoe-only]

For the large pdex/all_pdex.parquet (29.76 GB), use download_replogle_pdex.py
which uses HTTP Range requests for robust per-part retry.

Requirements:
  pip install huggingface_hub boto3 tqdm requests
  AWS credentials with s3:PutObject on knowledge-datasets-1759951976

Note: Running on EC2 in us-west-2 (same region as bucket) avoids egress charges.
"""

import os, sys, json, time, logging, argparse
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

import boto3
from huggingface_hub import HfApi, hf_hub_download
from tqdm import tqdm

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler("/tmp/arc_vcc_download.log"),
    ],
)
log = logging.getLogger(__name__)

S3_BUCKET = "knowledge-datasets-1759951976"

DATASETS = {
    "replogle_nadig": {
        "repo_id":   "tahoebio/replogle-nadig-de-rhaister",
        "s3_prefix": "replogle_nadig",
        "workers":   4,
        # pdex/all_pdex.parquet is 29.76 GB — use download_replogle_pdex.py for it
        "skip_files": {"pdex/all_pdex.parquet"},
    },
    "tahoe_100m": {
        "repo_id":    "tahoebio/Tahoe-100M",
        "s3_prefix":  "tahoe-100m",
        "workers":    6,
        "skip_files": set(),
    },
}

s3 = boto3.client("s3")


def s3_exists(key: str) -> bool:
    try:
        s3.head_object(Bucket=S3_BUCKET, Key=key)
        return True
    except Exception:
        return False


def upload_file(local_path: str, s3_key: str):
    s3.upload_file(local_path, S3_BUCKET, s3_key,
                   ExtraArgs={"StorageClass": "INTELLIGENT_TIERING"})


def download_dataset(name: str, repo_id: str, s3_prefix: str,
                     workers: int = 4, skip_files: set = None):
    skip_files = skip_files or set()
    api = HfApi()
    all_files = [f for f in api.list_repo_files(repo_id, repo_type="dataset")
                 if not f.startswith(".git")]
    files = [f for f in all_files if f not in skip_files]
    if skip_files:
        log.info("[%s] skipping large files (use dedicated script): %s", name, skip_files)
    log.info("[%s] %d files to sync to s3://%s/%s/", name, len(files), S3_BUCKET, s3_prefix)

    done, skipped, failed = [], [], []

    def process(fname):
        s3_key = f"{s3_prefix}/{fname}"
        if s3_exists(s3_key):
            return ("skip", fname)
        try:
            local = hf_hub_download(repo_id=repo_id, filename=fname,
                                    repo_type="dataset",
                                    local_dir=f"/tmp/{name}_staging")
            upload_file(local, s3_key)
            try:
                os.unlink(local)
            except Exception:
                pass
            return ("ok", fname)
        except Exception as e:
            return ("fail", fname, str(e))

    with ThreadPoolExecutor(max_workers=workers) as ex:
        futures = {ex.submit(process, f): f for f in files}
        for fut in tqdm(as_completed(futures), total=len(files), desc=name):
            result = fut.result()
            if result[0] == "ok":
                done.append(result[1])
                log.info("[%s] ✓ %s", name, result[1])
            elif result[0] == "skip":
                skipped.append(result[1])
            else:
                failed.append((result[1], result[2]))
                log.error("[%s] ✗ %s: %s", name, result[1], result[2])

    log.info("[%s] done: %d uploaded, %d already existed, %d failed",
             name, len(done), len(skipped), len(failed))
    for f, e in failed:
        log.error("  FAILED %s: %s", f, e)
    return len(failed) == 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--replogle-only", action="store_true")
    parser.add_argument("--tahoe-only", action="store_true")
    args = parser.parse_args()

    success = True
    if not args.tahoe_only:
        cfg = DATASETS["replogle_nadig"]
        ok = download_dataset("replogle_nadig", cfg["repo_id"], cfg["s3_prefix"],
                              workers=cfg["workers"], skip_files=cfg["skip_files"])
        success = success and ok

    if not args.replogle_only:
        cfg = DATASETS["tahoe_100m"]
        ok = download_dataset("tahoe_100m", cfg["repo_id"], cfg["s3_prefix"],
                              workers=cfg["workers"], skip_files=cfg["skip_files"])
        success = success and ok

    sys.exit(0 if success else 1)
