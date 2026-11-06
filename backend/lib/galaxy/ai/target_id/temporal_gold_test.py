"""Offline tests: novelty logic of temporal_gold and metric logic of temporal_eval (fake rows, no network).

Run: PYTHONPATH=backend/lib python -m galaxy.ai.target_id.temporal_gold_test
"""
import datetime
import unittest

from galaxy.ai.target_id import temporal_eval as te
from galaxy.ai.target_id import temporal_gold as tg

C = datetime.date(2024, 6, 30)


def T(tid, gene, ttype="SINGLE PROTEIN", org="Homo sapiens"):
    return tid, {"type": ttype, "organism": org, "genes": [gene] if isinstance(gene, str) else gene}


TARGETS = dict([T("T_A", "AAA"), T("T_B", "BBB"), T("T_C", "CCC"), T("T_D", "DDD"), T("T_E", "EEE"),
                T("T_BAC", "GYRA", org="Escherichia coli"), T("T_CPLX", ["XXX", "YYY"], ttype="PROTEIN COMPLEX")])


def mol(year, exact=None, name="d"):
    return {"name": name, "year": year, "exact": exact}


def mech(m, t, eff=1):
    return {"molecule": m, "target": t, "disease_efficacy": eff, "refs": [], "moa": "x"}


def ind(m, d, name="dis"):
    return {"molecule": m, "disease_id": d, "disease_name": name}


class NoveltyLogic(unittest.TestCase):
    def test_status(self):
        self.assertEqual(tg.approval_status(2023, None, C), "pre")
        self.assertEqual(tg.approval_status(2025, None, C), "post")
        self.assertEqual(tg.approval_status(2024, None, C), "ambiguous")
        self.assertEqual(tg.approval_status(2024, "2024-09-26", C), "post")
        self.assertEqual(tg.approval_status(2024, "2024-02-01", C), "pre")
        self.assertEqual(tg.approval_status(None, None, C), "unknown")
        # cut-off 2025-01-01: 2024 is cleanly pre, 2025 cleanly post
        c25 = datetime.date(2025, 1, 1)
        self.assertEqual(tg.approval_status(2024, None, c25), "pre")
        self.assertEqual(tg.approval_status(2025, None, c25), "post")

    def run_classify(self, mols, mechs, inds, **kw):
        return tg.classify(mols, mechs, inds, TARGETS, C, **kw)

    def test_novel_vs_new_indication(self):
        mols = {"M_old": mol(2010), "M_new1": mol(2025), "M_new2": mol(2025)}
        mechs = [mech("M_old", "T_A"), mech("M_new1", "T_A"), mech("M_new2", "T_B")]
        inds = [ind("M_old", "D1"), ind("M_new1", "D2"), ind("M_new2", "D2")]
        r = self.run_classify(mols, mechs, inds)
        by = {p["target_symbol"]: p["subset"] for p in r["pairs"]}
        self.assertEqual(by["AAA"], "new_indication")   # AAA had an approved drug in 2010 (D1)
        self.assertEqual(by["BBB"], "novel")            # BBB never approved before
        self.assertEqual(r["pre_cutoff_approved_targets"], ["AAA"])

    def test_same_pair_pre_approved_is_excluded(self):
        mols = {"M_old": mol(2010), "M_new": mol(2025)}
        mechs = [mech("M_old", "T_A"), mech("M_new", "T_A")]
        inds = [ind("M_old", "D1"), ind("M_new", "D1")]   # same disease again: a me-too, not new
        r = self.run_classify(mols, mechs, inds)
        self.assertEqual(r["pairs"], [])
        self.assertEqual(r["excluded_summary"]["pair_already_approved_pre_cutoff"], 1)

    def test_ambiguous_year_never_makes_novel(self):
        # BBB's only earlier drug is dated 2024 (straddles the cut-off) -> cannot prove novelty
        mols = {"M_amb": mol(2024), "M_new": mol(2025)}
        mechs = [mech("M_amb", "T_B"), mech("M_new", "T_B")]
        inds = [ind("M_amb", "D1"), ind("M_new", "D2")]
        r = self.run_classify(mols, mechs, inds)
        self.assertEqual(r["pairs"], [])
        self.assertEqual(r["excluded_summary"]["target_has_ambiguous_dated_approved_drug"], 1)

    def test_exact_date_resolves_ambiguity(self):
        mols = {"M_amb": mol(2024, "2024-09-26")}
        r = self.run_classify(mols, [mech("M_amb", "T_C")], [ind("M_amb", "D3")])
        self.assertEqual([(p["target_symbol"], p["subset"], p["date_precision"]) for p in r["pairs"]],
                         [("CCC", "novel", "day")])

    def test_unknown_date_blocks_novel(self):
        mols = {"M_unk": mol(None), "M_new": mol(2025)}
        mechs = [mech("M_unk", "T_C"), mech("M_new", "T_C")]
        inds = [ind("M_unk", "D1"), ind("M_new", "D2")]
        self.assertEqual(self.run_classify(mols, mechs, inds)["pairs"], [])

    def test_bacterial_and_complex_targets_not_gold_but_count_as_prior(self):
        mols = {"M_ab": mol(2000), "M_new": mol(2025), "M_cx": mol(2025)}
        mechs = [mech("M_ab", "T_BAC"), mech("M_new", "T_BAC"), mech("M_cx", "T_CPLX")]
        inds = [ind("M_ab", "D1"), ind("M_new", "D2"), ind("M_cx", "D3")]
        r = self.run_classify(mols, mechs, inds)
        self.assertEqual(r["pairs"], [])            # non-human single protein / complex: no gold
        # a complex's genes still count as "had an approved drug" for novelty of single-protein targets
        mols2 = {"M_cx0": mol(2001), "M_n": mol(2025)}
        mechs2 = [mech("M_cx0", "T_CPLX"), mech("M_n", "T_A")]
        r2 = self.run_classify(mols2, mechs2, [ind("M_cx0", "D1"), ind("M_n", "D2")])
        self.assertEqual(r2["pairs"][0]["subset"], "novel")

    def test_disease_efficacy_zero_ignored(self):
        mols = {"M_old": mol(2001), "M_new": mol(2025)}
        mechs = [mech("M_old", "T_D", eff=0), mech("M_new", "T_D")]   # old drug not efficacy-mediated via D
        r = self.run_classify(mols, mechs, [ind("M_old", "D1"), ind("M_new", "D2")])
        self.assertEqual(r["pairs"][0]["subset"], "novel")

    def test_multitarget_cap(self):
        mols = {"M_new": mol(2025)}
        mechs = [mech("M_new", "T_A"), mech("M_new", "T_B"), mech("M_new", "T_C"), mech("M_new", "T_D")]
        r = self.run_classify(mols, mechs, [ind("M_new", "D1")], max_targets_per_drug=3)
        self.assertEqual(r["pairs"], [])
        r = self.run_classify(mols, mechs, [ind("M_new", "D1")], max_targets_per_drug=4)
        self.assertEqual(len(r["pairs"]), 4)

    def test_earliest_drug_is_primary(self):
        mols = {"M1": mol(2026, name="late"), "M2": mol(2025, name="early")}
        mechs = [mech("M1", "T_E"), mech("M2", "T_E")]
        r = self.run_classify(mols, mechs, [ind("M1", "D1"), ind("M2", "D1")])
        self.assertEqual(len(r["pairs"]), 1)
        self.assertEqual(r["pairs"][0]["drug_name"], "early")
        self.assertEqual(r["pairs"][0]["other_drugs"], ["M1"])

    def test_disease_id_norm(self):
        self.assertEqual(tg.norm_disease_id("EFO:0000404"), "EFO_0000404")
        self.assertIsNone(tg.norm_disease_id(None))

    def test_pre_pairs_by_disease(self):
        mols = {"M_old": mol(2010), "M_new": mol(2025)}
        mechs = [mech("M_old", "T_A"), mech("M_new", "T_B")]
        inds = [ind("M_old", "D1"), ind("M_new", "D1")]
        self.assertEqual(tg.pre_pairs_by_disease(mols, mechs, inds, TARGETS, C, ["D1"]), {"D1": ["AAA"]})


class EvalLogic(unittest.TestCase):
    GOLD = {
        "meta": {"cutoff": "2024-06-30", "query_date": "2026-11-01"},
        "pairs": [
            {"pair_id": "D1|N1", "disease_id": "D1", "disease_name": "dis1", "target_symbol": "N1", "subset": "novel"},
            {"pair_id": "D1|I1", "disease_id": "D1", "disease_name": "dis1", "target_symbol": "I1", "subset": "new_indication"},
            {"pair_id": "D2|N2", "disease_id": "D2", "disease_name": "dis2", "target_symbol": "N2", "subset": "novel"},
        ],
        "pre_cutoff_approved_targets_global": ["P1", "P2"],
        "pre_cutoff_approved_targets_by_disease": {"D1": ["P1"]},
    }
    NEG = ["G%02d" % i for i in range(40)]

    def perfect(self, d, n):
        s = {t: 0.01 for t in self.NEG}
        for p in self.GOLD["pairs"]:
            if p["disease_id"] == d:
                s[p["target_symbol"]] = 1.0
        s["P1"] = 0.9    # a pre-cut-off approved target; must be removed from D1 negatives
        s["P2"] = 0.9    # approved elsewhere; kept in 'all', removed in 'unapproved'
        return s

    def test_midranks_and_auroc(self):
        self.assertEqual(te.midranks_ascending([1, 2, 2, 3]), [1.0, 2.5, 2.5, 4.0])
        self.assertEqual(te.auroc_from_labels([1, 2, 3, 4], [0, 0, 1, 1]), 1.0)
        self.assertEqual(te.auroc_from_labels([1, 1, 1, 1], [0, 0, 1, 1]), 0.5)
        self.assertIsNone(te.auroc_from_labels([1, 2], [1, 1]))

    def test_perfect_channel_beats_null_and_random_does_not(self):
        rnd = random_scores(self.NEG + ["P1", "P2", "N1", "I1", "N2"], seed=3)
        rep = te.run_eval(self.GOLD, {"perfect": self.perfect, "random": lambda d, n: rnd}, n_perm=200)
        nov = rep["results"]["novel|all"]
        self.assertEqual(nov["perfect"]["macro_auroc"], 1.0)
        self.assertLess(nov["perfect"]["perm_p_macro_auroc"], 0.05)
        self.assertEqual(nov["perfect"]["n_pairs"], 2)
        self.assertLess(nov["random"]["macro_auroc"], 0.98)
        self.assertEqual(nov["perfect"]["hit_at_k"]["10"]["hits"], 2)

    def test_subsets_are_separate(self):
        rep = te.run_eval(self.GOLD, {"perfect": self.perfect}, n_perm=50)
        self.assertEqual(rep["results"]["novel|all"]["perfect"]["n_pairs"], 2)
        self.assertEqual(rep["results"]["new_indication|all"]["perfect"]["n_pairs"], 1)
        self.assertEqual(rep["results"]["all_post|all"]["perfect"]["n_pairs"], 3)

    def test_negative_policies(self):
        subsets = te.gold_subsets(self.GOLD)
        scores = self.perfect("D1", "dis1")
        a = te.build_sets(self.GOLD, scores, [], "D1", "novel", "all", subsets)
        u = te.build_sets(self.GOLD, scores, [], "D1", "novel", "unapproved", subsets)
        self.assertNotIn("P1", a.items)          # approved for D1 pre-cut-off: never a negative
        self.assertNotIn("I1", a.items)          # other post-cut-off positive: never a negative
        self.assertIn("P2", a.items)             # approved elsewhere: negative under 'all'
        self.assertNotIn("P2", u.items)          # ...but removed under 'unapproved'

    def test_unscored_gold_ranks_last_and_is_reported(self):
        def partial(d, n):
            s = {t: 0.5 for t in self.NEG}
            return s                              # scores no gold at all
        rep = te.run_eval(self.GOLD, {"blind": partial}, n_perm=50)
        r = rep["results"]["novel|all"]["blind"]
        self.assertEqual(r["gold_scored_by_channel"], "0/2")
        self.assertEqual(r["macro_auroc"], 0.0)

    def test_channel_object_and_precomputed_dict(self):
        class Fake:
            def run(self, ctx):
                class R:
                    scores = {"N1": 1.0, "G00": 0.1} if ctx["disease_id"] == "D1" else {"N2": 1.0, "G00": 0.1}
                return R()
        pre = {"D1": {"N1": 5.0, "G00": 1.0}, "D2": {"N2": 5.0, "G00": 1.0}}
        rep = te.run_eval(self.GOLD, {"obj": Fake(), "pre": pre}, baseline=lambda d, n: {"G00": 1.0, "G01": 0.5}, n_perm=50)
        self.assertEqual(rep["results"]["novel|all"]["obj"]["macro_auroc"], 1.0)
        self.assertEqual(rep["results"]["novel|all"]["pre"]["macro_auroc"], 1.0)
        self.assertIn("pre", rep["vs_baseline"]["novel|all"])
        self.assertGreater(rep["vs_baseline"]["novel|all"]["pre"]["mean_auroc_diff"], 0)

    def test_failing_channel_is_a_miss_not_a_crash(self):
        def boom(d, n):
            raise RuntimeError("x")
        rep = te.run_eval(self.GOLD, {"boom": boom, "ok": self.perfect}, n_perm=20)
        self.assertEqual(rep["coverage"]["boom"]["errors"], 2)

    def test_format_report_runs(self):
        rep = te.run_eval(self.GOLD, {"perfect": self.perfect}, n_perm=20)
        self.assertIn("macroAUROC", te.format_report(rep))


def random_scores(keys, seed=0):
    import random
    r = random.Random(seed)
    return {k: r.random() for k in keys}


if __name__ == "__main__":
    unittest.main()
