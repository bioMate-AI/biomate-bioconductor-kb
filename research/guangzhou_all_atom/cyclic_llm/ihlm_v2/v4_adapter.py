"""V4Adapter: the audited v4 unified monomer LM (5.02 M params, vocab 393) behind the LoopModel contract, READ-ONLY, with explicit coverage reporting.
Scope (inventory row 1): scorer/sampler on the compounds the monomer converter maps completely; unmapped compounds return None (never imputed). No binding claim:
the v4 audit found its binding signal at chance against hard negatives on 4 of 5 targets and the target prefix barely used. v4 has no topology token."""
import re
import numpy as np, torch
from _paths import CKPT_V4, sha256_file
import unified_cyclic_llm as U
import smiles_to_monomers as S
from loop_model import LoopModel

_CTRL = {U.PAD, U.BOS, U.EOS, *U.EBUCK, *U.PBUCK}
_RE_ME = re.compile(r"^me([A-Z])$"); _RE_MEX = re.compile(r"^Me_(d?)([A-Za-z0-9]+)$")
_NAL = {"Nal": "2Nal", "2-Nal": "2Nal", "1-Nal": "1Nal", "d1-Nal": "d1Nal", "d2-Nal": "d2Nal", "dNal": "d2Nal"}
_BAD = set("-()[] \t")      # characters that break the HELM dialect parsed by acceptance_gate.raw_tokens (split on '-', brackets stripped)


def gate_name(tok):
    """v4/CycPeptMPDB monomer token -> the naming used by acceptance_gate / score.py (meK -> NMeK, Me_dL -> NMedL, Nal -> 2Nal). Returns None when the token cannot be
    represented in the gate's HELM dialect (e.g. 'Phe(4-Cl)' contains '-'): such compounds are ungradeable, not mis-parsed."""
    t = _NAL.get(tok, tok); m = _RE_ME.match(t)
    if m: t = "NMe" + m.group(1)
    else:
        m = _RE_MEX.match(t)
        if m: t = "NMe" + m.group(1) + m.group(2)
    return None if (not t or any(c in _BAD for c in t)) else t


def helm_from_tokens(tokens, cyclic=True):
    """HELM-style string for the gate/verifier from v4 monomer tokens; None if any token is not representable. Head-to-tail is ASSUMED for the string (v4 has no topology token;
    34.7 % of CycPeptMPDB rows are Lariat)."""
    names = [gate_name(t) for t in tokens]
    if not names or any(n is None for n in names): return None
    body = "-".join(n if len(n) == 1 else f"[{n}]" for n in names)
    return f"cyclo({body})" if cyclic else body


class V4Adapter:
    def __init__(self, ckpt=None, device="cpu"):
        self.ckpt = ckpt or CKPT_V4; self.sha_before = sha256_file(self.ckpt); self.device = device
        self.lm = LoopModel.from_checkpoint(self.ckpt, device)       # weights are copied into memory; the file is never written
        self.itos = {i: t for i, t in enumerate(self.lm.toks)}
        self.info = dict(params=self.lm.meter.n_params, vocab=len(self.lm.toks), block=self.lm.block, sha256_prefix=self.sha_before[:12])

    def verify_unmodified(self): return sha256_file(self.ckpt) == self.sha_before

    def segment(self, smiles):
        r = S.segment(smiles, self.lm.dictionary)
        ok = bool(r.get("ok") and r["complete"] and all(t in self.lm.stoi for t in r["tokens"]) and len(r["tokens"]) + 4 <= self.lm.block)
        return r["tokens"] if ok else None

    def coverage(self, smiles):
        flags = [self.segment(s) is not None for s in smiles]
        return dict(mapped=flags, n=len(flags), n_mapped=int(sum(flags)), fraction=(float(np.mean(flags)) if flags else 0.0))

    def score(self, smiles, target_seq): return self.lm.score(smiles, target_seq)        # None for unmapped; LLR(e_hi vs e_lo); NOT binding evidence

    def helm(self, smiles):
        t = self.segment(smiles); return None if t is None else helm_from_tokens(t)

    def propose(self, n, target_seq, seed=0, temp=1.0, max_len=16, eb="<e_hi>", pb="<p_hi>"):
        """sample monomer sequences from v4 under (target prefix, e_hi, p_hi) conditioning. Returns dicts {tokens, valid, helm}. valid = 3..max_len non-control tokens
        (TOKEN-level validity only, as in the v4 audit); `helm` is None when a token is not representable in the gate dialect."""
        torch.manual_seed(int(seed)); m, stoi, dev, block = self.lm.model, self.lm.stoi, self.lm.dev, self.lm.block
        tf = self.lm._tf_vec(target_seq)[None].to(dev); out = []
        for _ in range(int(n)):
            ids = [stoi[eb], stoi[pb], stoi[U.BOS]]
            for _ in range(max_len + 1):
                with torch.no_grad(): lg = m(torch.tensor([ids[-block:]], device=dev), tf)[0, -1] / float(temp)
                nx = int(torch.multinomial(torch.softmax(lg, -1), 1))
                if nx == stoi[U.EOS]: break
                ids.append(nx)
            toks = [self.itos[i] for i in ids[3:]]; valid = 3 <= len(toks) <= max_len and all(t not in _CTRL for t in toks)
            out.append(dict(tokens=toks, valid=valid, helm=helm_from_tokens(toks) if valid else None, topology="unspecified (v4 has no topology token)"))
        return out

    def update(self, labelled, mode="finetune_ranking", seed=0, **kw):
        """returns a NEW adapter around an updated LoopModel (the checkpoint file is never touched)."""
        new = object.__new__(V4Adapter); new.__dict__.update(self.__dict__); new.lm = self.lm.update(labelled, mode, seed, **kw); return new

    def fingerprint(self): return self.lm.fingerprint()
    def cost(self, **kw): return self.lm.cost(**kw)
