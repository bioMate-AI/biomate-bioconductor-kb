"""Multi-engine community workflow code via Dockstore's GA4GH TRS v2 API (indexes CWL/WDL/Nextflow/
Snakemake/Galaxy together). Pulls descriptor files as CODE docs (kept as code, language-tagged) so the
model sees ALL engines, not just Nextflow. WorkflowHub can be added the same way.

  python fetch_workflows.py --out /opt/dlami/nvme/corpus/workflows.jsonl --decontam .../decontam.pkl
"""
import argparse, json, os, sys, urllib.request, urllib.parse
sys.path.insert(0, os.path.dirname(__file__)); import common as C
TRS="https://dockstore.org/api/ga4gh/trs/v2"
TYPES=["CWL","WDL","NFL","SMK","GALAXY"]   # NFL=Nextflow, SMK=Snakemake

def get(url):
    req=urllib.request.Request(url, headers={"Accept":"application/json"})
    return json.load(urllib.request.urlopen(req, timeout=120))

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--out", required=True); ap.add_argument("--per-type", type=int, default=2000)
    ap.add_argument("--decontam", default=""); a=ap.parse_args()
    dec=None
    if a.decontam:
        import pickle; dec=pickle.load(open(a.decontam,"rb"))
    dd=C.Deduper(); man=C.Manifest("workflows"); f=C.open_out(a.out); kept=0
    for dtype in TYPES:
        offset=0
        while offset < a.per_type:
            try:
                tools=get(f"{TRS}/tools?descriptorType={dtype}&limit=100&offset={offset}")
            except Exception: break
            if not tools: break
            for t in tools:
                tid=t.get("id","")
                for v in t.get("versions",[]):
                    vid=v.get("name") or v.get("id","")
                    try:
                        files=get(f"{TRS}/tools/{urllib.parse.quote(tid,safe='')}/versions/"
                                  f"{urllib.parse.quote(vid,safe='')}/{dtype}/files")
                    except Exception: continue
                    for fi in files:
                        if fi.get("file_type") not in ("PRIMARY_DESCRIPTOR","SECONDARY_DESCRIPTOR"): continue
                        rel=fi.get("path","")
                        try:
                            d=get(f"{TRS}/tools/{urllib.parse.quote(tid,safe='')}/versions/"
                                  f"{urllib.parse.quote(vid,safe='')}/{dtype}/descriptor/{urllib.parse.quote(rel,safe='')}")
                            code=d.get("content","")
                        except Exception: continue
                        ok,_=C.quality_ok(code,"code",30)
                        if not (code and ok): continue
                        if dec and dec.is_contaminated(code): man.bump("decontam_drop"); continue
                        if not dd.add(code): man.bump("dedup_drop"); continue
                        C.write_doc(f, code, "workflow_code", tid, "", "", {"engine":dtype,"path":rel})
                        kept+=1; man.bump(f"kept_{dtype}", tok=C.tokens(code))
            offset+=100
            print(f"{dtype} offset={offset} kept={kept}", flush=True)
    f.close(); man.dump(a.out.replace(".jsonl","_manifest.json"))
    print(f"Workflows done: {kept} descriptors -> {a.out}")

if __name__=="__main__": raise SystemExit(main())
