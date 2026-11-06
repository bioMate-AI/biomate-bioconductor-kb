"""Atom-level (SMILES-token) language model for cyclic peptides (allatom/PREREG.md). Small GPT-style decoder, deterministic and resumable training, macrocycle upsampling.
Design notes: batches are a pure function of (seed, step) so a resumed run is bitwise identical to an uninterrupted one; checkpoints hold model + optimiser + step; no dropout (determinism)."""
import os, re, math
import numpy as np, torch, torch.nn as nn, torch.nn.functional as F

_SMI = re.compile(r"(\[[^\]]+]|Br?|Cl?|N|O|S|P|F|I|b|c|n|o|s|p|\(|\)|\.|=|#|-|\+|\\|\/|:|~|@|\?|>|\*|\$|\%[0-9]{2}|[0-9])")
PAD, BOS, EOS, UNK = 0, 1, 2, 3


def tokenize(smi):
    t = _SMI.findall(smi)
    assert "".join(t) == smi, f"tokenizer lost characters in {smi}"
    return t


class Vocab:
    def __init__(self, toks): self.itos = ["<pad>", "<bos>", "<eos>", "<unk>"] + list(toks); self.stoi = {t: i for i, t in enumerate(self.itos)}
    @classmethod
    def build(cls, smiles, max_vocab=None):
        c = {}
        for s in smiles:
            for t in tokenize(s): c[t] = c.get(t, 0) + 1
        toks = [t for t, _ in sorted(c.items(), key=lambda kv: (-kv[1], kv[0]))]
        return cls(toks[:max_vocab] if max_vocab else toks)
    def __len__(self): return len(self.itos)
    pad, bos, eos, unk = PAD, BOS, EOS, UNK
    def encode(self, smi): return [BOS] + [self.stoi.get(t, UNK) for t in tokenize(smi)] + [EOS]
    def decode(self, ids): return "".join(self.itos[i] for i in ids if i > UNK)


class Block(nn.Module):
    """Pre-LN transformer block with fused causal scaled-dot-product attention (flash / memory-efficient kernels when available)."""
    def __init__(self, d, heads):
        super().__init__(); self.heads = heads; self.ln1 = nn.LayerNorm(d); self.qkv = nn.Linear(d, 3 * d); self.proj = nn.Linear(d, d)
        self.ln2 = nn.LayerNorm(d); self.mlp = nn.Sequential(nn.Linear(d, 4 * d), nn.GELU(), nn.Linear(4 * d, d))
    def forward(self, x):
        B, T, D = x.shape; q, k, v = self.qkv(self.ln1(x)).view(B, T, 3, self.heads, D // self.heads).permute(2, 0, 3, 1, 4)
        x = x + self.proj(F.scaled_dot_product_attention(q, k, v, is_causal=True).transpose(1, 2).reshape(B, T, D)); return x + self.mlp(self.ln2(x))


class GPT(nn.Module):
    def __init__(self, vocab, d=256, layers=6, heads=8, max_len=256):
        super().__init__(); self.max_len = max_len; self.tok = nn.Embedding(vocab, d); self.pos = nn.Embedding(max_len, d)
        self.blocks = nn.ModuleList([Block(d, heads) for _ in range(layers)]); self.ln = nn.LayerNorm(d); self.head = nn.Linear(d, vocab, bias=False); self.head.weight = self.tok.weight
    def forward(self, x):
        h = self.tok(x) + self.pos(torch.arange(x.shape[1], device=x.device))[None]
        for blk in self.blocks: h = blk(h)
        return self.head(self.ln(h))


def has_macrocycle(smi, min_ring=12):
    from rdkit import Chem
    m = Chem.MolFromSmiles(smi); return bool(m is not None and any(len(r) >= min_ring for r in m.GetRingInfo().AtomRings()))


def sampling_weights(macro, upsample=1.0):
    w = 1.0 + (upsample - 1.0) * np.asarray(macro, float); return w / w.sum()


def batch_indices(n, batch_size, step, seed, weights=None):
    rng = np.random.default_rng(seed * 1_000_003 + step); return rng.choice(n, batch_size, p=weights)


_POOL = {}


def bucketed_indices(lengths, batch_size, step, seed, weights=None, pool_mult=32):
    """Length-bucketed batches that are still a pure function of (seed, step): draw a pool of pool_mult*batch_size indices for step//pool_mult, sort by length, split into pool_mult batches, return batch step % pool_mult. Cuts padding waste (random 128-batches of a skewed corpus waste ~3x)."""
    g = step // pool_mult; key = (len(lengths), batch_size, seed, g, pool_mult, id(weights))
    if key not in _POOL:
        if len(_POOL) > 4: _POOL.clear()
        rng = np.random.default_rng(seed * 1_000_003 + g); pool = rng.choice(len(lengths), pool_mult * batch_size, p=weights)
        _POOL[key] = pool[np.argsort(lengths[pool], kind="stable")].reshape(pool_mult, batch_size)
    return _POOL[key][step % pool_mult]


def collate(enc, idx, max_len, device):
    seqs = [enc[i][:max_len] for i in idx]; L = max(len(s) for s in seqs); x = torch.full((len(seqs), L), PAD, dtype=torch.long)
    for j, s in enumerate(seqs): x[j, :len(s)] = torch.tensor(s)
    return x.to(device)


def _loss(model, x):
    logits = model(x[:, :-1]); return F.cross_entropy(logits.reshape(-1, logits.shape[-1]), x[:, 1:].reshape(-1), ignore_index=PAD)


def train(model, enc, vocab, steps, batch_size, lr, seed=0, ckpt=None, ckpt_every=0, resume=False, device="cpu", weights=None, log_every=0, amp=False, on_ckpt=None, pool_mult=0, on_eval=None):
    model.to(device).train(); opt = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=0.01); start = 0
    use_amp = bool(amp and str(device).startswith("cuda")); amp_dtype = torch.bfloat16 if (use_amp and torch.cuda.is_bf16_supported()) else torch.float16       # T4 has no bf16 -> fp16 + loss scaling
    scaler = torch.amp.GradScaler("cuda", enabled=use_amp and amp_dtype == torch.float16)
    if resume and ckpt and os.path.exists(ckpt):
        s = torch.load(ckpt, map_location=device); model.load_state_dict(s["model"]); opt.load_state_dict(s["opt"]); start = s["step"]
    lengths = np.array([len(e) for e in enc]) if pool_mult else None; last_saved = None
    for step in range(start, steps):
        idx = bucketed_indices(lengths, batch_size, step, seed, weights, pool_mult) if pool_mult else batch_indices(len(enc), batch_size, step, seed, weights)
        x = collate(enc, idx, model.max_len, device)
        with torch.autocast(device_type="cuda", dtype=amp_dtype, enabled=use_amp): loss = _loss(model, x)
        opt.zero_grad(set_to_none=True); scaler.scale(loss).backward(); scaler.unscale_(opt); torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0); scaler.step(opt); scaler.update()
        if log_every and (step + 1) % log_every == 0: print(f"step {step+1} loss {loss.item():.4f}", flush=True)
        if ckpt and ckpt_every and (step + 1) % ckpt_every == 0:
            save(ckpt, model, opt, step + 1); last_saved = step + 1
            if on_ckpt: on_ckpt(ckpt, step + 1)
            if on_eval: on_eval(model, step + 1); model.train()
    if ckpt and last_saved != steps:
        save(ckpt, model, opt, steps)
        if on_ckpt: on_ckpt(ckpt, steps)
        if on_eval: on_eval(model, steps); model.train()
    return model


def save(path, model, opt, step):
    tmp = path + ".tmp"; torch.save({"model": model.state_dict(), "opt": opt.state_dict(), "step": step}, tmp); os.replace(tmp, path)


@torch.no_grad()
def eval_loss(model, enc, vocab, device="cpu", batch=64):
    model.to(device).eval(); tot = n = 0
    for i in range(0, len(enc), batch):
        x = collate(enc, list(range(i, min(i + batch, len(enc)))), model.max_len, device); l = _loss(model, x); k = (x[:, 1:] != PAD).sum().item(); tot += l.item() * k; n += k
    model.train(); return tot / n


@torch.no_grad()
def sample(model, vocab, n, max_len=200, temperature=1.0, seed=0, device="cpu"):
    model.to(device).eval(); g = torch.Generator(device="cpu").manual_seed(seed); x = torch.full((n, 1), BOS, dtype=torch.long, device=device); done = torch.zeros(n, dtype=torch.bool, device=device)
    for _ in range(min(max_len, model.max_len - 1)):
        p = F.softmax(model(x)[:, -1] / temperature, -1).cpu(); nxt = torch.multinomial(p, 1, generator=g).to(device)
        nxt[done] = PAD; x = torch.cat([x, nxt], 1); done |= nxt.squeeze(1) == EOS
        if done.all(): break
    model.train(); return [vocab.decode([t for t in row.tolist()[1:] if t not in (PAD,)][:next((i for i, t in enumerate(row.tolist()[1:]) if t == EOS), None)]) for row in x]


def valid(smi):
    from rdkit import Chem, RDLogger
    RDLogger.DisableLog("rdApp.*"); return bool(smi) and Chem.MolFromSmiles(smi) is not None
