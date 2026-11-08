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

from .arbiter import Arbiter, HarmonicSumArbiter
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
                 llm_client: Any = None, max_concurrent: int = 8, seed_top_n: int = 20):
        self.channels = list(channels)
        self.seed_top_n = seed_top_n
        # HONEST DEFAULT (benchmark_multidisease.py): the fusion does not beat OpenTargets-alone, so when an
        # OpenTargets channel is present we rank BY IT and use the other channels as corroboration/provenance
        # only (never a silent fusion that ranks worse than OT). Callers can pass an explicit arbiter to override.
        if arbiter is None:
            names = {getattr(ch, "name", "") for ch in self.channels}
            prim = "genetics_ot" if "genetics_ot" in names else None
            arbiter = HarmonicSumArbiter(primary_channel=prim)
        self.arbiter = arbiter
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

    def _seeds_from(self, results: List[ChannelResult], primary: Optional[str]):
        """Top genes of the primary (else the Open Targets) channel, used to seed the network channels."""
        for name in [n for n in (primary, "genetics_ot") if n]:
            for cr in results:
                if cr.channel == name and cr.ok:
                    top = sorted(cr.scores.items(), key=lambda kv: -kv[1])[: self.seed_top_n]
                    return [g for g, _ in top], name
        return [], None

    @staticmethod
    def _link_info(cr: ChannelResult, target: str) -> Dict[str, Any]:
        kind = cr.evidence_kind
        if kind == "model_judgment":
            return {"kind": kind, "url": None, "label": "model judgment, no citation"}
        if kind == "client_data":
            return {"kind": kind, "url": None,
                    "label": "hospital data: %s" % (cr.provenance.get("label") or cr.provenance.get("kind") or cr.channel)}
        link = cr.links.get(target)
        if link:
            return {"kind": kind, "url": link.get("url"), "label": link.get("label")}
        return {"kind": kind, "url": None, "label": str(cr.provenance.get("source") or cr.channel)}

    def _attach_links(self, ranked: List[Any], results: List[ChannelResult]) -> None:
        """Record, for every ranked target, which source stands behind each channel's score."""
        ok = {cr.channel: cr for cr in results if cr.ok}
        for ts in ranked:
            for ch, cr in ok.items():
                if ts.target in cr.scores:
                    ts.evidence.links[ch] = self._link_info(cr, ts.target)

    def identify(self, query: str, context: Optional[Dict[str, Any]] = None) -> OrchestratorResult:
        ctx = dict(context or {})
        ctx.setdefault("query", query)
        # Explicit caller candidates constrain the returned ranking. Candidates
        # merely proposed by the optional LLM planner are not a user restriction.
        requested = {str(g).upper() for g in ctx.get("candidate_targets", [])} if ctx.get("candidate_targets") else set()
        plan = self._plan(query, ctx)
        # Stage 1: channels that need no seeds, in parallel. Stage 2: channels that expand from a seed gene set
        # (STRING, pathway) run once stage 1 has produced the seeds (the primary channel's top genes), also in parallel.
        stage1 = [c for c in self.channels if not getattr(c, "needs_seeds", False)]
        stage2 = [c for c in self.channels if getattr(c, "needs_seeds", False)]
        results = _fanout(stage1, ctx, self.max_concurrent)
        seed_source: Optional[str] = None
        n_seeds = 0
        if stage2:
            ctx2 = dict(ctx)
            if ctx2.get("seed_genes"):
                seed_source = "request"
            else:
                seeds, seed_source = self._seeds_from(results, getattr(self.arbiter, "primary_channel", None))
                if seeds:
                    ctx2["seed_genes"] = seeds
            n_seeds = len(ctx2.get("seed_genes") or [])
            results = results + _fanout(stage2, ctx2, self.max_concurrent)
        errors = {cr.channel: cr.error for cr in results if cr.error}
        ranked = self.arbiter.rank(results, ctx)
        if requested:
            ranked = [t for t in ranked if t.target.upper() in requested]
            for rank, target in enumerate(ranked, 1):
                target.rank = rank
        self._attach_links(ranked, results)
        primary = getattr(self.arbiter, "primary_channel", None)
        primary_available = bool(primary and any(cr.channel == primary and cr.ok for cr in results))
        harmonic = isinstance(self.arbiter, HarmonicSumArbiter)
        return OrchestratorResult(
            query=query,
            targets=ranked,
            channels_run=[cr.channel for cr in results if cr.ok],
            channel_errors=errors,
            arbiter=getattr(self.arbiter, "name", "arbiter"),
            plan=plan,
            ranking={
                "mode": "primary_channel" if primary_available else ("weighted_harmonic_sum" if harmonic else "arbiter_specific"),
                "primary_channel": primary if primary_available else None,
                "requested_primary_channel": primary,
                "evidence_value_type": "normalized_score" if harmonic else "arbiter_specific",
                "requested_candidates": sorted(requested),
                "unscored_candidates": sorted(requested - {t.target.upper() for t in ranked}),
                "seed_source": seed_source,
                "n_seed_genes": n_seeds,
            },
            channel_provenance={cr.channel: cr.provenance for cr in results if cr.ok},
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
