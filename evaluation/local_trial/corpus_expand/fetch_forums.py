"""Bioinformatics forum Q&A -> {question + top/accepted answers} docs. Biostars and Bioconductor
support both run the Biostar engine with a JSON API. Q&A mirrors BioMate's real tasks (which-tool,
why-did-this-fail), so it's high-value for routing/clarification/diagnosis.

  python fetch_forums.py --out /opt/dlami/nvme/corpus/forums.jsonl --sites biostars,bioc \
      --max-id 9800000 --decontam .../decontam.pkl
Respects each site's API; keeps code/error blocks. SEQanswers (vBulletin, no clean API) is optional."""
import argparse, json, os, sys, urllib.request
sys.path.insert(0, os.path.dirname(__file__)); import common as C
SITES={"biostars":"https://www.biostars.org","bioc":"https://support.bioconductor.org"}

def get(url):
    try: return json.load(urllib.request.urlopen(urllib.request.Request(
        url, headers={"User-Agent":"biomate-corpus/1.0"}), timeout=60))
    except Exception: return None

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--out", required=True); ap.add_argument("--sites", default="biostars,bioc")
    ap.add_argument("--max-id", type=int, default=100000); ap.add_argument("--start-id", type=int, default=1)
    ap.add_argument("--decontam", default=""); a=ap.parse_args()
    dec=None
    if a.decontam:
        import pickle; dec=pickle.load(open(a.decontam,"rb"))
    dd=C.Deduper(); man=C.Manifest("forums"); f=C.open_out(a.out); kept=0
    for site in [s.strip() for s in a.sites.split(",")]:
        base=SITES.get(site);
        if not base: continue
        for pid in range(a.start_id, a.max_id):
            # Biostar API: /api/post/<id>/ returns post; questions have an answer thread via /api/traverse/
            post=get(f"{base}/api/post/{pid}/")
            if not post or post.get("type_display")!="Question":
                if pid%5000==0: print(f"{site} @id {pid} kept={kept}", flush=True)
                continue
            q=C.strip_html(post.get("content",""))
            answers=[]
            trav=get(f"{base}/api/traverse/{pid}/") or {}
            for aid in (trav.get("descendants") or [])[:5]:
                ap_=get(f"{base}/api/post/{aid}/")
                if ap_ and ap_.get("type_display") in ("Answer","Comment"):
                    answers.append(C.strip_html(ap_.get("content","")))
            if not answers: continue
            text=C.pii_redact(C.norm_ws(f"Question: {post.get('title','')}\n{q}\n\n"
                                        +"\n\n".join(f"Answer: {x}" for x in answers)))
            ok,why=C.quality_ok(text,"prose",40)
            if not ok: man.bump(f"drop_{why}"); continue
            if dec and dec.is_contaminated(text): man.bump("decontam_drop"); continue
            if not dd.add(text): man.bump("dedup_drop"); continue
            C.write_doc(f, text, f"forum_{site}", str(pid), "CC BY-SA", f"{base}/p/{pid}/")
            kept+=1; man.bump("kept", tok=C.tokens(text))
            if kept%1000==0: print(f"{site} kept={kept}", flush=True)
    f.close(); man.dump(a.out.replace(".jsonl","_manifest.json"))
    print(f"Forums done: {kept} Q&A docs -> {a.out}")

if __name__=="__main__": raise SystemExit(main())
