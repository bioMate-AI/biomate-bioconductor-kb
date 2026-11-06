#!/usr/bin/env python3
"""UNIFIED STAGE-2 GRPO for the on-prem 9B — verifiable-reward RL on top of the collected-gold SFT
checkpoint (sft_gold_adapter), over the WHOLE 12,275-row corpus (decision + routing + param +
autofix). A faithful port of train_grpo_decomp.py (the proven scaffold): model load / QLoRA /
PeftModel-start-policy / GRPOConfig / GRPOTrainer are IDENTICAL. Only three things differ:
  1. build_prompts reads the unified corpus shape ({prompt, gold, scorer, labels}), not decomp messages.
  2. reward = decision_reward.decision_reward (already TRL-shaped: reads gold/scorer/labels columns,
     dispatches the right scorer per row) — no db, no node/edge/struct weights.
  3. eval hook (optional, EVAL_HOOK-gated) is generic: generate on a held-out slice, score each row
     with decision_reward.score_one, log the mean. Default OFF — the honest gauge is the post-hoc
     re-eval of the saved adapter on decomposition_real / decision_eval / RealBio bare-vs-harness vs
     the sft_gold start policy (the WIN GATE in scripts/stage_onprem_rl_run.sh).

Reward+data PROVEN offline: `python3 decision_reward.py --selftest` ranks oracle>anti-oracle on all
12,275 rows. GRPO only needs the reward's RELATIVE ordering within a prompt's rollout group.

Run (GPU box; via spot_grpo_unified_entry.sh):
    python3 train_grpo_unified.py --base $BASE --adapter $SFT_GOLD --data unified_grpo_corpus.jsonl \
        --out $OUT/grpo --max-steps 400 --save-steps 25 --num-generations 8
"""
from __future__ import annotations
import argparse, json, os, sys


def build_prompts(data_path, limit=None):
    """unified_grpo_corpus.jsonl rows -> {'prompt': <chat list>, 'gold': str, 'scorer': str, 'labels': ...}.
    The corpus `prompt` is a single self-contained instruction string; wrap it as one user message so
    the tokenizer's chat template applies, exactly as the model saw at SFT. gold/scorer/labels are
    forwarded verbatim — TRL passes every non-standard dataset column to the reward fn as a kwarg,
    and decision_reward reads gold/scorer/labels."""
    rows = []
    for ln in open(data_path):
        if not ln.strip():
            continue
        r = json.loads(ln)
        p = r.get("prompt")
        if not p or "gold" not in r or "scorer" not in r:
            continue
        prompt = p if isinstance(p, list) else [{"role": "user", "content": str(p)}]
        gold = r["gold"]
        rows.append({"prompt": prompt,
                     "gold": gold if isinstance(gold, str) else json.dumps(gold),
                     "scorer": r["scorer"],
                     "labels": r.get("labels")})
        if limit and len(rows) >= limit:
            break
    return rows


def make_eval_callback(bench_path, tok, every, n_slice=40):
    """Optional generic held-out eval hook (EVAL_HOOK=1): generate on a held-out slice and log the
    mean verifiable reward via decision_reward.score_one. Robust: never crashes training."""
    import torch
    from transformers import TrainerCallback
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import decision_reward as DR

    def _rows():
        out = []
        try:
            for l in open(bench_path):
                if not l.strip():
                    continue
                r = json.loads(l)
                # accept {prompt|messages, gold, scorer, labels}; decision_eval uses task_id+messages
                p = r.get("prompt")
                if p is None and r.get("messages"):
                    p = r["messages"][1]["content"] if len(r["messages"]) > 1 else r["messages"][0]["content"]
                if p is None or "gold" not in r or "scorer" not in r:
                    continue
                out.append((p, r["gold"], r["scorer"], r.get("labels")))
                if len(out) >= n_slice:
                    break
        except Exception as e:
            print(f"[eval_hook] bench load failed ({e}) — hook disabled")
        return out
    bench = _rows()

    class EvalHook(TrainerCallback):
        def on_save(self, args, state, control, model=None, **kw):
            if os.environ.get("EVAL_HOOK", "0") != "1" or model is None or not bench:
                return
            try:
                model.eval()
                scores = []
                for p, gold, scorer, labels in bench:
                    enc = tok.apply_chat_template([{"role": "user", "content": str(p)}],
                                                  add_generation_prompt=True, return_tensors="pt",
                                                  return_dict=True)
                    enc = {k: v.to(model.device) for k, v in enc.items()}
                    ilen = enc["input_ids"].shape[1]
                    with torch.no_grad():
                        g = model.generate(**enc, max_new_tokens=512, do_sample=False,
                                           pad_token_id=tok.pad_token_id or tok.eos_token_id)
                    txt = tok.decode(g[0][ilen:], skip_special_tokens=True)
                    gd = json.loads(gold) if isinstance(gold, str) and gold.strip()[:1] in "{[" else gold
                    scores.append(DR.score_one(txt, gd, scorer, labels))
                mean = sum(scores) / len(scores) if scores else 0.0
                print(f"[eval_hook step={state.global_step}] held_out_mean_reward={mean:.4f} n={len(scores)}")
                model.train()
            except Exception as e:
                print(f"[eval_hook] skipped ({e})")

    return EvalHook()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True, help="clean base model dir (Qwen3.5-9B @ pinned rev)")
    ap.add_argument("--adapter", required=True, help="sft_gold adapter = the start policy + KL ref")
    ap.add_argument("--data", required=True, help="unified_grpo_corpus.jsonl (prompt/gold/scorer/labels)")
    ap.add_argument("--out", required=True)
    # Honest gauge is the post-hoc re-eval; the in-loop hook is optional (default off).
    ap.add_argument("--bench", default=os.path.join(os.path.dirname(os.path.abspath(__file__)),
                    "..", "..", "docs", "20260912_onprem_llm", "data_pool_v2", "decision_eval.jsonl"))
    ap.add_argument("--max-steps", type=int, default=400)
    ap.add_argument("--save-steps", type=int, default=25)
    ap.add_argument("--eval-steps", type=int, default=25)
    ap.add_argument("--num-generations", type=int, default=8, help="GRPO group size")
    ap.add_argument("--lr", type=float, default=1e-6)
    ap.add_argument("--beta", type=float, default=0.04, help="KL coefficient (anchor to SFT policy)")
    ap.add_argument("--temperature", type=float, default=0.9, help="rollout sampling temperature")
    ap.add_argument("--max-completion-len", type=int, default=640)
    ap.add_argument("--batch-size", type=int, default=2)
    ap.add_argument("--grad-accum", type=int, default=8)
    ap.add_argument("--resume", default=None)
    ap.add_argument("--dry-run", action="store_true",
                    help="build the prompt dataset + verify the reward ranks oracle>anti; train nothing")
    a = ap.parse_args()

    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import decision_reward as DR

    prompts = build_prompts(a.data)
    if not prompts:
        print("FATAL: no GRPO prompts built from", a.data); return 2
    reward_fn = DR.decision_reward  # already TRL-shaped; reads gold/scorer/labels dataset columns

    if a.dry_run:
        # CPU-only: prove the dataset + reward wiring without a model. For a few rows, build the
        # oracle completion from gold and a trivially-wrong one; the reward must rank oracle higher.
        from collections import Counter
        print(f"[dry-run] GRPO prompts built: {len(prompts)} (from {a.data})")
        print(f"[dry-run] scorer mix: {dict(Counter(r['scorer'] for r in prompts))}")
        try:
            from decision_reward import _oracle, _anti  # oracle/anti-oracle builders
        except Exception:
            _oracle = _anti = None
        # _oracle/_anti are defined for the AGENT-TASK scorers; decision-family scorers
        # (decision/categorical/set/numeric/mtd/chain) are validated separately by
        # `decision_reward.py --selftest` against their real gold completions. Check the agent-task
        # bulk here (that is 12,228 of the 12,275 rows — the whole point of the trainer wiring).
        AGENT = {"routing", "cross_domain_routing", "param_select", "param_prefill", "autofix"}
        ok = 0; checked = 0
        for r in (x for x in prompts if x["scorer"] in AGENT):
            if _oracle is None or checked >= 200:
                break
            orc = _oracle(r["gold"], r["scorer"]); anti = _anti(r["gold"], r["scorer"])
            ro = reward_fn([orc], gold=[r["gold"]], scorer=[r["scorer"]], labels=[r.get("labels")])[0]
            ra = reward_fn([anti], gold=[r["gold"]], scorer=[r["scorer"]], labels=[r.get("labels")])[0]
            checked += 1; ok += (ro > ra)
        print(f"[dry-run] reward ranks oracle>anti on {ok}/{checked} sampled agent-task rows "
              f"(decision-family validated by decision_reward.py --selftest)")
        assert checked == 0 or ok == checked, "reward must rank oracle above anti-oracle"
        print("DRY_RUN_OK")
        return 0

    # ---- real training path (GPU box only) — IDENTICAL scaffold to train_grpo_decomp.py ----
    import torch
    from datasets import Dataset
    from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig
    from peft import PeftModel, prepare_model_for_kbit_training
    from trl import GRPOTrainer, GRPOConfig

    tok = AutoTokenizer.from_pretrained(a.base, trust_remote_code=True)
    if tok.pad_token is None:
        tok.pad_token = tok.eos_token
    bnb = BitsAndBytesConfig(load_in_4bit=True, bnb_4bit_quant_type="nf4",
                             bnb_4bit_use_double_quant=True,
                             bnb_4bit_compute_dtype=torch.bfloat16)
    model = AutoModelForCausalLM.from_pretrained(a.base, quantization_config=bnb,
                                                 device_map="auto", torch_dtype=torch.bfloat16,
                                                 trust_remote_code=True)
    model = prepare_model_for_kbit_training(model, use_gradient_checkpointing=True)
    # load sft_gold as the trainable, resumable start policy; GRPO's frozen KL ref is this adapter's
    # initial state (no peft_config passed → trl 1.14.1 adds a frozen ref copy of THIS adapter).
    model = PeftModel.from_pretrained(model, a.adapter, is_trainable=True)

    ds = Dataset.from_list(prompts)

    cfg = GRPOConfig(
        output_dir=a.out, num_generations=a.num_generations, beta=a.beta,
        temperature=a.temperature, learning_rate=a.lr, lr_scheduler_type="cosine",
        warmup_steps=10, max_steps=a.max_steps, save_steps=a.save_steps,
        per_device_train_batch_size=a.batch_size, gradient_accumulation_steps=a.grad_accum,
        max_completion_length=a.max_completion_len,
        bf16=True, gradient_checkpointing=True,
        gradient_checkpointing_kwargs={"use_reentrant": False},
        optim="paged_adamw_8bit", report_to=[], seed=13, log_completions=True)

    callbacks = []
    if os.environ.get("EVAL_HOOK", "0") == "1":
        callbacks.append(make_eval_callback(a.bench, tok, a.eval_steps))

    trainer = GRPOTrainer(model=model, args=cfg, train_dataset=ds,
                          reward_funcs=[reward_fn], processing_class=tok,
                          callbacks=callbacks)
    trainer.train(resume_from_checkpoint=a.resume)
    trainer.save_model(a.out)
    print("GRPO_DONE ->", a.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
