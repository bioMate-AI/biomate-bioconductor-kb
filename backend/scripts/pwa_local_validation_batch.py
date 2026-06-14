#!/usr/bin/env python3
"""Per-workflow analysis batch harness: for each bioc package whose domain image is LOCAL,
run fixture (real data) -> B-2 entry wrapper -> real container, capture pass/fail + the real
R error. Surfaces the residual analysis bugs that remain after bootstrap+B-2+heredoc fixes.
"""
import ast, re, shutil, subprocess, os, json, sys
from pathlib import Path
from typing import Optional
from concurrent.futures import ThreadPoolExecutor, as_completed

WT = Path("/tmp/pwa-wt")
BIOC = WT / "backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor"
EXEC = WT / "backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py"

# local domain images (retagged to their ECR names so the .nf container directive resolves locally)
LOCAL_DOMAINS = {"metagenomics", "metabolomics", "imaging"}

# extract the real B-2 helpers
SRC = EXEC.read_text(); _tree = ast.parse(SRC); _segs = []
for n in _tree.body:
    if isinstance(n, ast.Assign) and any(getattr(t, "id", None) == "_BIOC_INPUT_DECL_RE" for t in n.targets):
        _segs.append(ast.get_source_segment(SRC, n))
    if isinstance(n, ast.FunctionDef) and n.name in {"_stage_declared_input", "_build_bioc_entry_wrapper"}:
        _segs.append(ast.get_source_segment(SRC, n))
class _L:
    def warning(s, *a, **k): pass
    def info(s, *a, **k): pass
_ns = {"re": re, "shutil": shutil, "subprocess": subprocess, "Path": Path, "Optional": Optional, "log": _L()}
exec("\n\n".join(_segs), _ns)
build = _ns["_build_bioc_entry_wrapper"]

def domain_of(nf_text):
    m = re.search(r'bioc-domain-([a-z]+):', nf_text)
    return m.group(1) if m else None

def real_err(out):
    m = re.findall(r'Error[^\n]*', re.sub(r'\x1b\[[0-9;]*m', '', out))
    return (m[-1][:160] if m else "")

def run_pkg(pkg_dir: Path):
    nf = pkg_dir / "main.nf"
    if not nf.exists(): return None
    t = nf.read_text()
    dom = domain_of(t)
    if dom not in LOCAL_DOMAINS: return None
    img_m = re.search(r'container\s+"([^"]+)"', t)
    if not img_m: return (pkg_dir.name, "no_container", "")
    img = img_m.group(1)
    fix = pkg_dir / "main.fixture.R"
    if not fix.exists(): return (pkg_dir.name, "no_fixture", "")
    decl = re.search(r'(?m)^\s*//\s*Input:\s*(.+)$', t)
    if not decl: return (pkg_dir.name, "no_input_decl", "")
    names = [re.split(r"\s*\(", x)[0].strip() for x in re.split(r"[,\s]+", decl.group(1)) if x.strip()]
    work = Path(f"/tmp/pwa_runs/{pkg_dir.name}"); shutil.rmtree(work, ignore_errors=True); work.mkdir(parents=True)
    shutil.copy(fix, work / "_fixture.R")
    fp = subprocess.run(["docker", "run", "--rm", "--platform", "linux/amd64", "-v", f"{work}:/work",
                         "-w", "/work", img, "Rscript", "_fixture.R"], capture_output=True, text=True, timeout=1800)
    made = [n for n in names if (work / n).exists() and (work / n).stat().st_size > 0]
    if not made:
        return (pkg_dir.name, "fixture_failed", real_err(fp.stdout + fp.stderr))
    run_dir = work / "run"; run_dir.mkdir()
    params = {n: str(work / n) for n in made}
    params["outdir"] = str(run_dir / "out")
    try:
        wrapper = build(nf, params, run_dir, pkg_dir.name)
    except Exception as e:
        return (pkg_dir.name, "wrapper_error", str(e)[:160])
    if wrapper is None:
        return (pkg_dir.name, "wrapper_none", "")
    (run_dir / "nextflow.config").write_text(
        'docker.enabled=true\ndocker.runOptions="--platform linux/amd64"\n'
        f'process.container="{img}"\nprocess.publishDir=[path:"{run_dir}/out",mode:"copy"]\n')
    env = dict(os.environ); env.pop("NXF_VER", None)
    p = subprocess.run(["/usr/local/bin/nextflow", "run", str(wrapper), "-c", "nextflow.config"],
                       cwd=str(run_dir), env=env, capture_output=True, text=True, timeout=2400)
    out = run_dir / "out"
    prod = [f for f in out.rglob("*") if f.is_file() and f.name != "versions.yml" and f.stat().st_size > 0] if out.exists() else []
    if p.returncode == 0 and prod:
        return (pkg_dir.name, "PASS", f"{len(prod)} outputs")
    return (pkg_dir.name, "exec_error", real_err(p.stdout + p.stderr))

def main():
    pkgs = sorted([d for d in BIOC.iterdir() if d.is_dir() and (d / "main.nf").exists()])
    # filter to local domains quickly
    todo = [d for d in pkgs if domain_of((d / "main.nf").read_text()) in LOCAL_DOMAINS]
    print(f"local-domain packages to test: {len(todo)}", flush=True)
    results = []
    with ThreadPoolExecutor(max_workers=3) as ex:
        futs = {ex.submit(run_pkg, d): d for d in todo}
        for i, f in enumerate(as_completed(futs), 1):
            r = f.result()
            if r:
                results.append(r)
                print(f"  [{i}/{len(todo)}] {r[0]}: {r[1]}  {r[2][:90]}", flush=True)
    json.dump(results, open("/tmp/pwa_batch_result.json", "w"), indent=2)
    from collections import Counter
    print("STATUS:", dict(Counter(r[1] for r in results)))

if __name__ == "__main__":
    main()
