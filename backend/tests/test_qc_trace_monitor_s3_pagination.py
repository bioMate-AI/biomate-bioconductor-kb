"""
Smoke test for qc_trace_monitor._read_s3_report_metrics S3 listing pagination.

Regression context (run 193c34ca, 2026-06-15):
  HTS workflow published qc_metrics.json to
    s3://.../03937a9f/hts_run/qc_metrics.json
  but monitor reported "No report found ... at s3://.../03937a9f/qc_metrics.json".
  Cause: single un-paginated list_objects_v2 (1000-key cap). With HTS-scale
  fan-out the step-subdir key sorted past page 1. LNP fit in one page and
  worked, masking the bug.

This test stubs boto3 and verifies the paginator path finds the file when it
only appears on page 2 of the listing.
"""
import json
import sys
import types
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
QC_FILE = ROOT / "lib" / "galaxy" / "jobs" / "qc_trace_monitor.py"


def _load_qc_module():
    import importlib.util
    spec = importlib.util.spec_from_file_location("qc_trace_monitor_under_test", QC_FILE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class _FakePaginator:
    def __init__(self, pages):
        self._pages = pages

    def paginate(self, **_kw):
        for p in self._pages:
            yield p


class _FakeS3:
    def __init__(self, pages, body):
        self._pages = pages
        self._body = body
        self.get_object_calls = []

    def get_paginator(self, name):
        assert name == "list_objects_v2"
        return _FakePaginator(self._pages)

    def get_object(self, Bucket, Key):
        self.get_object_calls.append((Bucket, Key))
        body = types.SimpleNamespace(read=lambda: json.dumps(self._body).encode("utf-8"))
        return {"Body": body}


def _install_fake_boto3(fake):
    mod = types.ModuleType("boto3")
    mod.client = lambda *_a, **_kw: fake
    sys.modules["boto3"] = mod


def _make_monitor(s3_outdir, s3_work_dir=None):
    qm = _load_qc_module()
    inst = qm.NextflowQCGateHandler.__new__(qm.NextflowQCGateHandler)
    inst.s3_outdir = s3_outdir
    inst.s3_work_dir = s3_work_dir
    return inst, qm


def test_finds_qc_metrics_on_paginated_second_page():
    """HTS regression: qc_metrics.json under <run>/hts_run/ on page 2."""
    # Page 1: thousands of per-plate junk that sorts before hts_run/
    page1_keys = [
        {"Key": f"nextflow/outputs/RUN/03937a9f/aplate_{i:04d}/result.csv"}
        for i in range(1000)
    ]
    # Page 2: the qc_metrics file at the step subdir
    page2_keys = [
        {"Key": "nextflow/outputs/RUN/03937a9f/hts_run/qc_metrics.json"},
        {"Key": "nextflow/outputs/RUN/03937a9f/zfinal/report.txt"},
    ]
    pages = [{"Contents": page1_keys}, {"Contents": page2_keys}]
    fake = _FakeS3(pages, {"z_prime": 0.71, "signal_window": 5.3})
    _install_fake_boto3(fake)

    inst, qm = _make_monitor("s3://biomate-nextflow-work/nextflow/outputs/RUN/03937a9f")
    result = inst._read_s3_report_metrics("HTS_PLATE_QC_WORKFLOW:HTS_PLATE_QC_HIT_CALLING (HTS_RUN)")

    assert result is not None, "Should find qc_metrics.json on page 2"
    assert result.get("z_prime") == 0.71
    assert fake.get_object_calls and fake.get_object_calls[0][1].endswith("hts_run/qc_metrics.json")


def test_finds_qc_metrics_at_step_prefix_depth_lnp():
    """LNP-style: qc_metrics.json under <run>/lnp_opt_run/ on page 1."""
    pages = [{"Contents": [
        {"Key": "nextflow/outputs/RUN/e80c4c0b/lnp_opt_run/qc_metrics.json"},
    ]}]
    fake = _FakeS3(pages, {"z_avg_nm": 95.0, "encap_efficiency": 0.92})
    _install_fake_boto3(fake)

    inst, _ = _make_monitor("s3://biomate-nextflow-work/nextflow/outputs/RUN/e80c4c0b")
    result = inst._read_s3_report_metrics("LNP_FORMULATION_OPTIMIZATION")

    assert result is not None
    assert result.get("z_avg_nm") == 95.0


def test_returns_none_when_no_qc_metrics_anywhere():
    pages = [{"Contents": [{"Key": "nextflow/outputs/RUN/x/foo/bar.txt"}]}]
    fake = _FakeS3(pages, {})
    _install_fake_boto3(fake)

    inst, _ = _make_monitor("s3://b/nextflow/outputs/RUN/x")
    assert inst._read_s3_report_metrics("HTS_PLATE_QC_HIT_CALLING") is None


# ---------------------------------------------------------------------------
# _read_s3_workdir_report — work-dir fallback added in 66ae809fa2.
# Locks in the Phase 3c production path: when publishDir is disabled (BioMate
# workflows; see nextflow_executor.py:1893-1936 for the CRT-SIGSEGV guard
# context) qc_metrics.json stays in the per-task work dir at
#   s3://<work-bucket>/nextflow/work/<user>/<run>/<hash[:2]>/<rest>/qc_metrics.json
# and the outdir scan returns None. The fallback method below targets the
# work-dir prefix directly using the process_hash from the Nextflow trace.
# ---------------------------------------------------------------------------


def test_workdir_fallback_finds_qc_metrics_via_abbreviated_hash():
    """Trace hash 'ab/cdef0123abc' → list under work/.../ab/, find the task
    subdir whose name starts with the abbreviated rest."""
    pages = [{"Contents": [
        # Other tasks in the same hash-bucket dir we should ignore
        {"Key": "nextflow/work/u/run/ab/9999fakeother/result.csv"},
        # The matching task dir: name starts with 'cdef0123abc'
        {"Key": "nextflow/work/u/run/ab/cdef0123abcfullhash00000000000000/qc_metrics.json"},
        {"Key": "nextflow/work/u/run/ab/cdef0123abcfullhash00000000000000/some_output.rds"},
    ]}]
    fake = _FakeS3(pages, {
        "success": True, "process": "BIOC_TEST", "domain": "bioconductor",
        "declared_qc_steps": ["missing-value handling"],
        "gates_by_label": {
            "missing-value handling": {
                "gate_row": "bioc_missing_value_handling",
                "metric_name": "na_fraction_remaining",
                "metric_value": 0.02, "passes": True, "status": "computed"
            }
        }
    })
    _install_fake_boto3(fake)

    inst, _ = _make_monitor(
        s3_outdir="s3://b/nextflow/outputs/u/run",
        s3_work_dir="s3://b/nextflow/work/u/run",
    )
    result = inst._read_s3_workdir_report("BIOC_TEST", "ab/cdef0123abc")
    assert result is not None
    # _report_json_to_metrics passthroughs BIOC payloads; gate_row must be
    # present in the returned metrics dict via the harness routing.
    assert fake.get_object_calls
    assert fake.get_object_calls[0][1].endswith(
        "ab/cdef0123abcfullhash00000000000000/qc_metrics.json"
    )


def test_workdir_fallback_skips_non_matching_hash_prefix():
    """Hash 'ab/cdef0123' must not match a sibling task 'ab/9999...'"""
    pages = [{"Contents": [
        {"Key": "nextflow/work/u/run/ab/9999differenthash/qc_metrics.json"},
        {"Key": "nextflow/work/u/run/ab/8888anotherone/qc_metrics.json"},
    ]}]
    fake = _FakeS3(pages, {})
    _install_fake_boto3(fake)
    inst, _ = _make_monitor(
        s3_outdir=None,
        s3_work_dir="s3://b/nextflow/work/u/run",
    )
    assert inst._read_s3_workdir_report("BIOC_TEST", "ab/cdef0123") is None


def test_workdir_fallback_returns_none_when_s3_work_dir_unset():
    fake = _FakeS3([], {})
    _install_fake_boto3(fake)
    inst, _ = _make_monitor(s3_outdir=None, s3_work_dir=None)
    assert inst._read_s3_workdir_report("BIOC_X", "ab/cdef") is None
    # Must short-circuit before any S3 call
    assert fake.get_object_calls == []


def test_workdir_fallback_returns_none_when_hash_lacks_slash():
    """Trace hash without 'prefix/rest' shape should be a hard skip — we
    can't construct the listing prefix without the first-two-chars subdir."""
    fake = _FakeS3([], {})
    _install_fake_boto3(fake)
    inst, _ = _make_monitor(
        s3_outdir=None,
        s3_work_dir="s3://b/nextflow/work/u/run",
    )
    assert inst._read_s3_workdir_report("BIOC_X", "fullhashnopfx") is None
    assert fake.get_object_calls == []


if __name__ == "__main__":
    test_finds_qc_metrics_on_paginated_second_page()
    test_finds_qc_metrics_at_step_prefix_depth_lnp()
    test_returns_none_when_no_qc_metrics_anywhere()
    test_workdir_fallback_finds_qc_metrics_via_abbreviated_hash()
    test_workdir_fallback_skips_non_matching_hash_prefix()
    test_workdir_fallback_returns_none_when_s3_work_dir_unset()
    test_workdir_fallback_returns_none_when_hash_lacks_slash()
    print("OK: all smoke tests passed")
