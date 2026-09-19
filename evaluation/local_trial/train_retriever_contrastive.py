"""Contrastive fine-tune of the routing retriever (committee 'retriever-first' + user's contrastive ask).

Trains BGE with InfoNCE (MultipleNegativesRankingLoss): for each labeled query the POSITIVE is the correct
workflow's doc, and the HARD NEGATIVES are the top candidates the current hybrid retriever returns that
are NOT the gold -- exactly the confusable workflows the LLM currently has to disambiguate. In-batch
negatives + these mined hard negatives pull the query embedding toward its true workflow and away from
look-alikes, so top-k retrieval (the routing front-end) gets more precise BEFORE the LLM sees candidates.

Reports recall@1/@5 on a held-out query split before vs after (the real contrastive-learning delta).
Runs on CPU for bge-small; use --device cuda on the GPU box. Output adapter dir -> serve as the routing
encoder and re-run build_rag_routing_sft.py to get harder, more realistic candidate blocks."""
import json, os, sys, re, random, argparse
import numpy as np, sqlite3
random.seed(303); REPO="/Users/kky/biomate-review"; D=f"{REPO}/docs/20260912_onprem_llm/routing_data_v1"

def load_workflows():
    c=sqlite3.connect(f"file:{REPO}/backend/database/galaxy_ai_tools.db?mode=ro",uri=True); c.row_factory=sqlite3.Row
    wf=[dict(r) for r in c.execute("select name,domain,description,input_types,output_types,tools_used from workflows")]
    names=[w["name"] for w in wf]
    def doc(w): return " ".join(str(w.get(k) or "") for k in
        ("name","domain","description","input_types","output_types","tools_used"))[:2000]
    return names, [doc(w) for w in wf], {n:i for i,n in enumerate(names)}

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--model",default="BAAI/bge-small-en-v1.5")
    ap.add_argument("--out",default=f"{REPO}/models/bge-routing-contrastive")
    ap.add_argument("--epochs",type=int,default=2); ap.add_argument("--batch",type=int,default=32)
    ap.add_argument("--n-hard",type=int,default=4); ap.add_argument("--device",default=None)
    ap.add_argument("--holdout-frac",type=float,default=0.15)
    ap.add_argument("--holdout-mode",choices=["random","family"],default="family",
                    help="family = hold out WHOLE workflows (no test workflow seen in training pairs); "
                         "the honest generalization test. random = leaks (same workflow in train & test).")
    a=ap.parse_args()
    import torch, torch.nn.functional as F
    torch.set_num_threads(4)  # cap CPU threads (frugal on small-RAM local box)
    from sentence_transformers import SentenceTransformer
    from sklearn.feature_extraction.text import TfidfVectorizer
    from sklearn.metrics.pairwise import cosine_similarity

    names, docs, idx = load_workflows()
    src=[json.loads(l) for l in open(f"{D}/audited_pass_fullcatalog.jsonl")]
    p=f"{D}/real_studies_labeled.jsonl"
    if os.path.exists(p): src+=[json.loads(l) for l in open(p)]
    src=[r for r in src if r.get("correct_workflow") in idx and r.get("query")]
    random.shuffle(src)
    if a.holdout_mode=="family":
        # hold out WHOLE workflows: no held-out workflow appears in any training pair (honest number).
        wfs=sorted({r["correct_workflow"] for r in src}); random.shuffle(wfs)
        held_wf=set(wfs[:int(len(wfs)*a.holdout_frac)])
        train_q=[r for r in src if r["correct_workflow"] not in held_wf]
        held_q =[r for r in src if r["correct_workflow"] in held_wf]
        print(f"FAMILY holdout: {len(held_wf)}/{len(wfs)} workflows held out "
              f"(their {len(held_q)} queries never seen in training).")
    else:
        ncut=int(len(src)*(1-a.holdout_frac)); train_q, held_q = src[:ncut], src[ncut:]
        print("RANDOM holdout (WARNING: same workflow can appear in train & test -> optimistic).")
    print(f"labeled queries: {len(src)} -> train {len(train_q)} / heldout {len(held_q)}")

    QPREFIX="Represent this sentence for searching relevant passages: "
    m=SentenceTransformer(a.model, device=a.device)

    def recall(model, qs, ks=(1,5)):
        de=model.encode(docs, batch_size=128, normalize_embeddings=True, show_progress_bar=False)
        qe=model.encode([QPREFIX+r["query"] for r in qs], batch_size=128,
                        normalize_embeddings=True, show_progress_bar=False)
        sim=qe@de.T; hits={k:0 for k in ks}
        for i,r in enumerate(qs):
            order=np.argsort(-sim[i]); gold=idx[r["correct_workflow"]]
            for k in ks:
                if gold in order[:k]: hits[k]+=1
        return {k: round(hits[k]/max(len(qs),1),3) for k in ks}

    before=recall(m, held_q); print("recall BEFORE:", before, flush=True)

    # mine hard negatives with a hybrid TF-IDF+dense retriever (same signal as production front-end)
    vec=TfidfVectorizer(ngram_range=(1,2),min_df=2,max_features=50000); Dm=vec.fit_transform(docs)
    de=m.encode(docs,batch_size=128,normalize_embeddings=True,show_progress_bar=False)
    def z(x): return (x-x.mean(1,keepdims=True))/(x.std(1,keepdims=True)+1e-9)
    def hard_negs(q, gold_i, k):
        lex=cosine_similarity(vec.transform([q]),Dm)
        den=(m.encode([QPREFIX+q],normalize_embeddings=True)@de.T)
        sc=(z(lex)+z(den))[0]
        return [i for i in np.argsort(-sc) if i!=gold_i][:k]

    # each training row = (anchor query, positive gold doc, list of hard-negative docs)
    triplets=[]
    for r in train_q:
        gi=idx[r["correct_workflow"]]
        negs=hard_negs(r["query"], gi, a.n_hard)
        if negs: triplets.append((QPREFIX+r["query"], docs[gi], [docs[ni] for ni in negs]))
    random.shuffle(triplets)
    print(f"contrastive rows: {len(triplets)} (query, +gold, {a.n_hard} hard negs each)")

    # --- InfoNCE / MultipleNegativesRankingLoss implemented directly (no `datasets` dep) ---
    dev=a.device or ("cuda" if torch.cuda.is_available() else "cpu")  # cpu default: stable, MPS is flaky here
    m=m.to(dev); m.train()
    def embed(texts):  # low-level forward WITH grad; features must live on model device
        f=m.tokenize(texts); f={k:(v.to(dev) if hasattr(v,"to") else v) for k,v in f.items()}
        return F.normalize(m(f)["sentence_embedding"], p=2, dim=1)
    opt=torch.optim.AdamW(m.parameters(), lr=2e-5)
    scale=20.0  # temperature (1/0.05), the ST MNRL default
    steps=0; total=len(triplets)*a.epochs
    warmup=max(int(0.1*total/a.batch),5)
    for ep in range(a.epochs):
        random.shuffle(triplets)
        for i in range(0, len(triplets)-a.batch+1, a.batch):
            batch=triplets[i:i+a.batch]
            anchors=[t[0] for t in batch]; pos=[t[1] for t in batch]
            hard=[d for t in batch for d in t[2]]           # flattened hard negatives
            A=embed(anchors); P=embed(pos); H=embed(hard)   # [b,d],[b,d],[b*n,d]
            cand=torch.cat([P,H],0)                          # in-batch positives+negs + hard negs
            logits=scale*(A@cand.T)                          # [b, b + b*n]
            labels=torch.arange(A.size(0), device=dev)       # positive of row i is column i
            loss=F.cross_entropy(logits, labels)
            for g in opt.param_groups: g["lr"]=2e-5*min(1.0,(steps+1)/warmup)
            opt.zero_grad(); loss.backward(); opt.step(); steps+=1
            if steps%20==0: print(f"ep{ep} step{steps}/{total//a.batch} loss={loss.item():.4f}", flush=True)
    m.eval()
    import os as _os; _os.makedirs(a.out, exist_ok=True); m.save(a.out)

    after=recall(m, held_q); print("recall AFTER: ", after, flush=True)
    res={"model":a.model,"n_train":len(train_q),"n_heldout":len(held_q),"n_triplets":len(triplets),
         "n_hard":a.n_hard,"epochs":a.epochs,"recall_before":before,"recall_after":after,
         "delta":{k: round(after[k]-before[k],3) for k in after}}
    os.makedirs(a.out, exist_ok=True); json.dump(res, open(f"{a.out}/contrastive_result.json","w"), indent=2)
    print("CONTRASTIVE_DONE delta:", res["delta"], "-> saved", a.out, flush=True)

if __name__=="__main__": raise SystemExit(main())
