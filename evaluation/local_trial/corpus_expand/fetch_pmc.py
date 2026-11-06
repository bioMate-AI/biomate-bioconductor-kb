"""PMC Open-Access subset -> cleaned prose docs. ALL topics (no topic filter, per decision); filter
only by LICENSE (config) and quality. Uses NCBI's OA file list + OA package service (JATS .nxml).

Run on the box (bandwidth):
  python fetch_pmc.py --out /opt/dlami/nvme/corpus/pmc.jsonl --limit 200000 \
      --license-allow "CC BY,CC0,CC BY-SA" --decontam /opt/dlami/nvme/data/decontam.pkl
Omit --license-allow to keep ALL OA licenses (respect NC/ND downstream). --limit uniformly samples."""
import argparse, csv, io, os, sys, tarfile, urllib.request, random, xml.etree.ElementTree as ET
sys.path.insert(0, os.path.dirname(__file__)); import common as C

OA_LIST="https://ftp.ncbi.nlm.nih.gov/pub/pmc/oa_file_list.csv"
OA_PKG="https://www.ncbi.nlm.nih.gov/pmc/utils/oa/oa.fcgi?id="   # -> download link per PMCID

def jats_to_text(nxml_bytes):
    try: root=ET.fromstring(nxml_bytes)
    except Exception: return None,None
    def txt(el): return "".join(el.itertext()) if el is not None else ""
    title=txt(root.find(".//article-title"))
    abst=" ".join(txt(a) for a in root.findall(".//abstract"))
    # body paragraphs, but skip ref-list / back matter
    body=[]
    for sec in root.findall(".//body//*"):
        if sec.tag in ("p","title") : body.append(txt(sec))
    parts=[title, abst]+body
    text=C.clean_prose("\n".join(p for p in parts if p and p.strip()))
    return title, text

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--out", required=True); ap.add_argument("--limit", type=int, default=100000)
    ap.add_argument("--license-allow", default="")   # comma list; empty = ALL
    ap.add_argument("--min-tok", type=int, default=120); ap.add_argument("--seed", type=int, default=17)
    ap.add_argument("--decontam", default=""); a=ap.parse_args()
    allow=set(x.strip() for x in a.license_allow.split(",") if x.strip())
    random.seed(a.seed)

    # 1) OA file list (license per article); uniform sample to --limit (no topic filter)
    print("fetching OA file list…", flush=True)
    rows=[]
    with urllib.request.urlopen(OA_LIST, timeout=120) as r:
        rd=csv.reader(io.TextIOWrapper(r, encoding="utf-8"))
        header=next(rd, None)
        for row in rd:
            if len(row)<6: continue
            fpath,cit,pmcid,updated,pmid,lic = row[0],row[1],row[2],row[3],row[4],row[5]
            if allow and lic not in allow: continue
            rows.append((fpath,pmcid,lic))
    random.shuffle(rows); rows=rows[:a.limit]
    print(f"{len(rows)} articles selected (license filter={'ALL' if not allow else sorted(allow)})", flush=True)

    dec=None
    if a.decontam:
        import pickle; dec=pickle.load(open(a.decontam,"rb"))
    dd=C.Deduper(); man=C.Manifest("pmc"); f=C.open_out(a.out); kept=0
    for i,(fpath,pmcid,lic) in enumerate(rows):
        try:
            url="https://ftp.ncbi.nlm.nih.gov/pub/pmc/"+fpath
            with urllib.request.urlopen(url, timeout=120) as resp: blob=resp.read()
            tf=tarfile.open(fileobj=io.BytesIO(blob), mode="r:gz")
            nx=[m for m in tf.getmembers() if m.name.endswith(".nxml")]
            if not nx: man.bump("no_nxml"); continue
            title,text=jats_to_text(tf.extractfile(nx[0]).read())
            if not text: man.bump("parse_fail"); continue
            text=C.pii_redact(text)
            ok,why=C.quality_ok(text, "prose", a.min_tok)
            if not ok: man.bump(f"drop_{why}"); continue
            if dec and dec.is_contaminated(text): man.bump("decontam_drop"); continue
            if not dd.add(text): man.bump("dedup_drop"); continue
            C.write_doc(f, text, "pmc", pmcid, lic, url); kept+=1; man.bump("kept", tok=C.tokens(text))
        except Exception as e:
            man.bump("fetch_error")
        if (i+1)%1000==0: print(f"{i+1}/{len(rows)} kept={kept}", flush=True)
    f.close(); man.dump(a.out.replace(".jsonl","_manifest.json"))
    print(f"PMC done: kept {kept} docs -> {a.out}")

if __name__=="__main__": raise SystemExit(main())
