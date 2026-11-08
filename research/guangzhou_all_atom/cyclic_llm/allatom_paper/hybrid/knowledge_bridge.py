"""Opt-in static evidence bridge for the pinned causal decoder.

The caller qualifies evidence and fixes one StaticMemory before sampling. Policy
and reference consume the same raw snapshot, through independently frozen
reference projection/attention weights. No retrieval or outcome access occurs.
"""
from contextlib import contextmanager
from copy import deepcopy
from dataclasses import asdict
import hashlib
import json

import torch
from torch import nn

from hybrid.knowledge_decoder import LlamaEvidenceHooks
from hybrid.knowledge_memory import StaticMemory
from hybrid.knowledge_projection import KnowledgeProjector


class LearnedKnowledgeBridge(nn.Module):
    def __init__(self, base_model, feature_schema, schema_digest, layer_indices, heads,
                 *, category_width=8, type_width=4, hidden_width=None):
        super().__init__()
        self.hooks = LlamaEvidenceHooks(base_model, layer_indices, heads)
        parameter = next(base_model.parameters())
        self.policy = KnowledgeProjector(feature_schema, schema_digest=schema_digest,
            output_width=self.hooks.hidden_dim, category_width=category_width,
            type_width=type_width, hidden_width=hidden_width).to(device=parameter.device,dtype=parameter.dtype)
        self.reference = deepcopy(self.policy).requires_grad_(False).eval()
        self.config = dict(feature_schema=deepcopy(feature_schema),schema_digest=schema_digest,
            decoder=self.hooks.get_extra_state(),projector=self.policy.get_extra_state())
        self.__reference_keys=tuple(sorted(key for key in self.state_dict()
            if key.startswith('reference.') or '._reference.' in key))
        self.__initial_reference_digest=self._reference_digest(self.state_dict())
        self.config['initial_reference_sha256']=self.__initial_reference_digest
        self.memory = None
        self.hooks.attach()

    def train(self, mode=True):
        super().train(mode)
        self.reference.eval()
        return self

    def trainable_parameters(self):
        return list(self.policy.parameters()) + list(self.hooks.trainable_parameters())

    def set_memory(self, memory):
        self.policy._validate(memory)
        # StaticMemory contains only immutable tuple/string primitives validated above.
        self.memory = deepcopy(memory)

    @property
    def digest(self):
        if self.memory is None:raise ValueError('set round knowledge before sampling or scoring')
        return self.memory.digest

    @contextmanager
    def condition(self, batch_size, *, reference=False):
        if type(batch_size) is not int or batch_size<1:raise ValueError('positive batch size required')
        digest=self.digest
        projector=self.reference if reference else self.policy
        # Fresh graph per forward: do not retain a projection graph across DPO pairs.
        with torch.set_grad_enabled(torch.is_grad_enabled() and not reference):
            projected,mask=projector([self.memory]*batch_size)
            with self.hooks.condition(projected,mask,digest,reference=reference):
                yield digest

    def delta_l2(self):
        with torch.no_grad():
            total=sum((p.float()-r.float()).square().sum() for p,r in
                      zip(self.policy.parameters(),self.reference.parameters()))
            for bridge in self.hooks.bridges.values():
                total=total+sum((p.float()-r.float()).square().sum() for p,r in
                               zip(bridge.policy.parameters(),bridge._reference.parameters()))
            return float(total.sqrt())

    def checkpoint(self):
        self._validate_reference_state(self.state_dict())
        return dict(config=deepcopy(self.config),state=self.state_dict(),
                    memory=None if self.memory is None else asdict(self.memory))

    def _reference_digest(self,state,prefix=''):
        """Hash actual frozen tensors/metadata, never a checkpoint's digest claim."""
        digest=hashlib.sha256()
        for key in self.__reference_keys:
            if prefix+key not in state:raise ValueError('frozen reference state missing: '+key)
            value=state[prefix+key]
            digest.update(json.dumps(key).encode())
            if isinstance(value,torch.Tensor):
                tensor=value.detach().contiguous().cpu()
                digest.update(json.dumps([str(tensor.dtype),list(tensor.shape)]).encode())
                digest.update(tensor.view(torch.uint8).numpy().tobytes())
            else:
                digest.update(json.dumps(value,sort_keys=True,separators=(',',':'),allow_nan=False).encode())
        return digest.hexdigest()

    def _validate_reference_state(self,state,prefix=''):
        if self._reference_digest(state,prefix)!=self.__initial_reference_digest:
            raise ValueError('frozen initial knowledge reference identity differs')

    def load_state_dict(self,state_dict,strict=True,assign=False):
        self._validate_reference_state(state_dict)
        return super().load_state_dict(state_dict,strict=strict,assign=assign)

    def _load_from_state_dict(self,state_dict,prefix,local_metadata,strict,
                              missing_keys,unexpected_keys,error_msgs):
        # Protect this bridge before its children are copied during nested load.
        # Whole-composite atomicity still requires caller prevalidation.
        self._validate_reference_state(state_dict,prefix)
        return super()._load_from_state_dict(state_dict,prefix,local_metadata,strict,
                                             missing_keys,unexpected_keys,error_msgs)

    def validate_checkpoint(self, payload):
        if not isinstance(payload,dict) or set(payload)!={'config','state','memory'} or payload['config']!=self.config:
            raise ValueError('learned knowledge checkpoint configuration differs')
        state=payload['state'];expected=self.state_dict()
        if not isinstance(state,dict) or set(state)!=set(expected):raise ValueError('bridge state keys differ')
        self._validate_reference_state(expected)
        self._validate_reference_state(state)
        for key,value in expected.items():
            found=state[key]
            if isinstance(value,torch.Tensor):
                if (not isinstance(found,torch.Tensor) or found.shape!=value.shape or found.dtype!=value.dtype
                        or not bool(torch.isfinite(found).all())):
                    raise ValueError('invalid bridge tensor: '+key)
            elif found!=value:raise ValueError('bridge state metadata differs: '+key)
        memory=payload['memory']
        if memory is not None:
            if not isinstance(memory,dict):raise ValueError('invalid saved round memory')
            try:memory=StaticMemory(**memory)
            except TypeError as exc:raise ValueError('invalid saved round memory') from exc
            self.policy._validate(memory)
        if self.memory is not None and (memory is None or memory.digest!=self.memory.digest):
            raise ValueError('checkpoint round knowledge memory differs from active memory')
        return memory

    def restore(self, payload):
        memory=self.validate_checkpoint(payload)
        self.load_state_dict(payload['state'])
        self.memory=deepcopy(memory)
        self.reference.requires_grad_(False).eval()
