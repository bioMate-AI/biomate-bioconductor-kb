"""B2 — region pack smoke tests."""
from __future__ import annotations
from galaxy.ai.drug_discovery.regulatory_region_packs import (
    region_style_rules, known_regions,
)


def test_default_fda_returns_some_rules():
    assert region_style_rules("FDA", "tox_overview")


def test_unknown_region_returns_empty():
    assert region_style_rules("ATLANTIS", "tox_overview") == []


def test_ema_pbpk_mentions_guideline():
    joined = " ".join(region_style_rules("EMA", "pbpk"))
    assert "EMA/CHMP/EWP/37498/2011" in joined


def test_nmpa_tox_has_ethnic_bridge():
    joined = " ".join(region_style_rules("NMPA", "tox_overview"))
    assert "Chinese ethnic" in joined or "Asian" in joined


def test_rule_cap_at_four():
    for region in known_regions():
        for sec in ("tox_overview", "pbpk", "admet", "tabulated_summary"):
            assert len(region_style_rules(region, sec)) <= 4


def test_case_insensitive_region():
    assert region_style_rules("ema", "pbpk") == region_style_rules("EMA", "pbpk")


def test_known_regions_four():
    assert set(known_regions()) == {"FDA", "EMA", "NMPA", "PMDA"}
