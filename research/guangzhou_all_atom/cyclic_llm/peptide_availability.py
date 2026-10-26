"""peptide_availability.py — a deployable, honestly-scoped peptide *availability* predictor.

WHY THIS EXISTS
---------------
Affinity is not enough. Lemieux, Barbeau, Dibyachintan, Dubé, Lagüé & Landry (bioRxiv 2026,
doi:10.64898/2026.09.21.752983) measured >6,500 PBD(SH3)–peptide variants *in cells* (DHFR-PCA) vs.
*in vitro* (phage-display) and showed that **peptide "availability" — how much of the peptide is actually
free to engage its target in the cell — is largely set by the peptide's own hydrophobicity (and charge),
and it limits functional binding independently of intrinsic affinity.** A high-affinity peptide can be
functionally dead in cells if it is unavailable. Standard design pipelines ignore this.

WHAT THIS IS (and is NOT)
-------------------------
A sequence -> availability-risk model, fit on the Landry measured-availability data (PCA1, 7 domains: 4 SH3 + 3 PDZ).
- It is a **ranking / liability-flag** tool: "is this peptide at risk of low cellular availability?"
- It is **peptide-intrinsic**, so unlike binding/affinity it **transfers across domains** — validated by
  leave-one-domain-out: mean Spearman 0.40 (per-domain 0.23-0.49), i.e. a *moderate but robust* predictor.
  Treat scores as a risk ranking, NOT a precise quantitative oracle.
- Scope: trained on linear canonical-AA SH3-binding peptides. For cyclic / ncAA macrocycles (e.g. our
  αvβ6 RGD cyclics) it is an **approximation** over the canonical residues; ncAA content is flagged.

Model: availability_score = b0 + b_hydro*meanKD + b_charge*net_charge + b_fc*frac_charged
Coefficients fit by OLS on all PCA1 availability data (in-sample Spearman 0.72; LODO 0.40).
Provenance: github.com/Landrylab/Lemieux_et_al2026 (data/PCA1/med_avail_score.csv).
"""
from __future__ import annotations
import re
from dataclasses import dataclass
from typing import Optional

# Kyte-Doolittle hydrophobicity
_KD = {'A':1.8,'R':-4.5,'N':-3.5,'D':-3.5,'C':2.5,'Q':-3.5,'E':-3.5,'G':-0.4,'H':-3.2,'I':4.5,
       'L':3.8,'K':-3.9,'M':1.9,'F':2.8,'P':-1.6,'S':-0.8,'T':-0.7,'W':-0.9,'Y':-1.3,'V':4.2}
_CHG = {'R':1,'K':1,'H':0.1,'D':-1,'E':-1}

# Fit on Landry PCA1 measured availability (med_avail_score.csv); see module docstring.
_B0, _B_HYDRO, _B_CHARGE, _B_FC = 0.3318, -0.2541, -0.1479, -0.4793
# measured-availability 25th percentile -> 'low availability' liability threshold
_LOW_AVAIL_THRESHOLD = -0.142

_AA3to1 = {'ALA':'A','ARG':'R','ASN':'N','ASP':'D','CYS':'C','GLN':'Q','GLU':'E','GLY':'G','HIS':'H',
           'ILE':'I','LEU':'L','LYS':'K','MET':'M','PHE':'F','PRO':'P','SER':'S','THR':'T','TRP':'W',
           'TYR':'Y','VAL':'V'}


# Conservative surrogates for common non-canonical residues, mapped onto the canonical Kyte-Doolittle/charge space the model
# was fit on. These are APPROXIMATIONS (the training data contains no ncAAs): aromatic/aliphatic analogues take their
# nearest canonical parent; cationic diamino acids take Lys. Anything not listed is UNMAPPED (never silently dropped).
_NCAA_SURROGATE = {'2Nal': 'F', '1Nal': 'F', 'Phe4F': 'F', 'Phe4Cl': 'F', 'Phe4Br': 'F', 'hPhe': 'F', 'Bip': 'F',
                   'Cha': 'L', 'Nle': 'L', 'Nva': 'V', 'Abu': 'A', 'Aib': 'A', 'Orn': 'K', 'Dap': 'K', 'Dab': 'K',
                   'Hyp': 'P', 'Cit': 'Q'}
_ABSTAIN_UNMAPPED_FRAC = 0.25   # abstain if more than this fraction of residues cannot be mapped


def _resolve(tok):
    """token -> canonical letter or None. Order matters: exact names first so '[Met]' is never read as 'Me'+'t'."""
    if len(tok) == 1 and tok.upper() in _KD:
        return tok.upper()
    if tok.upper() in _AA3to1:                       # 3-letter canonical, e.g. Met / Phe
        return _AA3to1[tok.upper()]
    return _NCAA_SURROGATE.get(tok)


def _residues_from_helm(helm: str):
    """Parse a plain sequence or a cyclo(...) string into canonical-space letters.

    Returns (letters, n_ncaa, n_total, n_unmapped, n_nmethyl). D-enantiomer prefixes (d / D-) do not change the letter;
    N-methylation (NMe...) is COUNTED (n_nmethyl) rather than erased -- it is real chemistry the training data never saw."""
    s = helm.strip()
    if s.lower().startswith('cyclo(') or '-' in s or '[' in s:
        inner = s[s.find('(') + 1:s.rfind(')')] if '(' in s else s
        toks = [a or b for a, b in re.findall(r'\[([^\]]+)\]|([A-Za-z\*])', inner)]
    else:
        toks = list(s)
    letters, n_ncaa, n_unmapped, n_nme = [], 0, 0, 0
    for t in toks:
        letter = _resolve(t)
        if letter is not None:
            letters.append(letter); n_ncaa += int(t not in _KD and t.upper() not in _KD)   # surrogate / 3-letter => not plain 1-letter
            continue
        base, nme, flagged = t, False, False
        if base.startswith('NMe') and len(base) > 3:
            base, nme = base[3:], True
        elif base.startswith('N-methyl-'):
            base, nme = base[9:], True
        if base.startswith('D-') and len(base) > 2:
            base = base[2:]
        elif len(base) > 1 and base[0] == 'd' and _resolve(base[1:]) is not None:
            base = base[1:]
        letter = _resolve(base)
        if letter is None:
            n_unmapped += 1; n_ncaa += 1; continue
        letters.append(letter); n_ncaa += 1; n_nme += int(nme)
    return letters, n_ncaa, len(toks), n_unmapped, n_nme


def features(sequence: str):
    """Return (mean_hydrophobicity_KD, net_charge, frac_charged, n_ncaa, n_total, n_unmapped, n_nmethyl) or None."""
    letters, n_ncaa, n_total, n_unmapped, n_nme = _residues_from_helm(sequence)
    if not letters:
        return None
    mean_h = sum(_KD[a] for a in letters) / len(letters)
    net_charge = sum(_CHG.get(a, 0) for a in letters)
    frac_charged = sum(1 for a in letters if a in _CHG) / max(len(letters), 1)
    return mean_h, net_charge, frac_charged, n_ncaa, n_total, n_unmapped, n_nme


@dataclass
class AvailabilityResult:
    score: float                    # predicted availability (higher = more available); ranking value, not absolute. NaN if abstained
    low_availability: Optional[bool]  # True => flagged low; False => not flagged; None => ABSTAINED (do not read as "ok")
    mean_hydrophobicity: float
    net_charge: float
    frac_charged: float
    ncaa_fraction: float            # fraction of residues that are non-canonical (model is an approximation here)
    note: str
    abstain: bool = False
    unmapped_fraction: float = 0.0
    nmethyl_fraction: float = 0.0


def _abstain(note, **kw):
    nan = float('nan')
    return AvailabilityResult(nan, None, nan, nan, nan, kw.get('ncaa', nan), note, True, kw.get('unmapped', 0.0), kw.get('nme', 0.0))


def predict_availability(sequence: str) -> AvailabilityResult:
    """Predict cellular-availability risk for a peptide sequence or cyclo(...) string.

    `low_availability=True` flags a peptide likely to be functionally limited in cells by hydrophobicity/charge-driven
    unavailability, independent of its affinity (Lemieux...Landry 2026). A *ranking* risk flag (LODO Spearman ~0.40), not an
    oracle. It ABSTAINS (`abstain=True`, `low_availability=None`) when nothing parses or when too much of the peptide is
    chemistry the model cannot map -- an abstention must never be read as "not flagged".

    Direction of the fitted terms (do not paraphrase as "charged => unavailable"): hydrophobicity LOWERS the score; the
    fraction of charged residues LOWERS it; net charge enters with a NEGATIVE coefficient, so net-POSITIVE peptides score
    lower and net-NEGATIVE (anionic) peptides score HIGHER. N-methylation and surrogate ncAAs are approximations."""
    f = features(sequence)
    if f is None:
        return _abstain("no parsable residues")
    mean_h, net_charge, frac_charged, n_ncaa, n_total, n_unmapped, n_nme = f
    unm = n_unmapped / max(n_total, 1)
    ncaa_frac = n_ncaa / max(n_total, 1); nme_frac = n_nme / max(n_total, 1)
    if unm > _ABSTAIN_UNMAPPED_FRAC:
        return _abstain(f"{unm:.0%} of residues unmapped (unknown non-canonical chemistry)", ncaa=round(ncaa_frac, 3),
                        unmapped=round(unm, 3), nme=round(nme_frac, 3))
    score = _B0 + _B_HYDRO * mean_h + _B_CHARGE * net_charge + _B_FC * frac_charged
    bits = []
    if ncaa_frac: bits.append(f"{ncaa_frac:.0%} non-canonical (approximated by surrogates)")
    if nme_frac: bits.append(f"{nme_frac:.0%} N-methylated (chemistry absent from training data)")
    if unm: bits.append(f"{unm:.0%} unmapped (excluded from the averages)")
    note = "canonical-AA peptide" if not bits else "APPROXIMATION: " + "; ".join(bits)
    return AvailabilityResult(round(score, 4), bool(score < _LOW_AVAIL_THRESHOLD), round(mean_h, 3), round(net_charge, 2),
                              round(frac_charged, 3), round(ncaa_frac, 3), note, False, round(unm, 3), round(nme_frac, 3))


if __name__ == "__main__":
    import sys
    for s in sys.argv[1:] or ["cyclo(W-R-G-D-L-T-F-[dP]-[NMeV])", "RGKLMPGRG", "GSLASLGIGRR"]:
        r = predict_availability(s)
        flag = "ABSTAIN" if r.abstain else ("LOW-AVAIL ⚠" if r.low_availability else "ok")
        print(f"{s:34s} score={r.score:+.3f} [{flag}] meanH={r.mean_hydrophobicity:+.2f} "
              f"charge={r.net_charge:+.1f} fracChg={r.frac_charged:.2f} ncaa={r.ncaa_fraction:.0%}  ({r.note})")
