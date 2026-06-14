#!/usr/bin/env python3
"""Local test-data collection + contract audit (no spot, no workflow analysis).
For each bioc package whose domain image is LOCAL: run ONLY its fixture.R in the container
(loads package example data + writes the input CSVs), capture each produced file's header,
and compare against what the WORKFLOW reads (declared // Input names + the column names /
row.names the R actually requires). Flags fixtures that emit data not matching the contract,
so we fix the *data*, not the workflow.
"""
import re, shutil, subprocess, os, json, glob
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

WT = Path("/tmp/pwa-wt")
BIOC = WT / "backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor"
LOCAL = {"metagenomics", "metabolomics", "imaging"}

def domain(t): m=re.search(r'bioc-domain-([a-z]+):',t); return m.group(1) if m else None

def workflow_contract(nf_text):
    """Column names / row.names the workflow R requires from its inputs (heuristic)."""
    reqs = set()
    # 'col' %in% colnames(df)  /  must contain a 'col' column
    reqs |= set(re.findall(r'["\']([a-zA-Z_][\w.]*)["\']\s*%in%\s*colnames', nf_text))
    reqs |= set(re.findall(r"must contain a ['\"]([\w.]+)['\"]", nf_text))
    # read.csv(..., row.names = "col")
    reqs |= set(re.findall(r'row\.names\s*=\s*["\']([\w.]+)["\']', nf_text))
    # df$col references right after a read
    reqs |= set(re.findall(r'\$([a-z_][\w.]*)', nf_text)) & {"taxon_id","sample","feature_id","gene_id","sample_id","id"}
    return sorted(reqs)

def run_one(pkg_dir: Path):
    nf = pkg_dir / "main.nf"
    if not nf.exists(): return None
    t = nf.read_text()
    if domain(t) not in LOCAL: return None
    fix = pkg_dir / "main.fixture.R"
    if not fix.exists(): return (pkg_dir.name, "no_fixture", {}, [])
    img_m = re.search(r'container\s+"([^"]+)"', t)
    if not img_m: return (pkg_dir.name, "no_container", {}, [])
    img = img_m.group(1)
    decl = re.search(r'(?m)^\s*//\s*Input:\s*(.+)$', t)
    names = [re.split(r"\s*\(",x)[0].strip() for x in re.split(r"[,\s]+", decl.group(1))] if decl else []
    work = Path(f"/tmp/fx_collect/{pkg_dir.name}"); shutil.rmtree(work, ignore_errors=True); work.mkdir(parents=True)
    shutil.copy(fix, work/"_fixture.R")
    try:
        subprocess.run(["docker","run","--rm","--platform","linux/amd64","-v",f"{work}:/work","-w","/work",
                        img,"Rscript","_fixture.R"], capture_output=True, text=True, timeout=600)
    except subprocess.TimeoutExpired:
        return (pkg_dir.name, "fixture_timeout", {}, workflow_contract(t))
    headers = {}
    for n in names:
        p = work/n
        if p.exists() and p.stat().st_size>0:
            try: headers[n] = p.read_text(errors="replace").splitlines()[0][:120]
            except Exception: headers[n] = "(binary)"
        else:
            headers[n] = "(MISSING)"
    return (pkg_dir.name, "collected", headers, workflow_contract(t))

def main():
    todo = [d for d in sorted(BIOC.iterdir()) if d.is_dir() and (d/"main.nf").exists()
            and domain((d/"main.nf").read_text()) in LOCAL and (d/"main.fixture.R").exists()]
    print(f"fixtures to collect: {len(todo)}", flush=True)
    out=[]
    with ThreadPoolExecutor(max_workers=4) as ex:
        futs={ex.submit(run_one,d):d for d in todo}
        for i,f in enumerate(as_completed(futs),1):
            r=f.result()
            if not r: continue
            out.append(r)
            pkg,st,hdr,req = r
            # flag mismatch: a required column not present in any produced header
            mism=""
            if st=="collected" and req:
                hdr_cols = " ".join(hdr.values())
                missing=[c for c in req if c not in hdr_cols]
                if missing: mism=f"  MISMATCH needs={req} missing_from_data={missing}"
            print(f"  [{i}/{len(todo)}] {pkg}: {st}{mism}", flush=True)
            if st=="collected" and hdr:
                for n,h in hdr.items(): print(f"        {n}: {h}", flush=True)
    json.dump(out, open("/tmp/fixture_collect.json","w"), indent=2)
    print("saved /tmp/fixture_collect.json")

if __name__=="__main__":
    main()
