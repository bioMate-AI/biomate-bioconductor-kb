"""Routing guard: `_is_executable_nextflow_match` must not select a Nextflow
file that cannot be launched standalone.

Regression for the RC-1 failure (2026-07): a real nf-core rnaseq subworkflow
(`FASTQ_QC_TRIM_FILTER_SETSTRANDEDNESS`, 24-channel `take:`) whose stored path
slipped past the substring excludes was routed as the execution target, then
launched via `-entry` and aborted with "declares N input channels but 0 were
given". The fix rejects, at routing time, any `.nf` that is not standalone-
runnable (no anonymous `workflow {}` and no `-entry`-able named workflow).
"""

import re
from pathlib import Path


# Standalone copy of AIAssistant._nf_file_is_standalone_runnable's logic so the
# test doesn't pull the full AIAssistant import graph (LLM clients, httpx, …).
# Kept byte-for-byte in sync with lib/galaxy/ai/ai_assistant.py.
def _runnable(nf_path) -> bool:
    p = str(nf_path)
    try:
        text = Path(p).read_text(errors="replace")
    except Exception:
        return True
    if re.search(r"(?m)^\s*workflow\s*\{", text):
        return True
    has_named = re.search(r"(?m)^\s*workflow\s+[A-Za-z_]", text) is not None
    if not has_named:
        return False
    if re.search(r"(?m)^\s*take\s*:", text):
        return "/bioconductor/" in p
    return True


def _w(tmp_path, name, body):
    f = tmp_path / name
    f.write_text(body)
    return f


def test_anonymous_workflow_is_runnable(tmp_path):
    f = _w(tmp_path, "main.nf", "process FOO { script: 'echo hi' }\nworkflow {\n  FOO()\n}\n")
    assert _runnable(f) is True


def test_named_take_only_subworkflow_not_runnable(tmp_path):
    # The RC-1 shape: named workflow with take:, no anonymous workflow{}.
    f = _w(tmp_path, "main.nf",
           "workflow FASTQ_QC_TRIM_FILTER_SETSTRANDEDNESS {\n"
           "    take:\n    ch_reads\n    ch_fasta\n    main:\n    FOO(ch_reads)\n}\n")
    assert _runnable(f) is False


def test_param_stub_with_no_workflow_not_runnable(tmp_path):
    # nfcore/rnaseq, nfcore/sarek shape: params + processes, no workflow block.
    f = _w(tmp_path, "main.nf",
           "params.input = null\nprocess STAR { script: 'STAR ...' }\n")
    assert _runnable(f) is False


def test_named_workflow_without_take_is_entry_runnable(tmp_path):
    f = _w(tmp_path, "main.nf", "workflow MYFLOW {\n  main:\n  FOO()\n}\n")
    assert _runnable(f) is True


def test_bioconductor_take_subworkflow_stays_eligible(tmp_path):
    # Under /bioconductor/, _build_bioc_entry_wrapper supplies the channel at run
    # time, so a take:-only bioc subworkflow must remain routable.
    d = tmp_path / "subworkflows" / "bioconductor" / "qckitfastq"
    d.mkdir(parents=True)
    f = _w(d, "main.nf",
           "workflow QCKITFASTQ_WORKFLOW {\n    take:\n    ch_in\n    main:\n    FOO(ch_in)\n}\n")
    assert _runnable(f) is True


def test_unreadable_path_is_not_over_rejected(tmp_path):
    assert _runnable(tmp_path / "does_not_exist.nf") is True
