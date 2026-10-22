#!/usr/bin/env python3
"""GUARD: inline-python-in-.nf IndentationError class (the qsar_rf_model Batch bug).

Nextflow strips the common leading whitespace of a script: block. A block that
mixes outer-indented python with an inner col-0 heredoc (''' / """) dedents to
an inconsistent result -> the first statement is indented after a col-0 shebang ->
IndentationError, which only surfaces on Batch (wasting a job). This static guard
compiles every workflow's inline python the way Nextflow would, so the whole CLASS
is caught before dispatch instead of one workflow at a time.

Usage:  python3 scripts/validate_nf_inline_python.py [backend/biomni_workflows]
Exit 1 + prints BROKEN: <file> for any that will not compile. Wire into the
pre-sync checklist / CI as a HARD gate.
"""
import re,sys,textwrap,py_compile,tempfile,os,pathlib
ROOT=sys.argv[1] if len(sys.argv)>1 else "backend/biomni_workflows"
SB="#!/usr/bin/env python3"
def blocks(text):
    # find `script:` or `exec:` then a line that is <ws>""" ; capture until the matching <ws>"""
    for m in re.finditer(r'(?:script|exec)\s*:\s*\n', text):
        rest=text[m.end():]
        dm=re.match(r'([ \t]*)(""")', rest) or re.match(r"([ \t]*)(''')", rest)
        if not dm: continue
        delim=dm.group(2); start=dm.end()
        close=rest.find(delim, start)
        if close<0: continue
        body=rest[start:close]
        head="\n".join(body.lstrip("\n").split("\n")[:3])
        if SB in head: yield body
def broken(body):
    sub=re.sub(r'\$\{[^}]*\}','DUMMY',textwrap.dedent(body)); sub=re.sub(r'!\{[^}]*\}','DUMMY',sub)
    tf=tempfile.NamedTemporaryFile("w",suffix=".py",delete=False);tf.write(sub);tf.close()
    try:
        py_compile.compile(tf.name,doraise=True); return None
    except py_compile.PyCompileError as e: return str(e).splitlines()[0][:120]
    finally: os.unlink(tf.name)
bad=[];n=0
for p in pathlib.Path(ROOT).rglob("*.nf"):
    try: t=p.read_text(errors="ignore")
    except: continue
    if SB not in t: continue
    for b in blocks(t):
        n+=1; e=broken(b)
        if e: bad.append((str(p),e))
print(f"checked {n} inline-python blocks")
for f,e in bad: print(f"BROKEN: {f}")
print(f"{len(bad)} broken / {n} checked")
sys.exit(1 if bad else 0)
