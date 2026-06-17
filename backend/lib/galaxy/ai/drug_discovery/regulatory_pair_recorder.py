"""
Lane B3 upstream — customer feedback → DPO pair recorder.

Single owner of the on-disk path + JSONL format that
regulatory_training_worker reads from. Provides:

  record_pair(user_id, org_id, chosen, rejected, section_type, ...)
    Validates, sanitises, appends one DPO row to
    data/regulatory_training/dpo/customer_pairs.jsonl

  count_for_org(org_id) → int
    Forwarding helper that wraps regulatory_training_jobs.count_edit_pairs
    so the recorder API can return a fresh count to the UI without the
    UI having to call a second endpoint.

Format matches the shape the existing worker + compiler already expect:

  {
    "prompt":   "...",          # optional source prompt
    "chosen":   "<text>",       # what the customer kept / edited to
    "rejected": "<text>",       # what the model originally produced
    "meta": {
      "org_id":       "<sanitised>",
      "user_id":      "<actor>",
      "section_type": "pbpk" | "tox_genotox" | "admet" | ...,
      "task":         "pbpk" | "tox_genotox" | ...,
      "row_id":       "<uuid>",
      "recorded_at":  <unix>
    }
  }

Append-only JSONL; never overwrites existing rows. Idempotency is
caller-mediated (the UI doesn't dedupe accidental double-posts —
that's intentional, those are real signal too if the customer reviewed
twice).
"""
from __future__ import annotations
import json, os, re, threading, time, uuid
from pathlib import Path
from typing import Any, Optional

REPO_ROOT = Path(__file__).resolve().parents[5]
DPO_DIR = REPO_ROOT / "data" / "regulatory_training" / "dpo"
PAIRS_PATH = DPO_DIR / "customer_pairs.jsonl"

_lock = threading.Lock()

# Match the worker's _safe_org so writes land where the worker reads.
_ORG_SANITISE_RE = re.compile(r"[^A-Za-z0-9_\-]")


def _safe_org(org_id: str) -> str:
    if not org_id:
        return ""
    return _ORG_SANITISE_RE.sub("", str(org_id))[:32]


def record_pair(
    user_id: str,
    org_id: str,
    chosen: str,
    rejected: str,
    section_type: str = "",
    task: str = "",
    prompt: str = "",
    meta_extra: Optional[dict[str, Any]] = None,
    pairs_path: Optional[Path] = None,
) -> dict[str, Any]:
    # Resolve PAIRS_PATH at call-time so tests / hot-reload paths reach a
    # monkeypatched module-level value instead of the value frozen at
    # function definition.
    if pairs_path is None:
        pairs_path = PAIRS_PATH
    """Append one row. Returns the persisted row (with assigned row_id +
    recorded_at). Raises ValueError on invalid inputs."""
    if not user_id:
        raise ValueError("user_id required")
    safe_org = _safe_org(org_id)
    if not safe_org:
        raise ValueError("invalid org_id (alphanumeric + _- only, max 32 chars)")
    chosen = (chosen or "").strip()
    rejected = (rejected or "").strip()
    if not chosen and not rejected:
        raise ValueError("at least one of chosen / rejected must be non-empty")
    # Cap each side at 8K chars so a runaway client can't bloat the JSONL
    if len(chosen) > 8000:   chosen = chosen[:8000]
    if len(rejected) > 8000: rejected = rejected[:8000]

    row = {
        "prompt":   str(prompt or "")[:2000],
        "chosen":   chosen,
        "rejected": rejected,
        "meta": {
            "org_id":       safe_org,
            "user_id":      str(user_id),
            "section_type": str(section_type or "").strip(),
            "task":         str(task or "").strip(),
            "row_id":       uuid.uuid4().hex,
            "recorded_at":  time.time(),
            **((meta_extra or {}) if isinstance(meta_extra, dict) else {}),
        },
    }
    with _lock:
        pairs_path.parent.mkdir(parents=True, exist_ok=True)
        with pairs_path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
            f.flush()
            try:
                os.fsync(f.fileno())
            except OSError:
                pass
    return row


def count_for_org(org_id: str, pairs_path: Optional[Path] = None) -> int:
    """Return how many pairs are now available for this org (matches the
    worker's count_edit_pairs semantics: row's meta.org_id matches OR
    row has no org_id, treated as a global/seed pair)."""
    if pairs_path is None:
        pairs_path = PAIRS_PATH
    if not pairs_path.exists():
        return 0
    safe = _safe_org(org_id)
    if not safe:
        return 0
    n = 0
    for line in pairs_path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except Exception:
            continue
        row_org = (row.get("meta") or {}).get("org_id") or row.get("org_id")
        if not row_org or _safe_org(str(row_org)) == safe:
            n += 1
    return n
