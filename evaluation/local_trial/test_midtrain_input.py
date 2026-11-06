"""Regression coverage for the actual October concept-corpus load failure."""
import json
import tempfile
import unittest
from pathlib import Path

from midtrain_run import text_rows


class ConceptInputTests(unittest.TestCase):
    def test_mixed_source_schemas_project_to_same_training_schema(self):
        rows = [
            {"text": "PMC conceptual background", "source": "pmc", "year": 2021},
            {"text": "GTN experimental design", "source": "gtn", "topic": "omics", "chars": 23},
            {"text": "General replay", "metadata": {"quality": 0.9}},
        ]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "mix.jsonl"
            path.write_text("\n".join(map(json.dumps, rows)))
            self.assertEqual(list(text_rows(str(path))), [{"text": r["text"]} for r in rows])
            self.assertEqual([json.loads(line) for line in path.read_text().splitlines()], rows)

    def test_missing_or_invalid_training_text_is_rejected(self):
        for text in (None, 123, "", "  "):
            with self.subTest(text=text), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "bad.jsonl"
                path.write_text(json.dumps({"text": text}))
                with self.assertRaisesRegex(ValueError, "expected nonempty text"):
                    list(text_rows(str(path)))


if __name__ == "__main__":
    unittest.main()
