import argparse, json, os, re, glob, xml.etree.ElementTree as ET
ap=argparse.ArgumentParser(); ap.add_argument("--dir",required=True); ap.add_argument("--out",required=True)
ap.add_argument("--max-tokens",type=int,default=3_000_000_000); a=ap.parse_args()
def nxml_text(p):
    try:
        t=" ".join(x for x in ET.parse(p).getroot().itertext())
    except Exception:
        try: t=re.sub(r"<[^>]+>"," ",open(p,encoding="utf-8",errors="ignore").read())
        except Exception: return ""
    return re.sub(r"\s+"," ",t).strip()
def txt_text(p):
    try: return re.sub(r"\s+"," ",open(p,encoding="utf-8",errors="ignore").read()).strip()
    except Exception: return ""
n=toks=0
with open(a.out,"w") as fo:
    for ext,fn in ((".nxml",nxml_text),(".txt",txt_text)):
        for p in glob.iglob(os.path.join(a.dir,"**","*"+ext),recursive=True):
            t=fn(p)
            if len(t)>500:
                fo.write(json.dumps({"text":t[:20000],"source":"pmc_fulltext_bulk"})+"\n"); n+=1; toks+=len(t)//4
            if toks>=a.max_tokens: break
        if toks>=a.max_tokens: break
print(f"PMC BULK: {n} articles ~{toks:,} tok -> {a.out}",flush=True)
