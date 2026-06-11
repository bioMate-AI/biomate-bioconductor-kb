#!/usr/bin/env python3
"""
Root-cause fix: a `cat <<-END_VERSIONS > versions.yml ... END_VERSIONS` BASH heredoc placed
INSIDE an `#!/usr/bin/env Rscript` process block. Nextflow runs the whole block through Rscript,
so R evaluates the heredoc and dies with `object 'END_VERSIONS' not found`. Surfaced in 7
packages on real execution; latent in 687 .nf files (stub tests never exercise it).

Convert the heredoc to the correct nf-core R idiom: writeLines(c(...), "versions.yml").
Version values `\$(Rscript -e 'cat(as.character(packageVersion("X")))')` -> as.character(packageVersion("X")).
"""
from __future__ import annotations
import re, sys, glob
from pathlib import Path

BIOC = Path(__file__).resolve().parents[1] / \
    "biomni_workflows/nextflow_nfcore/subworkflows/bioconductor"

# the heredoc inside the R block
HEREDOC = re.compile(
    r'([ \t]*)cat[ \t]+<<-?END_VERSIONS[ \t]*>[ \t]*versions\.yml[ \t]*\n'
    r'(.*?)\n[ \t]*END_VERSIONS[ \t]*\n',
    re.DOTALL)

PKGVER = re.compile(r'packageVersion\(\s*["\']([A-Za-z][\w.]+)["\']\s*\)')


def r_value_for(line: str) -> str | None:
    r"""Given a heredoc body line `    key: \$(...)` return an R expression producing the YAML line, or None for the header."""
    # header line: a quoted process key, no command substitution
    if '\\$(' not in line and '$(' not in line:
        # literal line (e.g. '"BIOC_FOO":') -> single-quoted R string literal
        lit = line.replace("\\", "").strip()
        return "'" + lit.replace("'", "\\'") + "'"
    # value line: split on first ':'
    key, _, _ = line.partition(':')
    prefix = key + ': '            # keep indentation + key
    prefix = prefix.replace("\\", "")
    m = PKGVER.search(line)
    if m:
        expr = f'as.character(packageVersion("{m.group(1)}"))'
    elif re.search(r'r-base|R\.version|R --version', line):
        expr = 'paste(R.version$major, R.version$minor, sep=".")'
    else:
        expr = "'NA'"
    plit = "'" + prefix.replace("'", "\\'") + "'"
    return f'paste0({plit}, {expr})'


def convert_block(indent: str, body: str) -> str:
    lines = [l for l in body.split('\n') if l.strip()]
    exprs = [r_value_for(l) for l in lines]
    exprs = [e for e in exprs if e]
    inner = (',\n' + indent + '    ').join(exprs)
    return (f'{indent}writeLines(c(\n{indent}    {inner}\n{indent}), "versions.yml")\n')


def in_r_block(text: str, pos: int) -> bool:
    """Is character offset `pos` inside a triple-quoted block whose first non-space line is the R shebang?"""
    for m in re.finditer(r'"""(.*?)"""', text, re.DOTALL):
        if m.start(1) <= pos < m.end(1):
            return m.group(1).lstrip().startswith("#!/usr/bin/env Rscript")
    return False


def sanitize_text(t: str) -> str:
    """Convert any R-block-contained versions.yml bash heredoc to writeLines. Importable by
    the workflow generators so the bug can never be reborn in a freshly-emitted .nf."""
    out, last, changed = [], 0, False
    for m in HEREDOC.finditer(t):
        if not in_r_block(t, m.start()):
            continue
        out.append(t[last:m.start()])
        out.append(convert_block(m.group(1), m.group(2)))
        last = m.end()
        changed = True
    if not changed:
        return t
    out.append(t[last:])
    return "".join(out)


def fix_file(nf: Path) -> int:
    t = nf.read_text(errors="replace")
    n = 0
    out = []
    last = 0
    for m in HEREDOC.finditer(t):
        if not in_r_block(t, m.start()):
            continue
        out.append(t[last:m.start()])
        out.append(convert_block(m.group(1), m.group(2)))
        last = m.end()
        n += 1
    if n:
        out.append(t[last:])
        nf.write_text("".join(out))
    return n


def main() -> int:
    files = sys.argv[1:] or [l.strip() for l in Path("/tmp/endver_bug_files.txt").read_text().splitlines() if l.strip()]
    total = 0; touched = 0
    for f in files:
        p = (BIOC / f) if not f.startswith('/') and not Path(f).exists() else Path(f)
        if not p.exists():
            p = BIOC / f
        c = fix_file(p)
        if c:
            touched += 1; total += c
    print(f"converted {total} heredoc(s) across {touched} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
