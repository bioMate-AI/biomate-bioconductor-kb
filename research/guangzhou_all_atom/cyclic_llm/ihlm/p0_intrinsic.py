#!/usr/bin/env python3
"""Intrinsic evaluation of a SMILES-LM checkpoint (P0 = the 2026-10-27 atom LM; later P1 and any candidate base). Baseline numbers for the P1 quality gates
(docs/20261030_IHLM_PRETRAINING_PLAN_P1.md). All metrics reported with CIs; source-grouped where the data have sources.
  A  held-out perplexity: CycPeptMPDB peptides (held out of P0's corpus by its Tanimoto >= 0.9 filter); cluster bootstrap over Source
  B  stereo / N-methyl sensitivity: paired per-token log-likelihood difference  true - D-flipped variant (one stereocentre inverted) and true - N-Me-shifted variant (one N-methyl moved to another
     secondary amide); sensitivity = mean gap > 0 means the model prefers the real isomer; CI by cluster bootstrap over Source
  C  sampling check (N samples, temperature 1): validity (RDKit), uniqueness, novelty vs the training corpus (canonical SMILES), macrocycle fraction (ring >= 12), ring-size and N-methyl-count
     distributions vs real CycPeptMPDB peptides (total-variation distance)
usage: python3 p0_intrinsic.py CKPT VOCAB_JSON OUT.json [--n-sample 1000] [--n-eval 1500] [--corpus corpus.smi.gz]   (cyclic_llm/ihlm; CPU ok)"""
import os, sys, json, csv, gzip, argparse, random, collections
import numpy as np, torch
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, os.path.join(HERE, "..", "allatom")); sys.path.insert(0, HERE)
import atom_lm as A
from symbolic import propose_edit_smiles
from rdkit import Chem, RDLogger
RDLogger.DisableLog("rdApp.*")
ap = argparse.ArgumentParser(); ap.add_argument("ckpt"); ap.add_argument("vocab"); ap.add_argument("out"); ap.add_argument("--n-sample", type=int, default=1000); ap.add_argument("--n-eval", type=int, default=1500)
ap.add_argument("--corpus", default=""); ap.add_argument("--max-len", type=int, default=256); ap.add_argument("--d", type=int, default=512); ap.add_argument("--layers", type=int, default=8); ap.add_argument("--heads", type=int, default=8); ap.add_argument("--seed", type=int, default=0)
a = ap.parse_args(); rng = random.Random(a.seed); torch.manual_seed(a.seed)
itos = json.load(open(a.vocab)); vocab = A.Vocab(itos[4:]) if itos[:4] == ["<pad>", "<bos>", "<eos>", "<unk>"] else A.Vocab(itos)
model = A.GPT(len(vocab), d=a.d, layers=a.layers, heads=a.heads, max_len=a.max_len); model.load_state_dict(torch.load(a.ckpt, map_location="cpu", weights_only=False)["model"]); model.eval()
rows = [r for r in csv.DictReader(open(os.path.join(HERE, "..", "..", "data", "raw", "CycPeptMPDB_Peptide_All.csv"), encoding="utf-8-sig", errors="replace")) if r.get("SMILES")]
seen = set(); pool = []
for r in rows:
    m = Chem.MolFromSmiles(r["SMILES"]);
    if m is None: continue
    c = Chem.MolToSmiles(m)
    if c in seen: continue
    seen.add(c); pool.append((c, r["Source"]))
rng.shuffle(pool); pool = pool[: a.n_eval]; out = {"checkpoint": os.path.basename(a.ckpt), "n_params": sum(p.numel() for p in model.parameters()), "n_eval_peptides": len(pool)}


@torch.no_grad()
def nll(smi_list, bs=32):
    """per-token mean log-likelihood for each SMILES (higher = more likely); None when untokenisable or too long."""
    res = [None] * len(smi_list); ids = []
    for i, s in enumerate(smi_list):
        try: e = vocab.encode(s)
        except AssertionError: continue
        if len(e) <= a.max_len: ids.append((i, e))
    for k in range(0, len(ids), bs):
        ch = ids[k:k + bs]; mx = max(len(e) for _, e in ch); X = torch.full((len(ch), mx), A.PAD, dtype=torch.long)
        for j, (_, e) in enumerate(ch): X[j, :len(e)] = torch.tensor(e)
        lp = torch.log_softmax(model(X)[:, :-1], -1).gather(2, X[:, 1:, None])[:, :, 0]; mk = (X[:, 1:] != A.PAD).float(); v = (lp * mk).sum(1) / mk.sum(1)
        for (i, _), x in zip(ch, v.tolist()): res[i] = x
    return res


def cluster_boot(vals, groups, B=2000, seed=0):
    """mean with a cluster bootstrap over groups (Source)."""
    r = np.random.default_rng(seed); g = collections.defaultdict(list)
    for v, k in zip(vals, groups): g[k].append(v)
    keys = list(g); means = [np.mean(g[k]) for k in keys]; w = [len(g[k]) for k in keys]; pt = float(np.average(means, weights=w)); bs = []
    for _ in range(B):
        ix = r.integers(0, len(keys), len(keys)); bs.append(np.average([means[i] for i in ix], weights=[w[i] for i in ix]))
    return dict(mean=round(pt, 4), ci95=[round(float(np.percentile(bs, 2.5)), 4), round(float(np.percentile(bs, 97.5)), 4)], n_clusters=len(keys), n=len(vals))


# A: held-out perplexity
s_true = nll([p[0] for p in pool]); ok = [i for i, v in enumerate(s_true) if v is not None]
out["A_heldout_perplexity"] = {"coverage": round(len(ok) / len(pool), 3), "mean_token_nll": cluster_boot([-s_true[i] for i in ok], [pool[i][1] for i in ok]), "perplexity_of_mean_nll": round(float(np.exp(-np.mean([s_true[i] for i in ok]))), 3)}
# B: stereo / N-Me sensitivity (paired)
dflip_gap, nmeshift_gap, g1, g2 = [], [], [], []
for i in ok[: min(len(ok), 600)]:
    smi, src = pool[i]; edits = propose_edit_smiles(smi, max_per_type=3); fl = [s for t, s in edits if t.startswith("dflip")]; nr = [s for t, s in edits if t == "nme_remove"]; na = [s for t, s in edits if t == "nme_add"]
    if fl:
        v = nll(fl); v = [x for x in v if x is not None]
        if v: dflip_gap.append(s_true[i] - float(np.mean(v))); g1.append(src)
    if nr and na:   # N-Me shift = remove one + add one (compare the pair-average of the single edits as a proxy: true vs unrelated N-Me position change)
        v = nll(na[:2] + nr[:2]); v = [x for x in v if x is not None]
        if v: nmeshift_gap.append(s_true[i] - float(np.mean(v))); g2.append(src)
out["B_stereo_sensitivity"] = {"dflip_gap_true_minus_variant": cluster_boot(dflip_gap, g1) if dflip_gap else None, "nme_edit_gap_true_minus_variant": cluster_boot(nmeshift_gap, g2) if nmeshift_gap else None,
                               "note": "gap > 0 (CI above 0): the model prefers the real isomer/N-Me pattern over a single-edit variant. NOTE: the variant is not a measured compound, so this tests plausibility not activity"}
# C: sampling
corpus = set()
if a.corpus and os.path.exists(a.corpus):
    for l in gzip.open(a.corpus, "rt"):
        s = l.strip().split()[0] if l.strip() else ""
        if s: corpus.add(s)
samples = A.sample(model, vocab, a.n_sample, max_len=a.max_len, temperature=1.0, seed=a.seed)
can = []; valid = 0
for s in samples:
    m = Chem.MolFromSmiles(s) if s else None
    if m is not None: valid += 1; can.append(Chem.MolToSmiles(m))
def ring_stats(smiles):
    rs, nme = [], []
    for s in smiles:
        m = Chem.MolFromSmiles(s); rr = [len(r) for r in m.GetRingInfo().AtomRings()]; rs.append(max(rr) if rr else 0); nme.append(len(m.GetSubstructMatches(Chem.MolFromSmarts("[CX3](=O)[NX3;!H1]([CH3])"))))
    return rs, nme
real = [p[0] for p in pool]; rr_real, nme_real = ring_stats(real); rr_s, nme_s = ring_stats(can) if can else ([], [])
def tv(x, y, bins):
    hx = np.histogram(x, bins=bins)[0] / max(len(x), 1); hy = np.histogram(y, bins=bins)[0] / max(len(y), 1); return round(float(0.5 * np.abs(hx - hy).sum()), 4)
out["C_sampling"] = {"n_sampled": len(samples), "validity": round(valid / len(samples), 4), "uniqueness_of_valid": round(len(set(can)) / max(len(can), 1), 4),
                     "novelty_vs_corpus": (round(1 - sum(c in corpus for c in set(can)) / max(len(set(can)), 1), 4) if corpus else "corpus not provided"),
                     "macrocycle_fraction_ring_ge12": round(float(np.mean([r >= 12 for r in rr_s])), 4) if rr_s else 0.0, "macrocycle_fraction_real_cycpeptmpdb": round(float(np.mean([r >= 12 for r in rr_real])), 4),
                     "max_ring_size_TV_distance_vs_real": tv(rr_s, rr_real, [0, 6, 8, 12, 16, 24, 40, 100]) if rr_s else None, "n_methyl_count_TV_distance_vs_real": tv(nme_s, nme_real, [0, 1, 2, 3, 5, 8, 40]) if nme_s else None,
                     "mean_n_methyl_sampled": round(float(np.mean(nme_s)), 3) if nme_s else None, "mean_n_methyl_real": round(float(np.mean(nme_real)), 3)}
json.dump(out, open(a.out, "w"), indent=1); print(json.dumps(out, indent=1))
