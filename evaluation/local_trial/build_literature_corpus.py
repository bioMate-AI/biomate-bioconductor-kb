"""Build the ENTIRE biomedical literature corpus from the NCBI PubMed baseline (title+abstract, ALL topics).
Public-domain metadata, stdlib-only (urllib+gzip+ElementTree). Parallel across baseline files.
Writes {"text": "<title>\n\n<abstract>", "source": "pubmed"} to --out. Optional --relevance filter (off by default).
Usage: python build_literature_corpus.py --out literature_corpus.jsonl --start 1 --files 1400 --workers 16
"""
import argparse, gzip, io, json, os, re, tempfile, urllib.request, xml.etree.ElementTree as ET
from concurrent.futures import ProcessPoolExecutor, as_completed

BASE = "https://ftp.ncbi.nlm.nih.gov/pubmed/baseline"
PREFIX = os.environ.get("PUBMED_PREFIX", "pubmed26n")
REL = re.compile(r"\b(genom|transcriptom|proteom|metabolom|epigenom|rna[- ]?seq|scrna|single[- ]cell|"
                 r"variant|sequenc|bioinformatic|ngs|crispr|methylation|chip[- ]?seq|atac|microbiom|"
                 r"metagenom|phylogen|alignment|assembly|expression|pathway|gene|protein|molecul|omics)\b", re.I)
_REL = False  # set per-process from arg


def fetch_gz_xml(idx):
    url = f"{BASE}/{PREFIX}{idx:04d}.xml.gz"
    for a in range(3):
        try:
            return gzip.decompress(urllib.request.urlopen(url, timeout=180).read())
        except Exception:
            pass
    return None


def process_file(args):
    idx, shard_dir, relevance = args
    xb = fetch_gz_xml(idx)
    if not xb:
        return (idx, 0, 0, None)
    shard = os.path.join(shard_dir, f"shard_{idx:04d}.jsonl")
    kept = scanned = 0
    with open(shard, "w") as fo:
        for _, el in ET.iterparse(io.BytesIO(xb), events=("end",)):
            if el.tag != "PubmedArticle":
                continue
            title = " ".join("".join(t.itertext()) for t in el.iter("ArticleTitle"))
            abst = " ".join("".join(t.itertext()) for t in el.iter("AbstractText")).strip()
            el.clear()
            scanned += 1
            if len(abst) < 200:
                continue
            text = (title.strip() + "\n\n" + abst).strip()
            if relevance and not REL.search(text):
                continue
            fo.write(json.dumps({"text": text[:16000], "source": "pubmed"}) + "\n")
            kept += 1
    return (idx, kept, scanned, shard)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--start", type=int, default=1)
    ap.add_argument("--files", type=int, default=1400)   # >= max index; missing files skipped
    ap.add_argument("--workers", type=int, default=16)
    ap.add_argument("--relevance", action="store_true")
    a = ap.parse_args()
    shard_dir = tempfile.mkdtemp(prefix="pubmed_shards_")
    jobs = [(i, shard_dir, a.relevance) for i in range(a.start, a.start + a.files)]
    shards, kept_tot, scan_tot, done = [], 0, 0, 0
    with ProcessPoolExecutor(max_workers=a.workers) as ex:
        futs = [ex.submit(process_file, j) for j in jobs]
        for f in as_completed(futs):
            idx, kept, scanned, shard = f.result()
            done += 1; kept_tot += kept; scan_tot += scanned
            if shard: shards.append(shard)
            if done % 25 == 0:
                print(f"  {done}/{len(jobs)} files | kept={kept_tot:,} scanned={scan_tot:,}", flush=True)
    # concatenate shards in file order -> single corpus
    shards.sort()
    with open(a.out, "w") as fo:
        for s in shards:
            with open(s) as fi:
                for line in fi:
                    fo.write(line)
            os.remove(s)
    approx_tok = 0
    # cheap token estimate from bytes/4
    try: approx_tok = os.path.getsize(a.out) // 4
    except Exception: pass
    print(f"LITERATURE DONE: {kept_tot:,} abstracts (scanned {scan_tot:,}), ~{approx_tok:,} tokens -> {a.out}", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
