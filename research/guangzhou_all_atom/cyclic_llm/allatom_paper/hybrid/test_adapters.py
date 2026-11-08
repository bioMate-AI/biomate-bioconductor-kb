"""Run on EC2 Spot. Interface tests are not real-model performance evidence."""
import sys
import pytest
import numpy as np
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from hybrid.adapters import ChemicalRetriever,CurrentTopMonitor,RealPreferenceUpdater
from contracts import PreferencePair


def test_current_top_monitor_does_not_duplicate_pool_and_restores():
    monitor=CurrentTopMonitor()
    monitor.update(0,list(range(10)),list(range(10)))
    monitor.update(1,list(range(1,11)),list(range(1,11)))
    assert len(monitor.inner.pool_t)==10
    assert monitor.inner.T[-1]==5.5
    restored=CurrentTopMonitor(); restored.load_state_dict(monitor.state_dict())
    assert restored.update(2,list(range(2,12)),list(range(2,12)))==monitor.update(2,list(range(2,12)),list(range(2,12)))


def test_retrieval_adapter_exposes_tuple_contract_and_excludes_self():
    r=ChemicalRetriever(); r.add('CCO',{'train':1.0}); r.add('CCN',{'train':2.0})
    hits=r.query('CCO',2)
    assert hits==[('CCN',{'train':2.0})]


def test_preference_gate_restored_from_generator_checkpoint_state():
    class Policy:
        extra_state={}
        lrs=[]
        def dpo_step(self,pairs,lr,beta):
            self.lrs.append(lr)
            return {'loss':0.6,'kl':0.0,'weight_delta_rel':0.0}
    p=Policy(); m=CurrentTopMonitor(); u=RealPreferenceUpdater(p,m)
    pair=[PreferencePair('CCO','CCN',1.0)]
    for r in range(4): u.observe_round(r,u.step(pair,1e-4,.1))
    assert p.extra_state['updater']['lr_multiplier']==2.0
    u=RealPreferenceUpdater(p,m)  # resume from generator-carried gate state
    for r in range(4,6): u.observe_round(r,u.step(pair,1e-4,.1))
    assert p.lrs[-1]==2e-4
    assert m.update_gate_stop


def test_no_pair_rounds_advance_gate_without_fabricated_kl():
    class Policy:
        extra_state={}
        def dpo_step(self,*args):raise AssertionError('no update allowed')
    policy=Policy(); monitor=CurrentTopMonitor(); updater=RealPreferenceUpdater(policy,monitor)
    actions=[]
    for r in range(6):
        pairs,diag=updater.make_pairs(['CCO'],[1.0],0.02)
        assert not pairs and diag['frac_small_groups_dropped']==1
        result=updater.observe_round(r,None,diag)
        actions.append(result['update_gate'])
        assert 'kl' not in result and 'loss' not in result
        assert result['update_gate_reason']=='no_preference_pairs'
        assert not result['optimizer_updated']
    assert actions==['continue','continue','continue','raise_lr_rank_once','continue','stop']
    assert monitor.update_gate_stop and policy.extra_state['updater']['next_round']==6
    with pytest.raises(ValueError,match='consecutive'):
        updater.observe_round(5)


def test_gate_tracks_search_rounds_when_updates_are_intermittent():
    class Policy:
        extra_state={}
        def dpo_step(self,*args):return {'loss':0.2,'kl':0.1,'weight_delta_rel':0.1}
    policy=Policy(); updater=RealPreferenceUpdater(policy,None)
    pair=[PreferencePair('CCO','CCN',1.0)]
    for r in range(3):updater.observe_round(r,updater.step(pair,1e-4,.1) if r==0 else None)
    assert updater.observe_round(3,None)['update_gate']=='raise_lr_rank_once'
    restored=RealPreferenceUpdater(policy,None)
    assert restored.observe_round(4,restored.step(pair,1e-4,.1))['update_gate']=='continue'
    assert restored.observe_round(5,None)['update_gate']=='stop'


def test_initial_retrieval_metadata_online_metadata_and_resume():
    rows=[dict(smiles='OCC',scores={'train':1.0},doc='paper-a',doc_year=2020,target='T',source='lab-a')]
    r=ChemicalRetriever(rows)
    r.add('CCN',{'train':2.0},doc='paper-b',doc_year=2021,target='T',source='lab-b')
    saved=r.state_dict()
    assert saved['rows'][0]['smiles']=='CCO'
    assert saved['rows'][1]['source']=='lab-b' and saved['rows'][1]['doc']=='paper-b'
    assert r.query('CCC',5,exclude_docs={'paper-a'},strict_docs=True)==[('CCN',{'train':2.0})]
    restored=ChemicalRetriever();restored.load_state_dict(saved)
    assert restored.state_dict()==saved
    assert restored.query('CCC',5,max_year=2020,strict_docs=True)==[('CCO',{'train':1.0})]
    with pytest.raises(ValueError,match='flat key'):
        ChemicalRetriever([dict(smiles='CCO',flat_key='CCN')])
    with pytest.raises(ValueError,match='nonfinite'):
        ChemicalRetriever([dict(smiles='CCO',scores={'train':float('nan')})])


def test_embedding_arm_updates_index_and_preserves_encoder_identity():
    calls=[]
    vectors={'CCO':[1,0],'CCN':[0,1],'CCC':[0,1],'CCCC':[1,1]}
    def embed(smiles):
        calls.append(list(smiles))
        return np.asarray([vectors[s] for s in smiles],dtype=np.float32)
    r=ChemicalRetriever([dict(smiles='CCO',scores={})],embed_fn=embed,model_tag='synthetic-v1',retrieval_mode='embedding')
    assert r.query('CCC',1)[0][0]=='CCO'
    r.add('CCN',{'train':2},source='online-test')
    assert r.query('CCC',1)[0][0]=='CCN'
    assert r.inner.emb.smiles==[row.smiles for row in r.inner.store.rows]
    assert sum(batch.count('CCO') for batch in calls)==1  # old rows are not repeatedly encoded
    state=r.state_dict()
    restored=ChemicalRetriever(embed_fn=embed,model_tag='synthetic-v1',retrieval_mode='embedding')
    restored.load_state_dict(state)
    assert restored.query('CCC',1)==r.query('CCC',1)
    with pytest.raises(ValueError,match='arm or encoder'):
        ChemicalRetriever(embed_fn=embed,model_tag='other',retrieval_mode='embedding').load_state_dict(state)
    with pytest.raises(ValueError,match='frozen encoder'):
        ChemicalRetriever(retrieval_mode='hybrid')
    with pytest.raises(ValueError,match='fixed'):
        r.query('CCC',1,mode='fingerprint')


def test_fingerprint_default_does_not_call_injected_encoder():
    def forbidden(smiles):raise AssertionError('fingerprint arm must not encode')
    r=ChemicalRetriever([dict(smiles='CCO',scores={})],embed_fn=forbidden,model_tag='unused')
    assert r.query('CCN',1)==[('CCO',{})]


def test_no_monitor_disables_only_goodhart_and_round_gate_remains_active():
    class Policy:
        def __init__(self):self.extra_state={}
    monitor=CurrentTopMonitor(enabled=False)
    def forbidden(*args):raise AssertionError('disabled Goodhart monitor executed')
    monitor.inner.update=forbidden
    updater=RealPreferenceUpdater(Policy(),monitor)
    for r in range(6):
        updater.observe_round(r)
        decision=monitor.update(r,[0,10],[10,0])
        assert decision['gap'] is None and not decision['goodhart_enabled']
        assert decision['should_stop']==(r==5)
    assert not monitor.inner.T and not monitor.inner.S
    state=monitor.state_dict()
    resumed=CurrentTopMonitor(enabled=False);resumed.load_state_dict(state)
    assert resumed.update(6,[0,10],[10,0])['should_stop']
    with pytest.raises(ValueError,match='ablation changed'):
        CurrentTopMonitor(enabled=True).load_state_dict(state)
