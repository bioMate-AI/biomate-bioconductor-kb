"""IH-LM on an open-weight backbone: PeptideCLM-2 (our re-implementation, NOTICE.md) wrapped so the unchanged IH-LM modules M1-M5 (ihlm/model.py Net/IHLM) use it.
Backbone swap = (a) PClmTokenizer instead of the atom tokenizer, (b) PClmBackbone instead of Backbone. M3's cross-attention to analog tokens needs cross-attention that the
pretrained encoder does not have: one NEW cross-attention sublayer per block, its output projection ZERO-initialised, so at initialisation the network computes exactly the
pretrained encoder function (tested). Pretrained parameters are the encoder; new parameters are the cross-attention, score/logvar/verifier heads and M3/M4 heads (random init).
Limits: no topology tokens (PeptideCLM-2 tokenizer has none; M1-M4 symbolic parts are unaffected); analog memory is truncated at 64 tokens (ihlm/model.py _pack); one learning rate for
all parameters in IHLM._slow_fit (default here 1e-4; per-group rates need a hook in ihlm/model.py, not made)."""
import os, sys, json, math
import torch, torch.nn as nn, torch.nn.functional as F
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, "..", "ihlm"))
from pclm_tokenizer import PClmTokenizer
from pclm_encoder import PClmMLM
import model as IH                      # ihlm/model.py (unchanged)


class CrossAttn(nn.Module):
    def __init__(self, d, heads):
        super().__init__(); self.h = heads; self.lnc = nn.LayerNorm(d); self.q = nn.Linear(d, d); self.kv = nn.Linear(d, 2 * d); self.cproj = nn.Linear(d, d)
        nn.init.zeros_(self.cproj.weight); nn.init.zeros_(self.cproj.bias)
    def forward(self, x, mem, mem_mask):
        B, T, D = x.shape; h = self.h
        q = self.q(self.lnc(x)).view(B, T, h, D // h).transpose(1, 2); k, v = self.kv(mem).view(B, mem.shape[1], 2, h, D // h).permute(2, 0, 3, 1, 4)
        return self.cproj(F.scaled_dot_product_attention(q, k, v, attn_mask=mem_mask[:, None, None, :]).transpose(1, 2).reshape(B, T, D))


class PClmBackbone(nn.Module):
    """same interface as ihlm/model.py Backbone: .d, .tok (nn.Embedding), .embed(X), forward(X, mem, mem_mask) -> (hidden, pad_mask)."""
    def __init__(self, mlm, heads):
        super().__init__(); self.mlm = mlm; core = mlm.model; self.d = core.embed.embedding_dim; self.tok = core.embed
        self.max_len = int(mlm.cfg["max_seq_len"]); self.xattn = nn.ModuleList([CrossAttn(self.d, heads) for _ in core.transformer.blocks])
    def embed(self, X): return self.tok(X)                                  # rotary positions are applied inside attention; no absolute position table
    def forward(self, X, mem=None, mem_mask=None):
        pm = X != IH.PAD; x = self.tok(X); core = self.mlm.model
        for blk, xa in zip(core.transformer.blocks, self.xattn):
            x = x + blk.attn(blk.attn_norm(x), pm)
            if mem is not None: x = x + xa(x, mem, mem_mask)
            x = x + blk.ffn(blk.ffn_norm(x))
        return core.transformer.norm(x), pm


class PClmIHLM(IH.IHLM):
    def __init__(self, weights_dir, max_len=512, train_cfg=None, **kw):
        with open(os.path.join(weights_dir, "config.json")) as fh: cfg = json.load(fh)
        self.weights_dir = weights_dir; self.pclm_cfg = cfg
        tc = dict(dict(steps=150, lr=1e-4, bs=32, rank_w=0.3, verif_w=1.0), **(train_cfg or {}))
        super().__init__(backbone_cfg=dict(d=cfg["embed_dim"], layers=0, heads=cfg["num_heads"], max_len=int(max_len), kind="encoder"), train_cfg=tc, **kw)
        self.tok = PClmTokenizer(os.path.join(weights_dir, "tokenizer.json"), max_len=int(max_len))
        self.provenance = {"backbone_init": "open_weights", "source": f"aaronfeller/peptideclm-2-mlm-{cfg.get('size')}", "licence": "MIT (model-card metadata; see NOTICE.md)",
                           "backbone_code": "ours (ihlm_backbone/pclm_encoder.py), re-implemented from published architecture; no remote code run", "new_params": "cross-attention (zero-init out-proj) + heads"}

    def _ensure_net(self):
        if self.net is None:
            torch.manual_seed(self.seed); self.net = IH.Net(len(self.tok), self.backbone_cfg, self.modules, self.n_verif)       # layers=0: scratch backbone is tiny and replaced below
            mlm, _, res = PClmMLM.from_dir(self.weights_dir, strict=True); assert not res.missing_keys and not res.unexpected_keys
            self.net.bb = PClmBackbone(mlm, self.pclm_cfg["num_heads"]); self.meter.n_params = sum(p.numel() for p in self.net.parameters())
