#!/usr/bin/env python3
"""QLoRA SFT pilot for the on-prem BioMate model.

Proves the training pipeline end to end: 4-bit base load -> LoRA attach -> assistant-token
SFT on admitted episodes -> checkpoint + adapter saved (for S3 upload / spot-resume).
This is a PILOT (pipeline + resume proof), not a release model.

Usage:
  python train_qlora_pilot.py --base <path> --data train.jsonl --out out_dir \
      --max-steps 60 [--resume out_dir/checkpoint-XX]
"""
from __future__ import annotations
import argparse, json
from pathlib import Path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True, help="local path to base model (HF safetensors)")
    ap.add_argument("--data", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--max-steps", type=int, default=60)
    ap.add_argument("--seq-len", type=int, default=1024)
    ap.add_argument("--lora-r", type=int, default=16)
    ap.add_argument("--batch-size", type=int, default=1, help="per-device batch (raise to fill a big GPU)")
    ap.add_argument("--grad-accum", type=int, default=16)
    ap.add_argument("--resume", default=None)
    args = ap.parse_args()

    import os, torch
    from datasets import load_dataset
    from transformers import (AutoModelForCausalLM, AutoTokenizer,
                              BitsAndBytesConfig)
    from peft import LoraConfig, prepare_model_for_kbit_training
    from trl import SFTTrainer, SFTConfig

    # DDP-safe device map: under torchrun each rank loads the full 4-bit model onto its own GPU.
    _lr = os.environ.get("LOCAL_RANK")
    devmap = {"": int(_lr)} if _lr is not None else "auto"
    tok = AutoTokenizer.from_pretrained(args.base, trust_remote_code=True)
    if tok.pad_token is None:
        tok.pad_token = tok.eos_token

    bnb = BitsAndBytesConfig(load_in_4bit=True, bnb_4bit_quant_type="nf4",
                             bnb_4bit_use_double_quant=True,
                             bnb_4bit_compute_dtype=torch.bfloat16)
    model = AutoModelForCausalLM.from_pretrained(
        args.base, quantization_config=bnb, device_map=devmap,
        torch_dtype=torch.bfloat16, trust_remote_code=True,
        low_cpu_mem_usage=True, attn_implementation="sdpa")
    model.config.use_cache = False
    model = prepare_model_for_kbit_training(model, use_gradient_checkpointing=True)

    lora = LoraConfig(r=args.lora_r, lora_alpha=2 * args.lora_r, lora_dropout=0.05,
                      bias="none", task_type="CAUSAL_LM",
                      target_modules=["q_proj", "k_proj", "v_proj", "o_proj",
                                      "gate_proj", "up_proj", "down_proj"])

    ds = load_dataset("json", data_files=args.data, split="train")

    cfg = SFTConfig(
        output_dir=args.out,
        per_device_train_batch_size=args.batch_size,
        gradient_accumulation_steps=args.grad_accum,
        max_steps=args.max_steps,
        learning_rate=2e-4,
        lr_scheduler_type="cosine",
        warmup_steps=3,
        logging_steps=1,
        save_steps=min(max(args.max_steps // 4, 10), 200),  # spot-friendly: checkpoint <=every 200 steps
        save_total_limit=10,
        bf16=True,
        gradient_checkpointing=True,
        gradient_checkpointing_kwargs={"use_reentrant": False},
        optim="paged_adamw_8bit",
        max_length=args.seq_len,
        ddp_find_unused_parameters=False,
        packing=False,
        assistant_only_loss=True,          # supervise assistant tokens only
        report_to=[],
        seed=13,
    )
    trainer = SFTTrainer(model=model, args=cfg, train_dataset=ds,
                         peft_config=lora, processing_class=tok)
    result = trainer.train(resume_from_checkpoint=args.resume)
    trainer.save_model(args.out)          # adapter
    tok.save_pretrained(args.out)
    (Path(args.out) / "pilot_result.json").write_text(json.dumps({
        "train_runtime_s": result.metrics.get("train_runtime"),
        "train_loss": result.metrics.get("train_loss"),
        "steps": args.max_steps, "base": args.base,
        "n_examples": ds.num_rows, "lora_r": args.lora_r, "seq_len": args.seq_len,
    }, indent=2))
    print("PILOT_DONE loss=", result.metrics.get("train_loss"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
