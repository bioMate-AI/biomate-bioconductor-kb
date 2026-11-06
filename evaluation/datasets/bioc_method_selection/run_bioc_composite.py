#!/usr/bin/env python3
"""Composite arm: live BioMate retrieval (top-k) -> KB-grounded SELECTION over the retrieved set.
Tests whether a selection step recovers the weak retrieval@1 (0.375) toward the recall@8 ceiling (0.825).
For each query: POST /api/workflows/search (dev) -> top-k candidates -> describe each from the DB ->
ask a selector LLM (OpenRouter) to pick ONE -> compare to gold.
Env: OPENROUTER_API_KEY. Usage: python3 run_bioc_composite.py [selector_model]
"""
import json, os, re, sqlite3, urllib.request, sys
HERE=os.path.dirname(os.path.abspath(__file__))
DB=os.path.join(HERE,"..","..","..","backend","database","galaxy_ai_tools.db")
KEY=os.environ.get("OPENROUTER_API_KEY","") or open(os.path.expanduser("~/.config/biomate/openrouter.key")).read().strip()
SEL=sys.argv[1] if len(sys.argv)>1 else "openai/gpt-4.1"
DEV="https://dev-public.biomate.ai/api/workflows/search"
OR="https://openrouter.ai/api/v1/chat/completions"
gold={json.loads(l)["id"]:json.loads(l) for l in open(f"{HERE}/data.jsonl")}
con=sqlite3.connect(DB); meta={}
for nm,d,it in con.execute("SELECT name, COALESCE(NULLIF(TRIM(description),''),annotation,''), COALESCE(input_types,'') FROM workflows"):
    if nm not in meta: meta[nm]=(d,it)
def norm(s): return str(s).strip().lower()
def retrieve(q):
    body=json.dumps({"query":q,"limit":8}).encode()
    d=json.load(urllib.request.urlopen(urllib.request.Request(DEV,body,
        {"Content-Type":"application/json","x-e2e-test-token":"biomate-e2e-bypass-token-dev-only"}),timeout=40))
    top=d.get("workflow_name") or ""
    cands=[(c.get("name") if isinstance(c,dict) else c) for c in (d.get("candidate_workflows") or [])]
    # ensure top is in the candidate set
    if top and top not in cands: cands=[top]+cands
    return cands[:8]
def kb_line(c):
    d,it=meta.get(c,("","")); d=(d or "")[:200].replace("\n"," ").strip()
    return f"{c} — {d}" + (f"  [input: {it}]" if it and it not in ("[]","") else "")
def select(q,cands):
    menu="\n".join(kb_line(c) for c in cands)
    prompt=(f"Select the single correct bioinformatics method for the analysis. Choose EXACTLY ONE name "
            f"from the candidates and respond with ONLY that exact name.\nEach candidate is 'name — description [input]'.\n{menu}\n\nANALYSIS:\n{q}")
    body=json.dumps({"model":SEL,"messages":[{"role":"user","content":prompt}],"temperature":0,"max_tokens":64}).encode()
    try:
        d=json.load(urllib.request.urlopen(urllib.request.Request(OR,body,
            {"Authorization":f"Bearer {KEY}","Content-Type":"application/json"}),timeout=120))
        t=re.sub(r"<think>.*?</think>","",d["choices"][0]["message"]["content"] or "",flags=re.S).strip().lower()
    except Exception as e: return ""
    for c in sorted(cands,key=len,reverse=True):
        if c.lower() in t: return c
    return t.split()[0] if t else ""
n=comp=retr1=recall=cond=0
for i,r in gold.items():
    accept={norm(r["correct_method"])}|{norm(a) for a in r.get("acceptable_alts",[])}
    try: cands=retrieve(r["query"])
    except Exception: cands=[]
    n+=1
    in_retr = any(norm(c) in accept for c in cands)
    recall+=int(in_retr); retr1+= int(bool(cands) and norm(cands[0]) in accept)
    pick=select(r["query"],cands) if cands else ""
    ok=norm(pick) in accept; comp+=ok
    if in_retr and ok: cond+=1
print(json.dumps({"selector":SEL,"n":n,
  "retrieval@1":round(retr1/n,3),"recall@8":round(recall/n,3),
  "composite@1 (retrieve->KB-select)":round(comp/n,3),
  "conditional-select (pick gold | gold retrieved)":round(cond/max(recall,1),3)},indent=2))
