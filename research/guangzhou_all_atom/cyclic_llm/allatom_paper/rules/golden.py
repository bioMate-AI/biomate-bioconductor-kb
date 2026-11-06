"""Golden set for the rule automaton: >= 2,000 peptide-like SMILES with known status.
  * 'sat'      : valid, satisfies C (spec.py): cyclic peptides from the 131-entry monomer dictionary (L, D, N-methyl, ncAA), canonical + random-order SMILES;
  * 'valid_bad': valid but violates C (too few/many N-Me, linear, too small/large MW, ...);
  * 'invalid'  : not parseable / not one fragment (token shuffles, unbalanced branches, bad ring closures).
Monomer library and cyclic builder are copies of generation_pilot/gen_pilot.py (S-LIB), so the golden strings share the chemistry of the pilot-3 constraint set."""
import json, os, random
from rdkit import Chem, RDLogger
from .spec import satisfies

RDLogger.DisableLog("rdApp.*")
HERE = os.path.dirname(os.path.abspath(__file__))
MONO_JSON = os.environ.get("MONO_JSON", os.path.join(HERE, "..", "..", "v4_eval", "monomer_dictionary_v5.json"))
_ALPHA = Chem.MolFromSmarts("[NX3;!$(N-C=O);!$(N=*);!$(N-S(=O)=O)]-[CX4]-[CX3](=O)[OX2H1]")
_MONO = None


def monomers():
    global _MONO
    if _MONO is None:
        d = json.load(open(MONO_JSON)); cls = {"L": [], "N": [], "D": []}; seen = set()
        for smi, code in d.items():
            if smi in seen: continue
            seen.add(smi); m = Chem.MolFromSmiles(smi)
            if m is None: continue
            mt = m.GetSubstructMatch(_ALPHA)
            if not mt: continue
            k = "N" if (code.startswith("me") or code.startswith("Me_") or code == "Sar") else ("D" if (code.startswith("d") and len(code) > 1 and code[1].isupper()) else "L")
            cls[k].append((m, mt, code))
        _MONO = cls
    return _MONO


def build(seq, cyclic=True):
    combo = Chem.Mol(); offs = []
    for m, mt, _ in seq: offs.append(combo.GetNumAtoms()); combo = Chem.CombineMols(combo, m)
    rw = Chem.RWMol(combo); rem = []; L = len(seq)
    for i in range(L):
        if not cyclic and i == L - 1: break
        mt = seq[i][1]; c = offs[i] + mt[2]; oh = offs[i] + mt[4]; j = (i + 1) % L; nn = offs[j] + seq[j][1][0]
        rw.AddBond(c, nn, Chem.BondType.SINGLE); rem.append(oh)
    for a in sorted(rem, reverse=True): rw.RemoveAtom(a)
    mol = rw.GetMol(); Chem.SanitizeMol(mol); return mol


def _random_smiles(m, rng, k):
    out = []
    for _ in range(k):
        s = Chem.MolToSmiles(m, doRandom=True, isomericSmiles=True)
        if s: out.append(s)
    return out


def make(n_sat=900, n_bad=700, n_inv=600, seed=0):
    try:
        from rdkit import rdBase; rdBase.SeedRandomNumberGenerator(seed)    # makes doRandom SMILES reproducible
    except Exception: pass
    rng = random.Random(seed); M = monomers(); rows = []; seen = set()

    def add(s, kind, tag):
        if s and s not in seen: seen.add(s); rows.append(dict(smiles=s, kind=kind, tag=tag))

    # ---- satisfying and valid-but-violating cyclic / linear peptides
    tries = 0
    while sum(r["kind"] == "sat" for r in rows) < n_sat or sum(r["kind"] == "valid_bad" for r in rows) < n_bad:
        tries += 1
        if tries > 60000: break
        L = rng.randint(3, 14); p_nme = rng.choice([0.0, 0.1, 0.25, 0.4, 0.6]); p_d = rng.choice([0.0, 0.15, 0.3]); cyclic = rng.random() > 0.12
        seq = []
        for _ in range(L):
            u = rng.random(); k = "N" if u < p_nme else ("D" if u < p_nme + p_d else "L"); seq.append(rng.choice(M[k]))
        try: m = build(seq, cyclic)
        except Exception: continue
        ok = satisfies(m)
        kind = "sat" if ok else "valid_bad"
        have = sum(r["kind"] == kind for r in rows); cap = n_sat if ok else n_bad
        if have >= cap: continue
        tag = f"L{L}_{'cyc' if cyclic else 'lin'}"
        add(Chem.MolToSmiles(m), kind, tag + "_canon")
        for s in _random_smiles(m, rng, 2): add(s, kind, tag + "_rand")
    # ---- invalid strings
    sat = [r["smiles"] for r in rows if r["kind"] == "sat"]
    while sum(r["kind"] == "invalid" for r in rows) < n_inv:
        s = rng.choice(sat); j = rng.randint(0, 5)
        if j == 0: t = s + ")"
        elif j == 1: t = "(" + s
        elif j == 2:
            i = rng.randrange(len(s)); t = s[:i] + rng.choice(["((", "))", "==", "[", "]", "%", "..", "99"]) + s[i:]
        elif j == 3: t = s + "1"
        elif j == 4: t = "".join(rng.sample(s, len(s)))
        else: t = s.replace("C(=O)", "C(=O", 1)
        if Chem.MolFromSmiles(t) is None: add(t, "invalid", f"inv{j}")
    return rows


if __name__ == "__main__":
    rows = make(); import collections
    print(collections.Counter(r["kind"] for r in rows), len(rows))
