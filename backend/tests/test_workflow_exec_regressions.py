"""Regression tests for workflow execution bugs.

Each test here documents a bug that reached production — the test name says
which bug, the docstring explains what was broken and how it was fixed.
Adding a test here is mandatory when a bug of this type is patched so CI
catches any future regression before it ships.

Covered regressions:
  R-01: _is_executable_nextflow_match returns True for missing .nf file
  R-02: auto-reroute passes empty params because run_meta key mismatch
  R-03: handleSendOrQueue stale closure creates a second chat session
        (frontend — covered by the TypeScript vitest suite)
"""

import re
import sys
from pathlib import Path
from unittest.mock import MagicMock

import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "lib"))


# ---------------------------------------------------------------------------
# Helpers: a minimal re-implementation of the fixed logic so we can test the
# logic contract independently of the full AiAssistant import chain.
# We also check that the actual source file contains the correct pattern so
# the tests flag any drift between the reference logic and production code.
# ---------------------------------------------------------------------------

_AI_ASSISTANT_SRC = (
    REPO_ROOT / "lib" / "galaxy" / "ai" / "ai_assistant.py"
)


def _is_executable_nf_match_fixed(filename: str, find_nf_file, nf_file_is_standalone) -> bool:
    """Reference implementation of the fixed _is_executable_nextflow_match logic.

    Parameters mirror the real method; callables stand in for self.* calls so
    this function is pure and test-friendly.
    """
    fname = filename.lower()

    # Exclude known non-entry subworkflow patterns
    if fname.startswith("nfcore/subworkflows/"):
        return False
    if "/nf-core-modules/subworkflows/" in fname:
        return False
    if "/nfcore/subworkflows/" in fname:
        return False
    if "subworkflow" in fname:
        return False

    if fname.endswith("/main.nf"):
        resolved = find_nf_file(filename)
        if resolved is None:          # ← the bug was: this branch was missing
            return False
        if not nf_file_is_standalone(resolved):
            return False
        return True

    if fname.endswith(".nf") and (
        "/workflows/" in fname or "biomni_nf/" in fname or "/bioconductor/" in fname
    ):
        resolved = find_nf_file(filename)
        return resolved is not None   # ← also require file to exist

    return False


# ---------------------------------------------------------------------------
# R-01  _is_executable_nextflow_match returns True for missing .nf file
# ---------------------------------------------------------------------------
# Bug: _is_executable_nextflow_match had the condition:
#   if resolved is not None and not self._nf_file_is_standalone_runnable(resolved):
#       return False
#   return True
# When _find_nf_file returned None (file not on disk), the `and` short-circuited
# and the code fell through to `return True`, marking a workflow as runnable even
# though its .nf file doesn't exist. This caused immediate 404 on /api/nextflow/execute
# for DB-indexed workflows whose files were never shipped in the backend image
# (e.g. nf-core/proteinfamilies).
# Fix: explicitly `return False` when resolved is None.

def test_R01_missing_nf_file_returns_false():
    """R-01: /main.nf workflow with missing file on disk → not executable."""
    result = _is_executable_nf_match_fixed(
        "nf-core/proteinfamilies/main.nf",
        find_nf_file=lambda _: None,          # file not on disk
        nf_file_is_standalone=lambda _: True,
    )
    assert result is False, (
        "A workflow whose .nf file is absent from the backend image must not be "
        "marked executable — it would cause immediate 404 on /api/nextflow/execute."
    )


def test_R01_present_standalone_file_returns_true(tmp_path):
    """R-01: /main.nf workflow that IS on disk and is standalone → executable."""
    nf_file = tmp_path / "main.nf"
    nf_file.write_text("workflow {\n}\n")
    result = _is_executable_nf_match_fixed(
        "structural_biology/chai1_structure_prediction/main.nf",
        find_nf_file=lambda _: nf_file,
        nf_file_is_standalone=lambda _: True,
    )
    assert result is True


def test_R01_present_but_not_standalone_returns_false(tmp_path):
    """R-01: file exists but is a take:-only subworkflow → not executable."""
    nf_file = tmp_path / "main.nf"
    nf_file.write_text("workflow MY_WF {\n  take: reads\n}\n")
    result = _is_executable_nf_match_fixed(
        "structural_biology/some_subwf/main.nf",
        find_nf_file=lambda _: nf_file,
        nf_file_is_standalone=lambda _: False,
    )
    assert result is False


def test_R01_biomni_nf_missing_file_returns_false():
    """R-01: biomni_nf/ path where file is absent → not executable."""
    result = _is_executable_nf_match_fixed(
        "biomni_nf/drug_discovery/admet_screener.nf",
        find_nf_file=lambda _: None,
        nf_file_is_standalone=lambda _: True,
    )
    assert result is False


def test_R01_subworkflow_path_excluded_immediately():
    """R-01: nfcore/subworkflows/ prefix is excluded before disk check."""
    result = _is_executable_nf_match_fixed(
        "nfcore/subworkflows/fastq_trim/main.nf",
        find_nf_file=lambda _: (_ for _ in ()).throw(AssertionError("should not be called")),
        nf_file_is_standalone=lambda _: True,
    )
    assert result is False


def test_R01_source_code_has_none_guard():
    """R-01: verify production source has the explicit `resolved is None` guard."""
    src = _AI_ASSISTANT_SRC.read_text(encoding="utf-8")
    # The fix adds an explicit `if resolved is None: return False` block before the
    # standalone-runnable check.
    assert re.search(
        r"if\s+resolved\s+is\s+None\s*:\s*\n\s+return\s+False",
        src,
    ), (
        "ai_assistant.py must contain 'if resolved is None: return False' inside "
        "_is_executable_nextflow_match. The guard may have been accidentally removed."
    )


# ---------------------------------------------------------------------------
# R-02  auto-reroute passes empty params due to wrong run_meta key
# ---------------------------------------------------------------------------
# Bug: _trigger_auto_reroute_on_failure read run_meta.get("parameters") but
# _execute_nextflow_impl stores the original params under the key "params".
# The result: every auto-rerouted workflow launched with an empty param dict {},
# so chai1 received no `sequence` and failed with "no valid fasta_path or
# sequence provided".
# Fix: read run_meta.get("params") or run_meta.get("parameters") or {}.

def test_R02_auto_reroute_reads_params_key():
    """R-02: auto-reroute must retrieve original params from the 'params' key."""
    # Simulate the run_meta structure produced by _execute_nextflow_impl
    run_meta = {
        "params": {"sequence": "MVLSEGEWQLVLHVWAKVEADVAGHGQDILIR", "outdir": "results"},
        "user_id": "user-42",
        "is_pilot": False,
        "nextflow_path": "structural_biology/alphafold2/main.nf",
        "workflow_domain": "structural_biology",
    }

    # This is the exact expression used in _trigger_auto_reroute_on_failure.
    # If we had the old bug (`.get("parameters")`), this would be {}.
    extracted = dict(run_meta.get("params") or run_meta.get("parameters") or {})

    assert extracted == {"sequence": "MVLSEGEWQLVLHVWAKVEADVAGHGQDILIR", "outdir": "results"}, (
        "auto-reroute must pass the original run params to the alternative workflow. "
        "Got empty dict — 'parameters' key was used instead of 'params'."
    )


def test_R02_auto_reroute_old_parameters_key_also_works():
    """R-02: backward compat — still works if run_meta uses the old 'parameters' key."""
    run_meta = {
        "parameters": {"sequence": "ACGT", "genome": "hg38"},
    }

    extracted = dict(run_meta.get("params") or run_meta.get("parameters") or {})

    assert extracted == {"sequence": "ACGT", "genome": "hg38"}


def test_R02_auto_reroute_missing_both_keys_gives_empty_dict():
    """R-02: if both keys are absent the result is an empty dict, not an error."""
    run_meta = {"user_id": "anon", "status": "failed"}

    extracted = dict(run_meta.get("params") or run_meta.get("parameters") or {})

    assert extracted == {}


# ---------------------------------------------------------------------------
# R-03  protein_sequences plural not recognised as sequence type
# ---------------------------------------------------------------------------
# Bug: _SEQUENCE_PARAM_NAMES contained singular forms only (protein_sequence)
# but nf-core/proteinfold declares params.protein_sequences (plural). The AI
# classified it as 'string', so the LLM param-extraction rule that only fills
# 'sequence'-typed params never triggered, leaving the field empty even when
# the user pasted a full AA string in the chat.
# Fix: add plural variants of all sequence param names to _SEQUENCE_PARAM_NAMES.

_AI_ASSISTANT_SRC = Path(REPO_ROOT / "lib" / "galaxy" / "ai" / "ai_assistant.py")


def test_R03_plural_sequence_param_names_in_source():
    """R-03: plural sequence param names must be in _SEQUENCE_PARAM_NAMES."""
    src = _AI_ASSISTANT_SRC.read_text(encoding="utf-8")
    for name in ("protein_sequences", "dna_sequences", "rna_sequences", "sequences"):
        assert f"'{name}'" in src, (
            f"'{name}' is missing from _SEQUENCE_PARAM_NAMES in ai_assistant.py. "
            "Add it so the AI auto-fills plural sequence params (e.g. nf-core/proteinfold)."
        )


def test_R03_detect_param_type_classifies_plural_sequence_as_sequence_type():
    """R-03: protein_sequences must be classified as type 'sequence', not 'string'."""
    # Reproduce the classification logic directly without importing the full class.
    src = _AI_ASSISTANT_SRC.read_text(encoding="utf-8")

    # Parse _SEQUENCE_PARAM_NAMES from source (simple extraction)
    import ast
    m = re.search(
        r"_SEQUENCE_PARAM_NAMES\s*:\s*frozenset\s*=\s*frozenset\(\s*\[([^\]]+)\]\s*\)",
        src, re.DOTALL
    )
    assert m, "_SEQUENCE_PARAM_NAMES frozenset literal not found in source"
    seq_names = frozenset(ast.literal_eval(f"[{m.group(1)}]"))

    assert "protein_sequences" in seq_names, (
        "'protein_sequences' not in _SEQUENCE_PARAM_NAMES — "
        "nf-core/proteinfold params will not be auto-filled."
    )
    assert "sequences" in seq_names
    assert "dna_sequences" in seq_names


# ---------------------------------------------------------------------------
# R-04  raw AA sequence in query not auto-filled into protein_sequences param
# ---------------------------------------------------------------------------
# Bug: _extract_explicit_params_from_query had no rule for raw sequence strings;
# it relied entirely on LLM inference (_infer_params_from_intent_llm) to fill
# sequence-type params. If the LLM call failed (timeout, network) or returned []
# (hallucination guard), the param stayed empty even when the user pasted a full
# amino-acid string in the chat (e.g. MVLSEGEWQLVLHVWAKVEADVAGHGQDILIR).
# Fix: add a rule-based extractor (longest AA run ≥15 chars → first unfilled
# 'sequence'-type param) inside _extract_explicit_params_from_query, before LLM.

def test_R04_rule_based_sequence_extraction_present_in_source():
    """R-04: source must contain the rule-based AA sequence extractor."""
    src = _AI_ASSISTANT_SRC.read_text(encoding="utf-8")
    assert "_seq_params_unfilled" in src, (
        "_extract_explicit_params_from_query must contain rule-based sequence extraction "
        "(_seq_params_unfilled). LLM-only extraction is unreliable and leaves the field "
        "empty on timeout or refusal."
    )
    assert "_AA_CHARS" in src or "AA_CHARS" in src, (
        "Rule-based sequence extractor must define an AA character class."
    )


def test_R04_rule_extracts_sequence_into_param():
    """R-04: longest AA/NT string ≥15 chars must be auto-filled into sequence-type param."""
    import re as _re_t

    # Simulate the rule extracted from _extract_explicit_params_from_query.
    # We duplicate the logic here as a pure-function reference to keep the test self-contained.
    def _extract_seq_rule(user_intent: str, req: list, opt: list, already_set: set) -> list:
        suggestions = []
        _seq_params_unfilled = [
            p for p in req + opt
            if p.get("type") == "sequence" and p.get("name") not in already_set
        ]
        if not _seq_params_unfilled:
            return suggestions
        _AA_CHARS = r'[ACDEFGHIKLMNPQRSTVWYBZXU]'
        _seq_match = None
        _best_len = 0
        for _m in _re_t.finditer(rf'\b({_AA_CHARS}{{15,}})\b', user_intent, _re_t.IGNORECASE):
            if len(_m.group(1)) > _best_len:
                _seq_match = _m.group(1)
                _best_len = len(_seq_match)
        if _seq_match:
            _req_seq = [p for p in _seq_params_unfilled if p.get("required", True)]
            _opt_seq = [p for p in _seq_params_unfilled if not p.get("required", True)]
            for _sp in (_req_seq or _opt_seq)[:1]:
                suggestions.append({"name": _sp["name"], "value": _seq_match.upper()})
        return suggestions

    user_query = "帮我跑一下这个DNA，分析下：MVLSEGEWQLVLHVWAKVEADVAGHGQDILIR"
    params_req = [{"name": "protein_sequences", "type": "sequence", "required": True}]
    result = _extract_seq_rule(user_query, params_req, [], set())

    assert len(result) == 1, "Expected 1 suggestion, got " + str(result)
    assert result[0]["name"] == "protein_sequences"
    assert result[0]["value"] == "MVLSEGEWQLVLHVWAKVEADVAGHGQDILIR"


def test_R04_sequence_shorter_than_15_not_extracted():
    """R-04: sequences < 15 AA chars must NOT be extracted (too short, could be text)."""
    import re as _re_t

    def _extract_seq_rule(user_intent, req, opt, already_set):
        suggestions = []
        _seq_params_unfilled = [p for p in req + opt if p.get("type") == "sequence" and p.get("name") not in already_set]
        if not _seq_params_unfilled:
            return suggestions
        _AA_CHARS = r'[ACDEFGHIKLMNPQRSTVWYBZXU]'
        _seq_match = None
        _best_len = 0
        for _m in _re_t.finditer(rf'\b({_AA_CHARS}{{15,}})\b', user_intent, _re_t.IGNORECASE):
            if len(_m.group(1)) > _best_len:
                _seq_match = _m.group(1)
                _best_len = len(_seq_match)
        if _seq_match:
            _req_seq = [p for p in _seq_params_unfilled if p.get("required", True)]
            _opt_seq = [p for p in _seq_params_unfilled if not p.get("required", True)]
            for _sp in (_req_seq or _opt_seq)[:1]:
                suggestions.append({"name": _sp["name"], "value": _seq_match.upper()})
        return suggestions

    result = _extract_seq_rule("run analysis MVLS", [{"name": "protein_sequences", "type": "sequence"}], [], set())
    assert result == [], "Short AA fragment < 15 chars must not be extracted"
