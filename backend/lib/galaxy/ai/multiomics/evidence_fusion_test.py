"""Cross-omics biomarker fusion = a real 2nd consumer of the general fuse_channels
engine (Pattern A exercised beyond target-ID), and a spearhead biomarker capability."""
import unittest

from galaxy.ai.multiomics.evidence_fusion import fuse_omics_biomarkers


class CrossOmicsFusionTest(unittest.TestCase):
    def _layers(self):
        # 8 background genes at low evidence in every layer; GENEA strong in RNA +
        # proteomics (corroborated), GENEB strong only in methylation (nominated).
        bg = {f"GENE{i}": 1.0 for i in range(10, 18)}
        return {
            "rna":         dict({"GENEA": 9.0, "GENEB": 1.0}, **bg),
            "proteomics":  dict({"GENEA": 9.0, "GENEB": 1.0}, **bg),
            "methylation": dict({"GENEB": 9.0, "GENEA": 1.0}, **bg),
        }

    def test_corroborated_gene_ranks_first(self):
        out = fuse_omics_biomarkers(self._layers())
        self.assertTrue(out)
        top = out[0]
        self.assertEqual(top["entity"], "GENEA")          # strong in 2 layers
        self.assertEqual(top["rank"], 1)
        self.assertGreaterEqual(top["n_fired"], 2)         # corroborated across layers
        self.assertIn("rna", top["fired_channels"])
        self.assertIn("proteomics", top["fired_channels"])

    def test_features_are_generic_gene_names(self):
        out = fuse_omics_biomarkers(self._layers())
        self.assertTrue(all(r["entity"].startswith("GENE") for r in out))

    def test_harmonic_sum_with_per_layer_weights(self):
        out = fuse_omics_biomarkers(self._layers(), method="harmonic_sum",
                                    weights={"rna": 1.0, "proteomics": 1.0, "methylation": 0.5})
        self.assertEqual(out[0]["entity"], "GENEA")

    def test_top_k_and_empty_input(self):
        self.assertEqual(len(fuse_omics_biomarkers(self._layers(), top_k=3)), 3)
        self.assertEqual(fuse_omics_biomarkers({}), [])


if __name__ == "__main__":
    unittest.main()
