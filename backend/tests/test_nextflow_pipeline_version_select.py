"""Per-pipeline Nextflow framework selection (_pipeline_nextflow_version).

DSL1 nf-core pipelines (eager 2.x, mnaseseq, proteomicslfq 1.0.0, ...) cannot run on
the default 25.10.5 framework (DSL1 was removed in 22.12), and some catalog-pinned
releases declare `nextflowVersion = '!>=26.04.6'`. The executor launches each on the
framework it needs instead of disabling it; everything else keeps the default pin.
"""
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "backend" / "lib"))

try:
    from galaxy.webapps.galaxy.api import nextflow_executor as ne
except Exception as e:  # pragma: no cover - heavy Galaxy import in some sandboxes
    pytest.skip(f"nextflow_executor not importable: {e}", allow_module_level=True)

DSL2_MAIN = "nextflow.enable.dsl = 2\ninclude { RNASEQ } from './workflows/rnaseq'\nworkflow {\n RNASEQ()\n}\n"
DSL1_MAIN = (
    "#!/usr/bin/env nextflow\n"
    "Channel.fromPath(params.input).set { ch }\n"
    "process FOO {\n input: file x from ch\n script: 'echo'\n}\n"
    "workflow.onComplete {\n log.info 'done'\n}\n"
)


def _pipeline(tmp_path, name, main, cfg=""):
    d = tmp_path / "nf-core-workflows" / name
    d.mkdir(parents=True)
    (d / "main.nf").write_text(main)
    (d / "nextflow.config").write_text(cfg)
    return d / "main.nf"


def test_dsl1_pipeline_gets_22_10_with_dsl1(tmp_path):
    p = _pipeline(tmp_path, "mnaseseq", DSL1_MAIN, "manifest { nextflowVersion = '>=19.10.0' }")
    assert ne._pipeline_nextflow_version(p) == ("22.10.8", True)


def test_explicit_dsl1_flag(tmp_path):
    p = _pipeline(tmp_path, "old", "nextflow.enable.dsl=1\nworkflow {\n}\n")
    assert ne._pipeline_nextflow_version(p) == ("22.10.8", True)


def test_dsl2_default_requirement_keeps_default(tmp_path):
    p = _pipeline(tmp_path, "rnaseq", DSL2_MAIN, "manifest {\n nextflowVersion = '!>=24.04.2'\n}")
    assert ne._pipeline_nextflow_version(p) == ("25.10.5", False)


def test_newer_requirement_gets_supported_version(tmp_path):
    p = _pipeline(tmp_path, "scdownstream", DSL2_MAIN, "manifest {\n nextflowVersion = '!>=26.04.6'\n}")
    assert ne._pipeline_nextflow_version(p) == ("26.04.6", False)
    p2 = _pipeline(tmp_path, "x", DSL2_MAIN, 'manifest { nextflowVersion = "!>=25.11.0" }')
    assert ne._pipeline_nextflow_version(p2) == ("26.04.6", False)


def test_unsupported_requirement_falls_back(tmp_path):
    p = _pipeline(tmp_path, "future", DSL2_MAIN, "manifest { nextflowVersion = '!>=27.0.0' }")
    assert ne._pipeline_nextflow_version(p) == ("25.10.5", False)


def test_non_nfcore_paths_untouched(tmp_path):
    d = tmp_path / "biomni_workflows"
    d.mkdir()
    (d / "x.nf").write_text(DSL1_MAIN)
    assert ne._pipeline_nextflow_version(d / "x.nf") == ("25.10.5", False)


def test_executor_config_pins_matching_nf_amazon(tmp_path):
    compute = {"executor": "awsbatch", "queue": "q", "region": "us-west-2",
               "workDir": "s3://biomate-nextflow-work/test"}
    cases = {
        "mnaseseq": (DSL1_MAIN, "", "nf-amazon@1.11.5"),
        "scdownstream": (DSL2_MAIN, "manifest { nextflowVersion = '!>=26.04.6' }", "nf-amazon@3.9.2"),
        "rnaseq": (DSL2_MAIN, "manifest { nextflowVersion = '!>=24.04.2' }", "nf-amazon@3.4.4"),
    }
    for name, (main, cfg, want) in cases.items():
        p = _pipeline(tmp_path, name, main, cfg)
        out = tmp_path / f"cfg_{name}"
        out.mkdir()
        res = ne._generate_executor_config(
            compute, out, user_id="u", run_id=f"r-{name}", credentials={},
            nf_path=str(p), output_location=None,
        )
        text = Path(res).read_text() if res else ""
        assert want in text, (name, text[:300])


def test_nfcore_pipeline_keeps_its_own_label_sizing(tmp_path):
    # Fixed tiers overrode the pipeline's own check_max(params.max_cpus) caps (mnaseseq test
    # profile: max_cpus=2 -> forced 12 cpus -> TrimGalore --cores 4 -> Python-2 cutadapt abort).
    compute = {"executor": "awsbatch", "queue": "q", "region": "us-west-2",
               "workDir": "s3://biomate-nextflow-work/test"}
    p = _pipeline(tmp_path, "mnaseseq", DSL1_MAIN, "")
    (p.parent / "conf").mkdir()
    (p.parent / "conf" / "base.config").write_text("process { withLabel:process_high { cpus = 12 } }")
    out = tmp_path / "cfg_sizes"
    out.mkdir()
    text = Path(ne._generate_executor_config(
        compute, out, user_id="u", run_id="r-sizes", credentials={},
        nf_path=str(p), output_location=None)).read_text()
    assert "cpus = 12; memory = '72.GB'" not in text
    assert "withLabel: 'process_high'" in text  # queue routing kept
