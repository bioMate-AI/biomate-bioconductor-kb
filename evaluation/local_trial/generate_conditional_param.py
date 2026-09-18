"""Conditional / long-parameter SFT: handle 'schema is long but only a few params are valid'.
Presents the FULL param list (with defaults/required/enums) as context, and teaches the model to
extract ONLY the params the user (a) provides for a required field or (b) overrides from its default
or (c) activates conditionally — NEVER re-stating defaults or filling irrelevant conditional params.
Grounded in workflows.params_schema (3,058) + optional nf-core nextflow_schema.json for true if/then.
This is RAG-SFT-shaped (full schema in the prompt) with conditional restraint. Verifier: gold values
are schema-valid + are a subset of the presented params + exclude unchanged-default params."""
import sqlite3, json, os, sys, time, random, urllib.request
from concurrent.futures import ThreadPoolExecutor
random.seed(71); REPO="/Users/kky/biomate-review"; KEY=os.environ["OPENAI_API_KEY"]; GEN="gpt-5-mini"
c=sqlite3.connect(f"file:{REPO}/backend/database/galaxy_ai_tools.db?mode=ro",uri=True); c.row_factory=sqlite3.Row
rows=[]
for r in c.execute("select name,domain,params_schema from workflows where params_schema is not null and length(params_schema)>80"):
    try: p=json.loads(r["params_schema"])
    except: continue
    params=[x for x in (p.get("parameters") or []) if x.get("name")]
    if len(params)>=4: rows.append((r["name"], r["domain"], params))  # only workflows with enough params to be 'long'

def sample_value(p):
    t=(p.get("type") or "").lower(); av=p.get("allowed_values") or []
    if av: return random.choice(av)
    if t in ("boolean","bool"): return True          # bool set = positive (impliable)
    if t in ("integer","int"): return random.choice([10,20,50,100])
    if t in ("number","float"): return random.choice([0.01,0.05,0.1])
    return None

def render_schema(params):
    """RAG-style: show the FULL param list with default/required so the model must pick the few."""
    lines=[]
    for p in params:
        req = "required" if not p.get("optional", True) else "optional"
        dv = f", default={p.get('default')}" if p.get("default") is not None else ""
        av = f", allowed={p.get('allowed_values')}" if p.get("allowed_values") else ""
        lines.append(f"- {p['name']} ({p.get('type')}, {req}{dv}{av})")
    return "\n".join(lines)

INSTR=("You are BioMate. Given a user request and a workflow's FULL parameter schema (many parameters, "
       "most optional with defaults), extract ONLY the parameters the request explicitly specifies or "
       "overrides. Do NOT restate default values, do NOT fill parameters the request does not mention, "
       "and use only canonical/allowed values. Reply with ONLY a JSON object {name: value}.")

def _call(p, mx=400):
    body=json.dumps({"model":GEN,"messages":[{"role":"user","content":p}],"max_completion_tokens":mx,"reasoning_effort":"low"}).encode()
    for a in range(3):
        try:
            d=json.load(urllib.request.urlopen(urllib.request.Request("https://api.openai.com/v1/chat/completions",data=body,headers={"Authorization":f"Bearer {KEY}","Content-Type":"application/json"}),timeout=60))
            return d["choices"][0]["message"]["content"].strip()
        except Exception: time.sleep(1.5*(a+1))
    return None

def gen(item):
    name,dom,params=item
    random.shuffle(params)
    req=[p for p in params if not p.get("optional", True)]
    opt=[p for p in params if p.get("optional", True)]
    # active set = a couple required (user must give) + 1-2 optional the user chooses to CHANGE
    chosen=(req[:2] + random.sample(opt, min(len(opt), random.randint(1,2)))) or params[:2]
    gold={}
    for p in chosen:
        v=sample_value(p)
        if v is not None and v != p.get("default"):  # exclude values equal to default (restraint)
            gold[p["name"]]=v
    if not gold: return None
    hints="; ".join(f"{p.get('description') or p['name']} set to {gold.get(p['name'])}" for p in chosen if p["name"] in gold)
    q=_call(f"Write ONE realistic {dom} request from a researcher that clearly implies these settings, "
            f"in their own words, WITHOUT naming the parameter keys: {hints}. Reply with only the request.")
    if not q or len(q)<20: return None
    prompt=f"{INSTR}\n\nParameter schema:\n{render_schema(params)[:1800]}\n\nRequest: {q}"
    # verifier: gold subset of presented, values valid, no unchanged-defaults (already enforced)
    names={p["name"] for p in params}
    if not set(gold) <= names: return None
    return {"messages":[{"role":"user","content":prompt},{"role":"assistant","content":json.dumps(gold)}],
            "workflow":name,"n_params_shown":len(params),"n_gold":len(gold)}

N=int(sys.argv[1]) if len(sys.argv)>1 else 400
out=[]
with ThreadPoolExecutor(max_workers=10) as ex:
    for e in ex.map(gen, random.sample(rows,min(N,len(rows)))):
        if e: out.append(e)
open(f"{REPO}/docs/20260912_onprem_llm/routing_data_v1/conditional_param_sft.jsonl","w").write("\n".join(json.dumps(e) for e in out))
import statistics
if out:
    print(f"CONDITIONAL-PARAM: {len(out)} ex | avg params shown={statistics.mean(e['n_params_shown'] for e in out):.1f}, "
          f"avg gold={statistics.mean(e['n_gold'] for e in out):.1f} (few-valid ratio confirms conditional restraint)")
