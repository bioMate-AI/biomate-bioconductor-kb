"""Offline tests for the data-backed channels (no network/files — injected http/reader).

Run: PYTHONPATH=backend/lib python3 backend/lib/galaxy/ai/target_id/data_channels_test.py
"""
import sys


def _run():
    from galaxy.ai.target_id.data_channels import (
        OpenTargetsGeneticsChannel, TableChannel, default_channels,
    )
    from galaxy.ai.target_id import TargetIDOrchestrator, EvidenceGateArbiter

    # --- OpenTargets channel with a fake http returning the live-verified response shape ---
    def fake_ot(url, payload, **kw):
        assert "associatedTargets" in payload["query"]
        assert payload["variables"]["efo"] == "MONDO_0005105"
        return {"data": {"disease": {"name": "melanoma", "associatedTargets": {"count": 3, "rows": [
            {"target": {"approvedSymbol": "CDKN2A"}, "score": 0.87},
            {"target": {"approvedSymbol": "BRAF"}, "score": 0.85},
            {"target": {"approvedSymbol": "MAP2K1"}, "score": 0.80},
        ]}}}}
    ot = OpenTargetsGeneticsChannel(http=fake_ot)
    r = ot.run({"disease_id": "MONDO_0005105"})
    assert r.ok and r.scores["BRAF"] == 0.85 and "CDKN2A" in r.scores, r
    assert r.provenance["disease"] == "melanoma", r.provenance

    # fail-soft: no disease id, and unresolved disease
    assert OpenTargetsGeneticsChannel(http=fake_ot).run({}).error, "missing disease_id must error"
    assert OpenTargetsGeneticsChannel(http=lambda u, p, **k: {"data": {"disease": None}}).run(
        {"disease_id": "X"}).error, "null disease must error"

    # --- TableChannel via injected reader (offline), with a disease filter ---
    rows = [
        {"disease": "melanoma", "target": "BRAF", "score": "5.0"},
        {"disease": "melanoma", "target": "EGFR", "score": "4.0"},
        {"disease": "melanoma", "target": "NRAS", "score": "0.9"},
        {"disease": "melanoma", "target": "MYC", "score": "0.8"},
        {"disease": "melanoma", "target": "A", "score": "0.7"},
        {"disease": "melanoma", "target": "B", "score": "0.6"},
        {"disease": "asthma", "target": "IL4", "score": "9.0"},   # filtered out
    ]
    tbl = TableChannel("mem://t", name="depmap", filter_col="disease", context_filter_key="disease",
                       reader=lambda path: rows)
    tr = tbl.run({"disease": "melanoma"})
    assert tr.ok and tr.scores["BRAF"] == 5.0 and "IL4" not in tr.scores, tr
    assert TableChannel("mem://t", filter_col="disease", context_filter_key="disease",
                        reader=lambda p: rows).run({"disease": "nope"}).error, "no-match must error"

    # --- default_channels assembler ---
    chans = default_channels(disease_id="MONDO_0005105",
                             tables=[{"path": "mem://t", "name": "depmap", "reader": lambda p: rows,
                                      "filter_col": "disease", "context_filter_key": "disease"}])
    # With a disease id the default set now includes the STRING network channel (it expands from the Open Targets
    # top genes in the orchestrator's second stage); include_network=False restores the Open Targets + tables set.
    assert [c.name for c in chans] == ["genetics_ot", "ppi_string", "depmap"], [c.name for c in chans]
    chans = default_channels(disease_id="MONDO_0005105", include_network=False,
                             tables=[{"path": "mem://t", "name": "depmap", "reader": lambda p: rows,
                                      "filter_col": "disease", "context_filter_key": "disease"}])
    assert [c.name for c in chans] == ["genetics_ot", "depmap"], [c.name for c in chans]

    # --- integration: OT + Table -> BRAF corroborated (fires in both), ranks top ---
    ot2 = OpenTargetsGeneticsChannel(http=fake_ot, name="genetics_ot")
    orch = TargetIDOrchestrator([ot2, tbl], arbiter=EvidenceGateArbiter(z_thresh=2.0))
    res = orch.identify("melanoma targets", context={"disease_id": "MONDO_0005105", "disease": "melanoma"})
    by = {t.target: t for t in res.targets}
    assert set(res.channels_run) == {"genetics_ot", "depmap"}, res.channels_run
    assert by["BRAF"].tier == "corroborated", {t.target: t.tier for t in res.targets}
    assert res.targets[0].target == "BRAF", [t.target for t in res.targets[:3]]

    print("data_channels test: PASS  (OT verified-shape parse + fail-soft; Table filter; "
          "BRAF corroborated #1 across OT+table)")


if __name__ == "__main__":
    try:
        _run()
    except AssertionError as e:
        print("data_channels test: FAIL ->", e)
        sys.exit(1)
    except Exception as e:  # pragma: no cover
        print("data_channels test: ERROR ->", type(e).__name__, e)
        sys.exit(2)
