"""Tests for workflow chain context parameter propagation."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[2] / "lib"))

from galaxy.webapps.galaxy.api.workflow_chain import resolve_context_params


def test_grch38_to_hsa():
    conn = {"context_params": {"organism": {"from_run_param": "genome", "transform": "genome_to_organism"}}}
    result = resolve_context_params(conn, {"genome": "GRCh38"})
    assert result == {"organism": "hsa"}, f"Expected {{'organism': 'hsa'}}, got {result}"


def test_grch37_to_hsa():
    conn = {"context_params": {"organism": {"from_run_param": "genome", "transform": "genome_to_organism"}}}
    result = resolve_context_params(conn, {"genome": "GRCh37"})
    assert result == {"organism": "hsa"}, f"Expected {{'organism': 'hsa'}}, got {result}"


def test_grcm39_to_mmu():
    conn = {"context_params": {"organism": {"from_run_param": "genome", "transform": "genome_to_organism"}}}
    result = resolve_context_params(conn, {"genome": "GRCm39"})
    assert result == {"organism": "mmu"}, f"Expected {{'organism': 'mmu'}}, got {result}"


def test_grcm38_to_mmu():
    conn = {"context_params": {"organism": {"from_run_param": "genome", "transform": "genome_to_organism"}}}
    result = resolve_context_params(conn, {"genome": "GRCm38"})
    assert result == {"organism": "mmu"}, f"Expected {{'organism': 'mmu'}}, got {result}"


def test_missing_source_param_returns_empty():
    conn = {"context_params": {"organism": {"from_run_param": "genome", "transform": "genome_to_organism"}}}
    result = resolve_context_params(conn, {})
    assert result == {}, f"Expected {{}}, got {result}"


def test_no_context_params_returns_empty():
    conn = {}
    result = resolve_context_params(conn, {"genome": "GRCh38"})
    assert result == {}, f"Expected {{}}, got {result}"


def test_unknown_genome_passthrough():
    conn = {"context_params": {"organism": {"from_run_param": "genome", "transform": "genome_to_organism"}}}
    result = resolve_context_params(conn, {"genome": "T2T-CHM13"})
    # unknown genome: passthrough unchanged
    assert result == {"organism": "T2T-CHM13"}, f"Expected {{'organism': 'T2T-CHM13'}}, got {result}"


def test_no_transform_direct_copy():
    conn = {"context_params": {"count_matrix": {"from_run_param": "output_counts_path"}}}
    result = resolve_context_params(conn, {"output_counts_path": "/results/counts.tsv"})
    assert result == {"count_matrix": "/results/counts.tsv"}, f"Expected count_matrix path, got {result}"


if __name__ == "__main__":
    tests = [
        test_grch38_to_hsa,
        test_grch37_to_hsa,
        test_grcm39_to_mmu,
        test_grcm38_to_mmu,
        test_missing_source_param_returns_empty,
        test_no_context_params_returns_empty,
        test_unknown_genome_passthrough,
        test_no_transform_direct_copy,
    ]
    passed = 0
    failed = 0
    for t in tests:
        try:
            t()
            print(f"  PASS  {t.__name__}")
            passed += 1
        except AssertionError as e:
            print(f"  FAIL  {t.__name__}: {e}")
            failed += 1
        except Exception as e:
            print(f"  ERROR {t.__name__}: {e}")
            failed += 1
    print(f"\n{passed}/{passed + failed} tests passed")
    sys.exit(0 if failed == 0 else 1)
