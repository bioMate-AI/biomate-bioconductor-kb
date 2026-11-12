"""Offline tests for citation_check (fake HTTP, no network)."""
from galaxy.ai.agents import citation_check as cc

PM = {"123": "Deep learning for cancer genomics"}
CR = {"10.1/real": "A real paper about kinases"}


def fake(url, timeout):
    if "esummary" in url:
        pid = url.rsplit("=", 1)[1]
        if pid in PM:
            return 200, {"result": {"uids": [pid], pid: {"uid": pid, "title": PM[pid] + "."}}}
        return 200, {"result": {pid: {"uid": pid, "error": "cannot get document summary"}}}
    doi = url.split("/works/")[1]
    return (200, {"message": {"title": [CR[doi]]}}) if doi in CR else (404, None)


def boom(url, timeout):
    raise OSError("network down")


def setup_function(_):
    cc.clear_cache()
    cc._last_call.clear()
    cc.NCBI_MIN_INTERVAL_S = cc.CROSSREF_MIN_INTERVAL_S = 0


def v(c, get=fake, **kw):
    return cc.verify_citation(c, get, offline=False, **kw)["status"]


def test_pmid_verified_and_missing_and_mismatch():
    assert v({"pmid": "123", "title": "Deep learning for cancer genomics"}) == "verified"
    assert v({"pmid": "999", "title": "x"}) == "not_found"
    assert v({"pmid": "123", "title": "Completely unrelated ocean biology"}) == "title_mismatch"
    assert v({"pmid": "12a"}) == "not_found"


def test_doi_paths():
    assert v({"doi": "https://doi.org/10.1/real", "title": "A real paper about kinases"}) == "verified"
    assert v({"doi": "10.1/fake", "title": "x"}) == "not_found"
    assert v({"doi": "10.1/real", "title": "Something else entirely"}) == "title_mismatch"


def test_network_failure_is_never_verified():
    r = cc.verify_citation({"pmid": "123", "title": "Deep learning for cancer genomics"}, boom, offline=False)
    assert r["status"] == "unverified" and "could not check" in r["label"]
    cc.clear_cache()
    assert cc.verify_citation({"pmid": "123"}, lambda u, t: (503, None), offline=False)["status"] == "unverified"


def test_offline_and_no_identifier(monkeypatch):
    monkeypatch.setenv("BIOMATE_OFFLINE", "1")
    called = []
    r = cc.verify_citation({"pmid": "123"}, lambda u, t: called.append(u))
    assert r["status"] == "not_checked_offline" and r["label"] == "not checked (offline)" and not called
    assert cc.verify_citation({"title": "t"}, fake, offline=False)["status"] == "no_identifier"


def test_cache_avoids_second_call():
    n = []
    def g(u, t):
        n.append(u); return fake(u, t)
    c = {"pmid": "123", "title": "Deep learning for cancer genomics"}
    cc.verify_citation(c, g, offline=False); cc.verify_citation(c, g, offline=False)
    assert len(n) == 1


def test_evidence_status():
    ok = {"status": "verified"}
    assert cc.evidence_status([]) == "insufficient"
    assert cc.evidence_status([{"status": "not_found"}]) == "insufficient"
    assert cc.evidence_status([ok, ok]) == "grounded"
    assert cc.evidence_status([ok, {"status": "unverified"}, {"status": "not_found"}]) == "partially_grounded"


def test_refusal_strips_invented_bibliography():
    ans = "It works [1]. See doi 10.9/zzz\nMore text.\n## References\n1. Fake et al. PMID 5"
    out = cc.refuse_without_evidence(ans)
    assert "Insufficient retrievable evidence" in out
    assert "10.9/zzz" not in out and "Fake" not in out and "[1]" not in out


def test_check_answer_renumbers_and_refuses():
    cites = [{"pmid": "999", "title": "bad"}, {"pmid": "123", "title": "Deep learning for cancer genomics"}]
    ans, kept, st, rows = cc.check_answer_citations("A [1]; B [2]; both [1, 2].", cites, fake, offline=False)
    assert st == "grounded" and len(kept) == 1
    assert "B [1]" in ans and "A ;" in ans and "removed" in ans
    ans, kept, st, _ = cc.check_answer_citations("A [1].", [cites[0]], fake, offline=False)
    assert st == "insufficient" and kept == [] and "Insufficient retrievable evidence" in ans
    ans, kept, st, _ = cc.check_answer_citations("Hello", [], fake, offline=False)
    assert st == "insufficient"


def test_refusal_preserves_body_prose_and_headings():
    """refuse_without_evidence strips a FABRICATED bibliography but must NOT delete body
    prose that merely starts with references/sources/citations or mentions doi/pmid as a
    word (committee review round 2, 2026-11-11)."""
    ans = (
        "EVIDENCE: insufficient\n"
        "## Sources of bias in this estimate\n"
        "Selection bias is the main concern.\n"
        "Background: the DOI framework matters for provenance.\n"
        "The PMID system assigns stable identifiers.\n"
        "## References\n"
        "1. Fake et al. doi:10.1234/fake PMID 999\n"
    )
    out = cc.refuse_without_evidence(ans)
    # Kept: the body heading and the prose mentioning doi/pmid as words.
    assert "Sources of bias in this estimate" in out
    assert "the DOI framework matters" in out
    assert "The PMID system assigns stable identifiers" in out
    # Stripped: the real reference section and its identifier line.
    assert "Fake et al" not in out and "10.1234/fake" not in out
