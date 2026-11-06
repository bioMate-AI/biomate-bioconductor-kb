#!/usr/bin/env python3
"""
mine_fix_commits.py — Mine git history (ALL branches) for (broken -> fixed) repair pairs.

Candidate commits: message contains 'fix' (case-insensitive) AND touch either
  - any *.nf file, or
  - backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py

For each MODIFIED matching file in each such commit emit a triple to fix_triples.jsonl:
  {commit, short, date, file, message, kind, lines_added, lines_deleted, before, after}
where before/after are the file content at the commit's first parent / at the commit.

Noise filter (a pair / commit is dropped when):
  - before or after is empty / unreadable (new-file / delete / rename -> no repair pair)
  - binary diff
  - diff is whitespace-only (normalising whitespace makes before == after)
  - diff is huge: lines_added + lines_deleted > MAX_DIFF_LINES (2000)
  - the whole commit touches more than MAX_FILES_PER_COMMIT matching files: that is a
    bulk *.nf regeneration sweep, not a targeted repair (its per-file diffs are near-
    duplicate, low-signal), so the entire commit is skipped as noise and reported.

These triples are (broken code + rationale -> fixed code) repair-SFT data.
Writes manifest_fix.json (committed) with candidate counts and real usable yield.

Perf: one `git show --numstat` per commit gives the file list + line counts + binary
flag in a single subprocess; whitespace-only is detected in Python from before/after
(no extra subprocess); only two `git show ref:path` calls per kept file.
"""
import json, os, subprocess, hashlib, sys, re

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(HERE, "fix_triples.jsonl")
MANIFEST = os.path.join(HERE, "manifest_fix.json")
EXECUTOR = "backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py"
MAX_DIFF_LINES = 2000
MAX_FILES_PER_COMMIT = 50
_WS = re.compile(r"\s+")


def git(args, binary=False):
    r = subprocess.run(["git", "-C", REPO] + args, capture_output=True)
    if binary:
        return r.returncode, r.stdout
    return r.returncode, r.stdout.decode("utf-8", errors="replace")


def fix_commit_shas(pathspec):
    rc, out = git(["log", "--all", "-i", "--grep=fix", "--format=%H", "--", pathspec])
    return set(l.strip() for l in out.splitlines() if l.strip())


def numstat_files(sha):
    """[(added, deleted, path, is_binary)] for matching files in sha vs first parent."""
    rc, out = git(
        ["show", "--first-parent", "--numstat", "--format=", sha, "--", "*.nf", EXECUTOR]
    )
    files = []
    for line in out.splitlines():
        if not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        a, d, path = parts[0], parts[1], parts[-1]
        is_bin = a == "-" or d == "-"
        ai = 0 if is_bin else int(a)
        di = 0 if is_bin else int(d)
        files.append((ai, di, path, is_bin))
    return files


def file_at(ref, path):
    rc, data = git(["show", f"{ref}:{path}"], binary=True)
    if rc != 0:
        return None
    if b"\x00" in data[:8000]:
        return None
    return data.decode("utf-8", errors="replace")


def main():
    nf = fix_commit_shas("*.nf")
    ex = fix_commit_shas(EXECUTOR)
    union = nf | ex
    print(f"candidate commits: .nf={len(nf)}  executor={len(ex)}  union={len(union)}")

    # order commits chronologically for stable output
    rc, out = git(["log", "--all", "--format=%H %ct"])
    order = {}
    for line in out.splitlines():
        sha, _, ct = line.partition(" ")
        if sha in union and sha not in order:
            order[sha] = int(ct or 0)
    ordered = sorted(union, key=lambda s: order.get(s, 0))

    dropped = {"empty_side": 0, "binary": 0, "whitespace_only": 0, "too_large": 0}
    bulk_commits_skipped = 0
    bulk_files_skipped = 0
    kept = kept_nf = kept_exec = 0
    commits_with_pair = set()

    with open(OUT, "w", encoding="utf-8") as f:
        for i, sha in enumerate(ordered):
            if i % 100 == 0:
                print(f"  ...{i}/{len(ordered)} commits, {kept} pairs kept", file=sys.stderr)
            files = numstat_files(sha)
            if len(files) > MAX_FILES_PER_COMMIT:
                bulk_commits_skipped += 1
                bulk_files_skipped += len(files)
                continue
            _, msg = git(["show", "-s", "--format=%B", sha])
            msg = msg.strip()
            _, dt = git(["show", "-s", "--format=%cI", sha])
            dt = dt.strip()
            for added, deleted, path, is_bin in files:
                if is_bin:
                    dropped["binary"] += 1
                    continue
                if added + deleted > MAX_DIFF_LINES:
                    dropped["too_large"] += 1
                    continue
                before = file_at(f"{sha}^", path)
                after = file_at(sha, path)
                if not before or not after or not before.strip() or not after.strip():
                    dropped["empty_side"] += 1
                    continue
                if _WS.sub(" ", before).strip() == _WS.sub(" ", after).strip():
                    dropped["whitespace_only"] += 1
                    continue
                kind = "executor" if path == EXECUTOR else "nf"
                rec = {
                    "commit": sha,
                    "short": sha[:9],
                    "date": dt,
                    "file": path,
                    "message": msg,
                    "kind": kind,
                    "lines_added": added,
                    "lines_deleted": deleted,
                    "before": before,
                    "after": after,
                }
                f.write(json.dumps(rec, ensure_ascii=False) + "\n")
                kept += 1
                commits_with_pair.add(sha)
                if kind == "nf":
                    kept_nf += 1
                else:
                    kept_exec += 1

    out_size = os.path.getsize(OUT)
    sha256 = hashlib.sha256(open(OUT, "rb").read()).hexdigest()
    manifest = {
        "candidate_commits": {
            "nf_fix_commits": len(nf),
            "executor_fix_commits": len(ex),
            "union": len(union),
        },
        "usable_triples": kept,
        "usable_triples_nf": kept_nf,
        "usable_triples_executor": kept_exec,
        "commits_producing_a_pair": len(commits_with_pair),
        "bulk_commits_skipped": bulk_commits_skipped,
        "bulk_files_skipped": bulk_files_skipped,
        "max_files_per_commit": MAX_FILES_PER_COMMIT,
        "max_diff_lines": MAX_DIFF_LINES,
        "dropped_pairs": dropped,
        "output_file": os.path.basename(OUT),
        "output_bytes": out_size,
        "output_sha256": sha256,
    }
    json.dump(manifest, open(MANIFEST, "w"), indent=2)
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
