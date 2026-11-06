import json
import os
import sqlite3
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import repair_workflow_chains as R  # noqa: E402


class RepairTest(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        self.db = os.path.join(self.d, "t.db")
        c = sqlite3.connect(self.db)
        c.execute("CREATE TABLE workflows (id INTEGER PRIMARY KEY, name TEXT, filename TEXT, executable INTEGER)")
        c.execute("CREATE TABLE workflow_chains (id INTEGER PRIMARY KEY, name TEXT UNIQUE, steps TEXT, connections TEXT, updated_at TEXT)")
        c.execute("INSERT INTO workflows VALUES (1,'dock','a/dock/main.nf',1)")
        c.execute("INSERT INTO workflows VALUES (2,'old','a/old/main.nf',0)")
        steps = [{"order": 1, "workflow_name": "up"}, {"order": 2, "workflow_name": "dock_x"}]
        conns = [{"from_step": 1, "from_output": "vcf", "to_step": 2, "to_input": "vcf"}]
        c.execute("INSERT INTO workflow_chains VALUES (1,'ch',?,?,'old')", (json.dumps(steps), json.dumps(conns)))
        c.commit()
        c.close()
        self.spec = os.path.join(self.d, "spec.json")
        self._write_spec("vcf", "input", 1)

    def _write_spec(self, old, new, wid):
        spec = {"chains": {"ch": {
            "connections": [{"from_step": 1, "from_output": "vcf", "to_step": 2, "old_to_input": old, "new_to_input": new}],
            "steps": [{"order": 2, "workflow_id": wid, "workflow_name": "dock_x"}]}}}
        json.dump(spec, open(self.spec, "w"))

    def _state(self):
        c = sqlite3.connect(self.db)
        r = c.execute("SELECT steps, connections, updated_at FROM workflow_chains").fetchone()
        c.close()
        return json.loads(r[0]), json.loads(r[1]), r[2]

    def run_(self, dry):
        return R.run(self.db, self.spec, dry, self.d, out=lambda *_: None)

    def test_dry_run_noop(self):
        before = self._state()
        n, drift, backup = self.run_(True)
        self.assertEqual((n, drift, backup), (2, 0, None))
        self.assertEqual(before, self._state())
        self.assertEqual([f for f in os.listdir(self.d) if "pre_chain_repair" in f], [])

    def test_apply_and_idempotent(self):
        n, drift, backup = self.run_(False)
        self.assertEqual((n, drift), (2, 0))
        self.assertTrue(os.path.exists(backup))
        steps, conns, upd = self._state()
        self.assertEqual(conns[0]["to_input"], "input")
        self.assertEqual(steps[1]["workflow_id"], 1)
        self.assertNotEqual(upd, "old")
        n2, d2, b2 = self.run_(False)
        self.assertEqual((n2, d2, b2), (0, 0, None))

    def test_drift_refused(self):
        self._write_spec("something_else", "input", 1)
        n, drift, _ = self.run_(False)
        self.assertEqual(drift, 1)
        steps, conns, _ = self._state()
        self.assertEqual(conns[0]["to_input"], "vcf")  # connection untouched
        self.assertEqual(n, 1)                          # the step pin is still valid

    def test_non_executable_pin_refused(self):
        self._write_spec("vcf", "input", 2)
        n, drift, _ = self.run_(True)
        self.assertEqual((n, drift), (1, 1))


if __name__ == "__main__":
    unittest.main()
