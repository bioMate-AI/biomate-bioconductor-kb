"""Offline tests for the modality selector (fakes only, no network).

Run (from backend/): PYTHONPATH=lib python -m galaxy.ai.target_id.modality_test
"""
import sys


def _entry(acc, gene, length, feats=None, locs=None, kws=None, ec=None, sim=""):
    f = []
    for typ, s, e, d in (feats or []):
        f.append({"type": typ, "location": {"start": {"value": s}, "end": {"value": e}}, "description": d})
    comments = []
    if locs:
        comments.append({"commentType": "SUBCELLULAR LOCATION", "subcellularLocations": [{"location": {"value": l}} for l in locs]})
    if sim:
        comments.append({"commentType": "SIMILARITY", "texts": [{"value": sim}]})
    pd = {"recommendedName": {"ecNumbers": [{"value": x} for x in (ec or [])]}}
    return {"primaryAccession": acc, "organism": {"taxonId": 9606}, "genes": [{"geneName": {"value": gene}}],
            "sequence": {"length": length}, "features": f, "comments": comments,
            "keywords": [{"name": k} for k in (kws or [])], "proteinDescription": pd}


HER2 = _entry("P04626", "ERBB2", 1255, [("Signal", 1, 22, ""), ("Topological domain", 23, 652, "Extracellular"),
                                         ("Transmembrane", 653, 675, "Helical"), ("Topological domain", 676, 1255, "Cytoplasmic")],
              ["Cell membrane"], ["Kinase", "Receptor", "Membrane"], ["2.7.10.1"])
BRAF = _entry("P15056", "BRAF", 766, None, ["Nucleus", "Cytoplasm"], ["Kinase", "Transferase"], ["2.7.11.1"], "Belongs to the protein kinase superfamily.")
TNF = _entry("P01375", "TNF", 233, [("Signal", 1, 0, ""), ("Transmembrane", 29, 49, "Helical")], ["Secreted", "Cell membrane"], ["Cytokine"])
IL6 = _entry("P05231", "IL6", 212, [("Signal", 1, 27, "")], ["Secreted"], ["Cytokine", "Secreted"])
ADRB2 = _entry("P07550", "ADRB2", 413, [("Transmembrane", i * 30, i * 30 + 20, "Helical") for i in range(1, 8)] +
               [("Topological domain", 1, 28, "Extracellular")], ["Cell membrane"], ["G-protein coupled receptor", "Receptor"],
               None, "Belongs to the G-protein coupled receptor 1 family.")
MYC = _entry("P01106", "MYC", 439, None, ["Nucleus"], ["Transcription regulation"])


def _fake_http(url):
    assert "uniprot" in url
    import urllib.parse
    url = urllib.parse.unquote_plus(url)
    res = []
    for e in (HER2, BRAF, TNF, IL6, ADRB2, MYC):
        if ("accession:" + e["primaryAccession"]) in url or ("gene_exact:" + e["genes"][0]["geneName"]["value"] + " ") in url:
            res.append(e)
    return {"results": res}


def _run():
    from galaxy.ai.target_id import modality as M

    p = M.parse_uniprot_entry(HER2)
    assert p["n_tm"] == 1 and p["signal_peptide"] and p["extracellular_len"] == 630 and p["ec"] == ["2.7.10.1"], p
    assert M.classify_location(p) == "membrane_single_or_few"
    assert M.classify_location(M.parse_uniprot_entry(BRAF)) == "intracellular"
    assert M.classify_location(M.parse_uniprot_entry(IL6)) == "secreted"
    assert M.classify_location(M.parse_uniprot_entry(ADRB2)) == "membrane_multipass"

    expect = {"BRAF": "small_molecule", "IL6": "biologic", "ADRB2": "small_molecule", "ERBB2": None, "MYC": None}
    for e in (BRAF, IL6, ADRB2, HER2, MYC):
        r = M.select_modality(M.parse_uniprot_entry(e))
        g = e["genes"][0]["geneName"]["value"]
        assert r["uses_drug_precedent"] is False and r["validated"] is False and "Guidance" in r["note"]
        assert [o["modality"] for o in r["ranked_options"]] and len(r["ranked_options"]) == 4
        assert r["rationale"] and r["confidence"] in ("high", "medium", "low")
        assert r["properties"]["length"] == e["sequence"]["length"]
        if expect[g]:
            assert r["top"] == expect[g], (g, r["top"], r["ranked_options"])
    # RTK with big ECD + kinase: both modalities must be in the top two (known dual-modality target)
    r = M.select_modality(M.parse_uniprot_entry(HER2))
    assert set(o["modality"] for o in r["ranked_options"][:2]) == {"biologic", "small_molecule"}, r["ranked_options"]
    # non-catalytic intracellular: macrocycle/other options are raised above zero and confidence is not high
    r = M.select_modality(M.parse_uniprot_entry(MYC))
    sc = dict((o["modality"], o["score"]) for o in r["ranked_options"])
    assert sc["macrocycle_peptide"] > 0 and sc["other"] > 0 and r["confidence"] != "high", r

    # baselines
    assert M.baseline_membrane_rule(M.parse_uniprot_entry(IL6)) == "biologic"
    assert M.baseline_membrane_rule(M.parse_uniprot_entry(BRAF)) == "small_molecule"

    # fetchers via injected http (batched + symbol), fail-soft
    feats = M.fetch_uniprot_features(["P04626", "P15056", "NOPE"], _fake_http)
    assert set(feats) == {"P04626", "P15056"}
    out = M.suggest_modality("BRAF", _fake_http)
    assert out["top"] == "small_molecule" and out["target"] == "BRAF", out

    def boom(url):
        raise RuntimeError("down")
    assert M.suggest_modality("BRAF", boom)["error"]
    assert M.fetch_uniprot_features(["P04626"], boom) == {}
    assert M.suggest_modality("ZZZ", lambda u: {"results": []})["error"]

    # precedent-aware mode is labelled and separate
    calls = []

    def fake_post(url, payload):
        calls.append(payload["query"][:12])
        if "search" in payload["query"]:
            return {"data": {"search": {"hits": [{"id": "ENSG1"}]}}}
        return {"data": {"target": {"approvedSymbol": "X", "tractability": [{"modality": "SM", "label": "a", "value": True},
                                                                              {"modality": "AB", "label": "b", "value": False}]}}}
    pa = M.precedent_aware_modality("X", fake_post)
    assert pa["mode"] == "precedent_aware" and pa["uses_drug_precedent"] is True and pa["ranked_options"][0]["modality"] == "small_molecule"

    # evaluation metrics helper
    from galaxy.ai.target_id import modality_eval as E
    m = E.metrics([("small_molecule", "small_molecule"), ("small_molecule", "biologic"), ("biologic", "biologic")])
    assert m["n"] == 3 and abs(m["accuracy"] - 2 / 3.0) < 1e-9
    assert m["per_class_recall"]["small_molecule"]["recall"] == 0.5 and m["per_class_recall"]["other"]["recall"] is None
    assert m["confusion_matrix_rows_gold_cols_pred"]["small_molecule"]["biologic"] == 1
    lo, hi = E.wilson(8, 10)
    assert 0.4 < lo < 0.8 < hi < 1.0
    print("modality_test: all OK")


if __name__ == "__main__":
    try:
        _run()
    except AssertionError as e:
        print("FAIL", e)
        sys.exit(1)
