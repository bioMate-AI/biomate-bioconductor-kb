"""
Phase 1 — build a canonical tool-catalog SQLite alongside the existing flat DB.

Reads (read-only): backend/database/galaxy_ai_tools.db
Writes:           sandbox/retrieval_v2/output/tool_canonical.db

Schema (all additive — production DB untouched):

  tool_suites
    suite_id        TEXT PRIMARY KEY
    display_name    TEXT
    description     TEXT
    top_category    TEXT
    edam_operation  TEXT
    wrapper_count   INTEGER
    function_count  INTEGER

  tool_functions
    suite_id        TEXT  (FK → tool_suites)
    function_id     TEXT
    display_name    TEXT
    wrapper_count   INTEGER
    PRIMARY KEY (suite_id, function_id)

  tool_wrapper_mapping
    wrapper_tool_id TEXT PRIMARY KEY  (the existing tool_id from galaxy_ai_tools.db)
    suite_id        TEXT
    function_id     TEXT
    confidence      REAL              (0..1; 1.0 = path-extracted, 0.7 = name-only)

Plus FTS5 indexes on suite display_name+description for `search_tool_suites`.

Run:
    PYTHONPATH=. python -m sandbox.retrieval_v2.scripts.build_canonical_db

Idempotent — drops and recreates the canonical DB each run.
"""
from __future__ import annotations

import re
import sqlite3
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Dict, List, Tuple

from sandbox.retrieval_v2.scripts.cluster_tools import _extract_family_and_function
from sandbox.retrieval_v2.scripts.function_dedup import _signature

SRC_DB = Path(__file__).resolve().parents[3] / "backend" / "database" / "galaxy_ai_tools.db"
OUT_DB = Path(__file__).resolve().parents[1] / "output" / "tool_canonical.db"
ALIAS_YAML = Path(__file__).resolve().parents[1] / "data" / "family_aliases.yaml"


def _load_alias_map() -> Dict[str, str]:
    """Load fragment→canonical mapping from family_aliases.yaml.

    Returns a flat dict: fragment_family_key → canonical_family_key.
    Both keys and values are lowercased for case-insensitive matching.
    """
    if not ALIAS_YAML.exists():
        return {}
    try:
        import yaml
    except ImportError:
        print("WARNING: pyyaml not installed; skipping alias map", file=sys.stderr)
        return {}
    raw = yaml.safe_load(ALIAS_YAML.read_text())
    flat: Dict[str, str] = {}
    for canonical, fragments in (raw or {}).items():
        canon_lc = canonical.lower().strip()
        for frag in (fragments or []):
            frag_lc = frag.lower().strip()
            if frag_lc and frag_lc != canon_lc:
                flat[frag_lc] = canon_lc
    return flat


def _apply_alias(family_key: str, alias_map: Dict[str, str]) -> str:
    """Resolve a family_key to its canonical form using the alias map."""
    if not alias_map:
        return family_key
    return alias_map.get(family_key.lower(), family_key)


SCHEMA = """
DROP TABLE IF EXISTS tool_suites;
DROP TABLE IF EXISTS tool_functions;
DROP TABLE IF EXISTS tool_wrapper_mapping;
DROP TABLE IF EXISTS suites_fts;

CREATE TABLE tool_suites (
    suite_id        TEXT PRIMARY KEY,
    display_name    TEXT NOT NULL,
    description     TEXT,
    top_category    TEXT,
    edam_operation  TEXT,
    wrapper_count   INTEGER NOT NULL,
    function_count  INTEGER NOT NULL
);

CREATE TABLE tool_functions (
    suite_id        TEXT NOT NULL,
    function_id     TEXT NOT NULL,
    display_name    TEXT NOT NULL,
    wrapper_count   INTEGER NOT NULL,
    PRIMARY KEY (suite_id, function_id)
);
CREATE INDEX idx_functions_suite ON tool_functions(suite_id);

CREATE TABLE tool_wrapper_mapping (
    wrapper_tool_id TEXT PRIMARY KEY,
    suite_id        TEXT NOT NULL,
    function_id     TEXT NOT NULL,
    confidence      REAL NOT NULL
);
CREATE INDEX idx_mapping_suite ON tool_wrapper_mapping(suite_id);
CREATE INDEX idx_mapping_fn    ON tool_wrapper_mapping(suite_id, function_id);

CREATE VIRTUAL TABLE suites_fts USING fts5(
    suite_id UNINDEXED, display_name, description, top_category,
    tokenize='porter unicode61'
);
"""


def _humanize_suite_name(family_key: str, member_names: List[str]) -> str:
    """Pick a human-readable display name for a suite.

    - Bioconductor: keep `Bioconductor: <pkg>` form.
    - Multi-wrapper toolkit suites (size > 5): use the family_key title-cased
      (e.g. `emboss` → `EMBOSS`, `gatk4` → `Gatk4`). Member names are
      individual functions and would mislead.
    - Small families (size ≤ 5): use the shortest member name as display, since
      for single tools the wrapper name IS the tool name (e.g. "DESeq2").
    """
    if family_key.startswith("bioconductor:"):
        pkg = family_key.split(":", 1)[1]
        return f"Bioconductor: {pkg}"

    titled = family_key.replace("_", " ").title()

    # Toolkit suite — prefer family_key over member function names.
    if len(member_names) > 5:
        # Upper-case if it's clearly an acronym pattern (length ≤ 6, single token)
        if len(family_key) <= 6 and "_" not in family_key:
            return family_key.upper()
        return titled

    # Small family — try to find a clean member name.
    candidates = []
    for n in member_names:
        if not n:
            continue
        s = re.sub(r"\bv?\d+(\.\d+)*\b", "", n).strip()
        s = re.sub(r"^Map with ", "", s, flags=re.IGNORECASE)
        s = re.sub(r"\s+", " ", s).strip()
        if s and 2 < len(s) < 40:
            candidates.append(s)
    if candidates:
        candidates.sort(key=lambda x: (len(x), x))
        return candidates[0]
    return titled


def _function_display_name(signature: str, fn_hint: str, sample_name: str) -> str:
    """Pick a display name for a function within a suite."""
    if sample_name:
        s = re.sub(r"\bv?\d+(\.\d+)*\b", "", sample_name).strip()
        s = re.sub(r"\s+", " ", s).strip()
        if 2 < len(s) < 60:
            return s
    if fn_hint:
        return fn_hint.replace("_", " ").title()
    if signature:
        return signature.replace("_", " ").title()
    return "Default"


def main() -> int:
    if not SRC_DB.exists():
        print(f"ERROR: source DB not found at {SRC_DB}", file=sys.stderr)
        return 1
    OUT_DB.parent.mkdir(parents=True, exist_ok=True)

    print(f"Reading {SRC_DB}")
    src = sqlite3.connect(f"file:{SRC_DB}?mode=ro", uri=True)
    rows = src.execute("""
        SELECT tool_id, COALESCE(name,''), COALESCE(category,''),
               COALESCE(description,''), COALESCE(edam_operations,'')
        FROM tools
    """).fetchall()
    src.close()
    print(f"  {len(rows):,} rows loaded")

    alias_map = _load_alias_map()
    if alias_map:
        print(f"  {len(alias_map):,} alias rules loaded from {ALIAS_YAML.name}")

    # ── Pass 1: classify every row into (suite, function) with confidence ──
    suite_members: Dict[str, List[Tuple[str, str, str, str, str]]] = defaultdict(list)
    # mapping rows to write later
    wrapper_rows: List[Tuple[str, str, str, float]] = []
    # per-suite function aggregation: suite_id → { fn_id → [(wrapper_id, name)] }
    fn_groups: Dict[str, Dict[str, List[Tuple[str, str]]]] = defaultdict(lambda: defaultdict(list))

    aliased_count = 0
    for tool_id, name, category, _desc, _edam in rows:
        family, fn_hint = _extract_family_and_function(tool_id, name)
        # Apply alias map BEFORE grouping. A fragment family_key gets rewritten
        # to its canonical form so all its wrappers land in the canonical suite.
        new_family = _apply_alias(family, alias_map)
        if new_family != family:
            aliased_count += 1
        family = new_family
        sig = _signature(name) or fn_hint or "default"
        fn_id = sig.replace(" ", "_")[:60] or "default"

        # confidence: 1.0 if path-extracted (toolshed/nfcore/biomate/bioconductor),
        # else 0.7 (name-derived fallback)
        path_extracted = (
            tool_id.startswith("toolshed.")
            or tool_id.startswith("nfcore/")
            or tool_id.startswith("biomate/")
            or tool_id.startswith("bioconductor/")
        )
        confidence = 1.0 if path_extracted else 0.7

        suite_members[family].append((tool_id, name, category, _desc, _edam))
        fn_groups[family][fn_id].append((tool_id, name))
        wrapper_rows.append((tool_id, family, fn_id, confidence))

    # ── Pass 2: aggregate into suites table rows ──
    suite_rows: List[Tuple[str, str, str, str, str, int, int]] = []
    function_rows: List[Tuple[str, str, str, int]] = []
    for family, members in suite_members.items():
        names = [m[1] for m in members]
        cats = Counter(m[2] for m in members if m[2])
        edam_ops = Counter()
        descs = [m[3] for m in members if m[3]]
        for m in members:
            edam = (m[4] or "").strip()
            if edam and edam != "[]":
                # Pick first EDAM op as a representative
                first = re.split(r"[,|;]", edam.strip("[] "))[0].strip().strip("'\"")
                if first:
                    edam_ops[first] += 1
        top_cat = cats.most_common(1)[0][0] if cats else ""
        top_edam = edam_ops.most_common(1)[0][0] if edam_ops else ""
        # Description: shortest non-empty member description, capped at 400 chars
        descs_sorted = sorted([d for d in descs if d], key=lambda d: (len(d), d))
        description = (descs_sorted[0][:400] if descs_sorted else "")
        n_fns = len(fn_groups[family])
        display = _humanize_suite_name(family, names)
        suite_rows.append((family, display, description, top_cat, top_edam, len(members), n_fns))

        for fn_id, fn_members in fn_groups[family].items():
            sample_name = fn_members[0][1] if fn_members else ""
            fn_display = _function_display_name(fn_id.replace("_", " "), "", sample_name)
            function_rows.append((family, fn_id, fn_display, len(fn_members)))

    # ── Write canonical DB ──
    if OUT_DB.exists():
        OUT_DB.unlink()
    dst = sqlite3.connect(OUT_DB)
    dst.executescript(SCHEMA)
    dst.executemany(
        "INSERT INTO tool_suites VALUES (?,?,?,?,?,?,?)", suite_rows
    )
    dst.executemany(
        "INSERT INTO tool_functions VALUES (?,?,?,?)", function_rows
    )
    dst.executemany(
        "INSERT INTO tool_wrapper_mapping VALUES (?,?,?,?)", wrapper_rows
    )
    # Populate FTS — enrich description with sample function names so suites
    # whose `description` is empty are still discoverable via their functions.
    fts_rows = []
    for s in suite_rows:
        suite_id, display, description, top_cat = s[0], s[1], s[2], s[3]
        # Pull up to 12 function display names for this suite (skip "Default"
        # singletons which are just the wrapper name itself).
        fn_names = [
            fn[2] for fn in function_rows
            if fn[0] == suite_id and fn[2] and fn[2].lower() != "default"
        ][:12]
        enriched_desc = description
        if fn_names:
            tail = " | ".join(fn_names)
            enriched_desc = (description + " | " + tail) if description else tail
        # Also include the suite_id as searchable text (key biological keywords
        # like 'deseq2', 'bwa' live there).
        enriched_desc = (suite_id.replace("_", " ") + " — " + enriched_desc) if enriched_desc else suite_id.replace("_", " ")
        fts_rows.append((suite_id, display, enriched_desc, top_cat))
    dst.executemany("INSERT INTO suites_fts VALUES (?,?,?,?)", fts_rows)
    dst.commit()

    # ── Integrity checks ──
    n_suites = dst.execute("SELECT COUNT(*) FROM tool_suites").fetchone()[0]
    n_functions = dst.execute("SELECT COUNT(*) FROM tool_functions").fetchone()[0]
    n_mappings = dst.execute("SELECT COUNT(*) FROM tool_wrapper_mapping").fetchone()[0]
    # Every wrapper has a valid suite/function backreference
    orphan = dst.execute("""
        SELECT COUNT(*) FROM tool_wrapper_mapping m
        WHERE NOT EXISTS (SELECT 1 FROM tool_suites s WHERE s.suite_id = m.suite_id)
    """).fetchone()[0]
    orphan_fn = dst.execute("""
        SELECT COUNT(*) FROM tool_wrapper_mapping m
        WHERE NOT EXISTS (
            SELECT 1 FROM tool_functions f
            WHERE f.suite_id = m.suite_id AND f.function_id = m.function_id
        )
    """).fetchone()[0]
    dst.close()

    print(f"\n=== Canonical DB written → {OUT_DB} ===")
    print(f"  tool_suites:           {n_suites:,}")
    print(f"  tool_functions:        {n_functions:,}")
    print(f"  tool_wrapper_mapping:  {n_mappings:,}")
    print(f"  Wrappers re-aliased:   {aliased_count:,}")
    print(f"  Orphan suite refs:     {orphan}")
    print(f"  Orphan function refs:  {orphan_fn}")
    if orphan or orphan_fn:
        print("WARNING: integrity check failed", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
