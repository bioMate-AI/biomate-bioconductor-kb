"""Prompt builder: retrieval context for a causal LM, with a token-budget guard and optional pharmacophore text.
Never silently treats an un-encoded target as encoded: `pharmacophore_encoded` is reported in the result."""
from __future__ import annotations

import importlib.util
import math
import os
from dataclasses import dataclass, field
from typing import Callable, List, Optional, Sequence


class PromptTooLong(ValueError):
    pass


@dataclass(frozen=True)
class PromptResult:
    text: str
    n_tokens_est: int
    used: int
    dropped: int
    pharmacophore_encoded: bool
    meta: dict = field(default_factory=dict)


def _default_count(text: str) -> int:
    return int(math.ceil(len(text) / 2.5))      # conservative for SMILES-heavy text; replaced by the real tokenizer on EC2


def pharmacophore_text(target: Optional[str]) -> Optional[str]:
    """Short rule text from pharmacophore_knowledge.PHARMACOPHORE (cyclic_llm/), or None if the target is not encoded."""
    if not target:
        return None
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(here, "..", "..", "pharmacophore_knowledge.py")
    spec = importlib.util.spec_from_file_location("pharmacophore_knowledge", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    ph = mod.PHARMACOPHORE.get(target)
    if not ph:
        return None
    parts = [f"target class: {ph['class']}"]
    if ph.get("required_motifs"):
        parts.append("required motif(s): " + ", ".join(ph["required_motifs"]))
    if ph.get("preferred_regex"):
        parts.append("preferred pattern: " + ph["preferred_regex"])
    if ph.get("conformational_lock"):
        parts.append("conformational lock: " + ", ".join(ph["conformational_lock"]))
    return "; ".join(parts)


def _fmt_values(values: dict, keys: Sequence[str]) -> str:
    return " ".join(f"{k}={values[k]:.2f}" for k in keys if k in values)


def build_prompt(hits, target: Optional[str] = None, value_keys: Sequence[str] = ("pact",), max_tokens: int = 512,
                 count_tokens: Callable[[str], int] = _default_count, header: str = "Known cyclic peptides with measured values:",
                 footer: str = "New cyclic peptide (SMILES):") -> PromptResult:
    """Closest hit first. If over budget, the FARTHEST hits are dropped first; if even header + pharmacophore + footer exceed the
    budget, raises PromptTooLong (never silently truncates the footer or the pharmacophore)."""
    ph = pharmacophore_text(target)
    head = header + ("\nTarget knowledge: " + ph if ph else "")
    base = head + "\n" + footer
    if count_tokens(base) > max_tokens:
        raise PromptTooLong(f"fixed part needs {count_tokens(base)} > {max_tokens} tokens")
    lines: List[str] = [f"{h.smiles}\t{_fmt_values(h.values, value_keys)}".rstrip() for h in hits]
    keep = len(lines)

    def render(n):
        return head + "\n" + "\n".join(lines[:n]) + ("\n" if n else "") + footer

    while keep > 0 and count_tokens(render(keep)) > max_tokens:
        keep -= 1
    text = render(keep)
    return PromptResult(text, count_tokens(text), keep, len(lines) - keep, ph is not None,
                        dict(target=target, max_tokens=max_tokens))
