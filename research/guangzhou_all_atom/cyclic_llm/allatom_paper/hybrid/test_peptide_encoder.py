"""Synthetic file-pin and pooling tests; execute on EC2 only."""
import hashlib
from types import SimpleNamespace
import numpy as np
import pytest
from hybrid.peptide_encoder import FrozenPeptideEncoder, verify_encoder_files, REQUIRED_FILES


def test_pins_reject_modified_tokenizer(tmp_path):
    pins = {}
    for name in REQUIRED_FILES:
        data = name.encode(); (tmp_path/name).write_bytes(data)
        pins[name] = hashlib.sha256(data).hexdigest()
    assert verify_encoder_files(tmp_path, pins)
    (tmp_path/'tokenizer.json').write_text('changed')
    with pytest.raises(ValueError, match='hash mismatch'):
        verify_encoder_files(tmp_path, pins)


def test_pooling_excludes_specials_and_padding_and_preserves_order():
    import torch
    class Tokenizer:
        PAD, UNK, CLS, SEP, max_len = 0, 1, 9, 8, 4
        def pretokenize(self, text): return list(text)
        def wordpiece(self, piece): return [int(piece)]
        def encode(self, text): return [9] + [int(t) for t in text][:2] + [8]
    class Model:
        def eval(self): return self
        def __call__(self, ids, mask, return_hidden):
            assert not torch.is_grad_enabled()
            return None, ids.float().unsqueeze(-1)
    encoder = FrozenPeptideEncoder.__new__(FrozenPeptideEncoder)
    encoder.model, encoder.tokenizer = Model(), Tokenizer()
    encoder.width, encoder.device, encoder.batch_size = 1, 'cpu', 2
    encoder.diagnostics = dict(molecules=0, truncated=0, unknown_tokens=0)
    np.testing.assert_allclose(encoder(['2', '46', '123']), [[2], [5], [1.5]])
    assert encoder.diagnostics == dict(molecules=3, truncated=1, unknown_tokens=1)
    assert encoder([]).shape == (0, 1)
