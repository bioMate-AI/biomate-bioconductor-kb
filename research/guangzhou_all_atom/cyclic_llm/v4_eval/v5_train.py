"""v5 trainer (docs/20261028_V5_PREREG_AND_LOOP_INTERFACE.md C1, C3, C4, C6; per-fold filter V5-A3).
Atom-level SMILES decoder (allatom/atom_lm.py style: pre-LN blocks, fused causal SDPA, tied head, no dropout -> deterministic) with
  C1  TARGET CROSS-ATTENTION: every block cross-attends from peptide tokens to a per-target memory (residue-level embeddings of the target, e.g. frozen protein-LM embeddings,
      projected to d); a learned NULL memory is used when no target is given (general/pretraining data).
  C3  affinity head on masked mean-pooled hidden states with a CENSORING-AWARE (Tobit) Gaussian likelihood for '=' / '<' / '>' relations (on pAct = -log10(M); '<' on affinity means pAct >= y)
      + WITHIN-TARGET PAIRWISE RANKING loss with hard-negative mining (each better compound vs the highest-scoring worse compound of the same target).
  C4/C6 topology tokens + chirality-preserving atom tokens come from v5_atom_tokens.encode (vocabulary = atom vocab + TOPO_TOKENS).
Batches are a pure function of (seed, step): a resumed run is bitwise identical to an uninterrupted one.
The per-fold filter is enforced by `assert_fold_clean` (no training compound may share a flat structure with, or be Tanimoto >= 0.9 to, a held-out compound)."""
import os, sys, math, json, hashlib
import numpy as np, torch, torch.nn as nn, torch.nn.functional as F
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, "..", "allatom"))
import atom_lm as A

PAD = A.PAD


class Block(nn.Module):
    def __init__(self, d, heads):
        super().__init__(); self.h = heads
        self.ln1 = nn.LayerNorm(d); self.qkv = nn.Linear(d, 3 * d); self.proj = nn.Linear(d, d)
        self.lnc = nn.LayerNorm(d); self.q = nn.Linear(d, d); self.kv = nn.Linear(d, 2 * d); self.cproj = nn.Linear(d, d)
        self.ln2 = nn.LayerNorm(d); self.mlp = nn.Sequential(nn.Linear(d, 4 * d), nn.GELU(), nn.Linear(4 * d, d))

    def forward(self, x, mem, mem_mask):
        B, T, D = x.shape; h = self.h
        q, k, v = self.qkv(self.ln1(x)).view(B, T, 3, h, D // h).permute(2, 0, 3, 1, 4)
        x = x + self.proj(F.scaled_dot_product_attention(q, k, v, is_causal=True).transpose(1, 2).reshape(B, T, D))
        qc = self.q(self.lnc(x)).view(B, T, h, D // h).transpose(1, 2); kc, vc = self.kv(mem).view(B, mem.shape[1], 2, h, D // h).permute(2, 0, 3, 1, 4)
        am = mem_mask[:, None, None, :]                       # (B,1,1,M) True = attend
        x = x + self.cproj(F.scaled_dot_product_attention(qc, kc, vc, attn_mask=am).transpose(1, 2).reshape(B, T, D))
        return x + self.mlp(self.ln2(x))


class V5Model(nn.Module):
    def __init__(self, vocab, d=256, layers=6, heads=8, max_len=512, target_dim=1280):
        super().__init__(); self.max_len = max_len; self.d = d
        self.tok = nn.Embedding(vocab, d); self.pos = nn.Embedding(max_len, d); self.blocks = nn.ModuleList([Block(d, heads) for _ in range(layers)])
        self.ln = nn.LayerNorm(d); self.head = nn.Linear(d, vocab, bias=False); self.head.weight = self.tok.weight
        self.tproj = nn.Sequential(nn.Linear(target_dim, d), nn.GELU(), nn.Linear(d, d)); self.null_mem = nn.Parameter(torch.zeros(1, 1, d)); self.target_dim = target_dim
        self.aff = nn.Linear(d, 1); self.log_sigma = nn.Parameter(torch.zeros(()))

    def memory(self, tmem, tmask, B, device):
        """tmem: (B,M,target_dim) or None; tmask (B,M) bool. Rows with no target (all-False mask) use the learned null memory."""
        if tmem is None: return self.null_mem.expand(B, 1, self.d).to(device), torch.ones(B, 1, dtype=torch.bool, device=device)
        m = self.tproj(tmem); has = tmask.any(1)
        m = torch.cat([self.null_mem.expand(B, 1, self.d), m], 1); mask = torch.cat([~has[:, None], tmask], 1)   # null slot attendable only when the row has no target
        return m, mask

    def forward(self, x, tmem=None, tmask=None):
        B, T = x.shape; mem, mm = self.memory(tmem, tmask, B, x.device)
        h = self.tok(x) + self.pos(torch.arange(T, device=x.device))[None]
        for blk in self.blocks: h = blk(h, mem, mm)
        h = self.ln(h); return self.head(h), h

    def affinity(self, x, tmem, tmask):
        _, h = self(x, tmem, tmask); m = (x != PAD).float()[:, :, None]
        return self.aff((h * m).sum(1) / m.sum(1).clamp(min=1))[:, 0]


# --------------------------------------------------------------------------------------- losses
def tobit_nll(mu, log_sigma, y, rel):
    """y = pAct; rel in {0:'=', 1:'<' (affinity upper bound -> pAct >= y), 2:'>' (affinity lower bound -> pAct <= y)}. Gaussian N(mu, sigma^2)."""
    s = torch.exp(log_sigma).clamp(min=1e-3); z = (y - mu) / s
    exact = 0.5 * z ** 2 + torch.log(s) + 0.5 * math.log(2 * math.pi)
    right = -torch.log(0.5 * torch.erfc(z / math.sqrt(2)).clamp(min=1e-12))        # P(pAct >= y) = 1 - Phi(z)
    left = -torch.log((0.5 * torch.erfc(-z / math.sqrt(2))).clamp(min=1e-12))      # P(pAct <= y) = Phi(z)
    return torch.where(rel == 0, exact, torch.where(rel == 1, right, left))


def pairwise_hard_neg(mu, y, margin=0.0, beta=1.0):
    """Within ONE target: each compound i with a strictly lower-labelled compound is ranked against the HIGHEST-scoring lower-labelled compound (hard negative)."""
    d = y[:, None] - y[None, :] > margin                    # i better than j
    if not d.any(): return mu.new_zeros(())
    sc = mu[None, :].expand(len(mu), -1).masked_fill(~d, float("-inf")); jmax = sc.argmax(1); has = d.any(1)
    diff = mu[has] - mu[jmax[has]]; return -F.logsigmoid(beta * diff).mean()


# --------------------------------------------------------------------------------------- data
class V5Data:
    """rows: dict(ids list[int], target str|None, y float|None, rel int). targets: dict target -> np.ndarray (M, target_dim). Batches are pure functions of (seed, step)."""
    def __init__(self, rows, targets, target_dim):
        self.rows, self.targets, self.td = rows, targets, target_dim
        self.by_t = {}
        for i, r in enumerate(rows):
            if r["target"] is not None and r["y"] is not None: self.by_t.setdefault(r["target"], []).append(i)
        self.tkeys = sorted(k for k, v in self.by_t.items() if len(v) >= 2); self.lm_idx = [i for i, r in enumerate(rows) if r["y"] is None]

    def collate(self, idx, device="cpu"):
        rs = [self.rows[i] for i in idx]; mx = max(len(r["ids"]) for r in rs); X = torch.full((len(rs), mx), PAD, dtype=torch.long)
        for j, r in enumerate(rs): X[j, :len(r["ids"])] = torch.tensor(r["ids"])
        Mx = max([len(self.targets[r["target"]]) if r["target"] is not None else 0 for r in rs] + [1]); tm = torch.zeros(len(rs), Mx, self.td); mk = torch.zeros(len(rs), Mx, dtype=torch.bool)
        for j, r in enumerate(rs):
            if r["target"] is not None: t = torch.tensor(self.targets[r["target"]]); tm[j, :len(t)] = t; mk[j, :len(t)] = True
        y = torch.tensor([r["y"] if r["y"] is not None else 0.0 for r in rs], dtype=torch.float32); rel = torch.tensor([r["rel"] for r in rs])
        return X.to(device), tm.to(device), mk.to(device), y.to(device), rel.to(device)

    def affinity_batch(self, seed, step, bs):
        rng = np.random.default_rng([seed, step, 1]); t = self.tkeys[rng.integers(len(self.tkeys))]; pool = self.by_t[t]
        return list(rng.choice(pool, min(bs, len(pool)), replace=False))

    def lm_batch(self, seed, step, bs):
        rng = np.random.default_rng([seed, step, 2]); return list(rng.choice(self.lm_idx, min(bs, len(self.lm_idx)), replace=False)) if self.lm_idx else []


def step_loss(model, data, seed, step, bs=32, lm_w=1.0, aff_w=1.0, rank_w=1.0, lm_bs=32, device="cpu"):
    loss = 0.0; parts = {}
    if data.tkeys and (aff_w or rank_w):
        idx = data.affinity_batch(seed, step, bs); X, tm, mk, y, rel = data.collate(idx, device); mu = model.affinity(X, tm, mk)
        if aff_w: la = tobit_nll(mu, model.log_sigma, y, rel).mean(); loss = loss + aff_w * la; parts["tobit"] = float(la.detach())
        if rank_w: lr = pairwise_hard_neg(mu, y); loss = loss + rank_w * lr; parts["rank"] = float(lr.detach())
    if lm_w and data.lm_idx or lm_w and data.tkeys:
        idx = data.lm_batch(seed, step, lm_bs) or data.affinity_batch(seed, step, lm_bs); X, tm, mk, _, _ = data.collate(idx, device)
        lg, _ = model(X, tm, mk); ll = F.cross_entropy(lg[:, :-1].reshape(-1, lg.size(-1)), X[:, 1:].reshape(-1), ignore_index=PAD); loss = loss + lm_w * ll; parts["lm"] = float(ll.detach())
    return loss, parts


def train(model, data, steps, seed=0, lr=3e-4, ckpt=None, ckpt_every=0, resume=False, device="cpu", **kw):
    model.to(device).train(); opt = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=0.0); start = 0
    if resume and ckpt and os.path.exists(ckpt):
        st = torch.load(ckpt, map_location=device, weights_only=False); model.load_state_dict(st["model"]); opt.load_state_dict(st["opt"]); start = st["step"]
    for s in range(start, steps):
        loss, _ = step_loss(model, data, seed, s, device=device, **kw); opt.zero_grad(); loss.backward(); torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0); opt.step()
        if ckpt and ckpt_every and (s + 1) % ckpt_every == 0:
            tmp = ckpt + ".tmp"; torch.save({"model": model.state_dict(), "opt": opt.state_dict(), "step": s + 1}, tmp); os.replace(tmp, ckpt)
    model.eval(); return model


@torch.no_grad()
def predict(model, data, rows, device="cpu", bs=64):
    model.to(device).eval(); out = []
    for i in range(0, len(rows), bs):
        d2 = V5Data(rows[i:i + bs], data.targets, data.td); X, tm, mk, _, _ = d2.collate(list(range(len(d2.rows))), device); out += model.affinity(X, tm, mk).tolist()
    return out


# --------------------------------------------------------------------------------------- per-fold filter guard
def assert_fold_clean(train_smiles, heldout_smiles, tan=0.9):
    """Raises AssertionError listing offenders if any training molecule shares a flat structure with, or has Tanimoto >= tan to, a held-out molecule (exact, brute force; for audits and small sets)."""
    from rdkit import Chem, DataStructs
    from rdkit.Chem import rdFingerprintGenerator
    g = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=2048)
    def prep(s):
        m = Chem.MolFromSmiles(s); return (Chem.MolToSmiles(m, isomericSmiles=False), g.GetFingerprint(m)) if m is not None else None
    H = [p for p in map(prep, heldout_smiles) if p]; hflat = {p[0] for p in H}; hfp = [p[1] for p in H]; bad = []
    for s in train_smiles:
        p = prep(s)
        if p is None: continue
        if p[0] in hflat or (hfp and max(DataStructs.BulkTanimotoSimilarity(p[1], hfp)) >= tan): bad.append(s)
    assert not bad, f"{len(bad)} training molecules overlap held-out compounds, e.g. {bad[:3]}"
    return True
