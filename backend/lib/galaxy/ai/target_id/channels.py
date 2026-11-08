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
    needs_seeds = False            # True for channels that expand from a seed gene set (STRING, pathway)
    evidence_kind = "public_source"

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


def _strip_reasoning(text: str) -> str:
    """Remove reasoning-model scaffolding that precedes or wraps the JSON answer."""
    text = re.sub(r"<think>[\s\S]*?</think>", "", text, flags=re.IGNORECASE)
    text = re.sub(r"^```[a-zA-Z]*\s*|```\s*$", "", text.strip(), flags=re.MULTILINE)
    return text


def _balanced_objects(text: str):
    """Yield every top-level {...} substring that is brace-balanced (strings and escapes respected)."""
    i, n = 0, len(text)
    while i < n:
        if text[i] != "{":
            i += 1
            continue
        depth, j, in_str, esc = 0, i, False, False
        while j < n:
            ch = text[j]
            if in_str:
                if esc:
                    esc = False
                elif ch == "\\":
                    esc = True
                elif ch == '"':
                    in_str = False
            elif ch == '"':
                in_str = True
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    yield text[i:j + 1]
                    break
            j += 1
        i = j + 1 if depth == 0 else i + 1


def _parse_json_obj(text: str) -> Optional[dict]:
    """Extract the first JSON object from an LLM response.

    Handles prose, markdown fences, reasoning-model <think> blocks and trailing commentary. Returns the
    first brace-balanced object that parses to a dict, or None."""
    if not text:
        return None
    for cand in _balanced_objects(_strip_reasoning(text)):
        try:
            obj = json.loads(cand)
        except Exception:
            continue
        if isinstance(obj, dict):
            return obj
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
    evidence_kind = "model_judgment"

    def __init__(self, llm_client: Any, name: str = "llm_reasoned", max_targets: int = 50,
                 generate_kwargs: Optional[Dict] = None, retries: int = 1, max_tokens_cap: int = 6000):
        self.llm = llm_client
        self.name = name
        self.max_targets = max_targets
        self.generate_kwargs = generate_kwargs or {"max_tokens": 1500, "temperature": 0.0}
        # Reasoning models can spend the whole token budget thinking and return no JSON; on a parse failure
        # we retry up to ``retries`` times with a doubled budget (capped) before reporting a channel error.
        self.retries = retries
        self.max_tokens_cap = max_tokens_cap

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
        kwargs = dict(self.generate_kwargs)
        obj, last_err = None, None
        for attempt in range(self.retries + 1):
            try:
                raw = self.llm.generate(self._prompt(query, candidates), **kwargs)
            except Exception as e:  # fail soft
                return ChannelResult(channel=self.name, evidence_kind=self.evidence_kind,
                                     error="llm error: %s: %s" % (type(e).__name__, e))
            obj = _parse_json_obj(raw)
            if isinstance(obj, dict):
                break
            last_err = "llm returned no parseable JSON object"
            if "max_tokens" in kwargs:       # give a reasoning model room to finish thinking AND answer
                kwargs["max_tokens"] = min(int(kwargs["max_tokens"]) * 2, self.max_tokens_cap)
        if not isinstance(obj, dict):
            return ChannelResult(channel=self.name, evidence_kind=self.evidence_kind, error=last_err)
        scores = {}
        for k, v in obj.items():
            try:
                scores[str(k).upper()] = float(v)
            except Exception:
                continue
        if not scores:
            return ChannelResult(channel=self.name, evidence_kind=self.evidence_kind, error="no numeric scores parsed")
        return ChannelResult(channel=self.name, scores=scores, evidence_kind=self.evidence_kind,
                             provenance={"source": "llm_reasoned", "model": getattr(self.llm, "model", "?"),
                                         "note": "model judgment; no per-target citation"})


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
