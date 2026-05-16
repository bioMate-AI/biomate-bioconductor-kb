"""
ICH M3(R2) phase-gating verifier — checker C2 from FDA reviewer checklist v2.

Encodes ICH M3(R2) Table 1 (duration of repeat-dose toxicity studies needed to
support clinical trials) and the phase-appropriate study battery requirements
(genotox per ICH S2(R1), safety pharm per ICH S7A, hERG per ICH S7B, DART per
ICH S5(R3), carcinogenicity per ICH S1A).

Given a proposed clinical trial design (phase, duration, population), returns
the required nonclinical study list. Verifies that a generated section lists
all required studies.

Reference: ICH M3(R2) Nonclinical Safety Studies for the Conduct of Human
Clinical Trials and Marketing Authorization for Pharmaceuticals.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Literal

Phase = Literal["I", "II", "III"]
Population = Literal["healthy_adult", "patient", "wocbp", "pediatric"]


# ICH M3(R2) Table 1 — repeat-dose tox duration required to support trial duration.
# Key: max trial duration in days. Value: (rodent_months, non_rodent_months).
TABLE1_REPEAT_DOSE: list[tuple[int, int, int]] = [
    # (max_trial_days, rodent_months, non_rodent_months)
    (14,    1,  1),   # up to 2 weeks
    (30,    1,  1),   # up to 1 month
    (90,    3,  3),   # up to 3 months
    (180,   6,  6),   # up to 6 months
    (99999, 6,  9),   # > 6 months — chronic: 6mo rodent + 9mo non-rodent
]


@dataclass
class StudyRequirement:
    name: str
    citation: str
    rationale: str


@dataclass
class PhaseGatingRequirements:
    phase: Phase
    trial_duration_days: int
    population: Population
    required: list[StudyRequirement] = field(default_factory=list)


def required_studies(
    phase: Phase,
    trial_duration_days: int,
    population: Population,
    *,
    route: str | None = None,
    indication_class: str | None = None,
) -> PhaseGatingRequirements:
    """
    Compute required nonclinical study list per ICH M3(R2).

    Optional `route` and `indication_class` keys activate
    regulatory-science overrides (see checker_overrides.py). E.g. a
    topical-route study is exempt from hERG per dismissal-driven rule
    refinement.
    """
    from .checker_overrides import is_exempt
    context = {
        "phase": phase,
        "trial_duration_days": trial_duration_days,
        "population": population,
        "route": route,
        "indication_class": indication_class,
    }
    out: list[StudyRequirement] = []

    # Repeat-dose tox duration from Table 1
    for max_days, rodent_mo, nonrodent_mo in TABLE1_REPEAT_DOSE:
        if trial_duration_days <= max_days:
            rationale = (
                f"supports clinical trial duration up to {max_days} days"
                if max_days < 99999
                else "supports chronic clinical use beyond 6 months"
            )
            out.append(StudyRequirement(
                name=f"{rodent_mo}-month repeat-dose toxicity in rodent",
                citation="ICH M3(R2) Table 1",
                rationale=rationale,
            ))
            out.append(StudyRequirement(
                name=f"{nonrodent_mo}-month repeat-dose toxicity in non-rodent",
                citation="ICH M3(R2) Table 1",
                rationale=rationale,
            ))
            break

    # Genotoxicity battery — Ames + in vitro mammalian for FIH
    out.append(StudyRequirement(
        name="Ames bacterial reverse mutation assay",
        citation="ICH S2(R1)",
        rationale="standard genotoxicity battery — required for first-in-human",
    ))
    out.append(StudyRequirement(
        name="in vitro mammalian cell genotoxicity assay",
        citation="ICH S2(R1)",
        rationale="standard genotoxicity battery — required for first-in-human",
    ))
    if trial_duration_days > 14:
        out.append(StudyRequirement(
            name="in vivo genotoxicity assay (micronucleus or comet)",
            citation="ICH S2(R1)",
            rationale="required for repeat-dose clinical trials beyond 2 weeks",
        ))

    # Safety pharmacology core battery
    out.append(StudyRequirement(
        name="cardiovascular safety pharmacology",
        citation="ICH S7A",
        rationale="core safety pharmacology battery for first-in-human",
    ))
    out.append(StudyRequirement(
        name="central nervous system safety pharmacology",
        citation="ICH S7A",
        rationale="core safety pharmacology battery for first-in-human",
    ))
    out.append(StudyRequirement(
        name="respiratory safety pharmacology",
        citation="ICH S7A",
        rationale="core safety pharmacology battery for first-in-human",
    ))

    # hERG / QT — exemption available for topical / ophthalmic via overrides
    if not is_exempt("phase_gating", "hERG_required", context):
        out.append(StudyRequirement(
            name="in vitro hERG channel assay",
            citation="ICH S7B",
            rationale="cardiac repolarization risk assessment for first-in-human",
        ))

    # DART — staged per population
    if population == "wocbp":
        out.append(StudyRequirement(
            name="embryo-fetal development study (one species)",
            citation="ICH S5(R3)",
            rationale="women of childbearing potential enrollment",
        ))
        if phase in ("II", "III") or trial_duration_days > 90:
            out.append(StudyRequirement(
                name="embryo-fetal development study (second species)",
                citation="ICH S5(R3)",
                rationale="confirmatory species for WOCBP enrollment beyond Phase I",
            ))
            out.append(StudyRequirement(
                name="fertility and early embryonic development study",
                citation="ICH S5(R3)",
                rationale="required prior to Phase III for WOCBP",
            ))

    # Carcinogenicity for chronic indications
    if trial_duration_days > 180 and phase == "III":
        out.append(StudyRequirement(
            name="2-year carcinogenicity study in rodent",
            citation="ICH S1A",
            rationale="chronic clinical use ≥6 months requires carcinogenicity assessment",
        ))

    return PhaseGatingRequirements(
        phase=phase,
        trial_duration_days=trial_duration_days,
        population=population,
        required=out,
    )


@dataclass
class PhaseGatingResult:
    grounded: bool
    missing: list[str]
    found: list[str]

    @property
    def passed(self) -> bool:
        return self.grounded and not self.missing


def verify_phase_gating(text: str, requirements: PhaseGatingRequirements) -> PhaseGatingResult:
    """
    Verify that `text` mentions every required study by name (or close synonym).
    """
    text_lower = text.lower()
    missing: list[str] = []
    found: list[str] = []

    # Match by salient keyword sets (any-of-set must appear)
    for req in requirements.required:
        keyword_sets = _salient_keyword_sets(req.name)
        if all(any(kw in text_lower for kw in alts) for alts in keyword_sets):
            found.append(req.name)
        else:
            missing.append(req.name)

    return PhaseGatingResult(
        grounded=True,
        missing=missing,
        found=found,
    )


_DURATION_RE = re.compile(r"(\d+)-month")


def _salient_keyword_sets(study_name: str) -> list[list[str]]:
    """Each inner list is a set of acceptable synonyms; ALL outer lists must match."""
    n = study_name.lower()
    if "repeat-dose" in n:
        m = _DURATION_RE.search(n)
        species_alts = ["non-rodent"] if "non-rodent" in n else ["rodent"]
        sets = [["repeat-dose"], species_alts]
        if m:
            sets.append([f"{m.group(1)}-month", f"{m.group(1)} month"])
        return sets
    if "ames" in n:
        return [["ames", "bacterial reverse mutation"]]
    if "in vitro mammalian" in n:
        return [["in vitro"], ["mammalian", "lymphoma", "chromosomal aberration"]]
    if "in vivo genotox" in n:
        return [["in vivo"], ["micronucleus", "comet", "genotox"]]
    if "cardiovascular" in n:
        return [["cardiovascular", "cv ", "qt"]]
    if "central nervous" in n:
        return [["cns", "central nervous", "neurological"]]
    if "respiratory" in n:
        return [["respiratory", "pulmonary"]]
    if "herg" in n:
        return [["herg", "ikr"]]
    if "embryo-fetal" in n:
        return [["embryo-fetal", "embryofetal", "developmental toxicity"]]
    if "fertility" in n:
        return [["fertility"]]
    if "carcinogenicity" in n:
        return [["carcinogenicity", "carcinogen"]]
    return [[n.split()[0]]]


if __name__ == "__main__":
    req = required_studies("I", trial_duration_days=14, population="healthy_adult")
    print(f"Phase {req.phase}, {req.trial_duration_days}d, {req.population}: "
          f"{len(req.required)} studies required")
    for s in req.required:
        print(f"  - {s.name} [{s.citation}]")

    good = (
        "First-in-human Phase I support: 1-month repeat-dose toxicity in rodent and "
        "1-month repeat-dose toxicity in non-rodent per ICH M3(R2) Table 1; Ames "
        "bacterial reverse mutation assay and in vitro mammalian cell genotoxicity "
        "assay per ICH S2(R1); cardiovascular, CNS, and respiratory safety pharmacology "
        "per ICH S7A; in vitro hERG channel assay per ICH S7B."
    )
    r = verify_phase_gating(good, req)
    print(f"\ngood: passed={r.passed}, missing={r.missing}")

    bad = "Phase I support: Ames assay and CNS safety pharmacology."
    r = verify_phase_gating(bad, req)
    print(f"bad:  passed={r.passed}, missing[:3]={r.missing[:3]}")
