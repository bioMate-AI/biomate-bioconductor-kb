"""Blind-rule hook for arm G (design section 6): retrieval context must not contain the held-out documents, and, if a temporal
rule is used, nothing dated at or after the answer document. Unknown-provenance rows are excluded under strict mode."""
from __future__ import annotations

from dataclasses import dataclass
from typing import FrozenSet, Iterable, Optional


class BlindRuleViolation(AssertionError):
    pass


@dataclass(frozen=True)
class BlindRule:
    exclude_docs: FrozenSet[str] = frozenset()
    exclude_flat: FrozenSet[str] = frozenset()      # flat (stereo-free) keys of the answer set: no retrieval of the answers themselves
    max_year: Optional[int] = None                  # context documents must be dated <= max_year
    strict_docs: bool = True

    @classmethod
    def for_answer_docs(cls, docs: Iterable[str], answer_flat: Iterable[str] = (), before_year: Optional[int] = None,
                        strict: bool = True) -> "BlindRule":
        return cls(frozenset(docs), frozenset(answer_flat), None if before_year is None else before_year - 1, strict)

    def query_kwargs(self) -> dict:
        return dict(exclude_docs=self.exclude_docs, exclude_flat=self.exclude_flat, max_year=self.max_year,
                    strict_docs=self.strict_docs)

    def assert_clean(self, hits) -> None:
        for h in hits:
            if h.doc is not None and h.doc in self.exclude_docs:
                raise BlindRuleViolation(f"excluded document {h.doc} leaked into retrieval context")
            if h.flat_key in self.exclude_flat:
                raise BlindRuleViolation("answer-set compound leaked into retrieval context")
            if self.max_year is not None and h.doc_year is not None and h.doc_year > self.max_year:
                raise BlindRuleViolation(f"document dated {h.doc_year} > {self.max_year} leaked")
            if self.strict_docs and (self.exclude_docs or self.max_year is not None) and h.doc is None:
                raise BlindRuleViolation("row of unknown provenance leaked under a strict blind rule")
