#!/usr/bin/env python3
"""TIERED EXECUTION grader for the nextflow_coding benchmark.

This grader ACTUALLY INVOKES nextflow — it does not pattern-match the .nf text.
A tier only passes if the real `nextflow` binary returns the expected result.

Tiers (cheap -> expensive):
  Tier A  parse/compile    `nextflow run <f> -preview`   (exit 0 = syntax ok + DAG builds)
  Tier B  pipeline wiring  `nextflow run <f> -stub-run`  (exit 0 = channels/process I/O wire up,
                           running every process stub/script with NO real tools or data)
  Tier C  real execution   `nextflow run <f>` + output-file CONTRACT
                           (exit 0 AND every expected output file exists in the run dir
                            with the required content). Only for tasks flagged runnable:true.

Aggregate score (per task, max 1.0):  A=0.34, B=0.33, C=0.33.
Tiers are gated: B is only attempted if A passed; C only if B passed. A task with
runnable:false has no Tier C, so its max is A+B = 0.67 and C is reported null.
The reported aggregate normalises each task to its own achievable max, so convert/fix/write
tasks are comparable regardless of whether they carry a Tier-C contract.

Usage:
  # grade a directory of generated files named <task_id>.nf
  python3 grade.py tasks.jsonl --gen-dir path/to/gen [--out results.json]
  # grade a single file against one task
  python3 grade.py tasks.jsonl --task-id write_status_pipeline --nf some.nf

Requires `nextflow` on PATH (set NEXTFLOW_BIN to override) and Java 17+.
"""
import argparse, json, os, shutil, subprocess, sys, tempfile, uuid
from pathlib import Path

NEXTFLOW = os.environ.get("NEXTFLOW_BIN", "nextflow")
PER_CALL_TIMEOUT = int(os.environ.get("NF_TIMEOUT", "240"))  # seconds per nextflow invocation


def _have_nextflow():
    return shutil.which(NEXTFLOW) is not None


def _run_nf(nf_text, extra_args):
    """Run `nextflow run main.nf <extra_args>` in an isolated temp dir.
    Returns (exit_code, run_dir, combined_log). run_dir is left on disk for the caller
    (Tier C scans it) and must be cleaned up by the caller."""
    run_dir = tempfile.mkdtemp(prefix="nfgrade_")
    (Path(run_dir) / "main.nf").write_text(nf_text)
    env = dict(os.environ)
    env["NXF_ANSI_LOG"] = "false"
    env.setdefault("NXF_HOME", str(Path(run_dir) / ".nextflow_home"))
    cmd = [NEXTFLOW, "-quiet", "run", "main.nf"] + extra_args
    try:
        p = subprocess.run(cmd, cwd=run_dir, env=env, capture_output=True,
                           text=True, timeout=PER_CALL_TIMEOUT)
        return p.returncode, run_dir, (p.stdout + p.stderr)
    except subprocess.TimeoutExpired as e:
        return 124, run_dir, f"TIMEOUT after {PER_CALL_TIMEOUT}s\n{e}"


def _count_processes(run_dir):
    """Count DISTINCT process names that actually executed, from the stub-run trace file.
    This is an execution signal (the DAG really ran), not a regex over the .nf source —
    a monolithic one-process pipeline reports 1 here no matter how its script is written.
    Fan-out tags like 'TAG (2)' collapse to their process name 'TAG'."""
    tf = Path(run_dir) / "trace.txt"
    if not tf.exists():
        return 0
    names = set()
    for i, line in enumerate(tf.read_text().splitlines()):
        if i == 0:  # header row: task_id<TAB>hash<TAB>native_id<TAB>name<TAB>...
            continue
        cols = line.split("\t")
        if len(cols) >= 4 and cols[3].strip():
            names.add(cols[3].split(" (")[0].strip())
    return len(names)


def _check_outputs(run_dir, outputs):
    """Scan the run dir recursively (covers work/<hash>/ and any publishDir) for each
    expected output: a file matching `glob` whose text contains ALL `contains` substrings.
    Returns (ok, detail_list)."""
    root = Path(run_dir)
    details = []
    all_ok = True
    for spec in outputs or []:
        glob = spec["glob"]
        needles = spec.get("contains", [])
        hit = None
        for cand in root.rglob(glob):
            if not cand.is_file():
                continue
            try:
                txt = cand.read_text(errors="replace")
            except Exception:
                continue
            if all(n in txt for n in needles):
                hit = str(cand.relative_to(root))
                break
        ok = hit is not None
        all_ok = all_ok and ok
        details.append({"glob": glob, "contains": needles,
                        "found": hit, "pass": ok})
    return all_ok, details


def grade_one(nf_text, task):
    """Execute the three tiers for one generated .nf against one task record."""
    contract = task.get("expected_contract", {})
    runnable = bool(contract.get("runnable", False))
    min_proc = contract.get("min_processes")  # decompose/notebook: >=N distinct processes
    res = {"id": task["id"], "kind": task.get("kind"),
           "tierA_pass": False, "tierB_pass": None, "tierC_pass": None,
           "runnable": runnable, "min_processes": min_proc, "n_processes": None,
           "logs": {}, "outputs": None}

    if not nf_text or not nf_text.strip():
        res["logs"]["error"] = "empty generation"
        res["score"] = 0.0
        return res

    # Tier A: parse / preview
    codeA, dirA, logA = _run_nf(nf_text, ["-preview"])
    res["tierA_pass"] = (codeA == 0)
    res["logs"]["A"] = logA[-800:]
    shutil.rmtree(dirA, ignore_errors=True)

    # Tier B: stub-run (gated on A). -with-trace lets us count processes that really ran.
    if res["tierA_pass"]:
        codeB, dirB, logB = _run_nf(nf_text, ["-stub-run", "-with-trace", "trace.txt"])
        stub_ok = (codeB == 0)
        res["n_processes"] = _count_processes(dirB)
        if min_proc is not None:
            # a monolithic conversion stub-runs fine but has too few processes -> Tier B fails
            res["tierB_pass"] = stub_ok and res["n_processes"] >= min_proc
        else:
            res["tierB_pass"] = stub_ok
        res["logs"]["B"] = logB[-800:]
        shutil.rmtree(dirB, ignore_errors=True)
    else:
        res["tierB_pass"] = False
        res["n_processes"] = 0

    # Tier C: real run + output contract (gated on B, only if runnable)
    if runnable:
        if res["tierB_pass"]:
            codeC, dirC, logC = _run_nf(nf_text, [])
            if codeC == 0:
                ok, details = _check_outputs(dirC, contract.get("outputs", []))
                res["tierC_pass"] = ok
                res["outputs"] = details
            else:
                res["tierC_pass"] = False
            res["logs"]["C"] = logC[-800:]
            shutil.rmtree(dirC, ignore_errors=True)
        else:
            res["tierC_pass"] = False
    else:
        res["tierC_pass"] = None  # not applicable

    # Per-task score, normalised to achievable max
    a = 1.0 if res["tierA_pass"] else 0.0
    b = 1.0 if res["tierB_pass"] else 0.0
    if runnable:
        c = 1.0 if res["tierC_pass"] else 0.0
        res["score"] = round((0.34 * a + 0.33 * b + 0.33 * c), 4)
    else:
        # normalise A+B weights to 1.0 when no Tier C
        res["score"] = round((0.34 * a + 0.33 * b) / 0.67, 4)
    return res


def aggregate(results):
    n = len(results)
    def rate(key):
        vals = [r[key] for r in results if r.get(key) is not None]
        return round(sum(1 for v in vals if v) / max(len(vals), 1), 4) if vals else None
    return {
        "benchmark": "nextflow_coding",
        "n_tasks": n,
        "tierA_pass_rate": rate("tierA_pass"),
        "tierB_pass_rate": rate("tierB_pass"),
        "tierC_pass_rate": rate("tierC_pass"),
        "tierC_eligible": sum(1 for r in results if r.get("runnable")),
        "mean_score": round(sum(r["score"] for r in results) / max(n, 1), 4),
        "by_kind": {
            k: round(sum(r["score"] for r in results if r["kind"] == k) /
                     max(sum(1 for r in results if r["kind"] == k), 1), 4)
            for k in sorted({r["kind"] for r in results})
        },
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tasks", help="tasks.jsonl")
    ap.add_argument("--gen-dir", help="dir with <task_id>.nf generations")
    ap.add_argument("--task-id", help="grade a single task")
    ap.add_argument("--nf", help="single .nf file (with --task-id)")
    ap.add_argument("--out", help="write full results JSON here")
    ap.add_argument("--quiet-logs", action="store_true", help="drop per-tier logs from output")
    args = ap.parse_args()

    if not _have_nextflow():
        sys.exit(f"ERROR: `{NEXTFLOW}` not on PATH — this grader must execute nextflow. "
                 "Install it (curl -s https://get.nextflow.io | bash) or set NEXTFLOW_BIN.")

    tasks = {json.loads(l)["id"]: json.loads(l) for l in open(args.tasks)}

    results = []
    if args.task_id:
        t = tasks[args.task_id]
        nf_text = Path(args.nf).read_text() if args.nf else ""
        results.append(grade_one(nf_text, t))
    elif args.gen_dir:
        for tid, t in tasks.items():
            fp = Path(args.gen_dir) / f"{tid}.nf"
            nf_text = fp.read_text() if fp.exists() else ""
            r = grade_one(nf_text, t)
            if not fp.exists():
                r["logs"]["error"] = f"missing generation {fp}"
            results.append(r)
            print(f"  {tid:28s} A={r['tierA_pass']} B={r['tierB_pass']} "
                  f"C={r['tierC_pass']} score={r['score']}", flush=True)
    else:
        sys.exit("provide --gen-dir OR (--task-id [--nf])")

    if args.quiet_logs:
        for r in results:
            r.pop("logs", None)

    agg = aggregate(results)
    payload = {"aggregate": agg, "results": results}
    print(json.dumps(agg, indent=2))
    if args.out:
        Path(args.out).write_text(json.dumps(payload, indent=2))
        print(f"\nwrote {args.out}")


if __name__ == "__main__":
    main()
