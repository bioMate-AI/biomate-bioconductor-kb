"""Executor-owned required data inputs are described, never dropped (docs/20261110 §7.3).

`input` is in _NEXTFLOW_INTERNAL_PARAMS (the executor builds the samplesheet — fetchngs for
accessions, upload wiring for files), so it never becomes an editable param. Before this fix it
also vanished from the workflow definition entirely: chat could not say what nf-core/rnaseq
needs, and the panel listed only the 9 optional reference overrides.
"""
from __future__ import annotations

import json
import sys
import types

if "galaxy.ai.unified_workflow_search" not in sys.modules:
    _uws = types.ModuleType("galaxy.ai.unified_workflow_search")
    _uws.UnifiedWorkflowSearch = type("UnifiedWorkflowSearch", (), {})
    _uws.get_workflow_search = lambda *a, **k: None  # type: ignore[assignment]
    _uws.WorkflowMatch = type("WorkflowMatch", (), {})
    sys.modules["galaxy.ai.unified_workflow_search"] = _uws

from galaxy.ai.ai_assistant import AIAssistant  # noqa: E402

RNASEQ_LIKE_SCHEMA = {
    "$defs": {
        "input_output_options": {
            "title": "Input/output options",
            "required": ["input", "outdir"],
            "properties": {
                "input": {"type": "string", "format": "file-path", "mimetype": "text/csv",
                          "description": "Path to comma-separated file containing information about the samples in the experiment."},
                "outdir": {"type": "string", "format": "directory-path", "description": "The output directory."},
            },
        },
        "reference_genome_options": {
            "title": "Reference genome options",
            "properties": {
                # iGenomes key — string build ID, not a FASTA path. Must surface as an
                # editable param so organism→genome rules and project instructions can fill it.
                "genome": {"type": "string",
                           "description": "Name of iGenomes reference to use (e.g. GRCh38)."},
                "fasta": {"type": "string", "format": "file-path", "description": "Path to FASTA genome file."},
                "gtf": {"type": "string", "format": "file-path", "description": "Path to GTF annotation file."},
            },
        },
    }
}


def _assistant_for(tmp_path):
    (tmp_path / "main.nf").write_text("// stub\n")
    (tmp_path / "nextflow_schema.json").write_text(json.dumps(RNASEQ_LIKE_SCHEMA))
    a = AIAssistant.__new__(AIAssistant)
    a._find_nf_file = lambda _filename: tmp_path / "main.nf"
    return a


def test_required_executor_input_is_described_not_editable(tmp_path):
    parsed = _assistant_for(tmp_path)._parse_nextflow_schema("nfcore/rnaseq/main.nf")
    names = [p["name"] for p in parsed["required"] + parsed["optional"]]
    assert "input" not in names and "outdir" not in names          # still not editable params
    assert [d["name"] for d in parsed["data_inputs"]] == ["input"]   # but the requirement is known
    d = parsed["data_inputs"][0]
    assert d["required"] is True and d["executor_bound"] is True
    assert d["label"] == "Samplesheet (sequencing reads)"
    assert "samples in the experiment" in d["description"]


def test_reference_overrides_stay_optional_and_outdir_is_not_a_data_input(tmp_path):
    parsed = _assistant_for(tmp_path)._parse_nextflow_schema("nfcore/rnaseq/main.nf")
    assert {p["name"] for p in parsed["optional"]} == {"genome", "fasta", "gtf"}
    assert all(d["name"] != "outdir" for d in parsed["data_inputs"])


def test_igenomes_genome_is_string_not_file(tmp_path):
    """genome without format=file-path is the iGenomes key (string), never a file picker."""
    parsed = _assistant_for(tmp_path)._parse_nextflow_schema("nfcore/rnaseq/main.nf")
    genome = next(p for p in parsed["optional"] if p["name"] == "genome")
    assert genome["type"] == "string"
    assert "genome" not in {d["name"] for d in parsed["data_inputs"]}


def test_run_data_detection():
    assert AIAssistant._RUN_DATA_RE.search("SRR1039508")
    assert AIAssistant._RUN_DATA_RE.search("[Uploaded datasets: a.fastq.gz: dataset_id=x]")
    assert AIAssistant._RUN_DATA_RE.search("use GSE52778")
    assert not AIAssistant._RUN_DATA_RE.search("运行 nf-core/rnaseq 工作流。")
