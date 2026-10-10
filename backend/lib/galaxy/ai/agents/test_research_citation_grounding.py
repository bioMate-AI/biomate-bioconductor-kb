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
