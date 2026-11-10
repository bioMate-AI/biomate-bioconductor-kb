"""Isolated evidence hooks for Transformers 4.51.3 Llama; not production wiring.

Pinned source: https://github.com/huggingface/transformers/blob/v4.51.3/src/transformers/models/llama/modeling_llama.py
LlamaDecoderLayer saves its MLP residual before post_attention_layernorm. A norm
prehook alone would therefore be wrong. Our paired hooks implement
    h' = attention_residual + evidence_delta
    output = h' + MLP(post_attention_layernorm(h'))
by changing the norm input and adding the same delta to the layer output.

Projected memory is supplied externally, never derived from a future candidate.
No projector, source qualification, generator integration or study claim lives
here. Gradient checkpointing is explicitly unsupported. Use state_dict, not
whole-object pickling. Attach/remove are structural operations, not concurrent
with model execution. Tests and model operations are remote-only.
"""
from contextlib import contextmanager, nullcontext
from contextvars import ContextVar
from dataclasses import dataclass
import hashlib
import json
import re
import weakref

import torch
from torch import nn

from hybrid.knowledge_attention import PolicyReferenceEvidenceAttention

PINNED_TRANSFORMERS = '4.51.3'
_OWNER = '_method_evidence_hook_owner'
_CACHE = '_method_evidence_cache_binding'


@dataclass(frozen=True)
class _MemoryContext:
    memory: torch.Tensor
    mask: torch.Tensor
    digest: str
    reference: bool


def _tensor_hash(tensor):
    value = tensor.detach().contiguous()
    digest = hashlib.sha256(str((tuple(value.shape), str(value.dtype))).encode())
    digest.update(value.view(torch.uint8).cpu().numpy().tobytes())
    return digest.hexdigest()


class LlamaEvidenceHooks(nn.Module):
    """Explicit attach/remove adapter over selected decoder layers.

    Usage: hooks.attach(); with hooks.condition(memory, mask, source_digest):
    model(...). No context (or enabled=False) is exactly bridge-disabled.
    Memory [B,M,D] and Boolean mask [B,M] must contain a valid null/evidence slot.
    Context entry clones input values, preserving any projection autograd graph;
    all calls in that context use the same snapshot and content-bound digest.
    Optimise hooks.trainable_parameters(), not the frozen reference copies.
    """
    def __init__(self, model, layer_indices, heads):
        super().__init__()
        import transformers
        from transformers.models.llama.modeling_llama import LlamaForCausalLM, LlamaModel
        if transformers.__version__ != PINNED_TRANSFORMERS:
            raise ValueError('evidence hooks require Transformers ' + PINNED_TRANSFORMERS)
        if type(model) not in (LlamaForCausalLM, LlamaModel):
            raise TypeError('only the pinned unwrapped Llama model classes are supported')
        core = model.model if isinstance(model, LlamaForCausalLM) else model
        indices = tuple(layer_indices)
        if not indices or any(isinstance(i,bool) or not isinstance(i,int) or not 0<=i<len(core.layers) for i in indices):
            raise ValueError('layer indices must be nonempty valid integers')
        if len(set(indices)) != len(indices):raise ValueError('duplicate evidence layer index')
        if indices != tuple(sorted(indices)):raise ValueError('layer indices must be sorted')
        if core.gradient_checkpointing:raise ValueError('gradient checkpointing is unsupported')
        self.layer_indices, self.hidden_dim = indices, core.config.hidden_size
        self.heads = heads
        # Weak references avoid registering/copying the billion-parameter base.
        self._model_ref, self._core_ref = weakref.ref(model), weakref.ref(core)
        self.bridges = nn.ModuleDict()
        for i in indices:
            parameter = core.layers[i].post_attention_layernorm.weight
            self.bridges[str(i)] = PolicyReferenceEvidenceAttention(self.hidden_dim, heads).to(device=parameter.device,dtype=parameter.dtype)
        self._owner = object()
        self._handles = []
        self._context = ContextVar('evidence_context_' + str(id(self)), default=None)
        self._frames = {i:ContextVar('evidence_frame_'+str(id(self))+'_'+str(i),default=()) for i in indices}
        self._calls = ContextVar('evidence_model_calls_'+str(id(self)),default=())

    def get_extra_state(self):
        return dict(schema=1, layer_indices=list(self.layer_indices), hidden_dim=self.hidden_dim,
                    heads=self.heads, transformers_version=PINNED_TRANSFORMERS)

    def set_extra_state(self, state):
        if state != self.get_extra_state():
            raise ValueError("evidence decoder checkpoint configuration mismatch")

    def load_state_dict(self, state_dict, strict=True, assign=False):
        # Validate before any parameter can be changed, even with strict=False.
        self.set_extra_state(state_dict.get("_extra_state"))
        return super().load_state_dict(state_dict, strict=strict, assign=assign)

    def _load_from_state_dict(self, state_dict, prefix, *args, **kwargs):
        # Also cover this module when nested in a larger checkpoint.
        self.set_extra_state(state_dict.get(prefix + "_extra_state"))
        return super()._load_from_state_dict(state_dict, prefix, *args, **kwargs)

    def _model(self):
        model = self._model_ref()
        if model is None:raise RuntimeError('underlying model no longer exists')
        return model

    def _check_runtime(self):
        if self._core_ref().gradient_checkpointing:
            raise ValueError('gradient checkpointing is unsupported')

    def trainable_parameters(self):
        return (p for bridge in self.bridges.values() for p in bridge.trainable_parameters())

    @contextmanager
    def condition(self, memory=None, mask=None, source_digest=None, *, enabled=True, reference=False):
        if not self._handles:raise RuntimeError('evidence hooks are not attached')
        if not isinstance(enabled,bool) or not isinstance(reference,bool):raise ValueError('context flags must be Boolean')
        self._check_runtime()
        context = None
        if enabled:
            if not isinstance(source_digest,str) or not re.fullmatch('[0-9a-f]{64}',source_digest):
                raise ValueError('source digest must be a SHA-256 hex digest')
            if not isinstance(memory,torch.Tensor) or memory.ndim!=3 or memory.shape[-1]!=self.hidden_dim:
                raise ValueError('projected memory must be [B,M,hidden_dim]')
            if not isinstance(mask,torch.Tensor) or mask.dtype!=torch.bool or mask.shape!=memory.shape[:2]:
                raise ValueError('memory mask must be Boolean [B,M]')
            if not memory.shape[0] or not memory.shape[1] or not bool(mask.any(1).all()):
                raise ValueError('each memory row requires an admitted slot')
            if not memory.is_floating_point() or not bool(torch.isfinite(memory).all()) or memory.device!=mask.device:
                raise ValueError('memory must be finite floating values on the mask device')
            frozen_memory, frozen_mask = memory.clone(), mask.clone()
            digest = hashlib.sha256(json.dumps([source_digest,_tensor_hash(frozen_memory),_tensor_hash(frozen_mask)]).encode()).hexdigest()
            context = _MemoryContext(frozen_memory,frozen_mask,digest,reference)
        token = self._context.set(context)
        try:
            with torch.no_grad() if reference else nullcontext():
                yield None if context is None else context.digest
        finally:
            self._context.reset(token)

    def _signature(self):
        context = self._context.get()
        branch = 'reference' if context is not None and context.reference else 'policy'
        bridge_parameters = (p for b in self.bridges.values() for p in
                             (b._reference.parameters() if branch=='reference' else b.policy.parameters()))
        # Cached self-attention states also depend on earlier bridge/base weights.
        versions = tuple(p._version for p in self._model().parameters()) + tuple(p._version for p in bridge_parameters)
        return (self._owner,None if context is None else context.digest,branch,versions)

    def _model_pre(self, module, args, kwargs):
        # always_call runs the posthook even when this prehook raises.
        # Push a sentinel first so a failure cannot consume an outer frame.
        self._calls.set(self._calls.get() + (None,))
        self._check_runtime()
        if len(args)>1:raise ValueError('prototype supports only input_ids positionally; pass other arguments by keyword')
        signature = self._signature()
        cache = kwargs.get('past_key_values')
        if cache is not None:
            from transformers.cache_utils import DynamicCache
            if not isinstance(cache,DynamicCache):raise ValueError('prototype supports DynamicCache only')
            prior = getattr(cache,_CACHE,None)
            if prior != signature and (prior is not None or cache.get_seq_length()>0):
                raise ValueError('cache belongs to different evidence, reference or weights')
            setattr(cache,_CACHE,('pending',self._owner))
        self._calls.set(self._calls.get()[:-1]+((signature,cache),))

    def _model_post(self, module, args, kwargs, output):
        calls = self._calls.get()
        if not calls:return
        frame = calls[-1]
        self._calls.set(calls[:-1])
        if frame is None:return
        signature, original_cache = frame
        if output is None:return  # failed input cache stays pending/unusable
        from transformers.cache_utils import Cache, DynamicCache
        cache = getattr(output,'past_key_values',None)
        if cache is None and isinstance(output,tuple):
            cache = next((item for item in output if isinstance(item,Cache)),None)
        if cache is not None:
            if not isinstance(cache,DynamicCache):raise ValueError('prototype supports DynamicCache only')
            setattr(cache,_CACHE,signature)
        elif original_cache is not None:
            setattr(original_cache,_CACHE,signature)

    def _layer_pre(self, index):
        def begin(module,args):
            self._frames[index].set(self._frames[index].get()+(None,))
            self._check_runtime()
        return begin

    def _norm_pre(self, index):
        def modify(module,args):
            context = self._context.get()
            if context is None:return None
            frames = self._frames[index].get()
            if not frames or frames[-1] is not None:raise RuntimeError('invalid evidence layer invocation frame')
            if len(args)!=1:raise RuntimeError('unexpected pinned norm call signature')
            hidden = args[0]
            bridge = self.bridges[str(index)]
            if context.reference:
                with bridge.reference_mode():changed=bridge(hidden,context.memory,context.mask)
            else:
                changed=bridge(hidden,context.memory,context.mask)
            self._frames[index].set(frames[:-1]+(changed-hidden,))
            return (changed,)
        return modify

    def _layer_post(self, index):
        def finish(module,args,output):
            frames = self._frames[index].get()
            if not frames:return None
            delta = frames[-1]
            self._frames[index].set(frames[:-1])
            if output is None or delta is None:return None
            if not isinstance(output,tuple) or not output:raise RuntimeError('unexpected pinned layer output')
            return (output[0]+delta,)+output[1:]
        return finish

    def attach(self):
        if self._handles:raise RuntimeError('evidence hooks are already attached')
        self._check_runtime()
        core=self._core_ref(); model=self._model()
        targets=[model]+[module for i in self.layer_indices for module in (core.layers[i],core.layers[i].post_attention_layernorm)]
        if any(getattr(module,_OWNER,None) is not None for module in targets):
            raise RuntimeError('evidence hook owner already attached')
        try:
            for module in targets:setattr(module,_OWNER,self._owner)
            self._handles.append(model.register_forward_pre_hook(self._model_pre,with_kwargs=True))
            self._handles.append(model.register_forward_hook(self._model_post,with_kwargs=True,always_call=True))
            for i in self.layer_indices:
                layer=core.layers[i]
                self._handles.extend([layer.register_forward_pre_hook(self._layer_pre(i)),
                    layer.post_attention_layernorm.register_forward_pre_hook(self._norm_pre(i)),
                    layer.register_forward_hook(self._layer_post(i),always_call=True)])
        except Exception:
            self.remove()
            raise
        return self

    def remove(self):
        if self._calls.get() or any(frame.get() for frame in self._frames.values()):
            raise RuntimeError('cannot remove evidence hooks during a forward')
        for handle in self._handles:handle.remove()
        self._handles=[]
        core=self._core_ref();model=self._model_ref()
        targets=([model] if model is not None else [])
        if core is not None:
            targets += [module for i in self.layer_indices for module in (core.layers[i],core.layers[i].post_attention_layernorm)]
        for module in targets:
            if getattr(module,_OWNER,None) is self._owner:delattr(module,_OWNER)
