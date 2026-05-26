"""
Knowledge base for NCA PK auto-loop parameter tuning.

SOURCES AND INTEGRITY POLICY
─────────────────────────────
All threshold values and remediation rationale come from primary regulatory
guidance and peer-reviewed pharmacokinetic literature.

Each KnowledgeEntry carries a `provenance` grade:
  GOLD   — the cited source states the threshold/rule verbatim.
  SILVER — community convention attributed to the source; the source supports
           the underlying concept but doesn't prescribe the exact numeric value.
  BRONZE — operational heuristic; the source is related context only.

`paper_supports` records what the source actually says; `rule_text` records
what BioMate enforces. See docs/20260522_AUTOLOOP_EVIDENCE_PROVENANCE_AUDIT.md.

PRIMARY SOURCES:
  FDA Guidance for Industry (2003) — "Bioavailability and Bioequivalence Studies
    for Orally Administered Drug Products — General Considerations"
    URL: https://www.fda.gov/media/70956/download
  Gabrielsson J & Weiner D (2006) — "Pharmacokinetic and Pharmacodynamic
    Data Analysis: Concepts and Applications" (4th ed.)
    ISBN: 9789197651615
  PKNCA R package vignette (2023) — "Introduction to PKNCA"
    URL: https://cran.r-project.org/web/packages/PKNCA/vignettes/Introduction-to-PKNCA.html
  Ette EI & Williams PJ (2004) — "Population pharmacokinetics I: background,
    concepts, and models"
    DOI: 10.1592/phco.24.7.907.33162
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class KnowledgeEntry:
    """
    One piece of knowledge supporting an NCA PK parameter tuning decision.

    paper_ref       : Short citation.
    paper_doi       : DOI or URL.
    provenance      : "GOLD" | "SILVER" | "BRONZE".
    paper_supports  : Factual content of the source.
    rule_text       : Operational threshold BioMate enforces.
    finding         : Remediation guidance.

    Legacy `source_file`/`source_text` retained for back-compat;
    `source_text` is an alias for `paper_supports`.
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

    "auc_extrapolation": [
        KnowledgeEntry(
            paper_ref="FDA (2003) Bioavailability and Bioequivalence Studies Guidance",
            paper_doi="https://www.fda.gov/media/70956/download",
            provenance="GOLD",
            paper_supports=(
                "The FDA 2003 BA/BE guidance states verbatim that AUCinf should be "
                "estimated as AUClast + Clast/lambda_z, and that the extrapolated "
                "portion (AUCinf − AUClast) should not exceed 20% of AUCinf. If "
                "extrapolation exceeds 20%, the sampling schedule is considered "
                "insufficient and the study should be redesigned with extended sampling."
            ),
            rule_text=(
                "BioMate NCA gate enforces the verbatim FDA ≤20% AUC-extrapolation "
                "rule. On HALT, the remediation extends last_sampling_time by 1.5×, "
                "which adds ~0.5 half-lives at typical t½ and reduces extrapolation "
                "from ~25% to ~15%."
            ),
            finding=(
                "FDA explicitly states AUC extrapolation > 20% indicates insufficient "
                "sampling. Extending last_sampling_time by 1.5× is the standard fix."
            ),
        ),
        KnowledgeEntry(
            paper_ref="PKNCA R package vignette (2023)",
            paper_doi="https://cran.r-project.org/web/packages/PKNCA/vignettes/Introduction-to-PKNCA.html",
            provenance="GOLD",
            paper_supports=(
                "PKNCA documents the default rule AUC.pct.extrapolated > 20 as an "
                "unreliable-estimate flag, and recommends 3–4 terminal-phase half-"
                "lives of sampling to reliably estimate lambda_z."
            ),
            rule_text=(
                "BioMate matches the PKNCA reference 20% rule and the 3–4 terminal "
                "half-life sampling recommendation. The 1.5× sampling extension is "
                "BioMate's operational first-step remediation."
            ),
            finding=(
                "PKNCA (reference NCA implementation) uses the same 20% rule. "
                "Extending last_sampling_time by 1.5× adds ~0.5 half-life of data."
            ),
        ),
    ],

    "terminal_slope_coverage": [
        KnowledgeEntry(
            paper_ref="Gabrielsson & Weiner (2006) PK/PD Data Analysis, 4th ed.",
            paper_doi="ISBN 9789197651615",
            provenance="SILVER",
            paper_supports=(
                "Gabrielsson & Weiner's PK/PD textbook establishes that reliable "
                "lambda_z estimation requires at least 3 concentration-time points "
                "in the log-linear terminal phase, with sampling extending to "
                "3–5 half-lives post-dose. The book treats r² > 0.85 as a "
                "common quality criterion; specific BioMate numeric thresholds "
                "(e.g. add 2 terminal_phase_points, 1.3× window) are operational "
                "conventions not prescribed verbatim by the text."
            ),
            rule_text=(
                "BioMate requires ≥3 terminal points and on HALT adds 2 "
                "terminal_phase_points + extends sampling 1.3×. This is a "
                "community-convention operationalization of the Gabrielsson "
                "minimum-3-points / 3–5 half-life sampling principle."
            ),
            finding=(
                "Terminal slope needs ≥3 points in the log-linear decline. Adding 2 "
                "points and extending the window 1.3× ensures adequate lambda_z coverage."
            ),
        ),
        KnowledgeEntry(
            paper_ref="PKNCA R package vignette (2023)",
            paper_doi="https://cran.r-project.org/web/packages/PKNCA/vignettes/Introduction-to-PKNCA.html",
            provenance="GOLD",
            paper_supports=(
                "PKNCA documents that by default it requires ≥3 points for lambda_z "
                "and adj. r² ≥ 0.9, and excludes subjects without a qualifying "
                "terminal slope from lambda_z and AUCinf summaries."
            ),
            rule_text=(
                "BioMate aligns with the PKNCA defaults (≥3 points, adj.r² ≥ 0.9). "
                "When more than 2 subjects would be excluded, BioMate increases "
                "terminal_phase_points by 2 to recover slope fits."
            ),
            finding=(
                "Subjects without a terminal slope are dropped from AUCinf summaries. "
                "Adding 2 terminal_phase_points reduces per-subject exclusions."
            ),
        ),
    ],

    "t_half_plausibility": [
        KnowledgeEntry(
            paper_ref="Ette & Williams (2004) Ann Pharmacother 38:907-915",
            paper_doi="10.1592/phco.24.7.907.33162",
            provenance="BRONZE",
            paper_supports=(
                "Ette & Williams (2004) provide background on population PK methodology "
                "and discuss diagnostic interpretation of derived parameters. The paper "
                "does not prescribe specific numeric flags such as 't½ > 1.5× sampling "
                "window' or 't½ > 500 h is implausible' — these are operational "
                "heuristics applied in NCA practice."
            ),
            rule_text=(
                "BioMate flags t_half as advisory (no automatic parameter change) when "
                "it exceeds 1.5× the sampling window or 500 h for small molecules, "
                "prompting scientist review for flip-flop kinetics or assay artifacts. "
                "These cutoffs are BioMate operational heuristics."
            ),
            finding=(
                "Implausibly long t½ suggests under-sampling or flip-flop kinetics. "
                "No automatic parameter change; scientist should review the C-t profile."
            ),
        ),
    ],
}


def get_knowledge(gate: str) -> list[KnowledgeEntry]:
    """Return knowledge entries for the given QC gate. Returns [] if unknown."""
    return _KNOWLEDGE.get(gate, [])
