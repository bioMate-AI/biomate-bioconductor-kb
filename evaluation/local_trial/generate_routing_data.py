"""GENERATOR: grounded routing-data generator. For a DB workflow, produce a realistic
user request grounded in its REAL artifacts (input_types/tools_used/output_types), with a
sampled persona — never paraphrasing the description (anti-circularity). Emits candidate
episode {query, correct_workflow, candidates, intent, persona, rationale}."""
import json, os, re, random, sqlite3, urllib.request
from concurrent.futures import ThreadPoolExecutor
random.seed(29); REPO="/Users/kky/biomate-review"; KEY=os.environ["OPENAI_API_KEY"]
GEN_MODEL="gpt-5-mini"
PERSONAS=["a wet-lab biologist with no coding experience","a core-facility bioinformatician",
 "a computational biology PhD student","a clinical geneticist","a PI writing a grant",
 "a data scientist new to genomics"]
c=sqlite3.connect(f"file:{REPO}/backend/database/galaxy_ai_tools.db?mode=ro",uri=True); c.row_factory=sqlite3.Row
rows=[dict(r) for r in c.execute("select name,domain,description,input_types,output_types,tools_used from workflows where input_types is not null and length(input_types)>20")]
allnames=[r["name"] for r in rows]
from collections import defaultdict
bydom=defaultdict(list)
for r in rows: bydom[r["domain"] or "general"].append(r["name"])
def cands(r):
    same=[n for n in bydom[r["domain"] or "general"] if n!=r["name"]]; random.shuffle(same)
    cs=list(dict.fromkeys([r["name"]]+same[:5]+random.sample(allnames,3)))[:9]; random.shuffle(cs)
    if r["name"] not in cs: cs[0]=r["name"]
    return cs
def gen(r):
    persona=random.choice(PERSONAS)
    prompt=(f"You are helping build a routing benchmark. Write ONE realistic request that {persona} "
      f"would type, describing THEIR DATA and SCIENTIFIC GOAL — grounded in these real workflow "
      f"characteristics. Do NOT mention or paraphrase the workflow name/description; describe the "
      f"experiment/data/analysis goal in the user's own words.\n"
      f"INPUT DATA TYPES: {(r['input_types'] or '')[:300]}\nOUTPUTS: {(r['output_types'] or '')[:150]}\n"
      f"TOOLS USED: {(r['tools_used'] or '')[:200]}\nDOMAIN: {r['domain']}\n"
      f"Reply with ONLY the request sentence(s).")
    body=json.dumps({"model":GEN_MODEL,"messages":[{"role":"user","content":prompt}],"max_completion_tokens":500,"reasoning_effort":"low"}).encode()
    try:
        d=json.load(urllib.request.urlopen(urllib.request.Request("https://api.openai.com/v1/chat/completions",data=body,headers={"Authorization":f"Bearer {KEY}","Content-Type":"application/json"}),timeout=60))
        q=d["choices"][0]["message"]["content"].strip().strip('"')
        return {"query":q,"correct_workflow":r["name"],"candidates":cands(r),"intent":"workflow_generation","persona":persona,"domain":r["domain"]} if len(q)>20 else None
    except Exception: return None
import sys
N=int(sys.argv[1]) if len(sys.argv)>1 else 40
sample=[]
for d,rs in bydom.items():
    random.shuffle(rs)
for r in random.sample(rows, min(N, len(rows))): sample.append(r)
out=[]
with ThreadPoolExecutor(max_workers=12) as ex:
    for e in ex.map(gen, sample):
        if e: out.append(e)
p=f"{REPO}/docs/20260912_onprem_llm/routing_data_v1/generated_raw.jsonl"
open(p,"w").write("\n".join(json.dumps(e) for e in out))
print(f"GENERATED {len(out)} grounded routing candidates -> generated_raw.jsonl")
