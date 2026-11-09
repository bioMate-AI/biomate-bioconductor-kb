"""Trainable typed projection of frozen static evidence, independent of decoder wiring."""
import json
import math
import torch
from torch import nn
from hybrid.knowledge_memory import CATEGORIES,StaticMemory,content_digest


class KnowledgeProjector(nn.Module):
    def __init__(self,feature_schema,*,schema_digest,output_width,category_width=8,type_width=4,hidden_width=None):
        super().__init__()
        if content_digest(feature_schema)!=schema_digest:raise ValueError('feature schema digest mismatch')
        if not isinstance(feature_schema,dict) or set(feature_schema)!={'schema','categories','embedding_width'}:
            raise ValueError('invalid feature schema fields')
        if feature_schema['schema']!='static_knowledge_features_v1':raise ValueError('unknown feature schema')
        categories=feature_schema['categories']
        if not isinstance(categories,dict) or set(categories)!=set(CATEGORIES):raise ValueError('invalid categorical fields')
        sizes=[]
        for key in CATEGORIES:
            values=categories[key]
            if (not isinstance(values,(list,tuple)) or len(values)<2
                    or any(not isinstance(v,str) or not v for v in values)
                    or len(set(values))!=len(values) or list(values[:2])!=['__missing__','__unknown__']):
                raise ValueError('invalid categorical vocabulary')
            sizes.append(len(values))
        hidden_width=output_width if hidden_width is None else hidden_width
        widths=(feature_schema['embedding_width'],output_width,category_width,type_width,hidden_width)
        if any(type(v) is not int or v<1 for v in widths):raise ValueError('projection widths must be positive integers')
        self.schema_digest=schema_digest
        self.molecular_width,self.output_width,self.category_width,self.type_width,self.hidden_width=widths
        self.category_sizes=tuple(sizes)
        self.category_embeddings=nn.ModuleList(nn.Embedding(n,category_width,padding_idx=0) for n in sizes)
        self.type_embedding=nn.Embedding(2,type_width,padding_idx=0)
        width=self.molecular_width+1+len(CATEGORIES)*(category_width+1)+type_width
        self.projection=nn.Sequential(nn.Linear(width,hidden_width),nn.GELU(),nn.Linear(hidden_width,output_width))

    def get_extra_state(self):
        return dict(schema_digest=self.schema_digest,category_order=list(CATEGORIES),category_sizes=list(self.category_sizes),
            molecular_width=self.molecular_width,output_width=self.output_width,category_width=self.category_width,
            type_width=self.type_width,hidden_width=self.hidden_width)

    def set_extra_state(self,state):
        if state!=self.get_extra_state():raise ValueError('projection checkpoint schema/order/configuration mismatch')

    def _prevalidate_checkpoint(self,state_dict,prefix=''):
        # Check before torch copies this module's children, including same-shape
        # vocabularies whose semantic IDs have changed. strict=False is no bypass.
        if state_dict.get(prefix+'_extra_state')!=self.get_extra_state():
            raise ValueError('projection checkpoint schema/order/configuration mismatch')

    def load_state_dict(self,state_dict,strict=True,assign=False):
        self._prevalidate_checkpoint(state_dict)
        return super().load_state_dict(state_dict,strict=strict,assign=assign)

    def _load_from_state_dict(self,state_dict,prefix,local_metadata,strict,
                              missing_keys,unexpected_keys,error_msgs):
        """Protect this projector when restored as a child of a larger module.

        PyTorch may already have copied preceding sibling modules. Composite
        callers requiring whole-model atomicity must prevalidate every child
        manifest before starting their root load, or load into a fresh model.
        """
        self._prevalidate_checkpoint(state_dict,prefix)
        return super()._load_from_state_dict(state_dict,prefix,local_metadata,strict,
                                             missing_keys,unexpected_keys,error_msgs)

    def _validate(self,memory):
        if not isinstance(memory,StaticMemory):raise ValueError('expected immutable StaticMemory')
        names=('molecular','categorical','categorical_present','molecular_present','eligible','slot_type','numeric','numeric_present')
        slots=len(memory.eligible)
        if slots<1 or any(not isinstance(getattr(memory,k),tuple) or len(getattr(memory,k))!=slots for k in names):
            raise ValueError('memory slot shape mismatch')
        try:audit=json.loads(memory.audit_json)
        except (TypeError,ValueError) as exc:raise ValueError('invalid memory audit') from exc
        if not isinstance(audit,dict) or audit.get('schema_digest')!=self.schema_digest:
            raise ValueError('memory feature schema mismatch')
        payload={k:getattr(memory,k) for k in names};payload['audit']=audit
        if content_digest(payload)!=memory.digest:raise ValueError('immutable memory digest mismatch')
        for i in range(slots):
            vector=memory.molecular[i];cat=memory.categorical[i];available=memory.categorical_present[i]
            if not isinstance(vector,tuple) or len(vector)!=self.molecular_width or any(type(v) not in (float,int) or not math.isfinite(v) for v in vector):
                raise ValueError('invalid molecular feature shape/value')
            if not isinstance(cat,tuple) or len(cat)!=len(CATEGORIES) or not isinstance(available,tuple) or len(available)!=len(CATEGORIES):
                raise ValueError('invalid categorical feature shape')
            if type(memory.molecular_present[i]) is not bool or type(memory.eligible[i]) is not bool or any(type(v) is not bool for v in available):
                raise ValueError('availability masks must be Boolean')
            for j,(value,present) in enumerate(zip(cat,available)):
                if type(value) is not int or not 0<=value<self.category_sizes[j]:raise ValueError('categorical ID out of range')
                if (value!=0)!=present:raise ValueError('categorical ID/missingness mismatch')
            kind=memory.slot_type[i]
            if type(kind) is not int or kind not in (0,1):raise ValueError('unsupported memory channel')
            if memory.numeric[i]!=() or memory.numeric_present[i]!=():raise ValueError('numeric/history inputs unsupported')
            if not memory.molecular_present[i] and any(v!=0 for v in vector):raise ValueError('missing molecular feature must be zero')
            if kind==0:
                if any(vector) or any(cat) or any(available) or memory.molecular_present[i]:
                    raise ValueError('null/padding payload must be zero')
                if memory.eligible[i]!=(i==0):raise ValueError('only slot zero is valid null')
            elif i==0 or not memory.eligible[i]:raise ValueError('static evidence slot must be eligible and non-null')
        if memory.slot_type[0]!=0 or memory.eligible[0] is not True:raise ValueError('missing always-valid null slot')

    def forward(self,memories):
        """Return projected [B,M,D] and eligible [B,M]; no input feature gradients.

        All snapshots must share capacity. Audits bind the schema and integrity;
        their source IDs, hashes and review metadata never enter numeric features.
        deepcopy(module).requires_grad_(False) provides an independent reference.
        """
        if not isinstance(memories,(list,tuple)) or not memories:raise ValueError('nonempty memory batch required')
        for memory in memories:self._validate(memory)
        if len({len(m.eligible) for m in memories})!=1:raise ValueError('batch memory capacities differ')
        parameter=self.projection[0].weight;device,dtype=parameter.device,parameter.dtype
        molecular=torch.tensor([m.molecular for m in memories],device=device,dtype=dtype).detach()
        if not torch.isfinite(molecular).all():raise ValueError('molecular features overflow projection dtype')
        ids=torch.tensor([m.categorical for m in memories],device=device,dtype=torch.long)
        available=torch.tensor([m.categorical_present for m in memories],device=device,dtype=dtype)
        mol_available=torch.tensor([m.molecular_present for m in memories],device=device,dtype=dtype)
        kinds=torch.tensor([m.slot_type for m in memories],device=device,dtype=torch.long)
        eligible=torch.tensor([m.eligible for m in memories],device=device,dtype=torch.bool)
        features=[molecular*mol_available.unsqueeze(-1),mol_available.unsqueeze(-1)]
        for j,embedding in enumerate(self.category_embeddings):
            present=available[:,:,j:j+1]
            features.extend((embedding(ids[:,:,j])*present,present))
        features.append(self.type_embedding(kinds))
        projected=self.projection(torch.cat(features,dim=-1))
        # Biases and learned embeddings cannot turn absence into evidence.
        projected=projected.masked_fill((kinds==0).unsqueeze(-1),0.)
        if not torch.isfinite(projected).all():raise FloatingPointError('nonfinite projected memory')
        return projected,eligible
