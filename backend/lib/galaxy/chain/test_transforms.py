"""Offline tests for galaxy.chain.transforms, binding_check transform support,
and the transform handoff / pre-launch failure in workflow_chain."""
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from galaxy.chain import binding_check as bc
from galaxy.chain import transforms as tf
from galaxy.chain.test_binding_check import _load_workflow_chain, _wf


class _TmpCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, name, text):
        p = self.root / name
        p.write_text(text)
        return str(p)


class SmilesTransformTest(_TmpCase):
    def run_t(self, text, args=None, name="s.smi"):
        return json.loads(tf.apply("smiles_file_to_json_list", self.write(name, text), args))

    def test_plain_lines_comments_blank_dupes(self):
        out = self.run_t("# lib\nCCO\n\nc1ccccc1\nCCO\n  CC(=O)O  \n")
        self.assertEqual(out, ["CCO", "c1ccccc1", "CC(=O)O"])

    def test_returns_string(self):
        self.assertIsInstance(tf.apply("smiles_file_to_json_list", self.write("a", "CCO\n")), str)

    def test_smi_with_names(self):
        self.assertEqual(self.run_t("CCO ethanol\nCCN ethylamine\n"), ["CCO", "CCN"])

    def test_csv_header(self):
        self.assertEqual(self.run_t("id,SMILES,mw\n1,CCO,46\n2,CCN,45\n3,CCO,46\n", name="a.csv"),
                         ["CCO", "CCN"])

    def test_tsv_canonical_column(self):
        self.assertEqual(self.run_t("name\tcanonical_smiles\nx\tC1CC1\ny\tCCC\n", name="a.tsv"),
                         ["C1CC1", "CCC"])

    def test_args_column(self):
        self.assertEqual(self.run_t("id,mol\n1,CCO\n", {"column": "mol"}, name="a.csv"), ["CCO"])

    def test_bad_column(self):
        with self.assertRaises(tf.TransformError):
            self.run_t("id,mol\n1,CCO\n", {"column": "nope"}, name="a.csv")

    def test_empty_and_comment_only(self):
        for text in ("", "\n\n", "# only\n"):
            with self.assertRaises(tf.TransformError):
                self.run_t(text)

    def test_header_no_rows(self):
        with self.assertRaises(tf.TransformError):
            self.run_t("id,smiles\n", name="a.csv")

    def test_missing_file(self):
        with self.assertRaises(tf.TransformError):
            tf.apply("smiles_file_to_json_list", str(self.root / "nope.smi"))
        with self.assertRaises(tf.TransformError):
            tf.apply("smiles_file_to_json_list", "")

    def test_over_max_errors_not_truncates(self):
        text = "\n".join("C" * (i + 1) for i in range(12))
        with self.assertRaises(tf.TransformError) as cm:
            self.run_t(text, {"max": 10})
        self.assertIn("max=10", str(cm.exception))
        self.assertEqual(len(self.run_t(text, {"max": 12})), 12)

    def test_default_max_5000(self):
        text = "\n".join("C" * (i + 1) for i in range(5001))
        with self.assertRaises(tf.TransformError):
            self.run_t(text)

    def test_unknown_transform(self):
        with self.assertRaises(tf.TransformError):
            tf.apply("nope", "x")


def _pockets(*ps):
    return json.dumps({"target": "1M17", "tool": "biotite_geometric", "version": "2.6",
                       "num_pockets": len(ps), "pockets": list(ps), "timestamp": "2026-11-01T00:00:00Z"})


def _p(i, vol, drug, x, y, z):
    return {"pocket_id": i, "volume_A3": vol, "druggability_score": drug, "hydrophobicity": 0.4,
            "polarity": 0.3, "center_x": x, "center_y": y, "center_z": z}


class PocketTransformTest(_TmpCase):
    def test_top_by_druggability(self):
        f = self.write("p.json", _pockets(_p(1, 500, 0.8, 1.5, 2.5, 3.5), _p(2, 900, 0.6, 9, 9, 9)))
        r = tf.apply("pocket_json_to_box_center", f)
        self.assertEqual(r["box_center"], [1.5, 2.5, 3.5])
        self.assertEqual((r["pocket_rank"], r["n_pockets"]), (1, 2))
        self.assertEqual(len(r["box_size"]), 3)
        self.assertTrue(20.0 <= r["box_size"][0] <= 40.0)
        self.assertIn("druggability", r["selection"])

    def test_tie_by_volume(self):
        f = self.write("p.json", _pockets(_p(1, 400, 0.7, 1, 1, 1), _p(2, 800, 0.7, 5, 6, 7)))
        r = tf.apply("pocket_json_to_box_center", f)
        self.assertEqual(r["box_center"], [5.0, 6.0, 7.0])
        self.assertEqual(r["pocket_rank"], 2)

    def test_failures(self):
        for text in (_pockets(), "{}", "not json", "[1,2]", _pockets({"pocket_id": 1})):
            with self.assertRaises(tf.TransformError):
                tf.apply("pocket_json_to_box_center", self.write("p.json", text))


class BindingCheckTransformTest(_TmpCase):
    def setUp(self):
        super().setUp()
        _wf(self.root, "down", "workflow { println params.smiles_list }")
        self.steps = [{"nextflow_path": "up/main.nf"}, {"nextflow_path": "down/main.nf", "workflow_name": "Down"}]

    def conn(self, transform):
        return [{"from_step": 1, "to_step": 2, "from_output": "x", "to_input": "smiles_list",
                 "transform": transform}]

    def test_registered_ok(self):
        for t in ({"name": "smiles_file_to_json_list"}, "smiles_file_to_json_list"):
            p, u = bc.check_connections(self.steps, self.conn(t), roots=[self.root])
            self.assertEqual((p, u), ([], []))

    def test_unknown_rejected(self):
        p, _ = bc.check_connections(self.steps, self.conn({"name": "bogus"}), roots=[self.root])
        self.assertEqual(len(p), 1)
        self.assertIn("unknown transform 'bogus'", p[0]["message"])

    def test_registered_but_undeclared_input_still_problem(self):
        c = self.conn({"name": "smiles_file_to_json_list"})
        c[0]["to_input"] = "other"
        p, _ = bc.check_connections(self.steps, c, roots=[self.root])
        self.assertEqual(len(p), 1)


class HandoffTest(_TmpCase):
    def state(self, to_input, transform, nf_text):
        _wf(self.root, "down", nf_text)
        return {
            "connections": [{"from_step": 1, "to_step": 2, "from_output": "x", "to_input": to_input,
                             "transform": transform}],
            "steps": [{"run_id": "r1", "nextflow_path": "up/main.nf"},
                      {"nextflow_path": str(self.root / "down" / "main.nf"), "params": {}}],
        }

    def handoff(self, state, files):
        wc = _load_workflow_chain(self)
        with mock.patch.object(wc, "_list_run_output_files", return_value=files):
            return wc._apply_connection_handoffs(state, 1, {})

    def test_str_transform(self):
        f = self.write("lib.smi", "CCO\nCCN\n")
        st = self.state("smiles_list", {"name": "smiles_file_to_json_list"}, "println params.smiles_list")
        params, warns = self.handoff(st, [{"filename": "lib.smi", "path": f, "extension": "smi"}])
        self.assertEqual(json.loads(params["smiles_list"]), ["CCO", "CCN"])
        self.assertNotIn("transform_error", st["steps"][1])

    def test_dict_transform_wires_declared_keys_only(self):
        f = self.write("x_pockets.json", _pockets(_p(1, 500, 0.8, 1.5, 2.5, 3.5)))
        st = self.state("box_center", {"name": "pocket_json_to_box_center"},
                        "println params.box_center; println params.box_size")
        params, _ = self.handoff(st, [{"filename": "x_pockets.json", "path": f, "extension": "json"}])
        self.assertEqual(json.loads(params["box_center"]), [1.5, 2.5, 3.5])
        self.assertIn("box_size", params)
        self.assertNotIn("pocket_rank", params)
        self.assertNotIn("selection", params)

    def test_dict_transform_skips_undeclared_box_size(self):
        f = self.write("x_pockets.json", _pockets(_p(1, 500, 0.8, 1.5, 2.5, 3.5)))
        st = self.state("box_center", {"name": "pocket_json_to_box_center"}, "println params.box_center")
        params, _ = self.handoff(st, [{"filename": "x_pockets.json", "path": f, "extension": "json"}])
        self.assertNotIn("box_size", params)

    def test_transform_error_recorded(self):
        f = self.write("empty.smi", "# nothing\n")
        st = self.state("smiles_list", {"name": "smiles_file_to_json_list"}, "println params.smiles_list")
        params, warns = self.handoff(st, [{"filename": "empty.smi", "path": f, "extension": "smi"}])
        self.assertNotIn("smiles_list", params)
        self.assertTrue(any("transform failed" in w for w in warns))
        self.assertIn("empty", st["steps"][1]["transform_error"])

    def test_run_chain_fails_before_launch(self):
        wc = _load_workflow_chain(self)
        state = {
            "chain_run_id": "c1", "status": "running", "execution_mode": "sequential",
            "connections": [{"from_step": 1, "to_step": 2, "from_output": "x", "to_input": "smiles_list"}],
            "steps": [{"nextflow_path": "up/main.nf", "params": {}, "status": "succeeded", "run_id": "r1"},
                      {"nextflow_path": "down/main.nf", "params": {}, "status": "pending"}],
        }

        def fake_handoff(chain, idx, params):
            chain["steps"][idx]["transform_error"] = "bad smiles file"
            return params, ["transform failed"]

        with mock.patch.object(wc, "_get_chain", return_value=state), \
                mock.patch.object(wc, "_update_chain"), \
                mock.patch.object(wc, "_check_bindings", return_value=([], [])), \
                mock.patch.object(wc, "_apply_connection_handoffs", side_effect=fake_handoff), \
                mock.patch.object(wc, "execute_nextflow", create=True) as ex:
            wc._run_chain("c1", start_from_step=1)
        ex.assert_not_called()
        self.assertEqual(state["steps"][1]["status"], "failed")
        self.assertEqual(state["steps"][1]["error"], "bad smiles file")
        self.assertEqual(state["status"], "failed")


if __name__ == "__main__":
    unittest.main()
