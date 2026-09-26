"""Do a quick stub run to make sure things are working"""
import subprocess

import pandas as pd


def test_no_groups(base_project, tmp_path):
    """Test that removing the grouping column still works"""
    config, input_csv, _ = base_project
    pd.read_csv(input_csv).drop(columns="group").to_csv(input_csv, index=False)
    cmd = ["nextflow", "run", "main.nf"] + config
    subprocess.run(cmd, check=True)
    base = tmp_path / "results"

    assert (base / "elib/encyclopedia.quant.elib").exists()


def test_no_aggregate(base_project, tmp_path):
    """Test the workflow logic for per experiment workflows"""
    config, *_ = base_project
    cmd = ["nextflow", "run", "main.nf"] + config
    subprocess.run(cmd, check=True)
    base = tmp_path / "results"
    expected = [
        base / "x" / "elib/encyclopedia.quant.elib",
        base / "y" / "elib/encyclopedia.quant.elib",
        base / "z" / "elib/encyclopedia.quant.elib",
        base / "x" / "elib/encyclopedia.chrlib.elib",
        base / "y" / "elib/encyclopedia.chrlib.elib",
    ]

    for fname in expected:
        assert fname.exists()

    not_expected = base / "agg" / "result-agg.elib"
    assert not not_expected.exists()

    with (base / "z/logs/m.mzML.local.log").open() as log:
        lib_name = log.read().strip()

    assert lib_name == "encyclopedia.chrlib.elib"


def test_aggregate(base_project, tmp_path):
    """Test workflow logic for global analyses."""
    config, *_ = base_project

    cmd = [
        "nextflow",
        "run",
        "main.nf",
        "--aggregate",
        "true",
    ]

    cmd += config

    subprocess.run(cmd, check=True)
    base = tmp_path / "results"
    not_expected = [
        base / "x/elib/encyclopedia.quant.elib",
        base / "y/elib/encyclopedia.quant.elib",
        base / "z/elib/encyclopedia.quant.elib",
    ]

    for fname in not_expected:
        assert not fname.exists()

    expected = base / "aggregated/elib/encyclopedia.quant.elib"
    assert expected.exists()


def test_already_converted(base_project, tmp_path):
    """Test that already converted mzML files are not converted again."""
    mzml_dir = tmp_path / "mzml" / "subdir"
    mzml_dir.mkdir(parents=True)
    mzml = mzml_dir / "a.mzML.gz"
    mzml.touch()
    old = mzml.stat()

    config, *_ = base_project
    cmd = ["nextflow", "run", "main.nf"] + config
    subprocess.run(cmd, check=True)

    assert old == mzml.stat()
    assert (mzml_dir / "b.mzML.gz").exists()


def test_force_convert(base_project, tmp_path):
    """Test that we can force files to be converted again."""
    mzml_dir = tmp_path / "mzml" / "subdir"
    mzml_dir.mkdir(parents=True)
    mzml = mzml_dir / "a.mzML.gz"
    mzml.touch()
    old = mzml.stat()

    config, *_ = base_project
    cmd = ["nextflow", "run", "main.nf", "--msconvert.force", "true"] + config
    subprocess.run(cmd, check=True)

    assert old != mzml.stat()
    assert (mzml_dir / "b.mzML.gz").exists()
