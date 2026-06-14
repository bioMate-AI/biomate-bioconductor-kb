"""Lane B3 — per-org adapter retrain queue.

In-memory + JSONL persistence so jobs survive a process restart without a
DB migration. Naming aligns with ind_assembly._resolve_adapter_path()'s
org_id sanitisation so retrained adapters land where the resolver finds
them on the next inference call.
"""
from __future__ import annotations
import json, re, threading, time, uuid
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any, Optional

REPO = Path(__file__).resolve().parents[5]
DATA_DIR = REPO / "data" / "regulatory_training"
JOBS_PATH = DATA_DIR / "training_jobs.jsonl"
DPO_PAIRS_PATH = DATA_DIR / "dpo" / "customer_pairs.jsonl"

VALID_STATUS = ("queued", "running", "succeeded", "failed", "cancelled")

# Per-org "adaptation" — covers everything from cheap prompt-rule compilation
# (works against the frontier API path today) up to GPU post-training (gated
# on the cross-judge+reference harness showing local > frontier).
#
#   prompt_rules:     compile customer edit-pair patterns into a per-org rule
#                     YAML loaded by _build_rag_context. Zero spend, runs in
#                     seconds. Default mode — serves the frontier-API
#                     production path today.
#   few_shot_index:   build a per-org retrieval index over the edit pairs;
#                     few-shot exemplars injected at prompt time. Cheap.
#   post_train_lora:  full SFT/DPO LoRA on the open base. ONLY allowed when
#                     the harness has shown a non-overlap-CI win for local
#                     over the frontier default on the org's task mix. Stub
#                     until that signal exists. See CLAUDE.md "Model-flip
#                     discipline" + "Review Code Before Testing".
VALID_ADAPTATION_MODE = ("prompt_rules", "few_shot_index", "post_train_lora")
DEFAULT_ADAPTATION_MODE = "prompt_rules"

_lock = threading.Lock()


@dataclass
class TrainingJob:
    job_id: str
    user_id: str
    org_id: str
    status: str
    submitted_at: float
    updated_at: float
    edit_pair_count: int
    message: str = ""
    adapter_path: str = ""
    # The kind of adaptation this job performs. Older job rows on disk
    # predate this field and default to prompt_rules when missing.
    adaptation_mode: str = DEFAULT_ADAPTATION_MODE

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def _safe_org(org_id: str) -> str:
    if not org_id:
        return ""
    return re.sub(r"[^A-Za-z0-9_\-]", "", org_id)[:32]


def count_edit_pairs(org_id: str) -> int:
    if not DPO_PAIRS_PATH.exists():
        return 0
    safe = _safe_org(org_id)
    if not safe:
        return 0
    n = 0
    for line in DPO_PAIRS_PATH.read_text(encoding="utf-8").splitlines():
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


def _append_jsonl(job: TrainingJob) -> None:
    JOBS_PATH.parent.mkdir(parents=True, exist_ok=True)
    with JOBS_PATH.open("a", encoding="utf-8") as f:
        f.write(json.dumps(job.to_dict()) + "\n")


def _read_jobs() -> list[TrainingJob]:
    if not JOBS_PATH.exists():
        return []
    out: list[TrainingJob] = []
    for line in JOBS_PATH.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        try:
            row = json.loads(line)
            # Back-fill the adaptation_mode default for rows that predate
            # the field (the queue is on-disk append-only JSONL).
            row.setdefault("adaptation_mode", DEFAULT_ADAPTATION_MODE)
            out.append(TrainingJob(**row))
        except Exception:
            continue
    return out


def _coalesce_status(jobs: list[TrainingJob]) -> dict[str, TrainingJob]:
    by_id: dict[str, TrainingJob] = {}
    for j in jobs:
        ex = by_id.get(j.job_id)
        if ex is None or j.updated_at >= ex.updated_at:
            by_id[j.job_id] = j
    return by_id


def submit(
    user_id: str,
    org_id: str,
    adaptation_mode: str = DEFAULT_ADAPTATION_MODE,
) -> TrainingJob:
    if not user_id:
        raise ValueError("user_id required")
    safe = _safe_org(org_id)
    if not safe:
        raise ValueError("invalid org_id (alphanumeric + _- only, max 32 chars)")
    if adaptation_mode not in VALID_ADAPTATION_MODE:
        raise ValueError(
            f"invalid adaptation_mode: {adaptation_mode}; "
            f"must be one of {VALID_ADAPTATION_MODE}"
        )
    now = time.time()
    job = TrainingJob(
        job_id=uuid.uuid4().hex,
        user_id=user_id,
        org_id=safe,
        status="queued",
        submitted_at=now,
        updated_at=now,
        edit_pair_count=count_edit_pairs(safe),
        adaptation_mode=adaptation_mode,
    )
    with _lock:
        _append_jsonl(job)
    return job


def list_for_user(user_id: str) -> list[TrainingJob]:
    if not user_id:
        return []
    with _lock:
        by_id = _coalesce_status(_read_jobs())
    return sorted(
        (j for j in by_id.values() if j.user_id == user_id),
        key=lambda j: j.submitted_at,
        reverse=True,
    )


def get(job_id: str) -> Optional[TrainingJob]:
    with _lock:
        by_id = _coalesce_status(_read_jobs())
    return by_id.get(job_id)


def mark_status(job_id: str, status: str, message: str = "", adapter_path: str = "") -> Optional[TrainingJob]:
    if status not in VALID_STATUS:
        raise ValueError(f"invalid status: {status}; must be one of {VALID_STATUS}")
    with _lock:
        by_id = _coalesce_status(_read_jobs())
        ex = by_id.get(job_id)
        if ex is None:
            return None
        ex.status = status
        ex.updated_at = time.time()
        if message:
            ex.message = message
        if adapter_path:
            ex.adapter_path = adapter_path
        _append_jsonl(ex)
        return ex


def reset_for_tests() -> None:
    if JOBS_PATH.exists():
        JOBS_PATH.unlink()
