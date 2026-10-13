"""Operationalizes acceptance_criteria.yaml (Candidate Design Requirements v1.0/1.1) as a computable gate.
αvβ6 sequence-evaluable hard gates: H1 RGD, H2 RGDL, H3 turn+N-methyl, H4 aromatic flanks (CANONICAL or
ncAA aromatics), H5 single Lys chelator handle (+cyclic), H8 FTO-genus flag (literal vs ncAA-divergent).
ncAA-aware (v1.1 A4): classifies non-canonical residues at the free positions. Docking gates H6/H7 pending."""

AROM_CANON = {"F", "Y", "W"}
# ncAA / variant aromatics that satisfy the aromatic-flank requirement (and add composition-of-matter novelty)
AROM_NCAA = {"2Nal", "1Nal", "Nal", "Phe4F", "4FPhe", "Phe4Cl", "4ClPhe", "Phe34F2", "hPhe", "Bip", "Tyr", "Trp", "Phe"}
SMALL_NCAA = {"Aib", "Abu", "Sar"}   # small specificity-knob residues (+ canonical A, G, S)


def raw_tokens(helm):
    """Ordered residue token-cores, preserving multi-char ncAA (2Nal, NMeK, dP)."""
    s = helm.strip()
    inner = s[s.index("(") + 1: s.rindex(")")] if s.lower().startswith("cyclo(") else s.split(" (")[0]
    out = []
    for t in inner.split("-"):
        t = t.strip()
        if t.startswith("[") and t.endswith("]"):
            t = t[1:-1]
        if t:
            out.append(t)
    return out


def _strip_mods(core):
    c = core
    if c.startswith("NMe"):
        c = c[3:]
    if c.startswith("d") and len(c) > 1 and c[1].isupper():
        c = c[1:]
    return c


def _is_arom(core):
    c = _strip_mods(core)
    return c in AROM_CANON or c in AROM_NCAA


def _canon1(core):
    c = _strip_mods(core)
    return c if (len(c) == 1 and c.isalpha()) else "X"   # canonical 1-letter; ncAA -> X (R/G/D/L preserved)


def _is_lys(core):
    return _strip_mods(core) == "K"


def avb6_gate(helm):
    toks = raw_tokens(helm)
    seq1 = "".join(_canon1(t) for t in toks)
    w = seq1 + seq1[:6]
    g = {}
    g["H1_RGD"] = "RGD" in w
    g["H2_RGDL"] = "RGDL" in w
    has_dpro = any(t == "dP" or (t.startswith("d") and _strip_mods(t) == "P") for t in toks)
    has_nme = any(t.startswith("NMe") for t in toks)
    g["H3_turn_nmethyl"] = has_dpro and has_nme
    # P1 = token before the R of RGDL; P7 = token before the D-Pro turn
    i = w.find("RGDL")
    p1 = toks[i - 1] if i > 0 else (toks[-1] if i == 0 else None)
    dpi = next((j for j, t in enumerate(toks) if t == "dP" or (t.startswith("d") and _strip_mods(t) == "P")), None)
    p7 = toks[dpi - 1] if dpi else None
    g["_P1"], g["_P7"] = p1, p7
    g["H4_aromatic_flanks"] = bool(p1 and p7 and _is_arom(p1) and _is_arom(p7))
    nlys = sum(1 for t in toks if _is_lys(t))
    g["_n_lys"] = nlys
    cyclic = helm.strip().lower().startswith("cyclo(")
    g["H5_single_handle"] = cyclic and nlys == 1
    # H8 FTO: literal canonical-flank genus vs ncAA-divergent matter
    if g["H2_RGDL"] and has_dpro and has_nme and p1 and p7 and _is_arom(p1) and _is_arom(p7):
        both_canon = (p1 in AROM_CANON) and (p7 in AROM_CANON)
        g["H8_fto"] = ("LITERAL nonapeptide genus (canonical F/Y/W flanks) -> patent counsel" if both_canon
                       else "ncAA-divergent from literal published sequences -> counsel on genus SCOPE (ncAA flanks may fall outside narrow composition claims)")
    else:
        g["H8_fto"] = "n/a"
    g["_ncaa_free"] = [t for t in (p1, p6_of(toks), p7) if t and _strip_mods(t) not in (AROM_CANON | {"A", "G", "S"})]
    g["PASS_H1_H5"] = all([g["H1_RGD"], g["H2_RGDL"], g["H3_turn_nmethyl"], g["H4_aromatic_flanks"], g["H5_single_handle"]])
    g["H6_H7_docking"] = "pending (dock vs avb6 + avb8/avb3/avb5/a5b1, controls in-batch, A2 validation first)"
    return g


def p6_of(toks):
    """P6 = token between L (of RGDL) and P7 (before the turn). Returns the specificity-knob residue."""
    seq1 = "".join(_canon1(t) for t in toks)
    i = (seq1 + seq1[:6]).find("RGDL")
    # RGDL occupies i..i+3; P6 is i+4
    return toks[i + 4] if (i >= 0 and i + 4 < len(toks)) else None
