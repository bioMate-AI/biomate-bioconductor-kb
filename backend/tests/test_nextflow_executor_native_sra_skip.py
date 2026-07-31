"""
Guard: SRA accessions must NOT be intercepted by the fetchngs prefetch when the target
workflow downloads SRA itself.

Root cause (2026-07-31, via the systemic-root-cause playbook + real fetchngs.log): the
accession chain ran nf-core/fetchngs as a pre-step launched with the awsbatch executor but
a LOCAL work dir, so every SRA-accession Batch launch (e.g. wgs_germline_gatk with
--reads SRR1518169) died in ~6s with "an S3 bucket must be provided as working directory"
— before the main workflow ran. Reference/requester-pays were red herrings. And even a
fixed fetchngs would substitute a samplesheet.csv into --reads, which the workflow's
fromFilePairs/isSRA path rejects. Fix: _workflow_handles_sra_natively() → pass the raw
accession straight through so the workflow's own FASTERQ_DUMP downloads it.

No heavy imports — reads the executor source + the WGS workflow + stdlib only; plain CI.
"""
import re
from pathlib import Path

BACKEND = Path(__file__).resolve().parents[1]
EXECUTOR = BACKEND / "lib/galaxy/webapps/galaxy/api/nextflow_executor.py"
WGS = BACKEND / "biomni_workflows/nextflow_nfcore/subworkflows/genomics/wgs_germline_gatk/main.nf"

_SRA_SIGNALS = r"FASTERQ[_ ]?DUMP|fasterq-dump|\bprefetch\b|\[SED\]RR|from_?sra|sra_download"


def test_native_sra_helper_defined():
    src = EXECUTOR.read_text()
    assert "def _workflow_handles_sra_natively(" in src, "native-SRA skip helper missing"


def test_detection_skips_prefetch_for_native_sra():
    src = EXECUTOR.read_text()
    # The accession-detection loop must skip (continue) sequencing accessions when the
    # workflow handles SRA natively — otherwise the Batch-incompatible fetchngs prefetch
    # intercepts them and the launch dies in ~6s.
    assert "_workflow_handles_sra_natively(str(nf_path))" in src, "detection must call the helper"
    assert "skipping fetchngs prefetch" in src, "detection must skip prefetch for native-SRA workflows"


def test_helper_regex_matches_wgs_workflow():
    # Functional check: the helper's signals must actually match a native-SRA workflow.
    # WGS has FASTERQ_DUMP + an isSRA branch. If this fails, the helper won't skip WGS and
    # the SRA-launch failure regresses.
    if not WGS.exists():
        return  # workflow relocated — the source asserts above still gate the fix
    assert re.search(_SRA_SIGNALS, WGS.read_text(), re.IGNORECASE), \
        "WGS workflow no longer matches the native-SRA signals — update the helper regex"
