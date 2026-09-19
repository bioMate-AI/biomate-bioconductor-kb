"""Grounded DPO (stage 4): preference optimization where the reward is GROUNDED, not a judge's taste.

For routing/param prompts we already know the gold. We sample K completions from the SFT model,
score each with a grounded reward, and form (chosen, rejected) pairs:
  - routing:  reward = 1 if the named workflow == gold (or an acceptable alt), else 0
  - param:    reward = fraction of gold param values present AND schema-valid (no invented keys)
  - diagnosis:reward = 1 if predicted category == gold category
The best-scoring sample is 'chosen', a strictly-worse one is 'rejected'. DPO then contrasts them --
generation-level contrastive learning, the same principle as the retriever's InfoNCE one level up.

Runs on the GPU box against the merged SFT model. Two phases: (A) build pairs by sampling; (B) DPO."""
import argparse, json, re, os, sys
from pathlib import Path

def norm(s): return re.sub(r"[^a-z0-9]+"," ",str(s).lower()).strip()

def reward(task, gold, out):
    o=norm(out)
    if task=="routing":
        cw=norm(gold.get("correct_workflow","")); return 1.0 if cw and cw in o else 0.0
    if task=="diagnosis":
        c=norm(gold.get("category","")); return 1.0 if c and c in o else 0.0
    if task=="param":
        exp=gold.get("expected_params",{}) or {}
        if not exp: return 0.0
        return sum(1 for v in exp.values() if norm(v) and norm(v) in o)/len(exp)
    return 0.0

def build_pairs(args):
    """Phase A: sample K completions per prompt from the SFT model, score, emit chosen/rejected pairs."""
    import torch
    from transformers import AutoModelForCausalLM, AutoTokenizer
    tok=AutoTokenizer.from_pretrained(args.model, trust_remote_code=True)
    model=AutoModelForCausalLM.from_pretrained(args.model, torch_dtype=torch.bfloat16,
        device_map="auto", trust_remote_code=True)
    model.eval()
    rows=[json.loads(l) for l in open(args.prompts) if l.strip()]
    pairs=[]
    for r in rows:
        task=r["task"]; gold=r["ground_truth"]; prompt=r["prompt"]
        enc=tok.apply_chat_template([{"role":"user","content":prompt}], add_generation_prompt=True,
                                    return_tensors="pt", return_dict=True)
        enc={k:v.to(model.device) for k,v in enc.items()}; ilen=enc["input_ids"].shape[1]
        outs=[]
        for _ in range(args.k):
            with torch.no_grad():
                g=model.generate(**enc, max_new_tokens=96, do_sample=True, temperature=0.9, top_p=0.95,
                                 pad_token_id=tok.pad_token_id or tok.eos_token_id)
            outs.append(tok.decode(g[0][ilen:], skip_special_tokens=True))
        scored=sorted(((reward(task,gold,o),o) for o in outs), key=lambda x:-x[0])
        if scored[0][0] > scored[-1][0]:   # a real preference gap exists
            pairs.append({"prompt":prompt,"chosen":scored[0][1],"rejected":scored[-1][1],
                          "task":task,"margin":round(scored[0][0]-scored[-1][0],3)})
    Path(args.pairs_out).write_text("\n".join(json.dumps(p) for p in pairs))
    print(f"DPO PAIRS: {len(pairs)}/{len(rows)} prompts yielded a preference gap -> {args.pairs_out}")

def train(args):
    """Phase B: DPO on the grounded pairs."""
    import torch
    from datasets import load_dataset
    from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig
    from peft import LoraConfig, prepare_model_for_kbit_training
    from trl import DPOTrainer, DPOConfig
    tok=AutoTokenizer.from_pretrained(args.model, trust_remote_code=True)
    if tok.pad_token is None: tok.pad_token=tok.eos_token
    bnb=BitsAndBytesConfig(load_in_4bit=True, bnb_4bit_quant_type="nf4",
        bnb_4bit_use_double_quant=True, bnb_4bit_compute_dtype=torch.bfloat16)
    model=AutoModelForCausalLM.from_pretrained(args.model, quantization_config=bnb, device_map="auto",
        torch_dtype=torch.bfloat16, trust_remote_code=True)
    model=prepare_model_for_kbit_training(model, use_gradient_checkpointing=True)
    lora=LoraConfig(r=16, lora_alpha=32, lora_dropout=0.05, bias="none", task_type="CAUSAL_LM",
        target_modules=["q_proj","k_proj","v_proj","o_proj","gate_proj","up_proj","down_proj"])
    ds=load_dataset("json", data_files=args.pairs_out, split="train")
    cfg=DPOConfig(output_dir=args.out, per_device_train_batch_size=1, gradient_accumulation_steps=16,
        num_train_epochs=1, learning_rate=5e-6, lr_scheduler_type="cosine", warmup_steps=10,
        bf16=True, gradient_checkpointing=True, gradient_checkpointing_kwargs={"use_reentrant":False},
        optim="paged_adamw_8bit", beta=0.1, max_length=1024, max_prompt_length=768, report_to=[], seed=13)
    tr=DPOTrainer(model=model, args=cfg, train_dataset=ds, processing_class=tok, peft_config=lora)
    tr.train(); tr.save_model(args.out); print("DPO_DONE ->", args.out)

def mine_routing_pairs(args):
    """Direct contrastive pairs from rag_routing hard_negatives (near-ties): chosen = verified gold,
    rejected = the near-tie the retriever nearly ranked first. No sampling needed — these ARE the
    hardest cases, exactly what the model must learn to discriminate (user's contrastive point)."""
    import random as _r; _r.seed(13)
    rows=[json.loads(l) for l in open(args.prompts) if l.strip()]
    pairs=[]
    for rr in rows:
        hn=rr.get("hard_negatives") or []
        if not hn: continue
        prompt=rr["messages"][0]["content"]; gold=rr["messages"][1]["content"]
        for neg in hn[:3]:
            if neg and neg!=gold:
                pairs.append({"prompt":prompt,"chosen":gold,"rejected":neg,"task":"routing"})
    Path(args.pairs_out).write_text("\n".join(json.dumps(p) for p in pairs))
    print(f"ROUTING DPO PAIRS (near-tie hard negatives): {len(pairs)} -> {args.pairs_out}")

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--phase", choices=["pairs","mine","train"], required=True)
    ap.add_argument("--model", required=True, help="merged SFT model")
    ap.add_argument("--prompts", help="jsonl {task,prompt,ground_truth} (phase pairs)")
    ap.add_argument("--pairs-out", default="dpo_pairs.jsonl")
    ap.add_argument("--out", default="dpo_out"); ap.add_argument("--k", type=int, default=6)
    a=ap.parse_args()
    if a.phase=="mine": return mine_routing_pairs(a)   # cheap: direct near-tie hard-negative pairs
    return build_pairs(a) if a.phase=="pairs" else train(a)

if __name__=="__main__": raise SystemExit(main())
