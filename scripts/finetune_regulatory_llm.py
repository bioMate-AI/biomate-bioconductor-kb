#!/usr/bin/env python3
"""
BioMate Regulatory LLM — LoRA Fine-Tuning Script

Trains a 7-8B instruction-tuned LLM with QLoRA (4-bit NF4 quantization + LoRA adapters)
on the regulatory document generation dataset produced by build_training_pairs.py.

Target: replace Gemini Flash in _llm_narrative() with a local model that generates
higher-quality, regulation-grounded ICH M4 CTD Module 2.6 prose.

Hardware:
  - GB10 Grace Blackwell (128GB unified memory) — requires NGC container for CUDA
  - CPU fallback: llama.cpp GGUF Q4_K_M (slower but functional)

Usage:
    # Full SFT on Tasks 1+2 (recommended)
    python scripts/finetune_regulatory_llm.py \
        --model qwen2.5-7b-instruct \
        --data data/regulatory_training/tasks/splits \
        --output models/regulatory_llm_v1 \
        --task section_generation regulatory_qa \
        --epochs 3

    # Quick test run (CPU, small model)
    python scripts/finetune_regulatory_llm.py \
        --model qwen2.5-0.5b-instruct \
        --data data/regulatory_training/tasks/splits \
        --output models/regulatory_llm_test \
        --epochs 1 --max-steps 50 --no-quantize

    # Resume from checkpoint
    python scripts/finetune_regulatory_llm.py \
        --resume models/regulatory_llm_v1/checkpoint-500

Requirements (GPU path, NGC container):
    pip install transformers>=4.40 peft>=0.10 bitsandbytes>=0.43 trl>=0.8 accelerate datasets

Requirements (CPU path):
    llama.cpp installed, pip install llama-cpp-python
"""
from __future__ import annotations

import argparse
import json
import logging
import os
import sys
import time
import warnings
from pathlib import Path
from typing import Optional

# GB10 sm_121 runs sm_90 PTX via CUDA backward compat — suppress the capability warning
warnings.filterwarnings("ignore", message=".*sm_121.*not compatible.*", category=UserWarning)
os.environ.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")
# Allow non-native architectures (needed for sm_121 on some torch builds)
os.environ.setdefault("TORCH_ALLOW_TF32_CUBLAS_OVERRIDE", "1")

log = logging.getLogger(__name__)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[logging.StreamHandler(), logging.FileHandler("finetune.log", mode="a")]
)

DEFAULT_MODEL  = "Qwen/Qwen3-8B"
DEFAULT_DATA   = Path("data/regulatory_training/tasks/splits")
DEFAULT_OUTPUT = Path("models/regulatory_llm_v1")

# ─── Model aliases ────────────────────────────────────────────────────────────

MODEL_ALIASES = {
    # Qwen3 (April 2025) — recommended, hybrid thinking/non-thinking mode
    "qwen3-8b":              "Qwen/Qwen3-8B",
    "qwen3-4b":              "Qwen/Qwen3-4B",
    "qwen3-1.7b":            "Qwen/Qwen3-1.7B",
    "qwen3-0.6b":            "Qwen/Qwen3-0.6B",
    # Qwen2.5 (September 2024) — legacy
    "qwen2.5-7b-instruct":   "Qwen/Qwen2.5-7B-Instruct",
    "qwen2.5-3b-instruct":   "Qwen/Qwen2.5-3B-Instruct",
    "qwen2.5-0.5b-instruct": "Qwen/Qwen2.5-0.5B-Instruct",
    # Other
    "llama3-8b-instruct":    "meta-llama/Meta-Llama-3.1-8B-Instruct",
    "biomistral-7b":         "BioMistral/BioMistral-7B",
}

# ─── LoRA config ─────────────────────────────────────────────────────────────

LORA_TARGET_MODULES = [
    # Qwen2.5 / LLaMA-3 attention + FFN projections
    "q_proj", "k_proj", "v_proj", "o_proj",
    "gate_proj", "up_proj", "down_proj",
]

# ─── Evaluation metrics ───────────────────────────────────────────────────────

ICH_CITATIONS = [
    "EMA/CHMP/EWP/37498/2011", "ICH S7B", "ICH S2(R1)", "ICH M3(R2)",
    "ICH M4", "ICH E5", "21 CFR Part 11", "Redfern",
]

def compute_regulatory_metrics(predictions: list[str], references: list[str]) -> dict:
    """
    Compute regulatory-specific quality metrics alongside ROUGE.
    - citation_recall: fraction of expected ICH guideline citations present
    - numeric_faithfulness: fraction of numeric values in input preserved in output (placeholder)
    """
    try:
        from rouge_score import rouge_scorer
        scorer = rouge_scorer.RougeScorer(["rougeL"], use_stemmer=True)
        rouge_l_scores = [scorer.score(ref, pred)["rougeL"].fmeasure
                          for pred, ref in zip(predictions, references)]
        avg_rouge = sum(rouge_l_scores) / len(rouge_l_scores) if rouge_l_scores else 0.0
    except ImportError:
        avg_rouge = 0.0
        log.warning("rouge_score not installed — skipping ROUGE metrics")

    # Citation recall
    citation_scores = []
    for pred in predictions:
        present = sum(1 for c in ICH_CITATIONS if c.lower() in pred.lower())
        citation_scores.append(present / max(len(ICH_CITATIONS), 1))
    avg_citation = sum(citation_scores) / len(citation_scores) if citation_scores else 0.0

    # Hallucination proxy: ratio of predictions containing unsupported numeric claims
    # Real hallucination detection uses an LLM judge (regulatory_auditor.py Tier 2)
    avg_length = sum(len(p.split()) for p in predictions) / max(len(predictions), 1)

    return {
        "rouge_l":         round(avg_rouge, 4),
        "citation_recall": round(avg_citation, 4),
        "avg_length_words": round(avg_length, 1),
        "n_samples":       len(predictions),
    }


# ─── Data loading ─────────────────────────────────────────────────────────────

def load_split(split_dir: Path, split: str, task_filter: Optional[list[str]] = None) -> list[dict]:
    path = split_dir / f"{split}.jsonl"
    if not path.exists():
        log.warning("Split file not found: %s", path)
        return []
    examples = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                ex = json.loads(line)
                if task_filter:
                    task = ex.get("meta", {}).get("task", "")
                    if task not in task_filter:
                        continue
                examples.append(ex)
            except Exception:
                pass
    log.info("Loaded %d examples from %s/%s", len(examples), split_dir, split)
    return examples


def format_for_model(example: dict, tokenizer, model_id: str = "") -> str:
    """Apply the model's chat template to format the ChatML example.

    Qwen3 note: Qwen3 supports thinking and non-thinking modes. For regulatory
    prose generation we always use non-thinking mode (/no_think), which produces
    direct regulatory text without chain-of-thought reasoning overhead.
    """
    messages = list(example.get("messages", []))

    # Qwen3: inject /no_think into the first user message so model skips CoT
    is_qwen3 = "qwen3" in model_id.lower() or "Qwen3" in model_id
    if is_qwen3:
        for i, msg in enumerate(messages):
            if msg.get("role") == "user":
                # Prepend /no_think tag — Qwen3 respects this directive
                messages[i] = dict(msg, content="/no_think\n" + msg["content"])
                break

    if hasattr(tokenizer, "apply_chat_template"):
        try:
            return tokenizer.apply_chat_template(
                messages, tokenize=False, add_generation_prompt=False,
                # Qwen3 accepts enable_thinking kwarg; ignore if unsupported
                **({"enable_thinking": False} if is_qwen3 else {}),
            )
        except TypeError:
            return tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=False)
    # Fallback: manual ChatML
    parts = []
    for msg in messages:
        role, content = msg["role"], msg["content"]
        parts.append(f"<|im_start|>{role}\n{content}<|im_end|>")
    return "\n".join(parts) + "\n"


# ─── GPU training (HuggingFace PEFT + TRL) ────────────────────────────────────

def train_gpu(args) -> None:
    """Full QLoRA fine-tuning via HuggingFace PEFT + TRL SFTTrainer."""
    try:
        import torch
        from transformers import (
            AutoModelForCausalLM, AutoTokenizer, TrainingArguments,
            BitsAndBytesConfig
        )
        from peft import LoraConfig, TaskType, get_peft_model, prepare_model_for_kbit_training
        from trl import SFTTrainer, SFTConfig
        from datasets import Dataset
    except ImportError as exc:
        log.error("GPU training requires: pip install transformers peft bitsandbytes trl datasets")
        log.error("Import error: %s", exc)
        sys.exit(1)

    model_id = MODEL_ALIASES.get(args.model, args.model)
    log.info("Loading model: %s", model_id)
    log.info("CUDA available: %s", torch.cuda.is_available())
    if torch.cuda.is_available():
        log.info("GPU: %s (%s)", torch.cuda.get_device_name(0),
                 f"{torch.cuda.get_device_properties(0).total_memory / 1e9:.1f} GB")

    # 4-bit QLoRA quantization config
    bnb_config = None
    if args.quantize and torch.cuda.is_available():
        bnb_config = BitsAndBytesConfig(
            load_in_4bit=True,
            bnb_4bit_quant_type="nf4",
            bnb_4bit_compute_dtype=torch.bfloat16,
            bnb_4bit_use_double_quant=True,
        )
        log.info("Using 4-bit NF4 quantization (QLoRA)")

    # Load tokenizer
    tokenizer = AutoTokenizer.from_pretrained(
        model_id, trust_remote_code=True, padding_side="right"
    )
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token

    # Load model
    model = AutoModelForCausalLM.from_pretrained(
        model_id,
        quantization_config=bnb_config,
        device_map="auto" if torch.cuda.is_available() else "cpu",
        trust_remote_code=True,
        torch_dtype=torch.bfloat16 if torch.cuda.is_available() else torch.float32,
    )

    if bnb_config:
        model = prepare_model_for_kbit_training(model)

    # LoRA config
    lora_config = LoraConfig(
        task_type=TaskType.CAUSAL_LM,
        r=args.lora_r,
        lora_alpha=args.lora_alpha,
        lora_dropout=args.lora_dropout,
        target_modules=LORA_TARGET_MODULES,
        bias="none",
    )
    model = get_peft_model(model, lora_config)
    model.print_trainable_parameters()

    # Load data
    task_filter = args.task if args.task else None
    train_data = load_split(args.data, "train", task_filter)
    dev_data   = load_split(args.data, "dev",   task_filter)

    if not train_data:
        log.error("No training data found. Run build_training_pairs.py first.")
        sys.exit(1)

    # Format with chat template — pass model_id for Qwen3 thinking-mode control
    def format_example(ex):
        return {"text": format_for_model(ex, tokenizer, model_id=model_id)}

    train_dataset = Dataset.from_list([format_example(ex) for ex in train_data])
    eval_dataset  = Dataset.from_list([format_example(ex) for ex in dev_data]) if dev_data else None

    # Training arguments — TRL 1.x: max_seq_length moved from SFTConfig to SFTTrainer
    do_eval = eval_dataset is not None
    training_args = SFTConfig(
        output_dir=str(args.output),
        num_train_epochs=args.epochs,
        max_steps=args.max_steps if args.max_steps > 0 else -1,
        per_device_train_batch_size=args.batch_size,
        gradient_accumulation_steps=args.grad_accum,
        learning_rate=args.lr,
        lr_scheduler_type="cosine",
        warmup_steps=50,
        weight_decay=0.01,
        optim="paged_adamw_8bit" if bnb_config else "adamw_torch",
        fp16=False,
        bf16=torch.cuda.is_available(),
        logging_steps=10,
        eval_strategy="steps" if do_eval else "no",
        eval_steps=100 if do_eval else None,
        save_strategy="steps",
        save_steps=200,
        save_total_limit=3,
        load_best_model_at_end=do_eval,
        metric_for_best_model="eval_loss" if do_eval else None,
        report_to="none",  # no wandb
        dataset_text_field="text",
        packing=False,
    )

    # TRL 1.x API changes:
    #   tokenizer       → processing_class
    #   max_seq_length  → removed from SFTConfig, set on tokenizer instead
    import inspect
    sig = inspect.signature(SFTTrainer.__init__).parameters
    tokenizer.model_max_length = args.max_seq_length  # always set truncation limit

    trainer_kwargs: dict = dict(
        model=model,
        args=training_args,
        train_dataset=train_dataset,
        eval_dataset=eval_dataset,
    )
    # TRL < 1.0: tokenizer kwarg; TRL >= 1.0: processing_class kwarg
    if "processing_class" in sig:
        trainer_kwargs["processing_class"] = tokenizer
    elif "tokenizer" in sig:
        trainer_kwargs["tokenizer"] = tokenizer

    if "max_seq_length" in sig:
        trainer_kwargs["max_seq_length"] = args.max_seq_length

    trainer = SFTTrainer(**trainer_kwargs)

    log.info("Starting training — %d examples, %d epochs, LR=%.0e",
             len(train_data), args.epochs, args.lr)
    t0 = time.time()
    trainer.train(resume_from_checkpoint=args.resume)
    elapsed = time.time() - t0
    log.info("Training complete in %.1f min", elapsed / 60)

    # Save LoRA adapter
    adapter_path = args.output / "lora_adapter"
    model.save_pretrained(adapter_path)
    tokenizer.save_pretrained(adapter_path)
    log.info("LoRA adapter saved → %s", adapter_path)

    # Evaluate on test set
    test_data = load_split(args.data, "test", task_filter)
    if test_data:
        log.info("Evaluating on %d test examples…", len(test_data))
        predictions, references, section_types = [], [], []
        model.eval()
        import torch
        # Sample up to 50 section_generation examples for the audit
        eval_pool = [ex for ex in test_data if ex.get("meta", {}).get("task") == "section_generation"]
        eval_pool = eval_pool[:50]
        for ex in eval_pool:
            messages = ex.get("messages", [])
            prompt_msgs = [m for m in messages if m["role"] != "assistant"]
            try:
                prompt = tokenizer.apply_chat_template(
                    prompt_msgs, tokenize=False, add_generation_prompt=True,
                    **({"enable_thinking": False} if "qwen3" in model_id.lower() else {}),
                )
            except TypeError:
                prompt = tokenizer.apply_chat_template(prompt_msgs, tokenize=False, add_generation_prompt=True)
            inputs = tokenizer(prompt, return_tensors="pt").to(model.device)
            with torch.no_grad():
                out = model.generate(
                    **inputs, max_new_tokens=512,  # 512 tokens ≈ 380 words, enough for eval
                    do_sample=True, temperature=0.3, top_p=0.9, repetition_penalty=1.1,
                    pad_token_id=tokenizer.eos_token_id,
                )
            pred = tokenizer.decode(out[0][inputs.input_ids.shape[1]:], skip_special_tokens=True).strip()
            ref = next((m["content"] for m in messages if m["role"] == "assistant"), "")
            predictions.append(pred)
            references.append(ref)
            section_types.append(ex.get("meta", {}).get("section_type", "unknown"))

        metrics = compute_regulatory_metrics(predictions, references)

        # Section-type-aware audit pass rate (uses same rules as collect_dpo_training_data.py)
        import re as _re
        def _section_passes(text: str, sec: str) -> bool:
            lower = text.lower()
            if sec in ("pbpk", "pk_overview"):
                if not ("EMA/CHMP/EWP/37498/2011" in text or "67%" in text or "criterion" in lower or "within-2-fold" in lower):
                    return False
            if sec == "tox_genotox":
                if "S2(R1)" not in text and "ICH S2" not in text:
                    return False
                if "ames" not in lower and "bacterial reverse" not in lower:
                    return False
            if sec == "tox_cardiac":
                if "S7B" not in text:
                    return False
            return True

        by_section_pass: dict[str, list[bool]] = {}
        for pred, sec in zip(predictions, section_types):
            passes = _section_passes(pred, sec)
            by_section_pass.setdefault(sec, []).append(passes)

        audit_summary = {
            sec: {"pass_rate": round(sum(vs)/len(vs), 3), "n": len(vs)}
            for sec, vs in by_section_pass.items()
        }
        overall_pass_rate = sum(v for vs in by_section_pass.values() for v in vs) / max(len(predictions), 1)
        metrics["audit_pass_rate"] = round(overall_pass_rate, 3)
        metrics["audit_by_section"] = audit_summary

        log.info("Test metrics: %s", json.dumps(metrics, indent=2))
        with open(args.output / "eval_metrics.json", "w") as f:
            json.dump(metrics, f, indent=2)

    # Save training manifest
    manifest = {
        "model_id": model_id,
        "base_model": model_id,
        "lora_r": args.lora_r,
        "lora_alpha": args.lora_alpha,
        "epochs": args.epochs,
        "lr": args.lr,
        "batch_size": args.batch_size,
        "grad_accum": args.grad_accum,
        "quantization": "nf4" if bnb_config else "none",
        "training_examples": len(train_data),
        "task_filter": task_filter,
        "training_time_min": round(elapsed / 60, 1),
        "adapter_path": str(adapter_path),
    }
    with open(args.output / "training_manifest.json", "w") as f:
        json.dump(manifest, f, indent=2)
    log.info("Manifest saved → %s", args.output / "training_manifest.json")


# ─── CPU training via llama.cpp (fallback) ────────────────────────────────────

def train_cpu_llamacpp(args) -> None:
    """
    CPU fine-tuning via llama.cpp --finetune (LoRA).
    Works on the GB10 ARM CPU without NGC container.
    Slower but functional: ~4-8 hours per epoch on 72-core Grace with Q4 model.
    """
    import subprocess
    model_id = MODEL_ALIASES.get(args.model, args.model)

    # Check for llama.cpp
    llamacpp = os.environ.get("LLAMACPP_PATH", "llama-finetune")
    result = subprocess.run([llamacpp, "--version"], capture_output=True)
    if result.returncode != 0:
        log.error("llama.cpp not found at '%s'", llamacpp)
        log.info("Install: git clone https://github.com/ggerganov/llama.cpp && cd llama.cpp && make -j$(nproc)")
        log.info("Set LLAMACPP_PATH env var to point to the llama-finetune binary")
        sys.exit(1)

    # Prepare training data in llama.cpp format (plain text with BOS/EOS)
    task_filter = args.task if args.task else None
    train_data = load_split(args.data, "train", task_filter)
    if not train_data:
        log.error("No training data found")
        sys.exit(1)

    train_txt = args.output / "train_llamacpp.txt"
    args.output.mkdir(parents=True, exist_ok=True)
    with open(train_txt, "w", encoding="utf-8") as f:
        for ex in train_data:
            msgs = ex.get("messages", [])
            # Write as plain text: system + user + assistant concatenated
            for msg in msgs:
                f.write(msg.get("content", "") + "\n")
            f.write("\n---\n\n")

    log.info("Training data written → %s (%d examples)", train_txt, len(train_data))

    # Download GGUF model if needed
    gguf_path = args.output / "base_model.gguf"
    if not gguf_path.exists():
        log.info("Download a GGUF model to %s", gguf_path)
        log.info("Example: huggingface-cli download Qwen/Qwen2.5-7B-Instruct-GGUF qwen2.5-7b-instruct-q4_k_m.gguf --local-dir %s", args.output)
        log.info("Or: wget -O %s https://huggingface.co/Qwen/Qwen2.5-7B-Instruct-GGUF/resolve/main/qwen2.5-7b-instruct-q4_k_m.gguf", gguf_path)
        log.warning("GGUF base model not found — set path manually or download above")
        return

    # Run llama.cpp fine-tune
    adapter_path = args.output / "lora_adapter_gguf.bin"
    cmd = [
        llamacpp,
        "--model-base", str(gguf_path),
        "--train-data",  str(train_txt),
        "--lora-out",   str(adapter_path),
        "--rank",        str(args.lora_r),
        "--lora-alpha",  str(args.lora_alpha),
        "--epochs",      str(args.epochs),
        "--batch",       str(args.batch_size),
        "--ctx",         str(args.max_seq_length),
        "--seed",        "42",
        "--adam-iter",   "30",
        "--threads",     str(os.cpu_count() or 16),
    ]
    if args.max_steps > 0:
        cmd += ["--adam-iter", str(args.max_steps)]

    log.info("Running llama.cpp fine-tune: %s", " ".join(cmd))
    result = subprocess.run(cmd, check=False)
    if result.returncode != 0:
        log.error("llama.cpp fine-tune failed with exit code %d", result.returncode)
    else:
        log.info("llama.cpp adapter saved → %s", adapter_path)


# ─── DPO training ─────────────────────────────────────────────────────────────

def train_dpo(args) -> None:
    """
    DPO (Direct Preference Optimization) fine-tuning on (prompt, chosen, rejected) pairs.

    Reward signal: BioMate regulatory auditor — outputs with MAJOR findings are rejected,
    auditor-clean outputs (Gemini or human-written) are chosen.

    Requires DPO pairs collected via:
      python scripts/collect_dpo_training_data.py --audit-failures --gemini-pairs
    """
    try:
        import torch
        from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig
        from peft import LoraConfig, TaskType, get_peft_model, PeftModel
        from trl import DPOConfig, DPOTrainer
        from datasets import Dataset
    except ImportError as exc:
        log.error("DPO requires: pip install transformers peft bitsandbytes trl datasets")
        raise

    dpo_file = args.dpo_data
    if not dpo_file or not Path(dpo_file).exists():
        log.error("DPO data not found at %s — run collect_dpo_training_data.py first", dpo_file)
        sys.exit(1)

    with open(dpo_file) as f:
        raw_pairs = [json.loads(l) for l in f if l.strip()]
    log.info("DPO pairs loaded: %d", len(raw_pairs))
    if len(raw_pairs) < 10:
        log.error("Need ≥10 DPO pairs for meaningful training (got %d)", len(raw_pairs))
        sys.exit(1)

    model_id = MODEL_ALIASES.get(args.model, args.model)
    bnb_config = BitsAndBytesConfig(
        load_in_4bit=True, bnb_4bit_quant_type="nf4",
        bnb_4bit_compute_dtype=torch.bfloat16, bnb_4bit_use_double_quant=True,
    ) if args.quantize and torch.cuda.is_available() else None

    tokenizer = AutoTokenizer.from_pretrained(
        args.resume or model_id, trust_remote_code=True
    )
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token

    # Load base + existing SFT adapter (if --resume provided)
    model = AutoModelForCausalLM.from_pretrained(
        model_id, quantization_config=bnb_config,
        device_map="auto", torch_dtype=torch.bfloat16,
    )
    if args.resume and Path(args.resume).exists():
        log.info("Loading SFT adapter from %s for DPO initialization", args.resume)
        model = PeftModel.from_pretrained(model, args.resume)
        model = model.merge_and_unload()  # merge SFT LoRA before DPO

    # Add fresh LoRA for DPO
    lora_config = LoraConfig(
        task_type=TaskType.CAUSAL_LM,
        r=args.lora_r, lora_alpha=args.lora_alpha,
        lora_dropout=args.lora_dropout,
        target_modules=LORA_TARGET_MODULES, bias="none",
    )
    model = get_peft_model(model, lora_config)
    model.print_trainable_parameters()

    # DPO dataset format: {prompt, chosen, rejected}
    dataset = Dataset.from_list(raw_pairs)
    split = dataset.train_test_split(test_size=0.1, seed=42)

    dpo_config = DPOConfig(
        output_dir=str(args.output),
        num_train_epochs=args.epochs,
        per_device_train_batch_size=args.batch_size,
        gradient_accumulation_steps=args.grad_accum,
        learning_rate=args.lr * 0.1,  # DPO uses lower LR than SFT
        bf16=torch.cuda.is_available(),
        logging_steps=5,
        save_steps=50,
        report_to="none",
        beta=0.1,           # DPO temperature — controls deviation from reference
        max_prompt_length=1024,
        max_length=2048,
    )

    trainer = DPOTrainer(
        model=model,
        args=dpo_config,
        train_dataset=split["train"],
        eval_dataset=split["test"],
        processing_class=tokenizer,
    )

    log.info("Starting DPO training on %d pairs (β=%.2f)", len(raw_pairs), dpo_config.beta)
    trainer.train()

    adapter_path = args.output / "dpo_adapter"
    model.save_pretrained(adapter_path)
    tokenizer.save_pretrained(adapter_path)
    log.info("DPO adapter saved → %s", adapter_path)


# ─── NGC container setup instructions ─────────────────────────────────────────

def print_ngc_setup() -> None:
    """Print NGC container setup instructions for GB10 CUDA access."""
    print("""
╔══════════════════════════════════════════════════════════════════════════════╗
║  NGC Container Setup — Enable CUDA on GB10 Blackwell for Fine-Tuning        ║
╚══════════════════════════════════════════════════════════════════════════════╝

The GB10 (Grace Blackwell) uses compute capability sm_121, which requires
NVIDIA's own PyTorch build. Standard PyPI torch has no aarch64+CUDA wheels.

Step 1: Pull the NGC PyTorch container
─────────────────────────────────────
  docker pull nvcr.io/nvidia/pytorch:25.04-py3

Step 2: Run the container with GPU access
──────────────────────────────────────────
  docker run --gpus all --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 \\
    -v $(pwd):/workspace -w /workspace \\
    -it nvcr.io/nvidia/pytorch:25.04-py3

Step 3: Inside container, install fine-tuning libraries
────────────────────────────────────────────────────────
  pip install peft>=0.10 trl>=0.8 bitsandbytes>=0.43 datasets rouge_score

Step 4: Verify GPU access
──────────────────────────
  python -c "import torch; print(torch.cuda.is_available(), torch.cuda.get_device_name(0))"
  # Expected: True  NVIDIA GB10

Step 5: Run fine-tuning
────────────────────────
  python scripts/finetune_regulatory_llm.py \\
    --model qwen3-8b \\
    --data data/regulatory_training/tasks/splits \\
    --output models/regulatory_llm_v1 \\
    --epochs 3 --lora-r 16

Model options (recommended):
  qwen3-8b    (default) Qwen3 8B, April 2025, hybrid thinking/non-thinking mode
  qwen3-4b              Qwen3 4B, faster, still strong multilingual
  qwen3-1.7b            Qwen3 1.7B, fastest, for quick iteration

Estimated training time (GB10 GPU):
  Task 1+2 SFT (3,089 train pairs):  4-8 hours
  DAPT (5B tokens):                  12-24 hours

Memory requirement:
  Qwen3-8B in 4-bit NF4 QLoRA:  ~18 GB GPU memory
  GB10 total unified memory:     128 GB ✓ (ample headroom)
""")


# ─── CLI ──────────────────────────────────────────────────────────────────────

def main() -> None:
    ap = argparse.ArgumentParser(description="Fine-tune regulatory LLM with QLoRA")
    ap.add_argument("--model",          default="qwen3-8b",
                    help=f"Model name or HuggingFace ID. Aliases: {list(MODEL_ALIASES.keys())}")
    ap.add_argument("--data",           type=Path, default=DEFAULT_DATA)
    ap.add_argument("--output",         type=Path, default=DEFAULT_OUTPUT)
    ap.add_argument("--task",           nargs="+",
                    choices=["section_generation", "regulatory_qa", "region_adaptation", "table_generation"],
                    help="Task filter (default: all Tasks 1+2)")
    ap.add_argument("--epochs",         type=int,   default=3)
    ap.add_argument("--max-steps",      type=int,   default=0,    help="0 = run all epochs")
    ap.add_argument("--batch-size",     type=int,   default=4)
    ap.add_argument("--grad-accum",     type=int,   default=8,    help="Effective batch = batch * grad_accum")
    ap.add_argument("--lr",             type=float, default=2e-4)
    ap.add_argument("--lora-r",         type=int,   default=16)
    ap.add_argument("--lora-alpha",     type=int,   default=32)
    ap.add_argument("--lora-dropout",   type=float, default=0.05)
    ap.add_argument("--max-seq-length", type=int,   default=2048)
    ap.add_argument("--quantize",       action="store_true", default=True,
                    help="Enable 4-bit NF4 quantization (QLoRA, requires GPU)")
    ap.add_argument("--no-quantize",    action="store_true",
                    help="Disable quantization (for CPU or testing)")
    ap.add_argument("--cpu",            action="store_true",
                    help="Use llama.cpp CPU path instead of HuggingFace")
    ap.add_argument("--resume",         type=str, default=None, help="Resume from checkpoint path")
    ap.add_argument("--ngc-setup",      action="store_true", help="Print NGC container setup instructions")
    # DPO arguments
    ap.add_argument("--dpo",            action="store_true",
                    help="Run DPO alignment instead of SFT (requires --dpo-data)")
    ap.add_argument("--dpo-data",       type=Path, default=None,
                    help="Path to DPO (prompt, chosen, rejected) JSONL pairs")
    args = ap.parse_args()

    if args.ngc_setup:
        print_ngc_setup()
        return

    if args.no_quantize:
        args.quantize = False

    args.output.mkdir(parents=True, exist_ok=True)

    log.info("BioMate Regulatory LLM Fine-Tuner")
    log.info("Model:  %s", MODEL_ALIASES.get(args.model, args.model))
    log.info("Data:   %s", args.data)
    log.info("Output: %s", args.output)
    log.info("Tasks:  %s", args.task or "all")
    log.info("Epochs: %d  LR: %.0e  LoRA r=%d α=%d", args.epochs, args.lr, args.lora_r, args.lora_alpha)
    log.info("Quant:  %s  CPU: %s", args.quantize, args.cpu)

    if args.dpo:
        log.info("Mode: DPO alignment  DPO data: %s", args.dpo_data)
        train_dpo(args)
    elif args.cpu:
        train_cpu_llamacpp(args)
    else:
        try:
            import torch
            if not torch.cuda.is_available():
                log.warning("CUDA not available — GPU training will run on CPU (very slow)")
                log.warning("For GPU access on GB10, run: python %s --ngc-setup", __file__)
        except ImportError:
            log.error("PyTorch not installed or CPU-only build active")
            log.info("For GPU training on GB10, run: python %s --ngc-setup", __file__)
        train_gpu(args)


if __name__ == "__main__":
    main()
