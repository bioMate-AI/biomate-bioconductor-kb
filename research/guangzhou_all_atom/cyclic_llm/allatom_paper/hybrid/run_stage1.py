"""Bounded REAL-model integration; validation gates must be frozen before study mode.

Run from allatom_paper on EC2 Spot. --mode smoke creates explicitly non-study
outputs. Study runs require exact approved manifest hashes and the M1 result.
No cloud provisioning, no publication, and no held-out scores used for updates.
Learned null/on arms require an approved mapping for every selected parent,
including newly retrieved parents. Unknowns stop the run; there is no resampling
or fallback that changes the candidate pool. Base-only M1 evidence does not
authorize the new learned architecture in study mode.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import sys
import time
from types import SimpleNamespace

AP=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(AP)); sys.path.insert(0,str(AP/'track_e'))


def file_sha(path):
    h=hashlib.sha256()
    with open(path,'rb') as stream:
        for data in iter(lambda:stream.read(4*1024*1024),b''): h.update(data)
    return h.hexdigest()


def load_gate(path,sha):
    if file_sha(path)!=sha:
        raise ValueError('frozen gate file SHA256 mismatch')
    return json.loads(Path(path).read_text())


def completed_result(root, initialization_identity):
    """Return finalised output after bind_run has checked current inputs.

    Legacy/incomplete output fails closed instead of re-scoring held-out data.
    """
    path=Path(root)/'result.json'
    if not path.exists():
        return None
    result=json.loads(path.read_text())
    if (not isinstance(result,dict) or result.get('execution_completed') is not True
            or result.get('run_identity_sha256')!=file_sha(Path(root)/'run_identity.json')
            or result.get('initialization_identity')!=initialization_identity):
        raise ValueError('existing result is incomplete or bound to a different initialization/run')
    return result


def validate_m1_evidence(evidence, initialization_identity, learned_knowledge_interface=None):
    """Bind the reviewed M1 decision to this exact pretrained initialization.

    This validates certificate identity, not the underlying scientific criteria;
    those remain the responsibility of the separately reviewed M1 evidence.
    """
    if (not isinstance(evidence,dict) or evidence.get('passed') is not True
            or evidence.get('real_model') is not True):
        raise ValueError('real-model M1 has not passed')
    if evidence.get('initialization_identity')!=initialization_identity:
        raise ValueError('M1 evidence initialization differs from requested model')
    if learned_knowledge_interface is not None and evidence.get('learned_knowledge_interface')!=learned_knowledge_interface:
        raise ValueError('M1 evidence learned knowledge interface differs from requested model')


class FrozenParentProtocol:
    """Shared candidate pool for bundle-backed off/null/on comparisons.

    Online structures remain in oracle/retrieval history, but do not become
    parents. Retrieval does not rank parents in this explicit protocol; its
    scientific contribution requires a separately specified comparison.
    Pool admission uses metadata/exclusions only, never evidence availability.
    """
    def __init__(self, inputs):
        from hybrid.knowledge_parent import REQUIRED_SCOPE
        from hybrid.knowledge_memory import content_digest
        admitted=[];excluded=[]
        for parent in sorted(inputs.parent_map.values(),key=lambda p:p.id):
            scope=dict(parent.scope)
            reason=None
            if (not parent.source_families or not set(parent.source_families)<=set(inputs.allowed)
                    or set(parent.source_families)&set(inputs.forbidden)):
                reason='source_exclusion'
            elif parent.compound_id in inputs.forbidden_compounds:reason='compound_exclusion'
            elif parent.scaffold_id in inputs.forbidden_scaffolds:reason='scaffold_exclusion'
            elif scope.get('target') in inputs.forbidden_targets or inputs.task_scope.get('target') in inputs.forbidden_targets:
                reason='target_exclusion'
            elif not REQUIRED_SCOPE<=scope.keys():reason='incomplete_parent_scope'
            elif any(k in scope and scope[k]!=v for k,v in inputs.task_scope.items()):reason='task_scope_conflict'
            if reason is not None:excluded.append(dict(parent_id=parent.id,reason=reason))
            else:admitted.append(dict(parent_id=parent.id,smiles=parent.smiles))
        if not admitted:raise ValueError('frozen parent protocol has no approved parents')
        self.parents=tuple(row['smiles'] for row in admitted)
        self.config=dict(schema='frozen_parent_pool_v1',parents=admitted,excluded=excluded,
            pool_sha256=content_digest(admitted),online_parent_promotion=False,retrieval_parent_ranking=False)

    def context_builder(self, cfg):
        from contracts import PromptContext
        def build(round_idx, oracle, retriever):
            # Do not inspect online top molecules or retrieve unknown candidates.
            return PromptContext(objective=cfg.objective,seed_smiles=self.parents,retrieved=(),
                extra={'parent_protocol':self.config['schema'],'parent_pool_sha256':self.config['pool_sha256']})
        return build


class FrozenParentInputs:
    """Bind pool identity without mutating the evidence provider's config copy."""
    def __init__(self, inputs, protocol):
        self._inputs=inputs
        from copy import deepcopy
        self._protocol=deepcopy(protocol.config)

    @property
    def config(self):
        from copy import deepcopy
        config=self._inputs.config
        config['parent_protocol']=deepcopy(self._protocol)
        return config

    @property
    def parent_map(self):return self._inputs.parent_map

    @property
    def task_scope(self):return self._inputs.task_scope

    def __call__(self, smiles):return self._inputs(smiles)

    def validate_memory(self, memory):return self._inputs.validate_memory(memory)


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--mode',choices=['smoke','study'],required=True)
    p.add_argument('--model-dir',required=True); p.add_argument('--out',required=True)
    p.add_argument('--adaptation-dir')
    p.add_argument('--initialization-manifest')
    p.add_argument('--initialization-manifest-sha256')
    p.add_argument('--family',choices=['F1','F2'],required=True)
    p.add_argument('--seed',type=int,required=True)
    p.add_argument('--arm',choices=['hybrid','no-rules','no-feedback','no-retrieval','no-monitor'],default='hybrid')
    p.add_argument('--level',choices=['L0','L1','L2','L3'],default='L0')
    p.add_argument('--budget',type=int,default=1000); p.add_argument('--max-seconds',type=float,default=14400)
    p.add_argument('--a6'); p.add_argument('--manifest'); p.add_argument('--manifest-sha'); p.add_argument('--m1'); p.add_argument('--m1-sha')
    p.add_argument('--learned-knowledge-arm',choices=['off','null','on'],default='off')
    p.add_argument('--learned-knowledge-bundle'); p.add_argument('--learned-knowledge-bundle-sha')
    p.add_argument('--knowledge-arm',choices=['off','on','provenance-control'],default='off')
    p.add_argument('--knowledge-catalogue'); p.add_argument('--knowledge-sha')
    p.add_argument('--parent-map'); p.add_argument('--parent-map-sha')
    p.add_argument('--knowledge-task'); p.add_argument('--knowledge-task-sha')
    p.add_argument('--allow-synthetic-knowledge',action='store_true')
    p.add_argument('--retrieval-store'); p.add_argument('--retrieval-store-sha')
    p.add_argument('--retrieval-mode',choices=['fingerprint','embedding','hybrid'],default='fingerprint')
    p.add_argument('--retrieval-alpha',type=float,default=.5)
    p.add_argument('--encoder-dir'); p.add_argument('--encoder-manifest'); p.add_argument('--encoder-manifest-sha')
    p.add_argument('--ann',required=True)
    a=p.parse_args()
    if a.budget<=0 or a.max_seconds<=0: raise ValueError('positive budget/time required')
    if not math.isfinite(a.retrieval_alpha) or not 0<=a.retrieval_alpha<=1:
        raise ValueError('retrieval alpha must be finite in [0,1]')
    for path,sha in ((a.retrieval_store,a.retrieval_store_sha),(a.knowledge_task,a.knowledge_task_sha),
                     (a.knowledge_catalogue,a.knowledge_sha),(a.parent_map,a.parent_map_sha),
                     (a.encoder_manifest,a.encoder_manifest_sha),(a.learned_knowledge_bundle,a.learned_knowledge_bundle_sha)):
        if bool(path)!=bool(sha):raise ValueError('input path and frozen hash must be supplied together')
        if path:load_gate(path,sha)
    if a.arm=='no-retrieval' and any((a.retrieval_store,a.retrieval_store_sha,a.encoder_dir,
            a.encoder_manifest,a.encoder_manifest_sha,a.retrieval_mode!='fingerprint')):
        raise ValueError('no-retrieval arm must not configure a store or encoder')
    if a.retrieval_mode!='fingerprint' and not all((a.encoder_dir,a.encoder_manifest,a.encoder_manifest_sha)):
        raise ValueError('embedding retrieval requires pinned encoder files')
    if a.retrieval_mode=='fingerprint' and any((a.encoder_dir,a.encoder_manifest,a.encoder_manifest_sha)):
        raise ValueError('fingerprint retrieval must not configure unused encoder files')
    if a.allow_synthetic_knowledge and a.mode!='smoke':
        raise ValueError('synthetic inputs prohibited outside smoke')
    if a.knowledge_arm!='off' and not a.knowledge_catalogue:
        raise ValueError('knowledge-on/control requires a frozen catalogue')
    if a.knowledge_catalogue and not all((a.parent_map,a.knowledge_task)):
        raise ValueError('knowledge catalogue requires parent map and task')
    if a.learned_knowledge_arm!='off' and not a.learned_knowledge_bundle:
        raise ValueError('learned null/on requires a frozen bundle')
    if a.learned_knowledge_bundle and not all((a.parent_map,a.knowledge_task)):
        raise ValueError('learned bundle requires frozen parent map and source-policy task')
    if a.retrieval_store and not a.knowledge_task:
        raise ValueError('reviewed retrieval requires a source-policy task')
    from hybrid.initialization import prepare_initialization
    initialization_identity=prepare_initialization(a.model_dir,
        adaptation_dir=a.adaptation_dir,manifest_path=a.initialization_manifest,
        manifest_sha256=a.initialization_manifest_sha256)
    if a.mode=='study':
        if not all([a.manifest,a.manifest_sha,a.m1,a.m1_sha,a.a6]): raise ValueError('study requires frozen A6/integration manifest and M1 evidence')
        manifest=load_gate(a.manifest,a.manifest_sha); m1=load_gate(a.m1,a.m1_sha)
        if manifest.get('status')!='FROZEN_STAGE1' or not manifest.get('remaining_spot_budget_verified'):
            raise ValueError('study manifest not frozen or remaining authorized Spot budget unverified')
        validate_m1_evidence(m1,initialization_identity)
        expected={'budget':1000,'max_seconds':14400,'source_groups':'v2','scale':'z_gen',
                  'monitor':'current_top10_no_duplicate_pool','lr_raise_factor':2.0,'reference':initialization_identity['reference'],
                  'kl_statistic':'mean_categorical_token_kl_on_pair_contexts'}
        for key,value in expected.items():
            if manifest.get(key)!=value: raise ValueError('unfrozen integration setting: '+key)
        if manifest.get('initialization_identity')!=initialization_identity:
            raise ValueError('initialization differs from frozen study manifest')
        if a.budget!=1000 or a.max_seconds!=14400 or a.seed not in manifest.get('seeds',[]): raise ValueError('study budget/time/seed differs from manifest')
        if not manifest.get('a6_sha256') or a.family not in manifest.get('evaluation_margins',{}): raise ValueError('A6 margins missing')
        a6=load_gate(a.a6,manifest['a6_sha256'])
        if a6.get('status')!='FROZEN_A6' or a6.get('margin_fraction')!=.10:
            raise ValueError('A6 result not reviewed/frozen with original margin fraction')
        for family in ('F1','F2'):
            measured=a6['families'][family]['margin_sd_auc']
            if manifest['evaluation_margins'].get(family)!=measured:
                raise ValueError('manifest margin differs from verified A6 artifact')
        if a.arm not in manifest.get('arms',[]) or a.level not in manifest.get('levels',[]): raise ValueError('unregistered arm/level')
    else:
        manifest={}
        if a.budget>100 or a.max_seconds>1800: raise ValueError('smoke bounded to100calls/1800seconds')
    from hybrid.knowledge_inputs import resolve_knowledge_inputs
    groups=json.loads((AP/'track_e/source_groups_v2.json').read_text())['membership']
    train_families=[name for name,g in groups.items() if g['group']=='A']
    excluded_families=[name for name,g in groups.items() if g['group']!='A']
    task={};allowed_families=train_families
    if a.knowledge_task:
        if a.learned_knowledge_bundle and 'scope' not in load_gate(a.knowledge_task,a.knowledge_task_sha):
            raise ValueError('learned bundle requires explicit reviewed source-policy task')
        task,allowed_families,excluded_families=resolve_knowledge_inputs(
            load_gate(a.knowledge_task,a.knowledge_task_sha),manifest,study=a.mode=='study',
            training_source_families=train_families,forbidden_source_families=excluded_families)
    learned_inputs=None;parent_protocol=None;bound_learned_inputs=None;learned_interface=None
    if a.learned_knowledge_bundle:
        from hybrid.learned_knowledge_inputs import LearnedKnowledgeInputs
        if a.mode=='study':
            for key in ('knowledge_forbidden_compounds','knowledge_forbidden_scaffolds','knowledge_forbidden_targets'):
                if key not in manifest:raise ValueError('learned split exclusions not frozen: '+key)
        learned_inputs=LearnedKnowledgeInputs(
            load_gate(a.learned_knowledge_bundle,a.learned_knowledge_bundle_sha),
            load_gate(a.parent_map,a.parent_map_sha),task,
            bundle_sha256=a.learned_knowledge_bundle_sha,parent_map_sha256=a.parent_map_sha,
            task_sha256=a.knowledge_task_sha,arm=a.learned_knowledge_arm,study=a.mode=='study',
            allowed_source_families=allowed_families,forbidden_source_families=excluded_families,
            forbidden_compounds=manifest.get('knowledge_forbidden_compounds',[]),
            forbidden_scaffolds=manifest.get('knowledge_forbidden_scaffolds',[]),
            forbidden_targets=manifest.get('knowledge_forbidden_targets',[]),
            allow_synthetic=a.allow_synthetic_knowledge and a.mode=='smoke')
        parent_protocol=FrozenParentProtocol(learned_inputs)
        bound_learned_inputs=FrozenParentInputs(learned_inputs,parent_protocol)
        learned_interface=bound_learned_inputs.config
        if a.mode=='study' and manifest.get('learned_knowledge_interface')!=learned_interface:
            raise ValueError('learned knowledge differs from frozen study manifest')
        if a.mode=='study' and a.learned_knowledge_arm!='off':
            validate_m1_evidence(m1,initialization_identity,learned_interface)
    elif a.mode=='study' and manifest.get('learned_knowledge_interface') is not None:
        raise ValueError('study manifest requires learned knowledge bundle')
    retrieval_config=dict(store_sha256=a.retrieval_store_sha,task_sha256=a.knowledge_task_sha,
        mode=a.retrieval_mode,alpha=a.retrieval_alpha,encoder_manifest_sha256=a.encoder_manifest_sha,
        enabled=a.arm!='no-retrieval')
    if a.mode=='study' and manifest.get('retrieval_interface')!=retrieval_config:
        raise ValueError('retrieval configuration differs from frozen study manifest')
    initial_rows=[];retrieval_provenance=[];encoder=None
    if a.retrieval_store:
        from hybrid.retrieval_inputs import validate_retrieval_inputs
        from retrieval.store import canon as retrieval_canon
        if a.mode=='study':
            for key in ('knowledge_forbidden_compounds','knowledge_forbidden_scaffolds',
                        'knowledge_forbidden_targets','knowledge_forbidden_docs','retrieval_training_score_keys'):
                if key not in manifest:raise ValueError('retrieval exclusions/score keys not frozen: '+key)
        initial_rows,retrieval_provenance=validate_retrieval_inputs(
            load_gate(a.retrieval_store,a.retrieval_store_sha),
            allowed_score_keys=manifest.get('retrieval_training_score_keys',['train']),
            allowed_source_families=allowed_families,forbidden_source_families=excluded_families,
            forbidden_compounds=manifest.get('knowledge_forbidden_compounds',[]),
            forbidden_scaffolds=manifest.get('knowledge_forbidden_scaffolds',[]),
            forbidden_targets=manifest.get('knowledge_forbidden_targets',[]),
            forbidden_docs=manifest.get('knowledge_forbidden_docs',[]),
            allow_synthetic=a.allow_synthetic_knowledge and a.mode=='smoke',canonicalize=retrieval_canon)
    if a.mode=='study' and a.arm!='no-retrieval' and not initial_rows:
        raise ValueError('study retrieval requires a nonempty reviewed initial store')
    encoder_files=None
    if a.encoder_manifest:
        from hybrid.peptide_encoder import verify_encoder_files
        encoder_files=load_gate(a.encoder_manifest,a.encoder_manifest_sha)
        verify_encoder_files(a.encoder_dir,encoder_files)
    from hybrid.run_guard import bind_run, remaining_seconds
    root=Path(a.out)
    identity_args=vars(a).copy()
    identity_args.pop('out')
    # Include runtime inputs and implementation; no checkpoint may silently cross
    # a model, tokenizer, dataset, code, arm, seed or scientific-setting change.
    input_paths=[Path(a.ann), AP/'track_e/source_groups_v2.json']
    input_paths += sorted(p for p in Path(a.model_dir).iterdir() if p.is_file())
    if a.adaptation_dir:
        input_paths += sorted(p for p in Path(a.adaptation_dir).iterdir() if p.is_file())
    if a.initialization_manifest:
        input_paths.append(Path(a.initialization_manifest))
    # Reference scales and seed generation import predecessor packages outside
    # allatom_paper; bind the whole cyclic_llm Python source closure as well.
    input_paths += sorted(AP.parent.rglob('*.py'))
    for path in (a.knowledge_catalogue,a.parent_map,a.knowledge_task,a.retrieval_store,a.encoder_manifest,a.learned_knowledge_bundle):
        if path:input_paths.append(Path(path))
    if a.encoder_dir:
        input_paths += sorted(p for p in Path(a.encoder_dir).rglob('*') if p.is_file())
    identity=dict(arguments=identity_args, file_sha256={str(p.resolve()):file_sha(p) for p in input_paths})
    from knowledge_augment.levels import build_level
    if a.level=='L2' and a.mode=='study' and 'knowledge_forbidden_targets' not in manifest:
        raise ValueError('L2 requires explicit frozen target exclusions')
    level=build_level(a.level,exclude_tokens=manifest.get('knowledge_forbidden_targets',[]))
    identity['level_config_hash']=level.config_hash
    identity['initialization_identity']=initialization_identity
    identity['learned_knowledge_interface']=learned_interface
    run_record=bind_run(root,identity,a.max_seconds)
    previous=completed_result(root,initialization_identity)
    if previous is not None:
        print(json.dumps(dict(status='ALREADY_COMPLETED',result_path=str(root/'result.json'),
                              run_identity_sha256=previous['run_identity_sha256'])),flush=True)
        return
    if a.mode=='study' and a.level in ('L1','L2') and not level.config['audit']['final_eligible']:
        raise ValueError('unaudited knowledge may not enter final study')
    from hybrid.model import ChemFMGenerator
    from hybrid.adapters import ChemicalRetriever,CurrentTopMonitor,RealPreferenceUpdater
    from orchestrator.loop import LoopConfig,JsonlLogger,run_loop
    from pmo_harness import check_three_way
    import run_stage0 as E
    E.setup(SimpleNamespace(out=str(root),max_seconds=a.max_seconds,gen_ref_n=1500,ann=a.ann,
                            groups='v2',scale='z_gen',n_ref=20))
    train,stop,held=E.family_objs(a.family)
    check_three_way([train],[stop],held)
    generator=ChemFMGenerator(a.model_dir,E.G['seeds'],seed=a.seed,masked=a.arm!='no-rules',
        adaptation_dir=a.adaptation_dir,initialization_manifest=a.initialization_manifest,
        initialization_manifest_sha256=a.initialization_manifest_sha256)
    if a.knowledge_arm!='off' and not a.knowledge_catalogue:
        raise ValueError('knowledge-on/control requires actual frozen evidence catalogue')
    if a.allow_synthetic_knowledge and a.mode!='smoke':
        raise ValueError('synthetic evidence prohibited outside smoke')
    if a.knowledge_catalogue:
        from hybrid.knowledge_parent import ConditionalParentSelector,Parent
        if not all([a.knowledge_sha,a.parent_map,a.parent_map_sha,a.knowledge_task,a.knowledge_task_sha]):
            raise ValueError('knowledge path requires catalogue/map/task hashes')
        parent_rows=load_gate(a.parent_map,a.parent_map_sha)
        parent_objects=[Parent.from_record(row) for row in parent_rows]
        if len({p.smiles for p in parent_objects})!=len(parent_objects):
            raise ValueError('duplicate chemical parent mapping')
        selector=ConditionalParentSelector(a.knowledge_catalogue,a.knowledge_sha,
            allowed_source_families=allowed_families,
            forbidden_source_families=excluded_families,
            forbidden_compounds=manifest.get('knowledge_forbidden_compounds',[]),
            forbidden_scaffolds=manifest.get('knowledge_forbidden_scaffolds',[]),
            forbidden_targets=manifest.get('knowledge_forbidden_targets',[]),
            allow_synthetic=a.allow_synthetic_knowledge)
        if a.mode=='study':
            required={'catalogue_sha256':a.knowledge_sha,'parent_map_sha256':a.parent_map_sha,
                      'task_sha256':a.knowledge_task_sha,'arm':a.knowledge_arm}
            if manifest.get('knowledge_interface')!=required:
                raise ValueError('knowledge mechanism differs from frozen study manifest')
            if not selector.evidence:raise ValueError('knowledge arm not instantiated: accepted catalogue empty')
            for key in ('knowledge_forbidden_compounds','knowledge_forbidden_scaffolds','knowledge_forbidden_targets'):
                if key not in manifest:raise ValueError('knowledge split exclusions not explicitly frozen')
        generator.configure_knowledge(selector,{p.smiles:p for p in parent_objects},task,a.knowledge_arm,a.parent_map_sha)
    if learned_inputs is not None:
        generator.learned_input_config=learned_interface
    if learned_inputs is not None and a.learned_knowledge_arm!='off':
        architecture=learned_inputs.architecture
        generator.configure_learned_knowledge(learned_inputs.bundle['feature_schema'],
            learned_inputs.config['payload_digests']['feature_schema'],architecture['layer_indices'],architecture['heads'],
            category_width=architecture['category_width'],type_width=architecture['type_width'],
            hidden_width=architecture['hidden_width'])
        generator.set_knowledge_provider(bound_learned_inputs)
    constraint=level.constraint(generator.vocab)
    if encoder_files is not None:
        from hybrid.peptide_encoder import FrozenPeptideEncoder
        encoder=FrozenPeptideEncoder(a.encoder_dir,encoder_files)
    retriever=None if a.arm=='no-retrieval' else ChemicalRetriever(initial_rows,
        embed_fn=encoder,model_tag=encoder.model_tag if encoder else None,
        retrieval_mode=a.retrieval_mode,alpha=a.retrieval_alpha)
    monitor=CurrentTopMonitor(enabled=a.arm!='no-monitor')
    updater=None if a.arm=='no-feedback' else RealPreferenceUpdater(generator,monitor)
    cfg=LoopConfig(run_id=root.name,method=a.arm,objective=a.family,seed=a.seed,budget=a.budget,
                   n_per_round=64,lr=1e-4,beta=.1,margin=.02,max_seconds=a.max_seconds)
    cfg.max_seconds=remaining_seconds(run_record)
    generator.deadline=time.monotonic()+cfg.max_seconds
    logger=JsonlLogger(str(root/'rounds.jsonl')).start()
    try:
        result=run_loop(cfg,generator,train,constraint,stop,retriever,updater,monitor,
                        logger=logger,canon=E.VE.canon,ckpt_dir=str(root/'checkpoint'),
                        ctx_builder=parent_protocol.context_builder(cfg) if parent_protocol is not None else None)
    finally:
        logger.close()
    result['heldout']={}
    # This measurement never repairs the failed F1 admissibility floor.
    for verifier in held:
        values=[verifier.fn(s) for s in result['top_smiles']]
        result['heldout'][verifier.name]=sum(values)/len(values) if values else None
    result.update(run_identity_sha256=file_sha(root/'run_identity.json'),deadline_unix=run_record['deadline_unix'],mode=a.mode,real_model=True,knowledge_config=level.config,
        initialization_identity=generator.initialization_identity,execution_completed=True,
        knowledge_config_hash=level.config_hash,manifest_sha256=a.manifest_sha,a6_sha256=manifest.get('a6_sha256'),
        kl_statistic='mean_categorical_token_kl_on_pair_contexts',
        source_groups_sha256=file_sha(AP/'track_e/source_groups_v2.json'),
        model_sha256=file_sha(Path(a.model_dir)/'model.safetensors'),
        knowledge_interface=generator.knowledge_config,knowledge_history=generator.extra_state.get('knowledge_history',[]),
        retrieval_interface=retrieval_config,retrieval_provenance=retrieval_provenance,
        learned_knowledge_interface=learned_interface,
        learned_round_identity=generator.extra_state.get('learned_round_identity'),
        parent_protocol=parent_protocol.config if parent_protocol else None,
        encoder_diagnostics=encoder.diagnostics if encoder else None,
        sampling_last_round=generator.last_stats,sampling_history=generator.extra_state.get('sampling_history',[]),optimizer_steps=generator.steps,
        primary_gate_ceiling='INCONCLUSIVE',scope='pipeline diagnostic' if a.mode=='smoke' else 'registered stage1')
    tmp=root/'result.json.tmp'; tmp.write_text(json.dumps(result,indent=2,default=lambda x:x.tolist() if hasattr(x,'tolist') else float(x))); tmp.replace(root/'result.json')
    print(json.dumps({k:result[k] for k in ['mode','calls','optimizer_steps','stop_reason','primary_gate_ceiling']}),flush=True)


if __name__=='__main__': main()
