"""LoRA fine-tuning of ChemFM-1B UNDER THE MASK (GPU spot): the loss is the cross-entropy of the masked softmax, i.e. -log( p(y) / sum_{v in feasible} p(v) ), so the learned distribution is the
model conditioned on the rules. Also logs the plain (unmasked) cross-entropy and the mean log feasible mass log Z. Smoke run: 200 steps, batch 8; checks loss decreases and stays finite.
usage: lora_mask_smoke.py OUT --prep DIR [--steps 200] [--bs 8] [--lr 2e-4] [--r 16]   Env: CHEMFM_DIR."""
import os, sys, json, time, argparse, math, contextlib
import numpy as np
import torch, torch.nn.functional as F
from transformers import AutoModelForCausalLM
from peft import LoraConfig, get_peft_model

V = 320
CUDA = torch.cuda.is_available()
AC = (lambda: torch.autocast("cuda", dtype=torch.bfloat16)) if CUDA else contextlib.nullcontext      # fp32 on CPU


def load(prep, name):
    d = np.load(os.path.join(prep, f"{name}.npz")); return d["ids"].astype(np.int64), d["lens"], d["masks"]


def batch(ids, lens, masks, idx, dev):
    L = int(lens[idx].max()); x = torch.tensor(ids[idx, :L - 1], device=dev); y = torch.tensor(ids[idx, 1:L], device=dev)
    m = np.unpackbits(masks[idx, :L - 1], axis=2)[:, :, :V].astype(bool); m = torch.tensor(m, device=dev)
    valid = torch.zeros_like(y, dtype=torch.bool)
    for k, i in enumerate(idx): valid[k, :lens[i] - 1] = True
    return x, y, m, valid


def losses(model, x, y, m, valid):
    out = model(input_ids=x).logits.float()                     # (B,T,V)
    lp_plain = F.log_softmax(out, -1)
    lg = out.masked_fill(~m, -1e4); lp_mask = F.log_softmax(lg, -1)
    tgt = y.unsqueeze(-1)
    nll_plain = -lp_plain.gather(-1, tgt).squeeze(-1); nll_mask = -lp_mask.gather(-1, tgt).squeeze(-1)
    logZ = (lp_plain.masked_fill(~m, -1e4)).logsumexp(-1)       # log unmasked mass of the feasible set
    f = valid.float(); n = f.sum()
    return (nll_mask * f).sum() / n, (nll_plain * f).sum() / n, (logZ * f).sum() / n


@torch.no_grad()
def evaluate(model, data, dev, bs=8):
    ids, lens, masks = data; tot = np.zeros(3); n = 0
    for k in range(0, len(lens), bs):
        idx = np.arange(k, min(k + bs, len(lens))); x, y, m, valid = batch(ids, lens, masks, idx, dev)
        with AC(): a, b, c = losses(model, x, y, m, valid)
        w = float(valid.sum()); tot += np.array([float(a), float(b), float(c)]) * w; n += w
    return dict(masked_nll=round(tot[0] / n, 5), plain_nll=round(tot[1] / n, 5), mean_log_feasible_mass=round(tot[2] / n, 5))


def main(a):
    dev = "cuda" if CUDA else "cpu"; torch.manual_seed(0); np.random.seed(0)
    base = AutoModelForCausalLM.from_pretrained(os.environ["CHEMFM_DIR"], torch_dtype=torch.bfloat16 if CUDA else torch.float32).to(dev)
    cfg = LoraConfig(r=a.r, lora_alpha=2 * a.r, lora_dropout=0.05, target_modules=["q_proj", "k_proj", "v_proj", "o_proj"], task_type="CAUSAL_LM")
    model = get_peft_model(base, cfg)
    for p in model.parameters():
        if p.requires_grad: p.data = p.data.float()
    model.print_trainable_parameters()
    tr = load(a.prep, "train"); ev = load(a.prep, "eval"); opt = torch.optim.AdamW([p for p in model.parameters() if p.requires_grad], lr=a.lr, weight_decay=0.0)
    log = []; t0 = time.time(); res = {"args": vars(a)}
    model.eval(); res["eval_step0"] = evaluate(model, ev, dev); print("eval step 0", res["eval_step0"], flush=True)
    model.train(); rng = np.random.default_rng(0); order = rng.permutation(len(tr[1])); pos = 0; nan = False
    for step in range(1, a.steps + 1):
        if pos + a.bs > len(order): order = rng.permutation(len(order)); pos = 0
        idx = order[pos:pos + a.bs]; pos += a.bs; x, y, m, valid = batch(*tr, idx, dev)
        with AC(): lm, lp, lz = losses(model, x, y, m, valid)
        if not math.isfinite(float(lm)): nan = True; print("NON-FINITE LOSS at step", step, flush=True); break
        opt.zero_grad(set_to_none=True); lm.backward(); torch.nn.utils.clip_grad_norm_([p for p in model.parameters() if p.requires_grad], 1.0); opt.step()
        if step % 10 == 0 or step == 1:
            log.append(dict(step=step, masked_nll=float(lm), plain_nll=float(lp), log_feasible_mass=float(lz), sec=round(time.time() - t0, 1))); print(log[-1], flush=True)
    model.eval(); res["eval_final"] = evaluate(model, ev, dev); print("eval final", res["eval_final"], flush=True)
    res["train_log"] = log; res["nan"] = nan; res["seconds"] = round(time.time() - t0, 1)
    first = np.mean([l["masked_nll"] for l in log[:3]]); last = np.mean([l["masked_nll"] for l in log[-3:]]); res["masked_nll_first3_mean"] = round(float(first), 4); res["masked_nll_last3_mean"] = round(float(last), 4)
    res["loss_decreased"] = bool(last < first)
    os.makedirs(a.out, exist_ok=True); model.save_pretrained(os.path.join(a.out, "lora")); json.dump(res, open(os.path.join(a.out, "lora_mask_smoke.json"), "w"), indent=1)


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("out"); ap.add_argument("--prep", required=True); ap.add_argument("--steps", type=int, default=200)
    ap.add_argument("--bs", type=int, default=8); ap.add_argument("--lr", type=float, default=2e-4); ap.add_argument("--r", type=int, default=16); main(ap.parse_args())
