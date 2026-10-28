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


class _TorchReg:
    """Shared fine-tune/predict for an encoder returning a pooled vector; subclasses build `self.enc_factory`, `self.encode`, `self.collate`."""
    lr_bb, lr_head, batch = 5e-5, 1e-3, 32
    def __init__(self, device="cpu"):
        import torch; self.torch = torch; self.dev = device
    def init_state(self):
        torch = self.torch; torch.manual_seed(0)
        m = self.build().to(self.dev); return m.eval()
    def fit(self, state, idx, y, steps, seed):
        torch = self.torch; new = copy.deepcopy(state); idx = np.asarray(idx); y = np.asarray(y, np.float32)
        if len(idx) < 2 or steps <= 0: return new
        torch.manual_seed(int(seed)); rng = np.random.default_rng(seed); new.train()
        hp = [p for n, p in new.named_parameters() if n.startswith("head")]; bb = [p for n, p in new.named_parameters() if not n.startswith("head")]
        opt = torch.optim.AdamW([{"params": bb, "lr": self.lr_bb}, {"params": hp, "lr": self.lr_head}], weight_decay=0.0)
        for _ in range(steps):
            sel = rng.choice(len(idx), min(self.batch, len(idx)), replace=len(idx) < self.batch)
            xb = self.collate(idx[sel]); yb = torch.tensor(y[sel], device=self.dev)
            loss = torch.nn.functional.mse_loss(new(*xb).squeeze(-1), yb)
            opt.zero_grad(); loss.backward(); torch.nn.utils.clip_grad_norm_(new.parameters(), 1.0); opt.step()
        return new.eval()
    def predict(self, state, idx):
        torch = self.torch; idx = np.asarray(idx); out = np.zeros(len(idx), np.float64)
        order = np.argsort([self.length[i] for i in idx], kind="stable")
        with torch.no_grad():
            for s in range(0, len(idx), 128):
                b = order[s:s + 128]; out[b] = state(*self.collate(idx[b])).squeeze(-1).float().cpu().numpy()
        return out


class AtomLMReg(_TorchReg):
    name = "atom_lm"; heads = 8        # pretrain.py default (heads do not change parameter shapes; strict load cannot detect a wrong value, see test)
    def __init__(self, smiles, ckpt, vocab_json, device="cpu"):
        super().__init__(device)
        sys.path.insert(0, os.path.join(HERE, "..", "allatom")); import atom_lm as A; self.A = A
        toks = json.load(open(vocab_json)); self.voc = A.Vocab(toks[4:]); self.ckpt = ckpt
        self.ids = [self.voc.encode(s) for s in smiles]; self.length = [len(x) for x in self.ids]
        assert max(self.length) <= 256, "SMILES longer than the atom LM context"
    def build(self):
        torch = self.torch; A = self.A; ck = torch.load(self.ckpt, map_location="cpu", weights_only=False)
        sd = ck["model"] if isinstance(ck, dict) and "model" in ck else ck
        d = sd["tok.weight"].shape[1]; layers = len({k.split(".")[1] for k in sd if k.startswith("blocks.")}); max_len = sd["pos.weight"].shape[0]
        gpt = A.GPT(len(self.voc), d=d, layers=layers, heads=self.heads, max_len=max_len); gpt.load_state_dict(sd, strict=True)   # architecture read from the checkpoint, never assumed
        class Reg(torch.nn.Module):
            def __init__(s, g):
                super().__init__(); s.g = g; s.head = torch.nn.Linear(g.ln.normalized_shape[0], 1)
                torch.nn.init.zeros_(s.head.weight); torch.nn.init.zeros_(s.head.bias)
            def forward(s, x, mask):
                g = s.g; h = g.tok(x) + g.pos(torch.arange(x.shape[1], device=x.device))[None]
                for b in g.blocks: h = b(h)
                h = g.ln(h); m = mask.unsqueeze(-1).to(h.dtype)
                return s.head((h * m).sum(1) / m.sum(1))
        return Reg(gpt)
    def collate(self, idx):
        torch = self.torch; L = max(self.length[i] for i in idx); x = torch.full((len(idx), L), self.A.PAD, dtype=torch.long)
        for j, i in enumerate(idx): x[j, :self.length[i]] = torch.tensor(self.ids[i])
        x = x.to(self.dev); return x, (x != self.A.PAD)


class ChemBERTaReg(_TorchReg):
    name = "chemberta"
    MODEL = "DeepChem/ChemBERTa-77M-MLM"
    def __init__(self, smiles, device="cpu"):
        super().__init__(device)
        from transformers import AutoTokenizer; self.tk = AutoTokenizer.from_pretrained(self.MODEL)
        self.ids = [self.tk(s, truncation=True, max_length=512)["input_ids"] for s in smiles]; self.length = [len(x) for x in self.ids]
        self.n_truncated = int(sum(len(self.tk(s)["input_ids"]) > 512 for s in smiles))
    def build(self):
        torch = self.torch; from transformers import AutoModel
        enc = AutoModel.from_pretrained(self.MODEL)
        class Reg(torch.nn.Module):
            def __init__(s, e):
                super().__init__(); s.enc = e; s.head = torch.nn.Linear(e.config.hidden_size, 1)
                torch.nn.init.zeros_(s.head.weight); torch.nn.init.zeros_(s.head.bias)
            def forward(s, x, mask):
                h = s.enc(input_ids=x, attention_mask=mask.long()).last_hidden_state; m = mask.unsqueeze(-1).to(h.dtype)
                return s.head((h * m).sum(1) / m.sum(1))
        return Reg(enc)
    def collate(self, idx):
        torch = self.torch; L = max(self.length[i] for i in idx); pad = self.tk.pad_token_id; x = torch.full((len(idx), L), pad, dtype=torch.long)
        for j, i in enumerate(idx): x[j, :self.length[i]] = torch.tensor(self.ids[i])
        x = x.to(self.dev); return x, (x != pad)
