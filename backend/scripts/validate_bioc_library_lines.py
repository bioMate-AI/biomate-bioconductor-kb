#!/usr/bin/env python3
"""
Guard against the "spliced library() insertion" codegen bug.

ROOT CAUSE (2026-06-12, commit eb7bc47e4 "add library(SummarizedExperiment) to 378
workflows"): a one-off post-processing script tried to insert a new line
`library(SummarizedExperiment)` *after* the first existing `library(...)` call in
each Bioconductor `.nf` script block. Instead of inserting a whole new line, it
spliced the text `library(SummarizedExperiment)\n` at a mis-computed *character*
offset, landing in the MIDDLE of an existing line and splitting it across two
lines, e.g.:

    library(MultiAssayExperiment)
  became
    librar    library(SummarizedExperiment)
    y(MultiAssayExperiment)

which is invalid R ("unexpected symbol"). 204 files were corrupted this way.

That generator script was never committed, so it cannot be fixed in-tree. This
validator is the enforceable guard: it fails (exit 1) if any Bioconductor `.nf`
still contains — or ever reintroduces — the splice signature, so a future
regeneration run cannot silently ship the mangle again.

Signature: a line containing a non-whitespace token, then 2+ spaces, then
`library(` — i.e. a `library(` call that is NOT at the start of its (indented)
line. Legitimate `library()` calls always begin a line (after indentation), so
this pattern only ever appears from the splice bug. Quoted/`cat()`/comment
occurrences of "library(" with leading spaces are explicitly excluded.

Usage:
    python3 backend/scripts/validate_bioc_library_lines.py            # scan default tree
    python3 backend/scripts/validate_bioc_library_lines.py <files...> # scan specific files
Exit code 0 = clean, 1 = mangle found.
"""
import re
import sys
import glob
import os

# this file lives at backend/scripts/<name>.py -> backend/ is two dirnames up
_BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_ROOT = os.path.join(
    _BACKEND_DIR,
    "biomni_workflows",
    "nextflow_nfcore",
    "subworkflows",
    "bioconductor",
)

# A `library(` that is preceded on the same line by a non-space token and 2+ spaces.
# This is the splice signature; a legitimate library() call always starts the line.
SPLICE_RE = re.compile(r'\S {2,}library\(')


def is_false_positive(line: str) -> bool:
    """Exclude library( appearing inside a string literal or a comment."""
    stripped = line.lstrip()
    if stripped.startswith("#"):
        return True
    # inside a quoted string (e.g. cat("  library(Pkg)\n"))
    before = line.split("library(", 1)[0]
    if before.count('"') % 2 == 1 or before.count("'") % 2 == 1:
        return True
    return False


def scan_file(path: str):
    hits = []
    with open(path, encoding="utf-8") as fh:
        for i, line in enumerate(fh, 1):
            line = line.rstrip("\n")
            if SPLICE_RE.search(line) and not is_false_positive(line):
                hits.append((i, line))
    return hits


def main(argv):
    if argv:
        files = argv
    else:
        files = sorted(glob.glob(os.path.join(DEFAULT_ROOT, "**", "*.nf"), recursive=True))

    bad = []
    for f in files:
        for ln, text in scan_file(f):
            bad.append((f, ln, text))

    if bad:
        print("FAIL: spliced library() insertion detected (codegen mangle):")
        for f, ln, text in bad:
            print(f"  {f}:{ln}: {text!r}")
        print(f"\n{len(bad)} mangled line(s) in {len({b[0] for b in bad})} file(s).")
        print("These are invalid R. Insert library() calls as whole lines, never by "
              "character-offset splicing. See this file's docstring for the root cause.")
        return 1

    print(f"OK: scanned {len(files)} file(s); no spliced library() mangle found.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
