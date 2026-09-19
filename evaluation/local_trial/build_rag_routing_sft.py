"""RAG-SFT for routing (committee #1 fix): format routing as a PRODUCTION RAG prompt — retrieve top-k
candidates from the REAL hybrid retriever (TF-IDF+BGE) so the distractors are genuine HARD NEGATIVES,
then the model picks the correct workflow FROM the provided context. Trains context-reading (attend to
retrieved candidates) rather than parametric recall. Local (no API): queries+gold already known."""
import json, sqlite3, re, os, numpy as np
REPO="/Users/kky/biomate-review"; D=f"{REPO}/docs/20260912_onprem_llm/routing_data_v1"
c=sqlite3.connect(f"file:{REPO}/backend/database/galaxy_ai_tools.db?mode=ro",uri=True); c.row_factory=sqlite3.Row
wf=[dict(r) for r in c.execute("select name,domain,description,input_types,output_types,tools_used from workflows")]
names=[w["name"] for w in wf]
def doc(w): return " ".join(str(w.get(k) or "") for k in ("name","domain","description","input_types","output_types","tools_used"))[:2000]
docs=[doc(w) for w in wf]; idx={n:i for i,n in enumerate(names)}
# hybrid retriever: TF-IDF + BGE (same as retriever eval)
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity
vec=TfidfVectorizer(ngram_range=(1,2),min_df=2,max_features=50000); Dm=vec.fit_transform(docs)
from sentence_transformers import SentenceTransformer
# RETRIEVER_MODEL env lets us mine candidates with the CONTRASTIVE retriever (recall@5 0.38->0.92),
# so the top-k candidate blocks contain genuinely-hard, gold-usually-present negatives.
RET=os.environ.get("RETRIEVER_MODEL","BAAI/bge-small-en-v1.5")
m=SentenceTransformer(RET); print("[rag] retriever:",RET); de=m.encode(docs,batch_size=128,normalize_embeddings=True,show_progress_bar=False)
def z(x): return (x-x.mean(1,keepdims=True))/(x.std(1,keepdims=True)+1e-9)
def retrieve(query,k=10):
    lex=cosine_similarity(vec.transform([query]),Dm)
    den=(m.encode(["Represent this sentence for searching relevant passages: "+query],normalize_embeddings=True)@de.T)
    sc=(z(lex)+z(den))[0]; return [names[i] for i in np.argsort(-sc)[:k]]
INSTR=("You are BioMate. Given the user request and the retrieved candidate workflows below, choose the "
       "single best-matching workflow and reply with ONLY its exact name from the candidates.")
def build_prompt(query,cands):
    block="\n".join(f"- {n}" for n in cands)
    return f"{INSTR}\n\nRetrieved candidates:\n{block}\n\nRequest: {query}"
src=[json.loads(l) for l in open(f"{D}/audited_pass_fullcatalog.jsonl")]+([json.loads(l) for l in open(f"{D}/real_studies_labeled.jsonl")] if os.path.exists(f"{D}/real_studies_labeled.jsonl") else [])
import random; random.seed(11); random.shuffle(src); src=src[:900]
out=[]; kept=0
for r in src:
    q=r["query"]; gold=r["correct_workflow"]
    if gold not in idx: continue
    cands=retrieve(q,10)
    if gold not in cands: cands=[gold]+cands[:9]   # ensure gold present (retriever recall gap)
    random.shuffle(cands)
    out.append({"messages":[{"role":"user","content":build_prompt(q,cands)},{"role":"assistant","content":gold}],"gold_in_retrieved":True}); kept+=1
open(f"{D}/rag_routing_sft.jsonl","w").write("\n".join(json.dumps(e) for e in out))
print(f"RAG-ROUTING SFT: {kept} ex (retrieved hard-negative candidates from hybrid TF-IDF+BGE)")
