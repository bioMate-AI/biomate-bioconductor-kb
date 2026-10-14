#!/usr/bin/env python3
"""Cross-model VISION committee review of BioMate user-manual screenshots.
Each of 3 frontier models (OpenAI/Google/Anthropic via OpenRouter) independently
reviews every docs/user-manual/assets/*.png on 4 axes, given the asset's intended
state (from the manual's CAPTURE comments). REVIEW layer, not validation."""
import os, re, json, base64, glob, time, urllib.request, urllib.error
KEY=open(os.path.expanduser("~/.config/biomate/openrouter.key")).read().strip()
URL="https://openrouter.ai/api/v1"
ROOT="/Users/kky/biomate-review"
ASSETS=os.path.join(ROOT,"docs/user-manual/assets")
RES=os.path.join(ROOT,"research/screenshot_committee/results")

def models():
    ids=[m["id"] for m in json.load(urllib.request.urlopen(urllib.request.Request(URL+"/models",headers={"Authorization":"Bearer "+KEY}),timeout=30))["data"]]
    def best(prov,prefer,avoid):
        c=[i for i in ids if i.startswith(prov) and not i.endswith(":batch") and not any(a in i for a in avoid)]
        for p in prefer:
            h=[i for i in c if p in i]
            if h: return sorted(h)[-1]
        return sorted(c)[-1] if c else None
    return {"openai":best("openai/",["gpt-6","gpt-5","gpt-4.1"],["mini","nano","audio","tts","search","image","realtime","codex"]),
            "google":best("google/",["gemini-3","gemini-2.5"],["flash","lite","image","tts"]),
            "anthropic":best("anthropic/",["opus","sonnet"],["haiku","fable"])}

# --- asset -> use-case/chapter + intended CAPTURE context, from the manual markdown ---
def build_map():
    amap={}  # asset -> {pages:set, captures:list}
    for md in glob.glob(ROOT+"/docs/user-manual/**/*.md",recursive=True):
        rel=os.path.relpath(md,ROOT+"/docs/user-manual")
        try: lines=open(md,encoding="utf-8").read().split("\n")
        except Exception: continue
        last_cap=""
        for ln in lines:
            cm=re.search(r"<!--\s*CAPTURE(.*?)-->",ln)
            if cm: last_cap=cm.group(1).strip()
            for m in re.finditer(r"!\[[^\]]*\]\((?:\.\./)+assets/([A-Za-z0-9_.\-]+\.png)\)",ln):
                a=m.group(1); d=amap.setdefault(a,{"pages":set(),"captures":[]})
                d["pages"].add(rel)
                if last_cap: d["captures"].append(last_cap[:300])
                alt=re.search(r"!\[([^\]]*)\]",ln)
                if alt and alt.group(1): d["captures"].append("alt: "+alt.group(1)[:200])
    return amap

def usecase_of(pages):
    if not pages: return "unreferenced"
    p=sorted(pages)[0]
    # chapter/use-case from path
    for key in ["domains/","tutorials/instruments/","tutorials/zh/","tutorials/","modules/","overview/","data/","appendix/"]:
        if p.startswith(key):
            base=os.path.basename(p).replace(".md","").replace(".zh","")
            return f"{key.rstrip('/')}:{base}"
    return p

RUBRIC=("You are a senior product-documentation UI reviewer for BioMate (a cloud bioinformatics/drug-discovery web app). "
 "You are given ONE screenshot that appears in the user manual, plus the INTENDED state it should show. Judge it on 4 axes: "
 "(1) screen quality — crop, legibility, resolution, clipping, overlap, empty/dead space; "
 "(2) ui_elements — are UI components complete, consistent, aligned; anything broken, missing, duplicated, or showing 'undefined'/placeholder/raw code; "
 "(3) content — are labels/values/terminology correct and internally consistent (BioMate's after-run report is now TWO tabs 'Results' + 'Reproducibility record'; the findings card has a 'Download findings' button, and there is ALSO a SEPARATE top-right 'Download report' button for the comprehensive report — BOTH are correct and legitimately coexist, do NOT flag 'Download report' as stale; the OLD three-tab Summary/Outputs/Reproducibility nav IS wrong; cold-start examples attach demo data / are self-contained); flag stale UI or wrong/contradictory content; "
 "(4) clarity — is the screen self-explanatory and useful at this spot in a manual, does it match the intended state. "
 "Respond ONLY as compact JSON: {\"quality\":\"..\",\"ui_elements\":\"..\",\"content\":\"..\",\"clarity\":\"..\",\"issues\":[\"..\"],\"severity\":\"ok|minor|major\"}. "
 "severity=major if a real UI bug / wrong content / unusable shot; minor for polish; ok if fine. Be specific and terse; do not invent.")

def parse(s):
    if not s: return None
    s=s.strip()
    if "```" in s: s=re.sub(r"```[a-z]*","",s).replace("```","")
    try: return json.loads(s[s.index("{"):s.rindex("}")+1])
    except Exception: return {"raw":s[:600]}

def ask(model,b64,ctx):
    body=json.dumps({"model":model,"temperature":0.2,"messages":[
        {"role":"system","content":RUBRIC},
        {"role":"user","content":[{"type":"text","text":"INTENDED state of this manual screenshot:\n"+ctx},
                                   {"type":"image_url","image_url":{"url":"data:image/png;base64,"+b64}}]}]}).encode()
    req=urllib.request.Request(URL+"/chat/completions",data=body,headers={"Authorization":"Bearer "+KEY,"Content-Type":"application/json"})
    r=json.load(urllib.request.urlopen(req,timeout=180))
    return r["choices"][0]["message"].get("content","")

def main():
    M=models(); print("committee:",M,flush=True)
    amap=build_map()
    assets=sorted(os.path.basename(p) for p in glob.glob(ASSETS+"/*.png"))
    print(f"{len(assets)} assets to review\n",flush=True)
    allres={}
    for i,a in enumerate(assets):
        info=amap.get(a,{"pages":set(),"captures":[]})
        uc=usecase_of(info["pages"]); ctx=(f"use-case/page: {uc}. "+(" | ".join(info['captures'][:2]) if info['captures'] else "(not referenced by any manual page)"))
        try: b64=base64.b64encode(open(os.path.join(ASSETS,a),"rb").read()).decode()
        except Exception as e: print("SKIP",a,e,flush=True); continue
        rec={"asset":a,"usecase":uc,"context":ctx,"reviews":{}}
        for prov,model in M.items():
            if not model: rec["reviews"][prov]={"error":"no model"}; continue
            ok=False
            for attempt in range(2):
                try:
                    raw=ask(model,b64,ctx)
                    if raw and raw.strip(): rec["reviews"][prov]={"model":model,"verdict":parse(raw)}; ok=True; break
                    rec["reviews"][prov]={"model":model,"error":"empty content"}
                except urllib.error.HTTPError as e:
                    rec["reviews"][prov]={"model":model,"error":f"HTTP {e.code}: {e.read()[:150].decode(errors='ignore')}"}
                except Exception as e:
                    rec["reviews"][prov]={"model":model,"error":str(e)[:150]}
                time.sleep(4)
            sev=rec["reviews"].get(prov,{}).get("verdict",{}).get("severity","?") if ok else "ERR"
            print(f"  [{i+1}/{len(assets)}] {a:38} {prov:10} {sev}",flush=True)
        allres[a]=rec
        json.dump({"committee":M,"results":allres},open(os.path.join(RES,"committee_raw.json"),"w"),indent=2)
        time.sleep(0.3)
    print("\nDONE -> results/committee_raw.json",flush=True)

if __name__=="__main__": main()
