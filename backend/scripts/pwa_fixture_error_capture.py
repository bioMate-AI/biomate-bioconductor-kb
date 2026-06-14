import re, shutil, subprocess, os
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
BIOC=Path("/tmp/pwa-wt/backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor")
pkgs="mia iseetree metams combi banocc flowviz immunoclust dirichletmultinomial crimage flowfp metcirc".split()
def err(out):
    m=re.findall(r'Error[^\n]*', re.sub(r'\x1b\[[0-9;]*m','',out))
    return m[-1][:150] if m else (out.strip().splitlines()[-1][:150] if out.strip() else "(no output)")
def run(p):
    d=BIOC/p; t=(d/"main.nf").read_text()
    img=re.search(r'container\s+"([^"]+)"',t).group(1)
    fx=d/"main.fixture.R"
    if not fx.exists(): return (p,"no_fixture")
    w=Path(f"/tmp/fxerr/{p}"); shutil.rmtree(w,ignore_errors=True); w.mkdir(parents=True)
    shutil.copy(fx,w/"_f.R")
    try:
        r=subprocess.run(["docker","run","--rm","--platform","linux/amd64","-v",f"{w}:/work","-w","/work",img,"Rscript","_f.R"],
                         capture_output=True,text=True,timeout=600)
        return (p, err(r.stdout+r.stderr))
    except subprocess.TimeoutExpired:
        return (p,"TIMEOUT>600s")
with ThreadPoolExecutor(max_workers=4) as ex:
    for f in as_completed({ex.submit(run,p):p for p in pkgs}):
        p,e=f.result(); print(f"  {p}: {e}",flush=True)
