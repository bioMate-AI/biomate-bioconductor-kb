"""ChemFM token-level Constraint: hard rules as a logit mask (prefix-feasibility look-ahead + exact eos gate), soft rules as log-linear potentials.

Interface (plan section 2, `Constraint`):  init_state(prefix_ids) / mask(state) / advance(state, token_id) / is_complete(state) / soft_logits(state).
`mask_ref` is the brute-force reference (tries every vocabulary entry); `mask` is the fast path (tries only syntactically plausible entries). They are asserted equal in test_rules.py.
Hard-rule guarantee: a sample ends only on eos, and eos is allowed only if the complete string satisfies C of spec.py (checked by RDKit) => rule satisfaction 1.0 by construction.
Soundness (tested on the golden set): the mask never removes the true next token of a prefix of any string that satisfies C (false-prune rate 0), because every prune is a sound lower-bound argument (tracker.py).
"""
import numpy as np
from .tracker import Tracker, ORG, ARO, BOND, expand2
from .spec import satisfies_smiles, MW_HI, NME_HI, NME_LO

DEFAULT_RULES = None  # path set by the caller (kb_audit/peptide_sar_rules_v1.json)


def _atom_w(tok):
    from .tracker import _weight
    e2 = expand2(tok)
    if e2 is not None: return sum(_weight(x.upper() if x in ARO else x) for x in e2)
    return _weight(tok.upper() if tok in ARO else tok)


def assert_priors_clean(rules_json, heldout_sources):
    """same guard as ihlm/symbolic.py::assert_priors_clean (kept local to avoid importing the model package)."""
    held = set(map(str, heldout_sources)); bad = held & set(map(str, rules_json.get("train_sources", [])))
    for name, rule in rules_json.get("rules", {}).items(): bad |= held & set(map(str, rule.get("mined_from", [])))
    assert not bad, f"held-out sources were used to mine the priors: {sorted(bad)}"
    return True


class ChemFMConstraint:
    def __init__(self, vocab, max_len=500, lam_soft=0.0, soft=None, forbidden_sources=(), lookahead_nme=True):
        from .soft import SoftSource, assert_sources_disjoint
        self.vocab = vocab; self.V = vocab.V; self.max_len = max_len; self.eos = vocab.eos; self.lookahead_nme = lookahead_nme
        t2i = vocab.tok2id
        self.real_ids = np.array(sorted(i for i in vocab.id2tok if i != vocab.eos), dtype=np.int64)
        self.atom_ids = [t2i[t] for t in t2i if (t in ORG or t in ARO or expand2(t) is not None)]
        self.bond_ids = [t2i[t] for t in BOND if t in t2i]
        self.digit_ids = [t2i[str(d)] for d in range(10)]
        self.open_ids = [t2i["("]]; self.close_ids = [t2i[")"]]; self.lbr = t2i["["]; self.rbr = t2i["]"]; self.pct = t2i["%"]
        self.bracket_ids = [i for t, i in t2i.items() if t not in ("<eos>", "[", "(", ")", ".", "=", "#", "\\", "/", "~", "?", ">", "*", "$", "%")]
        self.soft = soft or SoftSource.none(); self.lam = float(lam_soft) if soft is not None else 0.0
        assert_sources_disjoint(self.soft, forbidden_sources)
        self._polar = [t2i[t] for t in ("N", "O", "n", "o") if t in t2i]; self._carbon = [t2i[t] for t in ("C", "c") if t in t2i]
        self._tC = t2i["C"]; self._tOpen = t2i["("]

    # ------------------------------------------------------------------ state
    def init_state(self, prefix_ids=()):
        st = Tracker()
        for tid in prefix_ids:
            if not st.advance(self.vocab.id2tok[int(tid)]): raise ValueError(f"illegal prefix token {self.vocab.id2tok[int(tid)]!r} at position {st.n}")
        return st

    def advance(self, st, tid):
        """in place; returns False if the token was illegal (caller must have masked it)."""
        return st.advance(self.vocab.id2tok[int(tid)])

    def is_complete(self, st): return st.complete()

    def eos_ok(self, st):
        """eos is token number st.n + 1 and must fit inside max_len; it is allowed only on a COMPLETE string that satisfies C (exact RDKit check)."""
        return bool(st.n < self.max_len and st.complete() and satisfies_smiles(st.string()))

    # ------------------------------------------------------------------ mask
    def _tok_ok(self, st, tid):
        st2 = st.copy()
        if not st2.advance(self.vocab.id2tok[int(tid)]): return False
        return st2.feasible(MW_HI, NME_HI, self.max_len - st2.n, NME_LO if self.lookahead_nme else 0)

    def _candidates(self, st):
        if st.br is not None: return self.bracket_ids + [self.rbr]       # strict grammar + mass filter in Tracker.advance/_tok_ok
        if st.pct is not None: return self.digit_ids
        c = self.atom_ids + [self.lbr]
        if st.prev >= 0:
            if st.pend is None:
                c = c + self.bond_ids + self.open_ids + self.close_ids
            c = c + self.digit_ids + [self.pct]
        return c

    def mask_ref(self, st):
        m = np.zeros(self.V, dtype=bool)
        for tid in self.real_ids:
            if self._tok_ok(st, tid): m[tid] = True
        m[self.eos] = self.eos_ok(st)
        return m

    def _class_key(self, st, tok):
        """tokens with identical semantic effect (budget, N-methyl bound) share a key; the only per-token difference is the added mass (atoms)."""
        if st.br is not None:
            if tok == "]": return ("close",)
            if tok.isdigit(): return ("bdigit",)
            if tok == "H": return ("bH",)
            if tok in ("@", "+", "-", ":"): return ("bsym", tok)
            return ("belem",)
        if st.pct is not None: return ("pdigit",)
        if tok in ORG or tok in ARO or expand2(tok) is not None: return ("atom",)
        if tok == "[": return ("[",)
        if tok in BOND: return ("bond",)
        if tok in ("(", ")", "%"): return (tok,)
        if len(tok) == 1 and tok.isdigit(): return ("close_ring", tok) if tok in st.rings else ("open_ring",)
        return ("other", tok)

    def mask(self, st):
        """fast path: tokens that add no mass and whose effect depends only on a semantic class (bond / branch / ring digit / '[') are evaluated once per class with the real bounds; atoms
        and everything inside a bracket (mass-adding, token-specific) are checked individually. Equal to mask_ref (tested)."""
        m = np.zeros(self.V, dtype=bool); cache = {}; id2 = self.vocab.id2tok
        for tid in self._candidates(st):
            tok = id2[int(tid)]
            if st.br is not None or st.pct is not None or tok in ORG or tok in ARO or expand2(tok) is not None:
                if self._tok_ok(st, tid): m[tid] = True
                continue
            key = self._class_key(st, tok)
            if key not in cache: cache[key] = self._tok_ok(st, tid)
            if cache[key]: m[tid] = True
        m[self.eos] = self.eos_ok(st)
        return m

    # ------------------------------------------------------------------ soft rules
    def _amide_n_open(self, st):
        """prev is an unbracketed aliphatic N bonded to exactly one atom, a carbonyl carbon (so a methyl branch would make it an N-methyl amide)."""
        i = st.prev
        if i < 0 or st.sym[i] != "N" or st.arom[i] or st.brk[i] or len(st.nbr[i]) != 1: return False
        j = st.nbr[i][0][0]
        return st.sym[j] == "C" and any(st.sym[k] == "O" and o == 2.0 for k, o in st.nbr[j])

    def soft_logits(self, st):
        """log-linear potential added to the logits of FEASIBLE tokens (product of experts), lam * weights of the plugged SoftSource (zero for source 'none' or lam 0).
        Token-level proxies of molecule-level rules: polar heteroatom tokens (N/O) for the TPSA/HBD/HBA direction, carbon tokens for logP, and an N-methyl nudge ('(' after an amide
        N, 'C' as the first atom of that branch)."""
        out = np.zeros(self.V, dtype=np.float64)
        if not self.lam or st.br is not None or st.pct is not None: return out
        w = self.soft.weights
        for i in self._polar: out[i] = self.lam * w["polar"]
        for i in self._carbon: out[i] = self.lam * w["carbon"]
        if w["nme"]:
            if self._amide_n_open(st) and st.pend is None: out[self._tOpen] += self.lam * w["nme"]
            elif st.just_open and st.stack and st.stack[-1] == st.prev and st.sym[st.prev] == "N" and len(st.nbr[st.prev]) == 1: out[self._tC] += self.lam * w["nme"]
        return out


class RuleAutomaton:
    """Implements allatom_paper/contracts.py::Constraint (string tokens, caller-supplied vocab list) on top of ChemFMConstraint (id based).
    `mask(state, vocab)` aligns the result with the caller's vocab order; `advance` is pure (returns a new state); `is_complete` = complete AND satisfies C."""

    def __init__(self, base):
        self.c = base; self._cache = {}

    def init_state(self): return self.c.init_state()

    def _index(self, vocab):
        key = id(vocab)
        if key not in self._cache:
            t2i = self.c.vocab.tok2id; self._cache[key] = [t2i.get(t, -1) for t in vocab]
        return self._cache[key]

    def mask(self, state, vocab):
        m = self.c.mask(state); idx = self._index(vocab)
        return [bool(m[i]) if i >= 0 else False for i in idx]

    def advance(self, state, token):
        st = state.copy()
        if token == "<eos>":
            if not self.c.eos_ok(st): raise ValueError("eos emitted where the mask forbids it")
            return st
        if not st.advance(token): raise ValueError(f"token {token!r} is illegal here")
        return st

    def is_complete(self, state): return bool(state.complete() and satisfies_smiles(state.string()))

    def soft_logits(self, state, vocab):
        s = self.c.soft_logits(state); idx = self._index(vocab)
        return [float(s[i]) if i >= 0 else 0.0 for i in idx]

    def check(self, smiles): return bool(satisfies_smiles(smiles))
