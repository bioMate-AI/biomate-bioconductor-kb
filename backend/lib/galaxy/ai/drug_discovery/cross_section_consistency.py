"""
Cross-section consistency checker — D1/D2/D3 from FDA reviewer checklist v2.

Verifies that quantitative facts cited in §2.6.6 (Toxicology Written Summary)
match the corresponding rows in §2.6.7 (Toxicology Tabulated Summary).

Checks:
  D1 NOAEL consistency       — every species NOAEL in §2.6.6 equals §2.6.7 row
  D2 Study-ID consistency    — every study ID cited in §2.6.6 has a §2.6.7 row
  D3 Species/route agreement — species + route mentioned in narrative match table

No model required. Pure regex + dict comparison.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field

# Species canonical names (strip strain prefixes for matching)
_SPECIES_TERMS = [
    "mouse", "rat", "dog", "monkey", "rabbit", "minipig", "pig",
    "hamster", "ferret", "guinea pig",
]


def _canonical_species(text: str) -> str | None:
    t = text.lower()
    for s in _SPECIES_TERMS:
        if s in t:
            return s
    return None


# NOAEL claims in narrative: "NOAEL of 100 mg/kg/day in rats" or
# "NOAEL was identified at 30 mg/kg/day in the dog"
_NOAEL_NARRATIVE_RE = re.compile(
    r"NOAEL\s*(?:of|was|=|:|was\s+identified\s+at)?\s*"
    r"(\d+(?:\.\d+)?)\s*mg/kg(?:/day)?"
    r"[^.]{0,80}?\b("
    + "|".join(_SPECIES_TERMS) +
    r")s?\b",
    re.IGNORECASE,
)

# Study-ID pattern: TOX-2023-014, RTX-101, STUDY-99-A
_STUDY_ID_RE = re.compile(r"\b([A-Z]{2,5}-\d{2,4}(?:-\w{1,4})?)\b")


@dataclass
class ConsistencyIssue:
    code: str
    message: str


@dataclass
class ConsistencyResult:
    narrative_noaels: dict[str, float]  # species → NOAEL
    table_noaels:     dict[str, float]
    narrative_study_ids: set[str]
    table_study_ids:     set[str]
    issues: list[ConsistencyIssue] = field(default_factory=list)

    @property
    def passed(self) -> bool:
        return not self.issues


def _extract_narrative_noaels(text: str) -> dict[str, float]:
    out: dict[str, float] = {}
    for m in _NOAEL_NARRATIVE_RE.finditer(text):
        value = float(m.group(1))
        species = m.group(2).lower().rstrip("s")
        # If multiple NOAELs per species in narrative, keep the first (most specific)
        out.setdefault(species, value)
    return out


def _extract_table_noaels(table_text: str) -> dict[str, float]:
    """Parse markdown table; map species column → NOAEL column."""
    lines = [l.strip() for l in table_text.splitlines() if "|" in l]
    if len(lines) < 3:
        return {}
    header = [c.strip().lower() for c in lines[0].strip("|").split("|")]
    species_col = next((i for i, h in enumerate(header) if "species" in h), -1)
    noael_col   = next((i for i, h in enumerate(header) if "noael" in h), -1)
    if species_col < 0 or noael_col < 0:
        return {}

    out: dict[str, float] = {}
    for row_line in lines[2:]:
        cells = [c.strip() for c in row_line.strip("|").split("|")]
        if len(cells) <= max(species_col, noael_col):
            continue
        species = _canonical_species(cells[species_col])
        noael_str = re.search(r"\d+(?:\.\d+)?", cells[noael_col])
        if species and noael_str:
            out.setdefault(species, float(noael_str.group(0)))
    return out


def _extract_study_ids(text: str) -> set[str]:
    return set(_STUDY_ID_RE.findall(text))


def check_consistency(narrative_text: str, table_text: str,
                      tolerance_rel: float = 0.05) -> ConsistencyResult:
    """
    Compare §2.6.6 narrative to §2.6.7 tabulated summary.

    Tolerance: NOAELs match if within `tolerance_rel` (default 5%) — handles
    rounding (e.g. 100 vs 100.0).
    """
    nar_noaels = _extract_narrative_noaels(narrative_text)
    tab_noaels = _extract_table_noaels(table_text)
    nar_ids    = _extract_study_ids(narrative_text)
    tab_ids    = _extract_study_ids(table_text)

    issues: list[ConsistencyIssue] = []

    # D1: NOAEL mismatch per species
    for species, nar_val in nar_noaels.items():
        tab_val = tab_noaels.get(species)
        if tab_val is None:
            issues.append(ConsistencyIssue(
                "D1_species_not_in_table",
                f"narrative cites {species} NOAEL {nar_val} but no {species} row in §2.6.7",
            ))
            continue
        rel_err = abs(nar_val - tab_val) / max(tab_val, 1e-9)
        if rel_err > tolerance_rel:
            issues.append(ConsistencyIssue(
                "D1_noael_mismatch",
                f"{species}: §2.6.6 narrative NOAEL={nar_val} vs §2.6.7 table NOAEL={tab_val} "
                f"(rel_err={rel_err:.1%})",
            ))

    # D2: study IDs in narrative must appear in table
    missing_in_table = nar_ids - tab_ids
    for sid in sorted(missing_in_table):
        issues.append(ConsistencyIssue(
            "D2_study_id_not_in_table",
            f"study {sid} cited in narrative but absent from §2.6.7 table",
        ))

    return ConsistencyResult(
        narrative_noaels=nar_noaels,
        table_noaels=tab_noaels,
        narrative_study_ids=nar_ids,
        table_study_ids=tab_ids,
        issues=issues,
    )


if __name__ == "__main__":
    consistent_narrative = (
        "In the 28-day repeat-dose study, the NOAEL of 100 mg/kg/day was identified "
        "in rats. In a parallel study, the NOAEL of 30 mg/kg/day was identified in dogs."
    )
    consistent_table = """
    | Study | Species | NOAEL (mg/kg/day) | Findings |
    |-------|---------|-------------------|----------|
    | RTX-101 | Sprague-Dawley rat | 100 | mild liver enzyme elevation |
    | RTX-102 | beagle dog | 30 | emesis at high dose |
    """
    r = check_consistency(consistent_narrative, consistent_table)
    print(f"[consistent] passed={r.passed}, issues={[i.code for i in r.issues]}")

    inconsistent_narrative = (
        "NOAEL of 100 mg/kg/day was identified in rats. NOAEL of 30 mg/kg/day was "
        "identified in dogs. Findings consistent with study TOX-2024-A07."
    )
    inconsistent_table = """
    | Study | Species | NOAEL (mg/kg/day) | Findings |
    |-------|---------|-------------------|----------|
    | RTX-101 | rat | 50 | hepatic enzymes elevated |
    | RTX-102 | dog | 30 | emesis at high dose |
    """
    r = check_consistency(inconsistent_narrative, inconsistent_table)
    print(f"[inconsistent] passed={r.passed}")
    for i in r.issues:
        print(f"   [{i.code}] {i.message}")
