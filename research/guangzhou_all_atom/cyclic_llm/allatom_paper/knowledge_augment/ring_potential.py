"""Structure-derived ring-size potential (level L2) and the augmented constraint that applies it.

The potential comes from the bound-conformation priors of the structure-knowledge layer (structure_knowledge/results/soft_potentials_v1.json: log-probability
tables of the number of RESIDUES in the ring, per closure class). Applied at the token level it acts on ring-closure DIGIT tokens only: when a digit would
close a macrocycle (smallest ring through the closing bond >= MIN_RING_ATOMS atoms), its logit receives  weight * (log p(ring residues | class) - max_r log p(r | class)),
i.e. a penalty-only log-linear potential that is zero for the most frequent ring size of the closure class and negative for rare ones.

Documented approximations (token-level proxies of a residue-level statistic):
  * closure class from the two atoms joined by the closing bond: S-S -> disulfide; C-S -> thioether; C-N -> 'amide' (mixture of head_to_tail and amide_like
    weighted by their complex counts); anything else -> no potential.
  * ring atoms A = number of atoms on the shortest path between the two atoms in the partial molecular graph + 0 (the closing bond adds no atom).
    residues ~ round(A / 3) for amide and thioether closures (three backbone atoms per residue), round((A - 2) / 3) for disulfides (the CB-SG-SG-CB bridge adds 2 net atoms).
  * the turn-presence and interface-position priors have NO token-level potential (they are exported to the prompt only).
`AugmentedConstraint` subclasses the rule automaton's ChemFMConstraint (rules/constraint.py, owned by U1, not edited): the hard mask is untouched, soft logits = the
plugged SoftSource (token proxies: polar / carbon / N-methyl) + this ring potential.
"""
import hashlib
import json
import math
import os
import sys
from collections import Counter, deque
from dataclasses import dataclass, field

HERE = os.path.dirname(os.path.abspath(__file__))
AP = os.path.normpath(os.path.join(HERE, ".."))
if AP not in sys.path:
    sys.path.insert(0, AP)
from rules.constraint import ChemFMConstraint  # noqa: E402

LIB_DEFAULT = os.path.join(AP, "structure_knowledge", "results", "library_v1.jsonl")
CLASSES = ("disulfide", "head_to_tail", "amide_like", "thioether")
RES_RANGE = range(4, 31)
FLOOR = 1e-4                      # same floor as structure_knowledge/aggregate.py::potentials
MIN_RING_ATOMS = 12               # macrocycle scale; smaller rings (proline, aromatic) get no potential


def hash_targets(ts):
    """same definition as structure_knowledge/aggregate.py::_hash_targets."""
    return hashlib.sha256("\n".join(sorted(ts)).encode()).hexdigest()[:16]


def _read_lib(path):
    return [json.loads(l) for l in open(path)]


def ring_tables(exclude_tokens=(), lib_path=LIB_DEFAULT):
    """Recompute the ring-residue log-probability tables from the committed library, optionally WITHOUT a set of held-out targets (arm G).
    A token excludes every target whose key equals it or whose accession set contains it (same rule as structure_knowledge/aggregate.py main).
    Primary library = peptides bound to non-antibody receptors (as in the committed priors)."""
    rows = [r for r in _read_lib(lib_path) if not r["receptor_antibody_like"]]
    toks = set(map(str, exclude_tokens))
    keys = {r["target_key"] for r in rows}
    ex = frozenset(k for k in keys if k in toks or (set(k.split("+")) & toks))
    rows = [r for r in rows if r["target_key"] not in ex]
    targets = sorted({r["target_key"] for r in rows})
    tables, n = {}, {}
    for cls in CLASSES:
        c = Counter(min(max(int(r["ring_residues"]), 4), 30) for r in rows if r["primary_cyclisation"] == cls)
        tot = sum(c.values())
        n[cls] = tot
        if tot == 0:
            continue
        tables[cls] = {k: math.log(max(c.get(k, 0) / tot, FLOOR)) for k in RES_RANGE}
    return dict(tables=tables, n=n, targets_sha256=hash_targets(targets), excluded_sha256=hash_targets(ex) if ex else None,
                excluded_targets=sorted(ex), n_complexes=len(rows), n_targets=len(targets))


def committed_tables(path):
    """the exported potentials of the structure-knowledge layer (full library, no exclusion)."""
    pots = json.load(open(path))
    tables, n, sha = {}, {}, set()
    for p in pots:
        if p.get("feature") != "ring_residues":
            continue
        cls = p["applies_to"].split("=")[1]
        tables[cls] = {int(k): v for k, v in p["log_prob"].items()}
        n[cls] = p["n"]
        sha.add(p["targets_sha256"])
    return tables, n, sha


def _logsumexp(a, b):
    m = max(a, b)
    return m + math.log(math.exp(a - m) + math.exp(b - m))


@dataclass(frozen=True)
class RingPotential:
    tables: dict                      # closure class -> {residues: log p}; class 'amide' = mixture of head_to_tail and amide_like
    weight: float
    n: dict
    targets_sha256: str
    excluded_sha256: object = None
    min_ring_atoms: int = MIN_RING_ATOMS
    _max: dict = field(default_factory=dict, compare=False, hash=False)

    @staticmethod
    def build(rt, weight=0.5):
        t = {k: dict(v) for k, v in rt["tables"].items() if k in ("disulfide", "thioether")}
        nh, na = rt["n"].get("head_to_tail", 0), rt["n"].get("amide_like", 0)
        if nh and na:
            th, ta = rt["tables"]["head_to_tail"], rt["tables"]["amide_like"]
            t["amide"] = {r: _logsumexp(math.log(nh) + th[r], math.log(na) + ta[r]) - math.log(nh + na) for r in RES_RANGE}
        elif nh or na:
            t["amide"] = dict(rt["tables"]["head_to_tail" if nh else "amide_like"])
        mx = {k: max(v.values()) for k, v in t.items()}
        return RingPotential(t, float(weight), dict(rt["n"]), rt["targets_sha256"], rt["excluded_sha256"], MIN_RING_ATOMS, mx)

    @staticmethod
    def residues(cls, atoms):
        r = round((atoms - 2) / 3.0) if cls == "disulfide" else round(atoms / 3.0)
        return int(min(max(r, 4), 30))

    def penalty(self, cls, atoms):
        """<= 0; zero at the modal ring size of the class."""
        if cls not in self.tables or atoms < self.min_ring_atoms or not self.weight:
            return 0.0
        lp = self.tables[cls][self.residues(cls, atoms)]
        return self.weight * (lp - self._max[cls])


def closure_class(sym_a, sym_b):
    a, b = sorted((sym_a.capitalize(), sym_b.capitalize()))
    if a == "S" and b == "S":
        return "disulfide"
    if (a, b) == ("C", "S"):
        return "thioether"
    if (a, b) == ("C", "N"):
        return "amide"
    return None


def ring_atoms_if_closed(st, label):
    """atoms on the shortest path between the atom that opened `label` and the current atom (None if the closure is illegal or the atoms are not connected)."""
    j = st.rings[label][0]
    i = st.prev
    if i < 0 or j == i or any(k == j for k, _ in st.nbr[i]):
        return None
    dist = {j: 0}
    q = deque([j])
    while q:
        u = q.popleft()
        if u == i:
            return dist[u] + 1
        for v, _o in st.nbr[u]:
            if v not in dist:
                dist[v] = dist[u] + 1
                q.append(v)
    return None


class AugmentedConstraint(ChemFMConstraint):
    """ChemFMConstraint + structure-derived ring-size potential. Hard mask identical to the base class (tested); soft logits = base soft logits + ring potential."""

    def __init__(self, vocab, max_len=500, lam_soft=0.0, soft=None, forbidden_sources=(), ring=None):
        super().__init__(vocab, max_len=max_len, lam_soft=lam_soft, soft=soft, forbidden_sources=forbidden_sources)
        self.ring = ring
        self._digit = {str(d): vocab.tok2id[str(d)] for d in range(10) if str(d) in vocab.tok2id}

    def soft_logits(self, st):
        out = super().soft_logits(st)
        r = self.ring
        if r is None or not r.weight or st.br is not None or st.pct is not None or not st.rings:
            return out
        for label in list(st.rings):
            tid = self._digit.get(label)
            if tid is None:
                continue
            j = st.rings[label][0]
            cls = closure_class(st.sym[j], st.sym[st.prev]) if st.prev >= 0 else None
            if cls is None:
                continue
            a = ring_atoms_if_closed(st, label)
            if a is None:
                continue
            out[tid] += r.penalty(cls, a)
        return out
