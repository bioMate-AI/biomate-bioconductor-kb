"""Build a Workflow Knowledge Graph (WKG) linking workflows by DATA-TYPE flow, curated chains, tools,
and usage — from fields already in the DB (input_types/output_types, workflow_chains, tools_used,
description). Emits: (1) wkg.json (nodes+edges, loadable by the KG-grounded generators), (2)
wkg_corpus.jsonl (verbalized relations for mid-training). This turns isolated per-workflow facts into
'which workflow after which / what data flows / when to use' relations."""
import sqlite3, os, json, re, collections
REPO="/Users/kky/biomate-review"; DB=f"{REPO}/backend/database/galaxy_ai_tools.db"
OUTJSON=f"{REPO}/docs/20260912_onprem_llm/routing_data_v1/wkg.json"
OUTCORP=f"{REPO}/docs/20260912_onprem_llm/midtrain_corpus/wkg_corpus.jsonl"

# types that are NOT meaningful analysis hand-offs -> excluded from precede edges:
# reports/logs + GENERIC placeholders (verified: count_data=507, fasta=115, output_dir, input are hubs
# that make the graph a hairball; specific types like counts_matrix/vcf/h5ad give clean edges).
NONCONNECT={"multiqc_report","report","html","pdf","png","log","qc","qc_report","summary","txt","zip",
            "count_data","output_dir","input","output","data","file","dir","reads","fasta","fastq",
            "samplesheet","results","tabular","csv","tsv","json"}
MAXCONS=30   # a connecting type consumed by >30 workflows is too generic to imply a meaningful successor

def parse_types(s):
    if not s: return []
    try:
        v=json.loads(s)
        if isinstance(v,list): return [str(x).strip().lower() for x in v if str(x).strip()]
    except Exception: pass
    return [t.strip().lower() for t in re.split(r"[,;|]", s) if t.strip()]

def main():
    c=sqlite3.connect(f"file:{DB}?mode=ro",uri=True); c.row_factory=sqlite3.Row
    wf={}
    for r in c.execute("select name,domain,description,input_types,output_types,tools_used from workflows"):
        n=r["name"]
        wf[n]={"domain":r["domain"],"desc":(r["description"] or "")[:300],
               "in":parse_types(r["input_types"]),"out":parse_types(r["output_types"]),
               "tools":parse_types(r["tools_used"])}
    names=list(wf)
    # ---- type indices ----
    producers=collections.defaultdict(list); consumers=collections.defaultdict(list)
    for n,d in wf.items():
        for t in d["out"]:
            if t not in NONCONNECT: producers[t].append(n)
        for t in d["in"]:
            if t not in NONCONNECT: consumers[t].append(n)
    # ---- can_precede edges: A -> B via SPECIFIC type t iff A produces t and B consumes t (A != B) ----
    precede=collections.defaultdict(set); edge_type={}
    for t in set(producers)&set(consumers):
        if t in NONCONNECT or len(consumers[t])>MAXCONS: continue   # skip generic hub types
        for a in producers[t]:
            for b in consumers[t]:
                if a!=b:
                    precede[a].add(b); edge_type[(a,b)]=edge_type.get((a,b),set())|{t}
    # ---- curated chains (high-precision, with data-flow connections) ----
    chains=[]
    for r in c.execute("select name,display_name,domain,description,steps,connections,example_queries from workflow_chains"):
        try: steps=json.loads(r["steps"]); conns=json.loads(r["connections"] or "[]")
        except Exception: continue
        chains.append({"name":r["name"],"domain":r["domain"],"desc":(r["description"] or "")[:200],
                       "steps":steps,"connections":conns,
                       "example_queries":json.loads(r["example_queries"] or "[]")})
    # ---- write structured KG ----
    kg={"workflows":wf,
        "precede":{a:sorted(bs) for a,bs in precede.items()},
        "edge_types":{f"{a}|{b}":sorted(ts) for (a,b),ts in edge_type.items()},
        "curated_chains":chains}
    os.makedirs(os.path.dirname(OUTJSON),exist_ok=True); json.dump(kg,open(OUTJSON,"w"))
    n_precede=sum(len(v) for v in precede.values())
    print(f"WKG: {len(wf)} workflows | precede-edges {n_precede} | curated chains {len(chains)}")

    # ---- verbalize relations -> mid-train corpus ----
    def toks(s): return max(len(s.split()),1)
    docs=[]
    # 1) per-workflow I/O + successors
    for n,d in wf.items():
        if not d["in"] and not d["out"]: continue
        succ=sorted(precede.get(n,[]))[:8]
        seg=[f"Workflow {n} ({d['domain']}) consumes {', '.join(d['in']) or 'unspecified inputs'} and "
             f"produces {', '.join(d['out']) or 'unspecified outputs'}."]
        if d["desc"]: seg.append(d["desc"])
        if succ:
            via=collections.defaultdict(list)
            for b in succ:
                for t in edge_type.get((n,b),[]): via[t].append(b)
            for t,bs in list(via.items())[:4]:
                seg.append(f"Its {t} output can feed {', '.join(sorted(set(bs))[:5])}.")
        txt=" ".join(seg)
        if toks(txt)>=20: docs.append({"text":txt,"source":"wkg","kind":"workflow_io"})
    # 2) curated chains as prose (which workflow after which + what data flows)
    for ch in chains:
        order=sorted(ch["steps"], key=lambda s:s.get("order",0))
        chain_str=" -> ".join(f"{s.get('workflow_name','?')} ({s.get('role','')})" for s in order)
        flows="; ".join(f"{cn.get('from_output','?')} from step {cn.get('from_step')} into step "
                        f"{cn.get('to_step')} ({cn.get('to_input','?')})" for cn in ch["connections"][:6])
        eq=("; ".join(ch["example_queries"][:2]))
        txt=(f"Analysis chain '{ch['name']}' ({ch['domain']}): {ch['desc']} Steps: {chain_str}. "
             f"Data flow: {flows}." + (f" Example requests: {eq}." if eq else ""))
        docs.append({"text":txt,"source":"wkg","kind":"curated_chain"})
    with open(OUTCORP,"w") as f:
        for d in docs: f.write(json.dumps(d)+"\n")
    print(f"wkg_corpus: {len(docs)} docs (~{sum(toks(d['text']) for d in docs)*1.33/1e6:.2f}M tok) -> {OUTCORP}")

if __name__=="__main__": raise SystemExit(main())
