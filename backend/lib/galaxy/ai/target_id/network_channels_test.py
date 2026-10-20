"""Offline tests for network/gene-set channels (injected STRING http + gene_sets).

Run: PYTHONPATH=backend/lib python3 backend/lib/galaxy/ai/target_id/network_channels_test.py
"""
import sys


def _run():
    from galaxy.ai.target_id import StringPpiChannel, PathwayCoMembershipChannel

    # --- STRING channel with a fake http returning the live-verified row shape ---
    def fake_string(endpoint, params, **kw):
        assert endpoint == "interaction_partners"
        assert "TP53" in params["identifiers"]
        return [
            {"preferredName_A": "TP53", "preferredName_B": "SIRT1", "score": 0.999},
            {"preferredName_A": "TP53", "preferredName_B": "MAPK1", "score": 0.90},
            {"preferredName_A": "BRAF", "preferredName_B": "MAPK1", "score": 0.80},   # agg across seeds
            {"preferredName_A": "TP53", "preferredName_B": "TP53", "score": 1.0},     # self -> excluded
        ]
    ppi = StringPpiChannel(http=fake_string, agg="max")
    r = ppi.run({"seed_genes": ["TP53", "BRAF"]})
    assert r.ok, r.error
    assert "TP53" not in r.scores, "seed must be excluded from candidates"
    assert r.scores["SIRT1"] == 0.999 and r.scores["MAPK1"] == 0.90, r.scores  # max(0.90,0.80)
    # sum agg
    ppi_sum = StringPpiChannel(http=fake_string, agg="sum")
    rs = ppi_sum.run({"seed_genes": ["TP53", "BRAF"]})
    assert abs(rs.scores["MAPK1"] - 1.70) < 1e-9, rs.scores  # 0.90 + 0.80
    # fail-soft: no seeds
    assert StringPpiChannel(http=fake_string).run({}).error, "missing seeds must error"

    # --- Pathway co-membership with injected gene sets ---
    gene_sets = {
        "PW_MAPK": ["BRAF", "MAP2K1", "EGFR"],
        "PW_RAS": ["BRAF", "NRAS"],
        "PW_P53": ["TP53", "MDM2"],
    }
    pw = PathwayCoMembershipChannel(gene_sets=gene_sets)
    pr = pw.run({"seed_genes": ["BRAF"]})
    assert pr.ok, pr.error
    assert "BRAF" not in pr.scores, "seed excluded"
    assert pr.scores["MAP2K1"] == 1.0 and pr.scores["EGFR"] == 1.0 and pr.scores["NRAS"] == 1.0, pr.scores
    assert "TP53" not in pr.scores and "MDM2" not in pr.scores, "non-co-members excluded"
    # two seeds sharing: MAP2K1 co-occurs with BRAF in PW_MAPK only -> 1; with seeds {BRAF,NRAS} still PW_MAPK+PW_RAS? NRAS not in PW_MAPK
    pr2 = pw.run({"seed_genes": ["BRAF", "NRAS"]})
    assert pr2.scores.get("MAP2K1") == 1.0 and pr2.scores.get("EGFR") == 1.0, pr2.scores
    assert PathwayCoMembershipChannel(gene_sets=gene_sets).run({}).error, "missing seeds must error"
    assert PathwayCoMembershipChannel(gene_sets={}).run({"seed_genes": ["BRAF"]}).error, "no sets must error"

    print("network_channels test: PASS  (STRING max/sum agg + seed-exclusion + fail-soft; "
          "pathway co-membership guilt-by-association)")


if __name__ == "__main__":
    try:
        _run()
    except AssertionError as e:
        print("network_channels test: FAIL ->", e)
        sys.exit(1)
    except Exception as e:  # pragma: no cover
        print("network_channels test: ERROR ->", type(e).__name__, e)
        sys.exit(2)
