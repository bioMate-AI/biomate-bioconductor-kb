import base64, json, os, re, sys, urllib.request, pathlib
KEY=open(os.path.expanduser("~/.config/biomate/openrouter.key")).read().strip()
screens, out = sys.argv[1], sys.argv[2]
extra = os.environ.get("EXTRA","")
def img(p, mime="image/png"): return {"type":"image_url","image_url":{"url":f"data:{mime};base64,"+base64.b64encode(open(p,"rb").read()).decode()}}
brief = """You are the visual designer setting the TYPOGRAPHY system for BioMate (scientific workflow web app). The founder says the UI is "boring and hard to read"; colours/surfaces were already fixed (see screens A). Remaining problem: text is tiny (mostly 10–12px) and there are ~20 ad-hoc sizes with no hierarchy.

Deliver a restrained type ramp (5–7 steps max) as CSS custom properties, and a deterministic MAPPING from every existing px value to a ramp step, so a codemod can migrate ~3000 call sites. Constraints:
- Must stay usable in the ~480px workflow panel (tables, chips, badges) and the 224px sidebar — bigger, but don't blow up dense UI; tiny labels (badges, counts, kbd) may stay small but ≥11px.
- Body/readable text should be ~14–15px; secondary/meta ~13px; micro labels (uppercase eyebrows, badges) 11–12px.
- Headings: only a few sizes.
- Provide line-height per step. Mono step for code/ids.
- Prototype images (B) show the agreed direction for size/hierarchy (ignore their purple).

Return ONLY a JSON object in a ```json block:
{"tokens": {"--fs-<name>": {"size":"<px>", "line":"<unitless>", "use":"<what>"}...},
 "px_map": {"7":"--fs-…", "8":..., "9":..., "9.5":..., "10":..., ... every value listed in the distribution up to 36},
 "tailwind": {"xs":"--fs-…","sm":"--fs-…","base":"--fs-…","lg":"--fs-…","xl":"--fs-…","2xl":"--fs-…"},
 "rationale": "short"}"""
c=[{"type":"text","text":brief},{"type":"text","text":open(os.environ.get("DIST","type_dist.txt")).read()},{"type":"text","text":"(A) current live screens:"}]
for p in sorted(pathlib.Path(screens).glob("*.png")): c.append(img(str(p)))
c.append({"type":"text","text":"(B) prototypes:"})
for p in filter(None, os.environ.get("PROTO_IMAGES","").split(",")): c.append(img(p,"image/jpeg"))
if os.environ.get("PREV"): c.append({"type":"text","text":"PREVIOUS PLAN (the screens in A already render it — critique honestly and return an improved complete plan):\n"+open(os.environ["PREV"]).read()})
if extra: c.append({"type":"text","text":"REVIEWER OBSERVATIONS (verified on the render):\n"+extra})
req=urllib.request.Request("https://openrouter.ai/api/v1/chat/completions",data=json.dumps({"model":"google/gemini-3.1-pro-preview","messages":[{"role":"user","content":c}],"max_tokens":16000}).encode(),headers={"Authorization":f"Bearer {KEY}","Content-Type":"application/json"})
r=json.load(urllib.request.urlopen(req,timeout=600)); t=r["choices"][0]["message"]["content"]
open(out+".response.md","w").write(t)
m=re.search(r"```json\s*(.*?)```",t,re.S); plan=json.loads(m.group(1)); json.dump(plan,open(out,"w"),indent=1)
print("cost",r.get("usage",{}).get("cost")); print(json.dumps(plan["tokens"],indent=1)); print("tailwind",plan["tailwind"]); print("map",plan["px_map"]); print(plan.get("rationale"))
