"""AtomLoopModel: the same LoopModel contract (score / update / fingerprint / cost) over the atom-level SMILES LM (allatom/atom_lm.py; also the v5 backbone).
score(smiles, target_seq) = mean per-token log-likelihood (UNCONDITIONED: target_seq is accepted for interface parity and ignored - stated in the paper; v5 adds target conditioning).
update(): pairwise ranking on within-target pairs (label higher = better) over the same score; modes frozen / finetune_ranking / one_shot_matched (dpo = ranking against the frozen previous-round reference)."""
import os, sys, copy, hashlib, json, time
import numpy as np, torch
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, "..", "allatom"))
import atom_lm as A
from loop_model import CostMeter, MODES


class AtomLoopModel:
    def __init__(self, model, vocab, device="cpu", history=(), meter=None):
        self.model, self.vocab, self.dev, self.history = model.to(device).eval(), vocab, device, tuple(history)
        self.max_len = model.max_len; self.meter = meter or CostMeter(sum(p.numel() for p in model.parameters()))

    @classmethod
    def from_checkpoint(cls, ckpt, vocab_json, device="cpu", d=512, layers=8, heads=8, max_len=256):
        itos = json.load(open(vocab_json)); vocab = A.Vocab(itos[4:]) if itos[:4] == ["<pad>", "<bos>", "<eos>", "<unk>"] else A.Vocab(itos)
        m = A.GPT(len(vocab), d=d, layers=layers, heads=heads, max_len=max_len); m.load_state_dict(torch.load(ckpt, map_location="cpu", weights_only=False)["model"])
        return cls(m, vocab, device)

    def _ids(self, smi):
        try: ids = self.vocab.encode(smi)
        except AssertionError: return None
        return ids if len(ids) <= self.max_len else None

    def _mean_logp(self, id_lists, grad=False):
        mx = max(len(x) for x in id_lists); X = torch.full((len(id_lists), mx), A.PAD, dtype=torch.long)
        for j, s in enumerate(id_lists): X[j, :len(s)] = torch.tensor(s)
        X = X.to(self.dev)
        with torch.set_grad_enabled(grad):
            lp = torch.log_softmax(self.model(X)[:, :-1], -1).gather(2, X[:, 1:, None])[:, :, 0]; mask = (X[:, 1:] != A.PAD).float()
            return (lp * mask).sum(1) / mask.sum(1).clamp(min=1)

    def score(self, smiles, target_seq=None):
        t0 = time.time(); res = [None] * len(smiles); ok = [(i, self._ids(s)) for i, s in enumerate(smiles)]; ok = [(i, x) for i, x in ok if x is not None]
        for k in range(0, len(ok), 64):
            ch = ok[k:k + 64]; self.meter.score_tokens += sum(len(x) for _, x in ch)
            for (i, _), v in zip(ch, self._mean_logp([x for _, x in ch])): res[i] = float(v)
        self.meter.score_seconds += time.time() - t0; return res

    def fingerprint(self):
        h = hashlib.sha256()
        for k, v in sorted(self.model.state_dict().items()): h.update(k.encode()); h.update(v.detach().cpu().numpy().tobytes())
        h.update(json.dumps(self.history).encode()); return h.hexdigest()[:16]

    def update(self, labelled, mode="finetune_ranking", seed=0, steps=60, lr=1e-4, beta=20.0, pairs_per_step=32, rounds=1):
        """labelled: [{smiles, target_seq, label}]; same budget semantics as LoopModel.update_tokens (one_shot_matched: steps*rounds in one update)."""
        assert mode in MODES, mode
        t_upd = time.time(); eff = "finetune_ranking" if mode == "one_shot_matched" else mode
        if mode == "one_shot_matched": steps = steps * max(1, int(rounds))
        new = AtomLoopModel(copy.deepcopy(self.model), self.vocab, self.dev, self.history + ((mode, len(labelled), seed, rounds),), copy.deepcopy(self.meter))
        rows = [(r.get("target_seq"), self._ids(r["smiles"]), r["label"]) for r in labelled]; rows = [r for r in rows if r[1] is not None]
        by = {}
        for t, ids, y in rows: by.setdefault(t, []).append((ids, y))
        pairs = [(a[0], b[0]) for rs in by.values() for a in rs for b in rs if a[1] > b[1]]
        if eff == "frozen" or not pairs: new.meter.updates += 1; return new
        ref = AtomLoopModel(copy.deepcopy(self.model), self.vocab, self.dev) if eff == "dpo" else None
        torch.manual_seed(int(seed)); rng = np.random.default_rng(seed); new.model.train(); opt = torch.optim.AdamW(new.model.parameters(), lr=lr, weight_decay=0.0)
        for _ in range(steps):
            idx = rng.choice(len(pairs), min(pairs_per_step, len(pairs)), replace=False); w = [pairs[k][0] for k in idx]; l = [pairs[k][1] for k in idx]
            d = new._mean_logp(w, True) - new._mean_logp(l, True)
            if ref is not None:
                with torch.no_grad(): d = d - (ref._mean_logp(w) - ref._mean_logp(l))
            loss = -torch.nn.functional.logsigmoid(beta * d).mean(); opt.zero_grad(); loss.backward(); torch.nn.utils.clip_grad_norm_(new.model.parameters(), 1.0); opt.step()
            new.meter.train_tokens += sum(len(x) for x in w + l) * (2 if eff == "dpo" else 1)
        new.model.eval(); new.meter.update_seconds += time.time() - t_upd; new.meter.updates += 1; return new

    def cost(self, usd_per_hour=None):
        from loop_model import USD_PER_GPU_HOUR
        return self.meter.report(usd_per_hour if usd_per_hour is not None else USD_PER_GPU_HOUR)
