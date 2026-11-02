#!/usr/bin/env python3
"""Offline tests for scripts/lint_workflow_chains.py using a tiny temp SQLite DB and fake workflow files."""
import contextlib
import importlib.util
import io
import json
import os
import sqlite3
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("lint_workflow_chains", os.path.join(HERE, "lint_workflow_chains.py"))
lint = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lint)


class LintTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = os.path.join(self.tmp.name, "wf")
        self.db = os.path.join(self.tmp.name, "t.db")
        c = sqlite3.connect(self.db)
        c.execute("create table workflow_chains(name text, domain text, source text, usage_count int, steps text, connections text)")
        c.execute("create table workflows(id integer primary key, name text, filename text, executable int)")
        c.commit()
        self.c = c
        self.n = 0
        self.wf("alpha", "params.reads = null\n")
        self.wf("beta", "params.counts = null\n", schema={"properties": {"genome": {}}})
        self.wf("nofile", None)  # row exists, main.nf missing -> undeterminable

    def tearDown(self):
        self.c.close()
        self.tmp.cleanup()

    def wf(self, name, body, schema=None):
        self.n += 1
        d = os.path.join(self.root, name)
        os.makedirs(d, exist_ok=True)
        if body is not None:
            with open(os.path.join(d, "main.nf"), "w") as f:
                f.write(body)
        if schema:
            with open(os.path.join(d, "nextflow_schema.json"), "w") as f:
                json.dump(schema, f)
        self.c.execute("insert into workflows values(?,?,?,1)", (self.n, name, "%s/main.nf" % name))
        self.c.commit()

    def chain(self, name, steps, conns):
        self.c.execute("insert into workflow_chains values(?,?,?,?,?,?)", (name, "d", "s", 0,
                       json.dumps([{"workflow_name": s} for s in steps]), json.dumps(conns)))
        self.c.commit()

    def run_lint(self, req):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = lint.main(["--db", self.db, "--workflows-root", self.root, "--required-clean", req])
        return rc, buf.getvalue()

    def test_clean_passes(self):
        self.chain("ok", ["alpha", "beta"], [{"from_step": 1, "to_step": 2, "to_input": "counts"}])
        rc, out = self.run_lint("ok")
        self.assertEqual(rc, 0, out)
        self.assertTrue(out.strip().splitlines()[-1].startswith("PASS"))

    def test_schema_param_counts_as_declared(self):
        self.chain("ok", ["alpha", "beta"], [{"from_step": 1, "to_step": 2, "to_input": "genome"}])
        self.assertEqual(self.run_lint("ok")[0], 0)

    def test_unresolved_step_fails(self):
        self.chain("bad", ["alpha", "does_not_exist_zzz"], [])
        rc, out = self.run_lint("bad")
        self.assertEqual(rc, 1)
        self.assertIn("unresolved", out)
        self.assertTrue(out.strip().splitlines()[-1].startswith("FAIL"))

    def test_mismatching_to_input_fails(self):
        self.chain("bad", ["alpha", "beta"], [{"from_step": 1, "to_step": 2, "to_input": "wrong_name"}])
        rc, out = self.run_lint("bad")
        self.assertEqual(rc, 1)
        self.assertIn("wrong_name", out)

    def test_undeterminable_only_warns(self):
        self.chain("warn", ["alpha", "nofile"], [{"from_step": 1, "to_step": 2, "to_input": "anything"}])
        rc, out = self.run_lint("warn")
        self.assertEqual(rc, 0, out)
        self.assertIn("WARN undeterminable", out)
        self.assertIn("1 warning", out)

    def test_missing_required_chain_fails(self):
        rc, out = self.run_lint("not_in_db")
        self.assertEqual(rc, 1)
        self.assertIn("missing from DB", out)

    def test_non_required_broken_chain_not_enforced(self):
        self.chain("ok", ["alpha"], [])
        self.chain("other", ["alpha", "nope_zzz"], [])
        rc, out = self.run_lint("ok")
        self.assertEqual(rc, 0, out)
        self.assertIn("1 with unresolved", out)


if __name__ == "__main__":
    unittest.main()
