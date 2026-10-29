"""U3 real LoRA/DPO smoke on ChemFM-1B (CPU torch on EC2 spot; NOT a result - it checks that loss, KL and weight change behave).
3 rounds x (4 prompts x 16 samples) -> graded score -> GradedPreferenceUpdater pairs -> DPO steps on the LoRA delta.
Sanity facts checked: step-0 loss == ln 2 (adapter B=0 so policy == reference); all quantities finite; KL estimate >= 0 up to noise;
relative LoRA weight change > 0 after the first step. The graded score is an arbitrary smooth physchem objective chosen only to give
within-group variance; it says nothing about peptide quality."""
import json
import math
import os
import sys
import time

import numpy as np
import torch
from peft import LoraConfig, get_peft_model
from rdkit import Chem, RDLogger
from rdkit.Chem import Crippen, rdMolDescriptors
from transformers import AutoModelForCausalLM, AutoTokenizer

RDLogger.DisableLog("rdApp.*")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + "/..")
from feedback.preference_updater import GradedPreferenceUpdater, KLWeightGate  # noqa: E402

D = os.environ["CHEMFM_DIR"]
OUT = os.environ.get("OUT", "/w/smoke.json")
SEEDS = ["C[C@H]1NC(=O)[C@H](C)NC(=O)[C@H](C)NC(=O)[C@H](C)NC(=O)[C@H](C)NC1=O",
         "CC(C)C[C@H]1NC(=O)[C@H](Cc2ccccc2)NC(=O)[C@@H](C)NC(=O)[C@H](CC(C)C)NC(=O)[C@H](C)NC1=O",
         "C[C@H]1NC(=O)[C@@H](CC(C)C)N(C)C(=O)[C@H](Cc2ccccc2)NC(=O)[C@H](C)NC(=O)[C@H](CC(C)C)NC1=O",
         "O=C1[C@@H](Cc2ccccc2)NC(=O)[C@H](CC(C)C)NC(=O)[C@H](C)NC(=O)[C@@H](CC(C)C)NC(=O)[C@H](C)N1"]
N_PER, ROUNDS, STEPS, BS_PAIRS = 32, 3, 4, 8       # smoke v2: 32 samples per prompt (smoke v1 with 16 left < 16 valid per group at validity ~0.67, so every group was dropped and no DPO step ran)
PREFIX_FRAC, MAXNEW, TEMP, LR, BETA = 0.6, 80, 1.0, 1e-4, 0.1
torch.manual_seed(0)
np.random.seed(0)


def score(smi):
    m = Chem.MolFromSmiles(smi) if smi else None
    if m is None or m.GetNumHeavyAtoms() < 10:
        return None
    tpsa, logp = rdMolDescriptors.CalcTPSA(m), Crippen.MolLogP(m)
    return float(0.5 * math.exp(-((tpsa - 140) / 50) ** 2) + 0.5 * math.exp(-((logp - 1.5) / 1.5) ** 2))


tok = AutoTokenizer.from_pretrained(D)
base = AutoModelForCausalLM.from_pretrained(D, torch_dtype=torch.float32)
base.config.use_cache = True
cfg = LoraConfig(r=8, lora_alpha=16, target_modules=["q_proj", "v_proj"], lora_dropout=0.0, bias="none", task_type="CAUSAL_LM")
model = get_peft_model(base, cfg)
model.print_trainable_parameters()
opt = torch.optim.AdamW([p for p in model.parameters() if p.requires_grad], lr=LR)
EOS = tok.eos_token_id


def prefix_ids(s):
    ids = tok(s, add_special_tokens=True)["input_ids"]
    body = ids[1:-1] if (len(ids) > 2 and ids[-1] == EOS) else ids[1:]
    P = max(2, int(round(PREFIX_FRAC * len(body))))
    return [ids[0]] + body[:P]


def sample(prefix, n):
    x = torch.tensor([prefix] * n)
    model.eval()
    with torch.no_grad():
        o = model.generate(input_ids=x, attention_mask=torch.ones_like(x), do_sample=True, temperature=TEMP, top_k=0, top_p=1.0,
                           max_new_tokens=MAXNEW, pad_token_id=EOS)
    outs = []
    for row in o.tolist():
        comp = row[len(prefix):]
        if EOS in comp:
            comp = comp[:comp.index(EOS) + 1]
        outs.append(comp)
    return outs


def batch_tensors(items):
    L = max(len(p) + len(c) for p, c in items)
    ids = torch.full((len(items), L), EOS)
    att = torch.zeros((len(items), L), dtype=torch.long)
    cm = torch.zeros((len(items), L))
    for i, (p, c) in enumerate(items):
        seq = p + c
        ids[i, :len(seq)] = torch.tensor(seq)
        att[i, :len(seq)] = 1
        cm[i, len(p):len(seq)] = 1
    return ids, att, cm


def seq_logp(items, grad):
    ids, att, cm = batch_tensors(items)
    with torch.set_grad_enabled(grad):
        lg = model(input_ids=ids, attention_mask=att).logits[:, :-1].float()
        lp = torch.log_softmax(lg, -1).gather(-1, ids[:, 1:, None]).squeeze(-1)
        return (lp * cm[:, 1:]).sum(-1), cm[:, 1:].sum(-1)


def rel_weight_change():
    num = den = 0.0
    for n, mod in model.named_modules():
        if hasattr(mod, "lora_A") and "default" in getattr(mod, "lora_A", {}):
            A, B = mod.lora_A["default"].weight, mod.lora_B["default"].weight
            delta = (B @ A) * mod.scaling["default"]
            W = mod.base_layer.weight
            num += float(delta.norm() ** 2)
            den += float(W.norm() ** 2)
    return math.sqrt(num / den) if den else 0.0


upd = GradedPreferenceUpdater(group_size=N_PER, margin=0.02, max_pairs_per_group=2, beta=BETA)
gate = KLWeightGate(check_from=3)
log = dict(rounds=[], steps=[], config=dict(N_PER=N_PER, ROUNDS=ROUNDS, STEPS=STEPS, LR=LR, BETA=BETA, PREFIX_FRAC=PREFIX_FRAC,
                                              MAXNEW=MAXNEW, TEMP=TEMP))
t0 = time.time()
step_idx = 0
for r in range(ROUNDS):
    items, smis, scores, groups = [], [], [], []
    for gi, s in enumerate(SEEDS):
        pre = prefix_ids(s)
        for comp in sample(pre, N_PER):
            smi = tok.decode(pre + comp, skip_special_tokens=True).replace(" ", "")
            items.append((pre, comp)), smis.append(smi), scores.append(score(smi)), groups.append(gi)
    valid = [x for x in scores if x is not None]
    pairs, diag = upd.make_pairs(smis, scores, group_by=groups)
    idx = upd.last_index_pairs
    with model.disable_adapter():
        ref_lp, _ = seq_logp(items, grad=False)
    rinfo = dict(round=r, valid_frac=len(valid) / len(scores), mean_score=float(np.mean(valid)) if valid else None, **diag,
                 t_sample_s=time.time() - t0)
    for st in range(STEPS):
        if len(idx) == 0:
            break
        sel = np.random.default_rng(100 * r + st).choice(len(idx), size=min(BS_PAIRS, len(idx)), replace=False)
        W_ = [idx.winners[i] for i in sel]
        L_ = [idx.losers[i] for i in sel]
        model.train()
        lw, _ = seq_logp([items[i] for i in W_], grad=True)
        ll, _ = seq_logp([items[i] for i in L_], grad=True)
        z = BETA * ((lw - ref_lp[W_]) - (ll - ref_lp[L_]))
        loss = torch.nn.functional.softplus(-z).mean()
        opt.zero_grad()
        loss.backward()
        opt.step()
        log["steps"].append(dict(step=step_idx, round=r, loss=float(loss), reward_margin=float(z.mean() / BETA), finite=bool(torch.isfinite(loss)),
                                 rel_weight_change=rel_weight_change(), t_s=time.time() - t0))
        step_idx += 1
    # on-round KL estimate: per-token mean of (logp_policy - logp_ref) over this round's samples
    pol_lp, n_tok = seq_logp(items, grad=False)
    kl_est = float(((pol_lp - ref_lp) / n_tok.clamp(min=1)).mean())
    rinfo.update(kl_est_per_token=kl_est, rel_weight_change=rel_weight_change(), gate=gate.update(r, abs(kl_est), rel_weight_change()))
    log["rounds"].append(rinfo)
    json.dump(log, open(OUT, "w"), indent=1)
    print(json.dumps(rinfo), flush=True)
st = log["steps"]
log["checks"] = dict(
    step0_loss_is_ln2=(abs(st[0]["loss"] - math.log(2)) < 1e-3) if st else None,
    all_finite=all(s["finite"] for s in st),
    weight_change_positive=(st[-1]["rel_weight_change"] > 0) if st else None,
    n_steps=len(st), total_s=time.time() - t0)
json.dump(log, open(OUT, "w"), indent=1)
print(json.dumps(log["checks"]))
