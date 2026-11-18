"""
Preference-optimization / RL fine-tuning entrypoint — real TRL, LoRA-based.

Two training methods, both on top of a base causal LM with a PEFT LoRA adapter:

  * trl_dpo  — Direct Preference Optimization on {prompt, chosen, rejected}
               triples (DPOTrainer / DPOConfig). Offline, reward-model-free.
  * trl_grpo — Group Relative Policy Optimization on {prompt} rows, scored by a
               programmatic reward function (GRPOTrainer / GRPOConfig). Online.

TRL's deps (newer torch/transformers/pyarrow) conflict with Ludwig's pins, so
these run in a *separate* `biomate/trl-training` image, not the Ludwig one.
trl is lazy-imported; the module loads without it and the unit tests exercise
config/dataset/reward wiring without training. Real runs want a GPU for any
model beyond the tiny SmolLM default.

Produces the same TrainingResult contract + manifest as the other trainers.
"""
from __future__ import annotations

import json
import logging
import re
from pathlib import Path
from typing import Any, Callable, Optional

from .config import TrainingConfig
from .datasets import LoadedDataset
from .chemprop_trainer import TrainingResult

log = logging.getLogger(__name__)

# Reward assigned to a completion that fails a severity:"block" gate component, below
# any achievable weighted sum of in-[-1,1] components so a blocked completion always
# ranks last within its GRPO group ("gate before score").
GATE_FLOOR = -10.0


# ---------------------------------------------------------------------------
# GRPO reward functions — callable(completions, **kwargs) -> list[float]
# (TRL passes `completions` as a list of strings and `prompts` via kwargs.)
# ---------------------------------------------------------------------------
def _composite_component(comp: dict) -> tuple[float, Callable[[str], float]]:
    """Compile one declarative reward component into (weight, scorer(str)->float).

    A fixed interpreter — no `eval`/arbitrary code — so a reward_spec is safe to
    accept from a user or a project rule. Scores are in [-1, 1].
    """
    kind = comp.get("kind")
    weight = float(comp.get("weight", 1.0))
    terms = [str(t).lower() for t in comp.get("terms", [])]
    if kind == "contains_any":
        fn: Callable[[str], float] = lambda c: 1.0 if any(t in c.lower() for t in terms) else 0.0
    elif kind == "contains_all":
        fn = lambda c: 1.0 if terms and all(t in c.lower() for t in terms) else 0.0
    elif kind == "banned":
        fn = lambda c: -1.0 if any(t in c.lower() for t in terms) else 0.0
    elif kind == "regex":
        pat = re.compile(str(comp.get("pattern", "")), re.IGNORECASE)
        fn = lambda c: 1.0 if pat.search(c) else 0.0
    elif kind == "length_target":
        target = max(int(comp.get("target", 20) or 20), 1)
        fn = lambda c: float(-abs(len(c.split()) - target) / target)
    elif kind == "numeric":
        fn = lambda c: 1.0 if re.search(r"\d", c) else 0.0
    elif kind == "json_valid":
        def fn(c: str) -> float:
            try:
                json.loads(c.strip())
                return 1.0
            except Exception:
                return 0.0
    elif kind == "numeric_threshold":
        # G1: parse a number (the one after `near`, else the first) and compare to
        # `value` with `op`. +1 satisfied, -1 violated, 0 if no number to judge.
        op = str(comp.get("op", ""))
        try:
            thr = float(comp.get("value"))
        except (TypeError, ValueError):
            thr = None
        near = str(comp.get("near", "")).lower()
        _num = re.compile(r"[-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?")

        def fn(c: str) -> float:
            if thr is None:
                return 0.0
            s = str(c)
            m = None
            if near:
                idx = s.lower().find(near)
                if idx >= 0:
                    m = _num.search(s, idx + len(near))
            if m is None:
                m = _num.search(s)
            if not m:
                return 0.0
            x = float(m.group())
            ok = {"<": x < thr, "<=": x <= thr, ">": x > thr, ">=": x >= thr,
                  "==": x == thr, "!=": x != thr}.get(op, False)
            return 1.0 if ok else -1.0
    elif kind == "implies":
        # G6 (relational/conditional): if any if_term present, all then_terms must be.
        if_terms = [str(t).lower() for t in comp.get("if_terms", [])]
        then_terms = [str(t).lower() for t in comp.get("then_terms", [])]

        def fn(c: str) -> float:
            lc = c.lower()
            if not any(t in lc for t in if_terms):
                return 0.0  # rule not triggered
            return 1.0 if all(t in lc for t in then_terms) else -1.0
    elif kind == "order":
        # G7 (ordering): `before` must appear before `after`.
        before = str(comp.get("before", "")).lower()
        after = str(comp.get("after", "")).lower()

        def fn(c: str) -> float:
            lc = c.lower()
            i_b, i_a = lc.find(before), lc.find(after)
            if i_b < 0 or i_a < 0:
                return 0.0  # can't evaluate
            return 1.0 if i_b < i_a else -1.0
    else:
        fn = lambda c: 0.0
    return weight, fn


def make_reward_fn(kind: str, keyword: str = "", reward_spec: Optional[list] = None) -> Callable[..., list[float]]:
    kw = (keyword or "").strip().lower()

    def _length(completions, **_) -> list[float]:
        # Prefer concise, non-empty answers: reward peaks near ~20 words.
        out = []
        for c in completions:
            n = len(str(c).split())
            out.append(float(-abs(n - 20) / 20.0))  # 0 at 20 words, negative away
        return out

    def _keyword(completions, **_) -> list[float]:
        return [1.0 if kw and kw in str(c).lower() else 0.0 for c in completions]

    def _numeric_answer(completions, **_) -> list[float]:
        return [1.0 if re.search(r"\d", str(c)) else 0.0 for c in completions]

    if kind == "composite":
        # Weighted sum of declarative knowledge/rule components — the injectable
        # reward surface (parity with REINVENT4's multi-objective reward).
        #
        # "Gate before score" (SRVL Pillar C): a component may carry severity:"block".
        # If any block-severity component fails, the completion is FLOORED to GATE_FLOOR
        # and the weighted sum is NOT added — a polished-but-non-compliant answer can
        # never be rescued by positive soft components. The gate is evaluated by the
        # SAME declarative spec via rule_gates, so one authored rule drives both the
        # inference gate and this training reward. Specs with no severity key are
        # unchanged (gate_spec is empty → pure weighted sum), so this is backward-
        # compatible.
        from .rule_gates import evaluate_rule_gates
        scorers = [_composite_component(c) for c in (reward_spec or [])]
        gate_spec = [c for c in (reward_spec or [])
                     if isinstance(c, dict) and c.get("severity") == "block"]

        def _composite(completions, **_) -> list[float]:
            out = []
            for c in completions:
                s = str(c)
                if gate_spec and not evaluate_rule_gates(gate_spec, {"text": s}).passed:
                    out.append(GATE_FLOOR)   # blocked: gate before score
                    continue
                out.append(float(sum(w * fn(s) for (w, fn) in scorers)))
            return out
        return _composite

    return {"length": _length, "keyword": _keyword, "numeric_answer": _numeric_answer}[kind]


def _load_base(base_model: str, adapter: str, max_seq: int):
    """Load tokenizer + causal LM + optional LoRA config. Shared by DPO/GRPO."""
    import torch  # noqa: F401
    from transformers import AutoModelForCausalLM, AutoTokenizer

    tok = AutoTokenizer.from_pretrained(base_model)
    if tok.pad_token is None:
        tok.pad_token = tok.eos_token
    model = AutoModelForCausalLM.from_pretrained(base_model)
    peft_config = None
    if adapter in ("lora", "qlora"):
        from peft import LoraConfig
        peft_config = LoraConfig(
            r=8, lora_alpha=16, lora_dropout=0.05, bias="none",
            task_type="CAUSAL_LM",
        )
    return tok, model, peft_config


def train_trl(cfg: TrainingConfig, ds: LoadedDataset, artifact_dir: str) -> TrainingResult:
    """Dispatch to DPO or GRPO. `ds` is ignored — text data is loaded here."""
    if cfg.model_type == "trl_dpo":
        return _train_dpo(cfg, artifact_dir)
    if cfg.model_type == "trl_grpo":
        return _train_grpo(cfg, artifact_dir)
    raise ValueError(f"train_trl got non-TRL model_type={cfg.model_type}")


def _use_bf16() -> bool:
    """bf16 when a CUDA GPU is present (the GPU tier's CUDA trl-training image), else
    fp32. On the CPU image TRL/transformers abort with 'setup doesn't support
    bf16/gpu', so precision must follow the actual hardware, not be hard-coded."""
    try:
        import torch
        return bool(torch.cuda.is_available())
    except Exception:
        return False


def _train_dpo(cfg: TrainingConfig, artifact_dir: str) -> TrainingResult:
    try:
        from trl import DPOConfig, DPOTrainer
    except ImportError as e:
        raise ImportError(
            "trl (with transformers/peft/torch) is required for model_type=trl_dpo. "
            "Runs in the trl-training image."
        ) from e
    from datasets import Dataset
    from .datasets import load_preference_rows

    llm = cfg.llm
    rows = load_preference_rows(cfg.dataset)
    if len(rows) < 2:
        raise ValueError(f"too few preference rows for DPO ({len(rows)})")
    train_ds = Dataset.from_list(rows)

    tok, model, peft_config = _load_base(llm.base_model, llm.adapter, llm.max_sequence_length)
    out_dir = str(Path(artifact_dir) / "trl_dpo_run")
    args = DPOConfig(
        output_dir=out_dir,
        num_train_epochs=cfg.hyperparams.epochs,
        per_device_train_batch_size=max(1, cfg.hyperparams.batch_size),
        learning_rate=cfg.hyperparams.learning_rate,
        beta=llm.beta,
        max_length=llm.max_sequence_length,
        max_prompt_length=llm.max_sequence_length // 2,
        logging_steps=1,
        report_to=[],
        save_strategy="no",
        # Precision follows the hardware: bf16 on the CUDA GPU image, fp32 on CPU
        # (TRL aborts with "setup doesn't support bf16/gpu" on a CPU image).
        bf16=_use_bf16(),
        fp16=False,
    )
    log.info("[trl-dpo] %s on %s: %d pairs, %d epochs, beta=%.3f, adapter=%s",
             cfg.name, llm.base_model, len(rows), cfg.hyperparams.epochs, llm.beta, llm.adapter)

    trainer = DPOTrainer(
        model=model, ref_model=None, args=args,
        train_dataset=train_ds, processing_class=tok, peft_config=peft_config,
    )
    train_out = trainer.train()
    metrics = _extract_trl_metrics(train_out)

    model_dir = str(Path(artifact_dir) / "trl_model")
    trainer.save_model(model_dir)

    return _finish(cfg, artifact_dir, "trl_dpo", metrics, len(rows), model_dir,
                   extra={"beta": llm.beta})


def _train_grpo(cfg: TrainingConfig, artifact_dir: str) -> TrainingResult:
    try:
        from trl import GRPOConfig, GRPOTrainer
    except ImportError as e:
        raise ImportError(
            "trl (with transformers/peft/torch) is required for model_type=trl_grpo. "
            "Runs in the trl-training image."
        ) from e
    from datasets import Dataset
    from .datasets import load_prompt_rows

    llm = cfg.llm
    rows = load_prompt_rows(cfg.dataset)
    if len(rows) < 2:
        raise ValueError(f"too few prompt rows for GRPO ({len(rows)})")
    train_ds = Dataset.from_list(rows)

    tok, model, peft_config = _load_base(llm.base_model, llm.adapter, llm.max_sequence_length)
    reward_fn = make_reward_fn(llm.reward, llm.reward_keyword, llm.reward_spec)
    out_dir = str(Path(artifact_dir) / "trl_grpo_run")
    args = GRPOConfig(
        output_dir=out_dir,
        num_train_epochs=cfg.hyperparams.epochs,
        # GRPO requires the effective batch size to be a multiple of the group
        # size (num_generations); use the group size itself for the tiny runs.
        per_device_train_batch_size=llm.num_generations,
        learning_rate=cfg.hyperparams.learning_rate,
        num_generations=llm.num_generations,
        max_completion_length=llm.max_sequence_length,
        logging_steps=1,
        report_to=[],
        save_strategy="no",
        # bf16 on GPU, fp32 on CPU (see DPO note).
        bf16=_use_bf16(),
        fp16=False,
    )
    log.info("[trl-grpo] %s on %s: %d prompts, %d epochs, G=%d, reward=%s, adapter=%s",
             cfg.name, llm.base_model, len(rows), cfg.hyperparams.epochs,
             llm.num_generations, llm.reward, llm.adapter)

    trainer = GRPOTrainer(
        model=model, reward_funcs=reward_fn, args=args,
        train_dataset=train_ds, processing_class=tok, peft_config=peft_config,
    )
    train_out = trainer.train()
    metrics = _extract_trl_metrics(train_out)

    model_dir = str(Path(artifact_dir) / "trl_model")
    trainer.save_model(model_dir)

    return _finish(cfg, artifact_dir, "trl_grpo", metrics, len(rows), model_dir,
                   extra={"num_generations": llm.num_generations, "reward": llm.reward})


def _extract_trl_metrics(train_out: Any) -> dict[str, float]:
    metrics: dict[str, float] = {}
    try:
        m = getattr(train_out, "metrics", None) or {}
        for k in ("train_loss", "train_runtime", "train_samples_per_second"):
            if k in m and m[k] is not None:
                metrics[k] = float(m[k])
    except Exception as e:  # never crash a good run over metrics
        log.warning("[trl] metric extraction failed: %s", e)
    return metrics


def _finish(cfg: TrainingConfig, artifact_dir: str, model_type: str,
            metrics: dict[str, float], n_train: int, model_dir: str,
            extra: dict) -> TrainingResult:
    try:
        import trl as _trl
        fw = f"trl=={getattr(_trl, '__version__', '?')}"
    except Exception:
        fw = "trl==?"
    result = TrainingResult(
        model_type=model_type, artifact_dir=artifact_dir, metrics=metrics,
        n_train=n_train, n_val=0, n_test=0, framework_version=fw,
        extra={"model_dir": model_dir, "base_model": cfg.llm.base_model,
               "adapter": cfg.llm.adapter, "task": "text_generation",
               # TRL trains on every row; val_frac/test_frac are not applied.
               "split": {"requested": cfg.dataset.split, "method": "none_all_rows_train"},
               **extra},
    )
    (Path(artifact_dir) / "manifest.json").write_text(json.dumps({
        "name": cfg.name, "model_type": result.model_type, "task_type": cfg.task_type,
        "metrics": result.metrics, "framework_version": result.framework_version,
        "extra": result.extra,
    }, indent=2))
    return result
