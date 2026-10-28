#!/usr/bin/env python3
"""Regenerate every figure and table from committed artifacts.
usage: python3 run_all.py [--twice]     (--twice runs everything a second time and verifies the outputs are byte-identical)
Writes out/assertion_log.txt, out/figure_sources.jsonl and out/MANIFEST.json (sha256 of every output + source commits)."""
import hashlib
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE / "out"
LAST_SRC: dict = {}
SCRIPTS = ["f1_schematic.py", "f2_dataset.py", "f3_validity_gates.py", "f_h4b_fewlabel.py", "f_l5_loop.py", "f8_strata.py", "f_cv_schemes.py",
           "f9_mmp_forest.py", "f_kphys_lolo.py", "f11_coverage.py", "f5_controls.py", "tables.py", "f_pending.py"]


def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()[:16]


def source_map() -> dict:
    """figure/table name -> {artifact path: sha256 of the content actually used}"""
    m = {}
    for l in (OUT / "figure_sources.jsonl").read_text().splitlines():
        it = json.loads(l)
        m[it["figure"]] = {s["path"]: s["sha256"] for s in it["sources"]}
    return m


def run_once() -> dict:
    for f in ("assertion_log.txt", "figure_sources.jsonl"):
        (OUT / f).unlink(missing_ok=True)
    for s in SCRIPTS:
        r = subprocess.run([sys.executable, s], cwd=HERE, capture_output=True, text=True)
        if r.returncode != 0:
            print(r.stdout[-1500:], r.stderr[-1500:])
            raise SystemExit(f"{s} failed")
        print(f"ran {s}")
    global LAST_SRC
    LAST_SRC = source_map()
    outs = sorted([p for p in OUT.rglob("*") if p.is_file() and p.suffix in (".pdf", ".png", ".md", ".csv") and "_committed" not in p.parts])
    return {str(p.relative_to(OUT)): sha(p) for p in outs}


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    first = run_once()
    log = (OUT / "assertion_log.txt").read_text().splitlines()
    n_ok = sum(l.startswith("OK") for l in log); n_fail = sum(l.startswith("FAIL") for l in log); n_warn = sum(l.startswith("NOTE") for l in log)
    print(f"assertions: {n_ok} OK, {n_fail} FAIL, {n_warn} warnings (artifacts whose working tree differs from HEAD: HEAD version used)")
    det = None
    if "--twice" in sys.argv:
        src1 = dict(LAST_SRC)
        second = run_once()
        diff = [k for k in first if first[k] != second.get(k)]
        def stem(k):
            return Path(k).stem.replace("_PENDING", "")
        changed = [k for k in diff if src1.get(stem(k)) != LAST_SRC.get(stem(k))]
        unexplained = [k for k in diff if k not in changed]
        det = {"identical": not diff, "source_changed_between_passes": changed, "unexplained_differences": unexplained}
        print("determinism:", det)
        (OUT / "determinism.json").write_text(json.dumps(det, indent=1))
    srcs = [json.loads(l) for l in (OUT / "figure_sources.jsonl").read_text().splitlines()]
    (OUT / "MANIFEST.json").write_text(json.dumps(dict(outputs=first, assertions=dict(ok=n_ok, fail=n_fail, warnings=n_warn), determinism=det, items=srcs), indent=1, default=str))
    if n_fail:
        raise SystemExit("assertion failures")
    if det and det["unexplained_differences"]:
        raise SystemExit("non-deterministic outputs with unchanged sources")
