"""Extract AGGREGATE, arm-level labels from downloaded ClinicalTrials.gov records.

These are trial-level summary results (outcome measures, adverse-event counts
with arm denominators, and participant-flow withdrawals). They are NOT
patient-level records: individual_patient_records stays 0. Aggregate efficacy
and safety can support outcome evidence and trial-held-out evaluation; they
cannot be silently expanded into per-patient survival/duration examples.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RAW = ROOT / "raw"
DISEASES = ["rheumatoid_arthritis", "asthma", "lupus"]

def g(d, *path, default=None):
    for k in path:
        if not isinstance(d, dict):
            return default
        d = d.get(k, {})
    return d if d != {} else default

def flow_withdrawals(rs):
    """Sum non-completion (withdrawal/discontinuation) across participant-flow periods."""
    pf = g(rs, "participantFlowModule", default={}) or {}
    total_dropped = 0
    reasons = {}
    for period in pf.get("periods", []) or []:
        for milestone in period.get("milestones", []) or []:
            # 'NOT COMPLETED' milestone carries drop counts; 'STARTED'/'COMPLETED' don't
            if str(milestone.get("type", "")).upper() in ("NOT COMPLETED", "NOTCOMPLETED"):
                for ach in milestone.get("achievements", []) or []:
                    try:
                        total_dropped += int(ach.get("numSubjects", 0) or 0)
                    except ValueError:
                        pass
        for dwt in period.get("dropWithdraws", []) or []:
            rtype = dwt.get("type", "unspecified")
            n = sum(int(r.get("numSubjects", 0) or 0) for r in dwt.get("reasons", []) or [])
            reasons[rtype] = reasons.get(rtype, 0) + n
    return total_dropped, reasons

def summarize_study(s):
    ps, rs = s.get("protocolSection", {}), s.get("resultsSection", {})
    nct = g(ps, "identificationModule", "nctId")
    ae = g(rs, "adverseEventsModule", default={}) or {}
    om = g(rs, "outcomeMeasuresModule", "outcomeMeasures", default=[]) or []
    dropped, reasons = flow_withdrawals(rs)
    return dict(
        nct=nct,
        title=g(ps, "identificationModule", "briefTitle"),
        phase=g(ps, "designModule", "phases", default=[]),
        enrollment=g(ps, "designModule", "enrollmentInfo", "count"),
        n_arms=len(g(ps, "armsInterventionsModule", "armGroups", default=[]) or []),
        interventions=[i.get("name") for i in g(ps, "armsInterventionsModule", "interventions", default=[]) or []],
        has_results=bool(rs),
        n_outcome_measures=len(om),
        n_primary_outcomes=sum(1 for o in om if str(o.get("type", "")).upper() == "PRIMARY"),
        # adverse events: arm denominators + event counts
        ae_serious_num_affected=sum(
            int(st.get("numAffected", 0) or 0)
            for e in ae.get("seriousEvents", []) or []
            for st in e.get("stats", []) or []
        ),
        ae_other_num_affected=sum(
            int(st.get("numAffected", 0) or 0)
            for e in ae.get("otherEvents", []) or []
            for st in e.get("stats", []) or []
        ),
        ae_group_denoms=[
            {"id": grp.get("id"), "seriousNumAtRisk": grp.get("seriousNumAtRisk"), "otherNumAtRisk": grp.get("otherNumAtRisk")}
            for grp in ae.get("eventGroups", []) or []
        ],
        withdrawals_total=dropped,
        withdrawal_reasons=reasons,
    )

register = {}
usable = []
for disease in DISEASES:
    studies = {}
    for p in sorted(RAW.glob(disease + "_trials_*.json")):
        for s in json.loads(p.read_text()).get("studies", []):
            nct = g(s, "protocolSection", "identificationModule", "nctId")
            if nct:
                studies[nct] = s
    recs = [summarize_study(s) for s in studies.values()]
    with_results = [r for r in recs if r["has_results"]]
    # "usable aggregate" = has results AND at least one primary outcome AND AE table
    usable_here = [
        r for r in with_results
        if r["n_primary_outcomes"] > 0 and (r["ae_serious_num_affected"] or r["ae_other_num_affected"])
    ]
    usable.extend(r["nct"] for r in usable_here)
    register[disease] = dict(
        candidate_studies=len(studies),
        with_results=len(with_results),
        with_primary_outcome=sum(1 for r in recs if r["n_primary_outcomes"] > 0),
        with_ae_counts=sum(1 for r in recs if r["ae_serious_num_affected"] or r["ae_other_num_affected"]),
        with_withdrawal_flow=sum(1 for r in recs if r["withdrawals_total"] > 0),
        usable_aggregate_efficacy_safety=len(usable_here),
        total_enrollment_with_results=sum(int(r["enrollment"] or 0) for r in with_results),
    )
    (ROOT / f"trial_labels_{disease}.json").write_text(json.dumps(recs, indent=2) + "\n")

register["_note"] = (
    "Aggregate arm-level labels only. individual_patient_records=0. "
    "Withdrawal counts are trial-level flow totals, NOT patient time-to-event. "
    "Usable = has results + >=1 primary outcome + AE counts."
)
register["_usable_trial_ncts"] = sorted(set(usable))
(ROOT / "trial_label_register.json").write_text(json.dumps(register, indent=2) + "\n")
print(json.dumps({k: v for k, v in register.items() if not k.startswith("_")}, indent=2))
print("\nusable aggregate trials:", len(set(usable)))
