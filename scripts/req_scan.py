#!/usr/bin/env python3
"""P0 requirement-scanner (v2). For every workflow, derive its TRUE input surface from the stored script
and classify the silent-fail risk:
  A invisible-filename: script reads a literal data filename NOT pinned by a stageAs and NOT written by the
    workflow itself -> user must name their upload exactly that, undiscoverable (the `survival` pattern).
  B keyed-input: uses read_input_file("key") -> caller must know the opaque key (the DESeq2 cts/coldata pattern).
  C how many of A/B declare nothing queryable (input_types empty)."""
import sqlite3, re, json, collections

DB = "/Users/kky/biomate-review/backend/database/galaxy_ai_tools.db"
c = sqlite3.connect(DB).cursor()
rows = c.execute("SELECT id,name,format,input_types,workflow_json FROM workflows").fetchall()

READ_PATS = [
    r'read\.csv\(\s*(?:gzfile\(\s*)?["\']([^"\']+)["\']',
    r'read\.table\(\s*(?:gzfile\(\s*)?["\']([^"\']+)["\']',
    r'read\.delim\(\s*["\']([^"\']+)["\']',
    r'read\.taqman\(\s*["\']([^"\']+)["\']',
    r'readRDS\(\s*["\']([^"\']+)["\']',
    r'(?:read_csv|read_tsv|read_delim|fread)\(\s*["\']([^"\']+)["\']',
    r'(?:pd\.read_csv|pd\.read_table|pd\.read_excel)\(\s*["\']([^"\']+)["\']',
    r'\bopen\(\s*["\']([^"\']+)["\']\s*,\s*["\']r',
]
RIF  = re.compile(r'read_input_file\(\s*["\']([^"\']+)["\']')
STAGE= re.compile(r'stageAs:\s*["\']([^"\']+/)?([^"\'/]+)["\']')   # capture basename
WRITE= re.compile(r'(?:write\.csv|write\.table|writeLines|ggsave|saveRDS|write_csv|\.to_csv|pdf|png|cat\(file=)\(\s*(?:file\s*=\s*)?["\']([^"\']+)["\']')

def dataish(fn):
    fn=fn.lower()
    if not re.search(r'\.(csv|tsv|txt|tab|gz|rds|xlsx|json|sdf|mtx|h5|h5ad|loom|fa|fasta|fastq|bam|vcf|gtf|gff|bed|sdf)$',fn): return False
    if re.search(r'versions|\.command|nextflow|\.config|readme|output|result|_out|summary|report|plot|\.pdf|\.png',fn): return False
    return True

cat=collections.Counter(); invisible=[]; keyed=[]; both_undeclared=0
for wid,name,fmt,itypes,wjson in rows:
    cat['total']+=1; wjson=wjson or ""
    writes={m for m in WRITE.findall(wjson)}
    stages={b for _,b in STAGE.findall(wjson)}
    reads=set()
    for p in READ_PATS:
        for m in re.findall(p,wjson):
            if dataish(m): reads.add(m)
    inv = {r for r in reads if r.split('/')[-1] not in stages and r not in writes and r.split('/')[-1] not in writes}
    rif = set(RIF.findall(wjson))
    itypes_empty = (not itypes) or itypes.strip() in ('[]','')
    if inv:
        cat['A_invisible_filename']+=1; invisible.append((wid,name,fmt,sorted(inv)[:3],itypes_empty))
    if rif:
        cat['B_keyed_input']+=1; keyed.append((wid,name,sorted(rif)))
    if (inv or rif) and itypes_empty:
        cat['C_and_nothing_declared']+=1; both_undeclared+=1

print("=== P0 requirement scan (v2) ===")
print(f"  total workflows: {cat['total']}")
print(f"  A — reads an invisible literal filename (survival pattern): {cat['A_invisible_filename']}")
print(f"  B — uses read_input_file keys (DESeq2 cts/coldata pattern):  {cat['B_keyed_input']}")
print(f"  C — (A or B) AND input_types empty (nothing queryable):      {cat['C_and_nothing_declared']}")
# distribution of invisible reads by filename (what names users would have to guess)
fn=collections.Counter()
for _,_,_,reads,_ in invisible:
    for r in reads: fn[r.split('/')[-1]]+=1
print(f"\n  most common required-but-invisible filenames:")
for f,n in fn.most_common(12): print(f"    {n:4d}  {f}")
print(f"\n  read_input_file keys seen (sample):")
ks=collections.Counter()
for _,_,keys in keyed:
    for k in keys: ks[k]+=1
for k,n in ks.most_common(12): print(f"    {n:4d}  {k}")
print(f"\n  sample invisible-filename workflows (first 18):")
for wid,name,fmt,reads,emp in sorted(invisible,key=lambda x:x[1])[:18]:
    print(f"    [{wid}] {name[:44]:44s} reads {reads}{'  (nothing declared)' if emp else ''}")
