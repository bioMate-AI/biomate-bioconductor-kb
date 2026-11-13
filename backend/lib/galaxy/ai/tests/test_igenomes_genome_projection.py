"""iGenomes `genome` must surface on workflow_ga and accept organism→GRCh38 rules.

Root cause (2026-11-13): `_NEXTFLOW_INTERNAL_PARAMS` hid `genome`, so nf-core/rnaseq
never exposed the slot; rule-based human→GRCh38 and project-rule obedience could only
appear in reply prose. See docs/20261113_IGENOME_GENOME_PARAM_PROJECTION.md.
"""
from __future__ import annotations

import sys
import types
from pathlib import Path

# Avoid sentence_transformers / sklearn on developer laptops (scipy ABI mismatch).
if "sentence_transformers" not in sys.modules:
    _st = types.ModuleType("sentence_transformers")
    _st.SentenceTransformer = type("SentenceTransformer", (), {})
    sys.modules["sentence_transformers"] = _st
if "galaxy.ai.unified_workflow_search" not in sys.modules:
    _uws = types.ModuleType("galaxy.ai.unified_workflow_search")
    _uws.UnifiedWorkflowSearch = type("UnifiedWorkflowSearch", (), {})
    _uws.get_workflow_search = lambda *a, **k: None  # type: ignore[assignment]
    _uws.WorkflowMatch = type("WorkflowMatch", (), {})
    sys.modules["galaxy.ai.unified_workflow_search"] = _uws

from galaxy.ai.ai_assistant import AIAssistant  # noqa: E402


def _assistant_for_nf(tmp_path: Path, nf_text: str) -> AIAssistant:
    (tmp_path / "main.nf").write_text(nf_text)
    a = AIAssistant.__new__(AIAssistant)
    a._find_nf_file = lambda _filename: tmp_path / "main.nf"
    return a


RNASEQ_STUB_NF = """\
params.input            = null          // Samplesheet CSV
params.genome           = null          // Reference genome: GRCh38 | GRCm39 | GRCz11
params.strandedness     = 'auto'        // reverse | forward | unstranded | auto
params.aligner          = 'star_salmon' // star_salmon | hisat2
params.single_end       = false         // Single-end library
params.outdir           = './results'

process STAR_ALIGN {
    script: \"\"\"
    STAR --genome ${params.genome}
    \"\"\"
}
"""


def test_nf_stub_surfaces_genome_not_input_or_outdir(tmp_path):
    parsed = _assistant_for_nf(tmp_path, RNASEQ_STUB_NF)._parse_nextflow_params("nfcore/rnaseq/main.nf")
    names = {p["name"] for p in parsed["required"] + parsed["optional"]}
    assert "genome" in names
    assert "aligner" in names
    assert "input" not in names
    assert "outdir" not in names
    assert [d["name"] for d in parsed.get("data_inputs", [])] == ["input"]
    genome = next(p for p in parsed["required"] + parsed["optional"] if p["name"] == "genome")
    assert genome["type"] in ("string", "select")
    assert genome["type"] != "file"


def test_genome_not_in_internal_params():
    assert "genome" not in AIAssistant._NEXTFLOW_INTERNAL_PARAMS
    assert "input" in AIAssistant._NEXTFLOW_INTERNAL_PARAMS


def test_extract_genome_build_human_and_explicit():
    a = AIAssistant.__new__(AIAssistant)
    assert a._extract_genome_build("RNA-seq for my human paired-end samples") == "GRCh38"
    assert a._extract_genome_build("align to GRCh38") == "GRCh38"
    assert a._extract_genome_build("use hg38 reference") == "GRCh38"
    assert a._extract_genome_build("mouse scRNA-seq") == "GRCm39"
    assert a._extract_genome_build("Always use the GRCh38 human reference genome") == "GRCh38"


def test_inject_genome_prefills_select_enum(tmp_path):
    a = _assistant_for_nf(tmp_path, RNASEQ_STUB_NF)
    parsed = a._parse_nextflow_params("nfcore/rnaseq/main.nf")
    req, opt = a._inject_genome_into_params(parsed["required"], parsed["optional"], "GRCh38")
    genome = next(p for p in req + opt if p["name"] == "genome")
    assert genome["default"] == "GRCh38"
    assert genome["value"] == "GRCh38"
    assert genome.get("genome_auto") is True
