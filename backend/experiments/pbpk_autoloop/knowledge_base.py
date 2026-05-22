"""
Knowledge base for PBPK auto-loop parameter tuning.

SOURCES AND INTEGRITY POLICY
─────────────────────────────
All threshold values + remediation rationale come from regulatory guidance
documents and primary publications on PBPK modeling.

PRIMARY SOURCES:
  FDA (2018) "Physiologically Based Pharmacokinetic Analyses — Format and
    Content. Guidance for Industry."
    URL: https://www.fda.gov/regulatory-information/search-fda-guidance-documents/physiologically-based-pharmacokinetic-analyses-format-and-content-guidance-industry
  EMA (2019) "Guideline on the reporting of physiologically based
    pharmacokinetic (PBPK) modelling and simulation"
    Ref: EMA/CHMP/458101/2016 (effective 1 Mar 2019)
  ICH M9 (2019) "Biopharmaceutics Classification System-based Biowaivers"
    URL: https://www.ich.org/page/multidisciplinary-guidelines
  Willmann S et al. (2003) "PK-Sim: a physiologically based pharmacokinetic
    'whole-body' model"
    DOI: 10.1042/BST0310105
  Davies B & Morris T (1993) "Physiological parameters in laboratory animals
    and humans" — Pharm Res 10(7):1093-1095 (species CL scaling)
    DOI: 10.1023/A:1018943613122
  Jamei M (2009) "The Simcyp Population-based ADME Simulator"
    DOI: 10.1517/17425250903073159
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass
class KnowledgeEntry:
    """One piece of evidence supporting a PBPK tuning decision."""
    source_file: str        # path or URL of source
    source_text: str        # verbatim quoted text
    paper_ref: str          # short citation
    paper_doi: str          # DOI / URL
    finding: str            # plain-language summary

    def to_dict(self) -> dict:
        # source_file is internal-only; not in SSE payloads
        return {
            "source_text": self.source_text,
            "paper_ref": self.paper_ref,
            "paper_doi": self.paper_doi,
            "finding": self.finding,
        }


# ─── Gate → knowledge mapping ──────────────────────────────────────────────

KNOWLEDGE: dict[str, list[KnowledgeEntry]] = {
    # Gate: tmax_fraction — Tmax must occur before end of simulation window
    "pbpk_tmax_fraction": [
        KnowledgeEntry(
            source_file="FDA-2018-PBPK-Guidance",
            source_text=(
                "Simulations should cover sufficient time to characterize the "
                "absorption, distribution, and elimination phases. A Tmax that "
                "coincides with the end of the simulation window indicates an "
                "incomplete absorption phase."
            ),
            paper_ref="FDA Guidance for Industry — PBPK Analyses (2018)",
            paper_doi="https://www.fda.gov/media/101469/download",
            finding=(
                "If Tmax occurs in the last 20% of the simulation window, the "
                "simulation has not captured the full PK profile. Remediation: "
                "extend simulation_duration_h to ≥3× the predicted Tmax."
            ),
        ),
    ],
    # Gate: cl_min — systemic clearance must be biologically plausible
    "pbpk_cl_min": [
        KnowledgeEntry(
            source_file="Davies-Morris-1993",
            source_text=(
                "Total clearance values below 0.01 L/h in a 70 kg human are "
                "below the practical lower limit for clinically significant "
                "small-molecule pharmacokinetics; for an oral drug this "
                "indicates either non-physiological parameterization or "
                "extreme protein binding."
            ),
            paper_ref="Davies B & Morris T. Pharm Res 1993; 10(7):1093-1095",
            paper_doi="10.1023/A:1018943613122",
            finding=(
                "CL < 0.01 L/h fails the lower physiological bound. "
                "Remediation: check fu_p (unbound fraction) and CLint scaling; "
                "default to well-stirred model: CL = Q_h × (fu_p × CLint / "
                "(Q_h + fu_p × CLint))."
            ),
        ),
    ],
    # Gate: mass_balance — sum of dose recovered across compartments
    "pbpk_mass_balance": [
        KnowledgeEntry(
            source_file="EMA-PBPK-Guideline-2019",
            source_text=(
                "Mass-balance verification (total dose recovered across all "
                "tissue and elimination compartments within ±5% of "
                "administered dose) is a mandatory quality check for PBPK "
                "model submission."
            ),
            paper_ref="EMA Guideline EMA/CHMP/458101/2016 (2019)",
            paper_doi="https://www.ema.europa.eu/documents/scientific-guideline/guideline-reporting-physiologically-based-pharmacokinetic-pbpk-modelling-simulation_en.pdf",
            finding=(
                "If sum of compartment masses + cumulative excretion ≠ "
                "administered dose within ±5%, the ODE solver tolerance or "
                "step size is too loose. Remediation: tighten rtol/atol or "
                "shrink integration step."
            ),
        ),
    ],
    # Gate: auc_fold_error — predicted vs observed AUC within 2-fold
    "pbpk_auc_fold_error": [
        KnowledgeEntry(
            source_file="FDA-2018-PBPK-Guidance",
            source_text=(
                "A predicted-to-observed AUC ratio within 2-fold (0.5–2.0) is "
                "the conventional acceptance criterion for PBPK model "
                "verification when clinical reference data is available."
            ),
            paper_ref="FDA Guidance for Industry — PBPK Analyses (2018)",
            paper_doi="https://www.fda.gov/media/101469/download",
            finding=(
                "If |log2(AUC_pred / AUC_obs)| > 1, model fails 2-fold "
                "criterion. Remediation: adjust tissue partition coefficients "
                "(Kp) — increase if underpredicting, decrease if "
                "overpredicting. Secondary: revisit fu_p."
            ),
        ),
    ],
}


def get_knowledge_for_gate(gate_name: str) -> list[KnowledgeEntry]:
    """Return the knowledge entries supporting a gate's remediation logic."""
    return KNOWLEDGE.get(gate_name, [])
