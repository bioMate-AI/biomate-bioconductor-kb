"""Structural audit only; does not certify semantic quality or holdout independence."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path


def message_hash(messages):
    return hashlib.sha256(json.dumps(messages, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def audit_overlap(training, evaluation_paths):
    signatures, prompts = set(), set()
    with open(training) as stream:
        for line in stream:
            row = json.loads(line)
            messages = row["messages"]
            signatures.add(message_hash(messages))
            prompts.add(message_hash([m for m in messages if m.get("role") == "user"]))
    results = []
    for path in evaluation_paths:
        counts = {"rows": 0, "checked_rows": 0, "skipped_schema": 0,
                  "exact_message_overlap": 0, "exact_user_message_overlap": 0}
        digest, tasks = hashlib.sha256(), Counter()
        with open(path, "rb") as stream:
            for raw in stream:
                digest.update(raw)
                if not raw.strip():
                    continue
                row = json.loads(raw)
                counts["rows"] += 1
                messages = row.get("messages")
                if not isinstance(messages, list) or not any(m.get("role") == "user" for m in messages):
                    counts["skipped_schema"] += 1
                    continue
                counts["checked_rows"] += 1
                counts["exact_message_overlap"] += message_hash(messages) in signatures
                if message_hash([m for m in messages if m.get("role") == "user"]) in prompts:
                    counts["exact_user_message_overlap"] += 1
                    tasks[row.get("task", "missing")] += 1
        results.append({"file": str(path), "sha256": digest.hexdigest(), **counts,
                        "user_overlap_by_task": dict(tasks)})
    return results


def audit(path):
    tasks, sources, signatures = Counter(), Counter(), Counter()
    invalid = []
    rows = with_family = with_evidence = 0
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for number, raw in enumerate(stream, 1):
            digest.update(raw)
            if not raw.strip():
                continue
            rows += 1
            try:
                row = json.loads(raw)
                messages = row["messages"]
                if not isinstance(messages, list) or not messages:
                    raise ValueError("messages must be a nonempty list")
                for message in messages:
                    if message.get("role") not in {"system", "user", "assistant", "tool"}:
                        raise ValueError("unsupported role")
                    if not isinstance(message.get("content"), str) or not message["content"].strip():
                        raise ValueError("blank or non-string content")
                if not any(m["role"] == "assistant" for m in messages):
                    raise ValueError("missing assistant target")
                canonical = json.dumps(messages, sort_keys=True, ensure_ascii=False)
                signatures[hashlib.sha256(canonical.encode()).hexdigest()] += 1
                tasks[str(row.get("task", "missing"))] += 1
                sources[str(row.get("source", "missing"))] += 1
                with_family += bool(row.get("source_family") or row.get("source_groups"))
                with_evidence += bool(row.get("evidence") or row.get("citations"))
            except (ValueError, KeyError, TypeError, AttributeError) as error:
                invalid.append({"line": number, "error": str(error)})
    return {"sha256": digest.hexdigest(), "rows": rows, "invalid_rows": invalid,
            "tasks": dict(tasks), "sources": dict(sources),
            "exact_duplicate_messages": sum(n - 1 for n in signatures.values()),
            "rows_with_explicit_source_family": with_family,
            "rows_with_explicit_evidence_metadata": with_evidence,
            "limitations": ["Evidence may be embedded in messages; metadata absence is not proof of absence.",
                            "No semantic quality, token-mask, license, or held-out leakage certification.",
                            "Duplicate counts may reflect intentional sampling weights; do not silently delete."]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data")
    parser.add_argument("--out", required=True)
    parser.add_argument("--eval", nargs="*", default=[])
    args = parser.parse_args()
    result = audit(args.data)
    if args.eval:
        result["eval_overlap"] = audit_overlap(args.data, args.eval)
        result["limitations"].append("Overlap check covers exact messages only; skipped schemas and source-family overlaps remain unaudited.")
    Path(args.out).write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({key: result[key] for key in ("rows", "exact_duplicate_messages", "rows_with_explicit_source_family")}))
    raise SystemExit(bool(result["invalid_rows"]))
