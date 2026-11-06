"""Bioconductor package source -> vignettes (runnable analysis + prose) + man pages (.Rd).
Vignettes are the IDEAL grounding for both mid-train prose AND (later) code-gen SFT. Downloads each
package source tarball from src/contrib, extracts inst/doc (vignettes) and man/*.Rd.

  python fetch_bioconductor.py --out /opt/dlami/nvme/corpus/bioc.jsonl --decontam .../decontam.pkl
Emits doc kind='prose' for vignette narrative and kind='code' for code chunks / examples (kept as code)."""
import argparse, io, os, re, sys, tarfile, urllib.request
sys.path.insert(0, os.path.dirname(__file__)); import common as C
BASE="https://bioconductor.org/packages/release/bioc"
VIEWS=f"{BASE}/VIEWS"

def parse_views():
    """VIEWS is a DCF file; yield (package, version)."""
    txt=urllib.request.urlopen(VIEWS, timeout=120).read().decode("utf-8","replace")
    pkg=ver=None
    for blk in txt.split("\n\n"):
        p=re.search(r"^Package:\s*(\S+)", blk, re.M); v=re.search(r"^Version:\s*(\S+)", blk, re.M)
        if p and v: yield p.group(1), v.group(1)

def rd_to_text(rd):
    s=re.sub(r"\\[a-zA-Z]+\{", " ", rd)      # strip \command{
    s=s.replace("}"," ").replace("{"," "); return C.norm_ws(s)

def rmd_split(rmd):
    """Split an Rmd/Rnw vignette into prose and fenced code chunks."""
    code=re.findall(r"```{?r[^\n]*\n(.*?)```", rmd, re.S)
    prose=re.sub(r"```.*?```"," ", rmd, flags=re.S)
    prose=re.sub(r"^---.*?---","", prose, flags=re.S)   # yaml header
    return C.clean_prose(prose), "\n\n".join(code)

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--out", required=True); ap.add_argument("--limit", type=int, default=100000)
    ap.add_argument("--decontam", default=""); a=ap.parse_args()
    dec=None
    if a.decontam:
        import pickle; dec=pickle.load(open(a.decontam,"rb"))
    pkgs=list(parse_views())[:a.limit]; print(f"{len(pkgs)} Bioconductor packages", flush=True)
    dd=C.Deduper(); man=C.Manifest("bioconductor"); f=C.open_out(a.out); kept=0
    for i,(pkg,ver) in enumerate(pkgs):
        url=f"{BASE}/src/contrib/{pkg}_{ver}.tar.gz"
        try:
            blob=urllib.request.urlopen(url, timeout=180).read()
            tf=tarfile.open(fileobj=io.BytesIO(blob), mode="r:gz")
        except Exception: man.bump("fetch_error"); continue
        for m in tf.getmembers():
            nm=m.name.lower()
            try: raw=tf.extractfile(m).read().decode("utf-8","replace") if m.isfile() else ""
            except Exception: continue
            if not raw: continue
            if nm.endswith((".rmd",".rnw")):
                prose,code=rmd_split(raw)
                for text,kind in ((prose,"prose"),(code,"code")):
                    ok,why=C.quality_ok(text, kind);
                    if not (text and ok): continue
                    if dec and dec.is_contaminated(text): man.bump("decontam_drop"); continue
                    if not dd.add(text): man.bump("dedup_drop"); continue
                    C.write_doc(f, text, "bioconductor", f"{pkg}", "Artistic-2.0", url, {"kind":kind,"pkg":pkg})
                    kept+=1; man.bump(f"kept_{kind}", tok=C.tokens(text))
            elif nm.endswith(".rd"):
                text=rd_to_text(raw); ok,_=C.quality_ok(text,"prose",30)
                if text and ok and dd.add(text) and not (dec and dec.is_contaminated(text)):
                    C.write_doc(f, text, "bioconductor", pkg, "Artistic-2.0", url, {"kind":"manpage","pkg":pkg})
                    kept+=1; man.bump("kept_manpage", tok=C.tokens(text))
        if (i+1)%200==0: print(f"{i+1}/{len(pkgs)} kept={kept}", flush=True)
    f.close(); man.dump(a.out.replace(".jsonl","_manifest.json"))
    print(f"Bioconductor done: {kept} docs -> {a.out}")

if __name__=="__main__": raise SystemExit(main())
