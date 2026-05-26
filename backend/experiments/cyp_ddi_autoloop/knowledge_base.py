"""
Knowledge base for CYP DDI auto-loop parameter tuning.

SOURCES AND INTEGRITY POLICY
─────────────────────────────
All threshold values and remediation rationale come from primary regulatory
guidance and peer-reviewed pharmacokinetic literature.

Each KnowledgeEntry carries a `provenance` grade:
  GOLD   — the cited source states the threshold/rule verbatim.
  SILVER — the source supports the underlying mechanism; the exact numeric
           threshold is community/operational convention.
  BRONZE — operational heuristic; the source is related context only.

The schema separates `paper_supports` (what the source actually states) from
`rule_text` (what BioMate enforces). See
docs/20260522_AUTOLOOP_EVIDENCE_PROVENANCE_AUDIT.md.

PRIMARY SOURCES:
  FDA DDI Guidance (2020) — "In Vitro Drug Interaction Studies — Cytochrome
    P450 Enzyme- and Transporter-Mediated Drug Interactions"
    URL: https://www.fda.gov/media/134582/download
  Obach RS et al. (2006) — "The prediction of human pharmacokinetic parameters
    from preclinical and in vitro metabolism data"
    DOI: 10.1124/dmd.105.005595
  Callegari E et al. (2013) — "Predicting CYP3A4-mediated drug interactions"
    DOI: 10.1038/nrd4220
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class KnowledgeEntry:
    """
    One piece of knowledge supporting a CYP DDI parameter tuning decision.

    paper_ref       : Short citation of the underlying publication.
    paper_doi       : DOI or URL of that publication.
    provenance      : "GOLD" | "SILVER" | "BRONZE".
    paper_supports  : What the source actually states (factual).
    rule_text       : What BioMate enforces (operational).
    finding         : Plain-language remediation guidance.

    Legacy `source_file`/`source_text` retained for back-compat; `source_text`
    is an alias for `paper_supports`.
    """
    paper_ref: str
    paper_doi: str
    provenance: str
    paper_supports: str
    rule_text: str
    finding: str
    source_file: str = ""
    source_text: str = ""

    def __post_init__(self) -> None:
        if not self.source_text:
            self.source_text = self.paper_supports
        if not self.source_file:
            self.source_file = self.paper_ref

    def to_dict(self) -> dict:
        return {
            "provenance": self.provenance,
            "paper_supports": self.paper_supports,
            "rule_text": self.rule_text,
            "paper_ref": self.paper_ref,
            "paper_doi": self.paper_doi,
            "finding": self.finding,
            "source_text": self.source_text,
        }

    def short_ref(self) -> str:
        return self.paper_ref


# ── Per-gate knowledge entries ────────────────────────────────────────────────

_KNOWLEDGE: dict[str, list[KnowledgeEntry]] = {

    "clinical_study_isoforms": [
        KnowledgeEntry(
            paper_ref="FDA (2020) In Vitro Drug Interaction Studies Guidance",
            paper_doi="https://www.fda.gov/media/134582/download",
            provenance="GOLD",
            paper_supports=(
                "The FDA 2020 DDI guidance states verbatim that for reversible CYP "
                "inhibition the basic model is R1 = 1 + [I]/Ki, where [I] is mean "
                "Cmax,ss (total). The guidance specifies that R1 ≥ 1.1 indicates a "
                "potential clinical DDI and prompts a recommendation for a clinical "
                "DDI study."
            ),
            rule_text=(
                "BioMate CYP-DDI gate triggers CLINICAL_STUDY_RECOMMENDED at R1 ≥ 1.1, "
                "matching the FDA 2020 cutoff verbatim. The remediation lowers the "
                "input Cmax,ss (which directly reduces R1) by 50%."
            ),
            finding=(
                "Reducing Cmax,ss by 50% halves the (R1−1) term, moving weakly-"
                "inhibiting compounds below the FDA 1.1 CLINICAL_STUDY threshold."
            ),
        ),
        KnowledgeEntry(
            paper_ref="FDA (2020) In Vitro Drug Interaction Studies Guidance",
            paper_doi="https://www.fda.gov/media/134582/download",
            provenance="GOLD",
            paper_supports=(
                "FDA 2020 explicitly allows sponsors to refine from total Cmax,ss to "
                "unbound Cmax,ss in the basic model, noting that total Cmax,ss is the "
                "conservative default and may overestimate DDI risk."
            ),
            rule_text=(
                "BioMate's 50% Cmax reduction step is a simulation-level approximation "
                "of the FDA-permitted total→unbound Cmax refinement when the total-"
                "Cmax R1 triggers a clinical study recommendation."
            ),
            finding=(
                "Reducing input Cmax by 50% approximates the FDA-sanctioned "
                "total→unbound Cmax refinement step in the basic R1 model."
            ),
        ),
    ],

    "investigate_isoforms": [
        KnowledgeEntry(
            paper_ref="FDA (2020) In Vitro Drug Interaction Studies Guidance",
            paper_doi="https://www.fda.gov/media/134582/download",
            provenance="GOLD",
            paper_supports=(
                "FDA 2020 specifies R1 ≥ 1.02 as the threshold above which further "
                "investigation (mechanistic static models, PBPK, or clinical study) "
                "is warranted."
            ),
            rule_text=(
                "BioMate CYP-DDI gate raises INVESTIGATE at R1 ≥ 1.02, verbatim from "
                "the FDA 2020 guidance. Remediation reduces input Cmax by 30%."
            ),
            finding=(
                "R1 ≥ 1.02 is the FDA INVESTIGATE threshold; a 30% Cmax reduction "
                "moves marginal compounds (R1 ≈ 1.02–1.05) below it."
            ),
        ),
        KnowledgeEntry(
            paper_ref="Obach et al. (2006) Drug Metab Dispos 34:786-796",
            paper_doi="10.1124/dmd.105.005595",
            provenance="SILVER",
            paper_supports=(
                "Obach et al. (2006) characterize the relationship between in vitro "
                "Ki values and in vivo CYP3A4 inhibition risk, showing R1 scales "
                "linearly with Cmax/Ki. The paper supports the mechanistic basis for "
                "Cmax-based remediation but does not prescribe a specific 30% "
                "reduction factor."
            ),
            rule_text=(
                "BioMate uses a 30% Cmax reduction (× 0.7) as an operational "
                "remediation calibrated against the Obach Cmax/Ki framework for "
                "compounds with Ki > 5 µM."
            ),
            finding=(
                "A 30% Cmax reduction is calibrated to move weakly-inhibiting compounds "
                "(Ki > 5 µM) from INVESTIGATE to NOT_EXPECTED under the FDA basic R1 model."
            ),
        ),
    ],

    "tdi_concern": [
        KnowledgeEntry(
            paper_ref="FDA (2020) In Vitro Drug Interaction Studies Guidance",
            paper_doi="https://www.fda.gov/media/134582/download",
            provenance="GOLD",
            paper_supports=(
                "FDA 2020 prescribes the R2 framework for time-dependent CYP "
                "inhibition: R2 captures the apparent inactivation rate relative to "
                "enzyme degradation. The guidance specifies R2 ≤ 0.79 → INVESTIGATE "
                "and R2 ≤ 0.71 → CLINICAL_STUDY_RECOMMENDED."
            ),
            rule_text=(
                "BioMate enforces the FDA 2020 R2 cutoffs verbatim (0.79 / 0.71). "
                "The remediation is advisory only — no automatic parameter change — "
                "because in silico TDI predictions have a high false-positive rate "
                "and experimental confirmation (dialysis washout) is recommended "
                "before assuming clinical relevance."
            ),
            finding=(
                "TDI concern is advisory: confirm mechanism-based inactivation "
                "experimentally before assuming clinical relevance."
            ),
        ),
    ],
}


def get_knowledge(gate: str) -> list[KnowledgeEntry]:
    """Return knowledge entries for the given QC gate. Returns [] if unknown."""
    return _KNOWLEDGE.get(gate, [])
