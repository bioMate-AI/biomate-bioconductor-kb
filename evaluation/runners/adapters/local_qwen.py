"""Local Qwen3-8B adapter — with or without LoRA.

`lora_path=None` ⇒ the base-Qwen baseline (the critical reference point
that proves the LoRA adapter is doing real work, not the base model).

Reuses the load + generate pattern from
`backend/lib/galaxy/ai/drug_discovery/ind_assembly.py::_call_local_regulatory_llm`
which has been hardened in production.
"""
from __future__ import annotations

from pathlib import Path
from typing import Optional

from ._base import AdapterError, strip_thinking


class LocalQwenAdapter:
    style = "sft_style"

    def __init__(
        self,
        lora_path: Optional[Path] = None,
        base_model: str = "Qwen/Qwen3-8B",
        name: Optional[str] = None,
    ):
        self.lora_path = lora_path
        self.base_model = base_model
        self.name = name or ("qwen3_8b_v6" if lora_path else "qwen3_8b_base")
        self._model = None
        self._tok = None

    # ------------------------------------------------------------------ load
    def _ensure_loaded(self) -> None:
        if self._model is not None:
            return
        import warnings, os as _os
        warnings.filterwarnings("ignore", message=".*sm_121.*", category=UserWarning)
        _os.environ.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")
        import torch
        from transformers import AutoModelForCausalLM, AutoTokenizer

        tok_src = str(self.lora_path) if self.lora_path else self.base_model
        self._tok = AutoTokenizer.from_pretrained(tok_src, trust_remote_code=True)
        if self._tok.pad_token is None:
            self._tok.pad_token = self._tok.eos_token

        base = AutoModelForCausalLM.from_pretrained(
            self.base_model,
            torch_dtype=torch.bfloat16,
            device_map="auto",
            trust_remote_code=True,
        )
        if self.lora_path is not None:
            if not self.lora_path.exists():
                raise AdapterError(f"LoRA adapter not found: {self.lora_path}")
            from peft import PeftModel
            self._model = PeftModel.from_pretrained(base, str(self.lora_path))
        else:
            self._model = base
        self._model.eval()

    # -------------------------------------------------------------- generate
    def generate(
        self,
        system_prompt: str,
        user_prompt: str,
        max_new_tokens: int = 400,
    ) -> str:
        self._ensure_loaded()
        import torch

        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": f"/no_think\n{user_prompt}"},
        ]
        try:
            text_in = self._tok.apply_chat_template(
                messages, tokenize=False, add_generation_prompt=True,
                enable_thinking=False,
            )
        except TypeError:
            text_in = self._tok.apply_chat_template(
                messages, tokenize=False, add_generation_prompt=True,
            )

        inputs = self._tok(text_in, return_tensors="pt").to(self._model.device)
        with torch.no_grad():
            out = self._model.generate(
                **inputs,
                max_new_tokens=max_new_tokens,
                do_sample=True,
                temperature=0.3,
                top_p=0.9,
                repetition_penalty=1.1,
                pad_token_id=self._tok.eos_token_id,
            )
        gen = out[0][inputs.input_ids.shape[1]:]
        return strip_thinking(self._tok.decode(gen, skip_special_tokens=True).strip())

    # ----------------------------------------------------------------- close
    def close(self) -> None:
        if self._model is not None:
            try:
                import torch
                del self._model
                self._model = None
                self._tok = None
                torch.cuda.empty_cache()
            except Exception:
                pass
