"""Guard (Bug 2): nf-schema validation failures must be RETRIEVABLE.

Incident (2026-11, nf-core/rnaseq): a run failed with
    ERROR ~ Validation of pipeline parameters failed!
    The following invalid input values have been detected:
      -> Entry 6: Error for field 'fastq_1' (...): the file ... does not exist
but the run record surfaced only the truncated top line — log_tail was empty and
the detail (which samplesheet entry / field failed) was dropped. The log-tail
extractor's err_markers captured the top ERROR line but none of the actionable
nf-schema detail lines. Without the detail the failure is undiagnosable.

This guard asserts the validation detail markers are present so the real cause
reaches the status API.
"""
from __future__ import annotations

from pathlib import Path

EXECUTOR = (
    Path(__file__).resolve().parents[1]
    / "lib" / "galaxy" / "webapps" / "galaxy" / "api" / "nextflow_executor.py"
)

# A representative nf-schema validation error block (verbatim shape from the log).
SAMPLE_ERROR_LINES = [
    "ERROR ~ Validation of pipeline parameters failed!",
    "The following invalid input values have been detected:",
    "* --input (s3://b/airway_samplesheet.csv): Validation of file failed:",
    "\t-> Entry 6: Error for field 'fastq_1' (https://ftp.sra.ebi.ac.uk/a_1.fastq.gz): "
    "the file or directory 'https://ftp.sra.ebi.ac.uk/a_1.fastq.gz' does not exist "
    "(FastQ file for reads 1 must be provided, cannot contain spaces and must have "
    "extension '.fq.gz' or '.fastq.gz')",
]


def _err_markers_from_source() -> list:
    """Extract the err_markers tuple literal from the source without importing.

    Reads from `err_markers = (` to its closing `    )` at column 0+4 (the tuple
    is indented one level inside the function), then pulls every quoted string
    literal. Avoids matching a stray `)` inside a comment.
    """
    import re
    text = EXECUTOR.read_text()
    start = text.index("err_markers = (")
    # The closing paren of the tuple is a line that is exactly 4 spaces + ")".
    m = re.search(r"\n(    \))\n", text[start:])
    assert m, "could not locate the closing paren of the err_markers tuple"
    block = text[start:start + m.start()]
    return re.findall(r'"([^"]+)"', block)


def test_validation_detail_markers_present():
    markers = _err_markers_from_source()
    for needed in (
        "invalid input values",
        "Error for field",
        "-> Entry",
        "does not exist",
        "Validation of file failed",
    ):
        assert needed in markers, (
            f"err_markers is missing {needed!r} — nf-schema validation detail "
            f"lines will be dropped from log_tail and the failure undiagnosable"
        )


def test_sample_error_block_would_be_captured():
    """Every actionable line in a real validation block matches some marker."""
    markers = _err_markers_from_source()
    # The detail lines (not the generic top line) must each hit a marker.
    for line in SAMPLE_ERROR_LINES[1:]:
        assert any(m in line for m in markers), (
            f"validation detail line would be dropped from log_tail: {line[:80]!r}"
        )
