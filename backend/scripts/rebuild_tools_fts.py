#!/usr/bin/env python3
"""
rebuild_tools_fts.py

Rebuilds the tools_fts full-text search index to:
  1. Cover ALL tools (FTS was at 8,356 / 12,284 — missing 3,928)
  2. Incorporate scientific_context_v2 keywords and scientific_domain
     into the searchable text so LLM-enriched tools are findable by FTS

The FTS schema stays unchanged (no migration needed):
  tool_id, name, description, category, parameters, help_text,
  availability_status, tags, edam_operations, edam_topics

scientific_context_v2 data is merged into the `tags` slot as
space-separated keywords alongside the original tags content.

Usage:
    python3 scripts/rebuild_tools_fts.py [--db /path/to/db] [--dry-run]
"""
import argparse
import json
import sqlite3
from pathlib import Path

DB_DEFAULT = Path(__file__).parent.parent / "database" / "galaxy_ai_tools.db"


def extract_v2_text(ctx_json: str | None) -> str:
    """Pull searchable text from scientific_context_v2 JSON."""
    if not ctx_json:
        return ""
    try:
        ctx = json.loads(ctx_json)
    except (json.JSONDecodeError, TypeError):
        return ""
    parts = []
    domain = ctx.get("scientific_domain") or ctx.get("domain")
    if domain and isinstance(domain, str):
        parts.append(domain.replace("_", " "))
    for kw in (ctx.get("keywords") or [])[:10]:
        if isinstance(kw, str) and kw.strip():
            parts.append(kw.strip())
    # For legacy schema: extract from when_to_use
    wtu = ctx.get("when_to_use", "")
    if isinstance(wtu, list):
        parts.extend(str(w)[:80] for w in wtu[:2])
    return " ".join(parts)


def coalesce_tags(raw_tags: str | None, v2_text: str) -> str:
    """Merge raw tags (plain text or JSON array) with v2 keywords."""
    parts = []
    if raw_tags:
        raw = raw_tags.strip()
        if raw.startswith("["):
            try:
                items = json.loads(raw)
                parts.extend(str(i) for i in items if i)
            except json.JSONDecodeError:
                parts.append(raw)
        else:
            parts.append(raw)
    if v2_text:
        parts.append(v2_text)
    return " ".join(parts)


def rebuild(db_path: Path, dry_run: bool) -> None:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row

    # Verify FTS schema
    fts_sql = conn.execute(
        "SELECT sql FROM sqlite_master WHERE name='tools_fts'"
    ).fetchone()
    if not fts_sql:
        raise SystemExit("tools_fts table not found — run migrate_tool_search.py first")
    print(f"FTS schema: {fts_sql[0][:120]}…")

    tools = conn.execute("""
        SELECT tool_id, name, description, category, parameters, help_text,
               availability_status, tags, edam_operations, edam_topics,
               scientific_context_v2
        FROM tools
    """).fetchall()
    print(f"Tools in table: {len(tools)}")

    before = conn.execute("SELECT COUNT(*) FROM tools_fts").fetchone()[0]
    print(f"FTS rows before: {before}")

    if dry_run:
        # Sample 10 rows to show what would be indexed
        for row in tools[:10]:
            v2 = extract_v2_text(row["scientific_context_v2"])
            merged_tags = coalesce_tags(row["tags"], v2)
            print(f"  {row['name'][:30]} → tags: {merged_tags[:80]}")
        print(f"\n[dry-run] Would index {len(tools)} tools (currently {before})")
        conn.close()
        return

    print("Rebuilding FTS…")
    conn.execute("DELETE FROM tools_fts")

    batch = []
    for row in tools:
        v2_text = extract_v2_text(row["scientific_context_v2"])
        merged_tags = coalesce_tags(row["tags"], v2_text)
        batch.append((
            row["tool_id"],
            row["name"] or "",
            (row["description"] or "")[:800],
            row["category"] or "",
            (row["parameters"] or "")[:400],
            (row["help_text"] or "")[:400],
            row["availability_status"] or "",
            merged_tags[:600],
            row["edam_operations"] or "",
            row["edam_topics"] or "",
        ))

    conn.executemany("""
        INSERT INTO tools_fts(
            tool_id, name, description, category, parameters, help_text,
            availability_status, tags, edam_operations, edam_topics
        ) VALUES (?,?,?,?,?,?,?,?,?,?)
    """, batch)
    conn.commit()

    after = conn.execute("SELECT COUNT(*) FROM tools_fts").fetchone()[0]
    conn.close()
    print(f"FTS rows after: {after} (added {after - before})")
    print("Done.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default=str(DB_DEFAULT))
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    db_path = Path(args.db)
    if not db_path.exists():
        raise SystemExit(f"DB not found: {db_path}")
    rebuild(db_path, args.dry_run)
