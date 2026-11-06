"""
CMC / ADMET domain pack — the R&D/CMC edge BioMate already serves.

This pack deliberately spans the GROUNDEDNESS SPECTRUM of regulatory/discovery
thresholds, which is what makes it a strong demonstration of the engine:

  * ICH M7 mutagenic-impurity TTC (1.5 ug/day) — a threshold WITH a documented
    quantitative derivation (10^-5 lifetime cancer risk; TD50 linear
    extrapolation) AND a published peer-reviewed critique of that derivation.
    -> the engine should ground it AND surface the debate.
  * ICH Q3A/Q3B impurity qualification threshold (0.15%) — a harmonized
    expert/experience convention, dose-dependent, "whichever is lower".
    -> grounded as to WHAT and roughly WHY, boundary on the EXACT figure.
  * hERG cardiotoxicity — NO fixed regulatory cutoff; cardiac safety is governed
    by ICH S7B (nonclinical) + E14 (clinical QT). The common ~10 uM screen is a
    discovery heuristic, not a spec. -> engine should refuse to assert a "limit".
  * Lipinski Rule of Five — an empirical developability heuristic, not a
    regulatory spec. -> engine flags it as a heuristic, not a requirement.

Citations are REAL (URLs below); paraphrases of guidance carry verified=False so
the reader confirms against the controlled document, consistent with the
product's own rule. Research verified 2026-10-14.
"""

from __future__ import annotations

from typing import List

from ..models import Source, SourceTier


_SHARED: List[Source] = [
    # ── ICH M7 TTC: the WHAT (normative) ─────────────────────────────────────
    Source(
        id="ich-m7-ttc-clause",
        tier=SourceTier.NORMATIVE_PRIMARY,
        title="ICH M7 — mutagenic-impurity acceptable intake (TTC)",
        citation="ICH M7(R2), Assessment and Control of DNA-Reactive (Mutagenic) Impurities",
        text=(
            "A Threshold of Toxicological Concern (TTC)-based acceptable intake of "
            "1.5 micrograms per person per day for a mutagenic impurity is used as "
            "a default to derive a control limit for most pharmaceuticals, taken to "
            "be associated with negligible risk. This is the normative acceptance "
            "position; it states the limit, not its full derivation."
        ),
        owner=None,
        verified=False,
        locator="https://www.fda.gov/media/170461/download",
        keywords=["ich m7", "ttc", "mutagenic", "impurity", "1.5", "ug/day",
                  "microgram", "acceptable intake", "threshold", "limit", "genotoxic"],
    ),
    # ── ICH M7 TTC: the HOW/WHY (derivation — grounded) ──────────────────────
    Source(
        id="ich-m7-ttc-derivation",
        tier=SourceTier.NORMATIVE_PRIMARY,
        title="ICH M7 TTC — documented quantitative derivation",
        citation="ICH M7(R1) Guideline, TTC basis",
        text=(
            "Unlike many pragmatic limits, the TTC figure HAS a documented "
            "quantitative derivation: 1.5 ug/day corresponds to a theoretical 10^-5 "
            "(1 in 100,000) excess lifetime cancer risk. It is obtained by simple "
            "linear extrapolation from the TD50 (dose giving 50% tumour incidence) "
            "for the most sensitive species and tumour site, across a carcinogenicity "
            "analysis of >1000 chemicals; the TTC concept itself originated as the "
            "US FDA 'threshold of regulation' for food-contact substances. The "
            "methods are regarded as conservative."
        ),
        owner=None,
        verified=False,
        locator="https://database.ich.org/sites/default/files/M7_R1_Guideline.pdf",
        keywords=["ttc", "derivation", "exact_derivation", "10^-5",
                  "lifetime cancer risk", "td50", "linear extrapolation", "why", "basis",
                  "origin", "threshold of regulation", "1.5", "mutagenic", "conservative"],
    ),
    # ── ICH M7 TTC: the DEBATE (peer-reviewed critique) ──────────────────────
    Source(
        id="lit-ttc-critique",
        tier=SourceTier.PEER_REVIEWED,
        title="Peer-reviewed critique of the cancer-TTC derivation",
        citation="Critique of the derivation of the cancer TTC and recommendations "
                 "for structural-class-based limits (Regul. Toxicol. Pharmacol.)",
        text=(
            "The exact derivation of the cancer TTC is not settled science: peer-"
            "reviewed work critiques the statistical derivation of the 1.5 ug/day "
            "cancer TTC and recommends structural-class-based limits instead. So "
            "'why exactly 1.5 ug/day' has a grounded derivation AND an active "
            "scientific debate — both must be surfaced, not one asserted as final."
        ),
        owner=None,
        verified=True,
        locator="https://www.sciencedirect.com/science/article/abs/pii/S0273230013001311",
        keywords=["ttc", "critique", "debate", "1.5", "derivation", "structural class",
                  "cancer", "why", "mutagenic", "contested"],
    ),

    # ── ICH Q3A/Q3B impurity thresholds (convention) ─────────────────────────
    Source(
        id="ich-q3a-thresholds",
        tier=SourceTier.NORMATIVE_PRIMARY,
        title="ICH Q3A/Q3B — impurity reporting / identification / qualification thresholds",
        citation="ICH Q3A(R2) Impurities in New Drug Substances (dose-dependent thresholds)",
        text=(
            "Dose-dependent, harmonized thresholds for non-mutagenic impurities in a "
            "new drug substance: e.g. for a maximum daily dose <=2 g/day, reporting "
            "0.05%, identification 0.10% (or 1.0 mg/day intake, whichever is lower), "
            "qualification 0.15% (or 1.0 mg/day, whichever is lower); tighter "
            "percentages apply above 2 g/day. These are a harmonized expert/experience "
            "convention for an acceptable safety-qualification burden — the guideline "
            "states the figures but not a first-principles derivation of each percent."
        ),
        owner=None,
        verified=False,
        locator="https://www.fda.gov/media/71727/download",
        keywords=["ich q3a", "q3b", "impurity", "reporting threshold",
                  "identification threshold", "qualification threshold", "0.05", "0.10",
                  "0.15", "whichever is lower", "maximum daily dose", "limit", "why"],
    ),

    # ── hERG: NO fixed regulatory cutoff (the honest refusal case) ───────────
    Source(
        id="herg-no-fixed-limit",
        tier=SourceTier.NORMATIVE_PRIMARY,
        title="hERG / cardiac safety — governed by ICH S7B + E14, no fixed numeric cutoff",
        citation="ICH S7B (nonclinical) and ICH E14 (clinical QT/QTc) / Q&A",
        text=(
            "There is NO single regulatory hERG 'threshold' a compound must pass. "
            "Proarrhythmic cardiac risk is assessed under ICH S7B (nonclinical in-"
            "vitro IKr/hERG + in-vivo QT) and ICH E14 (clinical QT/QTc), as an "
            "integrated risk assessment, not a pass/fail number. The commonly quoted "
            "~10 uM hERG screening value is an empirical DISCOVERY heuristic (a "
            "safety-margin rule of thumb versus free Cmax), not a regulatory "
            "acceptance limit."
        ),
        owner=None,
        verified=False,
        locator="https://database.ich.org/sites/default/files/E14-S7B_QAs_Step4_2022_0221.pdf",
        keywords=["herg", "ikr", "cardiotoxicity", "qt", "qtc", "ich s7b", "ich e14",
                  "cardiac", "no fixed", "threshold", "limit", "10 um", "heuristic", "why"],
    ),

    # ── Lipinski Ro5: an empirical heuristic, not a spec ─────────────────────
    Source(
        id="lit-lipinski-ro5",
        tier=SourceTier.PEER_REVIEWED,
        title="Lipinski Rule of Five — empirical developability heuristic",
        citation="Lipinski et al., Adv. Drug Deliv. Rev. (Rule of Five)",
        text=(
            "The Rule of Five (MW <=500, logP <=5, H-bond donors <=5, acceptors "
            "<=10) is an EMPIRICAL statistical observation about oral drug-likeness "
            "derived from marketed/advanced oral drugs — a developability heuristic, "
            "explicitly NOT a regulatory specification or a hard limit, with many "
            "known exceptions (e.g. substrates of active transport)."
        ),
        owner=None,
        verified=True,
        locator="https://doi.org/10.1016/S0169-409X(96)00423-1",
        keywords=["lipinski", "rule of five", "ro5", "mw 500", "logp", "hbond",
                  "oral", "drug-likeness", "heuristic", "developability", "not regulatory",
                  "why", "limit"],
    ),

    # ── Tier C: firm's QA-validated control SOP ──────────────────────────────
    Source(
        id="sop-impurity-control",
        tier=SourceTier.ORG_VALIDATED,
        title="Internal SOP: impurity control strategy & specification setting",
        citation="SOP-CMC-IMP-021 rev B (QA-approved)",
        text=(
            "Our validated SOP operationalises ICH M7 / Q3A impurity control: how we "
            "classify impurities, set acceptance criteria, and justify specification "
            "limits against the batch and tox data on file. It records HOW we apply "
            "the limits and the firm's own supporting evidence; it does not restate "
            "the external derivation of the guideline figures."
        ),
        owner=None,
        verified=True,
        locator="dms://SOP-CMC-IMP-021",
        keywords=["sop", "impurity", "control strategy", "specification", "acceptance",
                  "qualification", "justification", "batch data"],
    ),
]


_PERSONAL: List[Source] = [
    Source(
        id="note-alice-cmc",
        tier=SourceTier.UNVERIFIED_PERSONAL,
        title="Alice's working note (draft, unverified)",
        citation="personal note — not reviewed",
        text=(
            "Draft thought: our genotoxic impurity is just over 1.5 ug/day at the "
            "highest clinical dose — maybe we can justify a higher limit via a "
            "compound-specific risk assessment? Need to confirm — my own guess."
        ),
        owner="alice",
        verified=False,
        locator="note://alice/2026-10-10",
        keywords=["ttc", "1.5", "genotoxic", "mutagenic", "impurity", "compound-specific",
                  "higher limit", "clinical dose"],
    ),
    Source(
        id="note-bob-cmc",
        tier=SourceTier.UNVERIFIED_PERSONAL,
        title="Bob's working note (draft, unverified)",
        citation="personal note — not reviewed",
        text=(
            "I'm pretty sure anything under 10 uM hERG is automatically fine to "
            "progress, that's the rule."
        ),
        owner="bob",
        verified=False,
        locator="note://bob/2026-10-05",
        keywords=["herg", "10 um", "progress", "rule", "cardiac"],
    ),
]


def load_corpus() -> List[Source]:
    return list(_SHARED) + list(_PERSONAL)
