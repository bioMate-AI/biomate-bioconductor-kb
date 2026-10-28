"""LoopModel: the model/update contract for the LLM-in-the-loop retrospective replay (docs/20261028_V5_PREREG_AND_LOOP_INTERFACE.md §6).
v4 backend (unified_cyclic_llm checkpoint). score() never imputes; update() returns a NEW model and never mutates the original.
Core works on monomer-token lists (score_tokens/update_tokens); SMILES wrappers go through the audited converter and mark unmapped compounds None."""
import os, sys, copy, hashlib, json
import numpy as np
import torch
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import unified_cyclic_llm as U
import smiles_to_monomers as S
from train_cyclic_llm_v3 import make_model, TFEAT_DIM, target_feature

MODES = ("finetune_ranking", "dpo", "frozen", "one_shot_matched")


class LoopModel:
    def __init__(self, model, toks, block, device="cpu", dictionary=None, history=()):
        self.model, self.toks, self.block, self.dev = model.to(device).eval(), toks, block, device
        self.stoi = {t: i for i, t in enumerate(toks)}; self.dictionary = dictionary if dictionary is not None else S.BASE
        self.history = tuple(history); self.pad = self.stoi[U.PAD]; self._tf = {}

    @classmethod
    def from_checkpoint(cls, path, device="cpu", dictionary=None):
        ck = torch.load(path, map_location="cpu", weights_only=False); a = ck["args"]
        m = make_model(len(ck["toks"]), TFEAT_DIM, d_model=a["d_model"], n_layer=a["n_layer"], n_head=a["n_head"], block=a["block"]); m.load_state_dict(ck["model"])
        return cls(m, ck["toks"], a["block"], device, dictionary)

    # ------------------------------------------------------------------ scoring
    def _tf_vec(self, seq):
        if seq not in self._tf: self._tf[seq] = torch.tensor(target_feature(seq).astype("float32"))
        return self._tf[seq]

    def _llr(self, token_lists, tf, grad=False):
        outs = []
        for eb in ("<e_hi>", "<e_lo>"):
            ids = [[self.stoi[eb], self.stoi["<p_na>"], self.stoi[U.BOS]] + [self.stoi[m] for m in t] + [self.stoi[U.EOS]] for t in token_lists]
            mx = max(len(x) for x in ids); X = torch.full((len(ids), mx), self.pad, dtype=torch.long)
            for j, s in enumerate(ids): X[j, :len(s)] = torch.tensor(s)
            TF = tf[None].repeat(len(ids), 1).to(self.dev); X = X.to(self.dev)
            with torch.set_grad_enabled(grad):
                lp = torch.log_softmax(self.model(X, TF), -1)[:, :mx]
                tl = lp.gather(2, X[:, :, None])[:, :, 0]
                outs.append(torch.stack([tl[j, 3:3 + len(t)].sum() for j, t in enumerate(token_lists)]))
        return outs[0] - outs[1]

    def score_tokens(self, token_lists, target_seq):
        out = []
        tf = self._tf_vec(target_seq)
        for i in range(0, len(token_lists), 256):
            out += [float(x) for x in self._llr(token_lists[i:i + 256], tf)]
        return out

    def score(self, smiles, target_seq):
        res, ok_idx, toks = [None] * len(smiles), [], []
        for i, s in enumerate(smiles):
            r = S.segment(s, self.dictionary)
            if r.get("ok") and r["complete"] and all(t in self.stoi for t in r["tokens"]) and len(r["tokens"]) + 4 <= self.block:
                ok_idx.append(i); toks.append(r["tokens"])
        if toks:
            for i, v in zip(ok_idx, self.score_tokens(toks, target_seq)): res[i] = v
        return res

    # ------------------------------------------------------------------ update
    def fingerprint(self):
        h = hashlib.sha256()
        for k, v in sorted(self.model.state_dict().items()): h.update(k.encode()); h.update(v.detach().cpu().numpy().tobytes())
        h.update(json.dumps(self.history).encode()); return h.hexdigest()[:16]

    def update_tokens(self, labelled, mode="finetune_ranking", seed=0, steps=60, lr=3e-4, beta=1.0, pairs_per_step=32, rounds=1):
        """labelled: [{tokens, target_seq, label}] (label higher = better, already within-target standardised). Returns a NEW LoopModel.
        one_shot_matched (data-matched control for the loop): ONE update on all labels the loop would have revealed over `rounds` rounds, with the same TOTAL
        gradient budget (steps*rounds) as a loop that does `steps` per round - same data, same compute, no feedback timing. `steps` is per-round."""
        assert mode in MODES, mode
        if mode == "one_shot_matched": steps = steps * max(1, int(rounds)); mode_eff = "finetune_ranking"
        else: mode_eff = mode
        new = LoopModel(copy.deepcopy(self.model), self.toks, self.block, self.dev, self.dictionary, self.history + ((mode, len(labelled), seed, rounds),))
        mode = mode_eff
        if mode == "frozen" or len(labelled) < 2: return new
        rng = np.random.default_rng(seed); by = {}
        for r in labelled: by.setdefault(r["target_seq"], []).append(r)
        pairs = []
        for t, rs in by.items():
            for i in range(len(rs)):
                for j in range(len(rs)):
                    if rs[i]["label"] > rs[j]["label"]: pairs.append((t, rs[i]["tokens"], rs[j]["tokens"]))
        if not pairs: return new
        ref = copy.deepcopy(self.model).eval() if mode == "dpo" else None
        torch.manual_seed(int(seed))   # dropout is active in train mode: updates must be deterministic given (model, data, seed)
        new.model.train(); opt = torch.optim.AdamW(new.model.parameters(), lr=lr, weight_decay=0.0)
        for _ in range(steps):
            idx = rng.choice(len(pairs), min(pairs_per_step, len(pairs)), replace=False); loss = 0.0
            for k in idx:
                t, w, l = pairs[k]; tf = new._tf_vec(t)
                s = new._llr([w, l], tf, grad=True); d = s[0] - s[1]
                if mode == "dpo":
                    with torch.no_grad(): rs_ = LoopModel(ref, self.toks, self.block, self.dev)._llr([w, l], tf); rd = rs_[0] - rs_[1]
                    d = d - rd
                loss = loss - torch.nn.functional.logsigmoid(beta * d)
            loss = loss / len(idx); opt.zero_grad(); loss.backward(); torch.nn.utils.clip_grad_norm_(new.model.parameters(), 1.0); opt.step()
        new.model.eval(); return new

    def update(self, labelled, mode="finetune_ranking", seed=0, **kw):
        rows = []
        for r in labelled:
            seg = S.segment(r["smiles"], self.dictionary)
            if seg.get("ok") and seg["complete"] and all(t in self.stoi for t in seg["tokens"]) and len(seg["tokens"]) + 4 <= self.block:
                rows.append(dict(tokens=seg["tokens"], target_seq=r["target_seq"], label=r["label"]))
        return self.update_tokens(rows, mode, seed, **kw)
