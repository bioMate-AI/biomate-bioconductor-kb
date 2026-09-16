# Routing as retrieve-then-rank — retriever (step 1) eval

Reframing: routing over 4,200 workflows is retrieve-then-rank (learning-to-rank), not single-label
classification. The prior 2×2's "+0.83 from candidates" was the retrieval step in disguise. Here we
measure it directly. Corpus = 4,200 catalog workflows (doc = name+domain+description+input/output
types+tools_used). Queries = 196 in-catalog RealBio items (4/200 labels are not in the catalog →
retrieval ceiling ~0.98).

| Retriever | recall@1 | recall@5 | recall@10 | recall@20 | recall@50 | MRR |
|-----------|----------|----------|-----------|-----------|-----------|-----|
| Lexical (TF-IDF 1-2gram) | 0.48 | 0.80 | 0.86 | 0.92 | 0.96 | 0.62 |
| Dense (MiniLM, general)  | 0.37 | 0.64 | 0.74 | 0.81 | 0.91 | 0.49 |
| Dense (BGE-small, domain)| 0.44 | 0.78 | 0.83 | 0.89 | 0.954 | 0.60 |
| Hybrid (TF-IDF+MiniLM)   | 0.51 | 0.83 | 0.90 | 0.94 | 0.985 | 0.65 |
| **Hybrid (TF-IDF+BGE)**  | 0.52 | 0.83 | 0.89 | 0.949 | 0.98 | 0.66 |

## Findings
1. Retrieval carries routing: hybrid recall@20=0.94, recall@50=0.985. The LLM ranker only needs to
   rerank a small retrieved set; that is where the 2×2 candidate effect came from.
2. Lexical > domain dense > general dense: TF-IDF (r@5 0.80) > BGE-small (0.78) > MiniLM (0.64). Domain
   routing depends on rare tokens (gene/assay/tool names); even a domain embedder slightly trails lexical.
   Best = hybrid TF-IDF+BGE (recall@20=0.95). A bigger/bio-specific embedder may add a little more.
3. recall@1≈0.51: search alone cannot pick the winner — the rank step is essential (0.94→top-1).

## Implications
- Build routing candidate sets from the REAL retriever (top-k hard negatives), not random/same-domain.
- Train the rank step as learning-to-rank with graded relevance; ambiguity is modeled, not rejected
  (this also fixes the low generation pass-rate, which was the "unambiguous" gate fighting a ranking task).
- Report recall@k (retrieval) separately from NDCG/top-1 (ranking), per TASK_CATALOG T05.
- Next: swap MiniLM for a domain embedder (BGE); re-run the base-vs-SFT rank eval on REAL retrieved
  top-20 hard negatives (harder, more realistic than the 9 random/same-domain candidates before).
