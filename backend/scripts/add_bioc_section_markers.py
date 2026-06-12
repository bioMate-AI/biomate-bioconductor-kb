#!/usr/bin/env python3
"""
add_bioc_section_markers.py  (B-1)
==================================

The Bioconductor UI step list is degraded.  ``_parse_nextflow_steps`` in
``backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py`` produces per-step UI
cards for a single-process Bioconductor stub from two authoritative sources:

  * Strategy 0 — a documented ``// Steps:`` header of the form
    ``//  * N. [Phase] Title`` (parsed by ``doc_re``); and
  * Strategy 1b — in-body R section markers of the form ``# --- Title ---``
    (parsed by ``sec_re``), used when exactly one process is present.

Only ~192 of the 3,353 regenerated bioc ``.nf`` carry ``# ---`` markers, and a
large slice of the rest carry a *mangled* single-line ``// Steps:`` block where
the generator crammed the whole multi-stage ``stages`` text onto step 1
(``//  * 1. [Phase] do A. 2. do B. 3. do C``).  Both failure modes collapse the
UI to one coarse step.

This script repairs both, using the **real** per-step boundaries the
interpret->build generator already wrote into each R body as numbered section
comments — the same boundaries that line up with the sibling
``_interpretation.json`` ``stages`` field.  Recognised in-body forms, in
priority order:

  * ``# Stage N: Title`` / ``# STAGE N: Title``
  * ``# Step N: Title``
  * ``# N. Title``

For each marker-less file the script:

  1. detects those boundaries (>=2 distinct-numbered comments required);
  2. rewrites each detected R comment line **in place** into the parser's
     marker form ``# --- Title ---`` (an R comment — runnable R/Groovy is never
     touched); and
  3. if a mangled ``// Steps:`` block is present (yielding <2 ``doc_re`` steps),
     regenerates it as a proper multi-line ``//  * N. [Phase] Title`` block from
     the same titles, so Strategy 0 (which returns *before* Strategy 1b) also
     yields the correct count.

Files with no recognisable boundary are reported and left untouched — we never
fabricate splits.  Triple-quote (R-script heredoc) parity is asserted unchanged for every
rewritten file; ``versions.yml`` ``writeLines`` blocks are never altered (they
contain no step-comment lines).

Usage::

    python3 backend/scripts/add_bioc_section_markers.py --dry-run
    python3 backend/scripts/add_bioc_section_markers.py            # apply
    python3 backend/scripts/add_bioc_section_markers.py --pkg diffcyt --dry-run
"""
from __future__ import annotations

import argparse
import glob
import os
import re
import sys

# ---------------------------------------------------------------------------
# Parser-mirroring regexes (kept byte-identical to ai_assistant.py).
# ---------------------------------------------------------------------------
# Strategy 0 documented-step header.
DOC_RE = re.compile(
    r'^\s*//\s*\*\s*(\d+)\.\s*(?:\[([^\]]+)\]\s*)?(.+?)\s*$', re.MULTILINE)
# Strategy 1b in-body marker.
SEC_RE = re.compile(
    r'#\s*---\s*([A-Za-z][^[#\n]{2,60}?)\s*(?:\[\]|(?:\[.*?\]))?\s*---')
SEC_SKIP = re.compile(
    r'(?i)^(save\s+output|versions?\.yml|write\s+output|output\s+file|cleanup|done)$')
# Authoritative process counter.
PROC_RE = re.compile(r'^process\s+([A-Za-z][A-Za-z0-9_]+)\s*\{', re.MULTILINE)

# ---------------------------------------------------------------------------
# In-body step-comment forms (priority order: Stage, Step, then "N.").
# Each captures (number, title).  Anchored to a whole comment line.
# ---------------------------------------------------------------------------
RX_STAGE = re.compile(r'^(\s*)#\s*[Ss][Tt][Aa][Gg][Ee]\s+(\d{1,2})\s*[:.\-]\s*(\S.*?)\s*$')
RX_STEP = re.compile(r'^(\s*)#\s*[Ss]tep\s+(\d{1,2})\s*[:.\-]\s*(\S.*?)\s*$')
RX_NUM = re.compile(r'^(\s*)#\s*(\d{1,2})\.\s+(\S.*?)\s*$')
_FORMS = (RX_STAGE, RX_STEP, RX_NUM)

BIOC_GLOB = (
    "backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/**/*.nf"
)


def sanitize_title(title: str) -> str:
    """Coerce a raw step title into a string that survives the parser SEC_RE.

    SEC_RE requires: starts with a letter, 3-60 chars, contains no '[' or '#'.
    We also strip a trailing period and collapse whitespace.  Returns "" if the
    result cannot satisfy the parser (caller then drops it).
    """
    t = title.strip()
    # Drop a trailing sentence period and any trailing marker dashes.
    t = re.sub(r'[\s.\-]+$', '', t).strip()
    # The parser forbids '[' and '#'; remap to harmless characters.
    t = t.replace('#', ' ').replace('[', '(').replace(']', ')')
    t = re.sub(r'\s+', ' ', t).strip()
    if len(t) > 58:
        # Truncate on a word boundary where possible.
        cut = t[:58]
        if ' ' in cut:
            cut = cut[:cut.rfind(' ')]
        t = cut.strip()
    if not t or not re.match(r'[A-Za-z]', t):
        return ""
    if len(t) < 3 or len(t) > 60:
        return ""
    if '[' in t or '#' in t:
        return ""
    if SEC_SKIP.match(t):
        return ""
    return t


def parser_step_count(content: str) -> int:
    """Replicate the parser step count for a single .nf body."""
    if "// Steps:" in content:
        ds = DOC_RE.findall(content)
        if ds:
            return len(ds)
    procs = PROC_RE.findall(content)
    n = len(procs)
    if n == 1:
        secs = [m.group(1).strip() for m in SEC_RE.finditer(content)]
        secs = [s for s in secs if s and len(s) <= 60 and not SEC_SKIP.match(s)]
        if len(secs) >= 2:
            return len(secs)
    if n >= 1:
        return n
    return 0


def detect_boundaries(lines: list[str]):
    """Return [(line_index, indent, number, raw_title)] for the first form that
    yields >=2 distinct-numbered matches, else []."""
    for rx in _FORMS:
        hits = []
        seen = set()
        for i, ln in enumerate(lines):
            m = rx.match(ln)
            if not m:
                continue
            indent, num, title = m.group(1), int(m.group(2)), m.group(3)
            if num in seen:
                # Duplicate number (e.g. a banner echoes "# 1." twice) — keep
                # only the first; later duplicates are left as-is.
                continue
            seen.add(num)
            hits.append((i, indent, num, title))
        if len(hits) >= 2:
            return hits
    return []


def extract_phase_label(content: str) -> str:
    """Pull the '[Phase]' label from an existing // Steps: block, if any, so the
    regenerated block keeps the generator's phase grouping."""
    for ln in content.splitlines():
        m = re.match(r'^\s*//\s*\*\s*\d+\.\s*\[([^\]]+)\]', ln)
        if m:
            return m.group(1).strip()
    return ""


def rebuild_steps_block(lines: list[str], titles: list[str], phase: str):
    """If a mangled '// Steps:' block (one that DOC_RE reduces to <2 steps) is
    present, replace its '//  * N.' lines with a clean multi-line block built
    from `titles`.  Returns (new_lines, changed_bool)."""
    content = "\n".join(lines)
    if "// Steps:" not in content:
        return lines, False
    ds = DOC_RE.findall(content)
    if len(ds) >= 2:
        # Header already healthy; nothing to do here.
        return lines, False

    # Locate the contiguous run of '//  * N.' lines (the block body).
    star_idx = [i for i, ln in enumerate(lines)
                if re.match(r'^\s*//\s*\*\s*\d+\.', ln)]
    if not star_idx:
        return lines, False
    lo, hi = min(star_idx), max(star_idx)
    if any(i not in star_idx for i in range(lo, hi + 1)):
        # Non-contiguous / interleaved — too risky to splice; leave it.
        return lines, False

    phase_tag = f"[{phase}] " if phase else ""
    new_block = [
        f"//  * {n}. {phase_tag}{t}" for n, t in enumerate(titles, start=1)
    ]
    out = lines[:lo] + new_block + lines[hi + 1:]
    return out, True


def process_file(path: str, dry_run: bool):
    """Return a dict describing the action taken for one .nf file."""
    original = open(path, encoding="utf-8", errors="replace").read()
    if parser_step_count(original) >= 2:
        return {"path": path, "status": "already_ok"}

    lines = original.split("\n")
    boundaries = detect_boundaries(lines)
    if not boundaries:
        return {"path": path, "status": "no_boundary"}

    # Sanitize titles; require >=2 to survive the parser.
    san = [(i, indent, sanitize_title(title)) for i, indent, _n, title in boundaries]
    san_valid = [(i, indent, t) for i, indent, t in san if t]
    if len(san_valid) < 2:
        return {"path": path, "status": "title_unusable"}

    # (1) Rewrite each detected R comment line in-place into '# --- Title ---'.
    new_lines = list(lines)
    for i, indent, title in san_valid:
        new_lines[i] = f"{indent}# --- {title} ---"

    # (2) Repair a mangled '// Steps:' block from the same titles.
    titles_only = [t for _i, _ind, t in san_valid]
    phase = extract_phase_label(original)
    new_lines, steps_changed = rebuild_steps_block(new_lines, titles_only, phase)

    new_content = "\n".join(new_lines)

    # --- Safety guards ------------------------------------------------------
    # Triple-quote parity must be unchanged (we only touch comment lines, but
    # assert it explicitly).
    if original.count('"""') != new_content.count('"""'):
        return {"path": path, "status": "tripleq_parity_broken"}
    # The new body must actually give the parser >=2 steps.
    after = parser_step_count(new_content)
    if after < 2:
        return {"path": path, "status": "parser_still_degraded", "after": after}

    if not dry_run and new_content != original:
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(new_content)

    return {
        "path": path,
        "status": "rewritten",
        "n_markers": len(san_valid),
        "steps_block_rebuilt": steps_changed,
        "after": after,
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true",
                    help="report planned changes without writing files")
    ap.add_argument("--pkg", default=None,
                    help="restrict to a single bioconductor package directory name")
    ap.add_argument("--repo-root", default=None,
                    help="repo root (default: two levels above this script)")
    args = ap.parse_args()

    repo_root = args.repo_root or os.path.abspath(
        os.path.join(os.path.dirname(__file__), "..", ".."))
    pattern = os.path.join(repo_root, BIOC_GLOB)
    files = sorted(glob.glob(pattern, recursive=True))
    if args.pkg:
        needle = f"/bioconductor/{args.pkg}/"
        files = [f for f in files if needle in f]
    if not files:
        print(f"[add_bioc_section_markers] no .nf found under {pattern}", file=sys.stderr)
        return 1

    counts = {
        "already_ok": 0, "rewritten": 0, "no_boundary": 0,
        "title_unusable": 0, "tripleq_parity_broken": 0,
        "parser_still_degraded": 0,
    }
    no_boundary, problems, rebuilt_blocks = [], [], 0
    for f in files:
        r = process_file(f, args.dry_run)
        counts[r["status"]] = counts.get(r["status"], 0) + 1
        if r["status"] == "no_boundary":
            no_boundary.append(f)
        elif r["status"] in ("tripleq_parity_broken", "parser_still_degraded", "title_unusable"):
            problems.append((f, r["status"]))
        elif r["status"] == "rewritten" and r.get("steps_block_rebuilt"):
            rebuilt_blocks += 1

    mode = "DRY-RUN" if args.dry_run else "APPLIED"
    print(f"\n[add_bioc_section_markers] {mode} over {len(files)} bioc .nf")
    print(f"  already_ok (>=2 steps)      : {counts['already_ok']}")
    print(f"  rewritten                   : {counts['rewritten']}"
          f"  (of which // Steps: block rebuilt: {rebuilt_blocks})")
    print(f"  no recognisable boundary    : {counts['no_boundary']}  (skipped, untouched)")
    if counts.get("title_unusable"):
        print(f"  title unusable after sanitize: {counts['title_unusable']}")
    if counts.get("tripleq_parity_broken") or counts.get("parser_still_degraded"):
        print(f"  PROBLEMS (parity/degraded)  : "
              f"{counts.get('tripleq_parity_broken',0)} / {counts.get('parser_still_degraded',0)}")

    if no_boundary:
        print(f"\n  --- {len(no_boundary)} files with no recognisable step boundary "
              f"(left untouched) ---")
        for f in no_boundary[:40]:
            print(f"    {os.path.relpath(f, repo_root)}")
        if len(no_boundary) > 40:
            print(f"    ... and {len(no_boundary) - 40} more")
    if problems:
        print(f"\n  !!! {len(problems)} files hit a guard (NOT written) !!!")
        for f, st in problems[:40]:
            print(f"    [{st}] {os.path.relpath(f, repo_root)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
