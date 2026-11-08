import csv, os, datetime, collections
HERE = os.path.dirname(os.path.dirname(__file__))
ROWS = list(csv.DictReader(open(os.path.join(HERE, "manifest.csv"))))
CUTOFF = "2023-10-01"

def test_nonempty():
    assert len(ROWS) > 500

def test_no_duplicate_ids():
    ids = [r["complex_id"] for r in ROWS]
    assert len(ids) == len(set(ids))

def test_dates_parse_and_year_matches():
    for r in ROWS:
        d = datetime.date.fromisoformat(r["deposit_date"])
        assert str(d.year) == r["deposit_year"]
        assert d <= datetime.date.today()

def test_post_set_really_post_cutoff():
    for r in ROWS:
        if r["set"] == "post": assert r["deposit_date"] >= CUTOFF, r["complex_id"]
        else: assert r["deposit_date"] < CUTOFF, r["complex_id"]

def test_criteria_enforced():
    for r in ROWS:
        assert 5 <= int(r["peptide_len"]) <= 25
        assert float(r["resolution"]) <= 3.5
        assert int(r["n_iface_res_5A"]) >= 5
        assert int(r["receptor_len"]) >= 40
        assert r["cyclisation_type"]
        assert len(r["peptide_seq"]) == int(r["peptide_len"])

def test_strict_implies_ccd_runnable_and_canonical():
    for r in ROWS:
        if r["runnable_strict"] == "1":
            assert r["runnable_ccd"] == "1" and r["n_noncanonical"] == "0"

def test_one_nr_representative_per_cluster_per_set():
    c = collections.Counter((r["set"], r["receptor_cluster40"]) for r in ROWS if r["nr_rep_in_set"] == "1")
    assert all(v == 1 for v in c.values())
    for s in ("pre", "post"):
        assert {k[1] for k in c if k[0] == s} == {r["receptor_cluster40"] for r in ROWS if r["set"] == s}
