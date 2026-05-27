"""Regression: Plan A queries must route to epitopeprediction, not mhcquant."""

from __future__ import annotations

import importlib.util
from pathlib import Path


def _load_search():
    mod_path = Path(__file__).resolve().parents[1] / "unified_workflow_search.py"
    spec = importlib.util.spec_from_file_location("uws", mod_path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    backend = Path(__file__).resolve().parents[4]
    db = backend / "database" / "galaxy_ai_tools.db"
    if not db.is_file():
        db = backend / "galaxy_ai_tools.db"
    return mod.UnifiedWorkflowSearch(str(db))


PLAN_A_QUERY = """
ANDV Plan A vaccine immunoinformatics track.
Use workflow nfcore/epitopeprediction (Galaxy id 12700) — NOT mhcquant.
Please run nf-core epitopeprediction with tools = mhcnuggets, genome_reference = grch37.
""".strip()


PLAN_B_QUERY = """
I'm on the ANDV Plan B mRNA-LNP vaccine engineering track.
Step 1: optimize codons for heterologous expression before RNA structure and LNP formulation.
Use workflow optimize_codons_for_heterologous_expression (registry id 10813).
This step is codon optimization only — not epitope prediction or immunopeptidomics.
target_sequence = ATGAGTAAAGGAGAAGAACTTTTCACTGGAGTTGTCCCAATTCTTGTTGAATTAGATGGTGATGTTAATGGGCACAAATTTTCTGTCAGTGGAGAGGGTGAAGGTGATGCAACATACGGAAAACTTACCCTTAAATTTATTTGCACTACTGGAAAACTACCTGTTCCATGG
outdir = s3://biomate-nextflow-work/nextflow/outputs/plan_b_e2e_ui/test/
host_codon_usage = {"TTT":0.58,"TTC":0.42,"ATG":1.00}
Use profile docker on AWS Batch.
All parameters are explicit — show the workflow card so I can Run from the panel.
""".strip()


def test_plan_a_routes_to_epitopeprediction_not_mhcquant():
    ws = _load_search()
    results = ws.search(PLAN_A_QUERY, limit=5)
    assert results, "expected at least one workflow match"
    top = results[0]
    assert "epitopeprediction" in top.name.lower(), f"top-1 was {top.name}"
    assert top.id == 12700
    names = [m.name.lower() for m in results[:5]]
    assert not any("mhcquant" in n for n in names), f"mhcquant should be filtered: {names}"


def test_explicit_slug_anchor_extraction():
    ws = _load_search()
    slug = ws._extract_explicit_pipeline_slug(PLAN_A_QUERY)
    assert slug == "epitopeprediction"
    assert ws._extract_negated_pipeline_slugs(PLAN_A_QUERY) == {"mhcquant"}


def test_plan_b_negated_epitope_not_treated_as_explicit_slug():
    ws = _load_search()
    negated = ws._extract_negated_pipeline_slugs(PLAN_B_QUERY)
    assert "epitopeprediction" in negated
    assert "mhcquant" in negated
    assert ws._extract_explicit_pipeline_slug(PLAN_B_QUERY) is None


def test_immunopeptidomics_negation_excludes_mhcquant():
    ws = _load_search()
    negated = ws._extract_negated_pipeline_slugs(
        "codon step only — not epitope prediction or immunopeptidomics"
    )
    assert "mhcquant" in negated


def test_plan_b_routes_to_optimize_codons_not_epitopeprediction():
    ws = _load_search()
    results = ws.search(PLAN_B_QUERY, limit=5)
    assert results, "expected at least one workflow match"
    top = results[0]
    assert top.id == 10813, f"top-1 was id={top.id} name={top.name!r}"
    assert "codon" in top.name.lower() or "optimize" in top.filename.lower()
    names = [m.name.lower() for m in results[:3]]
    assert not any("epitopeprediction" in n for n in names[:1]), f"epitope won: {names}"


def test_plan_b_vaccine_wording_does_not_prefer_immunoinformatics_domain():
    """Plan B mentions vaccine track but must not boost epitope domain over codon."""
    ws = _load_search()
    pref, pen = ws._infer_domain_preferences(PLAN_B_QUERY)
    assert "immunoinformatics" not in pref, f"unexpected immunoinformatics bias: {pref}"
    assert "synthetic_biology" in pref
    assert "immunoinformatics" in pen
