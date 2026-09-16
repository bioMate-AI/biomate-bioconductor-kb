"""Retriever eval for routing STEP 1 (search). Rank all catalog workflows for each RealBio query;
report recall@k + MRR for lexical (TF-IDF), dense (MiniLM), and hybrid. Measures the ceiling that
the +0.83 candidate-context effect was standing in for."""
import json, sqlite3, re, numpy as np
REPO="/Users/kky/biomate-review"
c=sqlite3.connect(f"file:{REPO}/backend/database/galaxy_ai_tools.db?mode=ro",uri=True); c.row_factory=sqlite3.Row
wf=[dict(r) for r in c.execute("select name,domain,description,input_types,output_types,tools_used from workflows")]
names=[w["name"] for w in wf]
def doc(w):
    return " ".join(str(w.get(k) or "") for k in ("name","domain","description","input_types","output_types","tools_used"))[:2000]
docs=[doc(w) for w in wf]
rb=[json.loads(l) for l in open(f"{REPO}/docs/20260912_onprem_llm/routing_data_v1/realbio_routing_eval.jsonl")]
catset=set(names); rb=[r for r in rb if r["correct_workflow"] in catset]  # in-catalog ceiling
queries=[r["query"] for r in rb]; gold=[names.index(r["correct_workflow"]) for r in rb]
def metrics(rank_lists):
    ks=[1,5,10,20,50]; rec={k:0 for k in ks}; mrr=0.0
    for gi,rl in zip(gold,rank_lists):
        pos=rl.index(gi) if gi in rl else 10**9
        for k in ks:
            if pos<k: rec[k]+=1
        if pos<10**8: mrr+=1.0/(pos+1)
    n=len(gold); return {f"recall@{k}":round(rec[k]/n,3) for k in ks} | {"MRR":round(mrr/n,3)}
def topranks(scores, k=50):
    return [list(np.argsort(-row)[:k]) for row in scores]
print(f"queries (in-catalog)={len(rb)} | catalog={len(wf)}")
# --- lexical TF-IDF ---
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity
vec=TfidfVectorizer(ngram_range=(1,2),min_df=2,max_features=50000)
D=vec.fit_transform(docs); Q=vec.transform(queries)
lex=cosine_similarity(Q,D)
print("LEXICAL (tfidf):", metrics(topranks(lex)))
# --- dense ---
try:
    from sentence_transformers import SentenceTransformer
    m=SentenceTransformer("all-MiniLM-L6-v2")
    de=m.encode(docs, batch_size=128, show_progress_bar=False, normalize_embeddings=True)
    qe=m.encode(queries, batch_size=128, show_progress_bar=False, normalize_embeddings=True)
    den=qe@de.T
    print("DENSE (MiniLM):  ", metrics(topranks(den)))
    # --- hybrid (z-normalized sum) ---
    def z(x): return (x-x.mean(1,keepdims=True))/(x.std(1,keepdims=True)+1e-9)
    hyb=z(lex)+z(den)
    print("HYBRID:          ", metrics(topranks(hyb)))
except Exception as e:
    print("dense skipped:", str(e)[:120])
