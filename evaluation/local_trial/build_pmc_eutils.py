"""PMC OPEN-ACCESS full-text via NCBI E-utilities, paginated past the 10k retstart cap using
usehistory=y -> WebEnv/query_key -> efetch windows against the history server. Emits article
body text (includes methods/protocols). stdlib only. Usage:
  python build_pmc_eutils.py --out pmc_fulltext_corpus.jsonl --max-tokens 3000000000
"""
import argparse, io, json, re, time, urllib.parse, urllib.request, xml.etree.ElementTree as ET
E = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils"


def get(url, timeout=120):
    for a in range(6):
        try:
            return urllib.request.urlopen(url, timeout=timeout).read()
        except Exception:
            time.sleep(3 * (a + 1))
    return b""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--max-tokens", type=int, default=3_000_000_000)
    ap.add_argument("--batch", type=int, default=100)
    a = ap.parse_args()
    # 1) esearch with usehistory -> WebEnv + QueryKey + total Count (paginates past the 10k retstart cap)
    q = urllib.parse.urlencode({"db": "pmc", "term": "open access[filter]", "usehistory": "y", "retmax": 0})
    head = get(f"{E}/esearch.fcgi?{q}").decode("utf-8", "ignore")
    we = re.search(r"<WebEnv>(\S+?)</WebEnv>", head)
    qk = re.search(r"<QueryKey>(\d+)</QueryKey>", head)
    ct = re.search(r"<Count>(\d+)</Count>", head)
    total = int(ct.group(1)) if ct else 0
    print(f"esearch total={total:,} webenv={'ok' if we else 'NONE'}", flush=True)
    if not (we and qk):
        print("NO WEBENV - abort", flush=True)
        return 1
    we, k = we.group(1), qk.group(1)
    toks = n = rs = 0
    with open(a.out, "w") as fh:
        while toks < a.max_tokens and rs < total:
            eq = urllib.parse.urlencode({"db": "pmc", "query_key": k, "WebEnv": we,
                                         "retstart": rs, "retmax": a.batch, "rettype": "xml"})
            xml = get(f"{E}/efetch.fcgi?{eq}").decode("utf-8", "ignore")
            rs += a.batch
            try:
                for _, el in ET.iterparse(io.BytesIO(xml.encode()), events=("end",)):
                    if el.tag.endswith("article"):
                        body = re.sub(r"\s+", " ", " ".join(t for t in el.itertext())).strip()
                        if len(body) > 500:
                            fh.write(json.dumps({"text": body[:20000], "source": "pmc_fulltext"}) + "\n")
                            n += 1
                            toks += len(body) // 4
                        el.clear()
            except Exception:
                pass
            time.sleep(0.4)
            if rs % 2000 == 0:
                print(f"  pmc retstart={rs} n={n} ~{toks:,} tok", flush=True)
    print(f"PMC FULLTEXT DONE: {n} articles ~{toks:,} tok -> {a.out}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
