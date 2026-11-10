"""Standalone learned evidence attention; not wired into the ChemFM decoder.

Reuses the LayerNorm -> Q/KV -> scaled-dot-product attention -> zero-output
projection pattern in ihlm_backbone.adapter.CrossAttn without importing the
predictor. Inputs are already qualified computational evidence features, not
text or raw mined claims. This primitive cannot establish source eligibility,
future-outcome separation, a trained architecture or scientific effectiveness.

The caller must freeze memory before generating a group and pass the identical
memory/mask to policy and reference likelihoods. This module never builds or
caches memory from candidate tokens. Execute tests/inference on approved cloud
compute only.
"""
from contextlib import contextmanager
from contextvars import ContextVar
from copy import deepcopy

import torch
from torch import nn
from torch.nn import functional as F


class EvidenceCrossAttention(nn.Module):
    """Residual evidence attention: hidden [B,T,D], projected memory [B,M,D], mask [B,M].

    `eligible` must be Boolean and on the input device. Every input, including
    padding, must be finite. Masked slots are zeroed before projection. The
    caller supplies an always-admitted null slot; fully masked rows fail closed.
    A trained null-only residual can be nonzero (the matched capacity control).
    No token-to-token attention occurs here: each query uses its own hidden
    state. Causality of those states is the decoder/caller's responsibility.
    """
    def __init__(self, hidden_dim, heads):
        super().__init__()
        if any(isinstance(v, bool) or not isinstance(v, int) or v < 1
               for v in (hidden_dim, heads)):
            raise ValueError('attention dimensions must be positive integers')
        if hidden_dim % heads:
            raise ValueError('hidden dimension must be divisible by heads')
        self.hidden_dim, self.heads = hidden_dim, heads
        self.norm = nn.LayerNorm(hidden_dim)
        self.query = nn.Linear(hidden_dim, hidden_dim)
        self.key_value = nn.Linear(hidden_dim, 2 * hidden_dim)
        self.output = nn.Linear(hidden_dim, hidden_dim)
        nn.init.zeros_(self.output.weight)
        nn.init.zeros_(self.output.bias)

    def _validate(self, hidden, memory, eligible):
        if not all(isinstance(v, torch.Tensor) for v in (hidden, memory, eligible)):
            raise TypeError('hidden, memory and eligibility must be tensors')
        if hidden.ndim != 3 or hidden.shape[-1] != self.hidden_dim or not hidden.shape[0] or not hidden.shape[1]:
            raise ValueError('hidden must have nonempty shape [B,T,hidden_dim]')
        if memory.ndim != 3 or memory.shape[0] != hidden.shape[0] or memory.shape[-1] != self.hidden_dim:
            raise ValueError('memory must have shape [B,M,hidden_dim]')
        if eligible.dtype != torch.bool or eligible.shape != memory.shape[:2]:
            raise ValueError('eligibility must be a Boolean [B,M] tensor')
        if not memory.shape[1] or not bool(eligible.any(dim=1).all()):
            raise ValueError('each memory row requires an admitted null or evidence slot')
        if hidden.device != memory.device or hidden.device != eligible.device:
            raise ValueError('attention inputs must share a device')
        if not hidden.is_floating_point() or not memory.is_floating_point() or hidden.dtype != memory.dtype:
            raise ValueError('hidden and memory must share a floating dtype')
        if not bool(torch.isfinite(hidden).all()) or not bool(torch.isfinite(memory).all()):
            raise ValueError('attention inputs including masked padding must be finite')

    def forward(self, hidden, memory, eligible):
        self._validate(hidden, memory, eligible)
        batch, tokens, dim = hidden.shape
        slots, heads = memory.shape[1], self.heads
        safe_memory = memory.masked_fill(~eligible[..., None], 0)
        queries = self.query(self.norm(hidden)).reshape(batch, tokens, heads, dim // heads).transpose(1, 2)
        keys, values = self.key_value(safe_memory).reshape(batch, slots, 2, heads, dim // heads).permute(2, 0, 3, 1, 4)
        attended = F.scaled_dot_product_attention(
            queries, keys, values, attn_mask=eligible[:, None, None, :], dropout_p=0.0)
        delta = self.output(attended.transpose(1, 2).reshape(batch, tokens, dim))
        result = hidden + delta
        if not bool(torch.isfinite(result).all()):
            raise FloatingPointError('nonfinite evidence-attention output')
        return result


class PolicyReferenceEvidenceAttention(nn.Module):
    """Trainable branch plus an independent small frozen initial reference.

    The frozen copy is created once at construction and stored in state_dict.
    Optimisers must use trainable_parameters(), or filter requires_grad. The
    reference-mode context is nesting/exception safe and context-local. It only
    selects this bridge; the caller must also select the base model reference.
    Reference forward is gradient-free. No automatic re-snapshot is performed.
    """
    def __init__(self, hidden_dim, heads):
        super().__init__()
        self.policy = EvidenceCrossAttention(hidden_dim, heads)
        self._reference = deepcopy(self.policy)
        self._reference.requires_grad_(False)
        self._reference.eval()
        self._use_reference = ContextVar('evidence_reference_' + str(id(self)), default=False)

    def train(self, mode=True):
        super().train(mode)
        self._reference.eval()
        return self

    def trainable_parameters(self):
        return (p for p in self.policy.parameters() if p.requires_grad)

    @contextmanager
    def reference_mode(self):
        token = self._use_reference.set(True)
        try:
            yield self
        finally:
            self._use_reference.reset(token)

    def forward(self, hidden, memory, eligible):
        if self._use_reference.get():
            with torch.no_grad():
                return self._reference(hidden, memory, eligible)
        return self.policy(hidden, memory, eligible)
