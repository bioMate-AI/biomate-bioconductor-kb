#!/usr/bin/env python3
"""Pilot 3: constrained seeded generation, LLM generators vs tuned simple generators.
Pre-registration: docs/20261031_GENERATION_PILOT3_PREREG.md (committed before any sampling). Validity/novelty/constraint yield is NOT binding or permeability evidence.
usage:
  gen_pilot.py selftest
  gen_pilot.py dev  OUTDIR --gens S-EDIT,S-LIB,...   (DEV tuning grids; seeds 100-102 x 300 samples)
  gen_pilot.py test OUTDIR --gens ... --cfg frozen_config.json   (run seeds 0-4 x 1000)
Env: CPM_CSV (CycPeptMPDB), P0_CKPT, P0_VOCAB, PCLM2_DIR (small), CHEMFM_DIR."""
import os, sys, json, csv, gzip, hashlib, random, argparse, time, itertools, collections, signal
import numpy as np
from rdkit import Chem, RDLogger, DataStructs
from rdkit.Chem import Descriptors, rdMolDescriptors, AllChem, BRICS
from rdkit.Chem.FilterCatalog import FilterCatalog, FilterCatalogParams
RDLogger.DisableLog("rdApp.*")
HERE = os.path.dirname(os.path.abspath(__file__)); CL = os.path.join(HERE, "..")
for p in (os.path.join(CL, "ihlm"), os.path.join(CL, "allatom"), os.path.join(CL, "ihlm_backbone"), CL): sys.path.insert(0, p)
CPM = os.environ.get("CPM_CSV", os.path.join(CL, "..", "data", "raw", "CycPeptMPDB_Peptide_All.csv"))
MONO_JSON = os.environ.get("MONO_JSON", os.path.join(CL, "v4_eval", "monomer_dictionary_v5.json"))
NME = Chem.MolFromSmarts("[CX3](=O)[NX3;!H1]([CH3])")
_pp = FilterCatalogParams(); _pp.AddCatalog(FilterCatalogParams.FilterCatalogs.PAINS); PAINS = FilterCatalog(_pp)
RING_BINS = [0, 6, 8, 12, 16, 24, 40, 100]; NME_BINS = [0, 1, 2, 3, 5, 8, 40]


# ---------------------------------------------------------------------------------------------- data
def iso(s):
    m = Chem.MolFromSmiles(s) if s else None
    return Chem.MolToSmiles(m) if m is not None else None


def part_of(src): return int(hashlib.sha256(str(src).encode()).hexdigest(), 16) % 2


def load_cpm():
    rows = [r for r in csv.DictReader(open(CPM, encoding="utf-8-sig", errors="replace")) if r.get("SMILES")]
    seen = {}
    for r in rows:
        c = iso(r["SMILES"])
        if c and c not in seen: seen[c] = (r.get("Source", ""), r)
    return seen


def split_data(seen):
    dev = [s for s, (src, _) in seen.items() if part_of(src) == 0]; test = [s for s, (src, _) in seen.items() if part_of(src) == 1]
    S = random.Random(12345).sample(sorted(dev), min(300, len(dev)))
    return S, dev, test


def mol_stats(m):
    rr = [len(r) for r in m.GetRingInfo().AtomRings()]
    return (max(rr) if rr else 0), len(m.GetSubstructMatches(NME))


def satisfies(m):
    """constraint set C (pre-registration section 3). m: sanitised Mol."""
    if m is None or len(Chem.GetMolFrags(m)) != 1: return False
    mr, nme = mol_stats(m)
    if mr < 12 or not (2 <= nme <= 6): return False
    mw = Descriptors.MolWt(m)
    if not (600 <= mw <= 1400): return False
    if rdMolDescriptors.CalcTPSA(m) > 300: return False
    return not PAINS.HasMatch(m)


def tv(x, y, bins):
    hx = np.histogram(x, bins=bins)[0] / max(len(x), 1); hy = np.histogram(y, bins=bins)[0] / max(len(y), 1); return round(float(0.5 * np.abs(hx - hy).sum()), 4)


def fps(smiles):
    out = []
    for s in smiles:
        m = Chem.MolFromSmiles(s); out.append(AllChem.GetMorganFingerprintAsBitVect(m, 2, 2048, useChirality=True))
    return out


def butina_clusters(fp_list, thr=0.7):
    from rdkit.ML.Cluster import Butina
    n = len(fp_list)
    if n == 0: return 0
    d = []
    for i in range(1, n): d.extend(DataStructs.BulkTanimotoSimilarity(fp_list[i], fp_list[:i]) and [1 - x for x in DataStructs.BulkTanimotoSimilarity(fp_list[i], fp_list[:i])])
    return len(Butina.ClusterData(d, n, 1 - thr, isDistData=True))


def evaluate(raw, seeds_set, cpm_set, ref_ring, ref_nme, rng):
    """metrics for one run (list of raw generated strings)."""
    n = len(raw); mols = []; canon = []
    for s in raw:
        m = Chem.MolFromSmiles(s) if s else None
        if m is not None:
            c = Chem.MolToSmiles(m); mols.append((c, m)); canon.append(c)
    valid = len(canon); uniq = {}
    for c, m in mols:
        if c not in uniq: uniq[c] = m
    novel = {c: m for c, m in uniq.items() if c not in cpm_set and c not in seeds_set}
    cons = {c: m for c, m in novel.items() if satisfies(m)}
    rr_nm = [mol_stats(m) for m in uniq.values()]
    rr = [a for a, _ in rr_nm]; nm = [b for _, b in rr_nm]
    out = dict(n=n, validity=round(valid / max(n, 1), 4), uniqueness_of_valid=round(len(uniq) / max(valid, 1), 4), novelty_of_unique=round(len(novel) / max(len(uniq), 1), 4),
               macro_fraction=round(float(np.mean([r >= 12 for r in rr])), 4) if rr else 0.0,
               ring_TV=tv(rr, ref_ring, RING_BINS) if rr else None, nme_TV=tv(nm, ref_nme, NME_BINS) if nm else None, mean_nme=round(float(np.mean(nm)), 3) if nm else None,
               n_constraint_satisfying=len(cons), Y=round(1000.0 * len(cons) / max(n, 1), 3))
    cl = list(cons)
    if cl:
        sub = cl if len(cl) <= 1500 else rng.sample(cl, 1500); f = fps(sub)
        out["Y_cluster"] = round(1000.0 * butina_clusters(f, 0.7) * (len(cl) / len(sub)) / max(n, 1), 3)
        sub2 = f[:500]; sims = []
        for i in range(1, len(sub2)): sims.extend(DataStructs.BulkTanimotoSimilarity(sub2[i], sub2[:i]))
        out["internal_diversity"] = round(1 - float(np.mean(sims)), 4) if sims else None
    else: out["Y_cluster"] = 0.0; out["internal_diversity"] = None
    return out, cons


# ---------------------------------------------------------------------------------------------- simple generators
def gen_edit(seeds, n, rng, cfg):
    from symbolic import propose_edit_smiles
    out = []
    for _ in range(n):
        cur = rng.choice(seeds)
        for _ in range(cfg["k"]):
            ed = propose_edit_smiles(cur)
            if not ed: break
            cur = rng.choice(ed)[1]
        out.append(cur)
    return out


_ALPHA = Chem.MolFromSmarts("[NX3;!$(N-C=O);!$(N=*);!$(N-S(=O)=O)]-[CX4]-[CX3](=O)[OX2H1]")
_MONO = None


def monomers():
    global _MONO
    if _MONO is None:
        d = json.load(open(MONO_JSON)); cls = {"L": [], "N": [], "D": []}; seen = set()
        for smi, code in d.items():
            if smi in seen: continue
            seen.add(smi); m = Chem.MolFromSmiles(smi)
            if m is None: continue
            mt = m.GetSubstructMatch(_ALPHA)
            if not mt: continue
            k = "N" if (code.startswith("me") or code.startswith("Me_") or code == "Sar") else ("D" if (code.startswith("d") and len(code) > 1 and code[1].isupper()) else "L")
            cls[k].append((m, mt, code))
        _MONO = cls
    return _MONO


def build_cyclic(seq):
    combo = Chem.Mol(); offs = []
    for m, mt, _ in seq: offs.append(combo.GetNumAtoms()); combo = Chem.CombineMols(combo, m)
    rw = Chem.RWMol(combo); rem = []; L = len(seq)
    for i in range(L):
        mt = seq[i][1]; c = offs[i] + mt[2]; oh = offs[i] + mt[4]; j = (i + 1) % L; nn = offs[j] + seq[j][1][0]
        rw.AddBond(c, nn, Chem.BondType.SINGLE); rem.append(oh)
    for a in sorted(rem, reverse=True): rw.RemoveAtom(a)
    mol = rw.GetMol(); Chem.SanitizeMol(mol); return Chem.MolToSmiles(mol)


def gen_lib(seeds, n, rng, cfg):
    M = monomers(); lo, hi = cfg["len"]; out = []
    for _ in range(n):
        L = rng.randint(lo, hi); seq = []
        for _ in range(L):
            u = rng.random(); k = "N" if u < cfg["p_nme"] else ("D" if u < cfg["p_nme"] + cfg["p_d"] else "L"); seq.append(rng.choice(M[k]))
        try: out.append(build_cyclic(seq))
        except Exception: out.append("")
    return out


class _TO(Exception): pass


def _alarm(sig, frm): raise _TO()


def gen_brics(seeds, n, rng, cfg):
    cache = {}; out = []
    for _ in range(n):
        a, b = rng.sample(seeds, 2)
        for s in (a, b):
            if s not in cache: cache[s] = sorted(BRICS.BRICSDecompose(Chem.MolFromSmiles(s)))
        fr = cache[a] + cache[b]; rng.shuffle(fr); ms = [Chem.MolFromSmiles(f) for f in fr[: cfg["nf"]]]; ms = [m for m in ms if m is not None]
        res = ""
        try:
            signal.signal(signal.SIGALRM, _alarm); signal.setitimer(signal.ITIMER_REAL, 0.4)
            p = next(BRICS.BRICSBuild(ms), None)
            signal.setitimer(signal.ITIMER_REAL, 0)
            if p is not None:
                rw = Chem.RWMol(p)
                for i in sorted([x.GetIdx() for x in rw.GetAtoms() if x.GetAtomicNum() == 0], reverse=True): rw.RemoveAtom(i)
                mol = rw.GetMol(); Chem.SanitizeMol(mol); res = Chem.MolToSmiles(mol)
        except Exception:
            signal.setitimer(signal.ITIMER_REAL, 0)
        out.append(res)
    return out


def gen_copy(seeds, n, rng, cfg): return [rng.choice(seeds) for _ in range(n)]


# ---------------------------------------------------------------------------------------------- LLM generators
_P0 = {}


def _p0(random_init=False):
    key = random_init
    if key not in _P0:
        import torch, atom_lm as A
        itos = json.load(open(os.environ["P0_VOCAB"])); vocab = A.Vocab(itos[4:]) if itos[:4] == ["<pad>", "<bos>", "<eos>", "<unk>"] else A.Vocab(itos)
        model = A.GPT(len(vocab), d=512, layers=8, heads=8, max_len=256)
        if random_init: torch.manual_seed(0)
        else: model.load_state_dict(torch.load(os.environ["P0_CKPT"], map_location="cpu", weights_only=False)["model"])
        _P0[key] = (model.eval(), vocab, A)
    return _P0[key]


def _p0_complete(model, prefix, max_new, temp, gen):
    """KV-cached sampling for equal-length prefixes (B,P). Mirrors allatom/atom_lm.GPT exactly."""
    import torch, torch.nn.functional as F
    B, P = prefix.shape; H = model.blocks[0].heads; caches = []
    with torch.no_grad():
        h = model.tok(prefix) + model.pos(torch.arange(P))[None]
        for blk in model.blocks:
            D = h.shape[-1]; q, k, v = blk.qkv(blk.ln1(h)).view(B, P, 3, H, D // H).permute(2, 0, 3, 1, 4); caches.append((k, v))
            h = h + blk.proj(F.scaled_dot_product_attention(q, k, v, is_causal=True).transpose(1, 2).reshape(B, P, D)); h = h + blk.mlp(blk.ln2(h))
        logits = model.head(model.ln(h[:, -1])); out = []; done = torch.zeros(B, dtype=torch.bool)
        for t in range(min(max_new, model.max_len - P)):
            nxt = torch.multinomial(F.softmax(logits / temp, -1), 1, generator=gen); out.append(nxt); done |= nxt[:, 0] == 2
            if done.all(): break
            h = model.tok(nxt) + model.pos(torch.tensor([P + t]))[None]; new = []
            for blk, (k0, v0) in zip(model.blocks, caches):
                D = h.shape[-1]; q, k, v = blk.qkv(blk.ln1(h)).view(B, 1, 3, H, D // H).permute(2, 0, 3, 1, 4); k = torch.cat([k0, k], 2); v = torch.cat([v0, v], 2); new.append((k, v))
                h = h + blk.proj(F.scaled_dot_product_attention(q, k, v).transpose(1, 2).reshape(B, 1, D)); h = h + blk.mlp(blk.ln2(h))
            caches = new; logits = model.head(model.ln(h[:, -1]))
    return torch.cat(out, 1) if out else torch.zeros(B, 0, dtype=torch.long)


def gen_p0(seeds, n, rng, cfg, random_init=False):
    import torch
    model, vocab, A = _p0(random_init); gen = torch.Generator().manual_seed(rng.randrange(1 << 30)); groups = collections.defaultdict(list)
    for i in range(n):
        s = rng.choice(seeds)
        try: e = vocab.encode(s)
        except AssertionError: continue
        P = max(2, min(len(e) - 1, 1 + int(round(cfg["prefix"] * (len(e) - 2))))); P = max(2, (P // 4) * 4); groups[P].append((i, e[:P]))
    res = {}
    for P, items in groups.items():
        for k in range(0, len(items), 128):
            ch = items[k:k + 128]; pre = torch.tensor([e for _, e in ch]); cont = _p0_complete(model, pre, 200, cfg["temp"], gen)
            for (i, e), row in zip(ch, cont.tolist()):
                toks = e[1:]
                for t in row:
                    if t == 2: break
                    toks.append(t)
                res[i] = vocab.decode(toks)
    return [res.get(i, "") for i in range(n)]


_PC = {}


def _pclm(random_init=False):
    key = random_init
    if key not in _PC:
        import torch
        from pclm_encoder import PClmMLM
        from pclm_tokenizer import PClmTokenizer
        d = os.environ["PCLM2_DIR"]; tok = PClmTokenizer(os.path.join(d, "tokenizer.json"))
        if random_init:
            cfg = json.load(open(os.path.join(d, "config.json"))); torch.manual_seed(0); model = PClmMLM(cfg)
        else: model, _, _ = PClmMLM.from_dir(d)
        _PC[key] = (model.eval(), tok)
    return _PC[key]


def _detok(tok, ids):
    t = [tok.itos[i] for i in ids if i > 4]
    return "".join(x[2:] if x.startswith("##") else x for x in t)


def gen_pclm2(seeds, n, rng, cfg, random_init=False, shuffle_logits=False):
    import torch, torch.nn.functional as F
    model, tok = _pclm(random_init); gen = torch.Generator().manual_seed(rng.randrange(1 << 30)); out = [""] * n; picks = [rng.choice(seeds) for _ in range(n)]
    enc = [tok.encode(s) for s in picks]; marg = collections.Counter(t for e in enc for t in e if t > 4); mv = torch.zeros(len(tok)); [mv.__setitem__(k, v) for k, v in marg.items()]
    with torch.no_grad():
        for k in range(0, n, 48):
            idx = list(range(k, min(n, k + 48))); L = max(len(enc[i]) for i in idx); ids = torch.zeros(len(idx), L, dtype=torch.long); att = torch.zeros(len(idx), L, dtype=torch.long); masks = []
            for j, i in enumerate(idx):
                e = enc[i]; ids[j, :len(e)] = torch.tensor(e); att[j, :len(e)] = 1; el = list(range(1, len(e) - 1)); m = rng.sample(el, max(1, int(round(cfg["mask"] * len(el))))) if len(el) > 1 else el; masks.append(m)
                ids[j, m] = 4
            cur = ids.clone()
            for r in range(cfg["rounds"]):
                logits = model(cur, attention_mask=att)
                if isinstance(logits, tuple): logits = logits[0]
                for j, m in enumerate(masks):
                    lg = logits[j, m] / cfg["temp"]; lg[:, :5] = -1e9
                    pr = F.softmax(lg, -1) if not shuffle_logits else (mv / mv.sum())[None].expand(len(m), -1)
                    cur[j, m] = torch.multinomial(pr, 1, generator=gen)[:, 0]
                if r + 1 < cfg["rounds"]:
                    for j, m in enumerate(masks):
                        re = rng.sample(m, max(1, len(m) // 2)); cur[j, re] = 4
            for j, i in enumerate(idx): out[i] = _detok(tok, cur[j, :len(enc[i])].tolist())
    return out


_CF = {}


def gen_chemfm(seeds, n, rng, cfg):
    import torch
    from transformers import AutoTokenizer, AutoModelForCausalLM
    if "m" not in _CF:
        d = os.environ["CHEMFM_DIR"]; _CF["tok"] = AutoTokenizer.from_pretrained(d); _CF["m"] = AutoModelForCausalLM.from_pretrained(d, torch_dtype=torch.float32).eval()
    tok, model = _CF["tok"], _CF["m"]; torch.manual_seed(rng.randrange(1 << 30)); groups = collections.defaultdict(list); step = 8
    for i in range(n):
        s = rng.choice(seeds); ids = tok(s, add_special_tokens=True)["input_ids"]
        body = ids[1:-1] if (len(ids) > 2 and ids[-1] == tok.eos_token_id) else ids[1:]
        P = max(2, min(len(body) - 1, int(round(cfg["prefix"] * len(body))))); P = max(2, (P // step) * step) if P >= step else P
        groups[P].append((i, [ids[0]] + body[:P]))
    res = {}
    with torch.no_grad():
        for P, items in groups.items():
            for k in range(0, len(items), 64):
                ch = items[k:k + 64]; x = torch.tensor([e for _, e in ch]); o = model.generate(x, attention_mask=torch.ones_like(x), do_sample=True, temperature=cfg["temp"], top_k=0, top_p=1.0, max_new_tokens=min(300, 500 - x.shape[1]), eos_token_id=tok.eos_token_id, pad_token_id=tok.eos_token_id)
                for (i, _), row in zip(ch, o.tolist()): res[i] = tok.decode(row, skip_special_tokens=True).replace(" ", "")
    return [res.get(i, "") for i in range(n)]


GENS = {"S-EDIT": gen_edit, "S-LIB": gen_lib, "S-BRICS": gen_brics, "C-COPY": gen_copy, "L-P0": gen_p0, "L-CHEMFM": gen_chemfm, "L-PCLM2": gen_pclm2,
        "C-RANDINIT-P0": lambda s, n, r, c: gen_p0(s, n, r, c, random_init=True), "C-RANDINIT-PCLM2": lambda s, n, r, c: gen_pclm2(s, n, r, c, random_init=True), "C-SHUF-PCLM2": lambda s, n, r, c: gen_pclm2(s, n, r, c, shuffle_logits=True)}
GRIDS = {"S-EDIT": [dict(k=k) for k in (1, 2, 3)],
         "S-LIB": [dict(len=ln, p_nme=a, p_d=b) for ln in ((5, 8), (6, 10), (8, 12)) for a in (0.1, 0.25, 0.4) for b in (0.0, 0.15, 0.3)],
         "S-BRICS": [dict(nf=k) for k in (4, 8)], "C-COPY": [dict()],
         "L-P0": [dict(prefix=p, temp=t) for p in (0.3, 0.5, 0.7) for t in (0.8, 1.0)], "L-CHEMFM": [dict(prefix=p, temp=1.0) for p in (0.3, 0.5, 0.7)],
         "L-PCLM2": [dict(mask=m, rounds=r, temp=t) for m in (0.15, 0.30) for r in (1, 3) for t in (0.8, 1.0)]}
GRIDS["C-RANDINIT-P0"] = GRIDS["L-P0"][:1]; GRIDS["C-RANDINIT-PCLM2"] = GRIDS["L-PCLM2"][:1]; GRIDS["C-SHUF-PCLM2"] = GRIDS["L-PCLM2"][:1]


# ---------------------------------------------------------------------------------------------- drivers
def context():
    seen = load_cpm(); S, dev, test = split_data(seen); cpm_set = set(seen)
    ref = [Chem.MolFromSmiles(s) for s in test]; rn = [mol_stats(m) for m in ref if m is not None]
    return dict(S=S, seeds_set=set(S), cpm_set=cpm_set, ref_ring=[a for a, _ in rn], ref_nme=[b for _, b in rn], n_dev=len(dev), n_test=len(test))


def run_one(ctx, name, cfg, n, run_seed):
    rng = random.Random(run_seed * 7919 + 13); t0 = time.time(); raw = GENS[name](ctx["S"], n, rng, cfg); sec = time.time() - t0
    met, cons = evaluate(raw, ctx["seeds_set"], ctx["cpm_set"], ctx["ref_ring"], ctx["ref_nme"], random.Random(run_seed))
    met["seconds"] = round(sec, 1); return met, raw, cons


def cmd_dev(a):
    ctx = context(); os.makedirs(a.out, exist_ok=True); print("seeds", len(ctx["S"]), "dev/test peptides", ctx["n_dev"], ctx["n_test"], flush=True)
    for name in a.gens.split(","):
        fn = os.path.join(a.out, f"dev_{name}.json")
        if os.path.exists(fn): continue
        rows = []
        for cfg in GRIDS[name]:
            ys = []
            for rs in (100, 101, 102):
                met, _, _ = run_one(ctx, name, cfg, a.n_dev, rs); ys.append(met["Y"]); print(name, cfg, rs, met, flush=True)
            rows.append(dict(cfg=cfg, Y_mean=round(float(np.mean(ys)), 3), Y=ys))
        best = max(rows, key=lambda r: r["Y_mean"]); json.dump(dict(gen=name, grid=rows, best=best["cfg"], n_dev=a.n_dev), open(fn, "w"), indent=1)


# amendment A1 (docs/20261031_GENERATION_PILOT3_PREREG.md section 9): one outward step per boundary parameter, other params at their best, DEV only
EXT = {"S-LIB": {"len": [(4, 6)], "p_nme": [0.55]}, "S-EDIT": {"k": [4, 5]}, "S-BRICS": {"nf": [2, 3]}, "L-P0": {"prefix": [0.85]}, "L-PCLM2": {"mask": [0.45], "rounds": [5], "temp": [1.2]}, "L-CHEMFM": {"prefix": [0.85]}}


def cmd_dev2(a):
    ctx = context(); os.makedirs(a.out, exist_ok=True)
    for name in a.gens.split(","):
        fn = os.path.join(a.out, f"dev2_{name}.json"); d1 = json.load(open(os.path.join(a.out, f"dev_{name}.json")))
        if os.path.exists(fn): continue
        best = d1["best"]; cells = []
        for par, vals in EXT[name].items():
            for v in vals:
                c = dict(best); c[par] = v; cells.append(c)
        rows = []
        for cfg in cells:
            ys = []
            for rs in (100, 101, 102):
                met, _, _ = run_one(ctx, name, cfg, a.n_dev, rs); ys.append(met["Y"]); print(name, cfg, rs, met, flush=True)
            rows.append(dict(cfg=cfg, Y_mean=round(float(np.mean(ys)), 3), Y=ys))
        allrows = d1["grid"] + rows; bestc = max(allrows, key=lambda r: r["Y_mean"])
        json.dump(dict(gen=name, ext_grid=rows, best=bestc["cfg"], best_Y_mean=bestc["Y_mean"], orig_best=best, n_dev=a.n_dev), open(fn, "w"), indent=1)


def ci_t(v):
    v = np.asarray(v, float); n = len(v)
    if n < 2: return None
    from scipy import stats
    m = v.mean(); h = stats.t.ppf(0.975, n - 1) * v.std(ddof=1) / np.sqrt(n); return [round(float(m - h), 3), round(float(m + h), 3)]


def ci_boot(v, B=5000):
    v = np.asarray(v, float); r = np.random.default_rng(0); b = [r.choice(v, len(v)).mean() for _ in range(B)]; return [round(float(np.percentile(b, 2.5)), 3), round(float(np.percentile(b, 97.5)), 3)]


def cmd_test(a):
    ctx = context(); cfgs = json.load(open(a.cfg)); os.makedirs(a.out, exist_ok=True)
    for name in a.gens.split(","):
        fn = os.path.join(a.out, f"test_{name}.json")
        if os.path.exists(fn): continue
        cfg = cfgs[name]; runs = []
        for rs in range(a.seeds):
            met, raw, cons = run_one(ctx, name, cfg, a.n_test, rs); runs.append(met); print(name, rs, met, flush=True)
            with gzip.open(os.path.join(a.out, f"raw_{name}_{rs}.smi.gz"), "wt") as fh: fh.write("\n".join(raw))
        summ = {}
        for k in ("validity", "uniqueness_of_valid", "novelty_of_unique", "macro_fraction", "ring_TV", "nme_TV", "mean_nme", "Y", "Y_cluster", "internal_diversity"):
            v = [r[k] for r in runs if r.get(k) is not None]
            if v: summ[k] = dict(mean=round(float(np.mean(v)), 4), t_interval=ci_t(v), percentile_bootstrap=ci_boot(v), per_seed=v)
        json.dump(dict(gen=name, cfg=cfg, runs=runs, summary=summ), open(fn, "w"), indent=1)


def selftest():
    ctx = context(); print("seeds", len(ctx["S"]), "ref", len(ctx["ref_ring"]), flush=True); rng = random.Random(0)
    for name, cfg in (("C-COPY", {}), ("S-EDIT", dict(k=2)), ("S-LIB", dict(len=(6, 10), p_nme=0.25, p_d=0.15)), ("S-BRICS", dict(nf=6))):
        met, raw, cons = run_one(ctx, name, cfg, 50, 1); print(name, met, flush=True)
    # decode round trip for the P0 / PClm tokenisers when available
    if os.environ.get("P0_CKPT"):
        met, raw, cons = run_one(ctx, "L-P0", dict(prefix=0.5, temp=1.0), 20, 1); print("L-P0", met, raw[:2], flush=True)
    if os.environ.get("PCLM2_DIR"):
        model, tok = _pclm(); s = ctx["S"][0]; print("pclm roundtrip", _detok(tok, tok.encode(s)) == s)
        met, raw, cons = run_one(ctx, "L-PCLM2", dict(mask=0.15, rounds=1, temp=1.0), 20, 1); print("L-PCLM2", met, raw[:2], flush=True)


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("mode"); ap.add_argument("out", nargs="?"); ap.add_argument("--gens", default=""); ap.add_argument("--cfg", default=""); ap.add_argument("--n-dev", type=int, default=300)
    ap.add_argument("--n-test", type=int, default=1000); ap.add_argument("--seeds", type=int, default=5); a = ap.parse_args()
    {"selftest": lambda: selftest(), "dev": lambda: cmd_dev(a), "dev2": lambda: cmd_dev2(a), "test": lambda: cmd_test(a)}[a.mode]()
