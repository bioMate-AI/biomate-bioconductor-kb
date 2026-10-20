"""Evidence channels for the target-ID orchestrator.

A Channel turns a context (query/disease/seed genes/candidate targets) into raw per-target
evidence scores. Channels run in PARALLEL (orchestrator fan-out) and fail soft. v1 ships the
Channel contract + a MockChannel (tests) + an LLMReasonedChannel (frontier-LLM "VC-reasoned"
channel). Real data channels (genetics via gwas_scrna_eqtl_target_chain, PPI/STRING, pathway/TF,
CAPTAIN/scGPT-as-channel) register the same interface in the next increment — the orchestrator
and arbiter already handle any registered channel.

3.9-safe. No galaxy/numpy import at load; LLM client is injected (duck-typed .generate).
"""
import json
import re
from abc import ABC, abstractmethod
from typing import Any, Callable, Dict, List, Optional

from .types import ChannelResult


class Channel(ABC):
    name = "channel"

    @abstractmethod
    def run(self, context: Dict[str, Any]) -> ChannelResult:
        """Return a ChannelResult of {target: raw_score}. Must fail soft (never raise)."""
        raise NotImplementedError


class MockChannel(Channel):
    """Deterministic channel for tests/offline smoke — returns injected scores."""

    def __init__(self, name: str, scores: Dict[str, float], provenance: Optional[Dict] = None):
        self.name = name
        self._scores = dict(scores)
        self._prov = provenance or {"source": "mock"}

    def run(self, context: Dict[str, Any]) -> ChannelResult:
        return ChannelResult(channel=self.name, scores=dict(self._scores), provenance=dict(self._prov))


def _parse_json_obj(text: str) -> Optional[dict]:
    """Extract the first JSON object from an LLM response (handles prose/markdown fences)."""
    if not text:
        return None
    m = re.search(r"\{[\s\S]*\}", text)
    if not m:
        return None
    try:
        return json.loads(m.group(0))
    except Exception:
        return None


class LLMReasonedChannel(Channel):
    """Frontier-LLM-reasoned evidence channel (the 'VC/literature-reasoned' channel).

    Scores candidate targets for relevance to the query by prompting an injected LLM client
    (duck-typed: ``.generate(prompt, **kwargs) -> str``). Deliberately a CHANNEL, not the
    arbiter — it must earn its place via the gate like any other. Fails soft on any error.

    context keys used: 'query' (str, required), 'candidate_targets' (List[str], optional —
    if absent, the LLM proposes up to max_targets).
    """

    name = "llm_reasoned"

    def __init__(self, llm_client: Any, name: str = "llm_reasoned", max_targets: int = 50,
                 generate_kwargs: Optional[Dict] = None):
        self.llm = llm_client
        self.name = name
        self.max_targets = max_targets
        self.generate_kwargs = generate_kwargs or {"max_tokens": 1500, "temperature": 0.0}

    def _prompt(self, query: str, candidates: Optional[List[str]]) -> str:
        if candidates:
            cand = ", ".join(candidates[: self.max_targets])
            scope = ("Score EACH of these candidate targets for how strongly current evidence "
                     "supports them as a drug target for the query. Candidates: " + cand)
        else:
            scope = (f"Propose up to {self.max_targets} of the most credible candidate drug "
                     "targets for the query, and score each.")
        return (
            "You are a cautious target-biology evaluator. " + scope + "\n"
            f"Query: {query}\n"
            "Return ONLY a JSON object mapping each gene symbol (string) to a score in [0,1] "
            "(1 = strongest evidence). Do not include commentary. Unknown -> omit it."
        )

    def run(self, context: Dict[str, Any]) -> ChannelResult:
        query = (context or {}).get("query") or ""
        if self.llm is None:
            return ChannelResult(channel=self.name, error="no llm_client injected")
        if not query:
            return ChannelResult(channel=self.name, error="no query in context")
        candidates = context.get("candidate_targets")
        try:
            raw = self.llm.generate(self._prompt(query, candidates), **self.generate_kwargs)
        except Exception as e:  # fail soft
            return ChannelResult(channel=self.name, error="llm error: %s: %s" % (type(e).__name__, e))
        obj = _parse_json_obj(raw)
        if not isinstance(obj, dict):
            return ChannelResult(channel=self.name, error="llm returned no parseable JSON object")
        scores = {}
        for k, v in obj.items():
            try:
                scores[str(k).upper()] = float(v)
            except Exception:
                continue
        if not scores:
            return ChannelResult(channel=self.name, error="no numeric scores parsed")
        return ChannelResult(channel=self.name, scores=scores,
                             provenance={"source": "llm_reasoned", "model": getattr(self.llm, "model", "?")})


class CallableChannel(Channel):
    """Adapter so a plain function (context)->{target: score} becomes a Channel (fails soft)."""

    def __init__(self, name: str, fn: Callable[[Dict[str, Any]], Dict[str, float]],
                 provenance: Optional[Dict] = None):
        self.name = name
        self._fn = fn
        self._prov = provenance or {"source": name}

    def run(self, context: Dict[str, Any]) -> ChannelResult:
        try:
            scores = self._fn(context) or {}
        except Exception as e:
            return ChannelResult(channel=self.name, error="%s: %s" % (type(e).__name__, e))
        scores = {str(k): float(v) for k, v in scores.items()}
        return ChannelResult(channel=self.name, scores=scores, provenance=dict(self._prov))
