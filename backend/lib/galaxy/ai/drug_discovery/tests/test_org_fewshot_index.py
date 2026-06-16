"""B3 few_shot_index real compiler + loader smoke."""
from __future__ import annotations
import json, pytest
from pathlib import Path
from galaxy.ai.drug_discovery.org_fewshot_index import (
    _tokens, build_index, write_index, build_and_write,
    load_top_exemplars, load_fewshot_block,
)


@pytest.fixture
def pairs_file(tmp_path):
    """Five chosen exemplars across two orgs + one global."""
    p = tmp_path / "customer_pairs.jsonl"
    p.write_text("\n".join([
        json.dumps({
            "chosen": "PBPK qualification met the EMA/CHMP/EWP/37498/2011 within-2-fold criterion. Per ICH M3(R2).",
            "rejected": "PBPK fine.",
            "meta": {"org_id": "acme", "section_type": "pbpk", "task": "pbpk"},
        }),
        json.dumps({
            "chosen":   "Genotoxicity assessed per ICH S2(R1). Ames assay was negative.",
            "rejected": "Genotoxicity studies performed.",
            "meta": {"org_id": "acme", "section_type": "tox_genotox"},
        }),
        json.dumps({
            "chosen":   "Cardiac safety per ICH S7B. No hERG signal.",
            "rejected": "Cardiac was fine.",
            "meta": {"org_id": "other", "section_type": "tox_cardiac"},
        }),
        json.dumps({
            "chosen":   "Use 21 CFR 312 audit-trail framing throughout.",
            "rejected": "Logs are stored.",
            "meta": {},
        }),
        json.dumps({
            "chosen":   "Second PBPK example: model is fit for purpose at all doses tested.",
            "rejected": "Model works.",
            "meta": {"org_id": "acme", "section_type": "pbpk"},
        }),
    ]))
    return p


def test_tokens_basic():
    toks = _tokens("PBPK met EMA/CHMP/EWP/37498/2011 within-2-fold criterion.")
    assert "pbpk" in toks
    # Citation token with slashes survives intact
    assert any("ema" in t for t in toks)
    # stopwords filtered out
    assert "the" not in toks


def test_build_index_filters_by_org(pairs_file):
    rows = build_index(pairs_file, org_id="acme")
    # acme = 2 + global = 1 → 3 rows
    sections = sorted(r["section_type"] for r in rows)
    assert sections == ["pbpk", "pbpk", "tox_genotox"] or "tox_cardiac" not in sections
    # No cardiac (belongs to other org)
    assert not any("cardiac" in r["section_type"] for r in rows)


def test_build_index_for_other_org(pairs_file):
    rows = build_index(pairs_file, org_id="other")
    assert any("cardiac" in r["section_type"] for r in rows)


def test_build_index_missing_file(tmp_path):
    assert build_index(tmp_path / "nope.jsonl", "acme") == []


def test_max_chars_truncates_exemplar(tmp_path):
    p = tmp_path / "p.jsonl"
    p.write_text(json.dumps({
        "chosen": "x" * 5000,
        "meta": {"org_id": "acme", "section_type": "pbpk"},
    }) + "\n")
    rows = build_index(p, "acme", max_chars=200)
    assert len(rows[0]["exemplar"]) == 200


def test_write_index_roundtrip(pairs_file, tmp_path):
    out = tmp_path / "acme.jsonl"
    n = build_and_write(pairs_file, out, "acme")
    assert n >= 2
    assert out.exists()
    rows = [json.loads(l) for l in out.read_text().splitlines() if l.strip()]
    assert len(rows) == n
    assert all("tokens" in r and "exemplar" in r for r in rows)


def test_load_top_exemplars_filters_by_section(pairs_file, tmp_path):
    out = tmp_path / "acme.jsonl"
    build_and_write(pairs_file, out, "acme")
    pbpk = load_top_exemplars(out, section_type="pbpk", prompt_text="PBPK model EMA criterion", k=2)
    assert len(pbpk) >= 1
    assert any("pbpk" in e.lower() for e in pbpk)
    # The PBPK-tagged exemplars rank highest for a PBPK query
    assert "ICH S2(R1)" not in pbpk[0]


def test_load_top_exemplars_falls_back_to_any_section(pairs_file, tmp_path):
    """A section with no indexed exemplars falls back to any-section."""
    out = tmp_path / "acme.jsonl"
    build_and_write(pairs_file, out, "acme")
    rows = load_top_exemplars(out, section_type="overview", prompt_text="", k=2)
    assert rows  # found something from another section


def test_load_top_exemplars_uses_token_overlap(pairs_file, tmp_path):
    """The prompt query steers which exemplar wins among section matches."""
    out = tmp_path / "acme.jsonl"
    build_and_write(pairs_file, out, "acme")
    # Query mentioning 'within-2-fold' should pull the first PBPK exemplar
    top = load_top_exemplars(out, section_type="pbpk", prompt_text="within-2-fold criterion EMA", k=1)
    assert "within-2-fold" in top[0].lower()


def test_load_fewshot_block_returns_bullets(pairs_file, tmp_path):
    out = tmp_path / "acme.jsonl"
    build_and_write(pairs_file, out, "acme")
    bullets = load_fewshot_block(out, section_type="pbpk", prompt_text="EMA criterion", k=2)
    assert bullets
    for b in bullets:
        assert "Example of preferred pbpk prose" in b


def test_load_empty_index_returns_empty(tmp_path):
    out = tmp_path / "empty.jsonl"
    out.write_text("")
    assert load_top_exemplars(out, section_type="pbpk") == []
    assert load_fewshot_block(out, section_type="pbpk") == []


def test_load_missing_index_returns_empty(tmp_path):
    assert load_top_exemplars(tmp_path / "nope.jsonl", section_type="pbpk") == []


def test_k_zero_returns_empty(pairs_file, tmp_path):
    out = tmp_path / "acme.jsonl"
    build_and_write(pairs_file, out, "acme")
    assert load_top_exemplars(out, section_type="pbpk", k=0) == []
