"""ChemFM Generator contract and masked-policy DPO. No model download at import.

One round shares one retrieved seed prefix, so every preference group has identical
conditioning. Failed completions remain empty proposals; never silently resample.
Checkpoint bytes include optimizer state, not merely LoRA weights.
"""
import io
import hashlib
import json
import math
import time
from collections import Counter
from contextlib import contextmanager, nullcontext
from contextvars import ContextVar

import numpy as np
import torch


class ChemFMGenerator:
    def __init__(self, model_dir, seeds, *, seed=0, prefix_fraction=0.5,
                 batch_size=16, masked=True, max_tokens=500, device="cuda",
                 adaptation_dir=None, initialization_manifest=None,
                 initialization_manifest_sha256=None):
        from transformers import AutoModelForCausalLM, AutoTokenizer
        from peft import LoraConfig, get_peft_model
        from rules.vocab import load
        from hybrid.initialization import prepare_initialization, merge_adaptation
        if device == "cuda" and not torch.cuda.is_available():
            raise RuntimeError("CUDA required; refusing silent CPU fallback")
        if not seeds or not 0 < prefix_fraction < 1 or batch_size < 1 or max_tokens < 3:
            raise ValueError("seed molecules, prefix fraction and batch size required")
        self.initialization_identity = prepare_initialization(
            model_dir, adaptation_dir=adaptation_dir,
            manifest_path=initialization_manifest,
            manifest_sha256=initialization_manifest_sha256)
        torch.manual_seed(seed)
        self.tok = AutoTokenizer.from_pretrained(model_dir, local_files_only=True)
        self.vocab = load(str(model_dir) + "/tokenizer.json")
        base = AutoModelForCausalLM.from_pretrained(
            model_dir, local_files_only=True, use_safetensors=True,
            torch_dtype=torch.bfloat16 if device == "cuda" else torch.float32).to(device)
        if adaptation_dir is not None:
            base = merge_adaptation(base, adaptation_dir)
        self.model = get_peft_model(base, LoraConfig(r=8, lora_alpha=16,
            target_modules=["q_proj", "v_proj"], lora_dropout=0.0,
            bias="none", task_type="CAUSAL_LM"))
        self.model.eval()
        self.device, self.seeds = device, tuple(seeds)
        self.frac, self.batch, self.masked, self.max_tokens = prefix_fraction, batch_size, masked, max_tokens
        self.optimizer = torch.optim.AdamW([p for p in self.model.parameters() if p.requires_grad], lr=1e-4)
        self.records, self.last_stats, self.con = {}, {}, None
        self.temperature = 1.0
        self.steps = 0
        self.extra_state = {}
        self.deadline = float("inf")
        self.knowledge_selector=None; self.parent_map={}; self.knowledge_task={}; self.knowledge_arm="off"
        self.knowledge_config=None
        self.learned_knowledge=None

    def configure_knowledge(self,selector,parent_map,task_scope,arm,parent_map_sha256):
        self.knowledge_selector=selector;self.parent_map=dict(parent_map)
        self.knowledge_task=dict(task_scope);self.knowledge_arm=arm
        self.knowledge_config=dict(catalogue_sha256=selector.catalogue_sha256,
            parent_map_sha256=parent_map_sha256,task_scope=dict(task_scope),arm=arm)

    def configure_learned_knowledge(self, feature_schema, schema_digest, layer_indices, heads,
                                    *, category_width=8, type_width=4, hidden_width=None):
        """Explicit opt-in; configure before sampling or any optimizer update."""
        if getattr(self,'learned_knowledge',None) is not None:
            raise ValueError('learned knowledge is already configured')
        if self.steps or self.records:
            raise ValueError('configure learned knowledge before sampling or optimization')
        from hybrid.knowledge_bridge import LearnedKnowledgeBridge
        bridge=LearnedKnowledgeBridge(self.model.get_base_model(),feature_schema,schema_digest,
            layer_indices,heads,category_width=category_width,type_width=type_width,hidden_width=hidden_width)
        self.learned_knowledge=bridge
        self._knowledge_reference=ContextVar('generator_reference_'+str(id(self)),default=False)
        self.optimizer.add_param_group({'params':bridge.trainable_parameters()})
        self._record_knowledge={}

    def set_knowledge_provider(self, provider):
        """Install frozen per-parent inputs before checkpoint restore or sampling."""
        if getattr(self,'learned_knowledge',None) is None:raise ValueError('learned knowledge is not configured')
        if self.records or self.steps or self.learned_knowledge.memory is not None:
            raise ValueError('install knowledge provider before sampling or restore')
        from copy import deepcopy
        self.knowledge_provider=provider
        self.learned_input_config=deepcopy(provider.config)
        self.parent_map=dict(provider.parent_map)
        self.knowledge_task=dict(provider.task_scope)

    def set_round_knowledge(self, memory):
        bridge=getattr(self,'learned_knowledge',None)
        if bridge is None:raise ValueError('learned knowledge is not configured')
        bridge.set_memory(memory)
        self.records={};self._record_knowledge={}

    def _knowledge_condition(self, batch_size):
        bridge=getattr(self,'learned_knowledge',None)
        if bridge is None:return nullcontext()
        return bridge.condition(batch_size,reference=self._knowledge_reference.get())

    @contextmanager
    def _reference_policy(self):
        marker=getattr(self,'_knowledge_reference',None)
        token=marker.set(True) if marker is not None else None
        try:
            with torch.no_grad(),self.model.disable_adapter():yield
        finally:
            if marker is not None:marker.reset(token)

    def _trainable_parameters(self):
        params=[p for p in self.model.parameters() if p.requires_grad]
        bridge=getattr(self,'learned_knowledge',None)
        return params+(bridge.trainable_parameters() if bridge is not None else [])

    def sample(self, n, ctx, temperature, seed, constraint=None):
        if n < 1 or temperature <= 0:
            raise ValueError("positive sample count/temperature required")
        from hybrid.sampling import sample_group
        rng = np.random.default_rng(seed)
        # Retrieval supplies chemical parents, not natural-language tokens ChemFM cannot read.
        parents = [s for s, _ in ctx.retrieved] or list(ctx.seed_smiles) or list(self.seeds)
        from hybrid.knowledge_parent import choose_parent
        parent,knowledge_trace=choose_parent(parents,self.knowledge_selector,self.parent_map,
            self.knowledge_task,np.random.default_rng(seed),self.knowledge_arm,seed)
        bridge=getattr(self,'learned_knowledge',None)
        if bridge is not None:
            provider=getattr(self,'knowledge_provider',None)
            if provider is not None:
                if provider.config!=self.learned_input_config:raise ValueError('learned provider configuration changed')
                self.set_round_knowledge(provider(parent))
            from hybrid.knowledge_parent import Parent, REQUIRED_SCOPE, scope_pairs
            bridge.digest  # Requires a validated memory before inspecting its audit.
            audit=json.loads(bridge.memory.audit_json)
            mapped=self.parent_map.get(parent)
            if (not isinstance(mapped,Parent) or mapped.smiles!=parent
                    or mapped.id not in audit.get('parent_ids',[])):
                raise ValueError('sampled parent is not approved by round knowledge memory')
            task=dict(scope_pairs(audit.get('task_scope',{})))
            scope=dict(scope_pairs(dict(mapped.scope)))
            if (not REQUIRED_SCOPE<=task.keys() or not REQUIRED_SCOPE<=scope.keys()
                    or any(scope.get(k)!=v for k,v in task.items())
                    or any(k in task and task[k]!=v for k,v in scope.items())):
                raise ValueError('sampled parent scope conflicts with round knowledge memory')
            configured=dict(getattr(self,'knowledge_task',{}))
            if configured and any(task.get(k)!=v for k,v in configured.items()):
                raise ValueError('configured task conflicts with round knowledge memory')
            if not mapped.source_families:
                raise ValueError('sampled parent source lineage is missing')
        ids = self.tok(parent, add_special_tokens=True)["input_ids"]
        body = ids[1:-1] if ids[-1] == self.tok.eos_token_id else ids[1:]
        size = max(2, min(len(body) - 1, int(round(self.frac * len(body)))))
        size = max(2, size // 8 * 8) if size >= 8 else size
        prompt = [ids[0]] + body[:size]
        if knowledge_trace is not None:
            knowledge_trace['prefix_sha256']=hashlib.sha256(json.dumps(prompt).encode()).hexdigest()
            self.extra_state.setdefault('knowledge_history',[]).append(knowledge_trace)
        self.con = constraint
        self.temperature = float(temperature)
        if constraint is None:
            raise ValueError("post-hoc chemical constraint is required even for no-rules arm")
        self.records = {}
        bridge=getattr(self,'learned_knowledge',None)
        if bridge is not None:
            bridge.digest  # Fail before generating if no round memory was supplied.
            self._record_knowledge={}
        stats = {"mask_seconds": 0.0, "row_steps": 0}
        outcomes = Counter(); samples = [""] * n
        self.model.eval(); torch.manual_seed(seed)
        for start in range(0, n, self.batch):
            if time.monotonic() >= self.deadline:
                outcomes["wallclock"] += n - start
                break
            items = [(i, prompt) for i in range(start, min(start + self.batch, n))]
            with torch.no_grad(),self._knowledge_condition(len(items)):
                rows = sample_group(self.model, self.device, constraint, items, temperature, self.masked, rng, stats, self.max_tokens)
            for i, (completion, finished, _, prefix, reason) in rows.items():
                outcomes[reason] += 1
                if not finished:
                    continue
                text = self.vocab.decode(prefix + completion)
                samples[i] = text
                self.records[text] = (list(prefix), list(completion) + [constraint.eos])
                if bridge is not None:self._record_knowledge[text]=bridge.digest
        self.last_stats = dict(stats, outcomes=dict(outcomes), requested=n,
                               completed=sum(bool(s) for s in samples), prompt_tokens=len(prompt))
        if bridge is not None:
            self.last_stats['knowledge_memory_digest']=bridge.digest
            self.last_stats['knowledge_parent_id']=self.parent_map[parent].id
            self.extra_state['learned_round_identity']=dict(parent_id=self.parent_map[parent].id,
                parent_sha256=hashlib.sha256(parent.encode()).hexdigest(),seed=seed,memory_digest=bridge.digest)
        self.extra_state.setdefault('sampling_history',[]).append(dict(self.last_stats,seed=seed))
        return samples

    def _token_logps(self, smiles, grad=False):
        """Full next-token distributions at the recorded completion's contexts."""
        if smiles not in self.records:
            raise ValueError("DPO candidate absent from current shared-prompt sampling batch")
        bridge=getattr(self,'learned_knowledge',None)
        if bridge is not None and getattr(self,'_record_knowledge',{}).get(smiles)!=bridge.digest:
            raise ValueError('candidate knowledge conditioning differs from sampled group')
        prefix, completion = self.records[smiles]
        x = torch.tensor([prefix + completion], device=self.device)
        with torch.set_grad_enabled(grad),self._knowledge_condition(1):
            logits = self.model(input_ids=x, use_cache=False).logits[0].float()
            state = self.con.init_state(prefix) if self.masked else None
            rows=[]
            for j, token in enumerate(completion):
                lg = logits[len(prefix) - 1 + j] / self.temperature
                if self.masked:
                    feasible = torch.as_tensor(self.con.mask(state), device=self.device)
                    if not bool(feasible[token]):
                        raise ValueError("sample completion is forbidden by its training mask")
                    lg = lg + torch.as_tensor(self.con.soft_logits(state), device=self.device, dtype=lg.dtype)
                    lg = lg.masked_fill(~feasible, -torch.inf)
                rows.append(torch.log_softmax(lg,-1))
                if self.masked and token != self.con.eos:
                    self.con.advance(state,token)
            return rows

    def _logp(self,smiles,grad=False):
        rows=self._token_logps(smiles,grad)
        return torch.stack([lp[token] for lp,token in zip(rows,self.records[smiles][1])]).sum()

    def logprobs(self, smiles_list, ctx):
        self.model.eval()
        return [float(self._logp(s)) for s in smiles_list]

    def kl_to_reference(self, smiles_list, ctx):
        """Exact categorical KL per visited token context, averaged over contexts.

        Contexts are sampled/generated and pair-selected; this is not the full
        sequence-distribution KL or an unbiased policy-rollout expectation.
        """
        self.model.eval(); values=[]
        for s in smiles_list:
            policy=self._token_logps(s)
            with self._reference_policy():
                reference=self._token_logps(s)
            for lp,lr in zip(policy,reference):
                support=torch.isfinite(lp)
                value=float((lp[support].exp()*(lp[support]-lr[support])).sum())
                if not math.isfinite(value) or value < -1e-5:
                    raise FloatingPointError('invalid categorical token KL')
                values.append(max(0.0,value))
        return float(np.mean(values)) if values else 0.0

    def weight_delta(self):
        num = den = 0.0
        for mod in self.model.modules():
            if hasattr(mod, "lora_A") and "default" in mod.lora_A:
                delta = mod.lora_B["default"].weight.float() @ mod.lora_A["default"].weight.float()
                num += float((delta * mod.scaling["default"]).square().sum())
                den += float(mod.base_layer.weight.float().square().sum())
        return math.sqrt(num / den) if den else 0.0

    def dpo_step(self, pairs, lr, beta):
        if not pairs or lr <= 0 or beta <= 0:
            raise ValueError("nonempty pairs and positive optimization parameters required")
        for group in self.optimizer.param_groups:
            group["lr"] = lr
        self.model.eval()  # no dropout; gradients remain enabled below
        self.optimizer.zero_grad(set_to_none=True)
        losses = []
        for pair in pairs:
            with self._reference_policy():
                ref_delta = self._logp(pair.chosen) - self._logp(pair.rejected)
            delta = self._logp(pair.chosen, True) - self._logp(pair.rejected, True)
            loss = torch.nn.functional.softplus(-beta * (delta - ref_delta)) / len(pairs)
            if not bool(torch.isfinite(loss)):
                raise FloatingPointError("nonfinite DPO loss")
            loss.backward(); losses.append(float(loss.detach()))
        parameters=self._trainable_parameters()
        grads = [p.grad for p in parameters if p.grad is not None]
        if not grads or not all(bool(torch.isfinite(g).all()) for g in grads):
            raise FloatingPointError("missing or nonfinite policy gradients")
        torch.nn.utils.clip_grad_norm_(parameters, 1.0)
        self.optimizer.step(); self.steps += 1
        if not all(bool(torch.isfinite(p).all()) for p in parameters):
            raise FloatingPointError("nonfinite updated policy weights")
        sampled = list(dict.fromkeys([s for p in pairs for s in (p.chosen,p.rejected)]))
        result=dict(loss=sum(losses), kl=self.kl_to_reference(sampled,None),
                    weight_delta_rel=self.weight_delta(), optimizer_steps=self.steps)
        bridge=getattr(self,'learned_knowledge',None)
        if bridge is not None:result['bridge_delta_l2']=bridge.delta_l2()
        return result

    def lora_state(self):
        from peft import get_peft_model_state_dict
        stream = io.BytesIO()
        torch.save({"adapter":get_peft_model_state_dict(self.model),
                    "optimizer":self.optimizer.state_dict(), "steps":self.steps, "extra_state":self.extra_state,
                    "rng_cpu":torch.get_rng_state(),
                    "rng_cuda":torch.cuda.get_rng_state_all() if torch.cuda.is_available() else [],
                    "knowledge_config":self.knowledge_config,
                    "learned_input_config":getattr(self,'learned_input_config',None),
                    "learned_knowledge":(self.learned_knowledge.checkpoint() if getattr(self,'learned_knowledge',None) is not None else None),
                    "initialization_identity":self.initialization_identity,
                    "sampling_config":dict(prefix_fraction=self.frac,batch_size=self.batch,masked=self.masked,max_tokens=self.max_tokens)},stream)
        return stream.getvalue()

    def load_lora(self, path):
        from peft import set_peft_model_state_dict
        state = torch.load(path, map_location=self.device, weights_only=True)
        from hybrid.initialization import assert_initialization_matches
        assert_initialization_matches(state.get('initialization_identity'), self.initialization_identity)
        expected=dict(prefix_fraction=self.frac,batch_size=self.batch,masked=self.masked,max_tokens=self.max_tokens)
        if state.get('knowledge_config')!=self.knowledge_config:raise ValueError('checkpoint knowledge configuration differs')
        if state.get('sampling_config')!=expected: raise ValueError('checkpoint sampling configuration differs')
        bridge=getattr(self,'learned_knowledge',None)
        saved_bridge=state.get('learned_knowledge')
        if (bridge is None)!=(saved_bridge is None):raise ValueError('checkpoint learned knowledge enablement differs')
        if state.get('learned_input_config')!=getattr(self,'learned_input_config',None):
            raise ValueError('checkpoint learned input configuration differs')
        if bridge is not None:
            memory=bridge.validate_checkpoint(saved_bridge)
            provider=getattr(self,'knowledge_provider',None)
            if provider is not None and memory is not None:provider.validate_memory(memory)
            round_identity=state.get('extra_state',{}).get('learned_round_identity')
            if provider is not None and memory is not None:
                audit=json.loads(memory.audit_json)
                if (not isinstance(round_identity,dict) or round_identity.get('memory_digest')!=memory.digest
                        or audit.get('parent_ids')!=[round_identity.get('parent_id')]):
                    raise ValueError('checkpoint learned round identity differs')
                parent=next((p for p in provider.parent_map.values() if p.id==round_identity['parent_id']),None)
                if (parent is None or type(round_identity.get('seed')) is not int
                        or round_identity.get('parent_sha256')!=hashlib.sha256(parent.smiles.encode()).hexdigest()):
                    raise ValueError('checkpoint learned parent/seed identity differs')
        set_peft_model_state_dict(self.model,state["adapter"])
        if bridge is not None:
            bridge.restore(saved_bridge)
            self.records={};self._record_knowledge={}
        torch.set_rng_state(state['rng_cpu'].cpu())
        if state.get('rng_cuda'):
            if not torch.cuda.is_available():raise RuntimeError('CUDA RNG checkpoint requires CUDA')
            torch.cuda.set_rng_state_all([r.cpu() for r in state['rng_cuda']])
        self.optimizer.load_state_dict(state["optimizer"]); self.steps=state["steps"]; self.extra_state=state.get("extra_state",{})
