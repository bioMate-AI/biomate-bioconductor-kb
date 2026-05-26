"""Held-out IND §2.6 corpus loader for the unified eval.

Reads `data/regulatory_training/tasks/splits_v6/test.jsonl` (326 lines per
session-time stats) and produces `Example` records the orchestrator iterates.
"""
from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator, Optional

_REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_TEST_PATH = _REPO_ROOT / "data" / "regulatory_training" / "tasks" / "splits_v6" / "test.jsonl"


@dataclass
class Example:
    id: str
    section_type: str   # tox_overview | pbpk | admet | ...
    region: str         # FDA | EMA | NMPA | PMDA
    system_prompt: str
    user_prompt: str
    reference_completion: str = ""  # gold, when present (for some checkers)
    raw: dict | None = None         # original line for debugging

    @property
    def short(self) -> str:
        return f"{self.id}|{self.section_type}|{self.region}"


def load_corpus(
    path: Optional[Path] = None,
    limit: Optional[int] = None,
    section_filter: Optional[set[str]] = None,
) -> list[Example]:
    """Load the v6 SFT test split.

    Schema is OpenAI chat-format (`messages: [system, user, assistant]`)
    plus a `meta` dict carrying `task`, `section_type`, and either
    `target_region` / `source_region` (for region_adaptation tasks) or no
    region (defaults to FDA).
    """
    src = path or DEFAULT_TEST_PATH
    if not src.exists():
        raise FileNotFoundError(f"corpus not found: {src}")
    examples: list[Example] = []
    with src.open() as f:
        for i, line in enumerate(f):
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue

            msgs = row.get("messages") or []
            meta = row.get("meta") or {}
            section = meta.get("section_type") or row.get("section_type") or "unknown"
            if section_filter and section not in section_filter:
                continue
            region = meta.get("target_region") or meta.get("source_region") or row.get("region") or "FDA"

            def _msg(role: str) -> str:
                for m in msgs:
                    if m.get("role") == role:
                        return m.get("content") or ""
                return ""

            system = _msg("system") or _default_system(section)
            user = _msg("user") or row.get("input") or row.get("instruction") or ""
            assistant = _msg("assistant") or row.get("output") or row.get("completion") or ""

            if not user:
                continue
            examples.append(Example(
                id=str(row.get("id", f"ex_{i:04d}")),
                section_type=section,
                region=region,
                system_prompt=system,
                user_prompt=user,
                reference_completion=assistant,
                raw=row,
            ))
            if limit is not None and len(examples) >= limit:
                break
    return examples


def _default_system(section_type: str) -> str:
    return (
        f"You are a regulatory writing assistant for IND module §2.6. "
        f"Produce a concise, factually-grounded paragraph for section type "
        f"{section_type}. Cite the relevant ICH guideline. Use past tense for "
        f"adverse findings; attribute them to the dose group. Always include "
        f"the [BioMate-generated draft] disclaimer prefix when generating "
        f"net-new prose for a customer."
    )


def iter_corpus(*args, **kwargs) -> Iterator[Example]:
    yield from load_corpus(*args, **kwargs)
