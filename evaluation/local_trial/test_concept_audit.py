import json
from pathlib import Path
import tempfile
import unittest

from audit_concept_sft import audit, audit_overlap


class ConceptAuditTests(unittest.TestCase):
    def test_overlap_catches_seen_prompt_even_when_answer_differs(self):
        with tempfile.TemporaryDirectory() as directory:
            train, heldout = Path(directory) / "train", Path(directory) / "eval"
            row = {"messages": [{"role": "user", "content": "Which method?"},
                                {"role": "assistant", "content": "Method A"}], "task": "model_selection"}
            other = {"messages": [row["messages"][0], {"role": "assistant", "content": "Method B"}]}
            train.write_text(json.dumps(row) + "\n" + json.dumps(row) + "\n")
            heldout.write_text("\n".join(map(json.dumps, [row, other, {"input": "unknown schema"}])))
            result = audit_overlap(train, [heldout])[0]
            self.assertEqual(result["exact_message_overlap"], 1)
            self.assertEqual(result["exact_user_message_overlap"], 2)
            self.assertEqual(result["skipped_schema"], 1)
            self.assertEqual(audit(train)["exact_duplicate_messages"], 1)

    def test_invalid_record_is_reported_with_line_number(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "bad"
            path.write_text('{"messages": []}\n')
            self.assertEqual(audit(path)["invalid_rows"][0]["line"], 1)
