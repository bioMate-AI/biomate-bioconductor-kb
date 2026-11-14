"""Regression guards for coldstart Batch G (Bioconductor R container exits).

These checks are intentionally import-light (no Galaxy app / beaker) so they run
on a laptop without the full Galaxy venv. They assert the script + binder source
contracts that closed the R traceback / missing-CSV class.
"""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
BIOC = REPO / "biomni_workflows/nextflow_nfcore/subworkflows/bioconductor"
EXEC = REPO / "lib/galaxy/webapps/galaxy/api/nextflow_executor.py"
ASSIST = REPO / "lib/galaxy/ai/ai_assistant.py"


def test_cox_script_maps_time_aliases_and_numeric():
    text = (BIOC / "survival" / "cox_proportional_hazards_regression.nf").read_text()
    assert "time|month" in text
    assert "clinical_data\\$time <- as.numeric" in text
    assert "patient_id" in text or "patient|" in text


def test_deqms_handles_potential_contaminant_and_hl_contrast():
    text = (BIOC / "deqms" / "maxquant_lfq.nf").read_text()
    assert "Potential.contaminant" in text
    assert "LFQ[._ ]*intensity" in text
    assert '"H", "L"' in text or "'H', 'L'" in text


def test_mageckflute_converts_counts_before_flutera():
    text = (BIOC / "mageckflute" / "main.nf").read_text()
    assert ".counts_to_rra" in text
    assert "incorporateDepmap = FALSE" in text
    assert ".is_counts" in text


def test_multigsea_optional_metabolome_and_abundance_ranks():
    text = (BIOC / "multigsea" / "main.nf").read_text()
    assert ".abundance_to_ranked" in text
    assert "required = FALSE" in text
    assert "tcga" not in text.lower() or "mrna" in text  # role patterns present
    assert '"mrna"' in text or "'mrna'" in text


def test_executor_freestyle_multi_name_staging_present():
    text = EXEC.read_text()
    assert "_ROLE_HINTS" in text
    assert "_freestyle_pool" in text
    assert "tcga_metadata.csv must not become metabolome" in text or "blind-zip" in text
    assert "transcriptome" in text and "proteome" in text


def test_binder_has_bioc_style_a_cues():
    text = ASSIST.read_text()
    assert '"patient_clinical_data"' in text
    assert '"proteinGroups"' in text or '"proteingroups"' in text
    assert "Exact filename match" in text
    assert '"transcriptome"' in text
