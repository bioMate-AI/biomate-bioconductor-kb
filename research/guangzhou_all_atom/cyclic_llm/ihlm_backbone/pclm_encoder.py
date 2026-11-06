"""Our re-implementation of the PeptideCLM-2 (PeptideMTR MLM) encoder: pre-LayerNorm blocks, fused QKV attention (no bias), rotary position embedding on
interleaved channel pairs, SwiGLU feed-forward (with biases), final LayerNorm, linear MLM head. Module/parameter names mirror the published safetensors
so `load_state_dict(strict=True)` is exact. Provenance/licence: NOTICE.md. No code from the model repository is imported or executed."""
import json, os, math
import torch, torch.nn as nn, torch.nn.functional as F
from safetensors.torch import load_file


def rope_cache(head_dim, max_len, base=10000.0, device="cpu"):
    theta = torch.pow(torch.tensor(float(base)), -(torch.arange(0, head_dim, 2, dtype=torch.float32)[: head_dim // 2] / float(head_dim)))
    ang = torch.einsum("i,j->ij", torch.arange(max_len, dtype=torch.float32), theta)
    return torch.stack([torch.cos(ang), torch.sin(ang)], -1).to(device)          # (T, hd/2, 2)


def apply_rope(x, cache, interleaved=True):
    """x (B,T,H,hd). interleaved=True rotates channel pairs (2i, 2i+1) (the published convention); False = half-split (NEGATIVE CONTROL only)."""
    B, T, H, hd = x.shape; c = cache[:T].view(1, T, 1, hd // 2, 2)
    if interleaved:
        xs = x.float().reshape(B, T, H, hd // 2, 2); a, b = xs[..., 0], xs[..., 1]
        out = torch.stack([a * c[..., 0] - b * c[..., 1], b * c[..., 0] + a * c[..., 1]], -1).flatten(3)
    else:
        a, b = x.float()[..., : hd // 2], x.float()[..., hd // 2:]
        out = torch.cat([a * c[..., 0] - b * c[..., 1], b * c[..., 0] + a * c[..., 1]], -1)
    return out.type_as(x)


class SwiGLU(nn.Module):
    def __init__(self, d, hidden):
        super().__init__(); self.linear1 = nn.Linear(d, hidden * 2, bias=True); self.linear2 = nn.Linear(hidden, d, bias=True); self.dropout = nn.Dropout(0.1)
    def forward(self, x):
        a, b = self.linear1(x).chunk(2, dim=-1); return self.dropout(self.linear2(F.silu(a) * b))


class Attention(nn.Module):
    def __init__(self, d, heads, max_len):
        super().__init__(); assert d % heads == 0
        self.h, self.hd, self.max_len = heads, d // heads, max_len; self.qkv_proj = nn.Linear(d, 3 * d, bias=False); self.out_proj = nn.Linear(d, d, bias=False); self.dropout = nn.Dropout(0.1)
        self.interleaved = True; self._cache = None
    def forward(self, x, key_mask=None):
        B, T, C = x.shape
        if self._cache is None or self._cache.shape[0] < T or self._cache.device != x.device: self._cache = rope_cache(self.hd, max(self.max_len, T), device=x.device)
        q, k, v = self.qkv_proj(x).view(B, T, 3, self.h, self.hd).unbind(2)
        q, k = apply_rope(q, self._cache, self.interleaved), apply_rope(k, self._cache, self.interleaved)
        am = None if key_mask is None else key_mask[:, None, None, :].to(torch.bool)
        o = F.scaled_dot_product_attention(q.transpose(1, 2), k.transpose(1, 2), v.transpose(1, 2), attn_mask=am, dropout_p=0.0)
        return self.dropout(self.out_proj(o.transpose(1, 2).contiguous().view(B, T, C)))


class Block(nn.Module):
    def __init__(self, d, heads, ffn, max_len):
        super().__init__(); self.attn_norm = nn.LayerNorm(d); self.attn = Attention(d, heads, max_len); self.ffn_norm = nn.LayerNorm(d); self.ffn = SwiGLU(d, ffn)
    def forward(self, x, key_mask=None):
        x = x + self.attn(self.attn_norm(x), key_mask); return x + self.ffn(self.ffn_norm(x))


class Stack(nn.Module):
    def __init__(self, n, d, heads, ffn, max_len):
        super().__init__(); self.blocks = nn.ModuleList([Block(d, heads, ffn, max_len) for _ in range(n)]); self.norm = nn.LayerNorm(d)


class Core(nn.Module):
    def __init__(self, vocab, d, n, heads, ffn, out_dim, max_len):
        super().__init__(); self.embed = nn.Embedding(vocab, d); self.transformer = Stack(n, d, heads, ffn, max_len); self.sequence_head = nn.Linear(d, out_dim, bias=True)
    def forward(self, ids, key_mask=None, return_hidden=False):
        x = self.embed(ids)
        for b in self.transformer.blocks: x = b(x, key_mask)
        h = self.transformer.norm(x); return (self.sequence_head(h), h) if return_hidden else self.sequence_head(h)


class PClmMLM(nn.Module):
    """names: model.embed / model.transformer.blocks.i.{attn_norm,attn.qkv_proj,attn.out_proj,ffn_norm,ffn.linear1,ffn.linear2} / model.transformer.norm / model.sequence_head"""
    def __init__(self, cfg):
        super().__init__(); self.cfg = cfg
        self.model = Core(cfg["vocab_size"], cfg["embed_dim"], cfg["num_blocks"], cfg["num_heads"], cfg["ffn_hidden_dim"], cfg["output_dim"], cfg["max_seq_len"])
    def forward(self, ids, attention_mask=None, return_hidden=False):
        return self.model(ids, None if attention_mask is None else attention_mask.bool(), return_hidden)
    def set_rope_interleaved(self, flag):
        for b in self.model.transformer.blocks: b.attn.interleaved = flag; b.attn._cache = None

    @classmethod
    def from_dir(cls, d, strict=True):
        with open(os.path.join(d, "config.json")) as fh: cfg = json.load(fh)
        m = cls(cfg); sd = load_file(os.path.join(d, "model.safetensors"))
        res = m.load_state_dict(sd, strict=strict); return m, cfg, res
