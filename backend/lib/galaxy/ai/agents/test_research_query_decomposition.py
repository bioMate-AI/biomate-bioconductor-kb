"""Regression test for the LitQA2 retrieval-recall fix (query decomposition).

Guards `_build_search_queries` in research_agent.py: a single AND-joined query
under-retrieves the answer-bearing paper on specific questions (measured LitQA2
recall 16.6%); decomposition into complementary queries widens recall. This test
locks in the decomposition contract WITHOUT dragging the heavy galaxy import chain.
"""
import os
import re
import sys
import types


def _load_helper():
    """Import _build_search_queries, stubbing heavy deps; fall back to source-exec."""
    here = os.path.dirname(__file__)
    path = os.path.join(here, "research_agent.py")
    for m in ("galaxy", "galaxy.ai", "galaxy.ai.agents",
              "galaxy.ai.agents.literature_clients", "galaxy.ai.agents.skill_loader"):
        sys.modules.setdefault(m, types.ModuleType(m))
    try:
        import importlib.util
        spec = importlib.util.spec_from_file_location("_ra_test", path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod._build_search_queries
    except Exception:
        src = open(path).read()
        m = re.search(r"def _build_search_queries.*?\n    return queries\[:max_queries\]\n", src, re.S)
        g = {"List": list}
        exec(m.group(0), g)
        return g["_build_search_queries"]


_build_search_queries = _load_helper()


def test_specific_question_decomposes_into_multiple_queries():
    q = "Does TREM2 R47H variant reduce microglial phagocytosis in Alzheimer's mouse models?"
    kt = ["TREM2", "R47H", "microglial phagocytosis", "Alzheimer", "mouse model"]
    out = _build_search_queries(q, kt)
    assert len(out) >= 3, "should widen a specific question into >= 3 complementary queries"
    assert out[0].lower() == " ".join(kt).lower(), "precise joined query must come first"
    assert q in out, "raw natural-language question must be included for semantic recall"
    assert any(len(x.split()) <= 2 for x in out[1:]), "must include narrower pair/singleton sub-queries"
    assert len(out) == len(set(x.lower() for x in out)), "no duplicate queries"


def test_empty_key_terms_falls_back_to_question_only():
    assert _build_search_queries("What is CRISPRi?", []) == ["What is CRISPRi?"]


def test_dedup_when_question_equals_joined_terms():
    out = _build_search_queries("STAR HISAT2", ["STAR", "HISAT2"])
    assert out.count("STAR HISAT2") == 1


def test_query_count_is_capped():
    kt = [f"term{i}" for i in range(20)]
    out = _build_search_queries("q " * 10, kt, max_queries=6)
    assert len(out) <= 6


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            print(f"PASS {name}")
    print("OK")
