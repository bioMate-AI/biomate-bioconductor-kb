"""The language-model channel reads reasoning-model output and retries once with a larger budget."""
import unittest

from galaxy.ai.target_id.channels import LLMReasonedChannel, _parse_json_obj


class Fake:
    model = "fake"

    def __init__(self, replies):
        self.replies, self.calls = list(replies), []

    def generate(self, prompt, **kw):
        self.calls.append(kw)
        return self.replies.pop(0)


class ParseTests(unittest.TestCase):
    def test_variants(self):
        self.assertEqual(_parse_json_obj('<think>maybe {"x": 1} is it</think>{"BRAF": 0.9}'), {"BRAF": 0.9})
        self.assertEqual(_parse_json_obj('```json\n{"BRAF": 0.9, "TP53": 0.4}\n```'), {"BRAF": 0.9, "TP53": 0.4})
        self.assertEqual(_parse_json_obj('Here {not json} is the answer: {"A": 0.5} Hope this helps {again}'), {"A": 0.5})
        self.assertEqual(_parse_json_obj('{"A": 0.5}\nExplanation: {"B": 9}'), {"A": 0.5})
        self.assertEqual(_parse_json_obj('{"a{b": 0.5}'), {"a{b": 0.5})          # braces inside strings
        self.assertIsNone(_parse_json_obj("no json here")); self.assertIsNone(_parse_json_obj(""))
        self.assertIsNone(_parse_json_obj('<think>{"A": 1}</think> only thoughts'))

    def test_retry_doubles_the_budget_and_recovers(self):
        llm = Fake(["<think>long reasoning, ran out of tokens", '{"BRAF": 0.9}'])
        r = LLMReasonedChannel(llm, generate_kwargs={"max_tokens": 1000, "temperature": 0.0}).run({"query": "q"})
        self.assertTrue(r.ok); self.assertEqual(r.scores, {"BRAF": 0.9})
        self.assertEqual([c["max_tokens"] for c in llm.calls], [1000, 2000])
        self.assertEqual(r.evidence_kind, "model_judgment")

    def test_gives_up_after_the_retry_with_a_clear_error_and_respects_the_cap(self):
        llm = Fake(["nothing", "still nothing"])
        r = LLMReasonedChannel(llm, generate_kwargs={"max_tokens": 5000}, max_tokens_cap=6000).run({"query": "q"})
        self.assertFalse(r.ok); self.assertIn("no parseable JSON", r.error)
        self.assertEqual([c["max_tokens"] for c in llm.calls], [5000, 6000])

    def test_transport_errors_do_not_retry(self):
        class Boom:
            calls = 0
            def generate(self, p, **k):
                Boom.calls += 1
                raise TimeoutError("slow")
        r = LLMReasonedChannel(Boom()).run({"query": "q"})
        self.assertIn("llm error", r.error); self.assertEqual(Boom.calls, 1)


if __name__ == "__main__":
    unittest.main()
