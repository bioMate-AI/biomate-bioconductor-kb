"""
Knowledge base for Docking auto-loop parameter tuning.

SOURCES AND INTEGRITY POLICY
─────────────────────────────
All threshold values and remediation rationale come from primary publications
on molecular docking methodology.

Each KnowledgeEntry carries a `provenance` grade:
  GOLD   — paper states the threshold/rule verbatim.
  SILVER — paper supports the concept; numeric threshold is community convention.
  BRONZE — operational/vendor heuristic; paper is related context only.

Most docking thresholds (binding-score cutoffs, exhaustiveness ladders, box
expansions) fall under BRONZE because the original Vina/Glide papers do not
prescribe project-level pass/fail cutoffs — those are vendor and community
heuristics. See docs/20260522_AUTOLOOP_EVIDENCE_PROVENANCE_AUDIT.md.

PRIMARY SOURCES:
  Trott O & Olson AJ (2010) — "AutoDock Vina: improving the speed and accuracy
    of docking with a new scoring function, efficient optimization, and
    multithreading"
    DOI: 10.1002/jcc.21334
  Friesner RA et al. (2004) — "Glide: A New Approach for Rapid, Accurate
    Docking and Scoring"
    DOI: 10.1021/jm0306430
  Halgren TA et al. (2004) — "Glide: A New Approach for Rapid, Accurate
    Docking and Scoring. 2. Enrichment Factors in Database Screening"
    DOI: 10.1021/jm030644s
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class KnowledgeEntry:
    """
    One piece of knowledge supporting a docking parameter tuning decision.

    paper_ref       : Short citation.
    paper_doi       : DOI.
    provenance      : "GOLD" | "SILVER" | "BRONZE".
    paper_supports  : Factual content of the source.
    rule_text       : Operational threshold BioMate enforces.
    finding         : Remediation guidance.

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

    "valid_poses": [
        KnowledgeEntry(
            source_file="Trott & Olson (2010) AutoDock Vina",
            paper_ref="Trott & Olson (2010) J Comput Chem 31:455-461",
            paper_doi="10.1002/jcc.21334",
            provenance="BRONZE",
            paper_supports=(
                "Trott & Olson (2010) document that AutoDock Vina's exhaustiveness "
                "parameter controls search thoroughness (default = 8) and that "
                "increasing it reduces the probability of missing the global minimum, "
                "particularly for flexible ligands. The paper does not prescribe a "
                "specific 8→16 doubling rule as a remediation step — that is an "
                "operational ladder used by the Vina community."
            ),
            rule_text=(
                "BioMate docking gate raises exhaustiveness 8→16 (and 16→32) on "
                "zero-valid-pose HALT. This is a vendor/community-heuristic ladder "
                "consistent with the Vina paper's general recommendation."
            ),
            finding=(
                "Doubling exhaustiveness reduces the probability of missing the "
                "global-minimum pose for flexible ligands or large pockets."
            ),
        ),
        KnowledgeEntry(
            source_file="Trott & Olson (2010) AutoDock Vina",
            paper_ref="Trott & Olson (2010) J Comput Chem 31:455-461",
            paper_doi="10.1002/jcc.21334",
            provenance="BRONZE",
            paper_supports=(
                "Vina docs recommend the search box encompass the binding site plus "
                "a 5–10 Å buffer. The 1 Å-per-retry expansion specifically used as a "
                "remediation step is operational, not from the paper."
            ),
            rule_text=(
                "BioMate expands the bounding box by 1 Å per retry when zero valid "
                "poses are produced — an operational step within the Vina-recommended "
                "buffer envelope."
            ),
            finding=(
                "Expanding the box 1 Å per retry recovers poses clipped at the original "
                "box boundary. Zero valid poses usually indicates exhaustiveness too "
                "low or box too tight."
            ),
        ),
    ],

    "best_binding_score": [
        KnowledgeEntry(
            source_file="Trott & Olson (2010) AutoDock Vina",
            paper_ref="Trott & Olson (2010) J Comput Chem 31:455-461",
            paper_doi="10.1002/jcc.21334",
            provenance="BRONZE",
            paper_supports=(
                "Trott & Olson note in passing that a binding affinity near "
                "−7 kcal/mol corresponds roughly to ~2 µM Kd as a rough guide. "
                "The paper does NOT prescribe a project-level hit/no-hit threshold; "
                "the −7 kcal/mol cutoff is a community/vendor convention."
            ),
            rule_text=(
                "BioMate uses −7 kcal/mol as an operational Vina hit cutoff "
                "(~2 µM Kd-equivalent). On weak-score HALT, exhaustiveness is raised "
                "to improve pose-search coverage. This is a vendor heuristic."
            ),
            finding=(
                "The −7 kcal/mol Vina cutoff (~2 µM Kd) is a community hit threshold. "
                "Raising exhaustiveness reduces under-sampling artifacts in weak scores."
            ),
        ),
        KnowledgeEntry(
            source_file="Friesner RA et al. (2004) Glide",
            paper_ref="Friesner et al. (2004) J Med Chem 47:1739-1749",
            paper_doi="10.1021/jm0306430",
            provenance="BRONZE",
            paper_supports=(
                "Friesner et al. introduce Glide XP and demonstrate that XP provides "
                "improved enrichment over SP for lead optimization, especially when "
                "GlideScore differences between actives and inactives are small "
                "(< 1 kcal/mol). The paper does not prescribe specific −6 SP / −8 XP "
                "project-level hit cutoffs."
            ),
            rule_text=(
                "BioMate uses operational Glide cutoffs of −6 kcal/mol (SP) and "
                "−8 kcal/mol (XP). On weak SP scores, BioMate upgrades the run "
                "from SP → XP — a vendor/community remediation step consistent with "
                "the Friesner findings."
            ),
            finding=(
                "Upgrading Glide SP → XP improves ranking accuracy near the hit threshold. "
                "SP can miss tight-binding poses that XP descriptors capture."
            ),
        ),
        KnowledgeEntry(
            source_file="Halgren TA et al. (2004) Glide Part 2",
            paper_ref="Halgren et al. (2004) J Med Chem 47:1750-1759",
            paper_doi="10.1021/jm030644s",
            provenance="BRONZE",
            paper_supports=(
                "Halgren et al. report that Glide SP is calibrated for high-throughput "
                "virtual screening and that XP provides AUC improvements of 10–25% "
                "over SP on pharmaceutical target sets. The paper does not prescribe "
                "BioMate's specific SP→XP escalation policy."
            ),
            rule_text=(
                "BioMate escalates Glide SP → XP rescoring when SP fails to identify a "
                "clear hit (GlideScore > −6). This is an operational step consistent "
                "with the Halgren AUC findings."
            ),
            finding=(
                "When SP scoring fails to yield a clear hit, XP rescoring of the same "
                "poses provides meaningfully better active/inactive separation."
            ),
        ),
    ],
}


def get_knowledge(gate: str) -> list[KnowledgeEntry]:
    """Return knowledge entries for the given QC gate. Returns [] if unknown."""
    return _KNOWLEDGE.get(gate, [])
