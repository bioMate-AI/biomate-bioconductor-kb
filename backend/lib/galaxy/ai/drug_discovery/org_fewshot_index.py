"""
Lane B3 few_shot_index — real implementation.

Builds a per-org retrieval index over the customer's accepted (chosen)
edit text. At inference time _build_rag_context picks the top-K
exemplars whose section_type + token-overlap with the prompt are best,
and injects them as few-shot demonstrations.

Design: keyword-overlap retrieval. Pure stdlib — no sklearn, no model
download. The bag-of-words token set is built once at index time. At
query time we score each candidate by Jaccard overlap with the query
tokens, filtered to the same section_type first.

Index file format (JSONL, one row per chosen-text exemplar):
  {
    "section_type": "pbpk",
    "task":         "pbpk",          # optional
    "exemplar":     "<chosen text>", # up to 800 chars
    "tokens":       ["pbpk", "ema", "criterion", ...]
  }

Loader returns plain text bullets ready for the RAG block.
"""
from __future__ import annotations
import json, re
from collections import Counter
from pathlib import Path
from typing import Any

# Minimal English stopword set — keeps the retrieval signal focused on
# domain vocabulary (compounds, citations, modalities) without dragging
# in NLTK.
_STOPWORDS = {
    "a", "an", "the", "and", "or", "but", "if", "then", "else", "of",
    "in", "on", "to", "for", "by", "with", "from", "as", "at", "is",
    "was", "were", "be", "been", "being", "are", "this", "that", "these",
    "those", "it", "its", "we", "they", "their", "our", "you", "he",
    "she", "his", "her", "i", "me", "my", "do", "does", "did", "have",
    "has", "had", "not", "no", "yes", "so", "such", "than", "into",
    "over", "under", "via", "per", "also", "however", "thus", "while",
    "when", "where", "what", "which", "who", "whom", "whose", "how",
    "any", "all", "each", "some", "more", "most", "less", "least",
    "may", "might", "must", "should", "shall", "will", "would", "could",
}

_TOKEN_RE = re.compile(r"[A-Za-z][A-Za-z0-9]+(?:[\-/(][A-Za-z0-9]+)*")


def _tokens(text: str) -> list[str]:
    """Tokenise to lowercased word/identifier stems. Citations like
    'EMA/CHMP/EWP/37498/2011' or 'ICH M3(R2)' survive intact as the
    regex permits slash, hyphen, paren joiners inside a token."""
    out = []
    for m in _TOKEN_RE.finditer(text or ""):
        t = m.group(0).lower()
        if t in _STOPWORDS or len(t) < 2:
            continue
        out.append(t)
    return out


def build_index(
    pairs_path: Path,
    org_id: str,
    max_exemplars: int = 64,
    max_chars: int = 800,
) -> list[dict[str, Any]]:
    """Walk customer_pairs.jsonl, filter to org (org-tagged + global
    untagged rows), produce up to `max_exemplars` retrieval rows from
    the `chosen` text. Rejected text is intentionally ignored — the
    index represents what the customer WANTS the model to say."""
    if not pairs_path.exists():
        return []

    rows: list[dict[str, Any]] = []
    for line in pairs_path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except Exception:
            continue
        row_org = (row.get("meta") or {}).get("org_id") or row.get("org_id")
        if row_org and str(row_org) != org_id:
            continue

        chosen = (row.get("chosen") or "").strip()
        if not chosen:
            continue

        meta = row.get("meta") or {}
        section_type = meta.get("section_type") or meta.get("task") or "unknown"
        rows.append({
            "section_type": str(section_type),
            "task":         str(meta.get("task") or ""),
            "exemplar":     chosen[:max_chars],
            "tokens":       _tokens(chosen),
        })
        if len(rows) >= max_exemplars:
            break

    return rows


def write_index(out_path: Path, rows: list[dict[str, Any]]) -> int:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    return len(rows)


def build_and_write(pairs_path: Path, out_path: Path, org_id: str) -> int:
    return write_index(out_path, build_index(pairs_path, org_id))


# ─── Loader — RAG-ready exemplars for _build_rag_context ─────────────────
def _jaccard(a: set[str], b: set[str]) -> float:
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


def load_top_exemplars(
    index_path: Path,
    section_type: str,
    prompt_text: str = "",
    k: int = 2,
) -> list[str]:
    """Return up to `k` exemplar paragraphs for the given section. When
    prompt_text is non-empty, score by token Jaccard overlap; otherwise
    return the most recently indexed ones. Always section-filtered when
    we have any matching rows, otherwise falls back to any-section."""
    if not index_path.exists() or k <= 0:
        return []

    rows: list[dict[str, Any]] = []
    for line in index_path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        try:
            rows.append(json.loads(line))
        except Exception:
            continue

    if not rows:
        return []

    # Section-filtered first; fall back to all-section if nothing matches
    section_rows = [r for r in rows if r.get("section_type") == section_type]
    pool = section_rows if section_rows else rows

    if prompt_text:
        q_tokens = set(_tokens(prompt_text))
        scored = sorted(
            pool,
            key=lambda r: _jaccard(q_tokens, set(r.get("tokens") or [])),
            reverse=True,
        )
    else:
        # Most recently indexed (input order is index time)
        scored = list(reversed(pool))

    return [r.get("exemplar", "") for r in scored[:k] if r.get("exemplar")]


def load_fewshot_block(
    index_path: Path,
    section_type: str,
    prompt_text: str = "",
    k: int = 2,
) -> list[str]:
    """Wrap the top-K exemplars into RAG bullets ready for
    _build_rag_context. Returns empty list when the index is empty so
    the caller emits nothing rather than a hollow header."""
    exemplars = load_top_exemplars(index_path, section_type, prompt_text, k)
    return [
        f"Example of preferred {section_type} prose from this org's edits:\n    {e}"
        for e in exemplars
    ]
