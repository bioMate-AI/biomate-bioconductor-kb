#!/usr/bin/env python3
"""Release-name regression tests; real source/catalogue checks, no API mocks."""
import ast
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sqlite3
import subprocess
import sys
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("image_migration", ROOT / "scripts/release/migrate_image_names.py")
M = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(M)


class ImageNameMigrationTests(unittest.TestCase):
    def test_reference_forms_and_longest_match(self):
        cases = {
            "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86": "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/workflow-tools:x86",
            "biomate/biomni-tools-base@sha256:abc": "biomate/workflow-tools-base@sha256:abc",
            "ghcr.io/biomate-ai/biomni-structure-to-drug-gpu:arm64": "ghcr.io/biomate-ai/structure-to-drug-gpu:arm64",
            "biomni-tools-${HOST_ARCH_NORM}.tar": "workflow-tools-${HOST_ARCH_NORM}.tar",
            "backend/docker/biomni-admet/requirements.lock": "backend/docker/admet/requirements.lock",
            "BIOMATE_BIOMNI_TOOLS_IMAGE": "BIOMATE_WORKFLOW_TOOLS_IMAGE",
        }
        for old, new in cases.items():
            with self.subTest(old=old):
                self.assertEqual(M.transform(old), new)

    def test_sdk_tool_ids_and_unrelated_roots_are_preserved(self):
        text = "from biomni.tool.pharmacology import predict_admet_properties\nbiomni_workflows/nextflow\nbiomni/genomics/example\nbiomni_example\n"
        self.assertEqual(M.transform(text), text)

    def test_idempotent(self):
        for old in M.MAPPING:
            value = M.transform("biomate/" + old + ":latest")
            self.assertEqual(M.transform(value), value)

    def test_neutral_unique_destinations(self):
        self.assertEqual(len(set(M.MAPPING.values())), len(M.MAPPING))
        self.assertTrue(all("biomni" not in x.lower() for x in M.MAPPING.values()))

    def active_files(self):
        files = {p for p in subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).decode().split("\0") if p}
        files |= {M.destination(p) for p in list(files)}
        return sorted(p for p in files if M.selected(p) and (ROOT / p).is_file())

    def test_no_old_image_components_in_active_consumers(self):
        failures = []
        for name in self.active_files():
            try:
                data = (ROOT / name).read_bytes()
                if b"\0" in data[:8192]:
                    continue
                text = data.decode()
            except UnicodeDecodeError:
                continue
            if M.PATTERN.search(text):
                failures.append(name)
        self.assertFalse(failures, "old image components remain: " + str(failures[:20]))

    def test_docker_build_paths_and_ci_paths_exist(self):
        for old, new in M.DIR_MOVES.items():
            if (ROOT / new).exists():
                self.assertFalse((ROOT / old).exists(), old)
        for old, new in M.FILE_MOVES.items():
            self.assertFalse((ROOT / old).exists(), old)
            self.assertTrue((ROOT / new).is_file(), new)
        for path in (ROOT / ".github/workflows").glob("*.yml"):
            text = path.read_text()
            for value in re.findall(r"(?:dockerfile|smoke_script):\s*([^\s#]+)", text):
                if value.startswith("backend/"):
                    self.assertTrue((ROOT / value).is_file(), f"{path}: {value}")
            for value in re.findall(r"uses:\s*\./([^\s#]+)", text):
                self.assertTrue((ROOT / value).exists(), f"{path}: {value}")

    def test_changed_python_parses(self):
        ledger = M.AUDIT / "applied.json"
        self.assertTrue(ledger.exists(), "migration not applied")
        for row in json.loads(ledger.read_text())["files"]:
            path = ROOT / row["after_path"]
            if path.suffix == ".py":
                ast.parse(path.read_text(), filename=str(path))

    def test_database_image_references_and_integrity(self):
        db = sqlite3.connect((ROOT / "backend/database/galaxy_ai_tools.db").as_uri() + "?mode=ro", uri=True)
        self.assertEqual(db.execute("PRAGMA quick_check").fetchall(), [("ok",)])
        for table, column in [("workflows", "docker_image"), ("workflows", "workflow_json"), ("tools", "container_info"), ("tools", "execution_info")]:
            for rowid, value in db.execute("SELECT rowid," + M.quote(column) + " FROM " + M.quote(table) + " WHERE typeof(" + M.quote(column) + ")='text'"):
                self.assertIsNone(M.PATTERN.search(value), f"{table}.{column} row {rowid}")
        self.assertEqual(db.execute("SELECT count(*) FROM tools_fts").fetchone(), db.execute("SELECT count(*) FROM tools").fetchone())
        db.close()

    def test_every_journaled_database_cell_matches_committed_value(self):
        # Independent of transform()/PATTERN: a partial migration must fail
        # even if the production selector accidentally omits a column.
        changes = json.loads((M.AUDIT / "database_changes.json").read_text())
        ledger = json.loads((M.AUDIT / "applied.json").read_text())
        self.assertEqual(len(changes), ledger["database_cells"])
        self.assertGreater(len(changes), 0)
        with sqlite3.connect((ROOT / "backend/database/galaxy_ai_tools.db").as_uri() + "?mode=ro", uri=True) as db:
            for change in changes:
                actual = db.execute("SELECT " + M.quote(change["column"]) + " FROM " + M.quote(change["table"]) + " WHERE rowid=?", (change["rowid"],)).fetchone()
                self.assertEqual(actual, (change["after"],), str({k: change[k] for k in ("table", "column", "rowid")}))

    def test_search_content_matches_primary_tools_not_just_row_count(self):
        with sqlite3.connect((ROOT / "backend/database/galaxy_ai_tools.db").as_uri() + "?mode=ro", uri=True) as db:
            columns = [row[1] for row in db.execute("PRAGMA table_info(tools_fts)")]
            fields = ",".join(M.quote(column) for column in columns)
            indexed = db.execute("SELECT rowid," + fields + " FROM tools_fts ORDER BY rowid").fetchall()
            primary = db.execute("SELECT id," + fields + " FROM tools ORDER BY id").fetchall()
            self.assertEqual(indexed, primary)

    def test_restored_historical_evidence_is_byte_identical(self):
        restorations = json.loads((M.AUDIT / "scope_restorations.json").read_text())
        ledger = json.loads((M.AUDIT / "applied.json").read_text())
        self.assertEqual(len(restorations), ledger["scope_restored_files"])
        for row in restorations:
            actual = hashlib.sha256((ROOT / row["path"]).read_bytes()).hexdigest()
            self.assertEqual(actual, row["restored_sha256"], row["path"])


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(ImageNameMigrationTests)
    started = time.time()
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    M.AUDIT.mkdir(parents=True, exist_ok=True)
    payload = json.dumps({
        "started_unix": started, "duration_s": time.time() - started, "tests": result.testsRun,
        "failures": [{"test": str(test), "traceback": message} for test, message in result.failures],
        "errors": [{"test": str(test), "traceback": message} for test, message in result.errors],
        "skipped": result.skipped, "successful": result.wasSuccessful()}, indent=2) + "\n"
    (M.AUDIT / ("tests-after.json" if (M.AUDIT / "applied.json").exists() else "tests-before.json")).write_text(payload)
    (M.AUDIT / ("tests-attempt-" + str(int(started)) + ".json")).write_text(payload)
    sys.exit(0 if result.wasSuccessful() else 1)
