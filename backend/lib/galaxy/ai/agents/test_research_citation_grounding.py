"""Exercise synthesis citation selection without importing optional Galaxy services."""
import ast
import asyncio
import logging
from pathlib import Path
from types import SimpleNamespace
from typing import Any, Dict, List, Optional


def test_clarification_does_not_inherit_uncited_search_candidates():
    tree = ast.parse(Path(__file__).with_name('research_agent.py').read_text())
    cls = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == 'ResearchAgent')
    names = {'_synthesize_response', '_ground_citations'}
    methods = [n for n in cls.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name in names]
    minimal = ast.Module(body=[ast.ClassDef(name='Agent', bases=[], keywords=[], body=methods, decorator_list=[])], type_ignores=[])
    env = dict(Dict=Dict, Any=Any, List=List, Optional=Optional, ResearchResponse=SimpleNamespace, Citation=SimpleNamespace, log=logging.getLogger(__name__))
    exec(compile(ast.fix_missing_locations(minimal), '<synthesis-test>', 'exec'), env)
    agent = env['Agent']()
    agent.llm_client = True
    agent.max_citations = 5
    agent._build_synthesis_prompt = lambda *args: 'prompt'
    agent._parse_llm_response = lambda answer: {'answer': answer}
    agent._split_evidence_verdict = lambda answer: (answer, None)
    agent._parse_conflicts_block = lambda answer: (answer, [])
    agent._compute_retrieval_stats = lambda pool, kept: []
    agent._ensure_evidence_boundary = lambda answer, *args: answer
    async def reply(*args, **kwargs):
        return 'Please provide the scaffold name or SMILES so I can find prior assays.'
    agent._call_llm = reply
    candidate = SimpleNamespace(title='Unrelated scaffold paper', authors=[], year=None, journal=None, doi='10.1/unrelated', pmid=None, abstract='Unrelated abstract', relevance_score=0.2)
    result = asyncio.run(agent._synthesize_response('Have we assayed this scaffold?', {}, {'citations': [candidate]}))
    assert result.citations == []
    assert 'Please provide' in result.answer


def _extract_build_synthesis_prompt():
    """Extract _build_synthesis_prompt in isolation (no heavy Galaxy imports)."""
    import json
    tree = ast.parse(Path(__file__).with_name('research_agent.py').read_text())
    cls = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == 'ResearchAgent')
    method = next(n for n in cls.body
                  if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))
                  and n.name == '_build_synthesis_prompt')
    minimal = ast.Module(
        body=[ast.ClassDef(name='Agent', bases=[], keywords=[], body=[method], decorator_list=[])],
        type_ignores=[])
    env = dict(Dict=Dict, Any=Any, List=List, Optional=Optional, json=json,
               _CONFLICT_INSTRUCTION='')
    exec(compile(ast.fix_missing_locations(minimal), '<synthesis-prompt-test>', 'exec'), env)
    return env['Agent']()


def test_empty_citations_injects_no_confabulation_guard():
    # Zero retrieved citations on a deep evidence-review query MUST produce the
    # explicit NONE guard (no table / PMID / DOI / records-count) and the
    # 'EVIDENCE: insufficient' opener — the model-independent anti-confabulation
    # defense restored after the DB-facts refactor dropped it.
    agent = _extract_build_synthesis_prompt()
    q = ("Provide a rigorous evidence table with one row per study, verifying every PMID, "
         "for every major claim that ZZZX9 directly ubiquitinates QQR7B.")
    prompt = agent._build_synthesis_prompt(q, {'intent': 'research', 'domain': 'x', 'key_terms': []},
                                           {'citations': []}, None)
    assert 'Retrieved Literature: NONE' in prompt
    assert 'EVIDENCE: insufficient' in prompt
    assert 'MUST NOT' in prompt
    # the deep-mode table instruction must be the GATED (forbid) variant, not the ask-for-table one
    assert 'Do NOT produce an evidence table' in prompt
    assert 'produce a markdown evidence table' not in prompt


def test_present_citations_use_numbered_list_and_table_allowed():
    # With retrieved citations the prompt injects the numbered 'ONLY citation list'
    # and (deep mode) permits the evidence table.
    agent = _extract_build_synthesis_prompt()
    cite = SimpleNamespace(title='Real paper', authors=['A B'], year=2020, journal='J',
                           doi='10.1/real', pmid='12345678', source='pubmed', abstract='abs')
    q = ("Provide a rigorous evidence table with one row per study for the claim that X binds Y.")
    prompt = agent._build_synthesis_prompt(q, {'intent': 'research', 'domain': 'x', 'key_terms': []},
                                           {'citations': [cite]}, None)
    assert 'your ONLY citation list' in prompt
    assert 'never invent a DOI, PMID, or PDB ID' in prompt
    assert 'produce a markdown evidence table' in prompt
    assert 'Retrieved Literature: NONE' not in prompt
