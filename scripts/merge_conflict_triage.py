#!/usr/bin/env python3
"""Triage the conflicts of an IN-PROGRESS merge (run inside a worktree after `git merge --no-commit <other>`).

  python3 scripts/merge_conflict_triage.py <other-ref> [--apply] [--json OUT]

For every unmerged file it checks whether one side's file is byte-identical to an EARLIER version of the same file in the other
side's history since the merge-base. If the other side's file already appeared in our history, the other side adds nothing newer:
TAKE_OURS (and symmetrically TAKE_THEIRS). Anything else is MANUAL (or ADD/DELETE). --apply performs only the provable
resolutions (`git checkout --ours/--theirs` + `git add`); it never touches MANUAL files. Read-only without --apply.
"""
import argparse, json, subprocess, sys


def sh(*a):
    return subprocess.run(a, capture_output=True, text=True).stdout.strip()


def blob(rev, f):
    return sh("git", "rev-parse", "-q", "--verify", "%s:%s" % (rev, f))


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("other"); ap.add_argument("--apply", action="store_true"); ap.add_argument("--json")
    a = ap.parse_args()
    mb = sh("git", "merge-base", "HEAD", a.other)
    files = [f for f in sh("git", "diff", "--name-only", "--diff-filter=U").split("\n") if f]
    plan = {}
    for f in files:
        tb, ob = blob(a.other, f), blob("HEAD", f)
        ours_hist = {blob(c, f) for c in sh("git", "log", "--format=%H", "%s..HEAD" % mb, "--", f).split() if c}
        theirs_hist = {blob(c, f) for c in sh("git", "log", "--format=%H", "%s..%s" % (mb, a.other), "--", f).split() if c}
        text = open(f, errors="ignore").read() if tb and ob else ""
        hunks = text.count("\n<<<<<<< ") + (1 if text.startswith("<<<<<<< ") else 0)
        if tb and tb in ours_hist:
            cls = "TAKE_OURS"
        elif ob and ob in theirs_hist:
            cls = "TAKE_THEIRS"
        elif not tb or not ob:
            cls = "ADD_DELETE"
        else:
            cls = "MANUAL"
        plan[f] = {"class": cls, "hunks": hunks}
    if a.apply:
        for f, p in plan.items():
            if p["class"] in ("TAKE_OURS", "TAKE_THEIRS"):
                subprocess.run(["git", "checkout", "--ours" if p["class"] == "TAKE_OURS" else "--theirs", "--", f], check=True)
                subprocess.run(["git", "add", "--", f], check=True)
    for f, p in sorted(plan.items(), key=lambda x: (x[1]["class"], -x[1]["hunks"])):
        print("%-12s %3d hunks  %s" % (p["class"], p["hunks"], f))
    print("merge-base %s; %d files: %s" % (mb[:9], len(plan), {c: sum(1 for p in plan.values() if p["class"] == c) for c in {p["class"] for p in plan.values()}}))
    if a.json:
        json.dump(plan, open(a.json, "w"), indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
