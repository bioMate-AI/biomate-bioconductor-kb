"""ClinicalTrials.gov (API v2 JSON) -> corpus_fs documents.

One trial = one document ``/papers/<NCT id>/sections/<Section>.lines``. Sections carry the study's own text only (nothing
generated), so every grep / cat / quote is grounded in the registry record. Stdlib only, Python 3.9-safe.
"""
from __future__ import annotations

import glob
import gzip
import json
from typing import Any, Dict, Iterable, Iterator, List, Optional


def _g(d: Any, *path: str, default: Any = None) -> Any:
    for p in path:
        if not isinstance(d, dict):
            return default
        d = d.get(p)
    return default if d is None else d


def _lines(*parts: Optional[str]) -> str:
    return "\n".join(p.strip() for p in parts if isinstance(p, str) and p.strip())


def ctgov_to_record(study: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    ps = study.get("protocolSection") or {}
    nct = _g(ps, "identificationModule", "nctId")
    if not isinstance(nct, str) or not nct:
        return None
    start = _g(ps, "statusModule", "startDateStruct", "date")
    year = int(start[:4]) if isinstance(start, str) and start[:4].isdigit() else None
    blocks: List[Dict[str, Any]] = []

    def add(section: str, text: str, kind: str = "text") -> None:
        if text and text.strip():
            blocks.append({"section": section, "kind": kind, "text": text.strip()})

    add("Overview", _lines(_g(ps, "identificationModule", "briefTitle"), _g(ps, "identificationModule", "officialTitle"),
                           "Sponsor: %s" % _g(ps, "sponsorCollaboratorsModule", "leadSponsor", "name", default="")
                           if _g(ps, "sponsorCollaboratorsModule", "leadSponsor", "name") else None))
    add("Summary", _g(ps, "descriptionModule", "briefSummary", default=""))
    add("Description", _g(ps, "descriptionModule", "detailedDescription", default=""))
    conds = _g(ps, "conditionsModule", "conditions", default=[]) or []
    kws = _g(ps, "conditionsModule", "keywords", default=[]) or []
    add("Conditions", _lines("Conditions: " + "; ".join(conds) if conds else None, "Keywords: " + "; ".join(kws) if kws else None), "field")
    dm = ps.get("designModule") or {}
    di = dm.get("designInfo") or {}
    add("Design", _lines(
        "Study type: %s" % dm["studyType"] if dm.get("studyType") else None,
        "Phase: %s" % ", ".join(dm["phases"]) if dm.get("phases") else None,
        "Allocation: %s" % di["allocation"] if di.get("allocation") else None,
        "Intervention model: %s" % di["interventionModel"] if di.get("interventionModel") else None,
        "Masking: %s" % _g(di, "maskingInfo", "masking") if _g(di, "maskingInfo", "masking") else None,
        "Enrollment: %s" % _g(dm, "enrollmentInfo", "count") if _g(dm, "enrollmentInfo", "count") is not None else None), "field")
    arms = []
    for a in _g(ps, "armsInterventionsModule", "armGroups", default=[]) or []:
        arms.append("Arm: %s (%s) %s" % (a.get("label", ""), a.get("type", ""), a.get("description", "")))
    ints = []
    for i in _g(ps, "armsInterventionsModule", "interventions", default=[]) or []:
        ints.append("Intervention: %s (%s) %s %s" % (i.get("name", ""), i.get("type", ""), i.get("description", ""),
                                                      ("also known as " + "; ".join(i["otherNames"])) if i.get("otherNames") else ""))
    add("Interventions", _lines(*(arms + ints)), "field")
    outs = []
    for kind, key in (("Primary", "primaryOutcomes"), ("Secondary", "secondaryOutcomes")):
        for o in _g(ps, "outcomesModule", key, default=[]) or []:
            outs.append("%s outcome: %s. %s Time frame: %s" % (kind, o.get("measure", ""), o.get("description", ""), o.get("timeFrame", "")))
    add("Outcomes", _lines(*outs), "field")
    em = ps.get("eligibilityModule") or {}
    demo = ["%s: %s" % (lab, em[k]) for lab, k in (("Sex", "sex"), ("Minimum age", "minimumAge"), ("Maximum age", "maximumAge")) if em.get(k)]
    add("Eligibility", _lines(em.get("eligibilityCriteria"), "; ".join(demo) if demo else None))   # only text present in the record
    sm = ps.get("statusModule") or {}
    add("Status", _lines("Overall status: %s" % sm["overallStatus"] if sm.get("overallStatus") else None,
                         "Why stopped: %s" % sm["whyStopped"] if sm.get("whyStopped") else None,
                         "Start: %s" % start if start else None,
                         "Completion: %s" % _g(sm, "completionDateStruct", "date") if _g(sm, "completionDateStruct", "date") else None), "field")
    rs = study.get("resultsSection") or {}
    if rs:
        res = []
        for m in _g(rs, "outcomeMeasuresModule", "outcomeMeasures", default=[]) or []:
            res.append("Result measure: %s. %s" % (m.get("title", ""), m.get("description", "")))
        res.append(_g(rs, "moreInfoModule", "limitationsAndCaveats", "description", default="") or "")
        add("Results", _lines(*res))
        ae = []
        for g in _g(rs, "adverseEventsModule", "eventGroups", default=[]) or []:
            ae.append("AE group %s: serious %s/%s, other %s/%s" % (g.get("title", ""), g.get("seriousNumAffected", "?"), g.get("seriousNumAtRisk", "?"),
                                                                    g.get("otherNumAffected", "?"), g.get("otherNumAtRisk", "?")))
        add("AdverseEvents", _lines(_g(rs, "adverseEventsModule", "description"), *ae), "field")
    if not blocks:
        return None
    return {"doc_id": nct, "title": _g(ps, "identificationModule", "briefTitle"), "year": year, "source": "ClinicalTrials.gov",
            "url": "https://clinicaltrials.gov/study/%s" % nct, "licence": "Public domain (U.S. National Library of Medicine)", "blocks": blocks}


def iter_records(paths: Iterable[str]) -> Iterator[Dict[str, Any]]:
    for p in paths:
        with gzip.open(p, "rt", encoding="utf-8") as fh:
            for line in fh:
                if line.strip():
                    rec = ctgov_to_record(json.loads(line))
                    if rec:
                        yield rec


def ingest_parts(index: Any, pattern: str, batch: int = 20000) -> Dict[str, int]:
    """Ingest ``studies_part_*.jsonl.gz`` files in large batches (each ingest call re-optimises the FTS index)."""
    totals = {"documents": 0, "blocks": 0, "skipped_documents": 0, "duplicate_documents": 0}
    buf: List[Dict[str, Any]] = []
    for rec in iter_records(sorted(glob.glob(pattern))):
        buf.append(rec)
        if len(buf) >= batch:
            for k, v in index.ingest(buf).items():
                totals[k] = totals.get(k, 0) + v
            buf = []
    if buf:
        for k, v in index.ingest(buf).items():
            totals[k] = totals.get(k, 0) + v
    return totals
