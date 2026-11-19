"""Surface rich "card" metadata for ranked workflow-search results.

Reads purpose, where a workflow fits and does not fit, input/output file kinds,
compute (CPU/GPU + memory) and a citation from the ``tools`` and
``tool_knowledge`` catalog tables and attaches them to each ranked result as a
compact ``card`` dict for the Workflows library UI.

Design notes:
  * Stdlib only (sqlite3/json/re) — no Galaxy framework imports — so it loads and
    tests standalone.
  * Prefers the clean structured sources (``structured_citations``,
    ``tool_knowledge.use_cases``/``limitations``, ``scientific_context_v2``) and
    drops HTML-contaminated fields, which some ``tools.citations`` rows contain.
  * Every field is optional: a workflow missing a source simply omits that key,
    so the UI hides it rather than showing a blank.
  * The public entry point swallows its own errors; the caller additionally
    guards the import, so enrichment can never break the search path.
"""
from __future__ import annotations

import json
import logging
import re
import sqlite3
from pathlib import Path
from typing import Any, Dict, List, Optional

log = logging.getLogger(__name__)

# tools.db lives at backend/database/; this file is at backend/lib/galaxy/ai/.
DB_PATH = Path(__file__).resolve().parent.parent.parent.parent / "database" / "galaxy_ai_tools.db"

_GPU_RE = re.compile(r"\b(gpu|cuda|nvidia|a100|v100|h100|t4|tesla|cupy)\b", re.IGNORECASE)
# Marks a value as HTML/markup junk (seen in some raw citation rows) — never show it.
_HTML_RE = re.compile(r"<[a-z/!][^>]*>|base\.mako|http-equiv|&lt;|&gt;", re.IGNORECASE)
_MEM_RE = re.compile(r"\s*([\d.]+)\s*([A-Za-z]+)?")


def _loads(raw: Any) -> Any:
    if not raw:
        return None
    try:
        return json.loads(raw)
    except Exception:
        return None


def _clean_text(raw: Any) -> Optional[str]:
    if not raw:
        return None
    s = str(raw).strip()
    if not s or _HTML_RE.search(s):
        return None
    return s


def _clean_list(value: Any, limit: int) -> List[str]:
    out: List[str] = []
    if isinstance(value, list):
        for item in value:
            if not isinstance(item, str):
                continue
            t = item.strip()
            if t and not _HTML_RE.search(t) and t not in out:
                out.append(t)
            if len(out) >= limit:
                break
    return out


def _file_kinds(value: Any, limit: int) -> List[str]:
    """Coerce an inputs/outputs JSON value to short file-kind tokens (``fasta``)."""
    out: List[str] = []
    if isinstance(value, list):
        for item in value:
            tok = None
            if isinstance(item, str):
                tok = item
            elif isinstance(item, dict):
                tok = item.get("ext") or item.get("format") or item.get("type") or item.get("name")
            if tok:
                tok = str(tok).strip().lstrip(".").lower()
                if tok and tok not in out:
                    out.append(tok)
            if len(out) >= limit:
                break
    return out


def _memory(execution_info: Any) -> Optional[str]:
    ei = _loads(execution_info)
    if not isinstance(ei, dict):
        return None
    mem = ei.get("memory")
    if not mem:
        return None
    m = _MEM_RE.match(str(mem))
    if not m:
        return None
    num = m.group(1)
    if "." in num:
        num = num.rstrip("0").rstrip(".")
    unit = (m.group(2) or "GB").upper()
    if unit in ("G", "GB"):
        unit = "GB"
    elif unit in ("M", "MB"):
        unit = "MB"
    return "%s %s" % (num, unit)


def _hardware(execution_info: Any, requirements: Any, container_info: Any = None) -> Dict[str, Any]:
    # Detect GPU from the tool's OWN signals only. execution_info carries a nested
    # ``evidence_source.samples`` blob naming OTHER workflows, so scanning the whole
    # string gives false positives — read just the tool-specific keys.
    signals: List[str] = [str(requirements or ""), str(container_info or "")]
    ei = _loads(execution_info)
    if isinstance(ei, dict):
        if ei.get("gpu") in (True, 1, "1"):
            signals.append("gpu")
        for key in ("type", "queue", "accelerator", "compute", "platform", "container", "image", "gpu"):
            val = ei.get(key)
            if val and not isinstance(val, (dict, list)):
                signals.append(str(val))
    return {
        "kind": "GPU" if _GPU_RE.search(" ".join(signals)) else "CPU",
        "memory": _memory(execution_info),
    }


def _citation(structured_citations: Any, primary_citation: Any) -> Optional[Dict[str, Any]]:
    """Return a compact citation from the structured sources only (never raw HTML)."""
    for src in (primary_citation, structured_citations):
        obj = _loads(src)
        cit = None
        if isinstance(obj, list):
            cit = next(
                (c for c in obj if isinstance(c, dict) and (c.get("title") or c.get("doi"))),
                None,
            )
        elif isinstance(obj, dict):
            cit = obj
        if not cit or not (cit.get("title") or cit.get("doi")):
            continue
        authors = cit.get("authors") or []
        lead = None
        if isinstance(authors, list) and authors:
            last = str(authors[0]).split()[-1]
            lead = ("%s et al." % last) if len(authors) > 1 else last
        title = _clean_text(cit.get("title"))
        return {
            "title": title,
            "lead": lead,
            "journal": cit.get("journal") or None,
            "year": cit.get("year") or None,
            "doi": cit.get("doi") or None,
        }
    return None


def _build_card(row: sqlite3.Row) -> Optional[Dict[str, Any]]:
    card: Dict[str, Any] = {"hardware": _hardware(row["execution_info"], row["requirements"], row["container_info"])}

    purpose = _clean_text(row["scientific_context_v2"])
    if purpose:
        card["purpose"] = purpose[:260]

    inputs = _file_kinds(_loads(row["inputs"]), 4)
    outputs = _file_kinds(_loads(row["outputs"]), 4)
    if inputs:
        card["inputs"] = inputs
    if outputs:
        card["outputs"] = outputs

    fits = _clean_list(_loads(row["use_cases"]), 3)
    not_fits = _clean_list(_loads(row["limitations"]), 3)
    if fits:
        card["fits"] = fits
    if not_fits:
        card["notFits"] = not_fits

    citation = _citation(row["structured_citations"], row["primary_citation"])
    if citation:
        card["citation"] = citation

    # A card with nothing beyond the (always-present) hardware kind adds no value.
    if len(card) == 1 and not card["hardware"].get("memory"):
        return None
    return card


_SELECT = """
    SELECT t.id AS id, t.inputs, t.outputs, t.requirements, t.execution_info,
           t.container_info, t.structured_citations, t.scientific_context_v2,
           k.use_cases, k.limitations, k.primary_citation
    FROM tools t
    LEFT JOIN tool_knowledge k ON k.tool_id = t.tool_id OR k.tool_name = t.name
    WHERE t.id IN (%s)
"""


def enrich_ranked_cards(ranked: List[Dict[str, Any]], db_path: Optional[str] = None) -> List[Dict[str, Any]]:
    """Attach a ``card`` dict to each catalog (``type == 'workflow'``) result in place.

    Chains carry no catalog id and are skipped. Never raises.
    """
    try:
        if not ranked:
            return ranked
        ids = [
            it.get("id")
            for it in ranked
            if it.get("type") == "workflow" and it.get("id") is not None
        ]
        ids = [int(x) for x in ids if str(x).isdigit()]
        if not ids:
            return ranked

        conn = sqlite3.connect(str(db_path or DB_PATH))
        try:
            conn.row_factory = sqlite3.Row
            placeholders = ",".join("?" for _ in ids)
            rows = conn.execute(_SELECT % placeholders, ids).fetchall()
        finally:
            conn.close()

        # One tool may match several tool_knowledge rows via the OR join; keep the
        # row that actually carries use_cases.
        by_id: Dict[str, sqlite3.Row] = {}
        for row in rows:
            key = str(row["id"])
            if key not in by_id or (not by_id[key]["use_cases"] and row["use_cases"]):
                by_id[key] = row

        for it in ranked:
            if it.get("type") != "workflow" or it.get("id") is None:
                continue
            row = by_id.get(str(it.get("id")))
            if row is None:
                continue
            card = _build_card(row)
            if card:
                it["card"] = card
    except Exception as exc:  # never break the search path
        log.warning("[workflow_card_enrich] skipped: %s", exc)
    return ranked
