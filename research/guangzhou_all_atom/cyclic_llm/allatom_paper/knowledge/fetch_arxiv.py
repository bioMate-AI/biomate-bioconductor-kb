#!/usr/bin/env python3
"""Fetch arXiv PDFs, extract text (pypdf), store normalised text for verbatim-quote verification, extract campaign/quantitative sentences.
RUNS ON EC2.  usage: fetch_arxiv.py ARXIV_IDS.txt OUTDIR   (needs: pip install pypdf)
Output layout matches fetch_fulltext.py (index.json + fulltext/<ID>.txt) so build_kb.py can verify quotes for arXiv sources too.
"""
import io, json, os, re, sys, time, urllib.request
import xml.etree.ElementTree as ET
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fetch_fulltext import norm, split_sentences, TOPICS, QUANT


def main():
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(os.path.join(out, "fulltext"), exist_ok=True)
    from pypdf import PdfReader
    index = {}
    for line in open(src):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        aid = line.split()[0]
        key = "arXiv:" + aid
        rec = {"status": "error"}
        try:
            api = urllib.request.urlopen(urllib.request.Request(f"http://export.arxiv.org/api/query?id_list={aid}", headers={"User-Agent": "biomate-knowledge-layer/1.0"}), timeout=60).read()
            root = ET.fromstring(api); ns = {"a": "http://www.w3.org/2005/Atom"}
            ent = root.find("a:entry", ns)
            title = norm(ent.find("a:title", ns).text); abstract = norm(ent.find("a:summary", ns).text); year = ent.find("a:published", ns).text[:4]
            time.sleep(3)
            pdf = urllib.request.urlopen(urllib.request.Request(f"https://arxiv.org/pdf/{aid}", headers={"User-Agent": "biomate-knowledge-layer/1.0"}), timeout=120).read()
            rd = PdfReader(io.BytesIO(pdf))
            raw = "\n".join((pg.extract_text() or "") for pg in rd.pages)
            raw = re.sub(r"(?<=[a-z])-\n(?=[a-z])", "", raw)          # de-hyphenate line-break splits
            full = norm(" ".join([title, abstract, raw]))
            open(os.path.join(out, "fulltext", key.replace(":", "_") + ".txt"), "w").write(full)
            cands = []
            for s in split_sentences(norm(raw)):
                if not (60 <= len(s) <= 450):
                    continue
                topics = [k for k, rx in TOPICS.items() if re.search(rx, s, re.I)]
                if not topics or not QUANT.search(s):
                    continue
                cands.append({"section": "", "text": s, "topics": topics, "score": round(len(topics) + len(QUANT.findall(s)) * 0.5, 1)})
            cands.sort(key=lambda c: -c["score"])
            rec = {"status": "ok", "title": title, "journal": "arXiv", "year": year, "doi": "arXiv:" + aid, "license": "see https://arxiv.org/abs/" + aid,
                   "abstract": abstract, "n_chars": len(full), "n_pages": len(rd.pages), "candidates": cands[:16]}
        except Exception as e:  # noqa
            rec = {"status": "error", "error": repr(e)[:200]}
        index[key] = rec
        print(key, rec["status"], rec.get("year", ""), (rec.get("title") or "")[:80], flush=True)
        time.sleep(3)
    json.dump(index, open(os.path.join(out, "index.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
