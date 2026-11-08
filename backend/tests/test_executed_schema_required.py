"""Required params come from the nf-core pipeline that RUNS, not the display stub.

The launch gate enforces required_params. chipseq's stub marks input/genome/macs_gsize
required (null defaults); the executed pipeline's nextflow_schema.json requires
fasta/input/outdir — outdir is executor-set, so the user is asked for fasta + input.
"""
import json
import sys
import types
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "backend" / "lib"))

import importlib.util  # noqa: E402

# Load the module file directly: importing the galaxy.ai package pulls in the whole AI stack.
_spec = importlib.util.spec_from_file_location(
    "executed_schema", REPO_ROOT / "backend" / "lib" / "galaxy" / "ai" / "executed_schema.py")
es = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(es)

SCHEMA = {
    "$defs": {
        "input_output_options": {"required": ["input", "outdir"],
                                 "properties": {"input": {"type": "string", "format": "file-path"},
                                                "outdir": {"type": "string"}}},
        "reference_genome_options": {"required": ["fasta"],
                                     "properties": {"fasta": {"type": "string"}, "genome": {"type": "string"}}},
    }
}


def _fake_executor(monkeypatch, resolved):
    mod = types.ModuleType("galaxy.webapps.galaxy.api.nextflow_executor")
    mod._resolve_nextflow_path = lambda f: resolved
    monkeypatch.setitem(sys.modules, "galaxy.webapps.galaxy.api.nextflow_executor", mod)


def test_required_from_executed_schema(tmp_path, monkeypatch):
    d = tmp_path / "nf-core-workflows" / "chipseq"
    d.mkdir(parents=True)
    (d / "main.nf").write_text("workflow {}")
    (d / "nextflow_schema.json").write_text(json.dumps(SCHEMA))
    _fake_executor(monkeypatch, d / "main.nf")
    req, props = es.executed_schema_required("nfcore/chipseq/main.nf")
    assert req == {"input", "fasta"}          # outdir is executor-set
    assert "genome" in props


def test_none_without_real_pipeline_or_schema(tmp_path, monkeypatch):
    stub = tmp_path / "biomni_workflows" / "nfcore" / "x" / "main.nf"
    stub.parent.mkdir(parents=True)
    stub.write_text("workflow {}")
    _fake_executor(monkeypatch, stub)
    assert es.executed_schema_required("nfcore/x/main.nf") is None
    d = tmp_path / "nf-core-workflows" / "noschema"
    d.mkdir(parents=True)
    _fake_executor(monkeypatch, d / "main.nf")
    assert es.executed_schema_required("nfcore/noschema/main.nf") is None
    m = tmp_path / "nf-core-workflows" / "modules" / "biomate-ai-tools" / "y"
    m.mkdir(parents=True)
    (m / "nextflow_schema.json").write_text(json.dumps(SCHEMA))
    _fake_executor(monkeypatch, m / "main.nf")
    assert es.executed_schema_required("y/main.nf") is None


def test_unresolvable_returns_none(monkeypatch):
    mod = types.ModuleType("galaxy.webapps.galaxy.api.nextflow_executor")

    def boom(f):
        raise FileNotFoundError(f)
    mod._resolve_nextflow_path = boom
    monkeypatch.setitem(sys.modules, "galaxy.webapps.galaxy.api.nextflow_executor", mod)
    assert es.executed_schema_required("nfcore/zzz/main.nf") is None


def test_config_param_defaults_top_level_literals():
    cfg = """
params {
  input = null
  add_decoys = false
  decoy_affix = 'DECOY_'
  max_cpus = 16
  fdr = 0.01
  igenomes_base = "s3://ngi-igenomes/igenomes"
  genomes = [:]
  nested {
    inner = 'x'
  }
}
process { cpus = 2 }
"""
    d = es.config_param_defaults(cfg)
    assert d["input"] is None and d["add_decoys"] is False and d["decoy_affix"] == "DECOY_"
    assert d["max_cpus"] == 16 and d["fdr"] == 0.01 and d["igenomes_base"].startswith("s3://")
    assert d["genomes"] is es._UNSET and "inner" not in d and "cpus" not in d


def test_executed_pipeline_params_defaults_and_known(tmp_path, monkeypatch):
    d = tmp_path / "nf-core-workflows" / "proteomicslfq"
    d.mkdir(parents=True)
    (d / "main.nf").write_text("// dsl1")
    (d / "nextflow_schema.json").write_text(json.dumps(SCHEMA))
    (d / "nextflow.config").write_text("params {\n  add_decoys = false\n  fasta = 'x.fa'\n}\n")
    _fake_executor(monkeypatch, d / "main.nf")
    got = es.executed_pipeline_params("nfcore/proteomicslfq/main.nf")
    assert got["defaults"]["add_decoys"] is False and got["defaults"]["fasta"] == "x.fa"
    assert {"add_decoys", "input", "genome"} <= got["known"] and "enable_umi" not in got["known"]


def test_known_includes_params_read_by_pipeline_code(tmp_path, monkeypatch):
    # cageseq 1.0 reads params.input_paths in main.nf and sets it only in conf/test.config —
    # neither its schema nor nextflow.config's params block lists it; it must not be dropped.
    d = tmp_path / "nf-core-workflows" / "cageseq"
    (d / "conf").mkdir(parents=True)
    (d / "main.nf").write_text("if (params.input_paths) { Channel.from(params.input_paths) }\n")
    (d / "conf" / "test.config").write_text("params { input_paths = [] }\n")
    (d / "nextflow_schema.json").write_text(json.dumps(SCHEMA))
    (d / "nextflow.config").write_text("params {\n  fasta = false\n}\n")
    _fake_executor(monkeypatch, d / "main.nf")
    got = es.executed_pipeline_params("nfcore/cageseq/main.nf")
    assert "input_paths" in got["known"] and "fasta" in got["known"] and "enable_umi" not in got["known"]
