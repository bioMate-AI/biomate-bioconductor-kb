"""Frozen peptide embeddings via the existing strict PeptideCLM implementation.

Explicit opt-in, local pinned files only. No downloads or inference at import.
The encoder supplies retrieval features; it is not a 3D generator or a trained
knowledge-fusion module. Run model loading/inference on approved cloud compute.
"""
import hashlib
import json
from pathlib import Path
import re

REQUIRED_FILES = ('config.json', 'tokenizer.json', 'model.safetensors')


def verify_encoder_files(directory, expected):
    root = Path(directory)
    if root.is_symlink() or not root.is_dir():
        raise ValueError('encoder requires a real checkpoint directory')
    if not isinstance(expected, dict) or not set(REQUIRED_FILES) <= set(expected):
        raise ValueError('encoder manifest must pin config, tokenizer and weights')
    for name, sha in expected.items():
        if (not isinstance(name, str) or Path(name).name != name or name in ('.', '..')
                or not isinstance(sha, str) or re.fullmatch(r'[0-9a-f]{64}', sha) is None):
            raise ValueError('invalid encoder file manifest')
        path = root / name
        if path.is_symlink() or not path.is_file():
            raise ValueError('missing or symlinked encoder file: ' + name)
        digest = hashlib.sha256()
        with path.open('rb') as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b''):
                digest.update(block)
        if digest.hexdigest() != sha:
            raise ValueError('encoder file hash mismatch: ' + name)
    return hashlib.sha256(json.dumps(expected, sort_keys=True).encode()).hexdigest()


class FrozenPeptideEncoder:
    def __init__(self, directory, expected_files, *, device='cuda', batch_size=16):
        self.model_tag = verify_encoder_files(directory, expected_files)
        if batch_size < 1:
            raise ValueError('encoder batch size must be positive')
        import sys
        import torch
        # Reuse the existing audited architecture and strict checkpoint loader.
        parent = str(Path(__file__).resolve().parents[2])
        if parent not in sys.path:
            sys.path.insert(0, parent)
        from ihlm_backbone.pclm_encoder import PClmMLM
        from ihlm_backbone.pclm_tokenizer import PClmTokenizer
        if device == 'cuda' and not torch.cuda.is_available():
            raise RuntimeError('CUDA required for selected encoder device')
        self.model, config, result = PClmMLM.from_dir(directory, strict=True)
        if result.missing_keys or result.unexpected_keys:
            raise ValueError('encoder checkpoint keys do not match')
        self.model.to(device).eval()
        for parameter in self.model.parameters():
            parameter.requires_grad_(False)
        self.tokenizer = PClmTokenizer(str(Path(directory) / 'tokenizer.json'),
                                      max_len=int(config['max_seq_len']))
        self.width = int(config['embed_dim'])
        if self.tokenizer.max_len < 3 or self.width < 1:
            raise ValueError('encoder requires molecular token capacity and positive width')
        self.device, self.batch_size = device, batch_size
        self.diagnostics = dict(molecules=0, truncated=0, unknown_tokens=0)

    def __call__(self, smiles):
        import numpy as np
        import torch
        if not smiles:
            return np.zeros((0, self.width), dtype=np.float32)
        output = []
        self.model.eval()
        with torch.inference_mode():
            for start in range(0, len(smiles), self.batch_size):
                records = []
                for text in smiles[start:start + self.batch_size]:
                    if not isinstance(text, str) or not text:
                        raise ValueError('empty peptide encoder input')
                    body = [token for piece in self.tokenizer.pretokenize(text)
                            for token in self.tokenizer.wordpiece(piece)]
                    if not body:
                        raise ValueError('empty molecular token sequence')
                    self.diagnostics['molecules'] += 1
                    self.diagnostics['truncated'] += int(len(body) > self.tokenizer.max_len - 2)
                    self.diagnostics['unknown_tokens'] += body.count(self.tokenizer.UNK)
                    records.append(self.tokenizer.encode(text))
                size = max(map(len, records))
                ids = torch.full((len(records), size), self.tokenizer.PAD,
                                 dtype=torch.long, device=self.device)
                mask = torch.zeros_like(ids)
                for row, record in enumerate(records):
                    ids[row, :len(record)] = torch.tensor(record, device=self.device)
                    mask[row, :len(record)] = 1
                _, hidden = self.model(ids, mask, return_hidden=True)
                for row, record in enumerate(records):
                    output.append(hidden[row, 1:len(record)-1].float().mean(0).cpu().numpy())
        values = np.asarray(output, dtype=np.float32)
        if values.shape != (len(smiles), self.width) or not np.isfinite(values).all():
            raise FloatingPointError('invalid frozen peptide embeddings')
        return values
