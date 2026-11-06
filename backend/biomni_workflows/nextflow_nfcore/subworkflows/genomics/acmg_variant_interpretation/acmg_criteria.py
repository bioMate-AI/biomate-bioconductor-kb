#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
acmg_criteria.py -- Mechanically-computable ACMG/AMP-2015 criteria engine.

HONESTY CONTRACT
================
This module does NOT emit a black-box "Pathogenic" verdict. It applies ONLY
the subset of ACMG/AMP-2015 (Richards et al., Genet Med 2015; PMID 25741868)
criteria that are *defensibly computable* from structured evidence:

  - Population frequency criteria  : BA1, BS1, PM2_Supporting
  - In-silico concordance criteria : PP3, BP4
  - Predicted loss-of-function     : PVS1 (FLAGGED, not auto-strong)

Every other criterion (PS3 functional, PP1/BS4 segregation, PM3 in-trans,
PS1/PM5 same-residue, PM1 hotspot, PP4 phenotype, BP2 etc.) REQUIRES human,
functional, or clinical judgment and is therefore returned in the
`requires_expert_review` list -- NEVER auto-applied.

The provisional tier returned by `classify()` is a TRANSPARENT SUM of the
auto-applied criteria only. It is explicitly labelled as
"computed from N automatable criteria -- NOT a final clinical classification".
Where evidence is missing, the criterion is `unknown` and the provisional
call defaults toward VUS. No evidence is ever fabricated.

This module is deterministic: identical evidence gives identical output. It
draws no random numbers of any kind. Every applied criterion cites the exact
evidence value and source that triggered it.

Python 3.9-safe: no PEP 604 unions, no `match`, typing via typing.* only.
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional, Tuple

# ---------------------------------------------------------------------------
# Threshold constants (documented, defensible defaults)
# ---------------------------------------------------------------------------

# BA1: stand-alone benign. gnomAD/ExAC allele frequency > 5% (ACMG 2015 text).
BA1_AF = 0.05

# BS1: strong benign. AF greater than expected for the disorder. In the absence
# of a gene/disease-specific max credible AF, we use a conservative generic
# threshold of 1% (a common default; the max-credible-AF calculator of
# Whiffin et al. 2017 supersedes this when a gene-specific value is supplied).
BS1_AF_DEFAULT = 0.01

# PM2_Supporting: absent or ultra-rare in population databases. The 2020
# ClinGen SVI recommendation downgraded PM2 to Supporting strength. We treat
# AF strictly below this as ultra-rare/absent. gnomAD grpmax/popmax preferred.
PM2_AF = 0.0001  # 0.01%

# In-silico predictor concordance thresholds.
#   REVEL   : Ioannidis et al. 2016. >=0.75 => pathogenic support (PP3),
#             <=0.25 => benign support (BP4).  Middle band => no call.
REVEL_PATH = 0.75
REVEL_BENIGN = 0.25
#   AlphaMissense: Cheng et al. Science 2023. class in {likely_pathogenic,
#             ambiguous, likely_benign}. Pathogenicity score >=0.564 => LP,
#             <=0.34 => LB (paper thresholds).
AM_PATH = 0.564
AM_BENIGN = 0.34
#   CADD PHRED: scaled deleteriousness. >=25 often cited as damaging support,
#             <10 as tolerated. CADD alone is weak; used only as a tie-breaker
#             and never as the sole basis for PP3/BP4.
CADD_PATH = 25.0
CADD_BENIGN = 10.0

# Consequence terms considered predicted loss-of-function (SO / VEP terms).
LOF_CONSEQUENCES = frozenset({
    "stop_gained",
    "frameshift_variant",
    "splice_acceptor_variant",
    "splice_donor_variant",
    "start_lost",
    "stop_lost",
    "transcript_ablation",
})

# Gene constraint threshold at which loss-of-function is an established
# disease mechanism (proxy). gnomAD pLI >= 0.9 OR LOEUF <= 0.35 indicates the
# gene is LoF-intolerant. This is a *supporting* signal for PVS1 applicability,
# NOT proof of a LoF mechanism -- hence PVS1 is FLAGGED, never auto-Strong.
PLI_LOF_INTOLERANT = 0.9
LOEUF_LOF_INTOLERANT = 0.35


# ---------------------------------------------------------------------------
# Criteria that this engine will NEVER auto-apply (require expert review).
# Returned so the dossier is explicit about what a human must still assess.
# ---------------------------------------------------------------------------
EXPERT_REVIEW_CRITERIA = (
    ("PS1", "Same amino-acid change as an established pathogenic variant "
            "(requires curated known-pathogenic mapping)."),
    ("PS2", "De novo (maternity/paternity confirmed) -- requires trio data."),
    ("PS3", "Well-established functional studies show a damaging effect."),
    ("PS4", "Prevalence in affecteds significantly increased vs controls -- "
            "requires case/control cohort."),
    ("PM1", "Located in a mutational hotspot / critical functional domain."),
    ("PM3", "For recessive disorders, detected in trans with a pathogenic "
            "variant -- requires phasing."),
    ("PM5", "Novel missense at a residue where a different pathogenic missense "
            "was seen before."),
    ("PM6", "Assumed de novo without confirmation of parentage."),
    ("PP1", "Co-segregation with disease in multiple affected family members."),
    ("PP2", "Missense in a gene with low benign-missense rate + missense "
            "mechanism -- requires gene-level curation."),
    ("PP4", "Phenotype/family history highly specific for the gene."),
    ("PP5", "Reputable source reports pathogenic (deprecated by ClinGen)."),
    ("BS3", "Well-established functional studies show NO damaging effect."),
    ("BS4", "Lack of segregation in affected family members."),
    ("BP1", "Missense in a gene where only truncating cause disease."),
    ("BP2", "Observed in trans/ cis with a pathogenic variant inconsistent "
            "with disease."),
    ("BP3", "In-frame indel in a repetitive region without known function."),
    ("BP5", "Variant found in a case with an alternate molecular cause."),
    ("BP6", "Reputable source reports benign (deprecated by ClinGen)."),
    ("BP7", "Synonymous with no predicted splice impact + not conserved."),
)


# ---------------------------------------------------------------------------
# Result container
# ---------------------------------------------------------------------------
class CriterionCall:
    """One ACMG criterion decision with its supporting evidence citation."""

    __slots__ = ("code", "applied", "strength", "direction", "evidence", "rationale")

    def __init__(self, code, applied, strength, direction, evidence, rationale):
        # code: str e.g. "BA1"
        # applied: True / False / None (None == unknown, evidence missing)
        # strength: "stand_alone"|"strong"|"moderate"|"supporting"|None
        # direction: "benign"|"pathogenic"|None
        # evidence: dict of the exact values + source that triggered the call
        # rationale: human-readable one-liner
        self.code = code
        self.applied = applied
        self.strength = strength
        self.direction = direction
        self.evidence = evidence
        self.rationale = rationale

    def to_dict(self):
        # type: () -> Dict[str, Any]
        return {
            "code": self.code,
            "applied": self.applied,
            "strength": self.strength,
            "direction": self.direction,
            "evidence": self.evidence,
            "rationale": self.rationale,
        }


# ---------------------------------------------------------------------------
# Evidence extraction helpers (tolerant of missing / string values)
# ---------------------------------------------------------------------------
def _as_float(value):
    # type: (Any) -> Optional[float]
    """Best-effort float parse. Returns None for missing/'.'/''/non-numeric."""
    if value is None:
        return None
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        f = float(value)
        return f
    s = str(value).strip()
    if s == "" or s == "." or s.upper() in ("NA", "N/A", "NAN", "NONE"):
        return None
    # VEP can emit '&'-joined multi-allele values; take the max magnitude.
    if "&" in s:
        parts = [p for p in s.split("&") if p not in ("", ".")]
        vals = []
        for p in parts:
            fv = _as_float(p)
            if fv is not None:
                vals.append(fv)
        if not vals:
            return None
        return max(vals)
    try:
        return float(s)
    except ValueError:
        return None


def _max_gnomad_af(ev):
    # type: (Dict[str, Any]) -> Tuple[Optional[float], Optional[str]]
    """Return (max_af, source_field) across the provided gnomAD AF fields.

    We use the maximum across supplied population/global AF fields, which is
    the conservative choice for BENIGN criteria (BA1/BS1) -- a common variant
    in ANY population is not a good candidate for pathogenic. grpmax/popmax is
    preferred when present.
    """
    candidate_fields = [
        "gnomad_af_grpmax", "gnomad_af_popmax", "gnomad_popmax_af",
        "gnomad_af", "gnomADg_AF", "gnomADe_AF", "max_af", "MAX_AF", "AF",
    ]
    best_af = None  # type: Optional[float]
    best_src = None  # type: Optional[str]
    for f in candidate_fields:
        if f in ev:
            af = _as_float(ev[f])
            if af is not None and (best_af is None or af > best_af):
                best_af = af
                best_src = f
    return best_af, best_src


# ---------------------------------------------------------------------------
# Individual criterion evaluators. Each returns a CriterionCall.
# ---------------------------------------------------------------------------
def eval_ba1(ev):
    # type: (Dict[str, Any]) -> CriterionCall
    af, src = _max_gnomad_af(ev)
    if af is None:
        return CriterionCall("BA1", None, "stand_alone", "benign",
                             {"gnomad_af": None},
                             "gnomAD allele frequency unavailable -- cannot assess BA1.")
    applied = af > BA1_AF
    return CriterionCall(
        "BA1", applied, "stand_alone", "benign",
        {"gnomad_af": af, "source_field": src, "threshold": BA1_AF},
        ("gnomAD AF %.4g > %.2g (BA1 stand-alone benign)." % (af, BA1_AF))
        if applied else
        ("gnomAD AF %.4g <= %.2g (BA1 not met)." % (af, BA1_AF)),
    )


def eval_bs1(ev, max_credible_af=None):
    # type: (Dict[str, Any], Optional[float]) -> CriterionCall
    af, src = _max_gnomad_af(ev)
    thr = max_credible_af if max_credible_af is not None else BS1_AF_DEFAULT
    if af is None:
        return CriterionCall("BS1", None, "strong", "benign",
                             {"gnomad_af": None, "threshold": thr},
                             "gnomAD allele frequency unavailable -- cannot assess BS1.")
    # BS1 is only meaningful below BA1 (BA1 supersedes).
    applied = (af > thr) and (af <= BA1_AF)
    if af > BA1_AF:
        rationale = ("AF %.4g exceeds BA1 threshold; BA1 supersedes BS1." % af)
    elif applied:
        rationale = ("gnomAD AF %.4g > disease-max %.2g (BS1 strong benign)." % (af, thr))
    else:
        rationale = ("gnomAD AF %.4g <= disease-max %.2g (BS1 not met)." % (af, thr))
    return CriterionCall(
        "BS1", applied, "strong", "benign",
        {"gnomad_af": af, "source_field": src, "threshold": thr,
         "max_credible_af_supplied": max_credible_af is not None},
        rationale,
    )


def eval_pm2_supporting(ev):
    # type: (Dict[str, Any]) -> CriterionCall
    af, src = _max_gnomad_af(ev)
    if af is None:
        # Absent from gnomAD is itself PM2-supporting evidence, but ONLY if we
        # know the variant was queried against gnomAD. We require an explicit
        # 'gnomad_queried' flag to distinguish "absent" from "never looked".
        if ev.get("gnomad_queried") is True:
            return CriterionCall(
                "PM2_Supporting", True, "supporting", "pathogenic",
                {"gnomad_af": 0.0, "gnomad_queried": True, "threshold": PM2_AF},
                "Absent from gnomAD (queried) -- PM2_Supporting.")
        return CriterionCall(
            "PM2_Supporting", None, "supporting", "pathogenic",
            {"gnomad_af": None, "gnomad_queried": ev.get("gnomad_queried")},
            "gnomAD not queried / AF unknown -- cannot assess PM2 (absence unconfirmed).")
    applied = af < PM2_AF
    return CriterionCall(
        "PM2_Supporting", applied, "supporting", "pathogenic",
        {"gnomad_af": af, "source_field": src, "threshold": PM2_AF},
        ("gnomAD AF %.4g < %.2g -- ultra-rare (PM2_Supporting)." % (af, PM2_AF))
        if applied else
        ("gnomAD AF %.4g >= %.2g -- not rare enough for PM2." % (af, PM2_AF)),
    )


def _insilico_direction(ev):
    # type: (Dict[str, Any]) -> Tuple[Optional[str], Dict[str, Any]]
    """Combine available in-silico predictors into a single concordant call.

    Returns ("pathogenic"|"benign"|"conflicting"|None, evidence_dict).
    Requires that ALL available predictors agree; conflicting -> no call
    (this is the conservative, defensible behaviour -- we never let a single
    weak predictor override a disagreeing stronger one).
    """
    votes = []          # list of ("pathogenic"|"benign", predictor_name, value)
    used = {}           # type: Dict[str, Any]

    revel = _as_float(ev.get("revel") if "revel" in ev else ev.get("REVEL"))
    if revel is not None:
        used["REVEL"] = revel
        if revel >= REVEL_PATH:
            votes.append(("pathogenic", "REVEL", revel))
        elif revel <= REVEL_BENIGN:
            votes.append(("benign", "REVEL", revel))

    am = _as_float(ev.get("alphamissense") if "alphamissense" in ev
                   else ev.get("am_pathogenicity"))
    am_class = ev.get("am_class")
    if am is not None:
        used["AlphaMissense"] = am
        if am >= AM_PATH:
            votes.append(("pathogenic", "AlphaMissense", am))
        elif am <= AM_BENIGN:
            votes.append(("benign", "AlphaMissense", am))
    elif am_class in ("likely_pathogenic", "likely_benign"):
        used["AlphaMissense_class"] = am_class
        votes.append((
            "pathogenic" if am_class == "likely_pathogenic" else "benign",
            "AlphaMissense_class", am_class))

    cadd = _as_float(ev.get("cadd_phred") if "cadd_phred" in ev
                     else ev.get("CADD_PHRED"))
    if cadd is not None:
        used["CADD_PHRED"] = cadd
        if cadd >= CADD_PATH:
            votes.append(("pathogenic", "CADD", cadd))
        elif cadd <= CADD_BENIGN:
            votes.append(("benign", "CADD", cadd))

    if not votes:
        return None, used

    directions = set(v[0] for v in votes)
    if len(directions) > 1:
        used["conflict"] = [{"predictor": v[1], "direction": v[0], "value": v[2]}
                            for v in votes]
        return "conflicting", used
    used["concordant_predictors"] = [
        {"predictor": v[1], "value": v[2]} for v in votes]
    return votes[0][0], used


def eval_pp3_bp4(ev):
    # type: (Dict[str, Any]) -> CriterionCall
    """PP3 (pathogenic support) / BP4 (benign support) from in-silico concordance.

    Only ONE of PP3/BP4 can fire, and only when predictors agree.
    """
    direction, used = _insilico_direction(ev)
    if direction is None:
        return CriterionCall("PP3_BP4", None, "supporting", None, used,
                             "No usable in-silico predictor scores -- PP3/BP4 unknown.")
    if direction == "conflicting":
        return CriterionCall("PP3_BP4", False, "supporting", None, used,
                             "In-silico predictors conflict -- neither PP3 nor BP4 applied.")
    if direction == "pathogenic":
        return CriterionCall("PP3", True, "supporting", "pathogenic", used,
                             "Multiple lines of computational evidence support a deleterious effect (PP3).")
    return CriterionCall("BP4", True, "supporting", "benign", used,
                         "Multiple lines of computational evidence support a benign effect (BP4).")


def eval_pvs1_flag(ev):
    # type: (Dict[str, Any]) -> CriterionCall
    """PVS1 -- predicted null variant in a LoF-mechanism gene.

    We deliberately FLAG rather than auto-apply at Very-Strong. Correct PVS1
    application (ClinGen SVI, Abou Tayoun et al. 2018) requires exon/transcript-
    level reasoning (NMD escape, last-exon rules, biologically-relevant
    transcript, established LoF mechanism). We compute the *preconditions*
    (LoF consequence + LoF-intolerant gene) and mark the rest as needing review.
    """
    consequence = str(ev.get("consequence", ev.get("Consequence", ""))).lower()
    csq_terms = set(t for t in consequence.replace("&", ",").split(",") if t)
    is_lof = bool(csq_terms & LOF_CONSEQUENCES)

    pli = _as_float(ev.get("pli") if "pli" in ev else ev.get("pLI"))
    loeuf = _as_float(ev.get("loeuf") if "loeuf" in ev else ev.get("LOEUF"))
    lof_intolerant = None  # type: Optional[bool]
    constraint_ev = {}
    if pli is not None:
        constraint_ev["pLI"] = pli
        lof_intolerant = pli >= PLI_LOF_INTOLERANT
    if loeuf is not None:
        constraint_ev["LOEUF"] = loeuf
        li_loeuf = loeuf <= LOEUF_LOF_INTOLERANT
        lof_intolerant = li_loeuf if lof_intolerant is None else (lof_intolerant or li_loeuf)

    if not is_lof:
        return CriterionCall("PVS1", False, "very_strong", "pathogenic",
                             {"consequence": consequence, "is_lof": False},
                             "Not a predicted loss-of-function consequence -- PVS1 not applicable.")

    ev_out = {"consequence": consequence, "is_lof": True,
              "lof_intolerant_gene": lof_intolerant}
    ev_out.update(constraint_ev)

    if lof_intolerant is None:
        return CriterionCall(
            "PVS1", None, "very_strong", "pathogenic", ev_out,
            "Predicted LoF, but gene constraint (pLI/LOEUF) unavailable -- "
            "PVS1 applicability UNKNOWN; requires expert transcript/mechanism review.")
    if lof_intolerant:
        return CriterionCall(
            "PVS1", "flag", "very_strong", "pathogenic", ev_out,
            "Predicted LoF in a LoF-intolerant gene -- PVS1 PRECONDITIONS MET but "
            "FLAGGED ONLY: final strength requires expert NMD / last-exon / "
            "biologically-relevant-transcript review (ClinGen SVI PVS1).")
    return CriterionCall(
        "PVS1", False, "very_strong", "pathogenic", ev_out,
        "Predicted LoF but gene is not LoF-intolerant (pLI/LOEUF) -- "
        "LoF mechanism not established; PVS1 not auto-applied.")


# ---------------------------------------------------------------------------
# ClinVar cross-reference (reported, NOT used to auto-classify)
# ---------------------------------------------------------------------------
def summarize_clinvar(ev):
    # type: (Dict[str, Any]) -> Optional[Dict[str, Any]]
    """Return the ClinVar assertion + review status as *reference context*.

    ClinVar's clinical significance is an EXISTING expert assertion, not one of
    our computed criteria. We surface it (with review-status star level) so a
    reviewer can compare our computed criteria against the current ClinVar
    consensus -- but we never copy ClinVar's call into our provisional tier.
    """
    def _clean(x):
        if x is None:
            return None
        s = str(x).strip()
        if s in ("", ".") or s.upper() in ("NA", "N/A", "NONE"):
            return None
        return s
    sig = _clean(ev.get("clinvar_sig") or ev.get("clinvar_clnsig")
                 or ev.get("CLNSIG"))
    review = _clean(ev.get("clinvar_review") or ev.get("clinvar_clnrevstat")
                    or ev.get("CLNREVSTAT"))
    if sig is None and review is None:
        return None
    star_map = {
        "practice_guideline": 4,
        "reviewed_by_expert_panel": 3,
        "criteria_provided,_multiple_submitters,_no_conflicts": 2,
        "criteria_provided,_single_submitter": 1,
        "criteria_provided,_conflicting_interpretations": 1,
        "no_assertion_criteria_provided": 0,
        "no_assertion_provided": 0,
    }
    review_key = str(review).strip().lower().replace(" ", "_") if review else None
    stars = star_map.get(review_key) if review_key else None
    return {
        "clinical_significance": sig,
        "review_status": review,
        "review_stars": stars,
        "note": ("ClinVar assertion shown for reference/comparison only; "
                 "NOT incorporated into the computed provisional tier."),
    }


# ---------------------------------------------------------------------------
# Aggregation -> transparent provisional tier
# ---------------------------------------------------------------------------
# Strength -> ordinal point value, following the Bayesian/points reframing of
# ACMG (Tavtigian et al. 2020, PMID 32720330), used here ONLY as a transparent
# additive summary. Pathogenic strengths add positive points; benign subtract.
_STRENGTH_POINTS = {
    "very_strong": 8,
    "strong": 4,
    "moderate": 2,
    "supporting": 1,
    "stand_alone": 8,  # BA1 is treated as decisive benign
}


def _points_for(call):
    # type: (CriterionCall) -> int
    if call.applied is not True:  # only genuine True contributes; 'flag'/None/False do not
        return 0
    pts = _STRENGTH_POINTS.get(call.strength, 0)
    if call.direction == "benign":
        return -pts
    if call.direction == "pathogenic":
        return pts
    return 0


def classify(evidence, max_credible_af=None):
    # type: (Dict[str, Any], Optional[float]) -> Dict[str, Any]
    """Evaluate all mechanically-computable criteria and build a dossier fragment.

    `evidence` is a flat dict of annotation values for ONE variant (see
    README for accepted keys). Returns a dict with:
      - applied_criteria     : criteria that genuinely fired (True)
      - flagged_criteria     : PVS1-style flags needing expert confirmation
      - not_applicable       : criteria evaluated but not met (False)
      - unknown_criteria     : criteria we could not assess (evidence missing)
      - requires_expert_review : criteria this engine never auto-applies
      - clinvar_reference    : ClinVar assertion (context only), or None
      - provisional          : transparent additive tier (labelled, non-clinical)
    """
    ba1 = eval_ba1(evidence)
    calls = [
        ba1,
        eval_bs1(evidence, max_credible_af=max_credible_af),
        eval_pm2_supporting(evidence),
        eval_pp3_bp4(evidence),
        eval_pvs1_flag(evidence),
    ]

    applied, flagged, not_applicable, unknown = [], [], [], []
    for c in calls:
        d = c.to_dict()
        if c.applied is True:
            applied.append(d)
        elif c.applied == "flag":
            flagged.append(d)
        elif c.applied is False:
            not_applicable.append(d)
        else:  # None
            unknown.append(d)

    # If BA1 (stand-alone benign) fired, ClinGen rules say it overrides all
    # pathogenic supporting evidence -> provisional is Benign regardless of PM2.
    ba1_fired = ba1.applied is True

    points = sum(_points_for(c) for c in calls)

    # Transparent tier bands (Tavtigian 2020 points thresholds), clearly
    # labelled as provisional/computed-only.
    if ba1_fired:
        tier = "Benign (BA1 stand-alone)"
    elif points >= 10:
        tier = "Pathogenic (computed)"
    elif points >= 6:
        tier = "Likely Pathogenic (computed)"
    elif points <= -7:
        tier = "Benign (computed)"
    elif points <= -1:
        tier = "Likely Benign (computed)"
    else:
        tier = "Uncertain Significance (VUS)"

    n_auto = len(applied)
    provisional = {
        "tier": tier,
        "points": points,
        "n_automatable_criteria_applied": n_auto,
        "label": ("PROVISIONAL -- computed from %d automatable ACMG criteria. "
                  "This is NOT a final clinical classification. Expert review "
                  "of functional, segregation, phenotype and PVS1-mechanism "
                  "criteria is REQUIRED before any clinical use." % n_auto),
        "points_scheme": "Tavtigian et al. 2020 (PMID 32720330) additive summary",
        "default_toward_vus_on_missing_evidence": True,
    }

    expert = [{"code": c, "reason": r} for (c, r) in EXPERT_REVIEW_CRITERIA]

    return {
        "applied_criteria": applied,
        "flagged_criteria": flagged,
        "not_applicable_criteria": not_applicable,
        "unknown_criteria": unknown,
        "requires_expert_review": expert,
        "clinvar_reference": summarize_clinvar(evidence),
        "provisional": provisional,
    }


# ---------------------------------------------------------------------------
# Required-evidence gate (HONEST-FAIL support)
# ---------------------------------------------------------------------------
def has_minimum_evidence(evidence):
    # type: (Dict[str, Any]) -> Tuple[bool, List[str]]
    """A dossier should not be emitted from nothing.

    We require at least ONE real, usable evidence axis among:
      (a) a gnomAD allele frequency (any field), OR
      (b) at least one in-silico predictor score, OR
      (c) a functional consequence term (for PVS1 evaluation).
    Returns (ok, missing_axes). If not ok, the caller should HONEST-FAIL.
    """
    missing = []
    af, _ = _max_gnomad_af(evidence)
    has_af = af is not None or evidence.get("gnomad_queried") is True
    if not has_af:
        missing.append("gnomAD allele frequency")
    direction, used = _insilico_direction(evidence)
    has_insilico = bool(used)
    if not has_insilico:
        missing.append("in-silico predictor (REVEL/AlphaMissense/CADD)")
    consequence = str(evidence.get("consequence",
                                   evidence.get("Consequence", ""))).strip()
    has_csq = consequence not in ("", ".", "none")
    if not has_csq:
        missing.append("functional consequence")

    ok = has_af or has_insilico or has_csq
    return ok, missing
