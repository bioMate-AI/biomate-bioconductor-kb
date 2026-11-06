"""Retriever (plan section 2 protocol): build / query / add over a RetrievalStore with a stereo-aware fingerprint index and an
optional embedding index. Blind-rule and exclusion filters are applied BEFORE ranking, so excluded rows can never be returned."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List, Optional, Sequence

import numpy as np

from .index import EmbeddingIndex, FingerprintIndex, rank_desc
from .store import Row, RetrievalStore, canon


@dataclass(frozen=True)
class Hit:
    smiles: str
    sim: float
    values: Dict[str, float]
    doc: Optional[str]
    doc_year: Optional[int]
    target: Optional[str]
    flat_key: str
    source: str


class Retriever:
    def __init__(self, store: Optional[RetrievalStore] = None, chiral: bool = True):
        self.store = store or RetrievalStore()
        self.fp = FingerprintIndex(chiral=chiral)
        self.emb: Optional[EmbeddingIndex] = None
        self._embed_fn = None
        if len(self.store):
            self.fp.fit([r.smiles for r in self.store.rows])

    # ---- protocol ----------------------------------------------------------------------------------------------
    def build(self, rows: Sequence[Row], embeddings: Optional[EmbeddingIndex] = None) -> "Retriever":
        self.store = RetrievalStore(rows)
        self.fp = FingerprintIndex(chiral=self.fp.chiral).fit([r.smiles for r in self.store.rows])
        self.emb = embeddings
        if embeddings is not None:
            assert embeddings.smiles == [r.smiles for r in self.store.rows], "embedding index not aligned with the store"
        return self

    def attach_embeddings(self, emb: EmbeddingIndex, embed_fn) -> None:
        assert emb.smiles == [r.smiles for r in self.store.rows], "embedding index not aligned with the store"
        self.emb, self._embed_fn = emb, embed_fn

    def add(self, smiles: str, score_dict: Dict[str, float], doc: Optional[str] = None, doc_year: Optional[int] = None,
            target: Optional[str] = None) -> bool:
        r = self.store.add(smiles, score_dict, doc, doc_year, target)
        if r is None:
            return False
        self.fp.add(r.smiles)
        if self.emb is not None:      # keep alignment: online rows are fingerprint-only unless re-embedded
            self.emb = None
        return True

    def query(self, smiles: str, k: int = 8, exclude_docs=None, exclude_flat=None, min_year=None, max_year=None,
              strict_docs: bool = False, target: Optional[str] = None, exclude_self: bool = True, mode: str = "fingerprint",
              alpha: float = 0.5) -> List[Hit]:
        c = canon(smiles)
        if c is None or len(self.store) == 0:
            return []
        allowed = np.array(self.store.mask(exclude_docs, exclude_flat, min_year, max_year, strict_docs, target), dtype=bool)
        if exclude_self:
            allowed &= np.array([r.smiles != c[0] for r in self.store.rows], dtype=bool)
        sims = self.fp.sims(c[0])
        if mode in ("embedding", "hybrid"):
            if self.emb is None or self._embed_fn is None:
                raise RuntimeError("embedding mode requested but no embedding index attached")
            qe = np.asarray(self._embed_fn([c[0]]), dtype=np.float32)[0]
            es = self.emb.sims(qe)
            sims = es if mode == "embedding" else (alpha * sims + (1 - alpha) * es).astype(np.float32)
        sims = np.where(allowed, sims, -np.inf)               # excluded rows can never rank
        order = rank_desc(sims)
        out: List[Hit] = []
        for i in order:
            if not np.isfinite(sims[i]) or len(out) >= k:
                break
            r = self.store.rows[int(i)]
            out.append(Hit(r.smiles, float(sims[i]), dict(r.values), r.doc, r.doc_year, r.target, r.flat_key, r.source))
        return out

    def save(self, path: str) -> None:
        import json
        self.fp.save(path + ".fp.npz")
        with open(path + ".rows.json", "w") as fh:
            json.dump([dict(smiles=r.smiles, flat_key=r.flat_key, values=r.values, doc=r.doc, doc_year=r.doc_year,
                            target=r.target, source=r.source) for r in self.store.rows], fh)

    @classmethod
    def load(cls, path: str) -> "Retriever":
        import json
        with open(path + ".rows.json") as fh:
            rows = [Row(**d) for d in json.load(fh)]
        rt = cls(RetrievalStore(rows))
        rt.fp = FingerprintIndex.load(path + ".fp.npz")
        assert rt.fp.smiles == [r.smiles for r in rows]
        return rt
