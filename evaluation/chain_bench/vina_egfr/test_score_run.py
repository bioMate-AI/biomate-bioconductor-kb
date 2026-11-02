"""Offline unit tests (synthetic scores). Run: python -m pytest test_score_run.py  or  python test_score_run.py"""
import csv, json, os, sys, tempfile, unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import score_run as S


def mk(tmp, labs, scores):
    """labs: list of labels; scores: dict idx->kcal or None. SMILES are 'C'*(i+1) strings."""
    lp, dp = os.path.join(tmp, "labels.csv"), os.path.join(tmp, "res.json")
    with open(lp, "w", newline="") as f:
        w = csv.writer(f); w.writerow(["smiles", "id", "label", "source"])
        for i, l in enumerate(labs):
            w.writerow(["C" * (i + 1), "m%d" % i, l, "t"])
    res = []
    for i in range(len(labs)):
        sc = scores.get(i)
        res.append({"smiles": "C" * (i + 1), "best_affinity_kcal_mol": sc} if sc is not None
                   else {"smiles": "C" * (i + 1), "error": "dock failed"})
    with open(dp, "w") as f:
        json.dump({"results": res}, f)
    return dp, lp


class T(unittest.TestCase):
    def run_case(self, labs, scores, **kw):
        with tempfile.TemporaryDirectory() as t:
            dp, lp = mk(t, labs, scores)
            return S.score_run(dp, lp, n_perm=200, **kw)

    def test_perfect(self):
        labs = ["active"] * 5 + ["decoy"] * 15
        sc = {i: -10.0 - (5 - i) if i < 5 else -5.0 + i * 0.01 for i in range(20)}
        r = self.run_case(labs, sc)
        self.assertEqual(r["auroc"], 1.0)
        self.assertLess(r["perm_p_value_auroc_ge_observed"], 0.05)

    def test_inverted(self):
        labs = ["active"] * 5 + ["decoy"] * 15
        sc = {i: -5.0 if i < 5 else -10.0 - i * 0.01 for i in range(20)}
        self.assertEqual(self.run_case(labs, sc)["auroc"], 0.0)

    def test_random_about_half(self):
        import random
        rng = random.Random(1)
        labs = ["active"] * 100 + ["decoy"] * 300
        sc = {i: -rng.uniform(4, 11) for i in range(400)}
        r = self.run_case(labs, sc)
        self.assertAlmostEqual(r["auroc"], 0.5, delta=0.07)
        self.assertGreater(r["perm_p_value_auroc_ge_observed"], 0.05)

    def test_unscored_actives_are_misses_and_reference_excluded(self):
        labs = ["active"] * 4 + ["decoy"] * 4 + ["reference"]
        sc = {0: -9, 1: -9, 4: -5, 5: -5, 6: -5, 7: -5, 8: -12}  # actives 2,3 unscored
        r = self.run_case(labs, sc)
        self.assertEqual(r["unscored_actives_counted_as_misses"], 2)
        self.assertEqual(r["n_reference_excluded"], 1)
        self.assertEqual(r["n_library_scored_set"], 8)
        # actives 0,1 beat all decoys (1.0 each); actives 2,3 below all decoys (0.0): AUROC 0.5
        self.assertAlmostEqual(r["auroc"], 0.5)

    def test_ef_hand_computed(self):
        # 20 compounds, 2 actives. ranked: active, decoys..., active at rank 10.
        # top1% -> n_top=1 (ceil 0.2): hits=1 -> EF=(1/1)/(2/20)=10.
        # top5% -> n_top=1 as well; top 50%: n_top=10 hits=2 -> (2/10)/(0.1)=2
        labs = [1] * 2 + [0] * 18
        scores = [0.0] * 20
        scores[0] = 100.0; scores[1] = 50.0
        for i in range(2, 20): scores[i] = 49.0 - i  # active #2 (idx1) is rank 2
        ef, hits, n = S.enrichment_factor(scores, labs, 0.01)
        self.assertEqual((n, hits), (1, 1)); self.assertAlmostEqual(ef, 10.0)
        ef, hits, n = S.enrichment_factor(scores, labs, 0.5)
        self.assertEqual((n, hits), (10, 2)); self.assertAlmostEqual(ef, 2.0)

    def test_missing_files(self):
        with self.assertRaises(S.ScoreError):
            S.score_run("/nonexistent.json", "/nonexistent.csv")

    def test_rmsd(self):
        with tempfile.TemporaryDirectory() as t:
            def pdb(path, shift):
                with open(path, "w") as f:
                    for i, (el, x) in enumerate([("C", 0.0), ("N", 1.5), ("O", 3.0)]):
                        f.write("HETATM%5d %-4s LIG A   1    %8.3f%8.3f%8.3f  1.00  0.00          %2s\n"
                                % (i + 1, el + str(i + 1), x + shift, 0.0, 0.0, el))
                    f.write("END\n")
            a, b, c = [os.path.join(t, n) for n in ("a.pdb", "b.pdb", "c.pdb")]
            pdb(a, 0.0); pdb(b, 0.0); pdb(c, 1.0)
            self.assertAlmostEqual(S.redock_rmsd(b, a), 0.0)
            self.assertAlmostEqual(S.redock_rmsd(c, a), 1.0)
            self.assertAlmostEqual(S.redock_rmsd(c, a, "nearest"), 1.0, delta=1.0)
            self.assertLess(S.redock_rmsd(c, a), 2.0)

    def test_real_crystal_self_rmsd(self):
        p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data", "erlotinib_crystal_ligand.pdb")
        if os.path.exists(p):
            self.assertAlmostEqual(S.redock_rmsd(p, p), 0.0)
            self.assertEqual(len(S._read_heavy_coords(p)), 29)


if __name__ == "__main__":
    unittest.main()
