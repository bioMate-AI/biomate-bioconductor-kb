#!/usr/bin/env python3
"""
Root-cause fix: 1,563 of 3,350 regenerated Bioconductor .nf call `library(<pkg>)` with NO
`# [biomate-deps]` self-install bootstrap. When the execution container does not already
ship <pkg>, the workflow dies immediately with `there is no package called '<pkg>'`
(surfaced locally on `microbiome`). Workflows that DO carry the bootstrap (deseq2, phyloseq)
self-install any missing declared dependency and run in any environment.

Insert the canonical bootstrap right after the `#!/usr/bin/env Rscript` line of every R
script block that lacks it, declaring exactly the packages the block `library()`/`require()`s
(base R packages excluded). The bootstrap only installs what `requireNamespace` reports
missing, so a fully-baked image pays nothing.
"""
from __future__ import annotations
import re, sys, glob
from pathlib import Path

BIOC = Path(__file__).resolve().parents[1] / \
    "biomni_workflows/nextflow_nfcore/subworkflows/bioconductor"

# base R packages ship with every R — never try to install them
_BASE = {"base", "utils", "stats", "methods", "graphics", "grDevices", "datasets",
         "parallel", "tools", "compiler", "splines", "grid", "tcltk", "stats4"}

_BOOT = (
    "{i}# [biomate-deps] resolve declared dependencies so the workflow runs in any environment\n"
    "{i}.bm_deps <- c({pkgs})\n"
    "{i}.bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]\n"
    "{i}if (length(.bm_miss)) {{\n"
    "{i}  .rv <- getRversion()\n"
    "{i}  .biocv <- if (.rv >= \"4.5\") \"3.21\" else if (.rv >= \"4.4\") \"3.20\" else if (.rv >= \"4.3\") \"3.18\" else \"3.16\"\n"
    "{i}  .repos <- c(sprintf(\"https://bioconductor.org/packages/%s/bioc\", .biocv), sprintf(\"https://bioconductor.org/packages/%s/data/annotation\", .biocv), sprintf(\"https://bioconductor.org/packages/%s/data/experiment\", .biocv), \"https://cloud.r-project.org\")\n"
    "{i}  suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))\n"
    "{i}}}\n"
)

_LIB_RE = re.compile(r'(?:library|require)\(\s*["\']?([A-Za-z][\w.]+)')
_SHEBANG_RE = re.compile(r'(^[ \t]*)#!/usr/bin/env Rscript[ \t]*\n', re.MULTILINE)


def _libs(block: str) -> list:
    seen = []
    for m in _LIB_RE.finditer(block):
        p = m.group(1)
        if p not in _BASE and p not in seen:
            seen.append(p)
    return seen


def sanitize_text(t: str) -> str:
    """Insert the dep bootstrap into every R script block that library()s something but has
    no .bm_deps. Importable by the generators so the gap can't be reborn. Idempotent."""
    out, last, changed = [], 0, False
    for m in re.finditer(r'"""(.*?)"""', t, re.DOTALL):
        blk = m.group(1)
        if not blk.lstrip().startswith("#!/usr/bin/env Rscript"):
            continue
        if ".bm_deps" in blk:
            continue
        libs = _libs(blk)
        if not libs:
            continue
        sheb = _SHEBANG_RE.search(blk)
        if not sheb:
            continue
        pkgs = ", ".join('"%s"' % p for p in libs)
        boot = _BOOT.format(i=sheb.group(1), pkgs=pkgs)
        ins = m.start(1) + sheb.end()          # offset into ORIGINAL text
        out.append(t[last:ins]); out.append(boot); last = ins; changed = True
    if not changed:
        return t
    out.append(t[last:])
    return "".join(out)


def fix_file(nf: Path) -> int:
    t = nf.read_text(errors="replace")
    new = sanitize_text(t)
    if new != t:
        nf.write_text(new)
        return 1
    return 0


def main() -> int:
    files = sys.argv[1:]
    if files and files[0] == "--dry-run":
        files = files[1:]
        dry = True
    else:
        dry = False
    if not files:
        files = [f for f in glob.glob(str(BIOC / "**/*.nf"), recursive=True)]
    touched = 0
    for f in files:
        p = Path(f) if Path(f).exists() else (BIOC / f)
        t = p.read_text(errors="replace")
        if sanitize_text(t) != t:
            touched += 1
            if not dry:
                p.write_text(sanitize_text(t))
    print(f"{'would add' if dry else 'added'} bootstrap to {touched} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
