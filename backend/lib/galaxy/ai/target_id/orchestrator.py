"""TargetIDOrchestrator — frontier-LLM-planned, parallel multi-channel target identification.

Flow: (optional) LLM plan -> run all channels IN PARALLEL -> arbiter fuses to a ranked,
confidence-tiered target list with provenance. Reuses the audited shared fan-out primitive
``galaxy.ai.map_reduce`` when available, with a self-contained ThreadPoolExecutor fallback so
the module is importable + testable without the rest of galaxy. The LLM is optional and only
plans/annotates — the ranking comes from the arbiter (channels earn their place via the gate).

3.9-safe. Heavy galaxy deps are imported lazily inside methods.
"""
import json
import re
from typing import Any, Dict, List, Optional

from .arbiter import Arbiter, EvidenceGateArbiter
from .channels import Channel
from .types import ChannelResult, OrchestratorResult


def _fanout(channels: List[Channel], context: Dict[str, Any], max_concurrent: int) -> List[ChannelResult]:
    """Run channels concurrently. Each worker fails soft into a ChannelResult (never raises)."""
    def work(ch: Channel) -> ChannelResult:
        try:
            return ch.run(context)
        except Exception as e:  # defence in depth; Channel.run should already fail soft
            return ChannelResult(channel=getattr(ch, "name", "channel"),
                                 error="%s: %s" % (type(e).__name__, e))
    # Prefer the shared, audited primitive.
    try:
        from galaxy.ai.map_reduce import map_reduce
        res = map_reduce(channels, work, max_concurrent=max_concurrent, on_error="collect")
        return list(res.get("results", []))
    except Exception:
        from concurrent.futures import ThreadPoolExecutor
        if not channels:
            return []
        with ThreadPoolExecutor(max_workers=max(1, min(max_concurrent, len(channels)))) as ex:
            return list(ex.map(work, channels))


class TargetIDOrchestrator:
    def __init__(self, channels: List[Channel], arbiter: Optional[Arbiter] = None,
                 llm_client: Any = None, max_concurrent: int = 8):
        self.channels = list(channels)
        self.arbiter = arbiter or EvidenceGateArbiter()
        self.llm = llm_client
        self.max_concurrent = max_concurrent

    def _plan(self, query: str, context: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Optional LLM planning: seed candidate targets / which channels matter. Fails soft."""
        if self.llm is None:
            return None
        prompt = (
            "You are planning a drug-target identification campaign. For the query below, return "
            "ONLY a JSON object with keys: 'candidate_targets' (list of up to 50 gene symbols that "
            "are plausible targets to score) and 'rationale' (one sentence). Query: " + query
        )
        try:
            raw = self.llm.generate(prompt, max_tokens=800, temperature=0.0)
            m = re.search(r"\{[\s\S]*\}", raw or "")
            plan = json.loads(m.group(0)) if m else None
        except Exception:
            return None
        if isinstance(plan, dict) and isinstance(plan.get("candidate_targets"), list):
            # seed channels that can use candidates (e.g. LLMReasonedChannel) unless caller set them
            context.setdefault("candidate_targets", [str(g).upper() for g in plan["candidate_targets"]])
            return plan
        return None

    def identify(self, query: str, context: Optional[Dict[str, Any]] = None) -> OrchestratorResult:
        ctx = dict(context or {})
        ctx.setdefault("query", query)
        plan = self._plan(query, ctx)
        results = _fanout(self.channels, ctx, self.max_concurrent)
        errors = {cr.channel: cr.error for cr in results if cr.error}
        ranked = self.arbiter.rank(results, ctx)
        return OrchestratorResult(
            query=query,
            targets=ranked,
            channels_run=[cr.channel for cr in results if cr.ok],
            channel_errors=errors,
            arbiter=getattr(self.arbiter, "name", "arbiter"),
            plan=plan,
        )


def create_target_id_orchestrator(channels: Optional[List[Channel]] = None, arbiter: Optional[Arbiter] = None,
                                   llm_client: Any = None, use_llm_planning: bool = False,
                                   max_concurrent: int = 8) -> TargetIDOrchestrator:
    """Factory. If ``channels`` is None, caller must register channels before .identify().
    When ``use_llm_planning`` and no llm_client is given, lazily wires the galaxy LLMClient.
    """
    if llm_client is None and use_llm_planning:
        try:
            from galaxy.ai.llm_client import LLMClient
            from galaxy.ai.config import AIConfig
            llm_client = LLMClient(AIConfig())
        except Exception:
            llm_client = None
    return TargetIDOrchestrator(channels or [], arbiter=arbiter, llm_client=llm_client,
                                max_concurrent=max_concurrent)
