#!/usr/bin/env python3
"""
enrich_tools_scientific_context.py

Batch-enriches tools missing scientific_context_v2 using an LLM.
Processes tools in priority order: tools with longer descriptions first
(they have more signal for good enrichment).

Writes scientific_context_v2 as JSON:
  {
    "package": "<name>",
    "when_to_use": ["<use case 1>", "..."],
    "primary_inputs": ["<input type>", "..."],
    "primary_outputs": ["<output type>", "..."],
    "scientific_domain": "<domain>",
    "keywords": ["<keyword>", "..."]
  }

Usage:
    # Enrich 100 tools (safe starting batch):
    python3 scripts/enrich_tools_scientific_context.py --limit 100

    # Enrich drug-discovery tools only:
    python3 scripts/enrich_tools_scientific_context.py --domain drug --limit 200

    # Dry run (print what would be enriched):
    python3 scripts/enrich_tools_scientific_context.py --dry-run --limit 20

    # Use specific model (default: claude-haiku-4-5-20251001):
    python3 scripts/enrich_tools_scientific_context.py --model claude-haiku-4-5-20251001 --limit 500

Requires ANTHROPIC_API_KEY in environment.
"""
import argparse
import json
import os
import re
import sqlite3
import sys
import time
from pathlib import Path

DB_DEFAULT = Path(__file__).parent.parent / "database" / "galaxy_ai_tools.db"


def _rebuild_tools_fts(conn: sqlite3.Connection) -> None:
    """Rebuild tools_fts covering all tools and merging scientific_context_v2 keywords into tags."""
    import json as _json

    def _v2_text(raw: str | None) -> str:
        if not raw:
            return ""
        try:
            ctx = _json.loads(raw)
        except Exception:
            return ""
        parts = []
        domain = ctx.get("scientific_domain") or ctx.get("domain")
        if isinstance(domain, str) and domain:
            parts.append(domain.replace("_", " "))
        for kw in (ctx.get("keywords") or [])[:10]:
            if isinstance(kw, str) and kw.strip():
                parts.append(kw.strip())
        wtu = ctx.get("when_to_use", "")
        if isinstance(wtu, list):
            parts.extend(str(w)[:80] for w in wtu[:2])
        return " ".join(parts)

    def _tags(raw: str | None, extra: str) -> str:
        parts = []
        if raw:
            r = raw.strip()
            if r.startswith("["):
                try:
                    parts.extend(str(i) for i in _json.loads(r) if i)
                except Exception:
                    parts.append(r)
            else:
                parts.append(r)
        if extra:
            parts.append(extra)
        return " ".join(parts)[:600]

    tools = conn.execute("""
        SELECT tool_id, name, description, category, parameters, help_text,
               availability_status, tags, edam_operations, edam_topics, scientific_context_v2
        FROM tools
    """).fetchall()
    conn.execute("DELETE FROM tools_fts")
    conn.executemany("""
        INSERT INTO tools_fts(
            tool_id, name, description, category, parameters, help_text,
            availability_status, tags, edam_operations, edam_topics
        ) VALUES (?,?,?,?,?,?,?,?,?,?)
    """, [
        (
            r[0], r[1] or "", (r[2] or "")[:800], r[3] or "",
            (r[4] or "")[:400], (r[5] or "")[:400], r[6] or "",
            _tags(r[7], _v2_text(r[10])),
            r[8] or "", r[9] or "",
        )
        for r in tools
    ])
    conn.commit()


SYSTEM_PROMPT = """You are a bioinformatics expert. Given a tool's name and description,
generate a concise scientific context JSON object. Be specific and accurate.
Return ONLY valid JSON — no markdown fences, no explanation."""

USER_TEMPLATE = """Tool name: {name}
Description: {description}

Return a JSON object with these exact fields:
- "package": the canonical package/tool name (string)
- "when_to_use": list of 3-5 specific scientific use cases (array of strings)
- "primary_inputs": list of input file types or data types (array of strings)
- "primary_outputs": list of output types produced (array of strings)
- "scientific_domain": one of: genomics, transcriptomics, proteomics, metabolomics, structural_biology, drug_discovery, immunology, epigenomics, metagenomics, single_cell, spatial_transcriptomics, population_genetics, clinical_genomics, biophysics, cell_biology, neuroscience, other
- "keywords": 5-10 specific scientific keywords for search (array of strings)"""

DOMAIN_KEYWORDS = {
    "drug": ["drug", "pharma", "compound", "ligand", "docking", "admet", "toxic", "ic50", "pk", "pkpd", "antibod", "bispecific", "car-t", "adc", "protac", "smiles", "molecular"],
    "genomics": ["variant", "snp", "gwas", "vcf", "genome", "exome", "wgs", "cnv", "sv", "annotation"],
    "rna": ["rna", "mrna", "scrna", "rnaseq", "expression", "transcript", "deseq", "edger", "salmon", "kallisto"],
    "protein": ["protein", "structure", "fold", "alphafold", "pdb", "alphafold", "docking", "binding"],
}


def build_domain_filter(domain: str) -> str:
    """Build SQL LIKE filter for domain keyword search."""
    if not domain or domain not in DOMAIN_KEYWORDS:
        return ""
    terms = DOMAIN_KEYWORDS[domain]
    conditions = " OR ".join(
        f"lower(name) LIKE '%{t}%' OR lower(description) LIKE '%{t}%'"
        for t in terms
    )
    return f"AND ({conditions})"


def fetch_unenriched(conn: sqlite3.Connection, limit: int, domain: str) -> list:
    domain_filter = build_domain_filter(domain)
    rows = conn.execute(f"""
        SELECT tool_id, name, description
        FROM tools
        WHERE (scientific_context_v2 IS NULL OR scientific_context_v2 = '')
          AND description IS NOT NULL AND LENGTH(description) > 50
          {domain_filter}
        ORDER BY LENGTH(description) DESC
        LIMIT ?
    """, (limit,)).fetchall()
    return rows


def call_llm(client, model: str, name: str, description: str) -> dict | None:
    """Call the LLM and return parsed JSON, or None on failure."""
    user_msg = USER_TEMPLATE.format(name=name, description=description[:900])
    for attempt in range(2):
        try:
            resp = client.messages.create(
                model=model,
                max_tokens=600,
                system=SYSTEM_PROMPT,
                messages=[{"role": "user", "content": user_msg}],
            )
            text = resp.content[0].text.strip()
            # Strip markdown fences if present
            text = re.sub(r"^```(?:json)?\s*", "", text)
            text = re.sub(r"\s*```$", "", text)
            # Truncate to last closing brace in case of runaway output
            last_brace = text.rfind("}")
            if last_brace != -1:
                text = text[: last_brace + 1]
            return json.loads(text)
        except json.JSONDecodeError:
            if attempt == 0:
                # Retry with a shorter description
                user_msg = USER_TEMPLATE.format(name=name, description=description[:400])
            else:
                print(f"    JSON parse failed for {name}", file=sys.stderr)
                return None
        except Exception as e:
            print(f"    LLM error for {name}: {e}", file=sys.stderr)
            return None
    return None


def enrich(db_path: Path, limit: int, domain: str, model: str, dry_run: bool) -> None:
    try:
        import anthropic
    except ImportError:
        print("ERROR: anthropic package not installed. Run: pip install anthropic")
        raise SystemExit(1)

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("ERROR: ANTHROPIC_API_KEY not set.")
        raise SystemExit(1)

    client = anthropic.Anthropic(api_key=api_key)
    conn = sqlite3.connect(db_path)
    tools = fetch_unenriched(conn, limit, domain)
    print(f"Enriching {len(tools)} tools (model={model}, dry_run={dry_run})")

    updated = 0
    failed = 0
    for i, (tool_id, name, description) in enumerate(tools):
        prefix = f"[{i+1}/{len(tools)}] {name}"
        if dry_run:
            print(f"  DRY  {prefix} — {description[:80]}…")
            continue

        ctx = call_llm(client, model, name, description)
        if ctx is None:
            print(f"  FAIL {prefix}")
            failed += 1
            time.sleep(0.5)
            continue

        conn.execute(
            "UPDATE tools SET scientific_context_v2 = ? WHERE tool_id = ?",
            (json.dumps(ctx), tool_id),
        )
        conn.commit()
        print(f"  OK   {prefix}")
        updated += 1
        time.sleep(0.05)  # gentle rate limit

    # Rebuild FTS after enrichment (delegate to rebuild_tools_fts.py logic)
    if not dry_run and updated > 0:
        print(f"\nRebuilding tools_fts (incorporating {updated} newly enriched tools)…")
        _rebuild_tools_fts(conn)
        print("FTS rebuilt.")

    conn.close()
    print(f"\nDone: {updated} enriched, {failed} failed.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Enrich tool scientific_context_v2 via LLM")
    parser.add_argument("--db", default=str(DB_DEFAULT), help="Path to galaxy_ai_tools.db")
    parser.add_argument("--limit", type=int, default=100, help="Max tools to process")
    parser.add_argument("--domain", default="", choices=["", "drug", "genomics", "rna", "protein"], help="Filter by domain")
    parser.add_argument("--model", default="claude-haiku-4-5-20251001", help="Anthropic model ID")
    parser.add_argument("--dry-run", action="store_true", help="Print tools that would be enriched without calling LLM")
    args = parser.parse_args()

    db_path = Path(args.db)
    if not db_path.exists():
        print(f"ERROR: DB not found at {db_path}")
        raise SystemExit(1)

    enrich(db_path, args.limit, args.domain, args.model, args.dry_run)
