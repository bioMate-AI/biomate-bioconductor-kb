"""Conditional mined-evidence parent selection; no numeric priors or chemistry edits.

This adapter implements a prospective mechanism, not a scientifically eligible
catalogue. Synthetic fixtures require explicit opt-in and cannot enter study
mode. All permissions, source exclusions, scope and approved parent mappings
must be supplied by a reviewed frozen catalogue; nothing is inferred from tiers.
"""
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
from typing import Tuple

SCOPE_FIELDS=frozenset(('property','assay','scaffold','closure','solvent','endpoint','target','site'))
REQUIRED_SCOPE=frozenset(('property','assay','scaffold','closure','solvent','endpoint'))


def digest(data):return hashlib.sha256(data).hexdigest()

def scope_pairs(raw):
    if not isinstance(raw,dict) or set(raw)-SCOPE_FIELDS:
        raise ValueError('unknown scope field; labels/residuals are not query inputs')
    if any(not isinstance(v,str) or not v.strip() or v=='*' for v in raw.values()):
        raise ValueError('scope requires explicit nonempty strings, not wildcards')
    return tuple(sorted(raw.items()))


@dataclass(frozen=True)
class Parent:
    id: str
    smiles: str
    compound_id: str
    scaffold_id: str
    source_families: Tuple[str,...]
    scope: Tuple[Tuple[str,str],...]

    @classmethod
    def from_record(cls,row):
        for key in ('id','smiles','compound_id','scaffold_id'):
            if not isinstance(row.get(key),str) or not row[key]:raise ValueError('parent missing '+key)
        families=row.get('source_families')
        if not isinstance(families,list) or not families or any(not isinstance(v,str) or not v for v in families):
            raise ValueError('parent source lineage missing')
        return cls(row['id'],row['smiles'],row['compound_id'],row['scaffold_id'],tuple(sorted(set(families))),scope_pairs(row.get('scope',{})))


@dataclass(frozen=True)
class Evidence:
    id: str
    rule_id: str
    source_id: str
    source_sha256: str
    raw_sha256: str
    evidence_family: str
    source_families: Tuple[str,...]
    scope: Tuple[Tuple[str,str],...]
    parent_ids: Tuple[str,...]
    quote: str
    quote_start: int
    quote_end: int
    tradeoffs: Tuple[str,...]


class ConditionalParentSelector:
    def __init__(self,catalogue_path,expected_sha256,*,allowed_source_families,
                 forbidden_source_families=(),forbidden_compounds=(),forbidden_scaffolds=(),
                 forbidden_targets=(),allow_synthetic=False):
        raw=Path(catalogue_path).read_bytes()
        if digest(raw)!=expected_sha256:raise ValueError('knowledge catalogue manifest mismatch')
        document=json.loads(raw)
        if document.get('schema')!='conditional_parent_v1':raise ValueError('unknown catalogue schema')
        self.synthetic=document.get('synthetic') is True
        if self.synthetic and not allow_synthetic:raise ValueError('synthetic catalogue prohibited')
        if not self.synthetic and document.get('review_status')!='FROZEN_REVIEWED':
            raise ValueError('real catalogue not scientifically reviewed/frozen')
        self.catalogue_sha256=expected_sha256
        self.allowed=frozenset(allowed_source_families);self.forbidden=frozenset(forbidden_source_families)
        if self.allowed & self.forbidden:raise ValueError('source split overlaps')
        self.forbidden_compounds=frozenset(forbidden_compounds);self.forbidden_scaffolds=frozenset(forbidden_scaffolds)
        self.forbidden_targets=frozenset(forbidden_targets)
        sources=document.get('sources',{});accepted=[];denied=[];seen=set()
        for row in document.get('evidence',[]):
            eid=row.get('id')
            if not isinstance(eid,str) or not eid or eid in seen:raise ValueError('missing/duplicate evidence ID')
            seen.add(eid)
            # Exclude before dereferencing source text: no forbidden-source access.
            families=row.get('source_families',[])
            if not families or not set(families)<=self.allowed or set(families)&self.forbidden:
                denied.append((eid,'source_lineage_denied'));continue
            if row.get('permission')!='conditional_proposal' or row.get('action')!='select_parent':
                denied.append((eid,'action_not_allowed'));continue
            if row.get('review_status')!='approved_for_scoped_parent_selection' or row.get('unresolved_flags'):
                denied.append((eid,'review_incomplete'));continue
            scope=scope_pairs(row.get('scope',{}))
            if not REQUIRED_SCOPE<=dict(scope).keys():
                denied.append((eid,'unknown_scope'));continue
            if dict(scope).get('target') in self.forbidden_targets:
                denied.append((eid,'heldout_target'));continue
            if row.get('position_specific') and 'site' not in dict(scope):
                denied.append((eid,'missing_site_map'));continue
            source=sources.get(row.get('source_id'))
            if not isinstance(source,dict):raise ValueError('missing approved source record')
            for field in ('url','accessed','text','sha256'):
                if not isinstance(source.get(field),str) or not source[field]:raise ValueError('source missing '+field)
            if digest(source['text'].encode())!=source['sha256']:raise ValueError('source text hash mismatch')
            start,end=row.get('quote_start'),row.get('quote_end');quote=row.get('quote')
            if not isinstance(start,int) or not isinstance(end,int) or not isinstance(quote,str) or not quote or not 0<=start<end<=len(source['text']):
                raise ValueError('invalid quotation offsets')
            if source['text'][start:end]!=quote:raise ValueError('altered quotation')
            ids=row.get('approved_parent_ids',[])
            if not ids or any(not isinstance(v,str) or not v for v in ids):
                denied.append((eid,'no_reviewed_parent_mapping'));continue
            for field in ('rule_id','extraction_run','code_revision','model_revision','evidence_family'):
                if not isinstance(row.get(field),str) or not row[field]:raise ValueError('evidence missing '+field)
            accepted.append(Evidence(eid,row['rule_id'],row['source_id'],source['sha256'],
                digest(json.dumps(row,sort_keys=True).encode()),row['evidence_family'],tuple(sorted(set(families))),
                scope,tuple(sorted(set(ids))),quote,start,end,tuple(row.get('tradeoffs',[]))))
        self.evidence=tuple(sorted(accepted,key=lambda e:e.id));self.denied=tuple(denied)

    def validate_parents(self, parents, task_scope):
        """Validate known provenance even when the sampling pool also has unknowns."""
        task=dict(scope_pairs(task_scope));parents=tuple(parents)
        if task.get('target') in self.forbidden_targets:raise ValueError('task requests heldout target')
        if len({p.id for p in parents})!=len(parents):raise ValueError('duplicate parent pool')
        for p in parents:
            if not p.source_families or not set(p.source_families)<=self.allowed or set(p.source_families)&self.forbidden:
                raise ValueError('parent pool source leakage')
            if p.compound_id in self.forbidden_compounds or p.scaffold_id in self.forbidden_scaffolds:
                raise ValueError('parent pool compound/scaffold leakage')
            if dict(p.scope).get('target') in self.forbidden_targets:raise ValueError('parent pool target leakage')

    def select(self,parents,task_scope,rng,*,arm,round_seed):
        if arm not in ('off','on','provenance-control'):raise ValueError('unknown knowledge arm')
        task=dict(scope_pairs(task_scope));parents=tuple(parents)
        if not parents or len({p.id for p in parents})!=len(parents):raise ValueError('empty/duplicate parent pool')
        self.validate_parents(parents,task_scope)
        baseline=parents[int(rng.integers(len(parents)))];matches=[];predicates=[]
        if arm!='off':
            for parent in parents:
                context=dict(parent.scope)
                # Task cannot silently overwrite a contradictory recorded molecular scope.
                conflict=any(k in context and context[k]!=v for k,v in task.items())
                context.update(task)
                for evidence in self.evidence:
                    expected=dict(evidence.scope)
                    if arm=='provenance-control':expected['scaffold']='__INAPPLICABLE_CONTROL__'
                    passed=not conflict and parent.id in evidence.parent_ids and all(context.get(k)==v for k,v in expected.items())
                    predicates.append(dict(parent_id=parent.id,evidence_id=evidence.id,inputs=context,passed=passed))
                    if passed:matches.append((parent,evidence))
        choices={p.id:p for p,e in matches}
        chosen=choices[sorted(choices)[int(rng.integers(len(choices)))]] if choices else baseline
        used=tuple(e for p,e in matches if p.id==chosen.id)
        trace=dict(catalogue_sha256=self.catalogue_sha256,arm=arm,synthetic=self.synthetic,
            instantiated=bool(self.evidence),knowledge_used=bool(used),round_seed=round_seed,
            parent_pool_ids=[p.id for p in parents],baseline_parent_id=baseline.id,selected_parent_id=chosen.id,
            evidence=[dict(id=e.id,rule_id=e.rule_id,source_sha256=e.source_sha256,raw_sha256=e.raw_sha256,
                           evidence_family=e.evidence_family,tradeoffs=list(e.tradeoffs)) for e in used],
            predicates=predicates,excluded=list(self.denied),fallback=None if used else 'knowledge_off' if arm=='off' else 'no_applicable_evidence',
            action='select_parent',prefix_sha256=None)
        return chosen,trace


def choose_parent(pool,selector,parent_map,task_scope,rng,arm,seed):
    """Use evidence only for mapped parents; unknowns remain baseline-only candidates.

    All arms draw their baseline from the identical full pool. Known provenance is
    validated before any fallback. No scope or provenance is guessed for unknowns.
    """
    if not pool:raise ValueError('empty chemical pool')
    if selector is None:
        return pool[int(rng.integers(len(pool)))],None
    if arm not in ('off','on','provenance-control'):raise ValueError('unknown knowledge arm')
    if len(set(pool))!=len(pool):raise ValueError('duplicate chemical pool')
    unknown=[s for s in pool if s not in parent_map]
    known=[parent_map[s] for s in pool if s in parent_map]
    if any(parent_map[s].smiles!=s for s in pool if s in parent_map):
        raise ValueError('parent mapping chemical identity mismatch')
    selector.validate_parents(known,task_scope)
    baseline=pool[int(rng.integers(len(pool)))]
    if known:
        chosen,trace=selector.select(known,task_scope,rng,arm=arm,round_seed=seed)
        parent=chosen.smiles if trace['knowledge_used'] else baseline
    else:
        parent=baseline
        trace=dict(catalogue_sha256=selector.catalogue_sha256,arm=arm,round_seed=seed,
            instantiated=bool(selector.evidence),knowledge_used=False,fallback='unknown_parent_metadata',
            evidence=[],predicates=[],excluded=list(selector.denied),synthetic=selector.synthetic,
            action='select_parent',prefix_sha256=None)
    trace.update(unknown_parent_hashes=[digest(s.encode()) for s in unknown],
        parent_pool_hashes=[digest(s.encode()) for s in pool],
        baseline_parent_id=parent_map[baseline].id if baseline in parent_map else None,
        selected_parent_id=parent_map[parent].id if parent in parent_map else None,
        baseline_parent_sha256=digest(baseline.encode()),selected_parent_sha256=digest(parent.encode()))
    if arm=='off':trace['fallback']='knowledge_off'
    return parent,trace
