import json
import os
import shutil
import sqlite3
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import add_vina_bench_chain as A  # noqa: E402

SPEC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "config", "vina_bench_chain.json")


class AddChainTest(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.d, True)
        self.db = os.path.join(self.d, "t.db")
        spec = json.load(open(SPEC))
        c = sqlite3.connect(self.db)
        c.execute("CREATE TABLE workflows (id INTEGER PRIMARY KEY, name TEXT, filename TEXT, executable INTEGER)")
        for s in spec["steps"]:
            c.execute("INSERT INTO workflows VALUES (?,?,?,1)", (s["workflow_id"], s["workflow_name"], s["workflow_file"]))
        c.execute("""CREATE TABLE workflow_chains (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE,
            display_name TEXT NOT NULL, domain TEXT NOT NULL, description TEXT, steps TEXT NOT NULL DEFAULT '[]',
            connections TEXT NOT NULL DEFAULT '[]', required_inputs TEXT NOT NULL DEFAULT '[]',
            expected_outputs TEXT NOT NULL DEFAULT '[]', example_queries TEXT NOT NULL DEFAULT '[]',
            tags TEXT NOT NULL DEFAULT '[]', source TEXT NOT NULL DEFAULT 'curated', usage_count INTEGER NOT NULL DEFAULT 0,
            success_rate REAL NOT NULL DEFAULT 0.0, created_at TEXT, updated_at TEXT)""")
        c.commit()
        c.close()

    def run_(self, dry, spec=SPEC):
        return A.run(self.db, spec, dry, self.d, out=lambda *_: None)

    def row(self):
        c = sqlite3.connect(self.db)
        r = c.execute("SELECT steps, connections, usage_count FROM workflow_chains").fetchall()
        c.close()
        return r

    def test_dry_run_noop(self):
        self.assertEqual(self.run_(True), ("insert", None))
        self.assertEqual(self.row(), [])
        self.assertEqual([f for f in os.listdir(self.d) if "pre_vina" in f], [])

    def test_insert_then_idempotent(self):
        action, backup = self.run_(False)
        self.assertEqual(action, "insert")
        self.assertTrue(os.path.exists(backup))
        steps, conns, _ = self.row()[0]
        steps, conns = json.loads(steps), json.loads(conns)
        self.assertEqual([s["workflow_id"] for s in steps], [12805, 12804, 12826, 12824])
        self.assertNotIn("workflow_file", steps[0])
        self.assertNotIn("evidence", conns[0])
        self.assertEqual({c["transform"]["name"] for c in conns}, {"pocket_json_to_box_center", "smiles_file_to_json_list"})
        self.assertEqual(self.run_(False), ("none", None))
        self.assertEqual(len(self.row()), 1)

    def test_update_preserves_usage(self):
        self.run_(False)
        c = sqlite3.connect(self.db)
        c.execute("UPDATE workflow_chains SET usage_count=7, description='stale'")
        c.commit()
        c.close()
        self.assertEqual(self.run_(False)[0], "update")
        self.assertEqual(self.row()[0][2], 7)
        self.assertEqual(self.run_(False)[0], "none")

    def test_bad_pin_aborts(self):
        c = sqlite3.connect(self.db)
        c.execute("UPDATE workflows SET executable=0 WHERE id=12824")
        c.commit()
        c.close()
        with self.assertRaises(SystemExit):
            self.run_(False)
        self.assertEqual(self.row(), [])

    def test_backup_refused_when_disk_low(self):
        fake = mock.Mock(free=1024)
        with mock.patch.object(A.shutil, "disk_usage", return_value=fake):
            with self.assertRaises(SystemExit):
                self.run_(False)
        self.assertEqual(self.row(), [])


if __name__ == "__main__":
    unittest.main()
