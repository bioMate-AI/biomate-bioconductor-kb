"""Normalize historical and live QC records without inventing outcomes/actions."""
from __future__ import annotations


def normalize_qc_events(events):
    rows = []
    for event in events or []:
        if not isinstance(event, dict):
            continue
        nested = event.get("failures") or event.get("warnings")
        if isinstance(nested, list) and nested:
            base = {k: v for k, v in event.items() if k not in ("failures", "warnings")}
            for item in nested:
                detail = item if isinstance(item, dict) else {"message": str(item)}
                row = {**base, **detail}
                row.update({
                    "ts": detail.get("ts") or event.get("ts") or event.get("timestamp"),
                    "gate": detail.get("gate") or detail.get("metric") or event.get("process_name"),
                    "measured": detail.get("measured", detail.get("value")),
                    "status": "advisory" if detail.get("advisory") or event.get("type") == "warning" else "fail",
                })
                rows.append(row)
        else:
            row = dict(event)
            row["ts"] = event.get("ts") or event.get("timestamp")
            row["gate"] = event.get("gate") or event.get("metric") or event.get("process_name")
            row["measured"] = event.get("measured", event.get("value"))
            status = str(event.get("status") or event.get("action") or "").lower()
            row["status"] = {
                "passed": "pass", "ok": "pass", "failed": "fail", "halt": "fail",
                "warning": "advisory", "error": "unavailable",
            }.get(status, status if status in ("pass", "fail", "advisory", "unavailable") else "not_evaluated")
            rows.append(row)
    return rows


def assess_qc_document(document, checker, source, gate_checker=None):
    """Reconstruct findings from a structured output, without dispatching actions."""
    if not isinstance(document, dict):
        return [{"gate": "QC", "status": "unavailable", "source": source}]
    process = document.get("process")
    rows = []
    for metric in document.get("_all_metrics", []):
        passed = metric.get("pass")
        rows.append({
            **metric, "gate": metric.get("name"), "measured": metric.get("measured"),
            "status": "pass" if passed is True else "fail" if passed is False else "not_evaluated",
            "source": source, "execution_control": "assessment_only",
        })
    if rows:
        return rows
    if not process:
        return [{"gate": "QC", "status": "not_evaluated", "source": source,
                 "message": "The source does not identify its producing process."}]
    passed, failures = checker(process, document)
    if failures:
        return normalize_qc_events([{
            "process_name": process, "failures": failures, "source": source,
            "execution_control": "assessment_only",
        }])
    if gate_checker:
        gates = gate_checker(process, document)
        if gates:
            return normalize_qc_events([{**gate, "source": source,
                "process_name": process, "execution_control": "assessment_only"} for gate in gates])
    return [{
        "gate": process, "status": "pass" if passed is True else "not_evaluated",
        "source": source, "metrics": document, "execution_control": "assessment_only",
        "message": ("No threshold violations in the available evaluated metrics." if passed is True
                    else "No supported QC rule evaluated these metrics."),
    }]
