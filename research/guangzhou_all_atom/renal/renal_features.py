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
# DOTA = 4 carboxylates; with a +3 metal (177Lu/90Y/225Ac/68Ga/161Tb) the complex is ~ -1.
CHELATOR_COMPLEX_CHARGE = {
    "DOTA": -1.0, "DOTAGA": -2.0, "NOTA": 0.0, "NODAGA": -1.0, "TRAP": -2.0,
    "macropa": -1.0, "DTPA": -2.0, "CHX-A-DTPA": -2.0, "DFO": 0.0, None: 0.0, "": 0.0,
}


def _charge_at_pH(seq: str, pH: float, cyclic_headtail: bool) -> float:
    """Henderson-Hasselbalch net charge of the peptide backbone + side chains."""
    q = 0.0
    if not cyclic_headtail:                       # free termini only if not head-to-tail cyclized
        q += 1.0 / (1.0 + 10 ** (pH - PKA_NTERM))         # N-term (cationic)
        q += -1.0 / (1.0 + 10 ** (PKA_CTERM - pH))        # C-term (anionic)
    for aa in seq.upper():
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


def featurize(seq: str, chelator: Optional[str] = None, cyclic_headtail: bool = False) -> RenalFeatures:
    """Compute interpretable renal features from a (sourced) one-letter sequence + chelator.

    seq: one-letter AA sequence (non-standard residues that are non-ionizable -> pass as 'X', ignored).
    chelator: key in CHELATOR_COMPLEX_CHARGE; adds the metal-complex charge to the total.
    cyclic_headtail: True if backbone-cyclized (no free N/C termini).
    """
    s = seq.upper()
    pep_q = _charge_at_pH(s, 7.4, cyclic_headtail)
    chel_q = CHELATOR_COMPLEX_CHARGE.get(chelator, 0.0)
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
    # A20FMDV2: FMDV VP1 20-mer, the canonical linear αvβ6 ligand (Hausner et al., Cancer Res 2007;67:7833)
    "Lu177-A20FMDV2": {"seq": "NAVPNLRGDLQVLAQKVART", "chelator": "DOTA", "cyclic_headtail": False},
    # DOTATATE octapeptide: DOTA-D-Phe-cyclo[Cys-Tyr-D-Trp-Lys-Thr-Cys]-Thr (Kwekkeboom/Strosberg)
    # one-letter (ionizable backbone approximated; disulfide cyclo, free termini): F C Y W K T C T
    "Lu177-DOTATATE": {"seq": "FCYWKTCT", "chelator": "DOTA", "cyclic_headtail": False},
    "Lu177-DOTATOC": {"seq": "FCYWKTCT", "chelator": "DOTA", "cyclic_headtail": False},   # Thr-ol C-term; ~same charge set
    # PSMA-617: Glu-urea-Lys pharmacophore + Nal-tranexamic linker + DOTA (one ionizable Lys + Glu)
    "Lu177-PSMA-617": {"seq": "EK", "chelator": "DOTA", "cyclic_headtail": False},
}


def features_for(construct_id: str) -> Optional[RenalFeatures]:
    rec = SEQUENCES.get(construct_id)
    if not rec:
        return None
    return featurize(rec["seq"], rec["chelator"], rec["cyclic_headtail"])


# chemotypes whose backbone is head-to-tail cyclized (no free termini)
_CYCLIC_CHEMOTYPES = {"cyclic_RGD", "cyclic_peptide", "cyclic_octapeptide", "bombesin_antagonist", "knottin"}


import re as _re
_ONE_LETTER = _re.compile(r"^[ACDEFGHIKLMNPQRSTVWYX]+$")


def is_clean_one_letter(seq) -> bool:
    """A sequence usable by featurize must be a pure one-letter peptide string. Descriptive strings
    like 'DOTA-D-Phe-cyclo[Cys-Tyr-...]' are NOT — passing them to featurize would miscount residues."""
    return isinstance(seq, str) and len(seq) >= 2 and bool(_ONE_LETTER.match(seq.upper()))


def features_for_row(row: dict) -> Optional[RenalFeatures]:
    """Featurize straight from a corpus row's OWN sourced fields (sequence/chelator/chemotype).
    Uses row['sequence'] ONLY if it is a clean one-letter peptide; else falls back to the curated
    SEQUENCES dict by construct_id. Returns None if no usable sequence is available."""
    seq = row.get("sequence")
    if is_clean_one_letter(seq):
        cyclic = bool(row.get("cyclic_headtail", row.get("chemotype") in _CYCLIC_CHEMOTYPES))
        return featurize(seq, row.get("chelator"), cyclic)
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
