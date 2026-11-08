"""PMC full-text from AWS Open Data (s3://pmc-oa-opendata) via boto3 UNSIGNED — in-process, parallel,
error-tolerant (no per-file CLI spawn / xargs / tar). Lists N per-article prefixes, downloads each
PMC*.txt, emits jsonl. Usage: python build_pmc_bulk.py --out pmc_fulltext_bulk.jsonl --n 8000"""
import argparse, hashlib, json, re, boto3
from botocore import UNSIGNED
from botocore.config import Config
from concurrent.futures import ThreadPoolExecutor
BUCKET = "pmc-oa-opendata"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True); ap.add_argument("--n", type=int, default=8000)
    ap.add_argument("--max-tokens", type=int, default=3_000_000_000); ap.add_argument("--workers", type=int, default=64)
    a = ap.parse_args()
    s3 = boto3.client("s3", config=Config(signature_version=UNSIGNED, max_pool_connections=a.workers + 8))
    prefixes = []
    for page in s3.get_paginator("list_objects_v2").paginate(Bucket=BUCKET, Delimiter="/"):
        for cp in page.get("CommonPrefixes", []):
            prefixes.append(cp["Prefix"])
            if len(prefixes) >= a.n: break
        if len(prefixes) >= a.n: break
    print(f"prefixes listed: {len(prefixes):,}", flush=True)

    def get(pfx):
        base = pfx.rstrip("/")
        try:
            o = s3.get_object(Bucket=BUCKET, Key=f"{pfx}{base}.txt")
            t = re.sub(r"\s+", " ", o["Body"].read().decode("utf-8", "ignore")).strip()
            if len(t) <= 500:
                return None
            pmcid = re.match(r"PMC\d+", base)
            return {"text": t[:20000], "source": "pmc_fulltext_bulk",
                    "pmcid": pmcid.group() if pmcid else None,
                    "source_family": pmcid.group() if pmcid else f"s3://{BUCKET}/{pfx}{base}.txt",
                    "source_uri": f"s3://{BUCKET}/{pfx}{base}.txt",
                    "source_sha256": hashlib.sha256(t.encode()).hexdigest()}
        except Exception:
            return None
    n = toks = 0
    with ThreadPoolExecutor(max_workers=a.workers) as ex, open(a.out, "w") as fo:
        for i, row in enumerate(ex.map(get, prefixes)):
            if row:
                fo.write(json.dumps(row) + "\n"); n += 1; toks += len(row["text"]) // 4
            if i % 1000 == 0:
                print(f"  {i}/{len(prefixes)} -> {n} articles ~{toks:,} tok", flush=True)
            if toks >= a.max_tokens: break
    print(f"PMC BULK: {n} articles ~{toks:,} tok -> {a.out}", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
