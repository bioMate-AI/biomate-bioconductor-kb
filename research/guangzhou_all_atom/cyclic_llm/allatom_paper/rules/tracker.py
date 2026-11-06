"""Incremental SMILES prefix tracker over ChemFM-style atom tokens.

Tracks only what is needed for SOUND prefix pruning (a prefix is pruned only if NO completion can satisfy the constraint set C of spec.py):
  * syntax (branches, ring closures, bracket atoms, bond symbols);
  * mass lower bound: sum of heavy-atom weights of atoms already written (the final MW can only be larger);
  * N-methyl amide lower bound: matches of [CX3](=O)[NX3;!H1]([CH3]) among atoms whose neighbourhood is FINAL (cannot gain a bond any more);
  * token-budget lower bound: tokens still needed to close branches / rings / a bracket / a dangling bond, plus the eos token.
Everything else in C (ring >= 12, MW >= 600, TPSA <= 300, PAINS, single fragment) is checked exactly by RDKit on the COMPLETE string when eos is proposed
(eos is the only token that can end a sample), which is what makes rule satisfaction 1.0 by construction.
Documented simplifications that can only make pruning weaker, never unsound: unbracketed atoms outside the organic subset are illegal; '.' (disconnected fragments)
is illegal because C requires one fragment; wildcard '*', '~', '?', '>' and '$' are illegal because no molecule satisfying C (an RDKit-sanitisable peptide) uses them.
"""
from rdkit import Chem

_PT = Chem.GetPeriodicTable()
# LANGUAGE RESTRICTION (declared; dead-end analysis 2026-10-29): peptide chemistry only. CycPeptMPDB (8,466 structures) and the 131-entry monomer dictionary use C N O S F Cl Br and no isotopes;
# P and I are kept as margin. Aromatic atoms: c n o s. No isotopes, no other elements. Strings outside this language are not generated (and cannot satisfy the intended use).
ORG = {"C", "N", "O", "S", "P", "F", "Cl", "Br", "I"}
ARO = {"c", "n", "o", "s"}
SINGLE = {"C", "N", "O", "S", "P", "F", "I", "c", "n", "o", "s"}
BOND = {"-": 1.0, "=": 2.0, "#": 3.0, ":": 1.5, "/": 1.0, "\\": 1.0}
MAX_BRACKET_TOKENS = 12


def expand2(t):
    """a two-letter vocabulary token that is really two SMILES atoms (e.g. 'Cn' = C + aromatic n, 'cn', 'Co', 'os'); None otherwise. 'Cl' and 'Br' are single atoms."""
    if len(t) == 2 and t not in ORG and t[0] in SINGLE and t[1] in ARO: return (t[0], t[1])
    return None


def _weight(sym):
    try: return float(_PT.GetAtomicWeight(sym))
    except Exception: return 0.0


def _is_element(tok):
    s = tok.capitalize() if tok.islower() else tok
    try: return _PT.GetAtomicNumber(s) > 0      # '*' (dummy) has atomic number 0 and must not count as an element
    except Exception: return False


class Tracker:
    __slots__ = ("sym", "arom", "brk", "hexp", "chg", "nbr", "prev", "stack", "rings", "pend", "br", "pct", "mass", "n", "toks", "just_open")

    def __init__(self):
        self.sym = []; self.arom = []; self.brk = []; self.hexp = []; self.chg = []; self.nbr = []
        self.prev = -1; self.stack = []; self.rings = {}; self.pend = None; self.br = None; self.pct = None
        self.mass = 0.0; self.n = 0; self.toks = []; self.just_open = False

    def copy(self):
        t = Tracker.__new__(Tracker)
        t.sym = self.sym[:]; t.arom = self.arom[:]; t.brk = self.brk[:]; t.hexp = self.hexp[:]; t.chg = self.chg[:]
        t.nbr = [x[:] for x in self.nbr]; t.prev = self.prev; t.stack = self.stack[:]; t.rings = dict(self.rings); t.pend = self.pend
        t.br = None if self.br is None else self.br[:]; t.pct = None if self.pct is None else self.pct[:]
        t.mass = self.mass; t.n = self.n; t.toks = self.toks[:]; t.just_open = self.just_open
        return t

    # ------------------------------------------------------------------ atoms and bonds
    def _add_atom(self, sym, arom, brk, hexp, chg, charged=False):
        i = len(self.sym)
        self.sym.append(sym); self.arom.append(arom); self.brk.append(brk); self.hexp.append(hexp); self.chg.append(chg); self.nbr.append([])
        if self.prev >= 0:
            order = self.pend if self.pend is not None else (1.5 if (arom and self.arom[self.prev]) else 1.0)
            self.nbr[self.prev].append((i, order)); self.nbr[i].append((self.prev, order))
        self.prev = i; self.pend = None; self.just_open = False
        if sym != "H" and not charged: self.mass += _weight(sym)
        return True

    def _ring(self, label):
        if self.prev < 0: return False
        if label in self.rings:
            j, o = self.rings.pop(label)
            if j == self.prev or any(k == j for k, _ in self.nbr[self.prev]): return False
            order = self.pend if self.pend is not None else (o if o is not None else (1.5 if (self.arom[j] and self.arom[self.prev]) else 1.0))
            self.nbr[self.prev].append((j, order)); self.nbr[j].append((self.prev, order))
        else:
            self.rings[label] = (self.prev, self.pend)
        self.pend = None; self.just_open = False
        return True

    # ------------------------------------------------------------------ bracket atoms
    # strict OpenSMILES bracket grammar:  [ isotope? element chirality? hcount? charge? ]   (atom classes ':' are not allowed). The element's mass is charged at the ELEMENT token
    # (not at ']'), so the mass bound prunes before a bracket can get stuck (dead-end analysis 2026-10-29: junk brackets near the MW cap).
    @staticmethod
    def _parse_bracket(b):
        """returns (stage, element_index) where stage in iso/post and post-state flags; None if the token list is not a valid prefix."""
        i = 0                                          # isotopes are not part of the restricted language
        if i == len(b): return ("iso", None, 0, 0, 0, 0)
        el = b[i]
        if not (el in ORG or el in ARO): return None
        j = i + 1; chi = 0; hc = 0; hd = 0; chg = 0; chd = 0
        while j < len(b):
            x = b[j]
            if x == "@" and chi < 2 and hc == 0 and chg == 0: chi += 1; j += 1
            elif x == "H" and hc == 0 and chg == 0: hc = 1; j += 1
            elif x.isdigit() and len(x) == 1 and hc == 1 and hd == 0 and chg == 0: hd = 1; j += 1
            elif x in ("+", "-") and chg == 0: chg = 1; j += 1
            elif x in ("+", "-") and chg == 1 and chd == 0 and b[j - 1] == x: chd = 1; j += 1
            elif x.isdigit() and len(x) == 1 and chg == 1 and chd == 0 and b[j - 1] in ("+", "-"): chd = 1; j += 1
            else: return None
        return ("post", i, chi, hc, chg, chd)

    def _bracket(self, t):
        b = self.br
        if t == "]": return self._close_bracket()
        if len(b) >= MAX_BRACKET_TOKENS: return False
        nb = b + [t]
        st = self._parse_bracket(nb)
        if st is None: return False
        # charge the element's mass the moment the element token is consumed
        if st[0] == "post" and st[1] == len(nb) - 1: self.mass += _weight(nb[st[1]].capitalize() if nb[st[1]].islower() else nb[st[1]])
        b.append(t); return True

    def _close_bracket(self):
        b = self.br; st = self._parse_bracket(b)
        if st is None or st[0] != "post": return False
        el = b[st[1]]; arom = el.islower(); sym = el.capitalize() if arom else el
        hexp = 0; chg = 0
        for k in range(st[1] + 1, len(b)):
            if b[k] == "H":
                hexp = 1
                if k + 1 < len(b) and b[k + 1].isdigit() and b[k - 1] != "+" and b[k - 1] != "-": hexp = int(b[k + 1])
        for k in range(st[1] + 1, len(b)):
            if b[k] in ("+", "-"):
                sgn = 1 if b[k] == "+" else -1; mag = 1
                if k + 1 < len(b) and b[k + 1].isdigit(): mag = int(b[k + 1])
                elif k + 1 < len(b) and b[k + 1] == b[k]: mag = 2
                chg = sgn * mag; break
        self.br = None
        return self._add_atom(sym, arom, True, hexp, chg, charged=True)

    # ------------------------------------------------------------------ public
    def advance(self, t):
        """consume one token; returns False if the token is syntactically illegal here (state is then undefined: callers advance copies)."""
        self.n += 1; self.toks.append(t)
        if self.br is not None: return self._bracket(t)
        if self.pct is not None:
            if len(t) == 1 and t.isdigit():
                self.pct.append(t)
                if len(self.pct) == 2:
                    lab = "%" + "".join(self.pct); self.pct = None; return self._ring(lab)
                return True
            return False
        if t in ORG: return self._add_atom(t, False, False, None, 0)
        if t in ARO: return self._add_atom(t.upper(), True, False, None, 0)
        e2 = expand2(t)
        if e2 is not None:
            return all(self._add_atom(x.upper() if x in ARO else x, x in ARO, False, None, 0) for x in e2)
        if t == "[": self.br = []; return True
        if t in BOND:
            if self.pend is not None or self.prev < 0: return False
            self.pend = BOND[t]; return True
        if t == "(":
            if self.prev < 0 or self.pend is not None or self.just_open: return False
            self.stack.append(self.prev); self.just_open = True; return True
        if t == ")":
            if not self.stack or self.pend is not None or self.just_open: return False
            self.prev = self.stack.pop(); return True
        if t == "%":
            if self.prev < 0 or self.pct is not None: return False
            self.pct = []; return True
        if len(t) == 1 and t.isdigit(): return self._ring(t)
        return False

    def complete(self):
        return (self.br is None and self.pct is None and not self.stack and not self.rings and self.pend is None and self.prev >= 0 and not self.just_open)

    def string(self): return "".join(self.toks)

    # ------------------------------------------------------------------ sound bounds
    def _final(self, i):
        return i != self.prev and i not in self.stack and all(a != i for a, _ in self.rings.values())

    def _in_small_ring(self, i, maxlen=8):
        """True if atom i lies on a cycle of <= maxlen atoms in the partial graph. Such atoms are excluded from the N-methyl lower bound because RDKit may
        perceive a small Kekule ring (e.g. a pyridone) as aromatic, which would remove the aliphatic-C/N SMARTS match; large macrocycle backbone rings cannot."""
        for j, _ in self.nbr[i]:
            seen = {j: 1}; q = [j]
            while q:
                nq = []
                for u in q:
                    if seen[u] + 1 > maxlen: continue
                    for v, _o in self.nbr[u]:
                        if u == j and v == i: continue
                        if v == i: return True
                        if v not in seen: seen[v] = seen[u] + 1; nq.append(v)
                q = nq
        return False

    def nme_lower_bound(self):
        """matches of [CX3](=O)[NX3;!H1]([CH3]) among atoms whose neighbourhood is final: a lower bound of the final count."""
        cnt = 0
        for i, s in enumerate(self.sym):
            if s != "N" or self.arom[i] or not self._final(i): continue
            if self.chg[i] != 0 or (self.brk[i] and self.hexp[i]) or self._in_small_ring(i): continue
            nb = self.nbr[i]
            if len(nb) != 3 or any(o != 1.0 for _, o in nb): continue
            carbonyl = 0; methyl = 0
            for j, _ in nb:
                if self.sym[j] != "C" or self.arom[j] or not self._final(j): continue
                nj = self.nbr[j]
                if len(nj) == 1 and not self.brk[j]: methyl += 1; continue
                if len(nj) == 3 and not self.brk[j]:
                    ok_o = False
                    for k, o in nj:
                        if k != i and self.sym[k] == "O" and not self.arom[k] and o == 2.0 and len(self.nbr[k]) == 1 and self._final(k): ok_o = True
                    if ok_o and not self._in_small_ring(j): carbonyl += 1
            cnt += carbonyl * methyl
        return cnt

    def tokens_to_finish_lb(self):
        """minimum number of further tokens before eos can be accepted (sound lower bound)."""
        lb = 1  # eos itself
        lb += len(self.stack)                      # one ')' per open branch
        lb += len(self.rings)                      # at least one closing digit per open ring label
        if self.br is not None: lb += 1            # ']'
        if self.pct is not None: lb += 2 - len(self.pct)
        if self.pend is not None or self.prev < 0: lb += 1
        if self.just_open: lb += 1
        return lb

    def feasible(self, mw_hi, nme_hi, remaining):
        """False only if NO completion within `remaining` more tokens can satisfy C."""
        if self.mass > mw_hi: return False
        if self.nme_lower_bound() > nme_hi: return False
        if self.tokens_to_finish_lb() > remaining: return False
        return True
