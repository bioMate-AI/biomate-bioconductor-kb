"""
Virtual-library generators for the sequence (peptide / biologic) DMTA loop.

The loop's surrogate scores a *candidate library*; this module produces one
cheaply and deterministically from a seed sequence by enumerating point
mutations — the sequence analogue of enumerating small-molecule analogues. For
richer generation, cyclic_peptide_design (peptides) and the scFv / antibody
design workflows (biologics) produce libraries that are scored the same way;
this enumerator is the always-available, dependency-free baseline so a loop can
run immediately.
"""
from __future__ import annotations

from typing import Iterable, Optional

_AA20 = "ACDEFGHIKLMNPQRSTVWY"
# Conservative substitution groups (BLOSUM-like) — mutating within a group
# keeps the candidate developable while exploring the series.
_GROUPS = [
    set("AVLIM"),   # aliphatic
    set("FWY"),     # aromatic
    set("ST"),      # small hydroxyl
    set("DE"),      # acidic
    set("KRH"),     # basic
    set("NQ"),      # amide
    set("GP"),      # special
    set("C"),       # cysteine (kept alone)
]
_GROUP_OF = {aa: g for g in _GROUPS for aa in g}


def _clean(seq: str) -> str:
    return "".join(c for c in str(seq).upper() if c in _AA20)


def single_point_mutants(seq: str, positions: Optional[Iterable[int]] = None,
                         conservative: bool = False) -> list[str]:
    """Every single-residue substitution of ``seq`` at the given positions
    (default: all). ``conservative`` restricts to within-group substitutions."""
    s = _clean(seq)
    out: list[str] = []
    pos = range(len(s)) if positions is None else [p for p in positions if 0 <= p < len(s)]
    for i in pos:
        choices = _GROUP_OF.get(s[i], set(_AA20)) if conservative else set(_AA20)
        for aa in sorted(choices):
            if aa != s[i]:
                out.append(s[:i] + aa + s[i + 1:])
    return out


def mutational_library(seed: str, positions: Optional[Iterable[int]] = None,
                       conservative: bool = False, include_seed: bool = True,
                       max_size: Optional[int] = None) -> list[str]:
    """Deterministic candidate library around ``seed``: the seed plus its
    single-point mutants (deduplicated, order-stable). ``max_size`` truncates."""
    s = _clean(seed)
    lib: list[str] = [s] if include_seed and s else []
    seen = set(lib)
    for cand in single_point_mutants(s, positions, conservative):
        if cand not in seen:
            seen.add(cand)
            lib.append(cand)
            if max_size and len(lib) >= max_size:
                break
    return lib
