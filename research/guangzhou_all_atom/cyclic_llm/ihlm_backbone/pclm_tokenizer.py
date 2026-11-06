"""Our re-implementation of the PeptideCLM-2 SMILES tokenizer from its published tokenizer.json (WordPiece over a regex 'Isolated' split).
Reads data only; imports/executes nothing from the model repository. Parity with the Rust `tokenizers` loader is tested in test_backbone.py.
Provenance/licence: NOTICE.md."""
import json, re

class PClmTokenizer:
    PAD, UNK, CLS, SEP, MASK = 0, 1, 2, 3, 4

    def __init__(self, tokenizer_json_path, max_len=512):
        with open(tokenizer_json_path) as fh: t = json.load(fh)
        m = t["model"]
        assert m["type"] == "WordPiece" and t["pre_tokenizer"]["type"] == "Split" and t["pre_tokenizer"]["behavior"] == "Isolated" and not t["pre_tokenizer"]["invert"]
        self.vocab = dict(m["vocab"]); self.itos = {i: s for s, i in self.vocab.items()}; self.prefix = m["continuing_subword_prefix"]; self.max_chars = int(m["max_input_chars_per_word"])
        self.unk = m["unk_token"]; self.split_re = re.compile(t["pre_tokenizer"]["pattern"]["Regex"]); self.max_len = int(max_len)
        assert [self.vocab[s] for s in ("[PAD]", "[UNK]", "[CLS]", "[SEP]", "[MASK]")] == [0, 1, 2, 3, 4]
        post = t["post_processor"]; assert post["type"] == "TemplateProcessing" and [list(x)[0] for x in post["single"]] == ["SpecialToken", "Sequence", "SpecialToken"]

    def pretokenize(self, s):
        """regex Isolated split: every match is a piece, and every non-matching gap between matches is its own piece."""
        out, pos = [], 0
        for m in self.split_re.finditer(s):
            if m.start() == m.end(): continue
            if m.start() > pos: out.append(s[pos:m.start()])
            out.append(m.group(0)); pos = m.end()
        if pos < len(s): out.append(s[pos:])
        return out

    def wordpiece(self, w):
        if len(w) > self.max_chars: return [self.vocab[self.unk]]
        ids, start = [], 0
        while start < len(w):
            end, cur = len(w), None
            while start < end:
                sub = w[start:end]
                if start > 0: sub = self.prefix + sub
                if sub in self.vocab: cur = self.vocab[sub]; break
                end -= 1
            if cur is None: return [self.vocab[self.unk]]
            ids.append(cur); start = end
        return ids

    def encode(self, s):
        body = [i for w in self.pretokenize(s) for i in self.wordpiece(w)]
        return ([self.CLS] + body[: self.max_len - 2] + [self.SEP])

    def tokens(self, s): return [self.itos[i] for i in self.encode(s)]
    def fit(self, smiles_list): return self        # fixed vocabulary; unseen tokens map to [UNK]
    def __len__(self): return len(self.vocab)
