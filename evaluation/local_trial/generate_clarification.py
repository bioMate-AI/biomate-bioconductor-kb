"""Clarification / restraint SFT (committee gap): when a REQUIRED parameter is missing from the
request, the model must ASK for it, not hallucinate a value. Grounded in workflows.params_schema:
pick a workflow with required params, generate a query that omits a specific required value ->
gold = a clarification asking for exactly that required parameter. Teaches abstention over guessing."""
import sqlite3, json, os, sys, time, random, urllib.request
from concurrent.futures import ThreadPoolExecutor
random.seed(91); REPO="/Users/kky/biomate-review"; KEY=os.environ["OPENAI_API_KEY"]; GEN="gpt-5-mini"
c=sqlite3.connect(f"file:{REPO}/backend/database/galaxy_ai_tools.db?mode=ro",uri=True); c.row_factory=sqlite3.Row
rows=[]
for r in c.execute("select name,domain,params_schema from workflows where params_schema is not null and length(params_schema)>80"):
    try: p=json.loads(r["params_schema"])
    except: continue
    params=[x for x in (p.get("parameters") or []) if x.get("name")]
    req=[x for x in params if not x.get("optional", True) and x.get("default") is None]  # truly-required, no default
    # committee fix: only workflows with a SMALL required-no-default set (1-4) -> the clarify gold is the
    # FULL missing set and stays realistic (avoids the unrealistic 'ask for 13 low-level knobs' case,
    # which usually means the schema's required flag is unreliable for that workflow).
    if 1<=len(req)<=4 and len(params)>=3: rows.append((r["name"], r["domain"], params, req))

def render(params):
    return "\n".join(f"- {p['name']} ({p.get('type')}, {'required' if not p.get('optional',True) else 'optional'})" for p in params)

INSTR=("You are BioMate. Extract the specified parameters as JSON {name: value}. If a REQUIRED parameter "
       "is not provided in the request, do NOT guess — instead ask for it. Reply with JSON of any provided "
       'params plus {"clarify_needed": ["<missing required param>", ...]} if required info is missing.')

def _call(p):
    body=json.dumps({"model":GEN,"messages":[{"role":"user","content":p}],"max_completion_tokens":700,"reasoning_effort":"low"}).encode()
    for a in range(3):
        try:
            d=json.load(urllib.request.urlopen(urllib.request.Request("https://api.openai.com/v1/chat/completions",data=body,headers={"Authorization":f"Bearer {KEY}","Content-Type":"application/json"}),timeout=60))
            return d["choices"][0]["message"]["content"].strip()
        except Exception: time.sleep(1.5*(a+1))
    return None

def gen(item):
    name,dom,params,req=item
    # committee fix: the gold must list the FULL set of missing required params, not one. Generate a
    # request that describes the goal/data but specifies NONE of the required params -> gold = all of req.
    missing_names=[p["name"] for p in req]
    missing_desc="; ".join(p.get("description") or p["name"] for p in req)
    q=_call(f"Write ONE realistic {dom} analysis request that describes the goal/data at a high level but "
            f"does NOT specify any of these required inputs: {missing_desc}. Natural, in a researcher's words. "
            f"Reply with only the request.")
    if not q or len(q)<20: return None
    gold={"clarify_needed": missing_names}
    prompt=f"{INSTR}\n\nParameter schema:\n{render(params)[:1200]}\n\nRequest: {q}"
    return {"messages":[{"role":"user","content":prompt},{"role":"assistant","content":json.dumps(gold)}],"workflow":name}

N=int(sys.argv[1]) if len(sys.argv)>1 else 250
out=[]
with ThreadPoolExecutor(max_workers=10) as ex:
    for e in ex.map(gen, random.sample(rows,min(N,len(rows)))):
        if e: out.append(e)
open(f"{REPO}/docs/20260912_onprem_llm/routing_data_v1/clarification_sft.jsonl","w").write("\n".join(json.dumps(e) for e in out))
print(f"CLARIFICATION/abstention: {len(out)} ex (ask-for-required, not hallucinate)")
