"""Confidence must track GROUNDING, not be a constant.

Regression for the stub that returned a flat 0.8 → every answer, including a
non-answer that restates the question, printed "reasonable confidence". Pure
logic; `_grounding_confidence` does not touch instance state, so we bypass the
heavy __init__.
"""
from galaxy.ai.agents.research_agent import ResearchAgent


def _gc(evidence_verdict, n_citations, n_db_channels=0):
    agent = ResearchAgent.__new__(ResearchAgent)  # no heavy __init__
    return agent._grounding_confidence(evidence_verdict, n_citations, n_db_channels)


def _level(c):
    return "limited" if c < 0.5 else ("moderate" if c < 0.8 else "reasonable")


def test_insufficient_verdict_is_limited():
    # model said the retrieved evidence does NOT address the question
    assert _level(_gc(False, 2, 0)) == "limited"


def test_nothing_grounded_is_limited():
    assert _level(_gc(True, 0, 0)) == "limited"


def test_two_paper_hedge_is_not_reasonable():
    # the ABL1 failure: 2 papers, model did not affirm coverage
    assert _level(_gc(None, 2, 0)) == "moderate"


def test_affirmed_with_breadth_is_reasonable():
    assert _level(_gc(True, 1, 2)) == "reasonable"


def test_db_channels_credit_confidence():
    # a DB-grounded answer (few literature citations) still reaches reasonable
    # when the model affirms coverage and multiple sources contributed
    assert _level(_gc(True, 0, 3)) == "reasonable"


def test_never_constant_0_8():
    # the whole point: the value now varies with grounding, it is not a fixed 0.8
    vals = {_gc(False, 0, 0), _gc(None, 1, 0), _gc(True, 2, 2), _gc(True, 5, 5)}
    assert len(vals) > 1 and 0.8 not in vals
