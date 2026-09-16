"""GENERATOR (T06 param extraction), APIGen-style & verifiable: sample schema-VALID param
values for a real workflow -> generate a query that IMPLIES them (without naming keys) ->
emit {query, workflow, gold_params, schema_params}. Gold is schema-valid by construction;
the auditor verifies the query faithfully implies exactly gold (+ restraint on distractors)."""
import json, os, re, random, sqlite3, sys, urllib.request
from concurrent.futures import ThreadPoolExecutor
random.seed(41); REPO="/Users/kky/biomate-review"; KEY=os.environ["OPENAI_API_KEY"]; GEN="gpt-5-mini"
PERSONAS=["a wet-lab biologist","a core-facility bioinformatician","a PhD student","a clinical geneticist","a PI"]
c=sqlite3.connect(f"file:{REPO}/backend/database/galaxy_ai_tools.db?mode=ro",uri=True); c.row_factory=sqlite3.Row
def extractable(p):
    t=(p.get("type") or "").lower(); av=p.get("allowed_values") or []
    return bool(av) or t in ("boolean","bool","integer","int","number","float")
def sample_val(p):
    t=(p.get("type") or "").lower(); av=p.get("allowed_values") or []
    if av: return random.choice(av)
    if t in ("boolean","bool"): return random.choice([True,False])
    if t in ("integer","int"): return random.choice([10,20,30,50,100])
    return round(random.choice([0.01,0.05,0.1,0.5]),2)
rows=[]
for r in c.execute("select name,domain,params_schema from workflows where params_schema is not null and length(params_schema)>60"):
    try: p=json.loads(r["params_schema"])
    except: continue
    params=[x for x in (p.get("parameters") or []) if x.get("name") and extractable(x)]
    if len(params)>=2: rows.append((r["name"],r["domain"],params))
def _call(prompt):
    body=json.dumps({"model":GEN,"messages":[{"role":"user","content":prompt}],"max_completion_tokens":400,"reasoning_effort":"low"}).encode()
    d=json.load(urllib.request.urlopen(urllib.request.Request("https://api.openai.com/v1/chat/completions",data=body,headers={"Authorization":f"Bearer {KEY}","Content-Type":"application/json"}),timeout=60))
    return d["choices"][0]["message"]["content"].strip().strip('"')
def gen(item):
    name,dom,params=item; persona=random.choice(PERSONAS)
    random.shuffle(params); k=min(random.randint(1,3),len(params))
    chosen=params[:k]; distract=params[k:k+4]
    gold={p["name"]:sample_val(p) for p in chosen}
    hints="\n".join(f"- {p.get('description') or p['name']}: intended setting = {gold[p['name']]}" for p in chosen)
    prompt=(f"Write ONE realistic request that {persona} would send to a bioinformatics assistant, "
            f"describing their experiment/data so that these settings are CLEARLY IMPLIED (but NEVER name "
            f"the parameter keys or copy this wording — describe the biology/data in your own words):\n{hints}\n"
            f"Domain: {dom}. Reply with ONLY the request.")
    try:
        q=_call(prompt)
        if len(q)<20: return None
        schema_params=[{kk:p.get(kk) for kk in ("name","type","allowed_values","description")} for p in (chosen+distract)]
        random.shuffle(schema_params)
        return {"query":q,"workflow":name,"domain":dom,"gold_params":gold,"schema_params":schema_params}
    except Exception: return None
N=int(sys.argv[1]) if len(sys.argv)>1 else 120
sample=random.sample(rows,min(N,len(rows)))
out=[]
with ThreadPoolExecutor(max_workers=12) as ex:
    for e in ex.map(gen, sample):
        if e: out.append(e)
p=f"{REPO}/docs/20260912_onprem_llm/routing_data_v1/param_generated_raw.jsonl"
open(p,"w").write("\n".join(json.dumps(e) for e in out))
print(f"GENERATED {len(out)} param episodes -> param_generated_raw.jsonl")
