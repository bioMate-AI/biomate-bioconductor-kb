#!/usr/bin/env python3
"""
Resolve unresolved workflow tool tokens using strict confidence matching.

Strategy:
1) For unresolved tokens, map to existing tools only when confidence is high and unique.
2) For remaining unresolved tokens, add a new tool record so token becomes resolvable.

No fuzzy low-confidence remaps are applied.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sqlite3
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


@dataclass
class ToolRow:
    tool_id: str
    name: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Resolve or add unresolved workflow tool tokens.")
    parser.add_argument("--db", default="backend/database/galaxy_ai_tools.db", help="Path to DB")
    parser.add_argument("--apply", action="store_true", help="Persist changes")
    parser.add_argument(
        "--report-json",
        default="backend/database/tmp/workflow_tool_resolution_report.json",
        help="Output report path",
    )
    return parser.parse_args()


def parse_tools_used(raw: Any) -> list[str]:
    if raw is None:
        return []
    text = str(raw).strip()
    if not text:
        return []
    if text.startswith("["):
        try:
            arr = json.loads(text)
            if isinstance(arr, list):
                return [str(x).strip() for x in arr if str(x).strip()]
        except Exception:
            pass
    return [p.strip().strip("\"'") for p in re.split(r"[,;\n]+", text) if p.strip()]


def normalize_token(token: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", token.lower()).strip("_")


def resolve_existing(ref: str, tools: list[ToolRow]) -> ToolRow | None:
    ref_l = ref.lower()
    for t in tools:
        if t.tool_id.lower() == ref_l or t.name.lower() == ref_l:
            return t
    # deterministic token shorthand resolver: single exact segment match in tool_id tail
    for t in tools:
        if t.tool_id.lower().endswith("/" + ref_l):
            return t
    return None


def score_candidate(token: str, tool: ToolRow) -> float:
    tok = token.lower()
    tid = tool.tool_id.lower()
    name = tool.name.lower()
    norm_tok = normalize_token(tok)

    if tok == tid or tok == name:
        return 1.0
    if tid.endswith("/" + tok) or tid.endswith("/" + norm_tok):
        return 0.98
    if norm_tok and ("/" + norm_tok) in tid:
        return 0.95

    parts = [p for p in re.split(r"[/_-]+", tok) if p]
    if not parts:
        return 0.0
    hit = sum(1 for p in parts if p in tid or p in name)
    ratio = hit / len(parts)
    # conservative: require all parts and last part alignment for high score
    if ratio == 1.0:
        last = parts[-1]
        if tid.endswith(last) or name.endswith(last):
            return 0.9
        return 0.8
    if ratio >= 0.8:
        return 0.55
    return 0.0


def choose_confident_mapping(token: str, tools: list[ToolRow]) -> tuple[ToolRow | None, list[tuple[ToolRow, float]]]:
    scored: list[tuple[ToolRow, float]] = []
    for t in tools:
        s = score_candidate(token, t)
        if s > 0:
            scored.append((t, s))
    scored.sort(key=lambda x: x[1], reverse=True)
    if not scored:
        return None, []
    best, best_score = scored[0]
    second_score = scored[1][1] if len(scored) > 1 else 0.0

    # strict confidence gate
    if best_score >= 0.95 and (best_score - second_score) >= 0.1:
        return best, scored[:10]
    if best_score >= 0.98 and second_score == 0.0:
        return best, scored[:10]
    return None, scored[:10]


def backup_db(db_path: Path) -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    backup_path = db_path.with_suffix(f".db.bak_{stamp}")
    shutil.copy2(db_path, backup_path)
    return backup_path


def main() -> int:
    args = parse_args()
    db_path = Path(args.db).resolve()
    report_path = Path(args.report_json).resolve()
    report_path.parent.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    try:
        cur = conn.cursor()
        cur.execute("SELECT id, name, filename, tools_used FROM workflows WHERE LOWER(format)='nextflow'")
        workflows = cur.fetchall()

        cur.execute("SELECT tool_id, name FROM tools")
        tools = [ToolRow(str(r["tool_id"] or ""), str(r["name"] or "")) for r in cur.fetchall() if r["tool_id"]]

        unresolved_tokens = []
        token_context = {}
        for wf in workflows:
            refs = parse_tools_used(wf["tools_used"])
            for ref in refs:
                if resolve_existing(ref, tools) is None:
                    unresolved_tokens.append(ref)
                    token_context.setdefault(ref, []).append(
                        {"workflow": wf["name"], "filename": wf["filename"]}
                    )

        unique_tokens = sorted(set(unresolved_tokens))
        mapped: dict[str, str] = {}
        ambiguous: dict[str, Any] = {}
        to_add: list[str] = []

        for tok in unique_tokens:
            best, scored = choose_confident_mapping(tok, tools)
            if best is not None:
                mapped[tok] = best.tool_id
            else:
                # add token as new tool_id unless already exists
                if resolve_existing(tok, tools) is None:
                    to_add.append(tok)
                if scored:
                    ambiguous[tok] = [{"tool_id": s[0].tool_id, "name": s[0].name, "score": s[1]} for s in scored]

        # rewrite workflows.tools_used using mapped aliases
        workflow_updates = []
        replacement_counter = Counter()
        for wf in workflows:
            old = parse_tools_used(wf["tools_used"])
            if not old:
                continue
            changed = False
            dedup = []
            seen = set()
            replacements = []
            for tok in old:
                new_tok = mapped.get(tok, tok)
                if new_tok != tok:
                    changed = True
                    replacements.append({"from": tok, "to": new_tok})
                    replacement_counter[tok] += 1
                if new_tok not in seen:
                    seen.add(new_tok)
                    dedup.append(new_tok)
            if changed:
                workflow_updates.append(
                    {
                        "id": wf["id"],
                        "workflow": wf["name"],
                        "filename": wf["filename"],
                        "old_tokens": old,
                        "new_tokens": dedup,
                        "replacements": replacements,
                    }
                )

        added_tools = []
        now = datetime.now(timezone.utc).isoformat()
        if args.apply:
            backup = backup_db(db_path)
            for wu in workflow_updates:
                cur.execute("UPDATE workflows SET tools_used = ? WHERE id = ?", (json.dumps(wu["new_tokens"]), wu["id"]))

            # add missing tool records for still-unresolved tokens
            for tok in to_add:
                token_l = tok.lower()
                cur.execute("SELECT 1 FROM tools WHERE LOWER(tool_id)=LOWER(?) LIMIT 1", (token_l,))
                if cur.fetchone():
                    continue
                norm = normalize_token(tok)
                display = tok.split("/")[-1].replace("_", " ").replace("-", " ").strip().title() or tok
                description = "Auto-added from unresolved Nextflow workflow token."
                cur.execute(
                    """
                    INSERT INTO tools (
                      tool_id, name, category, availability_status, description,
                      execution_info, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        tok,
                        display,
                        "nextflow_token",
                        "inferred_from_workflow_token",
                        description,
                        None,
                        now,
                        now,
                    ),
                )
                added_tools.append(tok)

            conn.commit()
        else:
            backup = None

        report = {
            "timestamp_utc": now,
            "db_path": str(db_path),
            "apply": args.apply,
            "unresolved_unique_tokens_before": len(unique_tokens),
            "confident_mapped_tokens": mapped,
            "ambiguous_tokens_with_candidates": ambiguous,
            "tokens_marked_for_addition": to_add,
            "workflows_updated": len(workflow_updates),
            "replacement_counts": dict(replacement_counter),
            "added_tools": added_tools if args.apply else [],
            "backup_file": str(backup) if backup else None,
            "sample_token_context": {k: token_context[k][:10] for k in list(token_context.keys())[:120]},
        }
        report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")

        print(f"db_path: {db_path}")
        print(f"mode: {'apply' if args.apply else 'dry-run'}")
        print(f"unresolved_unique_tokens_before: {len(unique_tokens)}")
        print(f"confident_mapped_token_count: {len(mapped)}")
        print(f"tokens_marked_for_addition: {len(to_add)}")
        print(f"workflows_updated: {len(workflow_updates)}")
        print(f"added_tools: {len(added_tools)}")
        if backup:
            print(f"backup_file: {backup}")
        print(f"report_json: {report_path}")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())

