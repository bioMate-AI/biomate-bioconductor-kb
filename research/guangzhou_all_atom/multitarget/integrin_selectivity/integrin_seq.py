"""Integrin descriptors from UniProt FASTA (human). Crude windows, NOT domain annotations:
beta subunits: first 450 residues of the precursor; alpha subunits: first 600 residues.
Identity = matches / max(len) from a global Needleman-Wunsch alignment (match +2, mismatch -1, gap -2).
Heterodimer kernel K = 0.5*(alpha identity + beta identity)."""
import numpy as np
from pathlib import Path
HERE = Path(__file__).parent
UNIPROT = {"avb3": ("P06756", "P05106"), "avb5": ("P06756", "P18084"), "avb6": ("P06756", "P18564"),
           "avb8": ("P06756", "P26012"), "a5b1": ("P08648", "P05556"), "aIIbb3": ("P08514", "P05106")}
WIN = {"alpha": 600, "beta": 450}


def read_fasta(acc):
    return "".join(l.strip() for l in open(HERE / "src_raw" / "uniprot" / f"{acc}.fasta") if not l.startswith(">"))


def nw_identity(a, b, match=2, mis=-1, gap=-2):
    n, m = len(a), len(b)
    A = np.frombuffer(a.encode(), dtype=np.uint8); B = np.frombuffer(b.encode(), dtype=np.uint8)
    S = np.zeros((n + 1, m + 1), dtype=np.int32); S[:, 0] = gap * np.arange(n + 1); S[0, :] = gap * np.arange(m + 1)
    for i in range(1, n + 1):
        sub = np.where(B == A[i - 1], match, mis)
        diag = S[i - 1, :-1] + sub; up = S[i - 1, 1:] + gap
        row = np.maximum(diag, up)
        for j in range(1, m + 1):  # left dependency
            v = max(row[j - 1], S[i, j - 1] + gap)
            S[i, j] = v
    i, j, matches = n, m, 0
    while i > 0 and j > 0:
        s = S[i, j]
        if s == S[i - 1, j - 1] + (match if a[i - 1] == b[j - 1] else mis):
            matches += a[i - 1] == b[j - 1]; i -= 1; j -= 1
        elif s == S[i - 1, j] + gap: i -= 1
        else: j -= 1
    return matches / max(n, m)


def kernel(names):
    seq = {}
    def get(acc, kind):
        if (acc, kind) not in seq: seq[(acc, kind)] = read_fasta(acc)[:WIN[kind]]
        return seq[(acc, kind)]
    cache = {}
    def ident(a1, a2, kind):
        if a1 == a2: return 1.0
        k = tuple(sorted((a1, a2)))
        if (k, kind) not in cache: cache[(k, kind)] = nw_identity(get(k[0], kind), get(k[1], kind))
        return cache[(k, kind)]
    K = np.eye(len(names)); parts = {}
    for x, n1 in enumerate(names):
        for y, n2 in enumerate(names):
            a = ident(UNIPROT[n1][0], UNIPROT[n2][0], "alpha"); b = ident(UNIPROT[n1][1], UNIPROT[n2][1], "beta")
            K[x, y] = 0.5 * (a + b); parts[(n1, n2)] = (a, b)
    return K, parts

if __name__ == "__main__":
    names = ["avb3", "avb5", "avb6", "avb8", "a5b1"]
    K, _ = kernel(names); print(np.round(K, 3))
