"""A completed run's output file becomes hospital evidence automatically, from a confined folder only."""
import gzip
import os
import tempfile
import unittest

from galaxy.ai.target_id import TargetIDOrchestrator, build_client_channels
from galaxy.ai.target_id.analysis_outputs import detect, spec_from_run_output, specs_from_run_outputs


def write(root, name, text, gz=False):
    p = os.path.join(root, name)
    if gz:
        with gzip.open(p, "wt") as fh:
            fh.write(text)
    else:
        with open(p, "w") as fh:
            fh.write(text)
    return name


DESEQ = ',baseMean,log2FoldChange,lfcSE,stat,pvalue,padj\nBRAF,900,3.5,0.2,15,1e-30,1e-28\nTP53,500,-1.0,0.2,-5,1e-6,1e-5\nGAPDH,9000,0.01,0.05,0.2,0.8,0.9\n'
EDGER = 'gene_name\tlogFC\tlogCPM\tF\tPValue\tFDR\nBRAF\t4.0\t8\t90\t1e-9\t1e-8\nMYC\t2.0\t7\t30\t1e-5\t1e-4\n'
LIMMA = 'Gene.symbol,logFC,AveExpr,t,P.Value,adj.P.Val,B\nERBB2,3.0,9,12,1e-9,1e-8,12\nESR1,-2,8,-9,1e-8,1e-7,10\n'
COX = 'gene,HR,p\nMYC,1.8,1e-4\nTP53,0.6,1e-3\n'


class DetectTests(unittest.TestCase):
    def test_header_signatures(self):
        self.assertEqual(detect(["", "baseMean", "log2FoldChange", "padj"])[:2], ("DESeq2 results", "differential_expression_up"))
        self.assertEqual(detect(["gene_name", "logFC", "FDR"])[0], "edgeR results")
        self.assertEqual(detect(["Gene.symbol", "logFC", "adj.P.Val"])[0], "limma results")
        self.assertEqual(detect(["gene", "HR", "p"])[1], "survival_adverse")
        self.assertEqual(detect(["gene", "exp(coef)", "Pr(>|z|)"])[2], {"hr": "exp(coef)", "p": "Pr(>|z|)"})
        self.assertIsNone(detect(["a", "b"]))


class ConvertTests(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.TemporaryDirectory(); self.root = self.d.name
    def tearDown(self):
        self.d.cleanup()

    def test_deseq2_with_unnamed_first_column_scores_like_the_adapter_formula(self):
        write(self.root, "deseq.csv", DESEQ)
        spec = spec_from_run_output({"path": "deseq.csv", "source_run_id": "run-42"}, root=self.root)
        self.assertEqual((spec["kind"], spec["columns"]["gene"], spec["source_run_id"], spec["label"]), ("differential_expression_up", "", "run-42", "DESeq2 results"))
        s = build_client_channels([spec])[0].run({}).scores
        self.assertAlmostEqual(s["BRAF"], 0.875 * 1.0)                    # min(1, 3.5/4) x min(1, 28/5)
        self.assertEqual((s["TP53"], s["GAPDH"]), (0.0, 0.0))             # down-regulated / not significant

    def test_edger_tsv_limma_and_cox_and_gzip(self):
        write(self.root, "edger.tsv", EDGER); write(self.root, "limma.csv", LIMMA); write(self.root, "cox.csv", COX); write(self.root, "deseq.csv.gz", DESEQ, gz=True)
        specs = specs_from_run_outputs([{"path": "edger.tsv"}, {"path": "limma.csv", "name": "L"}, {"path": "cox.csv"}, {"path": "deseq.csv.gz"}], root=self.root)
        self.assertEqual([s["kind"] for s in specs], ["differential_expression_up", "differential_expression_up", "survival_adverse", "differential_expression_up"])
        chans = build_client_channels(specs)
        edger = chans[0].run({}).scores
        self.assertAlmostEqual(edger["BRAF"], 1.0)                              # min(1, 4/4) x min(1, 8/5)
        self.assertAlmostEqual(edger["MYC"], 0.5 * 0.8)                         # min(1, 2/4) x (-log10(1e-4)/5)
        self.assertAlmostEqual(chans[2].run({}).scores["MYC"], 0.8)          # -log10(1e-4)/5
        self.assertIn("ERBB2", chans[1].run({}).scores)

    def test_end_to_end_ranking_uses_the_run_output(self):
        write(self.root, "deseq.csv", DESEQ)
        chans = build_client_channels(specs_from_run_outputs([{"path": "deseq.csv", "label": "NPC tumour vs normal"}], root=self.root))
        res = TargetIDOrchestrator(chans).identify("q").to_dict()
        top = res["targets"][0]
        self.assertEqual(top["target"], "BRAF")
        self.assertIn("NPC tumour vs normal", top["evidence_links"][chans[0].name]["label"])

    def test_refusals(self):
        write(self.root, "ens.csv", "gene_id,log2FoldChange,padj\nENSG00000157764,3,1e-9\nENSG00000147889,2,1e-5\n")
        write(self.root, "odd.csv", "a,b\n1,2\n")
        outside = tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False); outside.write(DESEQ); outside.close()
        cases = [({"path": "ens.csv"}, "Ensembl ids"), ({"path": "odd.csv"}, "format not recognised"), ({"path": "missing.csv"}, "not found"),
                 ({"path": outside.name}, "outside the allowed folder"), ({"path": "../" + os.path.basename(outside.name)}, "outside the allowed folder"), ({}, "needs a path")]
        for ro, frag in cases:
            with self.assertRaises(ValueError, msg=str(ro)) as cm:
                spec_from_run_output(ro, root=self.root)
            self.assertIn(frag, str(cm.exception))
        os.unlink(outside.name)
        os.environ.pop("TARGET_ID_RUN_OUTPUT_ROOT", None)
        with self.assertRaises(ValueError) as cm:
            spec_from_run_output({"path": "deseq.csv"})
        self.assertIn("disabled", str(cm.exception))

    def test_manual_mapping_for_unrecognised_formats(self):
        write(self.root, "odd.csv", "symbol,lfc,q\nBRAF,3,1e-9\n")
        spec = spec_from_run_output({"path": "odd.csv", "kind": "differential_expression_up", "columns": {"gene": "symbol", "log2fc": "lfc", "padj": "q"}}, root=self.root)
        self.assertEqual(build_client_channels([spec])[0].run({}).scores["BRAF"], 0.75)

    def test_row_limit(self):
        write(self.root, "big.csv", "gene,HR,p\n" + "\n".join("G%d,2,1e-3" % i for i in range(6)) + "\n")
        with self.assertRaises(ValueError):
            spec_from_run_output({"path": "big.csv"}, root=self.root, max_rows=3)


if __name__ == "__main__":
    unittest.main()
