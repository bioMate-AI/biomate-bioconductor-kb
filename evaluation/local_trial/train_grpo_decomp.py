#!/usr/bin/env python3
"""STAGE-2 GRPO for on-prem 9B task-decomposition — verifiable-reward RL on top of the SFT-decomp
checkpoint. Authoring + dry-run only; NOT launched here (no GPU/serving in this session).

Design doc: docs/20260912_onprem_llm/20261006_DECOMP_STAGE2_GRPO_DESIGN.md

What it does
------------
  * Starts from the SFT-decomp QLoRA checkpoint (the retrain that folds decomp_depgraph.jsonl in).
    That policy IS the KL reference — GRPO's reference model is the frozen initial policy, so the KL
    term anchors to the SFT-decomp behaviour (prevents reward-hacking / KL-collapse away from the
    data-learned parallel/mixed density).
  * Group rollouts per prompt (num_generations), scored by the verifiable reward in decomp_reward.py
    (node-F1 + edge-F1 + catalog structural validity − malformed penalty). GRPO normalizes rewards
    WITHIN each group, so it only needs the reward's RELATIVE ordering of a prompt's rollouts — which
    the §dry-run proves is correct (oracle > all-chain on parallel/mixed).
  * QLoRA (4-bit nf4, paged_adamw_8bit), same pinned venv as SFT (trl==1.14.1 has GRPOTrainer).
  * save_steps checkpoints (resume-safe, mirrored to S3 by spot_train-style entry) + an optional
    held-out eval hook against decomposition_REAL (EVAL_HOOK=1): every eval_steps it generates on a
    small bench slice and logs node/edge-F1 + per-class structure via the benchmark scorer.
    NOTE (2026-10-19): the eval default is decomposition_REAL (out-of-generator: real nf-core/chain/
    GTN topologies), NOT decomposition_v2. decomposition_v2 is IN-DISTRIBUTION to build_decomp_depgraph.py
    (it emits both the GRPO TRAIN prompts and decomposition_v2), so a v2 "gain" is the same leaked
    artifact that got the SFT decomp 0.73 retracted. The only honest gauge is decomposition_real.
    Enabling EVAL_HOOK=1 requires the entry to stage datasets/decomposition_real/{decomposition_real.jsonl,score.py}.

GRPO prompts come from the TRAIN pool of decomp_depgraph.jsonl (the SFT training rows) — the SAME
hash split that holds the benchmark out. Each row
carries its gold DAG as the `gold` column; TRL forwards dataset columns to the reward fn as kwargs.

Run (on the GPU box; NOT run here):
    python3 train_grpo_decomp.py \
        --base   $BASE            (clean Qwen3.5-9B @ pinned rev) \
        --adapter $SFT_DECOMP_CKPT (the retrain's sft_decompv2 adapter — the start policy) \
        --data   decomp_depgraph.jsonl \
        --db     galaxy_ai_tools.db \
        --out    $OUT/grpo  --max-steps 400 --save-steps 25 --num-generations 8
"""
from __future__ import annotations
import argparse, json, os, sys


def build_prompts(data_path, train_split_only=True, limit=None):
    """decomp_depgraph.jsonl rows -> {'prompt': <chat str>, 'gold': <json str of gold DAG>}.

    gold = the assistant target (list of {sub_task,order,depends_on}); it is what node/edge-F1 score
    against. We keep only TRAIN-pool rows (source=='catalog_depgraph_synth' already are TRAIN-pool by
    construction in build_decomp_depgraph.py; the benchmark is a disjoint BENCH-pool set)."""
    rows = []
    for ln in open(data_path):
        if not ln.strip():
            continue
        r = json.loads(ln)
        msgs = r.get("messages", [])
        if len(msgs) < 3:
            continue
        # prompt = system + user (the exact SFT prompt); completion is sampled by GRPO
        sys_c = msgs[0]["content"]
        usr_c = msgs[1]["content"]
        try:
            gold = json.loads(msgs[2]["content"])
        except Exception:
            continue
        rows.append({"prompt": [{"role": "system", "content": sys_c},
                                {"role": "user", "content": usr_c}],
                     "gold": json.dumps(gold)})
        if limit and len(rows) >= limit:
            break
    return rows


def make_eval_callback(bench_path, scorer_path, db_path, tok, every, n_slice=30):
    """Optional held-out eval hook: generate on a decomposition_v2 slice and log graph-aware metrics.
    Guarded by EVAL_HOOK=1; generation is bounded (n_slice rows, greedy) so it doesn't dominate."""
    import importlib.util, torch
    from transformers import TrainerCallback
    spec = importlib.util.spec_from_file_location("decompv2_score", scorer_path)
    sc = importlib.util.module_from_spec(spec); spec.loader.exec_module(sc)
    import decomp_reward as R
    bench = [json.loads(l) for l in open(bench_path) if l.strip()][:n_slice]

    class EvalHook(TrainerCallback):
        def on_save(self, args, state, control, model=None, **kw):
            if os.environ.get("EVAL_HOOK", "0") != "1" or model is None:
                return
            model.eval()
            gold_by_id, pred_by_id = {}, {}
            for r in bench:
                prompt = f"{r['instr']}\n\nINPUT:\n{r['query']}"
                enc = tok.apply_chat_template([{"role": "user", "content": prompt}],
                                              add_generation_prompt=True, return_tensors="pt",
                                              return_dict=True)
                enc = {k: v.to(model.device) for k, v in enc.items()}
                ilen = enc["input_ids"].shape[1]
                with torch.no_grad():
                    g = model.generate(**enc, max_new_tokens=512, do_sample=False,
                                       pad_token_id=tok.pad_token_id or tok.eos_token_id)
                txt = tok.decode(g[0][ilen:], skip_special_tokens=True)
                gold_by_id[r["id"]] = r
                pred_by_id[r["id"]] = R._parse_plan(txt)
            out = sc.score_batch(gold_by_id, pred_by_id)
            print(f"[eval_hook step={state.global_step}] " + json.dumps(
                {k: out[k] for k in ("node_f1", "edge_f1", "structure_accuracy")}))
            model.train()

    return EvalHook()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True, help="clean base model dir (Qwen3.5-9B @ pinned rev)")
    ap.add_argument("--adapter", required=True, help="SFT-decomp adapter = the start policy + KL ref")
    ap.add_argument("--data", required=True, help="decomp_depgraph.jsonl (TRAIN-pool GRPO prompts)")
    ap.add_argument("--db", required=True, help="galaxy_ai_tools.db for the structural verifier")
    ap.add_argument("--out", required=True)
    # Honest default: eval on decomposition_REAL (out-of-generator). decomposition_v2 is
    # in-distribution to the GRPO train generator (build_decomp_depgraph.py) and must not gauge.
    ap.add_argument("--scorer", default=os.path.join(os.path.dirname(os.path.abspath(__file__)),
                    "..", "datasets", "decomposition_real", "score.py"))
    ap.add_argument("--bench", default=os.path.join(os.path.dirname(os.path.abspath(__file__)),
                    "..", "datasets", "decomposition_real", "decomposition_real.jsonl"))
    ap.add_argument("--max-steps", type=int, default=400)
    ap.add_argument("--save-steps", type=int, default=25)
    ap.add_argument("--eval-steps", type=int, default=25)
    ap.add_argument("--num-generations", type=int, default=8, help="GRPO group size")
    ap.add_argument("--lr", type=float, default=1e-6)
    ap.add_argument("--beta", type=float, default=0.04, help="KL coefficient (anchor to SFT policy)")
    ap.add_argument("--temperature", type=float, default=0.9, help="rollout sampling temperature")
    ap.add_argument("--max-prompt-len", type=int, default=1024)
    ap.add_argument("--max-completion-len", type=int, default=640)
    ap.add_argument("--batch-size", type=int, default=2)
    ap.add_argument("--grad-accum", type=int, default=8)
    ap.add_argument("--resume", default=None)
    ap.add_argument("--w-node", type=float, default=0.30)
    ap.add_argument("--w-edge", type=float, default=0.40)
    ap.add_argument("--w-struct", type=float, default=0.30)
    ap.add_argument("--dry-run", action="store_true",
                    help="build the prompt dataset + reward fn + config and PRINT them; train nothing")
    a = ap.parse_args()

    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import decomp_reward as R

    prompts = build_prompts(a.data)
    if not prompts:
        print("FATAL: no GRPO prompts built from", a.data); return 2
    reward_fn = R.make_trl_reward_fn(
        gold_by_prompt={}, db_path=a.db,
        weights={"node": a.w_node, "edge": a.w_edge, "struct": a.w_struct})

    if a.dry_run:
        # CPU-only: prove the dataset + reward wiring without loading a model.
        catalog = R.load_catalog(a.db)
        print(f"[dry-run] GRPO prompts built: {len(prompts)} (from {a.data})")
        print(f"[dry-run] catalog indexed:    {catalog['n']} workflows ({a.db})")
        ex = prompts[0]
        gold = json.loads(ex["gold"])
        # simulate a group of rollouts for this prompt: the reward fn must rank oracle highest
        comps = [json.dumps(R._degrade(gold, m)) for m in
                 ("oracle", "all_chain", "all_parallel", "malformed")]
        # emulate TRL's call: completions as list of assistant strings, gold forwarded per-item
        rewards = reward_fn(prompts=[ex["prompt"]] * len(comps), completions=comps,
                            gold=[ex["gold"]] * len(comps))
        print(f"[dry-run] reward over a simulated rollout group (prompt 0, struct="
              f"{R._load_scorer(a.scorer)._structure_of(gold)}):")
        for m, rw in zip(("oracle", "all_chain", "all_parallel", "malformed"), rewards):
            print(f"            {m:13s} reward={rw:+.4f}")
        assert rewards[0] == max(rewards), "oracle must be the group-max reward"
        print("[dry-run] OK — oracle is the group-max; GRPO advantage would be positive for it.")
        print("[dry-run] GRPOConfig that WOULD be used:")
        cfg = dict(output_dir=a.out, num_generations=a.num_generations, beta=a.beta,
                   temperature=a.temperature, learning_rate=a.lr, max_steps=a.max_steps,
                   save_steps=a.save_steps, per_device_train_batch_size=a.batch_size,
                   gradient_accumulation_steps=a.grad_accum,
                   max_completion_length=a.max_completion_len,
                   reward_weights=[a.w_node, a.w_edge, a.w_struct])
        print("           " + json.dumps(cfg))
        print("DRY_RUN_OK")
        return 0

    # ---- real training path (GPU box only; NOT run in this session) ----
    import torch
    from datasets import Dataset
    from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig
    from peft import LoraConfig, PeftModel, prepare_model_for_kbit_training
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
    # load the SFT-decomp adapter as the trainable, resumable start policy (the KL reference is the
    # frozen initial state of this same policy, so KL anchors to SFT-decomp behaviour).
    model = PeftModel.from_pretrained(model, a.adapter, is_trainable=True)

    # Train the SFT adapter already loaded above as the policy. Do NOT pass a peft_config to
    # GRPOTrainer: trl 1.14.1 rejects a PeftModel + peft_config together, and with peft>=0.20 the
    # no-peft_config path adds a frozen "ref" copy of THIS adapter as the KL reference — exactly the
    # intended "anchor to SFT-decomp behaviour". (A fresh LoraConfig here would start a new adapter
    # from base, discarding the SFT start policy — wrong.)
    ds = Dataset.from_list(prompts)

    cfg = GRPOConfig(
        output_dir=a.out, num_generations=a.num_generations, beta=a.beta,
        temperature=a.temperature, learning_rate=a.lr, lr_scheduler_type="cosine",
        warmup_steps=10, max_steps=a.max_steps, save_steps=a.save_steps,
        per_device_train_batch_size=a.batch_size, gradient_accumulation_steps=a.grad_accum,
        # trl 1.14.1 removed GRPOConfig.max_prompt_length (prompts are tokenized as-is; truncation is
        # tokenizer-side). Our decomp prompts are <=~505 tok << context, so the old 1024 cap never
        # truncated — dropping it is a semantic no-op. Completion cap preserved via max_completion_length.
        max_completion_length=a.max_completion_len,
        bf16=True, gradient_checkpointing=True,
        gradient_checkpointing_kwargs={"use_reentrant": False},
        optim="paged_adamw_8bit", report_to=[], seed=13, log_completions=True)

    callbacks = []
    if os.environ.get("EVAL_HOOK", "0") == "1":
        callbacks.append(make_eval_callback(a.bench, a.scorer, a.db, tok, a.eval_steps))

    trainer = GRPOTrainer(model=model, args=cfg, train_dataset=ds,
                          reward_funcs=[reward_fn], processing_class=tok,
                          callbacks=callbacks)
    trainer.train(resume_from_checkpoint=a.resume)
    trainer.save_model(a.out)
    print("GRPO_DONE ->", a.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
