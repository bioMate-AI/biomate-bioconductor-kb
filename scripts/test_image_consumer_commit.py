#!/usr/bin/env python3
"""Check the isolated migration's Git objects, not the dirty working tree.

IMAGE_MIGRATION_REF may select a later commit on the same stacked branch.
This is an image-consumer gate, not a complete release-payload certificate.
"""
import ast
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
REF = os.environ.get("IMAGE_MIGRATION_REF", "codex/onprem-neutral-image-consumers-20261107")
LEDGER = "docs/qa/20261107-image-name-migration/next-phase-image-consumer-ledger.json"


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def tree(ref):
    entries = {}
    for record in git("ls-tree", "-rz", ref).split(b"\0"):
        if record:
            meta, path = record.split(b"\t", 1)
            mode, kind, oid = meta.decode().split()
            entries[os.fsdecode(path)] = (mode, kind, oid)
    return entries


def read_blobs(oids):
    # One bounded local Git process rather than thousands of shell invocations.
    requested = sorted(set(oids))
    process = subprocess.run(["git", "cat-file", "--batch"], cwd=ROOT,
                             input=("\n".join(requested) + "\n").encode(),
                             stdout=subprocess.PIPE, check=True)
    data, offset, result = process.stdout, 0, {}
    for expected in requested:
        end = data.index(b"\n", offset)
        oid, kind, length = data[offset:end].decode().split()
        assert oid == expected and kind == "blob"
        start, size = end + 1, int(length)
        result[oid] = data[start:start + size]
        assert data[start + size:start + size + 1] == b"\n"
        offset = start + size + 1
    assert offset == len(data)
    return result


def stream_blobs(named_oids):
    # Feed one object at a time: no pipe deadlock or whole-repository buffer.
    with subprocess.Popen(["git", "cat-file", "--batch"], cwd=ROOT,
                          stdin=subprocess.PIPE, stdout=subprocess.PIPE) as process:
        try:
            for name, oid in named_oids:
                process.stdin.write((oid + "\n").encode())
                process.stdin.flush()
                actual, kind, length = process.stdout.readline().decode().split()
                assert actual == oid and kind == "blob"
                data = process.stdout.read(int(length))
                assert process.stdout.read(1) == b"\n"
                yield name, data
        finally:
            process.stdin.close()
            process.stdout.close()
            assert process.wait(timeout=10) == 0


def verify_rows(rows, before, after, blobs):
    seen = set()
    for row in rows:
        source, target = row["before_path"], row["after_path"]
        assert target not in seen, "duplicate destination: " + target
        seen.add(target)
        for entries, name, phase in ((before, source, "before"), (after, target, "after")):
            mode, kind, oid = entries[name]
            assert kind == "blob" and mode == row["mode"], name
            assert oid == row[phase + "_blob"], name
            assert hashlib.sha256(blobs[oid]).hexdigest() == row[phase + "_sha256"], name
        if source != target:
            assert source not in after, "old moved path survives: " + source


class ImageConsumerCommitTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ledger = json.loads(git("show", f"{REF}:{LEDGER}"))
        cls.before, cls.after = tree(cls.ledger["base"]), tree(REF)
        oids = [r[p] for r in cls.ledger["files"] for p in ("before_blob", "after_blob")]
        oids += [cls.after["scripts/release/" + name][2]
                 for name in ("migrate_image_names.py", "image_name_map.json")]
        cls.blobs = read_blobs(oids)
        # The selector is used only after proving it equals the published tool.
        for name in ("migrate_image_names.py", "image_name_map.json"):
            path = "scripts/release/" + name
            assert (ROOT / path).read_bytes() == cls.blobs[cls.after[path][2]]
        spec = importlib.util.spec_from_file_location("migration", ROOT / "scripts/release/migrate_image_names.py")
        cls.migration = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.migration)

    def test_every_journaled_byte_and_mode_matches_git(self):
        self.assertGreater(len(self.ledger["files"]), 1000)
        verify_rows(self.ledger["files"], self.before, self.after, self.blobs)

    def test_corrupted_hash_is_rejected(self):
        rows = copy.deepcopy(self.ledger["files"][:1])
        rows[0]["after_sha256"] = "0" * 64
        with self.assertRaises(AssertionError):
            verify_rows(rows, self.before, self.after, self.blobs)

    def test_duplicate_destination_is_rejected(self):
        row = self.ledger["files"][0]
        with self.assertRaises(AssertionError):
            verify_rows([row, row], self.before, self.after, self.blobs)

    def test_mode_corruption_is_rejected(self):
        rows = copy.deepcopy(self.ledger["files"][:1])
        rows[0]["mode"] = "100755" if rows[0]["mode"] != "100755" else "100644"
        with self.assertRaises(AssertionError):
            verify_rows(rows, self.before, self.after, self.blobs)

    def test_changed_files_are_covered_or_explicit_tooling(self):
        changed = {p for p in set(self.before) | set(self.after) if self.before.get(p) != self.after.get(p)}
        covered = {r[p] for r in self.ledger["files"] for p in ("before_path", "after_path")}
        allowed = {LEDGER, "scripts/test_image_consumer_commit.py",
                   "scripts/release/copy_images_remote.py", "scripts/release/image_name_map.json",
                   "scripts/release/migrate_image_names.py"}
        self.assertFalse(changed - covered - allowed, sorted(changed - covered - allowed))

    def test_selected_consumers_have_no_old_image_family(self):
        failures = []
        selected = ((name, oid) for name, (_, kind, oid) in self.after.items()
                    if kind == "blob" and self.migration.selected(name))
        for name, data in stream_blobs(selected):
            if b"\0" in data[:8192]:
                continue
            try:
                text = data.decode("utf8")
            except UnicodeDecodeError:
                continue
            if self.migration.PATTERN.search(text):
                failures.append(name)
        self.assertEqual(failures, [])

    def test_python_syntax_and_mechanical_content(self):
        strengthened = {"backend/docker/admet/smoke.py", "backend/docker/structure-to-drug/smoke.py"}
        for row in self.ledger["files"]:
            name = row["after_path"]
            before, after = self.blobs[row["before_blob"]], self.blobs[row["after_blob"]]
            if name.endswith(".py"):
                ast.parse(after.decode(), filename=name)
            if name not in strengthened:
                self.assertEqual(self.migration.transform(before.decode()).encode(), after, name)

    def test_old_build_folders_and_workflow_files_are_absent(self):
        for old, new in self.migration.DIR_MOVES.items():
            self.assertFalse(any(p.startswith(old + "/") for p in self.after), old)
            if any(p.startswith(old + "/") for p in self.before):
                self.assertTrue(any(p.startswith(new + "/") for p in self.after), new)
        for old, new in self.migration.FILE_MOVES.items():
            self.assertNotIn(old, self.after)
            self.assertIn(new, self.after)

    def test_incomplete_release_is_not_certified(self):
        self.assertIs(self.ledger["release_ready"], False)
        self.assertIs(self.ledger["ghcr_publication_qualified"], False)
        self.assertIs(self.ledger["source_images_preserved"], True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
