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


def ensure_generation_markers(chat_template: str) -> tuple[str, bool]:
    """Guarantee the chat template marks the assistant turn with `{% generation %}`.

    ROOT CAUSE of the 2026-10-07 degenerate v3 run: SFTConfig(assistant_only_loss=True)
    builds the supervised-token mask via `apply_chat_template(..., return_assistant_tokens_mask=True)`,
    which ONLY produces a non-empty mask when the template wraps the assistant response in
    `{% generation %}...{% endgeneration %}`. The clean base Qwen/Qwen3.5-9B @ c202236 template
    has NO such markers (verified against the HF revision), so on transformers' standard masking
    path the mask is empty -> every row is "fully masked" -> loss ~0 -> untrained adapter
    (num_tokens ~4089 total, 2.17 it/s, train_loss 0.0007). The prior "v2 worked" was an
    undefined, version-dependent fallback — not something to bet GPU on.

    Fix (version-independent, deterministic): split the `<|im_start|>assistant\\n` header OUT of
    the supervised span, then wrap the assistant body + tool_calls + closing `<|im_end|>` in a
    balanced `{% generation %}` block. Rendering is byte-identical (proven over 500 rows of the
    v3 mix: 500/500 identical, so NO train/serve drift), but the mask becomes a healthy ~20-25%
    of tokens (0/500 rows empty). Raises loudly if the expected anchors are absent, so a future
    template change can NEVER silently reintroduce the empty-mask bug.
    """
    if chat_template is None:
        raise RuntimeError("tokenizer has no chat_template; cannot build assistant-loss mask")
    if "{% generation %}" in chat_template or "{%- generation %}" in chat_template:
        return chat_template, False
    old1 = ("        {%- if loop.index0 > ns.last_query_index %}\n"
            "            {{- '<|im_start|>' + message.role + '\\n<think>\\n' + reasoning_content + '\\n</think>\\n\\n' + content }}\n"
            "        {%- else %}\n"
            "            {{- '<|im_start|>' + message.role + '\\n' + content }}\n"
            "        {%- endif %}")
    new1 = ("        {{- '<|im_start|>' + message.role + '\\n' }}\n"
            "        {%- generation %}\n"
            "        {%- if loop.index0 > ns.last_query_index %}\n"
            "            {{- '<think>\\n' + reasoning_content + '\\n</think>\\n\\n' + content }}\n"
            "        {%- else %}\n"
            "            {{- content }}\n"
            "        {%- endif %}")
    old2 = "        {{- '<|im_end|>\\n' }}\n    {%- elif message.role == \"tool\" %}"
    new2 = "        {{- '<|im_end|>\\n' }}\n        {%- endgeneration %}\n    {%- elif message.role == \"tool\" %}"
    if old1 not in chat_template or old2 not in chat_template:
        raise RuntimeError(
            "chat template lacks `{% generation %}` AND the known Qwen3.5 assistant-turn anchors "
            "were not found — refusing to train on an empty supervised mask. Inspect the template "
            "and update ensure_generation_markers().")
    return chat_template.replace(old1, new1).replace(old2, new2), True


def assert_nonempty_mask(tok, ds, n: int = 64) -> None:
    """Fail-fast BEFORE GPU time: tokenize a sample through the (patched) template with
    assistant-loss masking and assert a non-empty, healthy supervised fraction. Cheaper than a
    single training step; catches any masking failure (wrong template, format drift) in seconds."""
    rows = ds.select(range(min(n, ds.num_rows)))
    tot_sup = tot_tok = n_empty = 0
    for r in rows:
        out = tok.apply_chat_template(r["messages"], tokenize=True,
                                      return_assistant_tokens_mask=True, return_dict=True)
        m = out.get("assistant_masks")
        if not m:
            n_empty += 1; continue
        s = sum(m)
        if s == 0:
            n_empty += 1
        tot_sup += s; tot_tok += len(m)
    frac = (tot_sup / tot_tok) if tot_tok else 0.0
    print(f"[mask-check] sampled {len(rows)} rows: supervised={tot_sup} tokens "
          f"({100*frac:.1f}% of {tot_tok}); empty_rows={n_empty}", flush=True)
    if tot_sup == 0 or n_empty > len(rows) // 2 or frac < 0.02:
        raise RuntimeError(
            f"EMPTY/DEGENERATE assistant-loss mask (supervised={tot_sup}, empty_rows={n_empty}/"
            f"{len(rows)}, frac={frac:.4f}) — the loss mask is broken; refusing to burn GPU. "
            "This is the empty-mask bug the `{% generation %}` patch is meant to prevent.")


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
    # ROOT-CAUSE FIX (2026-10-07): ensure the chat template has `{% generation %}` markers so
    # assistant_only_loss builds a NON-empty supervised mask (see ensure_generation_markers()).
    _patched_tmpl, _did_patch = ensure_generation_markers(tok.chat_template)
    if _did_patch:
        tok.chat_template = _patched_tmpl
        print("[mask-fix] injected `{% generation %}` markers into chat template "
              "(assistant-turn supervision was otherwise empty on this base).", flush=True)
    else:
        print("[mask-fix] chat template already contains generation markers — no patch needed.", flush=True)

    bnb = BitsAndBytesConfig(load_in_4bit=True, bnb_4bit_quant_type="nf4",
                             bnb_4bit_use_double_quant=True,
                             bnb_4bit_compute_dtype=torch.bfloat16)
    from model_loading import load_text_model
    model = load_text_model(
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

    # Fail-fast BEFORE any GPU time if the supervised mask is empty/degenerate.
    assert_nonempty_mask(tok, ds)

    cfg = SFTConfig(
        output_dir=args.out,
        per_device_train_batch_size=args.batch_size,
        gradient_accumulation_steps=args.grad_accum,
        max_steps=args.max_steps,
        learning_rate=2e-4,
        lr_scheduler_type="cosine",
        warmup_steps=3,
        logging_steps=1,
        save_steps=int(os.environ.get("SAVE_STEPS", "25")),
        save_total_limit=10,
        bf16=True,
        gradient_checkpointing=True,
        gradient_checkpointing_kwargs={"use_reentrant": False},
        optim="paged_adamw_8bit",
        max_length=args.seq_len,
        ddp_find_unused_parameters=False,
        packing=False,
        dataset_num_proc=int(os.environ.get("DATASET_NUM_PROC", "4")),
        assistant_only_loss=True,          # supervise assistant tokens only
        report_to=[],
        seed=13,
    )
    trainer = SFTTrainer(model=model, args=cfg, train_dataset=ds,
                         peft_config=lora, processing_class=tok)
    result = trainer.train(resume_from_checkpoint=args.resume)

    # GUARD (2026-10-07): refuse to save a DEGENERATE run. A near-zero train_loss or an
    # impossibly-fast step rate means the supervised-token mask was essentially empty
    # (e.g. assistant_only_loss found no assistant tokens under this base's chat template),
    # so the adapter is untrained garbage. This happened on the sft_v3_real run
    # (train_loss=0.0007, 2.15 steps/s at seq 2048) and a broken adapter was uploaded + an
    # eval box spun up on it. Fail loudly BEFORE save so the entry-script `&&` chain aborts.
    _tl = result.metrics.get("train_loss")
    _rt = result.metrics.get("train_runtime") or 0.0
    _sps = (args.max_steps / _rt) if _rt else 0.0
    if _tl is not None and _tl < 0.05:
        print(f"DEGENERATE_TRAIN train_loss={_tl} (<0.05) — empty loss mask? NOT saving.", flush=True)
        return 7
    if _sps > 1.5:
        print(f"DEGENERATE_TRAIN steps_per_sec={_sps:.2f} implausibly fast for a 9B at seq>={args.seq_len} — NOT saving.", flush=True)
        return 7

    # Save the LoRA adapter in bf16 (peft creates LoRA weights in fp32 -> ~116MB; casting the
    # trainable adapter params to bf16 halves it to ~58MB with no eval-quality impact). Defensive:
    # a cast failure must not block the save of a valid adapter.
    try:
        n_cast = 0
        for name, p in trainer.model.named_parameters():
            if p.requires_grad and "lora_" in name.lower() and p.dtype == torch.float32:
                p.data = p.data.to(torch.bfloat16); n_cast += 1
        print(f"[save] cast {n_cast} fp32 LoRA tensors -> bf16 before save", flush=True)
    except Exception as e:  # pragma: no cover
        print(f"[save] bf16 adapter cast skipped ({type(e).__name__}: {e}); saving as-is", flush=True)

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
