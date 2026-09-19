"""GENERATOR (T06 param extraction), APIGen-style & verifiable: sample schema-VALID param
values for a real workflow -> generate a query that IMPLIES them (without naming keys) ->
emit {query, workflow, gold_params, schema_params}. Gold is schema-valid by construction;
the auditor verifies the query faithfully implies exactly gold (+ restraint on distractors)."""
import json, os, re, random, sqlite3, sys, time, urllib.request
from concurrent.futures import ThreadPoolExecutor
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); import schema_guard
random.seed(41); REPO="/Users/kky/biomate-review"; KEY=os.environ["OPENAI_API_KEY"]; GEN="gpt-5-mini"
PERSONAS=["a wet-lab biologist","a core-facility bioinformatician","a PhD student","a clinical geneticist","a PI"]
c=sqlite3.connect(f"file:{REPO}/backend/database/galaxy_ai_tools.db?mode=ro",uri=True); c.row_factory=sqlite3.Row
def extractable(p):
    t=(p.get("type") or "").lower(); av=p.get("allowed_values") or []
    return bool(av) or t in ("boolean","bool","integer","int","number","float")
def sample_val(p):
    # schema+name-aware (fixes 'number'-typed count params sampled as fractions, e.g. nPerm=0.01)
    return schema_guard.sample_valid_value(p)
rows=[]
for r in c.execute("select name,domain,params_schema from workflows where params_schema is not null and length(params_schema)>60"):
    try: p=json.loads(r["params_schema"])
    except: continue
    params=[x for x in (p.get("parameters") or []) if x.get("name") and extractable(x)]
    if len(params)>=2: rows.append((r["name"],r["domain"],params))
def _call(prompt):
    body=json.dumps({"model":GEN,"messages":[{"role":"user","content":prompt}],"max_completion_tokens":400,"reasoning_effort":"low"}).encode()
    last=None
    for attempt in range(3):  # retry-harden: swallow transient API drops
        try:
            d=json.load(urllib.request.urlopen(urllib.request.Request("https://api.openai.com/v1/chat/completions",data=body,headers={"Authorization":f"Bearer {KEY}","Content-Type":"application/json"}),timeout=90))
            return d["choices"][0]["message"]["content"].strip().strip('"')
        except Exception as e:
            last=e; time.sleep(1.5*(attempt+1))
    raise last
def gen(item):
    name,dom,params=item; persona=random.choice(PERSONAS)
    # prioritize CLEANLY IMPLIABLE targets: enums + numerics first; booleans only set True
    enums=[p for p in params if p.get("allowed_values")]
    nums=[p for p in params if (p.get("type") or "").lower() in ("integer","int","number","float") and not p.get("allowed_values")]
    bools=[p for p in params if (p.get("type") or "").lower() in ("boolean","bool")]
    random.shuffle(enums); random.shuffle(nums); random.shuffle(bools)
    pref=enums+nums+bools
    if not pref: return None
    k=min(random.randint(1,3),len(pref)); chosen=pref[:k]; distract=[p for p in params if p not in chosen][:4]
    def val(p):
        return True if (p.get("type") or "").lower() in ("boolean","bool") else sample_val(p)  # bool gold = True (impliable)
    gold={p["name"]:val(p) for p in chosen}
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
# with replacement when N>catalog so we get multiple (distinct param-subset) episodes per workflow
sample=random.sample(rows,N) if N<=len(rows) else [random.choice(rows) for _ in range(N)]
out=[]
with ThreadPoolExecutor(max_workers=12) as ex:
    for e in ex.map(gen, sample):
        if e: out.append(e)
p=f"{REPO}/docs/20260912_onprem_llm/routing_data_v1/param_generated_raw.jsonl"
open(p,"w").write("\n".join(json.dumps(e) for e in out))
print(f"GENERATED {len(out)} param episodes -> param_generated_raw.jsonl")
