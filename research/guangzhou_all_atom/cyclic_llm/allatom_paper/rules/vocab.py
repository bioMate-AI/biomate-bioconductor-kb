"""ChemFM-1B token table. The tokenizer is atom-level (element symbols, brackets, ring digits, bond/branch symbols) with 266 real tokens in a 320-entry vocabulary; <eos> = 265.
Loaded from tokenizer.json (CHEMFM_DIR or an explicit path); no model weights needed."""
import json, os

PAD_TO = 320


class Vocab:
    def __init__(self, tokenizer_json):
        t = json.load(open(tokenizer_json)); at = sorted(t["added_tokens"], key=lambda a: a["id"])
        self.id2tok = {a["id"]: a["content"] for a in at}
        self.tok2id = {v: k for k, v in self.id2tok.items()}
        self.eos = self.tok2id["<eos>"]; self.V = PAD_TO
        assert max(self.id2tok) < PAD_TO

    def encode(self, smiles):
        """replicates the ChemFM HF tokenizer: greedy longest match over the token table (max 2 characters), NOT SMILES-aware, so 'Cn1' -> 'Cn','1'.
        The tracker expands such merged tokens back into the SMILES atoms they stand for. test_rules.py checks equality with the HF tokenizer."""
        out = []; i = 0
        while i < len(smiles):
            k = smiles[i:i + 2]
            if len(k) < 2 or k not in self.tok2id: k = smiles[i]
            if k not in self.tok2id: raise ValueError(f"cannot tokenise {smiles[i:i+5]!r}")
            out.append(self.tok2id[k]); i += len(k)
        return out

    def decode(self, ids): return "".join(self.id2tok[i] for i in ids if i in self.id2tok and i != self.eos)


def load(path=None):
    path = path or os.path.join(os.environ.get("CHEMFM_DIR", "."), "tokenizer.json")
    return Vocab(path)
