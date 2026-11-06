#!/usr/bin/env python3
import json,re,collections,os
d=json.load(open("research/screenshot_committee/results/committee_raw.json"))
M=d["committee"]; R=d["results"]
SEVRANK={"ok":0,"minor":1,"major":2}
def consensus_sev(recs):
    svs=[v.get("severity") for v in recs if v]
    c=collections.Counter(s for s in svs if s in SEVRANK)
    if not c: return "?"
    top,n=c.most_common(1)[0]
    if n>=2: return top
    # no majority -> take the middle/highest-mentioned
    return sorted(set(svs)&set(SEVRANK),key=lambda s:SEVRANK[s])[-1] if (set(svs)&set(SEVRANK)) else "?"
# capture-vs-bug heuristic
CAP=re.compile(r"crop|resolution|blurr|legib|cut off|cutoff|clipp|truncat|zoom|too small|low.res|whitespace|empty space|scroll|partial|off-screen|viewport|re-?capture|screenshot",re.I)
BUG=re.compile(r"undefined|placeholder|broken|overlap|misalign|duplicat|null|NaN|error|missing (button|label|icon|element)|raw (code|json|html)|contradict|stale|wrong|three tab|download report|outdated|inconsist",re.I)
rows=[]; byuc=collections.defaultdict(list)
for a,rec in R.items():
    verds={p:rec["reviews"][p].get("verdict") for p in rec["reviews"] if isinstance(rec["reviews"][p].get("verdict"),dict)}
    errs=[p for p in rec["reviews"] if rec["reviews"][p].get("error")]
    cs=consensus_sev(list(verds.values()))
    # collect issues flagged, with model attribution
    issues=[]
    for p,v in verds.items():
        for it in (v.get("issues") or []):
            if it: issues.append((p,it))
        # also fold the axis strings that read as problems
        for ax in ("content","ui_elements","quality","clarity"):
            t=v.get(ax,"")
            if isinstance(t,str) and BUG.search(t) and len(t)>20: issues.append((p,f"[{ax}] "+t))
    # consensus issue themes: an issue flagged by >=2 models (fuzzy by shared keywords)
    rows.append({"asset":a,"uc":rec["usecase"],"cons":cs,"n_major":sum(1 for v in verds.values() if v.get("severity")=="major"),
                 "issues":issues,"errs":errs})
    byuc[rec["usecase"]].append(a)
# classify each asset's dominant issue type
def issue_blob(r): return " || ".join(i for _,i in r["issues"])
majors=[r for r in rows if r["cons"]=="major"]
majors.sort(key=lambda r:(-r["n_major"]))
print("=== CONSENSUS-MAJOR assets (>=2 models major):",len([r for r in rows if r['n_major']>=2]),"===")
for r in rows:
    if r["n_major"]>=2:
        blob=issue_blob(r); kind="BUG" if BUG.search(blob) and not CAP.search(blob[:120]) else ("CAPTURE" if CAP.search(blob) else "MIXED")
        print(f"\n[{kind}] {r['asset']}  ({r['uc']})  major-votes={r['n_major']}/3")
        seen=set()
        for p,it in r["issues"][:4]:
            k=it[:60]
            if k in seen: continue
            seen.add(k); print(f"   - ({p}) {it[:160]}")
# write a compact machine summary for the doc builder
json.dump({"models":M,"rows":rows,"byuc":{k:v for k,v in byuc.items()}},open("research/screenshot_committee/results/aggregated.json","w"),indent=2)
print("\nwrote results/aggregated.json ; consensus-major assets:",len([r for r in rows if r['n_major']>=2]),"/",len(rows))
