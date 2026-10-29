#!/usr/bin/env python3
"""Fetch open-access full texts from Europe PMC, store normalised text for verbatim-quote verification, and extract
the abstract plus the most quantitative keyword sentences per paper. RUNS ON EC2 (not on the laptop).

usage: fetch_fulltext.py SOURCES.txt OUTDIR
writes OUTDIR/index.json (per-PMCID metadata + candidate sentences), OUTDIR/fulltext/<PMCID>.txt (normalised text),
OUTDIR/raw/<PMCID>.xml
Only sources that Europe PMC serves as full text are used; anything else gets status != 'ok' and is excluded.
"""
import json, os, re, sys, time, unicodedata, urllib.request, urllib.error
import xml.etree.ElementTree as ET

BASE = "https://www.ebi.ac.uk/europepmc/webservices/rest/{}/fullTextXML"
TOPICS = {
    "nme": r"N-methyl|N-Me\b|methylat",
    "perm": r"permeab|PAMPA|Caco|MDCK|RRCK|oral bioavailab|absorption",
    "psa": r"\bTPSA\b|polar surface|\bPSA\b|3D-PSA|\bHBD\b|hydrogen bond donor|NH\b",
    "imhb": r"intramolecular hydrogen|IMHB|chamele|hydrogen bond",
    "lip": r"lipophil|logD|log ?P\b|ALogP|cLogP|ElogD",
    "size": r"molecular weight|\bMW\b|ring size|macrocycle size|number of residues|heavy atom|Ro5|rule of 5|bRo5|beyond.{0,12}rule",
    "dres": r"D-amino|D-Pro|D-residue|stereochem|chirality|epimer|diastereomer",
    "cyc": r"cyclization|cyclisation|macrocyclization|head-to-tail|lactam|thioether|disulfide|stapl|bicyclic",
    "stab": r"protease|proteolytic|serum stability|half-life|plasma stability|metabolic stability|degradation",
    "liab": r"deamidat|isoaspart|aspartimide|succinimide|Asn-Gly|N-G\b|oxidation|aggregat|solubility",
    "rgd": r"\bRGD|RGDL|integrin|A20FMDV2|MIDAS|selectiv",
    "pdl1": r"PD-L1|PD-1",
    "grpr": r"GRPR|bombesin|gastrin-releasing|RM2|RM26|antagonist",
}
QUANT = re.compile(r"(\d+(\.\d+)?\s*(%|-fold|fold|nM|µM|μM|mM|Å|Da|kDa|cm/s|h\b|min\b|log))|10\s?[-−–]\s?\d|p\s?[<=]|n\s?=|[≥≤<>]\s?\d|\b(higher|lower|greater|less|increase[sd]?|decrease[sd]?|improv\w+|reduc\w+|enhanc\w+|correlat\w+)\b")


def norm(s: str) -> str:
    s = unicodedata.normalize("NFKC", s)
    s = s.replace("‐", "-").replace("‑", "-").replace("‒", "-").replace("–", "-").replace("—", "-").replace("−", "-")
    s = s.replace("‘", "'").replace("’", "'").replace("“", '"').replace("”", '"')
    return re.sub(r"\s+", " ", s).strip()


def text_of(el) -> str:
    return norm("".join(el.itertext()))


def split_sentences(t: str):
    return [x.strip() for x in re.split(r"(?<=[.!?])\s+(?=[A-Z(\[])", t) if x.strip()]


def parse(xml_bytes: bytes):
    root = ET.fromstring(xml_bytes)
    art = root if root.tag == "article" else root.find(".//article")
    if art is None:
        return None
    meta = art.find(".//article-meta")
    title = text_of(meta.find(".//article-title")) if meta is not None and meta.find(".//article-title") is not None else ""
    jt = art.find(".//journal-title")
    doi = ""
    for aid in art.findall(".//article-id"):
        if aid.get("pub-id-type") == "doi":
            doi = (aid.text or "").strip()
    year = ""
    for pd in art.findall(".//pub-date"):
        y = pd.find("year")
        if y is not None and y.text:
            year = y.text.strip()
            break
    lic = ""
    for lp in art.findall(".//license"):
        lic = text_of(lp)[:200]
        href = lp.get("{http://www.w3.org/1999/xlink}href")
        if href:
            lic = (href + " | " + lic)[:240]
        break
    ab = art.find(".//abstract")
    abstract = text_of(ab) if ab is not None else ""
    body = art.find("body")
    sections = []  # (section title, paragraph text)
    if body is not None:
        def walk(sec, trail):
            t = sec.find("title")
            name = text_of(t) if t is not None else ""
            tr = trail + ([name] if name else [])
            for ch in sec:
                if ch.tag == "p":
                    sections.append((" > ".join(tr), text_of(ch)))
                elif ch.tag == "sec":
                    walk(ch, tr)
        for ch in body:
            if ch.tag == "sec":
                walk(ch, [])
            elif ch.tag == "p":
                sections.append(("", text_of(ch)))
    return {"title": title, "journal": text_of(jt) if jt is not None else "", "doi": doi, "year": year,
            "license": lic, "abstract": abstract, "sections": sections}


def main():
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(os.path.join(out, "fulltext"), exist_ok=True)
    os.makedirs(os.path.join(out, "raw"), exist_ok=True)
    ids = []
    for line in open(src):
        line = line.strip()
        if line and not line.startswith("#"):
            ids.append(line.split()[0])
    index = {}
    for pmcid in ids:
        rec = {"status": "error"}
        try:
            req = urllib.request.Request(BASE.format(pmcid), headers={"User-Agent": "biomate-knowledge-layer/1.0"})
            data = urllib.request.urlopen(req, timeout=60).read()
            open(os.path.join(out, "raw", pmcid + ".xml"), "wb").write(data)
            p = parse(data)
            if p is None or not p["sections"]:
                rec = {"status": "no_fulltext_body"}
            else:
                full = norm(" ".join([p["title"], p["abstract"]] + [t for _, t in p["sections"]]))
                open(os.path.join(out, "fulltext", pmcid + ".txt"), "w").write(full)
                cands = []
                for sname, para in p["sections"]:
                    if re.search(r"reference|acknowledg|funding|author contrib|conflict|supplement|data availab", sname, re.I):
                        continue
                    for s in split_sentences(para):
                        if not (60 <= len(s) <= 450):
                            continue
                        topics = [k for k, rx in TOPICS.items() if re.search(rx, s, re.I)]
                        if not topics or not QUANT.search(s):
                            continue
                        score = len(topics) + len(QUANT.findall(s)) * 0.5
                        cands.append({"section": sname[:80], "text": s, "topics": topics, "score": round(score, 1)})
                cands.sort(key=lambda c: -c["score"])
                rec = {"status": "ok", "title": p["title"], "journal": p["journal"], "year": p["year"], "doi": p["doi"],
                       "license": p["license"], "abstract": p["abstract"], "n_chars": len(full), "candidates": cands[:14]}
        except urllib.error.HTTPError as e:
            rec = {"status": f"http_{e.code}"}
        except Exception as e:  # noqa
            rec = {"status": "error", "error": repr(e)[:200]}
        index[pmcid] = rec
        print(pmcid, rec.get("status"), rec.get("year", ""), (rec.get("title") or "")[:80], flush=True)
        time.sleep(0.4)
    json.dump(index, open(os.path.join(out, "index.json"), "w"), indent=1)
    print("DONE", sum(1 for r in index.values() if r["status"] == "ok"), "ok of", len(index))


if __name__ == "__main__":
    main()
