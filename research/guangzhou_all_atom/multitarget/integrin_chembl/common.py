"""Shared helpers: unit conversion, relation handling, structure standardisation, assay class, integrin-from-description."""
import re, math
import numpy as np

def nM_to_pact(nM):
    """pAct = 9 - log10(nM). nM must be > 0."""
    return 9.0 - math.log10(nM)

CENSOR_RIGHT = {">", ">="}   # IC50 > x  -> pAct <= bound  (weak, right-censored on the concentration axis)
CENSOR_LEFT = {"<", "<="}    # IC50 < x  -> pAct >= bound
def relation_class(rel):
    """'=' -> 'eq'; '>'/'>=' -> 'gt' (pAct upper bound); '<'/'<=' -> 'lt' (pAct lower bound); else None."""
    if rel == "=": return "eq"
    if rel in CENSOR_RIGHT: return "gt"
    if rel in CENSOR_LEFT: return "lt"
    return None

def norm_text(s):
    s = (s or "").lower().replace("α", "alpha").replace("β", "beta").replace("&alpha;", "alpha").replace("&beta;", "beta")
    s = re.sub(r"<[^>]+>", "", s)
    return re.sub(r"[\s\-_/\(\)]", "", s)

_PATS = [("avb3", r"alphavbeta3|avb3"), ("avb5", r"alphavbeta5|avb5"), ("avb6", r"alphavbeta6|avb6"), ("avb8", r"alphavbeta8|avb8"),
         ("avb1", r"alphavbeta1(?!\d)|avb1(?!\d)"), ("a5b1", r"alpha5beta1|a5b1"), ("aIIbb3", r"alphaiibbeta3|aiibb3|glycoproteiniib?iiia|gpiib?iiia"),
         ("a8b1", r"alpha8beta1|a8b1")]
def integrin_from_description(desc):
    """Return the unique heterodimer named in the first 300 chars of an assay description, else None."""
    t = norm_text((desc or "")[:300]); hits = {k for k, p in _PATS if re.search(p, t)}
    return hits.pop() if len(hits) == 1 else None

def assay_class(desc, assay_type):
    d = (desc or "").lower()
    if re.search(r"surface plasmon|\bspr\b|biacore|bio-?layer|\bbli\b", d): return "spr"
    if re.search(r"adhesion|migration|invasion|cells? |cell-based|huvec|k562|hek293|\bcho\b|reporter|platelet|aggregation|proliferation", d) and not re.search(r"purified|recombinant|immobili[sz]ed|coated", d): return "cell"
    if re.search(r"alphascreen|htrf|tr-?fret|fluorescence polari|\bfp\b|scintillation|\bspa\b|radioligand|\[125i\]|\[3h\]|\[?125\s?i|displacement of|flow cytom", d): return "homogeneous"
    if re.search(r"elisa|solid[- ]phase|microplate|microtiter|coated|plate|immobili[sz]ed|biotin|streptavidin|\bspra\b", d): return "solid_phase"
    return "cell" if assay_type == "F" else "other_binding"

def standardize_smiles(smi):
    """Return (mol, canonical_smiles, flat_inchikey, full_inchikey) of the largest fragment, neutralised; (None,)*4 on failure."""
    from rdkit import Chem
    from rdkit.Chem import inchi
    from rdkit.Chem.MolStandardize import rdMolStandardize
    from rdkit import RDLogger; RDLogger.DisableLog("rdApp.*")
    if not isinstance(smi, str) or not smi: return None, None, None, None
    m = Chem.MolFromSmiles(smi)
    if m is None or m.GetNumAtoms() == 0: return None, None, None, None
    frags = Chem.GetMolFrags(m, asMols=True)
    m = max(frags, key=lambda x: x.GetNumHeavyAtoms())
    try: m = rdMolStandardize.Uncharger().uncharge(m)
    except Exception: pass
    try: ik = inchi.MolToInchiKey(m)
    except Exception: ik = None
    if not ik: return None, None, None, None
    return m, Chem.MolToSmiles(m), ik[:14], ik
