"""Monomer-token classifier for CycPeptMPDB HELM monomer names (385 distinct tokens).
Topology ground truth comes from the HELM connection string; token classes are rule-based and audited against SMILES (audit_annotation.py)."""
import re

CAP_N_RE = re.compile(r".+-$")          # ac-, glyco-, deca-, Mono21-, Mono22-, medl-
CAP_C_RE = re.compile(r"^-.+")          # -pip, -pyrro, -nme2, -aze, -mor
UNKNOWN_RE = re.compile(r"^Mono\d+$")
EXT_BACKBONE = {"Bal", "bHph", "GABA", "5-Ava"}        # beta/gamma/omega amino acids (backbone longer than alpha)
ALPHA_DISUB = {"Ac5c", "Aib", "Ac6c", "Ac4c", "Ac3c"}
PRO_LIKE = {"P", "Pip", "Aze", "Hyp"}
AROMATIC_CORE = {"F", "Y", "W", "H", "Phe", "Tyr", "Trp", "His", "Nal", "1-Nal", "2-Nal", "Hph", "Phg", "Pal", "3Pal", "Pye", "Tza", "bHph", "2Abz"}
POSITIVE_CORE = {"K", "R", "Lys", "Arg", "Orn", "Dab", "Dap"}
NEGATIVE_EXACT = {"D", "E", "Asp", "Glu"}
POLAR_CORE = {"S", "T", "N", "Q", "C", "Ser", "Thr", "Asn", "Gln", "Cys", "Hse", "Hyp"}
ALIPHATIC_CORE = {"A", "L", "I", "V", "M", "Ala", "Leu", "Ile", "Val", "Met", "Nle", "Nva", "Abu", "Cha", "Chg", "Aib", "Ac5c", "Bmt", "aIle", "Bal", "GABA", "5-Ava", "Gly"}


def _core(base):
    return re.split(r"[(_]", base)[0]


def classify(tok):
    r = dict(tok=tok, kind="residue", base=tok, is_D=False, is_nme=False, is_nalkyl=False, is_peptoid=False, is_ext_backbone=False,
             is_cap_n=False, is_cap_c=False, is_unknown=False, is_backbone_mod=False, is_alpha_disub=False, is_pro_like=False,
             is_sidechain_mod=False, comp="other")
    if CAP_C_RE.match(tok):
        r.update(kind="cap_c", is_cap_c=True, comp="cap"); return r
    if CAP_N_RE.match(tok):
        r.update(kind="cap_n", is_cap_n=True, comp="cap"); return r
    if UNKNOWN_RE.match(tok):
        r.update(kind="unknown", is_unknown=True, comp="unknown"); return r
    t = tok
    if re.match(r"^d?\(N->O\)", t):
        r["is_backbone_mod"] = True; t = re.sub(r"\(N->O\)", "", t)
    if t == "Sar":
        r.update(is_nme=True, base="Gly", comp="aliphatic"); return r
    m = re.match(r"^Me_(.+)$", t) or re.match(r"^me([A-Z].*)$", t)
    if m:
        r["is_nme"] = True; t = m.group(1)
    else:
        m = re.match(r"^Et_(.+)$", t)
        if m: r["is_nalkyl"] = True; t = m.group(1)
    if re.match(r"^d(?=[A-Z0-9(])", t):
        r["is_D"] = True; t = t[1:]
    r["base"] = t
    if t.endswith("_Gly"):
        r["is_peptoid"] = True; r["is_nalkyl"] = True
    core = _core(t)
    r["is_ext_backbone"] = core in EXT_BACKBONE or t in EXT_BACKBONE
    r["is_alpha_disub"] = core in ALPHA_DISUB
    r["is_pro_like"] = core in PRO_LIKE
    r["is_sidechain_mod"] = ("(" in t) or ("_" in t and not r["is_peptoid"])
    if r["is_peptoid"]:
        subst = t[:-4]
        r["comp"] = "aromatic" if re.search(r"Bn|Ph|pyridyl|indol", subst) else "aliphatic"
    elif r["is_pro_like"]:
        r["comp"] = "proline"
    elif core in AROMATIC_CORE or re.search(r"indol|pyridyl|Ph\b|Phe|Tyr|Trp", t):
        r["comp"] = "aromatic"
    elif core in POSITIVE_CORE:
        r["comp"] = "positive"
    elif t in NEGATIVE_EXACT or re.match(r"^(Glu|Asp)\((3R-Me|3-Me)\)", t):
        r["comp"] = "negative"
    elif core in {"D", "E", "Asp", "Glu"}:
        r["comp"] = "polar"          # modified acid side chain (ester, amide, piperidide): neutral, polar
    elif core in POLAR_CORE:
        r["comp"] = "polar"
    elif core in ALIPHATIC_CORE or re.match(r"^Gly\(c", t):
        r["comp"] = "aliphatic"
    return r
