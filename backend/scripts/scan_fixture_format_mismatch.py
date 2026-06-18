#!/usr/bin/env python3
"""Detect fixture<->workflow read/write FORMAT-CONTRACT mismatches across all
Bioconductor workflows. For each `<wf>.fixture.R` + `<wf>.nf` pair, compare the
serializer the fixture uses for each declared input filename against the reader the
workflow uses for that same filename. A mismatch (fixture saveRDS but workflow
read.csv; fixture write.csv but workflow readRDS/load; etc.) makes the workflow
hard-fail at input load even though the workflow code is correct.
"""
import re, sys, json, collections
from pathlib import Path

BIOC = Path(__file__).resolve().parents[1] / "biomni_workflows/nextflow_nfcore/subworkflows/bioconductor"

# reader -> the format family it requires
READERS = [
    (r'readRDS\(\s*["\']{f}["\']', "rds"),
    (r'load\(\s*["\']{f}["\']', "rdata"),
    (r'loadDb\(\s*["\']{f}["\']', "sqlite"),
    (r'read\.csv\(\s*["\']{f}["\']', "csv"),
    (r'read_csv\(\s*["\']{f}["\']', "csv"),
    (r'read\.delim\(\s*["\']{f}["\']', "tsv"),
    (r'read\.table\(\s*["\']{f}["\']', "table"),   # whitespace/sep generic text
    (r'read_tsv\(\s*["\']{f}["\']', "tsv"),
    (r'scan\(\s*["\']{f}["\']', "lines"),
    (r'readLines\(\s*["\']{f}["\']', "lines"),
    (r'fread\(\s*["\']{f}["\']', "table"),
]
# serializer -> format family it produces
WRITERS = [
    (r'saveRDS\([^,]+,\s*(?:file\s*=\s*)?["\']{f}["\']', "rds"),
    (r'save\([^)]*?,\s*file\s*=\s*["\']{f}["\']', "rdata"),
    (r'write\.csv\([^,]+,\s*(?:file\s*=\s*)?["\']{f}["\']', "csv"),
    (r'write\.table\([^)]*?["\']{f}["\']', "table"),  # sep decides; treat as text
    (r'write_csv\([^,]+,\s*["\']{f}["\']', "csv"),
    (r'writeLines\([^,]+,\s*(?:con\s*=\s*)?["\']{f}["\']', "lines"),
    (r'cat\([^)]*?file\s*=\s*["\']{f}["\']', "lines"),
    (r'writeLines\([^)]*?["\']{f}["\']', "lines"),
]
TEXT = {"csv", "tsv", "table", "lines"}   # mutually loadable text families
def compatible(w, r):
    if w == r: return True
    # a generic text reader (read.table/fread) accepts any text writer
    if r in ("table",) and w in TEXT: return True
    if w in ("table",) and r in TEXT: return True
    # read.csv strictly needs comma; tsv/lines mis-parse -> NOT compatible
    return False

def families_for(text, fname, patterns):
    f = re.escape(fname)
    out = []
    for pat, fam in patterns:
        if re.search(pat.replace("{f}", f), text):
            out.append(fam)
    return out

def declared_inputs(nf_text):
    m = re.search(r'//\s*Input:\s*(.+)', nf_text)
    if not m: return []
    return [x.strip() for x in m.group(1).split(",") if x.strip()]

def main():
    fix_only = "--fix" in sys.argv
    pairs = mismatches = no_writer = 0
    rows = []
    for nf in BIOC.rglob("*.nf"):
        fx = nf.with_name(nf.stem + ".fixture.R")
        if not fx.exists():
            continue
        pairs += 1
        nft = nf.read_text(errors="replace").replace("\\$", "$")
        fxt = fx.read_text(errors="replace")
        for inp in declared_inputs(nft):
            readers = families_for(nft, inp, READERS)
            writers = families_for(fxt, inp, WRITERS)
            if not readers:
                continue                    # workflow doesn't read it by a known reader
            if not writers:
                no_writer += 1
                continue                    # fixture builds it some other way (object-only)
            if not any(compatible(w, r) for w in writers for r in readers):
                mismatches += 1
                rows.append((str(nf.relative_to(BIOC)), inp, "+".join(writers), "+".join(readers)))
    print(f"fixture/workflow pairs scanned : {pairs}")
    print(f"declared inputs w/ NO fixture writer (object-built): {no_writer}")
    print(f"FORMAT-CONTRACT MISMATCHES     : {mismatches}\n")
    by_kind = collections.Counter(f"{w} written -> {r} read" for _, _, w, r in rows)
    for k, n in by_kind.most_common():
        print(f"  {n:4d}  {k}")
    print("\n--- first 40 ---")
    for nf, inp, w, r in rows[:40]:
        print(f"  {nf}  [{inp}]  write={w} read={r}")
    Path("/tmp/fixture_mismatch.json").write_text(json.dumps(rows, indent=1))
    print(f"\nfull list -> /tmp/fixture_mismatch.json ({len(rows)} rows)")

if __name__ == "__main__":
    main()
