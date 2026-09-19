"""Build a MULTI-GRANULARITY Workflow Knowledge Graph (WKG) linking blocks by DATA-TYPE flow, curated
chains, and function — from DB fields (input_types/output_types, workflow_chains, tools.inputs/outputs/
edam_operations). Two layers:
  - WORKFLOW level (backward-compatible: `workflows`,`precede`,`edge_types`) — used by v2 generators.
  - BLOCK level (`blocks`,`block_precede`,`block_edge_types`) over workflows + TOOL FUNCTIONS — the v3
    substrate for compositional generation (bind a step to a tool / submodule / workflow by I/O type).
Emits wkg.json + wkg_corpus.jsonl (verbalized relations for mid-train)."""
import sqlite3, os, json, re, collections
REPO="/Users/kky/biomate-review"; DB=f"{REPO}/backend/database/galaxy_ai_tools.db"
OUTJSON=f"{REPO}/docs/20260912_onprem_llm/routing_data_v1/wkg.json"
OUTCORP=f"{REPO}/docs/20260912_onprem_llm/midtrain_corpus/wkg_corpus.jsonl"
NONCONNECT={"multiqc_report","report","html","pdf","png","log","qc","qc_report","summary","txt","zip",
            "count_data","output_dir","input","output","data","file","dir","reads","fasta","fastq",
            "samplesheet","results","tabular","csv","tsv","json"}
MAXCONS=30

def parse_types(s):
    if not s: return []
    try:
        v=json.loads(s)
        if isinstance(v,list): return [str(x).strip().lower() for x in v if str(x).strip()]
    except Exception: pass
    return [t.strip().lower() for t in re.split(r"[,;|]", s) if t.strip()]

def precede_graph(blocks):
    """A->B iff A produces a SPECIFIC type that B consumes (filter generic hub types)."""
    producers=collections.defaultdict(list); consumers=collections.defaultdict(list)
    for n,d in blocks.items():
        for t in d["out"]:
            if t not in NONCONNECT: producers[t].append(n)
        for t in d["in"]:
            if t not in NONCONNECT: consumers[t].append(n)
    pre=collections.defaultdict(set); et={}
    for t in set(producers)&set(consumers):
        if len(consumers[t])>MAXCONS: continue
        for a in producers[t]:
            for b in consumers[t]:
                if a!=b: pre[a].add(b); et[(a,b)]=et.get((a,b),set())|{t}
    return pre, et

def main():
    c=sqlite3.connect(f"file:{DB}?mode=ro",uri=True); c.row_factory=sqlite3.Row
    # workflow-level blocks
    wf={}
    for r in c.execute("select name,domain,description,input_types,output_types,tools_used from workflows"):
        wf[r["name"]]={"granularity":"workflow","domain":r["domain"],"desc":(r["description"] or "")[:300],
            "in":parse_types(r["input_types"]),"out":parse_types(r["output_types"]),
            "tools":parse_types(r["tools_used"]),"function":""}
    # tool-function blocks (granularity=tool): I/O + edam operation as 'function'
    tools={}
    for r in c.execute("select name,category,description,inputs,outputs,edam_operations from tools "
                       "where inputs is not null or outputs is not null"):
        nm=(r["name"] or "").strip()
        if not nm or nm in wf: continue          # avoid name clash with workflow nodes
        tools[nm]={"granularity":"tool","domain":r["category"] or "","desc":(r["description"] or "")[:200],
            "in":parse_types(r["inputs"]),"out":parse_types(r["outputs"]),"tools":[],
            "function":", ".join(parse_types(r["edam_operations"]))[:120]}
    blocks={**wf,**tools}

    wf_pre, wf_et = precede_graph(wf)                 # workflow-level (v2 backward-compat)
    blk_pre, blk_et = precede_graph(blocks)           # multi-granularity (v3)
    chains=[]
    for r in c.execute("select name,display_name,domain,description,steps,connections,example_queries from workflow_chains"):
        try: steps=json.loads(r["steps"]); conns=json.loads(r["connections"] or "[]")
        except Exception: continue
        chains.append({"name":r["name"],"domain":r["domain"],"desc":(r["description"] or "")[:200],
            "steps":steps,"connections":conns,"example_queries":json.loads(r["example_queries"] or "[]")})

    kg={"workflows":wf, "precede":{a:sorted(bs) for a,bs in wf_pre.items()},
        "edge_types":{f"{a}|{b}":sorted(ts) for (a,b),ts in wf_et.items()},
        "curated_chains":chains,
        "blocks":{n:{"granularity":d["granularity"],"domain":d["domain"],"in":d["in"],"out":d["out"],
                     "function":d["function"]} for n,d in blocks.items()},
        "block_precede":{a:sorted(bs) for a,bs in blk_pre.items()},
        "block_edge_types":{f"{a}|{b}":sorted(ts) for (a,b),ts in blk_et.items()}}
    os.makedirs(os.path.dirname(OUTJSON),exist_ok=True); json.dump(kg,open(OUTJSON,"w"))
    print(f"WKG: {len(wf)} workflows + {len(tools)} tool-functions = {len(blocks)} blocks | "
          f"wf-precede {sum(len(v) for v in wf_pre.values())} | block-precede {sum(len(v) for v in blk_pre.values())} | chains {len(chains)}")

    # verbalize relations -> mid-train corpus
    def toks(s): return max(len(s.split()),1)
    docs=[]
    for n,d in wf.items():
        if not d["in"] and not d["out"]: continue
        succ=sorted(wf_pre.get(n,[]))[:8]; seg=[f"Workflow {n} ({d['domain']}) consumes "
             f"{', '.join(d['in']) or 'unspecified inputs'} and produces {', '.join(d['out']) or 'unspecified outputs'}."]
        if d["desc"]: seg.append(d["desc"])
        if succ:
            via=collections.defaultdict(list)
            for b in succ:
                for t in wf_et.get((n,b),[]): via[t].append(b)
            for t,bs in list(via.items())[:4]: seg.append(f"Its {t} output can feed {', '.join(sorted(set(bs))[:5])}.")
        txt=" ".join(seg)
        if toks(txt)>=20: docs.append({"text":txt,"source":"wkg","kind":"workflow_io"})
    for ch in chains:
        order=sorted(ch["steps"], key=lambda s:s.get("order",0))
        chain_str=" -> ".join(f"{s.get('workflow_name','?')} ({s.get('role','')})" for s in order)
        flows="; ".join(f"{cn.get('from_output','?')} (step {cn.get('from_step')}) -> step {cn.get('to_step')} ({cn.get('to_input','?')})" for cn in ch["connections"][:6])
        eq="; ".join(ch["example_queries"][:2])
        docs.append({"text":f"Analysis chain '{ch['name']}' ({ch['domain']}): {ch['desc']} Steps: {chain_str}. "
             f"Data flow: {flows}." + (f" Example requests: {eq}." if eq else ""),"source":"wkg","kind":"curated_chain"})
    # tool-function relations (capped; focus on tools that participate in specific-type flow)
    tool_rel=0
    for n,d in tools.items():
        if tool_rel>=4000: break
        if not d["function"] or (not d["in"] and not d["out"]): continue
        succ=sorted(blk_pre.get(n,[]))[:4]
        if not succ: continue
        txt=(f"Tool {n} ({d['function']}) consumes {', '.join(d['in']) or '?'} and produces "
             f"{', '.join(d['out']) or '?'}; its output can feed {', '.join(succ)}.")
        docs.append({"text":txt,"source":"wkg","kind":"tool_function"}); tool_rel+=1
    with open(OUTCORP,"w") as f:
        for d in docs: f.write(json.dumps(d)+"\n")
    print(f"wkg_corpus: {len(docs)} docs ({tool_rel} tool-function relations) "
          f"~{sum(toks(d['text']) for d in docs)*1.33/1e6:.2f}M tok -> {OUTCORP}")

if __name__=="__main__": raise SystemExit(main())
