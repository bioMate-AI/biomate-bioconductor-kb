#!/usr/bin/env python3
"""Download pdex/all_pdex.parquet (29.76 GB) from HuggingFace to S3.

Uses HTTP Range requests so each 512 MB part is independently retried
on connection drop — avoids the 'Background writer channel closed' failure
that hf_hub_download hits on large single-stream downloads.

Usage:
  python3 download_replogle_pdex.py > /tmp/replogle_pdex.log 2>&1 &
"""
import sys, time, boto3, requests

BUCKET  = "knowledge-datasets-1759951976"
HF_REPO = "tahoebio/replogle-nadig-de-rhaister"
HF_FILE = "pdex/all_pdex.parquet"
S3_KEY  = "replogle_nadig/pdex/all_pdex.parquet"

PART_SIZE  = 512 * 1024 * 1024   # 512 MB per S3 multipart part
MAX_RETRY  = 5
RETRY_WAIT = 30

s3   = boto3.client("s3")
sess = requests.Session()
sess.headers.update({"User-Agent": "python-requests/2.32"})

HF_URL = f"https://huggingface.co/datasets/{HF_REPO}/resolve/main/{HF_FILE}"


def s3_exists():
    try:
        s3.head_object(Bucket=BUCKET, Key=S3_KEY)
        return True
    except Exception:
        return False


def get_size():
    r = sess.head(HF_URL, allow_redirects=True, timeout=60)
    r.raise_for_status()
    return int(r.headers["content-length"])


def download_range(start, end):
    for tri in range(1, MAX_RETRY + 1):
        try:
            r = sess.get(HF_URL,
                         headers={"Range": f"bytes={start}-{end}"},
                         stream=True,
                         timeout=(60, 600),
                         allow_redirects=True)
            r.raise_for_status()
            data = b"".join(r.iter_content(chunk_size=4 * 1024 * 1024))
            expected = end - start + 1
            if len(data) != expected:
                raise ValueError(f"got {len(data)} bytes, expected {expected}")
            return data
        except Exception as e:
            if tri == MAX_RETRY:
                raise
            wait = RETRY_WAIT * tri
            print(f"  [retry {tri}/{MAX_RETRY}] {e} — sleeping {wait}s", flush=True)
            time.sleep(wait)


def main():
    if s3_exists():
        print(f"SKIP: s3://{BUCKET}/{S3_KEY} already exists")
        return

    print(f"Resolving size of {HF_FILE} ...")
    total = get_size()
    print(f"Total size: {total/1e9:.2f} GB")

    ranges = []
    start = 0
    while start < total:
        end = min(start + PART_SIZE - 1, total - 1)
        ranges.append((start, end))
        start = end + 1
    n_parts = len(ranges)
    print(f"Uploading in {n_parts} parts of {PART_SIZE//1024//1024} MB each")

    mp  = s3.create_multipart_upload(Bucket=BUCKET, Key=S3_KEY,
                                     StorageClass="INTELLIGENT_TIERING")
    uid = mp["UploadId"]
    parts = []

    try:
        for i, (start, end) in enumerate(ranges, 1):
            pct = start / total * 100
            print(f"  part {i}/{n_parts}  [{start/1e9:.2f}–{end/1e9:.2f} GB]  {pct:.1f}%", flush=True)
            data = download_range(start, end)
            p = s3.upload_part(Bucket=BUCKET, Key=S3_KEY,
                               UploadId=uid, PartNumber=i, Body=data)
            parts.append({"PartNumber": i, "ETag": p["ETag"]})
            print(f"    → part {i} OK", flush=True)

        s3.complete_multipart_upload(Bucket=BUCKET, Key=S3_KEY,
                                     UploadId=uid,
                                     MultipartUpload={"Parts": parts})
        print(f"\n✓ DONE: s3://{BUCKET}/{S3_KEY}  ({total/1e9:.2f} GB)")

    except Exception as e:
        print(f"\n✗ FAILED: {e}")
        try:
            s3.abort_multipart_upload(Bucket=BUCKET, Key=S3_KEY, UploadId=uid)
        except Exception:
            pass
        sys.exit(1)


main()
