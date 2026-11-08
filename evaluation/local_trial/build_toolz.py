import argparse, json, re, urllib.request
def get(u,t=60):
    try: return urllib.request.urlopen(urllib.request.Request(u,headers={"User-Agent":"Mozilla/5.0"}),timeout=t).read().decode("utf-8","ignore")
    except Exception: return ""
def main():
    ap=argparse.ArgumentParser(); ap.add_argument("--out",required=True); a=ap.parse_args(); n=0
    with open(a.out,"w") as fo:
        # Bioconductor VIEWS = DCF with Package/Title/Description for every release package
        v=get("https://bioconductor.org/packages/release/bioc/VIEWS")
        for blk in v.split("\n\n"):
            d={}
            for m in re.finditer(r"^(Package|Title|Description|biocViews):\s*(.+?)(?=\n\S|\Z)", blk, re.S|re.M):
                d[m.group(1)]=re.sub(r"\s+"," ",m.group(2)).strip()
            if d.get("Package") and d.get("Description"):
                fo.write(json.dumps({"text":f"Bioconductor package {d['Package']}: {d.get('Title','')}. {d['Description']} Categories: {d.get('biocViews','')}","source":"tooldoc_bioconductor"})+"\n"); n+=1
        # nf-core pipelines
        try:
            pj=json.loads(get("https://nf-co.re/pipelines.json") or "{}")
            for p in pj.get("remote_workflows", []):
                fo.write(json.dumps({"text":f"nf-core pipeline {p.get('name')}: {p.get('description','')}. Topics: {', '.join(p.get('topics',[]))}","source":"tooldoc_nfcore"})+"\n"); n+=1
        except Exception: pass
    print(f"TOOLDOCS DONE: {n} docs -> {a.out}",flush=True)
if __name__=="__main__": raise SystemExit(main())
