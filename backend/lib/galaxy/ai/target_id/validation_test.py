"""Offline test for the nominate->validate bridge (mock catalog + mock orchestrator; no galaxy/network)."""
from galaxy.ai.target_id.validation import validation_plan, nominate_and_validate, VALIDATION_INTENTS
from galaxy.ai.target_id.types import TargetScore, TargetEvidence, OrchestratorResult


def _mock_search(query, limit=3):
    # returns a deterministic workflow per intent keyword in the query
    kw = ("druggability" if "druggab" in query else "rnaseq" if "expression" in query
          else "docking" if "docking" in query else "crispr")
    gene = query.split()[0]
    return [{"id": hash((gene, kw)) % 1000, "name": "%s_%s_wf" % (kw, gene), "domain": "drug_discovery",
             "source": "nfcore", "format": "nextflow", "filename": "%s.nf" % kw, "score": 0.8,
             "match_type": "high_confidence"}][:limit]


def test_validation_plan():
    targets = [TargetScore(target="BRAF", score=0.9, tier="corroborated", rank=1, evidence=TargetEvidence(target="BRAF")),
               TargetScore(target="PTEN", score=0.7, tier="nominated", rank=2, evidence=TargetEvidence(target="PTEN"))]
    plan = validation_plan(targets, top_n=2, per_intent=1, search_fn=_mock_search)
    assert set(plan) == {"BRAF", "PTEN"}, plan
    assert plan["BRAF"]["rank"] == 1 and plan["BRAF"]["tier"] == "corroborated"
    assert set(plan["BRAF"]["validation"]) == {k for k, _ in VALIDATION_INTENTS}
    assert plan["BRAF"]["validation"]["druggability"][0]["name"].startswith("druggability_BRAF")
    assert plan["BRAF"]["validation"]["expression"][0]["name"].startswith("rnaseq_BRAF")

    class _MockOrch:
        def identify(self, query, context=None):
            return OrchestratorResult(query=query, targets=targets, channels_run=["genetics_ot"],
                                      channel_errors={}, arbiter="harmonic_sum", plan=None)
    out = nominate_and_validate(_MockOrch(), "melanoma", top_n=2, per_intent=1, search_fn=_mock_search)
    assert out["targets"].targets[0].target == "BRAF"
    assert "BRAF" in out["validation_plan"] and "PTEN" in out["validation_plan"]
    # fail-soft: a search_fn that raises yields an error marker, not a crash
    def _boom(q, limit=3):
        raise RuntimeError("catalog down")
    p2 = validation_plan(targets[:1], top_n=1, per_intent=1, search_fn=_boom)
    assert isinstance(p2["BRAF"]["validation"]["druggability"], dict) and "error" in p2["BRAF"]["validation"]["druggability"]
    print("validation test: PASS  (per-target battery %s; nominate->validate end-to-end; fail-soft on catalog error)"
          % [k for k, _ in VALIDATION_INTENTS])


if __name__ == "__main__":
    test_validation_plan()
