"""renal_features.py — DETERMINISTIC sequence -> interpretable renal-retention features.

The renal thesis predicts kidney retention from INTERPRETABLE structure features (programme doc:
"NO learned embeddings; at this n, embeddings memorise"). The single most mechanistic feature is
NET POSITIVE CHARGE: megalin/cubilin-mediated tubular reabsorption of the filtered peptide scales
with net cationic charge (Behr, Akizawa, Vegt et al.). This module computes that — and the
supporting charge features — deterministically from sequence + chelator, so the Gate-A baseline
(net_charge alone) is COMPUTABLE and the surrogate has real inputs. No fabrication: charge is a
Henderson-Hasselbalch calculation on sourced sequences; the sequence's citation is the provenance.

Scope: standard + common non-standard radiopeptide residues, head-to-tail vs linear termini,
and the net charge contributed by the metal-chelate (e.g. DOTA-M(III) complex ~ -1).
"""
from __future__ import annotations
import math
from dataclasses import dataclass
from typing import Optional

# --- side-chain pKa (Lehninger / EMBOSS consensus) + termini ---
PKA = {"K": 10.5, "R": 12.5, "H": 6.0, "D": 3.9, "E": 4.1, "C": 8.3, "Y": 10.1}
PKA_NTERM, PKA_CTERM = 8.0, 3.1
POS_RES, NEG_RES = {"K", "R", "H"}, {"D", "E", "C", "Y"}

# --- metal-chelate net charge contribution at pH 7.4 (complex formed with the radiometal) ---
# FIX 1 (reviewer C): the complex charge is NOT radiometal-blind. DOTA's residual charge depends on the
# metal's oxidation state (M(III) occupies 3 of 4 carboxylates -> -1; M(II) occupies only 2 -> -2). So the
# complex charge is keyed on (chelator, metal_oxidation_state), the oxidation state being derived from the
# `radiometal` field. An unknown (chelator, oxidation) combination is FLAGGED (excluded), never guessed.
#
# radiometal -> oxidation state (coordination charge of the cation inside the chelate).
_METAL_OXIDATION = {
    # +3 lanthanides / group-3 / main-group(III)
    "177Lu": 3, "90Y": 3, "86Y": 3, "88Y": 3, "225Ac": 3, "161Tb": 3, "149Tb": 3, "152Tb": 3, "155Tb": 3,
    "68Ga": 3, "67Ga": 3, "111In": 3, "114mIn": 3, "44Sc": 3, "43Sc": 3, "47Sc": 3, "213Bi": 3, "134Ce": 3,
    # +2 transition / main-group(II)
    "64Cu": 2, "67Cu": 2, "61Cu": 2, "62Cu": 2, "52Mn": 2, "203Pb": 2, "212Pb": 2, "213Pb": 2,
    # +4
    "89Zr": 4, "227Th": 4,
    # 99mTc oxidation state inside its chelate is core-dependent (Tc(V)=O, Tc(I)-tricarbonyl, ...) -> None
    "99mTc": None, "94mTc": None,
}
# radiohalogens (not chelated — bound by a C-X bond); no metal-complex charge contribution.
_RADIOHALOGENS = {"18F", "125I", "123I", "124I", "131I", "211At", "76Br", "77Br"}

# (chelator, oxidation_state) -> (complex_charge, flagged). Only DEFENSIBLE combinations are listed;
# anything else is flagged (returned as unknown -> construct excluded from the computed-charge analysis).
_COMPLEX_CHARGE_BY_OX = {
    ("DOTA", 3): -1.0,   # 4 COOH; M(III) uses 3 -> -1   (Lu/Y/Ga/Ac/Tb/In/Sc)
    ("DOTA", 2): -2.0,   # M(II) uses 2 -> -2            (Cu-64, Pb-203/212, Mn-52)
    ("DOTAGA", 3): -2.0, # 5 COOH; M(III) -> -2
    ("NOTA", 3): 0.0,    # 3 COOH; M(III) uses 3 -> 0    (Ga-68 III)
    ("NODAGA", 3): -1.0,
    ("DTPA", 3): -2.0,   # acyclic; 5 COOH, M(III) -> -2
    ("CHX-A-DTPA", 3): -2.0,
    ("TRAP", 3): -2.0,   # triphosphinate, Ga(III) -> ~ -2
    ("macropa", 3): -1.0,
    ("TCMC", 2): -2.0,   # Pb-203/212 (DOTA/TCMC II) -> -2
    ("DFO", 4): 1.0,     # Zr-89(IV): 3 hydroxamate(-3) + Zr(+4) -> ~ +1 (neutral/+, defensible for DFO-Zr)
    ("CB-TE2A", 2): 0.0, # cross-bridged cyclam-diacetate + Cu(II): 2 COOH(-2)+Cu(+2) -> neutral
}


def _norm_chelator(chelator):
    if chelator is None:
        return None
    c = str(chelator).strip()
    # canonicalize the DTPA family naming (double-prime / apostrophe variants)
    repl = c.replace("″", "").replace("''", "").replace('"', "").replace("’", "")
    repl = repl.replace("CHX-A-DTPA", "CHX-A-DTPA").replace("CHX-A''-DTPA", "CHX-A-DTPA")
    if repl.upper().startswith("CHX-A") and "DTPA" in repl.upper():
        return "CHX-A-DTPA"
    return c


def complex_charge(chelator, radiometal):
    """Return (complex_charge, flagged) for a (chelator, radiometal) pair at pH 7.4.

    flagged=True means the (chelator, oxidation-state) combination is not defensibly known -> the caller
    must EXCLUDE the construct from the computed-charge analysis rather than guess a charge (reviewer C).
    No chelator / a radiohalogen vector -> 0.0 (there is genuinely no metal chelate), not flagged.
    """
    name = _norm_chelator(chelator)
    if name in (None, ""):
        return 0.0, False                                 # no chelate at all -> no complex charge
    metal = (str(radiometal).strip() if radiometal is not None else "")
    if metal in _RADIOHALOGENS:
        return 0.0, False                                 # halogen vector; the named "chelator" carries no metal
    ox = _METAL_OXIDATION.get(metal)
    if ox is None:
        return None, True                                 # unknown/ambiguous metal oxidation state -> flag
    key = (name, ox)
    if key in _COMPLEX_CHARGE_BY_OX:
        return _COMPLEX_CHARGE_BY_OX[key], False
    return None, True                                     # unknown (chelator, oxidation) combo -> flag


def _charge_at_pH(seq: str, pH: float, cyclic_headtail: bool,
                  n_term_conjugated: bool = False, cys_disulfide: bool = False,
                  alcohol_cterm: bool = False) -> float:
    """Henderson-Hasselbalch net charge of the peptide backbone + side chains.

    n_term_conjugated (FIX 3): the N-terminal alpha-amine is amide-bonded to the chelator -> no free cation.
    cys_disulfide    (FIX 4): Cys residues are disulfide-cyclized -> non-ionizable thiols, contribute 0.
    alcohol_cterm    (FIX 5): C-terminus is an alcohol (Thr-ol) -> no carboxylate, no -1 C-term term.
    """
    q = 0.0
    if not cyclic_headtail:                       # free termini only if not head-to-tail cyclized
        if not n_term_conjugated:                         # FIX 3: suppress N-term amine when chelator-conjugated
            q += 1.0 / (1.0 + 10 ** (pH - PKA_NTERM))     # N-term (cationic)
        if not alcohol_cterm:                             # FIX 5: no C-term carboxylate on alcohol-terminated peptides
            q += -1.0 / (1.0 + 10 ** (PKA_CTERM - pH))    # C-term (anionic)
    for aa in seq.upper():
        if aa == "C" and cys_disulfide:                   # FIX 4: disulfide Cys is non-ionizable
            continue
        if aa in POS_RES:
            q += 1.0 / (1.0 + 10 ** (pH - PKA[aa]))
        elif aa in NEG_RES:
            q += -1.0 / (1.0 + 10 ** (PKA[aa] - pH))
    return q


@dataclass
class RenalFeatures:
    net_charge_pH74: float
    n_lys: int
    n_arg: int
    n_his: int
    n_asp_glu: int
    basic_residue_frac: float
    seq_len: int
    chelator_charge: float
    net_charge_with_chelate: float


def featurize(seq: str, chelator: Optional[str] = None, cyclic_headtail: bool = False,
              radiometal: Optional[str] = None, n_term_conjugated: bool = False,
              cys_disulfide: bool = False, alcohol_cterm: bool = False) -> Optional[RenalFeatures]:
    """Compute interpretable renal features from a (sourced) one-letter sequence + chelator.

    seq: one-letter AA sequence (non-standard residues that are non-ionizable -> pass as 'X', ignored).
    chelator/radiometal: resolve the metal-complex charge via complex_charge() (oxidation-state aware).
    cyclic_headtail: True if backbone-cyclized (no free N/C termini).
    n_term_conjugated / cys_disulfide / alcohol_cterm: see _charge_at_pH (FIX 3/4/5).
    Returns None when the (chelator, radiometal) complex charge is unknown (flagged) -> exclude the construct.
    """
    s = seq.upper()
    chel_q, flagged = complex_charge(chelator, radiometal)
    if flagged:
        return None                                       # FIX 1: unknown complex charge -> exclude, don't guess
    pep_q = _charge_at_pH(s, 7.4, cyclic_headtail, n_term_conjugated, cys_disulfide, alcohol_cterm)
    n_lys, n_arg, n_his = s.count("K"), s.count("R"), s.count("H")
    n_neg = s.count("D") + s.count("E")
    n_basic = n_lys + n_arg + n_his
    L = max(len([c for c in s if c.isalpha()]), 1)
    return RenalFeatures(
        net_charge_pH74=round(pep_q, 3), n_lys=n_lys, n_arg=n_arg, n_his=n_his,
        n_asp_glu=n_neg, basic_residue_frac=round(n_basic / L, 3), seq_len=L,
        chelator_charge=chel_q, net_charge_with_chelate=round(pep_q + chel_q, 3))


# --- SOURCED sequences for seed constructs (provenance = the cited paper for each sequence) ---
# Only sequences I can attribute. Non-ionizable non-standard residues collapsed to 'X' (charge-neutral).
# These make net_charge COMPUTABLE for the Gate-A baseline — the charge itself is then deterministic.
SEQUENCES = {
    # A20FMDV2: FMDV VP1 20-mer, the canonical linear αvβ6 ligand (Hausner et al., Cancer Res 2007;67:7833).
    # N-terminally DOTA-conjugated (FIX 3: no free alpha-amine).
    "Lu177-A20FMDV2": {"seq": "NAVPNLRGDLQVLAQKVART", "chelator": "DOTA", "radiometal": "177Lu",
                       "cyclic_headtail": False, "n_term_conjugated": True},
    # DOTATATE octapeptide: DOTA-D-Phe-cyclo[Cys-Tyr-D-Trp-Lys-Thr-Cys]-Thr(acid) (Kwekkeboom/Strosberg)
    # one-letter: F C Y W K T C T — disulfide-cyclized Cys (FIX 4), N-terminally DOTA-conjugated (FIX 3).
    "Lu177-DOTATATE": {"seq": "FCYWKTCT", "chelator": "DOTA", "radiometal": "177Lu", "cyclic_headtail": False,
                       "n_term_conjugated": True, "cys_disulfide": True},
    # DOTATOC = Tyr3-octreotide: Thr-ol C-terminus (alcohol; FIX 5), disulfide Cys (FIX 4), N-conjugated (FIX 3)
    "Lu177-DOTATOC": {"seq": "FCYWKTCT", "chelator": "DOTA", "radiometal": "177Lu", "cyclic_headtail": False,
                      "n_term_conjugated": True, "cys_disulfide": True, "alcohol_cterm": True},
    # PSMA-617: Glu-urea-Lys pharmacophore + Nal-tranexamic linker + DOTA (one ionizable Lys + Glu);
    # N-terminally DOTA-conjugated (the Glu-urea-Lys carries no free alpha-amine). 177Lu(III) -> DOTA -1.
    "Lu177-PSMA-617": {"seq": "EK", "chelator": "DOTA", "radiometal": "177Lu", "cyclic_headtail": False,
                       "n_term_conjugated": True},
}


def features_for(construct_id: str) -> Optional[RenalFeatures]:
    rec = SEQUENCES.get(construct_id)
    if not rec:
        return None
    return featurize(rec["seq"], rec["chelator"], rec["cyclic_headtail"], radiometal=rec.get("radiometal"),
                     n_term_conjugated=rec.get("n_term_conjugated", False),
                     cys_disulfide=rec.get("cys_disulfide", False),
                     alcohol_cterm=rec.get("alcohol_cterm", False))


# chemotypes whose backbone is head-to-tail cyclized (no free termini)
_CYCLIC_CHEMOTYPES = {"cyclic_RGD", "cyclic_peptide", "cyclic_octapeptide", "bombesin_antagonist", "knottin"}


import re as _re
_ONE_LETTER = _re.compile(r"^[ACDEFGHIKLMNPQRSTVWYX]+$")


def is_clean_one_letter(seq) -> bool:
    """A sequence usable by featurize must be a pure one-letter peptide string. Descriptive strings
    like 'DOTA-D-Phe-cyclo[Cys-Tyr-...]' are NOT — passing them to featurize would miscount residues."""
    return isinstance(seq, str) and len(seq) >= 2 and bool(_ONE_LETTER.match(seq.upper()))


def _features_from_smiles(smiles: str, chelator: Optional[str],
                          radiometal: Optional[str] = None) -> Optional[RenalFeatures]:
    """Small-molecule path: net charge from SMILES (renal_smiles_charge), group counts mapped to the
    same feature slots. seq_len=0 marks a non-peptide (modality flag the surrogate can use).

    FIX 1: the metal-complex charge is resolved here (oxidation-state aware) rather than trusting the
    metal-blind value from smiles_net_charge; an unknown (chelator, oxidation) combo -> None (excluded)."""
    try:
        from renal_smiles_charge import smiles_net_charge
    except Exception:
        return None
    r = smiles_net_charge(smiles, chelator)        # raw ligand HH charge with chelator atoms excluded
    if r is None:
        return None
    chel_q, flagged = complex_charge(chelator, radiometal)
    if flagged:
        return None                                # FIX 1: don't guess an unknown complex charge
    raw = r["net_charge_pH74"]                      # ligand charge; chelator atoms already excluded (claimed)
    invivo = round(raw + chel_q, 3)
    g = r["groups"]
    n_lys, n_arg, n_his = g.get("aliphatic_amine", 0), g.get("guanidine", 0), g.get("imidazole", 0)
    n_neg = g.get("carboxylic_acid", 0) + g.get("sulfonic_acid", 0) + g.get("tetrazole", 0)
    n_basic = n_lys + n_arg + n_his
    return RenalFeatures(
        net_charge_pH74=raw, n_lys=n_lys, n_arg=n_arg, n_his=n_his, n_asp_glu=n_neg,
        basic_residue_frac=round(n_basic / max(n_basic + n_neg, 1), 3), seq_len=0,
        chelator_charge=chel_q, net_charge_with_chelate=invivo)


# --- FIX 3/4/5 inference helpers (from the row's OWN annotated fields) ---
# chelator names that carry a radiometal (a real metal chelate), vs prosthetic groups / none.
_REAL_CHELATORS = {"DOTA", "DOTAGA", "NOTA", "NODAGA", "DTPA", "CHX-A-DTPA", "TRAP", "macropa",
                   "TCMC", "DFO", "CB-TE2A", "AP", "KP", "N4", "HYNIC", "NODAGA"}
# chemotype PREFIX whose two Cys are disulfide-bridged (non-ionizable thiols) — the SSTR2 octreotide family.
# Matches both the agonists ("cyclic_octapeptide") and the antagonists ("cyclic_octapeptide_antagonist",
# e.g. LM3 / JR11-satoreotide), which are equally disulfide-cyclized.
_DISULFIDE_CHEMOTYPE_PREFIX = "cyclic_octapeptide"


def _is_n_term_conjugated(row: dict) -> bool:
    """FIX 3: chelator amide-conjugated to the N-terminal alpha-amine -> no free N-terminal cation.
    Explicit annotation wins; otherwise a chelator-bearing peptide is treated as N-conjugated (the norm
    for DOTA-TATE/-TOC/-NOC etc.)."""
    if "n_term_free" in row:          # explicit annotation: a free N-terminus (side-chain conjugation)
        return not bool(row["n_term_free"])
    if "n_term_conjugated" in row:
        return bool(row["n_term_conjugated"])
    chel = _norm_chelator(row.get("chelator"))
    return chel not in (None, "")     # chelator-bearing peptide -> N-conjugated by default


def _is_disulfide_cys(row: dict) -> bool:
    """FIX 4: Cys residues are disulfide-cyclized (octreotide/octreotate/SSTR2 family)."""
    if "cys_disulfide" in row:
        return bool(row["cys_disulfide"])
    if "disulfide" in row:
        return bool(row["disulfide"])
    return str(row.get("chemotype") or "").startswith(_DISULFIDE_CHEMOTYPE_PREFIX)


def _is_alcohol_cterm(row: dict) -> bool:
    """FIX 5: alcohol (Thr-ol) C-terminus -> no carboxylate. Octreotide-type (-TOC/-NOC/octreotide)
    end in Thr-ol; octreotate (-TATE) is the free acid. Explicit annotation wins."""
    if "alcohol_cterm" in row:
        return bool(row["alcohol_cterm"])
    if "c_term" in row:
        return str(row["c_term"]).lower() in ("ol", "alcohol", "thr-ol", "threoninol")
    cid = str(row.get("construct_id", "")).upper()
    if "TATE" in cid or "OCTREOTATE" in cid:     # octreotate = carboxylic acid
        return False
    return ("TOC" in cid) or ("NOC" in cid) or ("OCTREOTIDE" in cid)


def features_for_row(row: dict) -> Optional[RenalFeatures]:
    """Featurize from a corpus row's OWN sourced fields. Priority: (0) a PAPER-STATED net charge
    (authoritative — some charge differences live in terminal mods that a one-letter sequence can't
    encode, e.g. the MC1R Ac/Suc/amide ladder), (1) clean one-letter sequence (HH), (2) SMILES (HH),
    (3) curated SEQUENCES dict. None if nothing usable."""
    stated = row.get("net_charge_stated")
    if isinstance(stated, (int, float)):
        seq = row.get("sequence")
        if is_clean_one_letter(seq):
            s = seq.upper()
            n_lys, n_arg, n_his = s.count("K"), s.count("R"), s.count("H")
            n_neg = s.count("D") + s.count("E"); L = max(len(s), 1)
        else:
            n_lys = n_arg = n_his = n_neg = 0; L = 1
        return RenalFeatures(net_charge_pH74=float(stated), n_lys=n_lys, n_arg=n_arg, n_his=n_his,
            n_asp_glu=n_neg, basic_residue_frac=round((n_lys + n_arg + n_his) / L, 3),
            seq_len=len(row["sequence"]) if is_clean_one_letter(row.get("sequence")) else 0,
            chelator_charge=0.0, net_charge_with_chelate=float(stated))
    seq = row.get("sequence")
    if is_clean_one_letter(seq):
        cyclic = bool(row.get("cyclic_headtail", row.get("chemotype") in _CYCLIC_CHEMOTYPES))
        return featurize(seq, row.get("chelator"), cyclic, radiometal=row.get("radiometal"),
                         n_term_conjugated=_is_n_term_conjugated(row),   # FIX 3
                         cys_disulfide=_is_disulfide_cys(row),           # FIX 4
                         alcohol_cterm=_is_alcohol_cterm(row))           # FIX 5
    smi = row.get("smiles")
    if isinstance(smi, str) and len(smi) >= 4:
        f = _features_from_smiles(smi, row.get("chelator"), row.get("radiometal"))
        if f is not None:
            return f
    return features_for(row.get("construct_id", ""))


if __name__ == "__main__":
    # sanity: known-charge cases
    print("=== renal_features sanity (net charge @ pH 7.4) ===")
    cases = [("KKKK", False, "tetra-Lys -> strongly cationic"),
             ("EEEE", False, "tetra-Glu -> strongly anionic"),
             ("GGGG", True, "cyclic Gly4 -> ~0")]
    for seq, cyc, note in cases:
        f = featurize(seq, None, cyc)
        print(f"  {seq:6s} cyclic={cyc!s:5s} net={f.net_charge_pH74:+.2f}  ({note})")
    print("\n=== seed constructs with sourced sequences ===")
    for cid in SEQUENCES:
        f = features_for(cid)
        print(f"  {cid:22s} net(pep)={f.net_charge_pH74:+.2f}  +chelate={f.net_charge_with_chelate:+.2f}  "
              f"Lys={f.n_lys} Arg={f.n_arg} basic_frac={f.basic_residue_frac}")
    print("\nNet charge is now COMPUTABLE for these -> the Gate-A baseline (net_charge alone) has real inputs.")
    print("Each sequence is cited (provenance = the paper); charge is a deterministic HH calculation, not a label.")
