"""Test the MSstats script"""
import subprocess
from pathlib import Path

import pandas as pd
import pytest

from ..msstats_utils import _msstats_input

OUTPUTS = [
    Path("msstats/msstats.input.txt"),
    Path("msstats/msstats.processed.rda"),
    Path("results/msstats.proteins.txt"),
    Path("results/msstats.stats.txt"),
    Path("QCPlot.pdf"),
]


def test_reports(msstats_input, script):
    """Test without reports"""
    peptide_file, protein_file, annot_file, contrast_file = msstats_input
    args = [
        script,
        peptide_file,
        protein_file,
        annot_file,
        contrast_file,
        "equalizeMedians",
        "true",
    ]

    subprocess.run(args, check=True)
    _file_created(*OUTPUTS, exists=True)


def test_no_reports(msstats_input, script):
    """Test without reports"""
    peptide_file, protein_file, annot_file, contrast_file = msstats_input
    args = [
        script,
        peptide_file,
        protein_file,
        annot_file,
        contrast_file,
        "equalizeMedians",
        "false",
    ]

    subprocess.run(args, check=True)
    _file_created(*OUTPUTS[:4], exists=True)
    _file_created(*OUTPUTS[4:], exists=False)


def test_bad_norm(msstats_input, script):
    """Test without reports"""
    peptide_file, protein_file, annot_file, contrast_file = msstats_input
    args = [
        script,
        peptide_file,
        annot_file,
        "NO_FILE",
        "blah",
        "false",
    ]

    with pytest.raises(subprocess.CalledProcessError):
        subprocess.run(args, check=True)


def test_no_contrasts(msstats_input, script):
    """Test without reports"""
    peptide_file, protein_file, annot_file, contrast_file = msstats_input
    args = [
        script,
        peptide_file,
        protein_file,
        annot_file,
        "NO_FILE",
        "equalizeMedians",
        "true",
    ]

    subprocess.run(args, check=True)
    _file_created(*OUTPUTS[:3], OUTPUTS[4], exists=True)
    _file_created(OUTPUTS[3], exists=False)


def test_input(script, msstats_input):
    """Test that the script formats the input correctly."""
    peptide_file, protein_file, annot_file, contrast_file = msstats_input
    args = [
        script,
        peptide_file,
        protein_file,
        annot_file,
        "NO_FILE",
        "none",
        "false",
    ]
    subprocess.run(args, check=True)
    input_df = pd.read_table("msstats/msstats.input.txt")

    assert input_df.shape == (64, 11)
    assert input_df["Run"].tolist() == input_df["BioReplicate"].tolist()

    # Check group merging:
    in_group1 = input_df["Run"].isin(["W", "X"])
    assert (input_df.loc[in_group1, "Condition"] == "C").all()
    assert (input_df.loc[~in_group1, "Condition"] == "D").all()

    # Static fields:
    assert (input_df["PrecursorCharge"] == 2).all()
    assert (input_df["IsotopeLabelType"] == "L").all()
    assert (input_df["FragmentIon"] == "y0").all()
    assert (input_df["ProductCharge"] == 1).all()


def test_input_with_bioreplicate(script, msstats_input):
    """Test the optional specification of BioReplicate"""
    peptide_file, protein_file, annot_file, contrast_file = msstats_input

    # Test annotations with BioReplicates:
    annot_df = pd.read_csv(annot_file)
    annot_df["bioreplicate"] = 1
    annot_df.to_csv(annot_file, index=False)

    args = [
        script,
        peptide_file,
        protein_file,
        annot_file,
        "NO_FILE",
        "none",
        "false",
    ]

    subprocess.run(args, check=True)
    input_df = pd.read_table("msstats/msstats.input.txt")
    assert (input_df["BioReplicate"] == 1).all()


def test_msstats_with_non_r_names(tmp_path, script):
    peps = list("ABCDEFGHIJKLMNOP")  # Peptide Names
    prots = list("AAAAAAAABBBBBBBB")  # Protein Names
    stems = list("WXYZ")  # Raw file names
    conditions = ["c one", "c one", "1c two", "1c two"]  # Conditions to use

    peptide_file, protein_file, input_file, contrast_file = _msstats_input(
        tmp_path=tmp_path, peps=peps, prots=prots, stems=stems, conditions=conditions
    )
    args = [
        script,
        peptide_file,
        protein_file,
        input_file,
        contrast_file,
        "equalizeMedians",
        "true",
    ]

    subprocess.run(args, check=True)
    _file_created(*OUTPUTS, exists=True)

    with open("results/msstats.proteins.txt", "r") as f:
        header = next(iter(f))

    # Tests that the conditin names are kept in the final output
    for c in set(conditions):
        assert c in header, f"'{c}' not in '{header}'"


def _file_created(*args, exists=True):
    """Test whether one or more files exist."""
    for fname in args:
        if exists:
            assert fname.exists(), f"{fname.name} does not exist."
        else:
            assert not fname.exists(), f"{fname.name} exists."


@pytest.fixture
def script(monkeypatch, tmp_path):
    """Set the working directory"""
    (tmp_path / "msstats").mkdir(exist_ok=True)
    (tmp_path / "results").mkdir(exist_ok=True)
    script_path = Path("bin/msstats.R").resolve()
    monkeypatch.syspath_prepend(script_path)
    monkeypatch.chdir(tmp_path)
    return script_path
