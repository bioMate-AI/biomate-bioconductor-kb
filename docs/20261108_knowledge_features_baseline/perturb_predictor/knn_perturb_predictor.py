"""Knowledge-neighbor perturbation-effect predictor (deployable, CPU, no deps beyond numpy).

Predicts a held-out gene-knockout's per-context residual transcriptional effect by averaging the
MEASURED effects of training KOs that share curated gene-sets (GO/KEGG/Reactome) with it. The KO
whose effect is unknown is placed near its pathway neighbours and its effect is read off as their
(set-sharing-weighted) average.

Validated at full scale on the CZI genome-scale CD4+ T Perturb-seq atlas (33,983 contrasts, ~7k KOs
per culture context): the knowledge-weighted neighbour mean POSITIVELY predicts unseen-KO residual
effects (top-50 DE Pearson +0.078 at Rest) and beats a size-matched random-neighbour control by
t=+13.7..+28.5. A learned linear kernel-ridge over the same graph does NOT beat this simple average,
so the plain neighbour mean is the recommended shippable baseline.

API
    p = KnnPerturbPredictor(weighting="count", topk=None)   # or weighting="jaccard", topk=10
    p.fit(ko_names, effects, gene_sets)   # effects [n_ko, n_genes] per-context-CENTERED residuals
    yhat = p.predict(query_ko_names)      # [n_query, n_genes]; exact-name self-matches are excluded
    yhat = p.predict_loo()                # leave-one-out predictions for the fitted KOs

Inputs
    ko_names    : iterable[str]           KO gene symbol per training row
    effects     : float[n_ko, n_genes]    measured residual effect (subtract the per-context mean first)
    gene_sets   : iterable[set[str]]      curated gene-sets (e.g. parsed GO/KEGG/Reactome .gmt lines);
                                          a KO is a member of a set iff its symbol is in that set.
"""
import numpy as np


class KnnPerturbPredictor:
    def __init__(self, weighting="count", topk=None, min_shared=1):
        if weighting not in ("count", "jaccard"):
            raise ValueError("weighting must be 'count' or 'jaccard'")
        self.weighting = weighting
        self.topk = topk
        self.min_shared = int(min_shared)

    def fit(self, ko_names, effects, gene_sets):
        self.ko_ = np.asarray(list(ko_names), dtype=object).astype(str)
        self.Y_ = np.ascontiguousarray(effects, dtype=np.float32)
        if self.Y_.shape[0] != len(self.ko_):
            raise ValueError("effects rows must match ko_names")
        set_of = {}
        for j, s in enumerate(gene_sets):
            for g in s:
                set_of.setdefault(g, []).append(j)
        self.set_of_ = set_of
        self.full_deg_ = np.array([len(set_of.get(g, [])) for g in self.ko_], np.float32)
        # dense membership over the gene-sets actually touched by a training KO
        touched = sorted({j for g in self.ko_ for j in set_of.get(g, [])})
        self.col_ = {j: c for c, j in enumerate(touched)}
        Mb = np.zeros((len(self.ko_), max(1, len(touched))), np.float32)
        for a, g in enumerate(self.ko_):
            for j in set_of.get(g, []):
                Mb[a, self.col_[j]] = 1.0
        self.Mb_ = Mb
        return self

    def _apply_weighting(self, S, deg_q):
        """S [nq, n_train] shared-set counts -> weight matrix (count or Jaccard, min_shared, topk)."""
        if self.weighting == "jaccard":
            denom = deg_q[:, None] + self.full_deg_[None, :] - S
            with np.errstate(divide="ignore", invalid="ignore"):
                W = np.where(denom > 0, S / denom, 0.0).astype(np.float32)
        else:
            W = S.astype(np.float32).copy()
        W[S < self.min_shared] = 0.0
        if self.topk:
            for i in range(W.shape[0]):
                r = W[i]; nz = np.where(r > 0)[0]
                if len(nz) > self.topk:
                    drop = nz[np.argsort(-r[nz])[self.topk:]]
                    r[drop] = 0.0
        return W

    def _shared(self, query_names):
        q = np.asarray(list(query_names), dtype=object).astype(str)
        Mq = np.zeros((len(q), self.Mb_.shape[1]), np.float32)
        degq = np.zeros(len(q), np.float32)
        for a, g in enumerate(q):
            js = self.set_of_.get(g, [])
            degq[a] = len(js)
            for j in js:
                c = self.col_.get(j)
                if c is not None:
                    Mq[a, c] = 1.0
        S = Mq @ self.Mb_.T
        for a, g in enumerate(q):               # LOO-safe: never let a KO be its own neighbour
            S[a, self.ko_ == g] = 0.0
        return q, S, degq

    def predict(self, query_names):
        _, S, degq = self._shared(query_names)
        W = self._apply_weighting(S, degq)
        den = W.sum(1, keepdims=True)
        return np.where(den > 0, (W @ self.Y_) / np.maximum(den, 1e-9), 0.0).astype(np.float32)

    def predict_loo(self):
        return self.predict(self.ko_)

    def has_neighbors(self, query_names):
        _, S, _ = self._shared(query_names)
        return (S > 0).any(1)
