"""The research synthesis states whether its retrieved papers answer the question.

External-user replay (dev, 2026-11-04): support questions, a dataset search and "ADMET profile of
imatinib" were answered "the provided literature does not contain …" because retrieval returned
off-topic papers and the chat then replaced its own answer with that literature-only reply. The
synthesis now opens with 'EVIDENCE: addresses|insufficient'; the line is stripped and returned as
evidence_answers_question so the chat can keep an uncited answer when the papers are off-topic.

Run: cd backend && PYTHONPATH=lib pytest tests/test_research_evidence_verdict.py -v
"""
import pytest

from galaxy.ai.agents.research_agent import ResearchAgent

split = ResearchAgent._split_evidence_verdict


@pytest.mark.parametrize("text, verdict, rest", [
    ("EVIDENCE: addresses\nFcRn inhibition reduces IgG [1].", True, "FcRn inhibition reduces IgG [1]."),
    ("EVIDENCE: insufficient\nThe papers are about microelectronics.", False, "The papers are about microelectronics."),
    ("**EVIDENCE: insufficient**\n\n现有文献未涉及该问题。", False, "现有文献未涉及该问题。"),
    ("  evidence: Addresses — two trials\nAnswer [2].", True, "Answer [2]."),
])
def test_verdict_line_is_parsed_and_stripped(text, verdict, rest):
    assert split(text) == (rest, verdict)


def test_no_verdict_line_leaves_the_answer_unchanged():
    assert split("FcRn inhibition [1]. EVIDENCE: addresses later in text") == (
        "FcRn inhibition [1]. EVIDENCE: addresses later in text", None)
    assert split("") == ("", None)
