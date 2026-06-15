"""
Lane B3 prompt_rules — real compiler.

Reads customer_pairs.jsonl entries scoped to an org, extracts the signal
worth carrying into the next inference call as a per-org RAG block, and
writes it as YAML to data/regulatory_training/org_rules/<org>.yaml.

What we extract (cheap, deterministic, no LLM):

  preferred_citations
    Citation tokens (ICH, EMA/CHMP, FDA, 21 CFR, CDISC, MHLW, NMPA…) that
    appear in `chosen` but NOT in `rejected`. These are corrections the
    customer made that added a citation the model omitted. Sorted by
    times-observed desc; cap top-K so the RAG block stays focused.

  banned_phrases
    Distinct sentences (≤120 chars) that appear in `rejected` but NOT in
    `chosen`. These are sentences the customer removed. Same cap.

  preferred_phrases
    Distinct sentences that appear in `chosen` but NOT in `rejected`. The
    customer's additions. Same cap.

  meta
    pairs_observed (total), tasks (distribution), sections (distribution)
    so the operator can see what the org has been correcting.

Loader: regulatory_region_packs.org_rule_block(org_id, section_type) (in
this module too) reads the YAML and returns a list of natural-language
rules ready for _build_rag_context to inject.

Pure Python + PyYAML. No new dependencies beyond what's already in repo.
"""
from __future__ import annotations
import json, re
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Optional

import yaml

# ─── Citation token extractor — same regex family as reference_metrics ────
_CIT_RE = re.compile(
    # Leading \b prevents false starts (e.g. "xICH"). No trailing \b: the
    # ICH alternative ends in "...)? which means after a successful
    # "ICH S2(R1)" match, the trailing \b would have *also* been satisfied
    # at "ICH S2" because `(` is non-word — so the engine would truncate.
    # Each alternative is unambiguous enough that we don't need a closing
    # boundary.
    r"\b("
    r"ICH\s*[MQSE]\d+[A-Z]?(?:\([RS]?\d+\))?"
    r"|EMA/CHMP/[A-Z0-9/]+"
    r"|FDA\s+\d{4}"
    r"|21\s*CFR\s*\d+(?:\.\d+)*"
    r"|MHLW\s+(?:Notification|PSEHB)[^.,;]{0,40}"
    r"|NMPA\s+Announcement\s+No\.?\s*\d+"
    r"|CDER|CBER|CDISC|GLP|GCP|GMP|NMPA|PMDA|MHRA|TGA"
    r")",
    re.IGNORECASE,
)


def _norm_cit(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip().upper()


def _citations(text: str) -> set[str]:
    return {_norm_cit(m.group(0)) for m in _CIT_RE.finditer(text)}


# ─── Sentence-level diff ──────────────────────────────────────────────────
_SENT_SPLIT = re.compile(r"(?<=[.!?])\s+(?=[A-Z])")


def _sentences(text: str, max_chars: int = 240) -> list[str]:
    sents = []
    for s in _SENT_SPLIT.split(text or ""):
        s = re.sub(r"\s+", " ", s).strip()
        if 12 <= len(s) <= max_chars:
            sents.append(s)
    return sents


def _norm_sent(s: str) -> str:
    return re.sub(r"\s+", " ", s.lower()).strip().rstrip(".!?")


# ─── Compiler ─────────────────────────────────────────────────────────────
def compile_org_rules(
    pairs_path: Path,
    org_id: str,
    top_k: int = 8,
) -> dict[str, Any]:
    """Read customer_pairs.jsonl, filter to this org, return the rule pack."""
    pref_cits: Counter = Counter()
    banned_sents: Counter = Counter()
    pref_sents: Counter = Counter()
    tasks: Counter = Counter()
    sections: Counter = Counter()
    pair_n = 0

    if not pairs_path.exists():
        return _empty(org_id)

    for line in pairs_path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except Exception:
            continue

        # Org filter: explicit meta.org_id matches, or untagged ("global")
        row_org = (row.get("meta") or {}).get("org_id") or row.get("org_id")
        if row_org and str(row_org) != org_id:
            continue

        chosen = str(row.get("chosen") or "")
        rejected = str(row.get("rejected") or "")
        if not chosen and not rejected:
            continue

        pair_n += 1
        meta = row.get("meta") or {}
        if meta.get("task"):         tasks[meta["task"]] += 1
        if meta.get("section_type"): sections[meta["section_type"]] += 1

        # Citation delta
        for c in _citations(chosen) - _citations(rejected):
            pref_cits[c] += 1

        # Sentence delta — normalized so trivial whitespace differences
        # don't double-count
        chosen_norm = {_norm_sent(s): s for s in _sentences(chosen)}
        rejected_norm = {_norm_sent(s): s for s in _sentences(rejected)}
        for k in (chosen_norm.keys() - rejected_norm.keys()):
            pref_sents[chosen_norm[k]] += 1
        for k in (rejected_norm.keys() - chosen_norm.keys()):
            banned_sents[rejected_norm[k]] += 1

    return {
        "org_id": org_id,
        "pairs_observed": pair_n,
        "preferred_citations": [c for c, _ in pref_cits.most_common(top_k)],
        "preferred_phrases":   [s for s, _ in pref_sents.most_common(top_k)],
        "banned_phrases":      [s for s, _ in banned_sents.most_common(top_k)],
        "tasks":    dict(tasks),
        "sections": dict(sections),
    }


def _empty(org_id: str) -> dict[str, Any]:
    return {
        "org_id": org_id,
        "pairs_observed": 0,
        "preferred_citations": [],
        "preferred_phrases":   [],
        "banned_phrases":      [],
        "tasks":    {},
        "sections": {},
    }


def write_rule_pack(out_path: Path, pack: dict[str, Any]) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    header = "# per-org rule pack — generated by regulatory_training_worker\n"
    out_path.write_text(header + yaml.safe_dump(pack, sort_keys=False), encoding="utf-8")


# ─── Loader — produces RAG-ready bullets for _build_rag_context ──────────
def load_org_rule_block(rules_path: Path, section_type: str) -> list[str]:
    """Read a per-org rule YAML and return a focused list of bullets the
    LLM should respect on the NEXT generation. Filters by section so we
    don't drown the prompt in unrelated rules.
    """
    if not rules_path.exists():
        return []
    try:
        pack = yaml.safe_load(rules_path.read_text(encoding="utf-8")) or {}
    except Exception:
        return []

    out: list[str] = []
    for cit in (pack.get("preferred_citations") or [])[:4]:
        out.append(f"Cite '{cit}' when relevant (this org prefers it).")
    for phrase in (pack.get("preferred_phrases") or [])[:3]:
        out.append(f"Prefer phrasing: \"{phrase}\"")
    for phrase in (pack.get("banned_phrases") or [])[:3]:
        out.append(f"Avoid phrasing: \"{phrase}\"")
    return out


# ─── Tiny helper for the worker ───────────────────────────────────────────
def compile_and_write(pairs_path: Path, out_path: Path, org_id: str) -> int:
    """One-shot for the worker. Returns pair count consumed."""
    pack = compile_org_rules(pairs_path, org_id)
    write_rule_pack(out_path, pack)
    return int(pack.get("pairs_observed", 0))
