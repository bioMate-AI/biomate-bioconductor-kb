"""Surface rich "card" metadata for ranked workflow-search results.

Reads purpose, where a workflow fits and the alternatives to consider,
input/output kinds, and compute (CPU/GPU) from the ``workflows`` catalog table
and attaches them to each ranked result as a compact ``card`` dict for the
Workflows library UI.

Design notes:
  * The ranked results come from the ``workflows`` table (``search_ranked``
    returns ``workflows.id``), so enrichment reads that same table and joins on
    ``workflows.id`` — NOT ``tools.id``, which is a different id space.
  * A name-match guard verifies the fetched row actually is the ranked result
    before attaching a card, so a future id-space change can never misattribute
    one workflow's metadata to another.
  * Stdlib only (sqlite3/json/re) — no Galaxy framework imports — so it loads and
    tests standalone.
  * Every field is optional: a workflow missing a source simply omits that key,
    so the UI hides it rather than showing a blank. Citations are not stored per
    workflow, so they are omitted here (shown only if present).
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

# galaxy_ai_tools.db lives at backend/database/; this file is at backend/lib/galaxy/ai/.
DB_PATH = Path(__file__).resolve().parent.parent.parent.parent / "database" / "galaxy_ai_tools.db"

_GPU_RE = re.compile(r"(cuda|nvidia|-gpu|_gpu|/gpu|a100|v100|h100)", re.IGNORECASE)
_HTML_RE = re.compile(r"<[a-z/!][^>]*>|base\.mako|http-equiv|&lt;|&gt;", re.IGNORECASE)
# annotation_v2 is "- key: value ;; value\n- key2: value ..." — split on the "- key:" heads.
_SECTION_RE = re.compile(r"(?m)^\s*-\s+([a-z_]+)\s*:\s*")


def _loads(raw: Any) -> Any:
    if not raw:
        return None
    try:
        return json.loads(raw)
    except Exception:
        return None


def _norm(name: Any) -> str:
    return re.sub(r"[^a-z0-9]+", "", str(name or "").lower())


def _clean_text(raw: Any) -> Optional[str]:
    if not raw:
        return None
    s = str(raw).strip()
    if not s or _HTML_RE.search(s) or s.startswith("{") or s.startswith("["):
        return None
    # Strip light markdown emphasis so '**name** is a pipeline…' reads cleanly.
    s = s.replace("**", "").replace("`", "").strip()
    return s or None


def _kinds(value: Any, limit: int) -> List[str]:
    """Coerce an input_types/output_types JSON list to readable tokens."""
    out: List[str] = []
    data = _loads(value)
    if isinstance(data, list):
        for item in data:
            if isinstance(item, str):
                tok = item.strip().replace("_", " ")
                if tok and tok not in out:
                    out.append(tok)
            if len(out) >= limit:
                break
    return out


def _parse_annotation_v2(av2: Any) -> Dict[str, str]:
    """Return {section_key: raw_value} from the '- key: value' annotation format."""
    sections: Dict[str, str] = {}
    if not av2:
        return sections
    text = str(av2)
    parts = _SECTION_RE.split(text)
    # parts = [preamble, key1, val1, key2, val2, ...]
    i = 1
    while i + 1 <= len(parts) - 1:
        key = parts[i].strip()
        val = parts[i + 1].strip()
        if key:
            sections[key] = val
        i += 2
    return sections


def _split_items(raw: str, limit: int) -> List[str]:
    out: List[str] = []
    for chunk in str(raw).split(";;"):
        t = chunk.strip().strip(".").strip()
        if t and not _HTML_RE.search(t) and t not in out:
            out.append(t)
        if len(out) >= limit:
            break
    return out


def _alternatives(raw: str, limit: int) -> List[str]:
    """Format 'name=reason ;; name=reason' alternatives into 'name — reason'."""
    out: List[str] = []
    for chunk in str(raw).split(";;"):
        c = chunk.strip()
        if not c:
            continue
        if "=" in c:
            name, _, reason = c.partition("=")
            name = name.strip()
            reason = reason.strip().rstrip(".")
            # Trim a leading "Use " so it reads "name — for raw FASTQ ...".
            reason = re.sub(r"^use\s+", "", reason, flags=re.IGNORECASE)
            item = "%s — %s" % (name, reason) if reason else name
        else:
            item = c
        if item and not _HTML_RE.search(item) and item not in out:
            out.append(item[:120])
        if len(out) >= limit:
            break
    return out


def _build_card(row: sqlite3.Row) -> Optional[Dict[str, Any]]:
    card: Dict[str, Any] = {}

    sections = _parse_annotation_v2(row["annotation_v2"])

    # Purpose: prefer the clean description; fall back to when_to_use prose.
    purpose = _clean_text(row["description"])
    if not purpose:
        purpose = _clean_text(sections.get("when_to_use"))
    if purpose:
        card["purpose"] = purpose[:260]

    # Input -> output kinds.
    inputs = _kinds(row["input_types"], 4) or _kinds(row["input_kinds"], 4)
    outputs = _kinds(row["output_types"], 4)
    if inputs:
        card["inputs"] = inputs
    if outputs:
        card["outputs"] = outputs

    # Fits: when_to_use scenarios. Not/alternatives: the alternatives section.
    when = sections.get("when_to_use")
    if when:
        fits = _split_items(when, 3)
        if fits:
            card["fits"] = [f[:160] for f in fits]
    alts = sections.get("alternatives") or sections.get("not_for") or sections.get("limitations")
    if alts:
        not_fits = _alternatives(alts, 3) if "=" in str(alts) else _split_items(alts, 3)
        if not_fits:
            card["notFits"] = not_fits

    # Compute: GPU if the pinned container is a CUDA/GPU image, else CPU.
    img = str(row["docker_image"] or "")
    card["hardware"] = {"kind": "GPU" if _GPU_RE.search(img) else "CPU", "memory": None}

    # A card carrying only the (always-present) CPU/GPU kind adds little; still
    # show it when we have at least I/O or a purpose.
    if len(card) == 1:
        return None
    return card


_SELECT = """
    SELECT id, name, filename, description, annotation_v2,
           input_types, output_types, input_kinds, docker_image
    FROM workflows
    WHERE id IN (%s)
"""


def enrich_ranked_cards(ranked: List[Dict[str, Any]], db_path: Optional[str] = None) -> List[Dict[str, Any]]:
    """Attach a ``card`` dict to each catalog (``type == 'workflow'``) result in place.

    Joins on workflows.id and verifies the row's name/filename matches the ranked
    result before attaching, so a card is never misattributed. Never raises.
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

        by_id = {str(row["id"]): row for row in rows}

        for it in ranked:
            if it.get("type") != "workflow" or it.get("id") is None:
                continue
            row = by_id.get(str(it.get("id")))
            if row is None:
                continue
            # Name-match guard: never attach a row whose identity differs from the
            # ranked result (protects against any id-space drift).
            rn, inm = _norm(row["name"]), _norm(it.get("name"))
            rf, inf = _norm(row["filename"]), _norm(it.get("nextflow_path"))
            if rn and inm and rn != inm and not (rf and inf and rf == inf):
                continue
            card = _build_card(row)
            if card:
                it["card"] = card
    except Exception as exc:  # never break the search path
        log.warning("[workflow_card_enrich] skipped: %s", exc)
    return ranked
