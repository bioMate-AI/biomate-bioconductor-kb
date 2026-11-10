"""Explicit interface adapters; no toy generator is used in stage-1 runs."""
from dataclasses import asdict, replace
import math
from contextlib import nullcontext
import numpy as np
from feedback.stop_monitor import GapStopMonitor
from feedback.preference_updater import GradedPreferenceUpdater, KLWeightGate
from retrieval.retriever import Retriever
from retrieval.store import Row, canon
from retrieval.index import EmbeddingIndex


class ChemicalRetriever:
    """Tuple-contract bridge retaining the source metadata used by exclusions.

    Initial rows must already be scientifically eligible; this adapter validates
    their structural/schema consistency, not their eligibility or measurements.
    """
    def __init__(self, rows=(), *, embed_fn=None, model_tag=None,
                 retrieval_mode='fingerprint', alpha=0.5):
        if retrieval_mode not in ('fingerprint','embedding','hybrid'):
            raise ValueError('unknown retrieval mode')
        if not math.isfinite(alpha) or not 0<=alpha<=1:raise ValueError('invalid hybrid retrieval alpha')
        if retrieval_mode!='fingerprint' and (not callable(embed_fn) or not isinstance(model_tag,str) or not model_tag):
            raise ValueError('embedding retrieval requires a frozen encoder and model identity')
        self.embed_fn,self.model_tag=embed_fn,model_tag
        self.retrieval_mode,self.alpha=retrieval_mode,float(alpha)
        self._embedding_cache={};self._embedding_dirty=True
        self.inner = Retriever()
        self.build(rows)

    def build(self, rows):
        prepared=[]
        for raw in rows:
            row=asdict(raw) if isinstance(raw,Row) else dict(raw)
            if set(row)-{'smiles','flat_key','values','scores','doc','doc_year','target','source'}:
                raise ValueError('unknown retrieval row fields')
            if 'scores' in row and 'values' in row:
                raise ValueError('retrieval row has two score mappings')
            c=canon(row.get('smiles'))
            if c is None:raise ValueError('invalid initial retrieval molecule')
            if row.get('flat_key',c[1])!=c[1]:raise ValueError('retrieval flat key mismatch')
            values=self._scores(row.get('values',row.get('scores',{})))
            self._metadata(row.get('doc'),row.get('doc_year'),row.get('target'),row.get('source',''))
            prepared.append(Row(c[0],c[1],values,row.get('doc'),row.get('doc_year'),row.get('target'),row.get('source','')))
        self.inner.build(prepared)
        self._embedding_dirty=True
        return self

    @staticmethod
    def _scores(scores):
        if not isinstance(scores,dict) or any(not isinstance(k,str) or not k for k in scores):
            raise ValueError('retrieval scores require named values')
        values={k:float(v) for k,v in scores.items()}
        if not all(math.isfinite(v) for v in values.values()):raise ValueError('nonfinite retrieval score')
        return values

    @staticmethod
    def _metadata(doc,doc_year,target,source):
        if any(v is not None and not isinstance(v,str) for v in (doc,target)) or not isinstance(source,str):
            raise ValueError('retrieval provenance must be strings')
        if doc_year is not None and (not isinstance(doc_year,int) or isinstance(doc_year,bool)):
            raise ValueError('retrieval document year must be an integer')

    def _embed(self,smiles):
        missing=list(dict.fromkeys(s for s in smiles if s not in self._embedding_cache))
        if missing:
            # The injected encoder must also be frozen/eval; inference_mode prevents
            # accidental autograd graphs while keeping this bridge usable without torch.
            try:
                import torch
                context=torch.inference_mode()
            except ImportError:
                context=nullcontext()
            with context:
                values=np.asarray(self.embed_fn(missing),dtype=np.float32)
            if values.ndim!=2 or values.shape[0]!=len(missing) or not values.shape[1] or not np.isfinite(values).all():
                raise ValueError('encoder returned invalid retrieval embeddings')
            if self._embedding_cache and values.shape[1]!=len(next(iter(self._embedding_cache.values()))):
                raise ValueError('encoder dimension changed')
            self._embedding_cache.update((key,value.copy()) for key,value in zip(missing,values))
        return np.stack([self._embedding_cache[s] for s in smiles])

    def _ensure_embeddings(self):
        if self.retrieval_mode=='fingerprint' or not self.inner.store.rows:return
        if self._embedding_dirty or self.inner.emb is None:
            smiles=[r.smiles for r in self.inner.store.rows]
            emb=EmbeddingIndex(model_tag=self.model_tag).fit(smiles,self._embed)
            self.inner.attach_embeddings(emb,self._embed)
            self._embedding_dirty=False

    def query(self, smiles, k, exclude_docs=None, **filters):
        if 'mode' in filters or 'alpha' in filters:
            raise ValueError('retrieval mode and alpha are fixed by the selected arm')
        self._ensure_embeddings()
        return [(h.smiles,h.values) for h in self.inner.query(smiles,k,exclude_docs=exclude_docs,
                    mode=self.retrieval_mode,alpha=self.alpha,**filters)]

    def add(self, smiles, scores, doc=None, source='online', doc_year=None, target=None):
        self._metadata(doc,doc_year,target,source)
        added=self.inner.add(smiles,self._scores(scores),doc=doc,doc_year=doc_year,target=target)
        if added:
            # Retriever.add currently omits source although RetrievalStore supports it.
            self.inner.store.rows[-1]=replace(self.inner.store.rows[-1],source=source)
            self._embedding_dirty=True
        return added

    def state_dict(self):
        return {'schema':'chemical_retriever_v1','rows':[asdict(r) for r in self.inner.store.rows],
                'retrieval_config':{'mode':self.retrieval_mode,'model_tag':self.model_tag,'alpha':self.alpha}}

    def load_state_dict(self,state):
        if state.get('schema')!='chemical_retriever_v1':raise ValueError('unknown retrieval checkpoint schema')
        expected={'mode':self.retrieval_mode,'model_tag':self.model_tag,'alpha':self.alpha}
        if state.get('retrieval_config')!=expected:raise ValueError('retrieval checkpoint arm or encoder changed')
        # Keep the injected encoder, rebuild its index lazily with the same identity.
        self.build(state['rows'])


class CurrentTopMonitor:
    """U2 receives the CURRENT cumulative top-10 once, not repeated pooled copies.

    Requires a prospective integration amendment: original GapStopMonitor receives
    fresh batches and pools them itself. The orchestrator supplies an already
    selected top-k. q=1 consumes that whole set; clearing pool prevents duplicates.
    """
    def __init__(self, enabled=True):
        if not isinstance(enabled,bool):raise ValueError('monitor enabled must be boolean')
        self.enabled=enabled
        self.inner = GapStopMonitor(q=1.0)
        self.update_gate_stop = False

    def update(self, round_idx, train_scores, stop_scores):
        if not self.enabled:
            # This arm ablates Goodhart decisions, not the independent learning gate.
            return dict(gap=None,trend=None,should_stop=self.update_gate_stop,
                        restore_round=None,goodhart_enabled=False)
        self.inner.pool_t.clear(); self.inner.pool_s.clear()
        self.inner.k0 = len(train_scores)
        out = self.inner.update(round_idx,train_scores,stop_scores)
        out['should_stop'] = out['should_stop'] or self.update_gate_stop
        out['goodhart_enabled']=True
        return out

    def state_dict(self):
        return dict(inner=asdict(self.inner),update_gate_stop=self.update_gate_stop,enabled=self.enabled)

    def load_state_dict(self,state):
        if state.get('enabled',True)!=self.enabled:raise ValueError('Goodhart-monitor ablation changed on resume')
        self.inner=GapStopMonitor(**state['inner']); self.update_gate_stop=state['update_gate_stop']


class RealPreferenceUpdater(GradedPreferenceUpdater):
    """Observe the learning gate once per *search* round, including no-pair rounds.

    KLWeightGate defaults remain 0.01 KL, 0.005 relative weight change,
    check_from=3 (zero-based fourth search round), recheck_after=2. This fixes
    the observation schedule; it does not change scientific success criteria.
    No-pair rounds are explicit stall events, not measured zero-KL observations.
    """
    def __init__(self, generator, monitor):
        super().__init__(group_size=16,max_pairs_per_group=2,policy=generator)
        self.monitor=monitor
        self.gate=KLWeightGate()

    def _state(self):
        state=self.policy.extra_state.get('updater')
        if state is None:
            state=dict(schema='search_round_gate_v1',next_round=0,raised_at=None,lr_multiplier=1.0)
        if state.get('schema')!='search_round_gate_v1':
            raise ValueError('legacy update-count gate checkpoint cannot resume as search-round gate')
        return dict(state)

    def step(self,pairs,lr,beta):
        state=self._state()
        return super().step(pairs,lr*state['lr_multiplier'],beta)

    def observe_round(self,round_idx,step_metrics=None,pair_diag=None):
        state=self._state()
        if round_idx!=state['next_round']:
            raise ValueError('learning gate requires consecutive actual search rounds')
        self.gate.raised_at=state['raised_at']
        out=dict(step_metrics or {})
        has_update=bool(step_metrics)
        if has_update:
            kl,delta=float(out['kl']),float(out['weight_delta_rel'])
            if not math.isfinite(kl) or not math.isfinite(delta) or kl < -1e-5 or delta < 0:
                raise ValueError('invalid learning-gate measurements')
            reason='measured_update'
        else:
            # Feed the existing gate a stall event; keep measured KL/delta absent.
            kl=delta=0.0
            reason='no_preference_pairs'
        action=self.gate.update(round_idx,max(0.0,kl),delta)
        if action=='raise_lr_rank_once':
            state['lr_multiplier']=2.0  # no rank change or mid-run adapter surgery
        if action=='stop' and self.monitor is not None:
            self.monitor.update_gate_stop=True
        state.update(next_round=round_idx+1,raised_at=self.gate.raised_at,
                     last_action=action,last_reason=reason)
        self.policy.extra_state['updater']=state
        out.update(update_gate=action,update_gate_reason=reason,learning_gate_round=round_idx,
                   optimizer_updated=has_update,lr_multiplier=state['lr_multiplier'])
        return out
