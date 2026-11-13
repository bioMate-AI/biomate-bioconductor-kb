"""Step 1 of the 2026-11-12 example-routing fix: the SHAPE of the user's attached data must
reach workflow search on BOTH the chat/agent path and the decomposed-chain per-step path.

Before this, data_perception typed the 4 incident files to {molecules, structure} but that signal
never reached scoring: the chat path called generate_workflow_unified WITHOUT user_input_kinds
(ai_assistant.py:696) and the chain path searched each step's prose with no datasets at all
(_resolve_task_to_workflow → search(desc), ai_assistant.py:917). These tests pin the plumbing.
"""
import asyncio

from galaxy.ai.ai_assistant import AIAssistant

# The four files from the incident transcript.
DATASETS = [
    {"name": "candidate_library.csv"},
    {"name": "1IEP.pdb"},
    {"name": "pilot_reference_actives.smi"},
    {"name": "pilot_target_info.json"},
]


def _assistant():
    # Build without __init__ (which needs config + a real workflow DB); these tests exercise
    # only the perception/threading plumbing with stubbed search + generation.
    return AIAssistant.__new__(AIAssistant)


def test_perceive_user_input_kinds_from_attached_files():
    kinds = _assistant()._perceive_user_input_kinds({"datasets": DATASETS})
    assert kinds is not None
    assert "structure" in kinds    # 1IEP.pdb → structure (auxiliary)
    assert "molecules" in kinds    # pilot_reference_actives.smi → molecules (auxiliary)


def test_perceive_is_none_safe_without_datasets():
    a = _assistant()
    assert a._perceive_user_input_kinds({}) in (None, [])
    assert a._perceive_user_input_kinds(None) in (None, [])


def test_chat_intent_path_threads_kinds_into_generation():
    a = _assistant()
    captured = {}

    def _gen(user_intent, uploaded_datasets=None, user_input_kinds=None, **kw):
        captured["user_input_kinds"] = user_input_kinds
        captured["uploaded_datasets"] = uploaded_datasets
        return {"success": True, "workflow_ga": {}, "source": "s", "confidence": 1.0, "message": "m"}

    a.generate_workflow_unified = _gen
    asyncio.run(a._handle_workflow_generation(
        "Rank these 500 candidates for developability and show me the top 20.",
        {"datasets": DATASETS},
    ))
    assert "structure" in (captured["user_input_kinds"] or [])
    assert "molecules" in (captured["user_input_kinds"] or [])
    # And the datasets are forwarded under the correct kwarg (the old call used a
    # non-existent `available_datasets=` kwarg).
    assert captured["uploaded_datasets"] == DATASETS


def test_chain_step_resolution_threads_kinds_into_search():
    a = _assistant()
    captured = {}

    class _Search:
        def search(self, desc, user_input_kinds=None, **kw):
            captured["desc"] = desc
            captured["user_input_kinds"] = user_input_kinds
            return []  # pick_workflow_match([]) → None (fine: we assert the plumbing only)

    a.workflow_search = _Search()
    a._resolve_task_to_workflow(
        {"description": "rank the candidates by developability"},
        user_input_kinds=["molecules", "structure"],
    )
    assert captured["user_input_kinds"] == ["molecules", "structure"]
