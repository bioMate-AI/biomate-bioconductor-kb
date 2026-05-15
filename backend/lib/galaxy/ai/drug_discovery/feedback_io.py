"""
JSONL plumbing for customer feedback loop (Appendix B of IND Product UI doc).

Atomic, thread-safe append to JSONL files under data/regulatory_training/.
Implements PII stripping for the free-tier shared pool (drug names, study IDs
replaced with placeholders) so that customer-edit pairs can be safely merged
into the public training corpus.

Backed by simple file locks (`fcntl.flock`) — adequate for the single-process
gunicorn deployment. If/when the backend scales horizontally, swap to Redis
or a queue.
"""
from __future__ import annotations

import fcntl
import json
import re
import time
import uuid
from pathlib import Path
from typing import Any

_REPO_ROOT = Path(__file__).resolve().parents[5]
_FEEDBACK_ROOT = _REPO_ROOT / "data" / "regulatory_training"

# Files used by each feedback type
CUSTOMER_PAIRS    = _FEEDBACK_ROOT / "dpo" / "customer_pairs.jsonl"
CHECKER_FEEDBACK  = _FEEDBACK_ROOT / "checker_feedback.jsonl"
CITATION_EXTS     = _FEEDBACK_ROOT / "citation_extensions.jsonl"
PROMPT_TUNING     = _FEEDBACK_ROOT / "prompt_tuning_signals.jsonl"


# ---------------------------------------------------------------------------
# PII stripping — for free-tier shared corpus
# ---------------------------------------------------------------------------

# Drug-name heuristic: title-case word followed by common suffixes
# (-mab, -tinib, -tide, -izumab, etc.) OR proper noun >5 chars not in stopwords.
_DRUG_SUFFIXES = (
    "mab", "tinib", "tide", "azole", "vir", "olol", "pril", "sartan",
    "statin", "cept", "stim", "kine", "ximab", "izumab", "lukast",
)
_DRUG_RE = re.compile(
    r"\b([A-Z][a-z]{2,})(" + "|".join(_DRUG_SUFFIXES) + r")\b"
)
# Study ID heuristic — e.g. RTX-101, TOX-2024-A07, STUDY-99-A
_STUDY_ID_RE = re.compile(r"\b([A-Z]{2,5}-\d{2,4}(?:-\w{1,4})?)\b")


def strip_pii(text: str) -> str:
    """
    Replace identifiable drug names and study IDs with neutral placeholders.
    Conservative — only strips strongly-shaped matches, leaves edge cases alone.
    Used for free-tier customer_pairs.jsonl entries; paid-tier preserves originals.
    """
    text = _DRUG_RE.sub(r"the investigational compound", text)
    text = _STUDY_ID_RE.sub(r"the study", text)
    return text


# ---------------------------------------------------------------------------
# Atomic JSONL append
# ---------------------------------------------------------------------------

def append_jsonl(path: Path, record: dict[str, Any]) -> str:
    """
    Atomically append one record to a JSONL file. Returns a generated row id.
    Creates parent dirs and file if missing.
    """
    path.parent.mkdir(parents=True, exist_ok=True)

    row_id = uuid.uuid4().hex
    record = dict(record)  # don't mutate caller's dict
    record.setdefault("id", row_id)
    record.setdefault("created_at", time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()))

    line = json.dumps(record, ensure_ascii=False) + "\n"

    # File-level exclusive lock — prevents interleaved partial writes across
    # gunicorn workers and async coroutines on the same host.
    with path.open("a", encoding="utf-8") as f:
        fcntl.flock(f.fileno(), fcntl.LOCK_EX)
        try:
            f.write(line)
            f.flush()
        finally:
            fcntl.flock(f.fileno(), fcntl.LOCK_UN)
    return row_id


# ---------------------------------------------------------------------------
# Public writers — one per feedback type
# ---------------------------------------------------------------------------

def record_customer_edit(
    *,
    prompt: str,
    chosen: str,
    rejected: str,
    section_type: str,
    paragraph_id: str,
    org_id: str | None = None,
) -> str:
    """Customer edited a paragraph; store as DPO pair candidate."""
    if org_id is None:
        # free-tier — PII strip before write to shared pool
        chosen = strip_pii(chosen)
        rejected = strip_pii(rejected)
        prompt = strip_pii(prompt)
    return append_jsonl(CUSTOMER_PAIRS, {
        "prompt": prompt,
        "chosen": chosen,
        "rejected": rejected,
        "meta": {
            "section_type": section_type,
            "paragraph_id": paragraph_id,
            "org_id": org_id,
            "source": "customer_edit",
        },
    })


def record_audit_dismissal(
    *,
    finding_id: str,
    rule_id: str,
    section_type: str,
    reason: str,
    free_text: str | None = None,
    document_state_hash: str | None = None,
    org_id: str | None = None,
) -> str:
    """Customer dismissed an audit finding; store as rule-refinement candidate."""
    return append_jsonl(CHECKER_FEEDBACK, {
        "finding_id": finding_id,
        "rule_id": rule_id,
        "section_type": section_type,
        "dismissed_reason": reason,
        "free_text": free_text,
        "document_state_hash": document_state_hash,
        "org_id": org_id,
    })


def record_citation_suggestion(
    *,
    guideline_id: str,
    rationale: str,
    document_only: bool = False,
    org_id: str | None = None,
) -> str:
    """Customer suggested a missing citation; store for corpus extension review."""
    return append_jsonl(CITATION_EXTS, {
        "guideline_id": guideline_id,
        "rationale": rationale,
        "document_only": document_only,
        "approved": False,
        "org_id": org_id,
    })


def record_prompt_tuning_signal(
    *,
    section_type: str,
    instruction: str,
    before: str,
    after: str,
    follow_up_edit: bool = False,
    org_id: str | None = None,
) -> str:
    """Customer used regenerate-with-instruction and was satisfied with the result."""
    return append_jsonl(PROMPT_TUNING, {
        "section_type": section_type,
        "instruction": instruction,
        "before": before,
        "after": after,
        "follow_up_edit": follow_up_edit,
        "org_id": org_id,
    })


# ---------------------------------------------------------------------------
# Review-queue reader (internal endpoint — reg science team only)
# ---------------------------------------------------------------------------

def read_feedback_queue(
    *,
    kind: str,
    limit: int = 50,
    offset: int = 0,
) -> list[dict]:
    """
    Paginated read of one feedback file. `kind` in:
      customer_pairs / checker_feedback / citation_extensions / prompt_tuning.
    """
    paths = {
        "customer_pairs":       CUSTOMER_PAIRS,
        "checker_feedback":     CHECKER_FEEDBACK,
        "citation_extensions":  CITATION_EXTS,
        "prompt_tuning":        PROMPT_TUNING,
    }
    path = paths.get(kind)
    if path is None or not path.exists():
        return []
    rows = []
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return rows[offset : offset + limit]


if __name__ == "__main__":
    # Smoke test
    rid = record_customer_edit(
        prompt="Write §2.6.6.2 repeat-dose summary for Tadalafil",
        chosen="The NOAEL of 100 mg/kg/day was established in the 13-week rat study (RTX-101).",
        rejected="The NOAEL was approximately 100 mg/kg/day in rats.",
        section_type="tox_overview",
        paragraph_id="2.6.6.2-p3",
    )
    print(f"customer_edit id={rid}")
    rows = read_feedback_queue(kind="customer_pairs", limit=3)
    print(f"latest row: {json.dumps(rows[-1], indent=2)}")
