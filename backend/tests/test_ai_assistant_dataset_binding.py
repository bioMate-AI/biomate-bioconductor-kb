"""Regression tests for deterministic session-upload binding.

These tests cover the no-LLM path used when a user supplies count matrix and
sample metadata files for differential abundance.
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))

from galaxy.ai.ai_assistant import AIAssistant


def _assistant_without_init():
    """The binding helpers do not need a Galaxy app or external services."""
    return object.__new__(AIAssistant)


def test_differential_expression_uploads_bind_by_filename():
    assistant = _assistant_without_init()
    required = [
        {"name": "samplesheet", "type": "file", "default": None},
        {"name": "matrix", "type": "file", "default": None},
    ]
    optional = [{"name": "contrasts", "type": "file", "default": None}]
    uploaded = [
        {"name": "counts_matrix.csv", "s3_uri": "s3://uploads/counts_matrix.csv"},
        {"name": "sample_metadata.csv", "s3_uri": "s3://uploads/sample_metadata.csv"},
        {"name": "contrasts.csv", "s3_uri": "s3://uploads/contrasts.csv"},
    ]

    required, optional = assistant._bind_uploaded_datasets_to_params(required, optional, uploaded)
    values = {p["name"]: p["value"] for p in required + optional}

    assert values == {
        "samplesheet": "s3://uploads/sample_metadata.csv",
        "matrix": "s3://uploads/counts_matrix.csv",
        "contrasts": "s3://uploads/contrasts.csv",
    }
    assert assistant._build_prereq_validation(required) is None


def test_unrelated_upload_is_not_bound_to_a_semantic_de_input():
    assistant = _assistant_without_init()
    required = [{"name": "matrix", "type": "file", "default": None}]
    bound, _ = assistant._bind_uploaded_datasets_to_params(
        required,
        [],
        [{"name": "clinical_notes.pdf", "s3_uri": "s3://uploads/notes.pdf"}],
    )

    assert bound[0].get("value") is None
    assert assistant._build_prereq_validation(bound) is not None


def test_de_input_names_are_file_parameters():
    assistant = _assistant_without_init()
    assert assistant._detect_param_type("matrix", "") == "file"
    assert assistant._detect_param_type("samplesheet", "") == "file"
    assert assistant._detect_param_type("contrasts", "") == "file"
