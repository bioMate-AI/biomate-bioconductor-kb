"""Minimal peptide sequence -> SMILES converter for patent text (K4). Handles hyphen/space separated 3-letter codes with optional D- / N-Me- prefixes,
a small set of common non-canonical residues, and 'cyclo' head-to-tail closure. Anything else is reported as a FAILURE, never guessed."""
import re
from rdkit import Chem

# side-chain SMILES fragments attached at CA; Gly special. Each entry: (side_chain_smiles_after_CA)
SC = {"Gly": "", "Ala": "C", "Val": "C(C)C", "Leu": "CC(C)C", "Ile": "C(C)CC", "Pro": None, "Phe": "Cc1ccccc1", "Trp": "Cc1c[nH]c2ccccc12",
      "Tyr": "Cc1ccc(O)cc1", "Ser": "CO", "Thr": "C(C)O", "Cys": "CS", "Met": "CCSC", "Asn": "CC(N)=O", "Gln": "CCC(N)=O",
      "Asp": "CC(=O)O", "Glu": "CCC(=O)O", "Lys": "CCCCN", "Arg": "CCCNC(N)=N", "His": "Cc1c[nH]cn1",
      "Orn": "CCCN", "Nle": "CCCC", "Abu": "CC", "Dap": "CN", "Dab": "CCN", "Aib": "AIB", "Sar": "SAR", "Hyp": "HYP", "Nva": "CCC"}
ONE = {"G": "Gly", "A": "Ala", "V": "Val", "L": "Leu", "I": "Ile", "P": "Pro", "F": "Phe", "W": "Trp", "Y": "Tyr", "S": "Ser", "T": "Thr",
       "C": "Cys", "M": "Met", "N": "Asn", "Q": "Gln", "D": "Asp", "E": "Glu", "K": "Lys", "R": "Arg", "H": "His"}

class ConvertError(Exception):
    pass

def _residue(code, d, nme):
    """Return (n_cap_builder) pieces as SMILES string for ONE residue as -N(R)-C(CA)(...)-C(=O)- written N->C, using ring-closure-free chain."""
    if code == "Pro":
        base = "N1CCC[C@@H]1C(=O)" if not d else "N1CCC[C@H]1C(=O)"
        return base
    if code == "Hyp":
        return "N1C[C@H](O)C[C@@H]1C(=O)" if not d else "N1C[C@@H](O)C[C@H]1C(=O)"
    if code == "Sar":
        return "N(C)CC(=O)"
    n = "N(C)" if nme else "N"
    if code == "Gly":
        return f"{n}CC(=O)"
    if code == "Aib":
        return f"{n}C(C)(C)C(=O)"
    sc = SC[code]
    chir = "@" if d else "@@"        # L-amino acids written N[C@@H](R)C(=O): D flips
    return f"{n}[C{chir}H]({sc})C(=O)"

def parse_tokens(seq):
    s = seq.strip()
    cyclo = bool(re.search(r"cyclo|cyclic|c\(", s, re.I))
    s = re.sub(r"cyclo|cyclic|^\s*c\(|\)$|\(|\)|\[|\]", " ", s, flags=re.I)
    s = re.sub(r"\bAc[- ]|\bNH2\b|[- ]NH2\b|\bOH\b|\bH-", " ", s)
    toks = [t for t in re.split(r"[-\s,]+", s) if t]
    if len(toks) < 2:
        # try one-letter string
        one = re.sub(r"[^A-Za-z]", "", seq)
        if len(one) >= 2 and all(c.upper() in ONE or c.lower() in ONE.keys() for c in one):
            toks = list(one)
        else:
            raise ConvertError("unparsable sequence")
    out, i = [], 0
    while i < len(toks):
        t = toks[i]
        d = nme = False
        if t in ("D", "d") and i + 1 < len(toks):
            d = True; i += 1; t = toks[i]
        if t.lower() in ("n", "nme", "me") and i + 1 < len(toks) and toks[i + 1].lower() in ("me",):
            nme = True; i += 2; t = toks[i] if i < len(toks) else ""
        elif t.lower().startswith("nme") and len(t) > 3:
            nme = True; t = t[3:]
        elif t.lower().startswith("n-me") and len(t) > 4:
            nme = True; t = t[4:]
        elif t.lower().startswith("me") and t[2:].capitalize() in SC:
            nme = True; t = t[2:]
        if t.lower().startswith("d-") and t[2:].capitalize() in SC:
            d = True; t = t[2:]
        key = t.capitalize() if len(t) > 1 else ONE.get(t.upper(), "")
        if len(t) == 1 and t.islower():
            d = True
        if key not in SC:
            raise ConvertError(f"unknown residue '{t}'")
        out.append((key, d, nme))
        i += 1
    return out, cyclo

def to_smiles(seq):
    res, cyclo = parse_tokens(seq)
    if len(res) < 3:
        raise ConvertError("fewer than 3 residues")
    body = "".join(_residue(*r) for r in res)
    smi = body + "O" if not cyclo else body
    if cyclo:
        # head-to-tail: close the ring between the first N and the last C
        first = _residue(*res[0])
        body = "".join(_residue(*r) for r in res)
        # use ring-bond label 9 on the first N and on the last carbonyl carbon
        body = body.replace("N", "N9", 1) if body.startswith("N") and not body.startswith("N1") else body
        if not body.startswith("N9") and not body.startswith("N1"):
            raise ConvertError("cannot close ring for this N-terminus")
        if body.startswith("N1"):
            raise ConvertError("N-terminal Pro/Hyp cyclisation not supported")
        if not body.endswith("C(=O)"):
            raise ConvertError("bad C-terminus")
        smi = body[:-5] + "C9=O"
    m = Chem.MolFromSmiles(smi)
    if m is None:
        raise ConvertError("RDKit could not parse the generated SMILES")
    return Chem.MolToSmiles(m), cyclo, len(res)
