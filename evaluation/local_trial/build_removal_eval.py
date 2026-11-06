"""v3 removal eval — dataset builder. Measures out-of-catalog ability: take real (query -> workflow)
pairs where the workflow has a known step decomposition, REMOVE that workflow from the retrieved
candidates, and require the model to reconstruct an equivalent phase->step plan from what remains
(compose/abstain) instead of picking a wrong single workflow. Ground truth = the removed workflow's
step_metadata; candidates = contrastive-retriever top-k with the target removed."""
import json, os, sys, sqlite3, re
REPO="/Users/kky/biomate-review"; D=f"{REPO}/docs/20260912_onprem_llm/routing_data_v1"
DB=f"{REPO}/backend/database/galaxy_ai_tools.db"

def main():
    N=int(sys.argv[1]) if len(sys.argv)>1 else 150
    c=sqlite3.connect(f"file:{DB}?mode=ro",uri=True); c.row_factory=sqlite3.Row
    # workflows with a real step decomposition (the reconstruction target)
    steps_of={}
    for r in c.execute("select name,step_metadata from workflows where step_metadata is not null and length(step_metadata)>60"):
        try: s=json.loads(r["step_metadata"])
        except: continue
        st=[(x.get("step"), x.get("phase") or "Analysis") for x in s if isinstance(x,dict) and x.get("step")]
        if 3<=len(st)<=12: steps_of[r["name"]]=st
    # labeled queries whose gold workflow has a decomposition
    src=[json.loads(l) for l in open(f"{D}/audited_pass_fullcatalog.jsonl")]
    p=f"{D}/real_studies_labeled.jsonl"
    if os.path.exists(p): src+=[json.loads(l) for l in open(p)]
    src=[r for r in src if r.get("query") and r.get("correct_workflow") in steps_of]
    import random; random.seed(23); random.shuffle(src)

    # contrastive retriever for candidates (remove the target -> no exact match)
    from sentence_transformers import SentenceTransformer
    from sklearn.feature_extraction.text import TfidfVectorizer
    from sklearn.metrics.pairwise import cosine_similarity
    import numpy as np
    wf=[dict(r) for r in c.execute("select name,domain,description,input_types,output_types,tools_used from workflows")]
    names=[w["name"] for w in wf]
    def doc(w): return " ".join(str(w.get(k) or "") for k in ("name","domain","description","input_types","output_types","tools_used"))[:2000]
    docs=[doc(w) for w in wf]
    vec=TfidfVectorizer(ngram_range=(1,2),min_df=2,max_features=50000); Dm=vec.fit_transform(docs)
    RET=os.environ.get("RETRIEVER_MODEL", f"{REPO}/models/bge-routing-contrastive")
    m=SentenceTransformer(RET); de=m.encode(docs,batch_size=128,normalize_embeddings=True,show_progress_bar=False)
    def z(x): return (x-x.mean(1,keepdims=True))/(x.std(1,keepdims=True)+1e-9)
    def retrieve(q,k,drop):
        lex=cosine_similarity(vec.transform([q]),Dm)
        den=(m.encode(["Represent this sentence for searching relevant passages: "+q],normalize_embeddings=True)@de.T)
        sc=(z(lex)+z(den))[0]
        return [names[i] for i in np.argsort(-sc) if names[i]!=drop][:k]

    out=[]
    for r in src[:N]:
        q=r["query"]; W=r["correct_workflow"]
        cands=retrieve(q,10,drop=W)          # top-10 with the true workflow REMOVED
        out.append({"query":q,"removed_workflow":W,"domain":next((w["domain"] for w in wf if w["name"]==W),""),
                    "ground_truth_steps":[{"step":s,"phase":ph} for s,ph in steps_of[W]],
                    "candidates":cands})
    open(f"{D}/removal_eval.jsonl","w").write("\n".join(json.dumps(e) for e in out))
    print(f"REMOVAL EVAL: {len(out)} cases (target removed from candidates; ground-truth steps kept)")

if __name__=="__main__": raise SystemExit(main())
