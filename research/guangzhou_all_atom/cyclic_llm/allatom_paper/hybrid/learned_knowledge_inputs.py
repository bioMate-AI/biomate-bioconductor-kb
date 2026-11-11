"""Frozen, explicitly approved static evidence inputs for opt-in learned arms.

The runner verifies file hashes before construction. This provider resolves a
single selected parent before packing; it never uses measured outcomes, changes
parent choice, or silently falls back when a parent is unknown or excluded.
"""
from copy import deepcopy
from dataclasses import asdict
import json
import re

from hybrid.knowledge_memory import content_digest, pack_static_memory
from hybrid.knowledge_parent import Parent, REQUIRED_SCOPE, scope_pairs


def _ids(values, name, nonempty=False):
    if (not isinstance(values,(list,tuple)) or any(not isinstance(v,str) or not v.strip() for v in values)
            or len(set(values))!=len(values) or (nonempty and not values)):
        raise ValueError('invalid '+name)
    return tuple(sorted(values))


class LearnedKnowledgeInputs:
    def __init__(self,bundle,parent_rows,task_scope,*,bundle_sha256,parent_map_sha256,task_sha256,
                 arm,study,allowed_source_families,forbidden_source_families=(),
                 forbidden_compounds=(),forbidden_scaffolds=(),forbidden_targets=(),allow_synthetic=False):
        if arm not in ('off','null','on'):raise ValueError('unknown learned knowledge arm')
        if type(study) is not bool or type(allow_synthetic) is not bool:raise ValueError('mode flags must be Boolean')
        if study and allow_synthetic:raise ValueError('synthetic knowledge prohibited in study')
        for value in (bundle_sha256,parent_map_sha256,task_sha256):
            if not isinstance(value,str) or not re.fullmatch('[0-9a-f]{64}',value):raise ValueError('frozen file SHA256 required')
        if not isinstance(bundle,dict) or set(bundle)!={'schema','catalogue','feature_schema','embeddings','architecture'}:
            raise ValueError('invalid learned knowledge bundle fields')
        if bundle['schema']!='learned_knowledge_bundle_v1':raise ValueError('unknown learned knowledge bundle schema')
        architecture=bundle['architecture']
        if not isinstance(architecture,dict) or set(architecture)!={'layer_indices','heads','category_width','type_width','hidden_width','max_slots'}:
            raise ValueError('invalid learned architecture fields')
        layers=architecture['layer_indices']
        if (not isinstance(layers,list) or not layers or any(type(i) is not int or i<0 for i in layers)
                or layers!=sorted(set(layers))):raise ValueError('invalid learned layer indices')
        for key in ('heads','category_width','type_width','max_slots'):
            if type(architecture[key]) is not int or architecture[key]<1:raise ValueError('invalid architecture '+key)
        if architecture['hidden_width'] is not None and (type(architecture['hidden_width']) is not int or architecture['hidden_width']<1):
            raise ValueError('invalid architecture hidden_width')
        catalogue=bundle['catalogue']
        if (not isinstance(catalogue,dict) or catalogue.get('schema')!='learned_conditioning_catalogue_v1'
                or catalogue.get('review_status')!='FROZEN_REVIEWED' or type(catalogue.get('synthetic')) is not bool):
            raise ValueError('learned catalogue must be frozen reviewed')
        if catalogue['synthetic'] and not allow_synthetic:raise ValueError('synthetic catalogue prohibited')
        if not isinstance(parent_rows,list) or not parent_rows:raise ValueError('reviewed parent map is empty')
        parents=[Parent.from_record(row) for row in parent_rows]
        if len({p.id for p in parents})!=len(parents) or len({p.smiles for p in parents})!=len(parents):
            raise ValueError('duplicate parent identity or chemical mapping')
        self.parent_map={p.smiles:p for p in parents}
        self._by_id={p.id:p for p in parents}
        self.task_scope=dict(scope_pairs(task_scope))
        self.allowed=_ids(allowed_source_families,'allowed source families',True)
        self.forbidden=_ids(forbidden_source_families,'forbidden source families')
        if set(self.allowed)&set(self.forbidden):raise ValueError('source policy overlaps')
        self.forbidden_compounds=_ids(forbidden_compounds,'forbidden compounds')
        self.forbidden_scaffolds=_ids(forbidden_scaffolds,'forbidden scaffolds')
        self.forbidden_targets=_ids(forbidden_targets,'forbidden targets')
        self.arm,self.study,self.allow_synthetic=arm,study,allow_synthetic
        self.bundle=deepcopy(bundle);self.architecture=deepcopy(architecture)
        self._hashes={key:content_digest(bundle[key]) for key in ('catalogue','feature_schema','embeddings')}
        self._config=dict(schema='learned_knowledge_interface_v1',bundle_sha256=bundle_sha256,
            parent_map_sha256=parent_map_sha256,task_sha256=task_sha256,arm=arm,
            architecture=deepcopy(architecture),payload_digests=dict(self._hashes),task_scope=dict(self.task_scope),
            allowed_source_families=list(self.allowed),forbidden_source_families=list(self.forbidden),
            forbidden_compounds=list(self.forbidden_compounds),forbidden_scaffolds=list(self.forbidden_scaffolds),
            forbidden_targets=list(self.forbidden_targets),synthetic=catalogue['synthetic'])
        self.__runtime_fingerprint=content_digest(self._runtime_payload())

    def _runtime_payload(self):
        """Bind live behavior, not just its original descriptive config dict."""
        return dict(parent_map={key:asdict(value) for key,value in self.parent_map.items()},
            by_id={key:asdict(value) for key,value in self._by_id.items()},
            task_scope=self.task_scope,allowed=self.allowed,forbidden=self.forbidden,
            forbidden_compounds=self.forbidden_compounds,forbidden_scaffolds=self.forbidden_scaffolds,
            forbidden_targets=self.forbidden_targets,arm=self.arm,study=self.study,
            allow_synthetic=self.allow_synthetic,bundle=self.bundle,architecture=self.architecture,
            payload_hashes=self._hashes,config=self._config)

    def _assert_frozen(self):
        try:actual=content_digest(self._runtime_payload())
        except (TypeError,ValueError,AttributeError) as exc:
            raise ValueError('learned input runtime state changed') from exc
        if actual!=self.__runtime_fingerprint:
            raise ValueError('learned input runtime state changed')

    @property
    def config(self):
        self._assert_frozen()
        return deepcopy(self._config)

    def __call__(self,smiles):
        self._assert_frozen()
        if self.arm=='off':raise ValueError('off arm has no learned memory')
        parent=self.parent_map.get(smiles)
        if parent is None:raise ValueError('selected parent lacks approved mapping')
        if (not set(parent.source_families)<=set(self.allowed) or set(parent.source_families)&set(self.forbidden)
                or parent.compound_id in self.forbidden_compounds or parent.scaffold_id in self.forbidden_scaffolds):
            raise ValueError('selected parent violates source/compound/scaffold exclusions')
        scope=dict(parent.scope)
        if not REQUIRED_SCOPE<=scope.keys():raise ValueError('selected parent scope is incomplete')
        if scope.get('target') in self.forbidden_targets or self.task_scope.get('target') in self.forbidden_targets:
            raise ValueError('selected parent/task target is excluded')
        if any(k in scope and scope[k]!=v for k,v in self.task_scope.items()):
            raise ValueError('selected parent scope conflicts with task')
        scope.update(self.task_scope)
        if not REQUIRED_SCOPE<=scope.keys():raise ValueError('selected parent/task scope is incomplete')
        # Exclusions precede source text dereferencing and vector packing. The
        # packer also excludes forbidden evidence families and target scopes.
        forbidden_parent_ids=[p.id for p in self.parent_map.values() if
            p.compound_id in self.forbidden_compounds or p.scaffold_id in self.forbidden_scaffolds
            or dict(p.scope).get('target') in self.forbidden_targets
            or not set(p.source_families)<=set(self.allowed) or set(p.source_families)&set(self.forbidden)]
        memory=pack_static_memory(self.bundle['catalogue'],self.bundle['feature_schema'],self.bundle['embeddings'],
            catalogue_digest=self._hashes['catalogue'],schema_digest=self._hashes['feature_schema'],
            embeddings_digest=self._hashes['embeddings'],task_scope=scope,parent_ids=[parent.id],
            allowed_source_families=self.allowed,forbidden_source_families=self.forbidden,
            forbidden_targets=self.forbidden_targets,forbidden_parent_ids=forbidden_parent_ids,
            enabled=self.arm=='on',max_slots=self.architecture['max_slots'],allow_synthetic=self.allow_synthetic)
        if self.study and self.arm=='on' and not any(kind==1 for kind in memory.slot_type):
            raise ValueError('study learned-on requires eligible evidence for selected parent')
        return memory

    def validate_memory(self,memory):
        self._assert_frozen()
        audit=json.loads(memory.audit_json)
        ids=audit.get('parent_ids')
        if not isinstance(ids,list) or len(ids)!=1 or ids[0] not in self._by_id:
            raise ValueError('saved memory lacks one approved selected parent')
        expected=self(self._by_id[ids[0]].smiles)
        if expected!=memory:raise ValueError('saved memory differs from frozen learned inputs')
