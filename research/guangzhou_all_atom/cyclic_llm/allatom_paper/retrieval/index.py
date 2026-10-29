"""Similarity indices. FingerprintIndex = stereo-aware Morgan (r2, 2048 bit, includeChirality) + exact Tanimoto;
EmbeddingIndex = cosine over frozen encoder embeddings (PeptideCLM-2) with a content-hash cache.
Determinism: ties are broken by ascending row index (np.lexsort), so identical inputs give identical rankings."""
from __future__ import annotations

import hashlib
import json
import os
from typing import List, Optional, Sequence

import numpy as np

try:
    from rdkit import Chem, RDLogger
    from rdkit.Chem import rdFingerprintGenerator

    RDLogger.DisableLog("rdApp.*")
    _GEN = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=2048, includeChirality=True)
    _GEN_FLAT = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=2048, includeChirality=False)
except Exception:  # pragma: no cover
    _GEN = _GEN_FLAT = None


def fp_bits(smiles: str, chiral: bool = True) -> Optional[np.ndarray]:
    m = Chem.MolFromSmiles(smiles) if isinstance(smiles, str) else None
    if m is None:
        return None
    return (_GEN if chiral else _GEN_FLAT).GetFingerprintAsNumPy(m).astype(np.uint8)


def rank_desc(scores: np.ndarray) -> np.ndarray:
    """indices sorted by score descending, ties by ascending index (deterministic)."""
    return np.lexsort((np.arange(len(scores)), -scores))


class FingerprintIndex:
    def __init__(self, chiral: bool = True):
        self.chiral = chiral
        self.smiles: List[str] = []
        self.bits = np.zeros((0, 2048), dtype=np.uint8)
        self.n_bits = np.zeros(0, dtype=np.float32)

    def fit(self, smiles: Sequence[str]) -> "FingerprintIndex":
        self.smiles = list(smiles)
        rows = []
        for s in self.smiles:
            b = fp_bits(s, self.chiral)
            rows.append(b if b is not None else np.zeros(2048, dtype=np.uint8))
        self.bits = np.vstack(rows) if rows else np.zeros((0, 2048), dtype=np.uint8)
        self.n_bits = self.bits.sum(1).astype(np.float32)
        return self

    def add(self, smiles: str) -> None:
        b = fp_bits(smiles, self.chiral)
        b = b if b is not None else np.zeros(2048, dtype=np.uint8)
        self.smiles.append(smiles)
        self.bits = np.vstack([self.bits, b[None, :]])
        self.n_bits = np.append(self.n_bits, np.float32(b.sum()))

    def sims(self, query: str) -> np.ndarray:
        """Tanimoto of the query to every row (0 for an unparsable query or an empty row pair)."""
        q = fp_bits(query, self.chiral)
        if q is None or len(self.smiles) == 0:
            return np.zeros(len(self.smiles), dtype=np.float32)
        inter = self.bits.astype(np.float32) @ q.astype(np.float32)
        union = self.n_bits + np.float32(q.sum()) - inter
        return np.where(union > 0, inter / np.maximum(union, 1), 0.0).astype(np.float32)

    def save(self, path: str) -> None:
        np.savez_compressed(path, bits=np.packbits(self.bits, axis=1), smiles=np.array(self.smiles, dtype=object),
                            chiral=np.array([self.chiral]))

    @classmethod
    def load(cls, path: str) -> "FingerprintIndex":
        z = np.load(path, allow_pickle=True)
        ix = cls(chiral=bool(z["chiral"][0]))
        ix.smiles = [str(s) for s in z["smiles"]]
        ix.bits = np.unpackbits(z["bits"], axis=1)[:, :2048].astype(np.uint8)
        ix.n_bits = ix.bits.sum(1).astype(np.float32)
        return ix


class EmbeddingIndex:
    """Cosine index over a fixed embedding matrix aligned with the store rows. `embed_fn(list[str]) -> ndarray` is injected
    (e.g. a frozen PeptideCLM-2 mean-pooled encoder, run on EC2/Spark only); results are cached by content hash."""

    def __init__(self, cache_dir: Optional[str] = None, model_tag: str = "unset"):
        self.cache_dir, self.model_tag = cache_dir, model_tag
        self.smiles: List[str] = []
        self.emb = np.zeros((0, 0), dtype=np.float32)

    @staticmethod
    def _norm(x: np.ndarray) -> np.ndarray:
        n = np.linalg.norm(x, axis=1, keepdims=True)
        return (x / np.maximum(n, 1e-12)).astype(np.float32)

    def _key(self, smiles: Sequence[str]) -> str:
        return hashlib.sha256((self.model_tag + "\n" + "\n".join(smiles)).encode()).hexdigest()[:20]

    def fit(self, smiles: Sequence[str], embed_fn) -> "EmbeddingIndex":
        self.smiles = list(smiles)
        path = os.path.join(self.cache_dir, f"emb_{self._key(self.smiles)}.npy") if self.cache_dir else None
        if path and os.path.exists(path):
            self.emb = np.load(path)
        else:
            self.emb = self._norm(np.asarray(embed_fn(self.smiles), dtype=np.float32))
            if path:
                os.makedirs(self.cache_dir, exist_ok=True)
                np.save(path, self.emb)
        return self

    def sims(self, query_emb: np.ndarray) -> np.ndarray:
        q = self._norm(np.asarray(query_emb, dtype=np.float32).reshape(1, -1))[0]
        return (self.emb @ q).astype(np.float32) if len(self.emb) else np.zeros(0, dtype=np.float32)

    def save(self, path: str) -> None:
        np.savez_compressed(path, emb=self.emb, smiles=np.array(self.smiles, dtype=object), tag=np.array([self.model_tag]))

    @classmethod
    def load(cls, path: str) -> "EmbeddingIndex":
        z = np.load(path, allow_pickle=True)
        ix = cls(model_tag=str(z["tag"][0]))
        ix.smiles, ix.emb = [str(s) for s in z["smiles"]], z["emb"].astype(np.float32)
        return ix
