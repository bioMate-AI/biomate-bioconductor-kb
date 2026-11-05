"""Cross-omics biomarker-driver ranking — the scoring step that makes the general
fuse_channels engine usable end-to-end for multi-omics stratification.

Builds synthetic layer matrices with a KNOWN cross-layer driver and confirms the
F-statistic scoring + fusion surfaces it as the top, corroborated biomarker.
"""
import unittest

from galaxy.ai.multiomics.biomarker_fusion import (
    rank_cross_omics_drivers,
    _f_statistic_per_feature,
)


def _layer(features, samples, label_of, hi_feature, sep=5.0):
    """A features x samples matrix where `hi_feature` separates the two subtypes
    and every other feature is flat noise-free baseline (F≈0)."""
    values = []
    for f in features:
        row = []
        for s in samples:
            if f == hi_feature:
                row.append(sep if label_of[s] == "A" else 0.0)
            else:
                row.append(1.0 + (0.01 if label_of[s] == "A" else -0.01))  # near-flat
        values.append(row)
    return {"features": features, "samples": samples, "values": values}


class CrossOmicsDriverTest(unittest.TestCase):
    def setUp(self):
        self.samples = [f"P{i}" for i in range(20)]
        self.label = {s: ("A" if i % 2 == 0 else "B") for i, s in enumerate(self.samples)}
        # DRV is the strong separating feature in BOTH rna and protein (corroborated);
        # SOLO separates only in methyl (nominated, single layer).
        self.layers = {
            "rna":     _layer(["DRV", "r1", "r2"], self.samples, self.label, "DRV"),
            "protein": _layer(["DRV", "p1", "p2"], self.samples, self.label, "DRV"),
            "methyl":  _layer(["SOLO", "m1", "m2"], self.samples, self.label, "SOLO"),
        }

    def test_corroborated_driver_ranks_first(self):
        out = rank_cross_omics_drivers(self.layers, self.label)
        self.assertTrue(out)
        top = out[0]
        self.assertEqual(top["entity"], "DRV")           # strong in rna + protein
        self.assertGreaterEqual(top["n_fired"], 2)        # corroborated across layers
        self.assertIn("rna", top["fired_channels"])
        self.assertIn("protein", top["fired_channels"])

    def test_single_layer_driver_is_nominated_not_corroborated(self):
        out = rank_cross_omics_drivers(self.layers, self.label)
        solo = next((r for r in out if r["entity"] == "SOLO"), None)
        self.assertIsNotNone(solo)
        self.assertEqual(solo["n_fired"], 1)              # only methyl

    def test_fstat_scores_driver_above_flat(self):
        fvals = _f_statistic_per_feature(
            self.layers["rna"]["values"], self.samples, self.label)
        # DRV is feature index 0; r1/r2 are near-flat.
        self.assertGreater(fvals[0], fvals[1])
        self.assertGreater(fvals[0], fvals[2])

    def test_empty_and_unlabeled_inputs(self):
        self.assertEqual(rank_cross_omics_drivers({}, self.label), [])
        # No labels → every feature F=0 → nothing fires.
        out = rank_cross_omics_drivers(self.layers, {})
        self.assertTrue(all(r.get("n_fired", 0) == 0 for r in out) or out == [])

    def test_top_k_limits_results(self):
        out = rank_cross_omics_drivers(self.layers, self.label, top_k=1)
        self.assertEqual(len(out), 1)
        self.assertEqual(out[0]["entity"], "DRV")

    def test_permutation_significance_separates_true_from_null(self):
        # With TRUE labels the strong driver DRV is significant under the label-
        # permutation null; with RANDOM labels (almost) nothing is significant —
        # the negative control the plain `corroborated` tier fails (it over-calls
        # each layer's relative top tail even on noise). Max-statistic FWER control.
        import random
        true = rank_cross_omics_drivers(self.layers, self.label, n_perm=40, alpha=0.05)
        drv = next((r for r in true if r["entity"] == "DRV"), None)
        self.assertIsNotNone(drv)
        self.assertTrue(drv.get("significant"))
        self.assertLessEqual(drv.get("perm_p", 1.0), 0.05)
        vals = list(self.label.values()); keys = list(self.label.keys())
        random.Random(0).shuffle(vals)
        rnd = rank_cross_omics_drivers(self.layers, dict(zip(keys, vals)),
                                       n_perm=40, alpha=0.05)
        self.assertLessEqual(sum(1 for r in rnd if r.get("significant")), 1)


# ── drivers_from_run: findings-hook orchestration (cluster CSV + omics URIs ->
#    drivers) with an injected reader so it is unit-testable with no network. ──
class DriversFromRunTest(unittest.TestCase):
    def setUp(self):
        self.samples = [f"P{i}" for i in range(20)]
        self.label = {s: ("1" if i % 2 == 0 else "2") for i, s in enumerate(self.samples)}
        # snf_clusters.csv shape: "sample","cluster"
        self.cluster_csv = '"sample","cluster"\n' + "\n".join(
            f'"{s}",{self.label[s]}' for s in self.samples)

        def _matrix_csv(features, hi):
            head = "feature," + ",".join(self.samples)
            lines = [head]
            for f in features:
                vals = []
                for s in self.samples:
                    if f == hi:
                        vals.append("5.0" if self.label[s] == "1" else "0.0")
                    else:
                        vals.append("1.01" if self.label[s] == "1" else "0.99")
                lines.append(f + "," + ",".join(vals))
            return "\n".join(lines)

        self._store = {
            "s3://b/rna.csv":     _matrix_csv(["DRV", "r1"], "DRV"),
            "s3://b/protein.csv": _matrix_csv(["DRV", "p1"], "DRV"),
            "s3://b/methyl.csv":  _matrix_csv(["SOLO", "m1"], "SOLO"),
        }

    def _fetch(self, uri):
        return self._store[uri]

    def test_drivers_from_run_ranks_corroborated_first(self):
        out = drivers_from_run(self.cluster_csv, list(self._store), fetch_text=self._fetch)
        self.assertTrue(out)
        self.assertEqual(out[0]["entity"], "DRV")
        self.assertGreaterEqual(out[0]["n_fired"], 2)

    def test_needs_two_layers(self):
        out = drivers_from_run(self.cluster_csv, ["s3://b/rna.csv"], fetch_text=self._fetch)
        self.assertEqual(out, [])

    def test_no_labels_or_no_uris(self):
        self.assertEqual(drivers_from_run("", list(self._store), fetch_text=self._fetch), [])
        self.assertEqual(drivers_from_run(self.cluster_csv, [], fetch_text=self._fetch), [])

    def test_bad_layer_is_skipped_not_fatal(self):
        def flaky(uri):
            if uri == "s3://b/protein.csv":
                raise IOError("staging failed")
            return self._store[uri]
        out = drivers_from_run(self.cluster_csv, list(self._store), fetch_text=flaky)
        self.assertTrue(out)                         # rna + methyl still fuse


class ParserTest(unittest.TestCase):
    def test_parse_cluster_csv_aliases(self):
        from galaxy.ai.multiomics.biomarker_fusion import _parse_cluster_csv
        d = _parse_cluster_csv('"sample","cluster"\n"P0",2\n"P1",1\n')
        self.assertEqual(d, {"P0": "2", "P1": "1"})
        d2 = _parse_cluster_csv("patient,subtype\nX,A\nY,B\n")
        self.assertEqual(d2, {"X": "A", "Y": "B"})

    def test_parse_feature_matrix(self):
        from galaxy.ai.multiomics.biomarker_fusion import _parse_feature_matrix
        m = _parse_feature_matrix("feature,P0,P1\nGENE0,1.0,2.0\nGENE1,3.0,4.0\n")
        self.assertEqual(m["features"], ["GENE0", "GENE1"])
        self.assertEqual(m["samples"], ["P0", "P1"])
        self.assertEqual(m["values"], [[1.0, 2.0], [3.0, 4.0]])


if __name__ == "__main__":
    unittest.main()
