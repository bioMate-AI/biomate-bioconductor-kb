import sys
import types
import unittest
from unittest.mock import Mock, patch

from eval_today import answer
from model_loading import load_text_model


class TodayPipelineTests(unittest.TestCase):
    def test_answer_parser_rejects_ambiguous_or_incidental_letters(self):
        for value in ("A", "(B)", "Answer: C", "D."):
            self.assertIsNotNone(answer(value))
        for value in ("A or B", "A patient needs treatment", "", "E because I think so"):
            self.assertIsNone(answer(value))

    def loaders(self, info):
        module = types.ModuleType("transformers")
        module.AutoConfig = Mock()
        module.AutoConfig.from_pretrained.return_value = types.SimpleNamespace(model_type="qwen3_5", text_config="text_config")
        module.AutoModelForCausalLM = Mock()
        module.Qwen3_5ForCausalLM = Mock()
        module.Qwen3_5ForCausalLM.from_pretrained.return_value = ("model", info)
        return module

    def test_text_backbone_maps_checkpoint_keys_and_ignores_only_vision(self):
        module = self.loaders({"unexpected_keys": ["model.visual.patch_embed.weight"]})
        with patch.dict(sys.modules, {"transformers": module}):
            self.assertEqual(load_text_model("base"), "model")
        kwargs = module.Qwen3_5ForCausalLM.from_pretrained.call_args.kwargs
        self.assertEqual(kwargs["config"], "text_config")
        self.assertEqual(kwargs["key_mapping"], {r"^model\.language_model\.": "model."})

    def test_missing_or_unexpected_language_weights_fail_closed(self):
        for info in ({"missing_keys": ["model.embed_tokens.weight"]},
                     {"unexpected_keys": ["model.language_model.layers.0.weight"]}):
            with self.subTest(info=info), patch.dict(sys.modules, {"transformers": self.loaders(info)}):
                with self.assertRaises(RuntimeError):
                    load_text_model("base")
