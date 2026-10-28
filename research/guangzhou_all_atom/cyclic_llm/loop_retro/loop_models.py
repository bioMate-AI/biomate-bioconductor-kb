"""Model backends for the L7a model-comparison replay (PREREG_LOOP.md amendment L7a).
One contract for every learner:  state = B.init_state();  state = B.fit(state, idx, y, steps, seed);  scores = B.predict(state, idx).
fit() never mutates its input state (returns a new one); torch backends warm-start from the given state; the GBM backend refits from scratch (documented: for it one_shot == final loop model).
Backends: GBM (L5 `fp` learner), AtomLMReg (allatom/pretrain ckpt), ChemBERTaReg (DeepChem/ChemBERTa-77M-MLM). v4 goes through v4_eval/loop_model.py (see run_l7a.py)."""
import os, sys, copy, json
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)


class GBM:
    name = "gbm"
    def __init__(self, X): self.X = X
    def init_state(self): return None
    def fit(self, state, idx, y, steps, seed):
        import run_loop as R
        rng = np.random.default_rng(seed); idx = np.asarray(idx, dtype=int)
        assert len(idx) == len(y), f"GBM.fit: {len(idx)} indices but {len(y)} labels"
        if len(idx) == 0: return []                      # k = 0 labels (learning-curve origin): untrained -> constant, uninformative scores
        return R.fit_ens(self.X[idx], np.asarray(y, float), rng)
    def predict(self, state, idx):
        idx = np.asarray(idx, dtype=int)
        if not state: return np.zeros(len(idx))
        return np.mean([m.predict(self.X[idx]) for m in state], 0)
    def predict_std(self, state, idx):                  # ensemble standard deviation: the only native uncertainty among the backends (calibration analysis, dimension 8)
        idx = np.asarray(idx, dtype=int)
        if not state: return np.zeros(len(idx))
        return np.std([m.predict(self.X[idx]) for m in state], 0)


LORA_TARGETS = ("query", "key", "value", "q_proj", "k_proj", "v_proj", "o_proj", "out_proj", "dense", "qkv", "proj", "fc1", "fc2")


def add_lora(module, r=8, alpha=16, targets=LORA_TARGETS):
    """Minimal LoRA (no peft dependency): every nn.Linear whose name ends with a target gets a frozen base weight plus a trainable low-rank update B@A (A: r x in, B: out x r, B zero-initialised, scale alpha/r).
    The caller freezes everything else. Returns the number of wrapped layers."""
    import torch
    class LoRALinear(torch.nn.Module):
        def __init__(s, base):
            super().__init__(); s.base = base; s.lora_A = torch.nn.Parameter(torch.randn(r, base.in_features) / (base.in_features ** 0.5)); s.lora_B = torch.nn.Parameter(torch.zeros(base.out_features, r)); s.scale = alpha / r
            for q in s.base.parameters(): q.requires_grad_(False)
        def forward(s, x): return s.base(x) + (x @ s.lora_A.t() @ s.lora_B.t()) * s.scale
    n = 0
    for name, child in list(module.named_modules()):
        for cname, c in list(child.named_children()):
            if isinstance(c, torch.nn.Linear) and cname.split(".")[-1] in targets: setattr(child, cname, LoRALinear(c)); n += 1
    return n


class _TorchReg:
    """Shared fine-tune/predict for an encoder returning a pooled vector; subclasses build `self.enc_factory`, `self.encode`, `self.collate`.
    Cost counters (L7g): padded tokens processed in fit / predict, parameters total / trainable."""
    lr_bb, lr_head, lr_lora, batch = 5e-5, 1e-3, 3e-4, 32
    lora = False; tok_train = 0; tok_inf = 0
    def __init__(self, device="cpu", desc=None):
        import torch; self.torch = torch; self.dev = device
        self.desc = None if desc is None else np.asarray(desc, np.float32)      # L7f physchem channel: label-free descriptors (z-scored over the data), concatenated to the pooled hidden state
    def init_state(self):
        torch = self.torch; torch.manual_seed(0)
        m = self.build().to(self.dev); return m.eval()
    def fit(self, state, idx, y, steps, seed):
        torch = self.torch; new = copy.deepcopy(state); idx = np.asarray(idx); y = np.asarray(y, np.float32)
        if len(idx) < 2 or steps <= 0: return new
        torch.manual_seed(int(seed)); rng = np.random.default_rng(seed); new.train()
        hp = [p for n, p in new.named_parameters() if n.startswith("head") and p.requires_grad]
        lo = [p for n, p in new.named_parameters() if "lora_" in n and p.requires_grad]
        bb = [p for n, p in new.named_parameters() if not n.startswith("head") and "lora_" not in n and p.requires_grad]
        groups = [{"params": hp, "lr": self.lr_head}] + ([{"params": lo, "lr": self.lr_lora}] if lo else []) + ([{"params": bb, "lr": self.lr_bb}] if bb else [])
        opt = torch.optim.AdamW(groups, weight_decay=0.0)
        for _ in range(steps):
            sel = rng.choice(len(idx), min(self.batch, len(idx)), replace=len(idx) < self.batch)
            xb = self.collate(idx[sel]); yb = torch.tensor(y[sel], device=self.dev); self.tok_train += int(xb[0].numel())
            loss = torch.nn.functional.mse_loss(new(*xb).squeeze(-1), yb)
            opt.zero_grad(); loss.backward(); torch.nn.utils.clip_grad_norm_(new.parameters(), 1.0); opt.step()
        return new.eval()
    def predict(self, state, idx):
        torch = self.torch; idx = np.asarray(idx); out = np.zeros(len(idx), np.float64)
        order = np.argsort([self.length[i] for i in idx], kind="stable")
        with torch.no_grad():
            for s in range(0, len(idx), 128):
                b = order[s:s + 128]; xb = self.collate(idx[b]); self.tok_inf += int(xb[0].numel()); out[b] = state(*xb).squeeze(-1).float().cpu().numpy()
        return out
    def cost_info(self, state=None):
        """Parameters and token counters; FLOPs ~ 6*P*tokens (full fine-tune) or 4*P_total + 6*P_trainable per token (LoRA: backward still flows through the frozen weights); inference 2*P*tokens."""
        m = state if state is not None else self.init_state(); tot = sum(p.numel() for p in m.parameters()); tr = sum(p.numel() for p in m.parameters() if p.requires_grad)
        fl_train = (4 * tot + 6 * tr) * self.tok_train if self.lora else 6 * tot * self.tok_train
        return dict(params_total=int(tot), params_trainable=int(tr), tokens_train=int(self.tok_train), tokens_inference=int(self.tok_inf), flops_train=float(fl_train), flops_inference=float(2 * tot * self.tok_inf), lora=bool(self.lora))


class AtomLMReg(_TorchReg):
    name = "atom_lm"; heads = 8        # pretrain.py default (heads do not change parameter shapes; strict load cannot detect a wrong value, see test)
    def __init__(self, smiles, ckpt, vocab_json, device="cpu", desc=None):
        super().__init__(device, desc)
        sys.path.insert(0, os.path.join(HERE, "..", "allatom")); import atom_lm as A; self.A = A
        toks = json.load(open(vocab_json)); self.voc = A.Vocab(toks[4:]); self.ckpt = ckpt
        self.ids = [self.voc.encode(s) for s in smiles]; self.length = [len(x) for x in self.ids]
        assert max(self.length) <= 256, "SMILES longer than the atom LM context"
    def build(self):
        torch = self.torch; A = self.A; ck = torch.load(self.ckpt, map_location="cpu", weights_only=False)
        sd = ck["model"] if isinstance(ck, dict) and "model" in ck else ck
        d = sd["tok.weight"].shape[1]; layers = len({k.split(".")[1] for k in sd if k.startswith("blocks.")}); max_len = sd["pos.weight"].shape[0]
        gpt = A.GPT(len(self.voc), d=d, layers=layers, heads=self.heads, max_len=max_len); gpt.load_state_dict(sd, strict=True)   # architecture read from the checkpoint, never assumed
        nd = 0 if self.desc is None else self.desc.shape[1]
        class Reg(torch.nn.Module):
            def __init__(s, g):
                super().__init__(); s.g = g; s.head = torch.nn.Linear(g.ln.normalized_shape[0] + nd, 1)
                torch.nn.init.zeros_(s.head.weight); torch.nn.init.zeros_(s.head.bias)
            def forward(s, x, mask, dsc=None):
                g = s.g; h = g.tok(x) + g.pos(torch.arange(x.shape[1], device=x.device))[None]
                for b in g.blocks: h = b(h)
                h = g.ln(h); m = mask.unsqueeze(-1).to(h.dtype); v = (h * m).sum(1) / m.sum(1)
                return s.head(v if dsc is None else torch.cat([v, dsc], -1))
        return Reg(gpt)
    def collate(self, idx):
        torch = self.torch; L = max(self.length[i] for i in idx); x = torch.full((len(idx), L), self.A.PAD, dtype=torch.long)
        for j, i in enumerate(idx): x[j, :self.length[i]] = torch.tensor(self.ids[i])
        x = x.to(self.dev); out = (x, (x != self.A.PAD))
        return out if self.desc is None else out + (torch.tensor(self.desc[np.asarray(idx)], device=self.dev),)


class HFReg(_TorchReg):
    """Generic Hugging Face encoder regressor (SMILES tokenizer from the same repo): pooled last hidden state (+ optional physchem channel) -> linear head. lora=True freezes the backbone and trains LoRA adapters + head."""
    name = "hf"
    def __init__(self, smiles, model_id, device="cpu", desc=None, lora=False, trust_remote_code=False, max_length=512):
        super().__init__(device, desc); self.MODEL, self.lora, self.trc = model_id, lora, trust_remote_code
        from transformers import AutoTokenizer; self.tk = AutoTokenizer.from_pretrained(model_id, trust_remote_code=trust_remote_code)
        self.ids = [self.tk(s, truncation=True, max_length=max_length)["input_ids"] for s in smiles]; self.length = [len(x) for x in self.ids]
        self.n_truncated = int(sum(len(self.tk(s)["input_ids"]) > max_length for s in smiles)); self.pad_id = self.tk.pad_token_id if self.tk.pad_token_id is not None else 0
    def build(self):
        torch = self.torch; from transformers import AutoModel
        enc = AutoModel.from_pretrained(self.MODEL, trust_remote_code=self.trc); nd = 0 if self.desc is None else self.desc.shape[1]
        hid = getattr(enc.config, "hidden_size", None) or getattr(enc.config, "d_model", None) or getattr(enc.config, "n_embd")
        if self.lora:
            for q in enc.parameters(): q.requires_grad_(False)
            n = add_lora(enc); assert n > 0, "no Linear layer matched the LoRA targets"
        class Reg(torch.nn.Module):
            def __init__(s, e):
                super().__init__(); s.enc = e; s.head = torch.nn.Linear(hid + nd, 1)
                torch.nn.init.zeros_(s.head.weight); torch.nn.init.zeros_(s.head.bias)
            def forward(s, x, mask, dsc=None):
                h = s.enc(input_ids=x, attention_mask=mask.long()).last_hidden_state; m = mask.unsqueeze(-1).to(h.dtype); v = (h * m).sum(1) / m.sum(1)
                return s.head(v if dsc is None else torch.cat([v, dsc], -1))
        return Reg(enc)
    def collate(self, idx):
        torch = self.torch; L = max(self.length[i] for i in idx); x = torch.full((len(idx), L), self.pad_id, dtype=torch.long)
        for j, i in enumerate(idx): x[j, :self.length[i]] = torch.tensor(self.ids[i])
        x = x.to(self.dev); out = (x, (x != self.pad_id))
        return out if self.desc is None else out + (torch.tensor(self.desc[np.asarray(idx)], device=self.dev),)


class KNN:
    """Nearest-neighbour baseline (L7g): mean label of the k=5 most cosine-similar REVEALED peptides (feature = chirality-aware Morgan count vector); refit = store the revealed set. k = 0 labels -> constant 0."""
    name = "knn"
    def __init__(self, X, k=5):
        X = np.asarray(X, np.float32); n = np.linalg.norm(X, axis=1, keepdims=True); self.Xn = X / np.where(n > 0, n, 1.0); self.k = k
    def init_state(self): return None
    def fit(self, state, idx, y, steps, seed):
        idx = np.asarray(idx, dtype=int); assert len(idx) == len(y), f"KNN.fit: {len(idx)} indices but {len(y)} labels"
        return (idx, np.asarray(y, float)) if len(idx) else None
    def predict(self, state, idx):
        idx = np.asarray(idx, dtype=int)
        if state is None: return np.zeros(len(idx))
        ri, ry = state; S = self.Xn[idx] @ self.Xn[ri].T; k = min(self.k, S.shape[1]); top = np.argpartition(-S, k - 1, axis=1)[:, :k]
        return ry[top].mean(1)


class ChemBERTaReg(_TorchReg):
    name = "chemberta"
    MODEL = "DeepChem/ChemBERTa-77M-MLM"
    def __init__(self, smiles, device="cpu", desc=None):
        super().__init__(device, desc)
        from transformers import AutoTokenizer; self.tk = AutoTokenizer.from_pretrained(self.MODEL)
        self.ids = [self.tk(s, truncation=True, max_length=512)["input_ids"] for s in smiles]; self.length = [len(x) for x in self.ids]
        self.n_truncated = int(sum(len(self.tk(s)["input_ids"]) > 512 for s in smiles))
    def build(self):
        torch = self.torch; from transformers import AutoModel
        enc = AutoModel.from_pretrained(self.MODEL); nd = 0 if self.desc is None else self.desc.shape[1]
        class Reg(torch.nn.Module):
            def __init__(s, e):
                super().__init__(); s.enc = e; s.head = torch.nn.Linear(e.config.hidden_size + nd, 1)
                torch.nn.init.zeros_(s.head.weight); torch.nn.init.zeros_(s.head.bias)
            def forward(s, x, mask, dsc=None):
                h = s.enc(input_ids=x, attention_mask=mask.long()).last_hidden_state; m = mask.unsqueeze(-1).to(h.dtype); v = (h * m).sum(1) / m.sum(1)
                return s.head(v if dsc is None else torch.cat([v, dsc], -1))
        return Reg(enc)
    def collate(self, idx):
        torch = self.torch; L = max(self.length[i] for i in idx); pad = self.tk.pad_token_id; x = torch.full((len(idx), L), pad, dtype=torch.long)
        for j, i in enumerate(idx): x[j, :self.length[i]] = torch.tensor(self.ids[i])
        x = x.to(self.dev); out = (x, (x != pad))
        return out if self.desc is None else out + (torch.tensor(self.desc[np.asarray(idx)], device=self.dev),)
