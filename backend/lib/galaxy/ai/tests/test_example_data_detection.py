"""A workflow that runs on its own bundled example data is detected from the .nf
definition (docs/20261111 example-data default).

`_detect_example_data` reads the executed .nf and returns a descriptor when the
workflow can run with NO user input because its data inputs resolve to bundled /
built-in example data. The signal is a REAL property of the definition (never a
hard-coded list of workflow names):

  (B) a built-in example/demo DATA fallback keyed on the absence of a data param
      (``def demo = ( !params.x )``, a demo_mode / input_is_demo / demo_used flag,
      a "built-in demo default" block, or a "param-less" quick run); and/or
  (A) a data-input param whose default IS bundled example data — a sample_data /
      test-data file path, or an inline example-values literal.

Fixture snippets below mirror the exact patterns of the seven live cold-start
workflows (metaboanalystr, chipseq-MACS, ATAC, chemoproteomics, WSI, flow
cytometry, EBV) and two genuinely data-required negatives (macsr, flowtime).
"""
from galaxy.ai.ai_assistant import AIAssistant


def _detect(tmp_path, nf_text):
    (tmp_path / "main.nf").write_text(nf_text)
    a = AIAssistant.__new__(AIAssistant)
    a._find_nf_file = lambda _filename: tmp_path / "main.nf"
    return a._detect_example_data("whatever/main.nf")


# ── Signal B: built-in demo DATA fallback keyed on an absent param ────────────

def test_demo_guard_fallback_is_example_data(tmp_path):
    # chipseq / chemoproteomics pattern: downloads REAL public data when no file given.
    nf = (
        "params.chip_seq_file = null\n"
        "params.control_file = null\n"
        "// Built-in demo default (mirrors merfish/metaboanalystr): when no pair is supplied,\n"
        "workflow { def demo = ( !params.chip_seq_file || !params.control_file ) }\n"
    )
    out = _detect(tmp_path, nf)
    assert out and out["present"] is True
    assert out["signals"]["fallback"] is True
    assert "s3://" not in out["note"] and "example dataset" in out["note"]


def test_demo_mode_flag_is_example_data(tmp_path):
    # metaboanalystr pattern: param-less quick run on the human_cachexia demo.
    nf = "params.outdir = './results'\n// param-less quick run\ndemo_mode <- FALSE\n"
    assert _detect(tmp_path, nf)["signals"]["fallback"] is True


def test_input_is_demo_flag_is_example_data(tmp_path):
    # WSI pattern: no --input_wsi supplied -> public OpenSlide demo slide.
    assert _detect(tmp_path, "params.input_wsi = null\ninput_is_demo = False\n")["present"] is True


# ── Signal A: a data param whose default is bundled example data ──────────────

def test_bundled_sample_data_path_default_is_example_data(tmp_path):
    # flow cytometry pattern: fcs_file_path defaults to a bundled sample_data file.
    nf = 'params.fcs_file_path = "${projectDir}/../../sample_data/flow_cytometry/Accuri_C6_A01_H2O.fcs"\n'
    out = _detect(tmp_path, nf)
    assert out and out["signals"]["bundled_default"] is True


def test_inline_example_values_default_is_example_data(tmp_path):
    # EBV pattern: raw_od_data defaults to inline ELISA OD readings.
    nf = 'params.raw_od_data = \'{"sample1": {"VCA_IgG": 0.85}}\'\n'
    out = _detect(tmp_path, nf)
    assert out and out["signals"]["inline_default"] is True


# ── Negatives: genuinely data-required workflows are NOT example-data ─────────

def test_null_data_param_without_fallback_is_not_example_data(tmp_path):
    # macsr / flowtime pattern: a required data file, no demo fallback, no default.
    nf = "params.CHIP = null\nparams.CTRL = null\nworkflow { Channel.fromPath(params.CHIP) }\n"
    assert _detect(tmp_path, nf) is None


def test_reference_default_is_not_mistaken_for_example_data(tmp_path):
    # A genome-size setting default (not a data file / inline data literal) must not trip it.
    nf = "params.input = null\nparams.genome_size = 'hs'\nparams.q_value = '0.05'\n"
    assert _detect(tmp_path, nf) is None


def test_missing_file_returns_none(tmp_path):
    a = AIAssistant.__new__(AIAssistant)
    a._find_nf_file = lambda _f: None
    assert a._detect_example_data("nope/main.nf") is None
