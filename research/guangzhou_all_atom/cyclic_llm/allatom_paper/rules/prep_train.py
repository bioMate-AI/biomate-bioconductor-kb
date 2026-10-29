"""Build the LoRA-under-mask smoke corpus ON EC2: satisfying S-LIB-style peptides (monomer-library enumeration, NOT CycPeptMPDB-derived), tokenised with the ChemFM vocabulary,
plus the per-position feasibility mask (the automaton's mask BEFORE each target token). usage: prep_train.py OUTDIR [--n-train 1700] [--n-eval 100]"""
import os, sys, argparse, time
import numpy as np
from multiprocessing import Pool
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, os.path.join(HERE, ".."))
from rules import golden, vocab as V
from rules.constraint import ChemFMConstraint

TOK = os.environ.get("CHEMFM_TOK", os.path.join(os.environ.get("CHEMFM_DIR", "."), "tokenizer.json"))
LMAX = 320
_C = None


def _init():
    global _C; _C = ChemFMConstraint(V.load(TOK), max_len=500)


def _one(s):
    c = _C; ids = c.vocab.encode(s) + [c.eos]
    if len(ids) > LMAX: return None
    st = c.init_state(); masks = []
    for j, t in enumerate(ids[:-1]):
        ok = c.advance(st, t)
        if not ok: return None
        masks.append(c.mask(st))
    # masks[j] = feasible set for target ids[j+1]; soundness guarantees the true token is inside (checked below)
    M = np.stack(masks)
    if not M[np.arange(len(ids) - 1), ids[1:]].all(): return "FALSE_PRUNE"
    return np.array(ids, dtype=np.int16), np.packbits(M, axis=1)


def build(strings, name, out):
    t0 = time.time()
    with Pool(3, initializer=_init) as p: res = p.map(_one, strings, chunksize=16)
    bad = sum(r == "FALSE_PRUNE" for r in res); res = [r for r in res if isinstance(r, tuple)]
    N = len(res); ids = np.zeros((N, LMAX), dtype=np.int16); lens = np.zeros(N, dtype=np.int32); mk = np.zeros((N, LMAX - 1, 40), dtype=np.uint8)
    for k, (i, m) in enumerate(res): ids[k, :len(i)] = i; lens[k] = len(i); mk[k, :m.shape[0]] = m
    np.savez_compressed(os.path.join(out, f"{name}.npz"), ids=ids, lens=lens, masks=mk)
    print(f"{name}: {N} strings, false-prune strings dropped {bad}, mean len {lens.mean():.1f}, {time.time()-t0:.0f}s", flush=True)
    return N, bad


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("out"); ap.add_argument("--n-train", type=int, default=1700); ap.add_argument("--n-eval", type=int, default=100); a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    tr = [r["smiles"] for r in golden.make(n_sat=a.n_train, n_bad=0, n_inv=0, seed=11)]
    ev = [r["smiles"] for r in golden.make(n_sat=a.n_eval, n_bad=0, n_inv=0, seed=12)]
    ev = [s for s in ev if s not in set(tr)]
    build(tr, "train", a.out); build(ev, "eval", a.out)
