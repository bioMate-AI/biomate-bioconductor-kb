"""
Self-contained integration test for cro_order_export and commercial_availability.

Run from the repo root:
    python backend/lib/galaxy/ai/drug_discovery/test_cro_commercial.py
"""
import os
import sys
import json
import tempfile
import traceback

# ---------------------------------------------------------------------------
# Make the package importable regardless of PYTHONPATH
# ---------------------------------------------------------------------------
_HERE = os.path.dirname(os.path.abspath(__file__))
_BACKEND_LIB = os.path.normpath(os.path.join(_HERE, "..", "..", ".."))
if _BACKEND_LIB not in sys.path:
    sys.path.insert(0, _BACKEND_LIB)

from galaxy.ai.drug_discovery.cro_order_export import (
    CompoundOrderEntry,
    CROOrderExporter,
)
from galaxy.ai.drug_discovery.commercial_availability import (
    CommercialAvailabilityChecker,
)

# ---------------------------------------------------------------------------
# Shared test fixtures
# ---------------------------------------------------------------------------

EXAMPLE_COMPOUNDS = [
    CompoundOrderEntry(
        compound_id="BM-001",
        smiles="CC(=O)Oc1ccccc1C(=O)O",      # Aspirin
        priority_rank=1,
        requested_quantity_mg=50.0,
        scientific_rationale="COX inhibitor; strong docking score in PTGS2 pocket.",
        admet_flags=[],
        purity_spec_percent=99.0,
        docking_score=-8.4,
        assay_context="IC50 assay vs PTGS2",
    ),
    CompoundOrderEntry(
        compound_id="BM-002",
        smiles="CN1C=NC2=C1C(=O)N(C(=O)N2C)C",  # Caffeine
        priority_rank=2,
        requested_quantity_mg=25.0,
        scientific_rationale="Adenosine receptor antagonist; favourable LogP.",
        admet_flags=["hERG_risk"],
        purity_spec_percent=95.0,
        docking_score=-7.1,
        assay_context="Selectivity panel",
    ),
    CompoundOrderEntry(
        compound_id="BM-003",
        smiles="c1ccc2c(c1)cc1ccc3cccc4ccc2c1c34",  # Pyrene
        priority_rank=3,
        requested_quantity_mg=10.0,
        scientific_rationale="Scaffold hopping candidate; moderate hydrophobicity.",
        admet_flags=["DILI_flag"],
        purity_spec_percent=95.0,
        docking_score=-6.9,
    ),
    CompoundOrderEntry(
        compound_id="BM-004",
        smiles="OC(=O)c1ccccc1",               # Benzoic acid
        priority_rank=4,
        requested_quantity_mg=100.0,
        scientific_rationale="Fragment anchor; low MW, ideal for FBDD growth.",
        admet_flags=[],
        purity_spec_percent=97.0,
        docking_score=-5.3,
    ),
    CompoundOrderEntry(
        compound_id="BM-005",
        smiles="Nc1ccc(S(=O)(=O)Nc2ccccn2)cc1",  # Sulfadiazine
        priority_rank=5,
        requested_quantity_mg=30.0,
        scientific_rationale="DHPS inhibitor; confirmed antibacterial mechanism.",
        admet_flags=[],
        purity_spec_percent=98.0,
        docking_score=-9.1,
        assay_context="MIC assay vs E. coli",
    ),
]

# ---------------------------------------------------------------------------
# Test helpers
# ---------------------------------------------------------------------------

_results: list[tuple[str, bool, str]] = []


def run_test(name: str, fn) -> bool:
    try:
        fn()
        _results.append((name, True, ""))
        return True
    except Exception:
        _results.append((name, False, traceback.format_exc()))
        return False


def assert_true(condition: bool, message: str = "") -> None:
    if not condition:
        raise AssertionError(message or "Assertion failed")


def assert_file_exists(path: str) -> None:
    assert_true(os.path.isfile(path), f"Expected file not found: {path}")


def assert_file_nonempty(path: str) -> None:
    assert_file_exists(path)
    assert_true(os.path.getsize(path) > 0, f"File is empty: {path}")


# ---------------------------------------------------------------------------
# CROOrderExporter tests
# ---------------------------------------------------------------------------

def _build_exporter(output_dir: str) -> CROOrderExporter:
    exporter = CROOrderExporter(campaign_id="TEST-CAMPAIGN-001", output_dir=output_dir)
    for entry in EXAMPLE_COMPOUNDS:
        exporter.add_compound(entry)
    return exporter


def test_wuxi_csv(output_dir: str) -> None:
    exporter = _build_exporter(output_dir)
    path = exporter.export_wuxi_csv()
    assert_file_nonempty(path)
    with open(path, encoding="utf-8") as f:
        header = f.readline()
    assert_true("Compound_ID" in header, "WuXi CSV missing Compound_ID column")
    assert_true("SMILES" in header, "WuXi CSV missing SMILES column")
    assert_true("Scientific_Rationale" in header, "WuXi CSV missing Scientific_Rationale")


def test_pharmaron_csv(output_dir: str) -> None:
    exporter = _build_exporter(output_dir)
    path = exporter.export_pharmaron_csv()
    assert_file_nonempty(path)
    with open(path, encoding="utf-8") as f:
        header = f.readline()
    assert_true("MW_estimate" in header, "Pharmaron CSV missing MW_estimate column")
    assert_true("Purity_Requirement" in header, "Pharmaron CSV missing Purity_Requirement")


def test_enamine_csv(output_dir: str) -> None:
    exporter = _build_exporter(output_dir)
    path = exporter.export_enamine_csv()
    assert_file_nonempty(path)
    with open(path, encoding="utf-8") as f:
        header = f.readline()
    assert_true("SMILES" in header, "Enamine CSV missing SMILES column")
    assert_true("Catalog_ID" in header, "Enamine CSV missing Catalog_ID column")
    assert_true("Amount_mg" in header, "Enamine CSV missing Amount_mg column")


def test_scientific_summary(output_dir: str) -> None:
    exporter = _build_exporter(output_dir)
    path = exporter.export_scientific_summary()
    assert_file_nonempty(path)
    with open(path, encoding="utf-8") as f:
        content = f.read()
    assert_true("Campaign ID" in content, "Summary missing Campaign ID")
    assert_true("ADMET Pre-filter" in content, "Summary missing ADMET section")
    assert_true("Executive Summary" in content, "Summary missing Executive Summary")
    assert_true("BM-001" in content, "Summary missing first compound")


def test_qc_report(output_dir: str) -> None:
    exporter = _build_exporter(output_dir)
    path = exporter.export_qc_report()
    assert_file_nonempty(path)
    with open(path, encoding="utf-8") as f:
        report = json.load(f)
    assert_true(report["n_compounds"] == 5, f"Expected 5 compounds, got {report['n_compounds']}")
    assert_true(0.0 <= report["admet_pass_rate"] <= 1.0, "admet_pass_rate out of range")
    assert_true("priority_distribution" in report, "QC report missing priority_distribution")
    assert_true("diversity_estimate" in report, "QC report missing diversity_estimate")


def test_export_all(output_dir: str) -> None:
    exporter = _build_exporter(output_dir)
    paths = exporter.export_all(prefix="all_")
    expected_keys = {"wuxi_csv", "pharmaron_csv", "enamine_csv", "scientific_summary", "qc_report"}
    assert_true(set(paths.keys()) == expected_keys, f"export_all returned unexpected keys: {paths.keys()}")
    for key, path in paths.items():
        assert_file_nonempty(path)


def test_csv_row_count(output_dir: str) -> None:
    """Each CSV should contain a header + exactly 5 data rows."""
    exporter = _build_exporter(output_dir)
    for export_fn, fname in [
        (exporter.export_wuxi_csv, "wuxi_order.csv"),
        (exporter.export_pharmaron_csv, "pharmaron_order.csv"),
        (exporter.export_enamine_csv, "enamine_order.csv"),
    ]:
        path = export_fn()
        with open(path, encoding="utf-8") as f:
            rows = [l for l in f if l.strip()]
        # header + 5 data rows
        assert_true(
            len(rows) == 6,
            f"{fname}: expected 6 lines (header + 5 rows), got {len(rows)}"
        )


# ---------------------------------------------------------------------------
# CommercialAvailabilityChecker tests
# ---------------------------------------------------------------------------

_TEST_SMILES = [e.smiles for e in EXAMPLE_COMPOUNDS]
_TEST_IDS = [e.compound_id for e in EXAMPLE_COMPOUNDS]


def test_check_single_mock() -> None:
    checker = CommercialAvailabilityChecker(mock_mode=True)
    result = checker.check_single(_TEST_SMILES[0], _TEST_IDS[0])
    assert_true(result.compound_id == "BM-001", "Wrong compound_id in result")
    assert_true(isinstance(result.is_available, bool), "is_available must be bool")
    assert_true(isinstance(result.sources, list), "sources must be a list")
    assert_true(result.query_timestamp != "", "query_timestamp must not be empty")


def test_check_batch_mock() -> None:
    checker = CommercialAvailabilityChecker(mock_mode=True)
    results = checker.check_batch(_TEST_SMILES, _TEST_IDS)
    assert_true(len(results) == 5, f"Expected 5 results, got {len(results)}")
    for r in results:
        assert_true(r.smiles != "", "SMILES must not be empty")
        if r.is_available:
            assert_true(len(r.sources) > 0, "Available compound must have at least one source")
            assert_true(r.cheapest_source is not None, "Available compound must have cheapest_source")


def test_availability_summary() -> None:
    checker = CommercialAvailabilityChecker(mock_mode=True)
    results = checker.check_batch(_TEST_SMILES, _TEST_IDS)
    summary = checker.availability_summary(results)
    assert_true(summary["n_checked"] == 5, "n_checked should be 5")
    assert_true(0.0 <= summary["availability_rate"] <= 1.0, "availability_rate out of range")
    assert_true("cheapest_sources" in summary, "summary missing cheapest_sources")


def test_export_availability_report(output_dir: str) -> None:
    checker = CommercialAvailabilityChecker(mock_mode=True)
    results = checker.check_batch(_TEST_SMILES, _TEST_IDS)
    path = os.path.join(output_dir, "availability_report.csv")
    returned = checker.export_availability_report(results, path)
    assert_true(returned == path, "export_availability_report must return the output_path")
    assert_file_nonempty(path)
    with open(path, encoding="utf-8") as f:
        header = f.readline()
    assert_true("compound_id" in header, "Availability CSV missing compound_id")
    assert_true("is_available" in header, "Availability CSV missing is_available")
    assert_true("cheapest_source" in header, "Availability CSV missing cheapest_source")
    with open(path, encoding="utf-8") as f:
        rows = [l for l in f if l.strip()]
    assert_true(len(rows) == 6, f"Expected header + 5 rows, got {len(rows)}")


def test_mock_determinism() -> None:
    """Same compound_id should always produce the same mock availability."""
    checker = CommercialAvailabilityChecker(mock_mode=True)
    r1 = checker.check_single("CC(=O)O", "DET-001")
    r2 = checker.check_single("CC(=O)O", "DET-001")
    assert_true(r1.is_available == r2.is_available, "Mock result not deterministic")


def test_batch_length_mismatch() -> None:
    """check_batch must raise ValueError for mismatched list lengths."""
    checker = CommercialAvailabilityChecker(mock_mode=True)
    raised = False
    try:
        checker.check_batch(["CC"], ["ID-1", "ID-2"])
    except ValueError:
        raised = True
    assert_true(raised, "Expected ValueError for mismatched list lengths")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    with tempfile.TemporaryDirectory(prefix="biomate_cro_test_") as tmpdir:
        print(f"\nOutput directory: {tmpdir}\n")
        print("=" * 60)
        print("CROOrderExporter tests")
        print("=" * 60)

        cro_tests = [
            ("WuXi CSV export", lambda: test_wuxi_csv(tmpdir)),
            ("Pharmaron CSV export", lambda: test_pharmaron_csv(tmpdir)),
            ("Enamine CSV export", lambda: test_enamine_csv(tmpdir)),
            ("Scientific summary", lambda: test_scientific_summary(tmpdir)),
            ("QC JSON report", lambda: test_qc_report(tmpdir)),
            ("export_all convenience", lambda: test_export_all(tmpdir)),
            ("CSV row counts", lambda: test_csv_row_count(tmpdir)),
        ]
        for name, fn in cro_tests:
            ok = run_test(name, fn)
            print(f"  {'PASSED' if ok else 'FAILED':<8} {name}")

        print()
        print("=" * 60)
        print("CommercialAvailabilityChecker tests")
        print("=" * 60)

        avail_tests = [
            ("check_single mock mode", test_check_single_mock),
            ("check_batch mock mode", test_check_batch_mock),
            ("availability_summary", test_availability_summary),
            ("export_availability_report", lambda: test_export_availability_report(tmpdir)),
            ("mock determinism", test_mock_determinism),
            ("batch length mismatch error", test_batch_length_mismatch),
        ]
        for name, fn in avail_tests:
            ok = run_test(name, fn)
            print(f"  {'PASSED' if ok else 'FAILED':<8} {name}")

        # Print availability summary for visibility
        print()
        print("=" * 60)
        print("Mock availability summary (5 compounds)")
        print("=" * 60)
        checker = CommercialAvailabilityChecker(mock_mode=True)
        results = checker.check_batch(_TEST_SMILES, _TEST_IDS)
        summary = checker.availability_summary(results)
        for k, v in summary.items():
            if k != "timestamp":
                print(f"  {k}: {v}")
        for r in results:
            status = "available" if r.is_available else "not available"
            vendor = f" via {r.cheapest_source}" if r.cheapest_source else ""
            print(f"  {r.compound_id}: {status}{vendor}")

    # Final report
    n_pass = sum(1 for _, ok, _ in _results if ok)
    n_fail = sum(1 for _, ok, _ in _results if not ok)
    print()
    print("=" * 60)
    print(f"Results: {n_pass} PASSED  {n_fail} FAILED  (total {len(_results)})")
    print("=" * 60)

    if n_fail > 0:
        print("\nFailures:")
        for name, ok, tb in _results:
            if not ok:
                print(f"\n--- {name} ---")
                print(tb)
        sys.exit(1)
    else:
        print("\nAll tests passed.")


if __name__ == "__main__":
    main()
