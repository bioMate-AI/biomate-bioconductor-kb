import json, sqlite3, numpy as np
REPO="/Users/kky/biomate-review"
c=sqlite3.connect(f"file:{REPO}/backend/database/galaxy_ai_tools.db?mode=ro",uri=True); c.row_factory=sqlite3.Row
wf=[dict(r) for r in c.execute("select name,domain,description,input_types,output_types,tools_used from workflows")]
names=[w["name"] for w in wf]
def doc(w): return " ".join(str(w.get(k) or "") for k in ("name","domain","description","input_types","output_types","tools_used"))[:2000]
docs=[doc(w) for w in wf]
rb=[json.loads(l) for l in open(f"{REPO}/docs/20260912_onprem_llm/routing_data_v1/realbio_routing_eval.jsonl")]
catset=set(names); rb=[r for r in rb if r["correct_workflow"] in catset]
queries=[r["query"] for r in rb]; gold=[names.index(r["correct_workflow"]) for r in rb]
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity
lex=cosine_similarity(TfidfVectorizer(ngram_range=(1,2),min_df=2,max_features=50000).fit(docs).transform(queries),
                      TfidfVectorizer(ngram_range=(1,2),min_df=2,max_features=50000).fit(docs).transform(docs)) if False else None
vec=TfidfVectorizer(ngram_range=(1,2),min_df=2,max_features=50000); D=vec.fit_transform(docs)
lex=cosine_similarity(vec.transform(queries),D)
def metrics(sc):
    ks=[1,5,10,20,50]; rec={k:0 for k in ks}; mrr=0
    for gi,row in zip(gold,sc):
        rl=list(np.argsort(-row)[:50]); pos=rl.index(gi) if gi in rl else 10**9
        for k in ks:
            if pos<k: rec[k]+=1
        if pos<10**8: mrr+=1/(pos+1)
    n=len(gold); return {f"r@{k}":round(rec[k]/n,3) for k in ks}|{"MRR":round(mrr/n,3)}
from sentence_transformers import SentenceTransformer
m=SentenceTransformer("BAAI/bge-small-en-v1.5")
de=m.encode(docs,batch_size=128,normalize_embeddings=True,show_progress_bar=False)
qe=m.encode(["Represent this sentence for searching relevant passages: "+q for q in queries],batch_size=128,normalize_embeddings=True,show_progress_bar=False)
bge=qe@de.T
print("BGE-small:     ", metrics(bge))
def z(x): return (x-x.mean(1,keepdims=True))/(x.std(1,keepdims=True)+1e-9)
print("HYBRID lex+BGE:", metrics(z(lex)+z(bge)))
