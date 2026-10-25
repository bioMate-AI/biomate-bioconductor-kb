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
A sequence -> availability-risk model, fit on the Landry measured-availability data (PCA1, 7 SH3 domains).
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


def _residues_from_helm(helm: str):
    """Extract per-residue canonical-AA letters from a HELM-ish cyclo(...) string or a plain sequence.
    ncAA tokens ([dP], [NMeK], [Nle], ...) are mapped to their canonical parent where obvious, else flagged.
    Returns (letters, n_ncaa, n_total)."""
    s = helm.strip()
    if s.lower().startswith('cyclo(') or '-' in s or '[' in s:
        inner = s[s.find('(')+1:s.rfind(')')] if '(' in s else s
        toks = re.findall(r'\[([^\]]+)\]|([A-Za-z\*])', inner)
        toks = [a or b for a, b in toks]
    else:
        toks = list(s)
    letters, n_ncaa = [], 0
    for t in toks:
        if len(t) == 1 and t.upper() in _KD:
            letters.append(t.upper()); continue
        # ncAA token: strip common modifier prefixes to recover a canonical parent
        base = re.sub(r'^(NMe|Me|N-methyl-|d|D-)', '', t)
        base = base[:3].upper()
        if len(base) == 1 and base in _KD:
            letters.append(base); n_ncaa += 1
        elif base in _AA3to1:
            letters.append(_AA3to1[base]); n_ncaa += 1
        elif base.startswith('NLE'):          # norleucine ~ Leu-like hydrophobicity
            letters.append('L'); n_ncaa += 1
        else:
            n_ncaa += 1                        # unknown ncAA: counted, no canonical mapping
    return letters, n_ncaa, len(toks)


def features(sequence: str):
    """Return (mean_hydrophobicity_KD, net_charge, frac_charged, n_ncaa, n_total) for a sequence/HELM."""
    letters, n_ncaa, n_total = _residues_from_helm(sequence)
    if not letters:
        return None
    mean_h = sum(_KD[a] for a in letters) / len(letters)
    net_charge = sum(_CHG.get(a, 0) for a in letters)
    frac_charged = sum(1 for a in letters if a in _CHG) / max(len(letters), 1)
    return mean_h, net_charge, frac_charged, n_ncaa, n_total


@dataclass
class AvailabilityResult:
    score: float            # predicted availability (higher = more available); ranking value, not absolute
    low_availability: bool  # True => flagged at risk of low cellular availability
    mean_hydrophobicity: float
    net_charge: float
    frac_charged: float
    ncaa_fraction: float    # fraction of residues that are non-canonical (model is an approximation here)
    note: str


def predict_availability(sequence: str) -> AvailabilityResult:
    """Predict cellular-availability risk for a peptide sequence or HELM cyclo(...) string.

    Returns an AvailabilityResult. `low_availability=True` flags a peptide likely to be functionally
    limited in cells by hydrophobicity/charge-driven unavailability, independent of its affinity
    (Landry 2026). A *ranking* risk flag (LODO Spearman ~0.40), not a precise oracle.
    """
    f = features(sequence)
    if f is None:
        return AvailabilityResult(float('nan'), False, float('nan'), float('nan'), float('nan'),
                                  float('nan'), "no canonical residues parsed")
    mean_h, net_charge, frac_charged, n_ncaa, n_total = f
    score = _B0 + _B_HYDRO * mean_h + _B_CHARGE * net_charge + _B_FC * frac_charged
    ncaa_frac = n_ncaa / max(n_total, 1)
    note = ("canonical-AA peptide" if ncaa_frac == 0 else
            f"APPROXIMATION: {ncaa_frac:.0%} non-canonical residues (model trained on canonical SH3 peptides)")
    return AvailabilityResult(round(score, 4), score < _LOW_AVAIL_THRESHOLD, round(mean_h, 3),
                              round(net_charge, 2), round(frac_charged, 3), round(ncaa_frac, 3), note)


if __name__ == "__main__":
    import sys
    for s in sys.argv[1:] or ["cyclo(W-R-G-D-L-T-F-[dP]-[NMeV])", "RGKLMPGRG", "GSLASLGIGRR"]:
        r = predict_availability(s)
        flag = "LOW-AVAIL ⚠" if r.low_availability else "ok"
        print(f"{s:34s} score={r.score:+.3f} [{flag}] meanH={r.mean_hydrophobicity:+.2f} "
              f"charge={r.net_charge:+.1f} fracChg={r.frac_charged:.2f} ncaa={r.ncaa_fraction:.0%}  ({r.note})")
