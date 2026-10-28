"""Scorers for the multi-target retrospective benchmark (docs/20261028_AVB6_RETROSPECTIVE_RECOVERY_PREREG.md, A1).
Two zero-fit arms (no benchmark label is ever used to fit either model):
  V4Scorer       unified cyclic LLM v4: LLR = logP(monomers | target, e_hi) - logP(monomers | target, e_lo), averaged over backbone rotations for cyclic peptides.
                 Requires a COMPLETE SMILES->monomer mapping (smiles_to_monomers.segment) and every token in the v4 vocabulary; otherwise score=None (reported as coverage).
  AtomLMScorer   2026-10-27 atom-level SMILES LM (ChEMBL-dominated, unconditioned): mean per-token log-likelihood. Carries NO target information; it measures typicality
                 under the pretraining corpus and is a control arm, not a binding model.
Neither scorer touches labels; target-family holdout therefore matters only for contamination (checked separately: CycPeptMPDB/display training sets vs benchmark positives)."""
import os, sys, json
import numpy as np
import torch
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "allatom"))
import smiles_to_monomers as S
import unified_cyclic_llm as U
from train_cyclic_llm_v3 import make_model, TFEAT_DIM, target_feature


class V4Scorer:
    def __init__(self, ckpt, device="cpu", dictionary=None):
        ck = torch.load(ckpt, map_location="cpu", weights_only=False); a = ck["args"]; self.toks = ck["toks"]; self.stoi = {t: i for i, t in enumerate(self.toks)}
        self.model = make_model(len(self.toks), TFEAT_DIM, d_model=a["d_model"], n_layer=a["n_layer"], n_head=a["n_head"], block=a["block"]); self.model.load_state_dict(ck["model"])
        self.model.to(device).eval(); self.dev = device; self.block = a["block"]; self.dictionary = dictionary if dictionary is not None else S.BASE
        self.pad = self.stoi[U.PAD]; self._tf = {}

    def target_vec(self, seq):
        if seq not in self._tf: self._tf[seq] = torch.tensor(target_feature(seq).astype("float32"))
        return self._tf[seq]

    @torch.no_grad()
    def _loglik(self, token_lists, eb, tf):
        ids = [[self.stoi[eb], self.stoi["<p_na>"], self.stoi[U.BOS]] + [self.stoi[m] for m in t] + [self.stoi[U.EOS]] for t in token_lists]
        mx = max(len(x) for x in ids); X = torch.full((len(ids), mx), self.pad, dtype=torch.long)
        for j, s in enumerate(ids): X[j, :len(s)] = torch.tensor(s)
        TF = tf[None].repeat(len(ids), 1)
        lp = torch.log_softmax(self.model(X.to(self.dev), TF.to(self.dev)), -1)[:, :mx]
        tl = lp.gather(2, X.to(self.dev)[:, :, None])[:, :, 0]
        return np.array([float(tl[j, 3:3 + len(t)].sum()) for j, t in enumerate(token_lists)])

    def llr_tokens(self, tokens, target_seq, cyclic=True):
        rots = S.rotations(tokens) if cyclic else [tokens]
        tf = self.target_vec(target_seq)
        return float(np.mean(self._loglik(rots, "<e_hi>", tf) - self._loglik(rots, "<e_lo>", tf)))

    def score_smiles(self, smiles, target_seq):
        """-> dict(score or None, status). Never silently drops unmapped residues."""
        r = S.segment(smiles, self.dictionary)
        if not r.get("ok"): return dict(score=None, status="segment_fail:" + str(r.get("why")))
        if not r["complete"]: return dict(score=None, status="unmapped_residues", coverage=round(r["coverage"], 3))
        if any(t not in self.stoi for t in r["tokens"]): return dict(score=None, status="token_not_in_v4_vocab")
        if len(r["tokens"]) + 4 > self.block: return dict(score=None, status="too_long")
        return dict(score=self.llr_tokens(r["tokens"], target_seq, cyclic=r["cyclic"]), status="ok", n_res=len(r["tokens"]))


class AtomLMScorer:
    def __init__(self, ckpt, vocab_json, device="cpu", d=512, layers=8, heads=8, max_len=256):
        import atom_lm as A
        self.A = A; itos = json.load(open(vocab_json)); self.vocab = A.Vocab(itos[4:]) if itos[:4] == ["<pad>", "<bos>", "<eos>", "<unk>"] else A.Vocab(itos)
        self.model = A.GPT(len(self.vocab), d=d, layers=layers, heads=heads, max_len=max_len)
        sd = torch.load(ckpt, map_location="cpu", weights_only=False)["model"]; self.model.load_state_dict(sd); self.model.to(device).eval(); self.dev = device; self.max_len = max_len

    @torch.no_grad()
    def score_smiles(self, smiles):
        try: ids = self.vocab.encode(smiles)
        except AssertionError: return dict(score=None, status="tokenizer_fail")
        if len(ids) > self.max_len: return dict(score=None, status="too_long")
        x = torch.tensor([ids], device=self.dev); lp = torch.log_softmax(self.model(x)[0, :-1], -1)
        tl = lp.gather(1, x[0, 1:, None])[:, 0]
        return dict(score=float(tl.mean()), sum_logp=float(tl.sum()), n_tok=len(ids) - 1, n_unk=int((x[0] == self.A.UNK).sum()), status="ok")
