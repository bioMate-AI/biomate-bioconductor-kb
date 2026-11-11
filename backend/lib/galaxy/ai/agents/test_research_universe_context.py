"""Universe-aware research agent: answer a question about the user's OWN run
from the supplied context, not from general literature.

The frontend threads the user's recent-runs block (status · outputs · failed-run
diagnosis) + standing memory into `context['user_context']` on the research call.
These tests lock in that:

  1. a run-problem query WITH that context routes the synthesis prompt to answer
     from the run record (its actual status/error), with literature demoted to
     secondary — NOT a generic literature citation as the failure reason; and
  2. a genuine knowledge question is UNAFFECTED — the universe block is never
     injected and the literature path is unchanged.

Style follows test_research_citation_grounding.py: AST-extract only the methods
under test so the heavy galaxy import chain (and the broken local scipy) is never
dragged in.
"""
import ast
import asyncio
import json
import logging
import re
from pathlib import Path
from types import SimpleNamespace
from typing import Any, Dict, List, Optional


def _extract_agent(method_names):
    """Build a throwaway Agent class holding only the named ResearchAgent methods,
    exec'd in a minimal namespace (no galaxy imports)."""
    tree = ast.parse(Path(__file__).with_name("research_agent.py").read_text())
    cls = next(n for n in tree.body
               if isinstance(n, ast.ClassDef) and n.name == "ResearchAgent")
    methods = [n for n in cls.body
               if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))
               and n.name in method_names]
    found = {m.name for m in methods}
    missing = set(method_names) - found
    assert not missing, f"methods not found in ResearchAgent: {missing}"
    minimal = ast.Module(
        body=[ast.ClassDef(name="Agent", bases=[], keywords=[], body=methods,
                           decorator_list=[])],
        type_ignores=[])
    env = dict(Dict=Dict, Any=Any, List=List, Optional=Optional, json=json, re=re,
               asyncio=asyncio, log=logging.getLogger(__name__),
               ResearchResponse=SimpleNamespace, Citation=SimpleNamespace,
               _CONFLICT_INSTRUCTION="")
    exec(compile(ast.fix_missing_locations(minimal), "<universe-test>", "exec"), env)
    return env["Agent"]()


# A realistic universe_context block (shape produced by _buildRecentRunsBlock on
# the frontend): a FAILED run followed by its plain-language diagnosis.
_FAILED_RUN_CTX = (
    "[The user's recent workflow runs — STANDING context. Answer ANY question about "
    "the user's own runs from THIS; never treat such a question as a literature query.]\n"
    "  • a1b2c3d4 · nf-core/rnaseq · failed · 2026-11-08 · 0 outputs · this chat\n"
    "      cause: a required input was missing\n"
    "      at-fault input: reads.fastq (not provided)\n"
    "      next: attach the reads.fastq file and re-run\n"
    "      Error: NextflowError: Missing input file reads.fastq for process RNASEQ:FASTQC\n"
    "  • 9f8e7d6c · admet_standard · completed · 2026-11-07 · 5 outputs\n"
    "(call list_history for filtered/expanded details)\n"
)


# ── Detector: _is_about_user_runs ────────────────────────────────────────────

def test_detector_fires_on_user_run_questions():
    agent = _extract_agent({"_is_about_user_runs"})
    for q in (
        "Why did my run fail?",
        "why is it failing?",
        "What did my run produce?",
        "where are my results?",
        "Can you look at my last workflow and tell me what happened?",
        "show me the outputs of my rnaseq run",
        "what went wrong with this run?",
    ):
        assert agent._is_about_user_runs(q) is True, q


def test_detector_ignores_genuine_knowledge_questions():
    agent = _extract_agent({"_is_about_user_runs"})
    for q in (
        "What is the evidence linking APOE4 to Alzheimer's disease?",
        "Which aligner is best for long-read RNA-seq?",
        "How does STAR compare to HISAT2?",
        "In my view, what are the best benchmark results reported in the literature?",
        "What are best practices for single-cell normalization?",
    ):
        assert agent._is_about_user_runs(q) is False, q


# ── Prompt construction: _build_synthesis_prompt ─────────────────────────────

def test_run_question_with_user_context_builds_universe_first_prompt():
    agent = _extract_agent({"_build_synthesis_prompt", "_is_about_user_runs"})
    # Give it literature too, to prove literature is DEMOTED (not the failure reason).
    cite = SimpleNamespace(title="RNA-seq QC methods review", authors=["A B"], year=2021,
                           journal="Bioinformatics", doi="10.1/x", pmid="111", source="pubmed",
                           abstract="A review of QC.")
    ctx = {"information_need": "research", "user_context": _FAILED_RUN_CTX}
    prompt = agent._build_synthesis_prompt(
        "Why did my run fail?",
        {"intent": "research", "domain": "transcriptomics", "key_terms": ["rnaseq"]},
        {"citations": [cite]},
        ctx,
    )
    # Universe context is present and primary.
    assert "<universe_context>" in prompt
    assert "PRIMARY source" in prompt
    assert "PRIMARY TASK" in prompt
    # The actual recorded status + error reaches the model verbatim.
    assert "failed" in prompt
    assert "Missing input file reads.fastq" in prompt
    assert "reads.fastq (not provided)" in prompt
    # Literature must NOT be allowed to explain the failure.
    assert "NEVER cite a paper as the reason a specific run failed" in prompt
    assert "attribute a specific run's failure to a paper" in prompt
    # user_context is not ALSO dumped verbatim into the generic ## Context JSON.
    assert '"user_context"' not in prompt


def test_knowledge_question_with_user_context_is_unaffected():
    """Same user_context present, but a genuine literature question must keep its
    pure-literature prompt: no universe block, no run directive, and the runs block
    is not forced into the context dump (its strong 'answer from this' header would
    otherwise suppress the literature answer)."""
    agent = _extract_agent({"_build_synthesis_prompt", "_is_about_user_runs"})
    cite = SimpleNamespace(title="APOE4 and Alzheimer's", authors=["C D"], year=2020,
                           journal="Nature", doi="10.1/y", pmid="222", source="pubmed",
                           abstract="APOE4 raises risk.")
    ctx = {"information_need": "research", "user_context": _FAILED_RUN_CTX}
    prompt = agent._build_synthesis_prompt(
        "What is the evidence linking APOE4 to Alzheimer's disease?",
        {"intent": "research", "domain": "genomics", "key_terms": ["APOE4"]},
        {"citations": [cite]},
        ctx,
    )
    assert "<universe_context>" not in prompt
    assert "PRIMARY TASK" not in prompt
    # Runs block is not injected anywhere (neither as universe nor as background dump).
    assert "Missing input file reads.fastq" not in prompt
    assert '"user_context"' not in prompt
    # The normal literature contract is intact.
    assert "your ONLY citation list" in prompt


# ── End-to-end synthesis: _synthesize_response ───────────────────────────────

def _make_synth_agent():
    agent = _extract_agent({
        "_synthesize_response", "_build_synthesis_prompt", "_is_about_user_runs",
        "_ground_citations",
    })
    agent.llm_client = True
    agent.max_citations = 5
    # Stub the light-weight post-processing helpers (exercised by their own tests).
    agent._parse_llm_response = lambda answer: {"answer": answer}
    agent._split_evidence_verdict = lambda answer: (answer, None)
    agent._parse_conflicts_block = lambda answer: (answer, [])
    agent._compute_retrieval_stats = lambda pool, kept: []
    agent._ensure_evidence_boundary = lambda answer, *a: answer
    return agent


def test_synthesize_answers_failed_run_from_context_not_literature():
    """A compliant model, given the universe-first prompt, answers from the run
    record. _synthesize_response must surface that answer and attach NO literature
    citation (the model cited no [N]) — i.e. no paper is presented as the cause."""
    agent = _make_synth_agent()

    async def fake_llm(prompt, max_tokens=2000):
        # Simulate a model that follows the universe-first instruction: it only does
        # so when the universe block + directive are actually in the prompt.
        assert "PRIMARY TASK" in prompt and "<universe_context>" in prompt
        return ("Your nf-core/rnaseq run (a1b2c3d4) failed because a required input "
                "was missing — reads.fastq was not provided "
                "(Error: NextflowError: Missing input file reads.fastq). "
                "Attach reads.fastq and re-run.")
    agent._call_llm = fake_llm

    cite = SimpleNamespace(title="RNA-seq QC methods review", authors=["A B"], year=2021,
                           journal="Bioinformatics", doi="10.1/x", pmid="111", source="pubmed",
                           abstract="A review of QC.", relevance_score=0.3)
    ctx = {"user_context": _FAILED_RUN_CTX}
    resp = asyncio.run(agent._synthesize_response(
        "Why did my run fail?",
        {"intent": "research", "domain": "transcriptomics", "key_terms": ["rnaseq"]},
        {"citations": [cite]},
        ctx,
    ))
    # Answer references the ACTUAL recorded status/error, from context.
    assert "reads.fastq" in resp.answer
    assert "failed" in resp.answer.lower()
    # No literature citation is attached — nothing is presented as "the paper that
    # explains your failure".
    assert resp.citations == []
    assert "RNA-seq QC methods review" not in resp.answer


def test_synthesize_knowledge_question_keeps_literature_citation():
    """Control: a genuine knowledge question with the same context still grounds on
    retrieved literature — the universe plumbing does not disturb the literature path."""
    agent = _make_synth_agent()

    async def fake_llm(prompt, max_tokens=2000):
        assert "<universe_context>" not in prompt  # knowledge question → no universe block
        return "APOE4 is the strongest common genetic risk factor for Alzheimer's [1]."
    agent._call_llm = fake_llm

    cite = SimpleNamespace(title="APOE4 and Alzheimer's", authors=["C D"], year=2020,
                           journal="Nature", doi="10.1/y", pmid="222", source="pubmed",
                           abstract="APOE4 raises risk.", relevance_score=0.9)
    ctx = {"user_context": _FAILED_RUN_CTX}
    resp = asyncio.run(agent._synthesize_response(
        "What is the evidence linking APOE4 to Alzheimer's disease?",
        {"intent": "research", "domain": "genomics", "key_terms": ["APOE4"]},
        {"citations": [cite]},
        ctx,
    ))
    assert "[1]" in resp.answer
    assert len(resp.citations) == 1
    assert resp.citations[0].title == "APOE4 and Alzheimer's"


if __name__ == "__main__":
    import traceback
    _passed = _failed = 0
    for _name, _fn in sorted(globals().items()):
        if _name.startswith("test_") and callable(_fn):
            try:
                _fn()
                print(f"PASS {_name}")
                _passed += 1
            except Exception:
                print(f"FAIL {_name}")
                traceback.print_exc()
                _failed += 1
    print(f"{_passed} passed, {_failed} failed")
