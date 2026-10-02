#!/usr/bin/env python3
"""
audit_fabrication.py — CLASS GUARD against fabricated-result workflows.

Invariant enforced: NO `executable=1` workflow may fabricate its outputs, i.e. generate
result values with an RNG (`np.random.*` / `random.*` / `runif`/`rnorm`/`rpois`/`rbinom`)
AND write output (`to_csv`/`savefig`/`json.dump`/`write.csv`/`saveRDS`/`writeLines`/`.write(`)
AND read NO input — judged on CODE LINES ONLY (comments stripped, so anti-fabrication guard
comments don't false-positive).

Why this exists: MERFISH shipped a stub that emitted `random.*` fake Moran's I as if real; a
platform audit then found ~11 more "Analyze/Quantify" workflows doing the same (incl.
metal_meta_analysis inventing GWAS summary stats). Those were disabled (executable=0). This
guard stops a NEW fabricating stub from entering the catalog as executable.
See docs/20261002_FABRICATION_AUDIT.md and docs/20261001_MERFISH_SPATIAL.md.

A trip is NOT automatically a bug — it forces triage:
  * genuinely fabricating analysis workflow  -> fix it (rewire to a real tool) or set executable=0
  * legitimately RNG (an array/IO package whose purpose IS random data, a simulation, or an
    honestly-labeled synthetic demo) -> add its id to ALLOWLIST below WITH a one-line reason.

Usage:
    python scripts/audit_fabrication.py [--db PATH] [--list]
Exit 0 = clean (no non-allowlisted executable fabricators). Exit 1 = offenders found.
Requires the FULL enriched galaxy_ai_tools.db (dev/S3 or CI-pulled); the local stub lacks the
real `executable` flags, so run it where the full DB is present (CI, or after an S3 pull).
"""
from __future__ import annotations
import argparse, os, re, sqlite3, sys

# Reviewed-legitimate RNG (kept executable). id -> reason. Adding here requires a human judgment
# that the RNG is the workflow's PURPOSE (not fake analysis results).
ALLOWLIST = {
    11022: "BumpyMatrix — ragged-array data-structure demo; random array IS the point",
    11084: "chihaya — DelayedArray serialization demo; random array is the fixture",
    11237: "DelayedRandomArray — package literally produces random arrays by design",
    12541: "TileDBArray — array backend demo; random array is the fixture",
    11359: "ExperimentSubset — SCE subsetting demo; random fixture",
    11709: "LoomExperiment — loom I/O demo; random fixture",
    11038: "CardinalIO — imzML write/round-trip I/O demo (writeImzML), not analysis output",
    10726: "Simulate Microbial Population Dynamics — a SIMULATION; RNG is the method",
    14629: "Virtual Patient Cohort — synthetic cohort by design (clearly labeled virtual)",
    14516: "Hts Plate Qc Hit Calling — fabricates but HONESTLY labels data_source='synthetic_demo'",
    10597: "Save Image — utility that writes a test image, not an analysis result",
}

RNG = re.compile(r'(np\.random\.(randn|randint|uniform|normal|rand|choice|poisson|standard_normal)'
                 r'|random\.(uniform|gauss|randint|choice|normalvariate|sample|random)'
                 r'|\brunif\(|\brnorm\(|\brpois\(|\brbinom\()')
WRITES = re.compile(r'to_csv\(|savefig\(|json\.dump|write\.csv\(|saveRDS\(|writeLines\(|\.write\(|write_csv\(')
READS = re.compile(r'read\.csv|readRDS|read_csv|read\.table|readImzML|stageAs|Read10X|read10x|'
                   r'pd\.read|np\.load|np\.loadtxt|np\.genfromtxt|sc\.read|ad\.read|h5read|readLines|'
                   r'params\.input|input_file|argv|args\[|read\.delim|readr::|loadRData|fromJSON|load\(|'
                   # staging / domain file readers all count as ingesting real input
                   r'shutil\.copy|shutil\.move|SeqIO\.(parse|read)|pysam\.|cv2\.imread|imread\(|tifffile|'
                   r'flowio|FlowData|io\.imread|skimage\.io|Image\.open|readfcs|fcsparser|FCMeasurement|nd2')
# An honestly-LABELED synthetic/demo fallback (clearly disclosed to the user) is not deceptive
# fabrication. These biomni "Analyze X" workflows do real analysis on real input and only
# synthesize when input is absent, writing a "DEMO MODE / synthetic / provide X for actual analysis"
# notice. That is acceptable; deceptive fabrication (merfish's old stub) is UNLABELED and fakes a
# versions.yml claiming tools it never ran.
DEMO_LABELED = re.compile(r'DEMO MODE|synthetic data|for demonstration|provide .*for actual|'
                          r'synthetic .*(track|data|cohort|demo)|demonstration purposes|use_baked_toy',
                          re.I)
# A real external tool invocation means the workflow does genuine work (not pure fabrication),
# even if it also has an opt-in toy/demo RNG path (e.g. metal_meta_analysis runs the real `metal`
# binary; comparative-genomics runs real `bwa`). Presence of this downgrades an RNG hit.
REALTOOL = re.compile(r'subprocess\.(run|call|check_call|check_output|Popen)|os\.system\(|'
                      r'system2?\(|check_call|check_output|\bRscript\b|\bmetal\b|\bbwa\b|\bsamtools\b|'
                      r'\bbcftools\b|\bplink\b|\bgatk\b')

def strip_comments(text: str) -> str:
    out = []
    for line in text.splitlines():
        s = line.lstrip()
        if s.startswith(("#", "//", "*", "/*")):
            continue
        out.append(line)
    return "\n".join(out)

def find_nf(filename: str, repo_root: str) -> str | None:
    if not filename:
        return None
    for base in ("backend", "backend/biomni_workflows", "."):
        p = os.path.join(repo_root, base, filename)
        if os.path.isfile(p):
            return p
    return None

def main() -> int:
    ap = argparse.ArgumentParser()
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap.add_argument("--db", default=os.path.join(repo_root, "backend/database/galaxy_ai_tools.db"))
    ap.add_argument("--list", action="store_true", help="also print allowlisted legit-RNG entries")
    args = ap.parse_args()

    if not os.path.isfile(args.db):
        print(f"[audit_fabrication] DB not found: {args.db}", file=sys.stderr)
        return 2
    c = sqlite3.connect(args.db)
    try:
        rows = c.execute("SELECT id,name,filename,domain FROM workflows WHERE executable=1").fetchall()
    except sqlite3.OperationalError as e:
        print(f"[audit_fabrication] cannot read workflows: {e}", file=sys.stderr)
        return 2

    offenders, allowed_hit, scanned = [], [], 0
    for wid, name, filename, domain in rows:
        p = find_nf(filename, repo_root)
        if not p:
            continue
        scanned += 1
        code = strip_comments(open(p, errors="replace").read())
        # Pure (deceptive) fabrication = RNG produces output, with NO real input read, NO real tool
        # run, AND no honest demo/synthetic label. Reading input (incl. staging), invoking a real
        # external tool, or clearly disclosing a synthetic/demo fallback all mean it is not
        # deceptive fabrication.
        if (RNG.search(code) and WRITES.search(code)
                and not READS.search(code) and not REALTOOL.search(code)
                and not DEMO_LABELED.search(code)):
            (allowed_hit if wid in ALLOWLIST else offenders).append((wid, name, domain))

    print(f"[audit_fabrication] scanned {scanned} executable workflows with a .nf on disk")
    if args.list and allowed_hit:
        print(f"[audit_fabrication] {len(allowed_hit)} allowlisted legit-RNG entries (kept executable):")
        for wid, name, _ in sorted(allowed_hit):
            print(f"    OK   [{wid}] {name} — {ALLOWLIST[wid]}")

    if offenders:
        print(f"\n[audit_fabrication] FAIL — {len(offenders)} executable workflow(s) fabricate results "
              f"(RNG->output, no input read):", file=sys.stderr)
        for wid, name, domain in sorted(offenders):
            print(f"    FABRICATES [{wid}] {name} ({domain})", file=sys.stderr)
        print("\nFix each: rewire to a real tool, OR set executable=0, OR (if RNG is legitimately "
              "its purpose) add the id to ALLOWLIST in this script with a reason.", file=sys.stderr)
        return 1

    print("[audit_fabrication] PASS — no non-allowlisted executable fabricators.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
