"""
Deep-research controller — iterative, parallel, trust-grounded evidence seeking.

Architecture (harness + LLM + skills, see controller.py):
  research(question, user, retrieve_fn, decompose_fn=, assess_fn=, budget=)
    -> ResearchResult(answer: GroundedAnswer, rounds, trace, sources_used, stop_reason)

  router.route(question)         -> (ranked SourceSpec set, intent)
  registry.all_sources()         -> capability-tagged source catalog
"""

from .controller import Budget, ResearchResult, RoundTrace, Verdict, research
from . import registry, router

__all__ = [
    "research", "Budget", "ResearchResult", "RoundTrace", "Verdict",
    "registry", "router",
]
