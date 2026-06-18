#!/usr/bin/env python3
"""Fix pattern-A fixture/workflow format-contract mismatches: the workflow loads its
input with readRDS() but the auto-generated fixture wrote a write.csv() data-frame
dump (readRDS on a CSV -> "unknown input format"). Every such fixture shares the same
template:
    .obj <- get("<data>")
    .df  <- tryCatch(as.data.frame(.obj), error=function(e) as.data.frame(as.matrix(.obj)))
    write.csv(.df, "<INPUT>", row.names=TRUE)
The `.obj` is the real typed object the readRDS() expects, so the fix is to serialize
it directly. Only touches fixtures that contain that exact two-line block AND whose
workflow readRDS the same declared input. Idempotent.
"""
import json, re, sys
from pathlib import Path

BIOC = Path(__file__).resolve().parents[1] / "biomni_workflows/nextflow_nfcore/subworkflows/bioconductor"
rows = json.load(open("/tmp/fixture_mismatch.json"))

BLOCK = re.compile(
    r'\.df\s*<-\s*tryCatch\(as\.data\.frame\(\.obj\),\s*error=function\(e\)\s*as\.data\.frame\(as\.matrix\(\.obj\)\)\)\s*\n'
    r'\s*write\.csv\(\.df,\s*"(?P<inp>[^"]+)",\s*row\.names=TRUE\)')

apply = "--apply" in sys.argv
fixed, skipped = [], []
for nf_rel, inp, w, r in rows:
    if w != "csv" or "rds" not in r:
        continue
    fx = (BIOC / nf_rel).with_name(Path(nf_rel).stem + ".fixture.R")
    if not fx.exists():
        skipped.append((nf_rel, "no fixture")); continue
    t = fx.read_text()
    m = BLOCK.search(t)
    if not m or m.group("inp") != inp:
        skipped.append((nf_rel, "template not matched")); continue
    new = BLOCK.sub(
        '# Workflow loads this input with readRDS(); serialize the real object\n'
        '# (a write.csv data-frame dump is not an RDS and fails readRDS at load).\n'
        f'saveRDS(.obj, "{inp}")', t, count=1)
    fixed.append(nf_rel)
    if apply:
        fx.write_text(new)

print(f"{'APPLIED' if apply else 'DRY-RUN'}: {len(fixed)} fixtures fixed, {len(skipped)} skipped")
for f in fixed: print("  FIX ", f)
for f, why in skipped: print("  skip", f, "::", why)
