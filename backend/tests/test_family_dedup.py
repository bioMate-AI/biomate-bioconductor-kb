"""Tests for backend.lib.galaxy.ai.retrievers.family_dedup.

Pure unit tests — no network, no DB. Verifies:
1. Alias YAML loads cleanly and contains expected mappings.
2. canonical_family_key correctly resolves path-extraction + alias rules.
3. dedup_results_by_family preserves rank order, merges duplicates, counts
   family members, and handles edge cases (missing tool_id, empty input).
"""
from __future__ import annotations

import pytest

from backend.lib.galaxy.ai.retrievers.family_dedup import (
    load_alias_map,
    load_canonical_map,
    canonical_family_key,
    dedup_results_by_family,
    rerank_to_canonical,
    prioritize_query_family,
)


# ─── alias map ──────────────────────────────────────────────────────────

def test_alias_map_loads_and_has_known_rules():
    m = load_alias_map()
    assert isinstance(m, dict)
    assert len(m) >= 100, f"Expected ≥100 alias rules, got {len(m)}"
    # Spot-check rules that drove the Phase 1.5 A/B win
    assert m.get("naturalis_fastqc") == "fastqc"
    assert m.get("ensemblvep") == "ensembl_vep"
    assert m.get("metaspades") == "spades"
    assert m.get("rmarkdown_deseq2") == "deseq2"
    assert m.get("perform_chipseq_peak_calling_with_macs2") == "macs2"


# ─── canonical_family_key ───────────────────────────────────────────────

@pytest.mark.parametrize("tool_id,name,expected", [
    # Path-extraction cases (no alias needed)
    ("toolshed.g2.bx.psu.edu/repos/iuc/deseq2/deseq2/2.11.40.8+galaxy0",
     "DESeq2", "deseq2"),
    ("toolshed.g2.bx.psu.edu/repos/devteam/bwa/bwa_mem/0.7.19",
     "Map with BWA-MEM", "bwa"),
    ("toolshed.g2.bx.psu.edu/repos/devteam/picard/PicardSortSam/2.27.5",
     "SortSam", "picard"),
    ("nfcore/abricate/run", "Abricate Run", "abricate"),
    ("biomate/protein_dynamics_md", "Protein Dynamics MD", "protein_dynamics_md"),
    ("bioconductor/a4base", "a4base", "bioconductor:a4base"),
    # Alias-rewrite cases (path extraction → fragment → alias → canonical)
    ("toolshed.g2.bx.psu.edu/repos/naturalis/naturalis_fastqc/foo/1.0",
     "Naturalis FastQC", "fastqc"),
])
def test_canonical_family_key(tool_id, name, expected):
    assert canonical_family_key(tool_id, name) == expected


def test_canonical_family_key_uses_caller_alias_map():
    custom = {"deseq2": "rnaseq_de"}
    assert canonical_family_key(
        "toolshed.g2.bx.psu.edu/repos/iuc/deseq2/deseq2/2.11",
        "DESeq2",
        alias_map=custom,
    ) == "rnaseq_de"


# ─── dedup_results_by_family ───────────────────────────────────────────

def test_dedup_collapses_picard_wrappers():
    """Three picard-family rows should collapse to one."""
    results = [
        {"rank": 1, "tool_id": "toolshed.g2.bx.psu.edu/repos/devteam/picard/sort/2.27",
         "name": "Picard SortSam", "score": 14.2},
        {"rank": 2, "tool_id": "toolshed.g2.bx.psu.edu/repos/iuc/picard_plus/foo/1.0",
         "name": "Picard Plus Foo", "score": 13.1},
        {"rank": 3, "tool_id": "toolshed.g2.bx.psu.edu/repos/devteam/picard/md/2.27",
         "name": "Picard MarkDuplicates", "score": 12.0},
        {"rank": 4, "tool_id": "toolshed.g2.bx.psu.edu/repos/iuc/samtools/sort/1.17",
         "name": "Samtools Sort", "score": 11.0},
    ]
    out = dedup_results_by_family(results)
    assert len(out) == 2, f"Expected 2 deduped, got {len(out)}"
    assert out[0]["canonical_family_id"] == "picard"
    assert out[0]["family_member_count"] == 3
    assert out[0]["score"] == 14.2  # highest-ranked kept
    assert out[1]["canonical_family_id"] == "samtools"
    assert out[1]["family_member_count"] == 1


def test_dedup_preserves_rank_order():
    """If first hit is from family A and second is from family B, A stays first."""
    results = [
        {"tool_id": "toolshed.g2.bx.psu.edu/repos/x/bwa/bwa/0.7.18", "name": "BWA"},
        {"tool_id": "toolshed.g2.bx.psu.edu/repos/x/samtools/view/1.17", "name": "Samtools View"},
    ]
    out = dedup_results_by_family(results)
    assert [r["canonical_family_id"] for r in out] == ["bwa", "samtools"]


def test_dedup_empty_input():
    assert dedup_results_by_family([]) == []


def test_dedup_missing_tool_id():
    """Items without tool_id or name are kept as singletons."""
    results = [{"score": 1.0}, {"score": 0.5}]
    out = dedup_results_by_family(results)
    assert len(out) == 2
    for r in out:
        assert r["canonical_family_id"] is None
        assert r["family_member_count"] == 1


def test_dedup_does_not_mutate_input():
    original = {"tool_id": "toolshed.g2.bx.psu.edu/repos/x/bwa/bwa/0.7", "name": "BWA"}
    out = dedup_results_by_family([original])
    assert "canonical_family_id" not in original  # original unchanged
    assert out[0]["canonical_family_id"] == "bwa"


def test_dedup_alias_rewrite_merges_naturalis_and_canonical_fastqc():
    """Naturalis fastqc and canonical fastqc should land in one family."""
    results = [
        {"tool_id": "toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.12",
         "name": "FastQC"},
        {"tool_id": "toolshed.g2.bx.psu.edu/repos/naturalis/naturalis_fastqc/foo/1.0",
         "name": "Naturalis FastQC"},
    ]
    out = dedup_results_by_family(results)
    assert len(out) == 1
    assert out[0]["canonical_family_id"] == "fastqc"
    assert out[0]["family_member_count"] == 2


def test_dedup_custom_keys():
    """Caller can override which dict keys hold tool_id and name."""
    results = [
        {"wrapper_id": "toolshed.g2.bx.psu.edu/repos/x/bwa/bwa/0.7",
         "display_name": "BWA"},
    ]
    out = dedup_results_by_family(results, tool_id_key="wrapper_id",
                                    name_key="display_name")
    assert out[0]["canonical_family_id"] == "bwa"


# ─── Robustness gaps caught during full-validation audit ─────────────

def test_alias_chain_resolves_transitively(tmp_path):
    """If YAML has frag1 → mid → canonical, frag1 resolves to canonical."""
    yaml_path = tmp_path / "chain.yaml"
    yaml_path.write_text(
        "canonical_x:\n"
        "  - mid_y\n"
        "mid_y:\n"
        "  - frag1\n"
        "  - frag2\n"
    )
    load_alias_map.cache_clear()
    m = load_alias_map(str(yaml_path))
    load_alias_map.cache_clear()
    # frag1 and frag2 should resolve all the way to canonical_x, not stop at mid_y
    assert m.get("frag1") == "canonical_x", f"chain broke: frag1 → {m.get('frag1')}"
    assert m.get("frag2") == "canonical_x"
    assert m.get("mid_y") == "canonical_x"


def test_alias_cycle_doesnt_hang(tmp_path):
    """A YAML cycle (a→b, b→a) must not loop forever; loader bounds itself."""
    yaml_path = tmp_path / "cycle.yaml"
    yaml_path.write_text("a:\n  - b\nb:\n  - a\n")
    load_alias_map.cache_clear()
    m = load_alias_map(str(yaml_path))   # must return; should not hang
    load_alias_map.cache_clear()
    assert isinstance(m, dict)


def test_yaml_file_is_a_symlink_to_production(tmp_path):
    """Sandbox copy of the YAML must symlink to the production file, not
    diverge. Prevents the two copies from drifting silently."""
    import os
    from pathlib import Path
    sandbox_yaml = (
        Path(__file__).resolve().parents[2]
        / "sandbox" / "retrieval_v2" / "data" / "family_aliases.yaml"
    )
    if not sandbox_yaml.exists():
        pytest.skip(f"sandbox copy not present at {sandbox_yaml}")
    assert sandbox_yaml.is_symlink(), (
        f"{sandbox_yaml} must be a symlink to backend/database/"
        f"tool_family_aliases.yaml — having two real copies risks drift."
    )
    # Resolve and check it points to the production file
    target = os.readlink(sandbox_yaml)
    assert target.endswith("backend/config/tool_family_aliases.yaml"), \
        f"symlink target unexpected: {target}"


def test_canonical_map_loads():
    """Canonical YAML loads with ≥20 mappings, each value a real tool_id."""
    m = load_canonical_map()
    assert len(m) >= 20, f"expected ≥20 canonical mappings, got {len(m)}"
    # Spot-check a few important ones
    assert m.get("bwa", "").startswith("toolshed.")
    assert m.get("deseq2", "").startswith("toolshed.")
    assert m.get("samtools", "").startswith("toolshed.")


def test_rerank_promotes_canonical_to_family_head():
    """Picard family results: canonical (MarkDuplicates) should rank first."""
    canonical_pic = "toolshed.g2.bx.psu.edu/repos/devteam/picard/picard_MarkDuplicates/3.1.1.0"
    results = [
        {"tool_id": "toolshed.g2.bx.psu.edu/repos/devteam/picard/picard_RevertSam/3.1.1.0",
         "name": "RevertSam", "score": 14.0},
        {"tool_id": "toolshed.g2.bx.psu.edu/repos/devteam/picard/picard_FastqToSam/3.1.1.0",
         "name": "FastqToSam", "score": 13.5},
        {"tool_id": canonical_pic,
         "name": "MarkDuplicates", "score": 13.0},
        {"tool_id": "toolshed.g2.bx.psu.edu/repos/iuc/samtools/samtools_view/1.17",
         "name": "Samtools View", "score": 12.0},
    ]
    out = rerank_to_canonical(results)
    # Picard's canonical (MarkDuplicates) should now be at index 0
    assert out[0]["tool_id"] == canonical_pic, \
        f"canonical should be first: got {[r['tool_id'] for r in out]}"
    # Samtools (different family) should still be last (preserve inter-family order)
    assert out[-1]["canonical_family_id"] == "samtools"


def test_rerank_preserves_order_when_canonical_already_first():
    """If canonical is already at the family head, no swap occurs."""
    canonical_bwa = "toolshed.g2.bx.psu.edu/repos/devteam/bwa/bwa_mem/0.7.19"
    results = [
        {"tool_id": canonical_bwa, "name": "Map with BWA-MEM"},
        {"tool_id": "toolshed.g2.bx.psu.edu/repos/devteam/bwa/bwa/0.7.19", "name": "BWA"},
    ]
    out = rerank_to_canonical(results)
    assert out[0]["tool_id"] == canonical_bwa


def test_rerank_no_op_when_canonical_not_in_results():
    """If the canonical wrapper isn't in the FTS results, leave order intact."""
    results = [
        {"tool_id": "toolshed.g2.bx.psu.edu/repos/x/picard/picard_RevertSam/3.0",
         "name": "RevertSam"},
        {"tool_id": "toolshed.g2.bx.psu.edu/repos/x/picard/picard_FastqToSam/3.0",
         "name": "FastqToSam"},
    ]
    out = rerank_to_canonical(results)
    # Neither has the canonical; order unchanged
    assert out[0]["name"] == "RevertSam"
    assert out[1]["name"] == "FastqToSam"


def test_rerank_preserves_inter_family_order():
    """Two distinct families: each family's slice gets reordered, but
    the families themselves stay in their original positions."""
    canonical_bwa = "toolshed.g2.bx.psu.edu/repos/devteam/bwa/bwa_mem/0.7.19"
    canonical_pic = "toolshed.g2.bx.psu.edu/repos/devteam/picard/picard_MarkDuplicates/3.1.1.0"
    results = [
        {"tool_id": "toolshed.g2.bx.psu.edu/repos/devteam/bwa/bwa/0.7.19", "name": "BWA"},
        {"tool_id": "toolshed.g2.bx.psu.edu/repos/devteam/picard/picard_RevertSam/3.1.1.0", "name": "RevertSam"},
        {"tool_id": canonical_bwa, "name": "Map BWA-MEM"},
        {"tool_id": canonical_pic, "name": "MarkDuplicates"},
    ]
    out = rerank_to_canonical(results)
    # First two slots: bwa family. Third+fourth: picard family.
    # Within each family, canonical wins.
    assert out[0]["tool_id"] == canonical_bwa
    assert out[0]["canonical_family_id"] == "bwa"
    # Picard MarkDuplicates should be at the start of the picard slice (index 1, the original picard-head)
    assert out[1]["tool_id"] == canonical_pic
    assert out[1]["canonical_family_id"] == "picard"


# ─── prioritize_query_family ────────────────────────────────────────────

def test_prioritize_moves_query_family_above_unrelated():
    """When query='bwa', BWA-family results should rank above CIRCexplorer2
    even if CIRCexplorer2 had the higher BM25 score."""
    canonical_bwa = "toolshed.g2.bx.psu.edu/repos/devteam/bwa/bwa_mem/0.7.19"
    results = [
        {"tool_id": "toolshed.g2.bx.psu.edu/repos/iuc/circexplorer2/foo/2.0",
         "name": "CIRCexplorer2"},
        {"tool_id": "toolshed.g2.bx.psu.edu/repos/iuc/chira/chira_map/1.0",
         "name": "ChIRA Map"},
        {"tool_id": canonical_bwa, "name": "Map with BWA-MEM"},
        {"tool_id": "toolshed.g2.bx.psu.edu/repos/devteam/bwa/bwa/0.7.19", "name": "BWA"},
    ]
    out = prioritize_query_family("bwa", results)
    # Canonical BWA-MEM should be at the very top
    assert out[0]["tool_id"] == canonical_bwa, \
        f"expected canonical bwa first; got {[r['name'] for r in out]}"
    # Both BWA results should precede unrelated ones
    bwa_positions = [i for i, r in enumerate(out) if r["canonical_family_id"] == "bwa"]
    other_positions = [i for i, r in enumerate(out) if r["canonical_family_id"] != "bwa"]
    assert max(bwa_positions) < min(other_positions), \
        "all bwa-family results should precede non-bwa results"


def test_prioritize_no_op_when_query_doesnt_match_known_family():
    """Random query text shouldn't reorder results."""
    results = [
        {"tool_id": "toolshed.g2.bx.psu.edu/repos/x/foo/foo/1.0", "name": "Foo"},
        {"tool_id": "toolshed.g2.bx.psu.edu/repos/y/bar/bar/1.0", "name": "Bar"},
    ]
    out = prioritize_query_family("totally unknown garbage", results)
    # Order preserved; tags added
    assert [r["name"] for r in out] == ["Foo", "Bar"]


def test_prioritize_handles_empty_results():
    assert prioritize_query_family("samtools", []) == []


def test_prioritize_via_alias_indirect_match():
    """Query says 'naturalis_fastqc' → alias map says that's 'fastqc' family
    → results should still be reordered to put fastqc first."""
    canonical_fastqc = "toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.74+galaxy1"
    results = [
        {"tool_id": "toolshed.g2.bx.psu.edu/repos/x/other/other_tool/1.0", "name": "Other"},
        {"tool_id": canonical_fastqc, "name": "FastQC"},
    ]
    out = prioritize_query_family("naturalis_fastqc adapter trimming", results)
    assert out[0]["tool_id"] == canonical_fastqc


def test_module_imports_without_pulling_broken_llm_client():
    """The new retrievers package must not transitively import llm_client.py,
    which currently has an unresolved merge conflict making it un-importable.
    Documented in 20260518_PHASE0_CLUSTERING_RESULTS.md."""
    import sys
    # Clear any cached imports
    for mod in list(sys.modules):
        if "backend.lib.galaxy.ai.retrievers" in mod or "llm_client" in mod:
            sys.modules.pop(mod, None)
    # Should not raise
    from backend.lib.galaxy.ai.retrievers import family_dedup  # noqa: F401
    assert "backend.lib.galaxy.ai.llm_client" not in sys.modules, (
        "family_dedup must not transitively import llm_client.py"
    )
