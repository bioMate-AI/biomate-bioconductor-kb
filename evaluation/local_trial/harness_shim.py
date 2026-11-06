#!/usr/bin/env python3
"""Tiny OpenAI-compatible /v1/chat/completions shim over a local transformers 9B.

Serves ONE reconstructed arm per process so the RealBio harness (public_export/run_baseline.py)
can hit it unchanged:
  - base arm        : --base <hf dir>
  - domainpro arm   : --base <hf dir> --merge-adapter <cpt1200 dir> --adapter <sft dir>
                      (reconstructs base_domain = base + midtrain-LoRA merged, then applies the SFT LoRA)

PROTOCOL (apples-to-apples with the knowledge_recall MCQA that produced the +5.4pp number):
  * BASE tokenizer + chat template for BOTH arms  -> only the weights differ
  * thinking disabled, greedy (temperature 0), deterministic
so the per-task base-vs-domainpro delta is attributable to the adapter stack alone.
"""
import argparse, time, uuid
import torch
from fastapi import FastAPI
from pydantic import BaseModel
from typing import List, Optional, Any, Dict
import uvicorn
from transformers import AutoTokenizer
from model_loading import load_text_model
from peft import PeftModel

TOK = None
MODEL = None
MAXCAP = 512


def build(base, tokenizer_dir, merge_adapter, adapter):
    tok = AutoTokenizer.from_pretrained(tokenizer_dir, trust_remote_code=True)
    model = load_text_model(base, torch_dtype=torch.bfloat16, device_map="auto",
                            attn_implementation="sdpa")
    if merge_adapter:
        model = PeftModel.from_pretrained(model, merge_adapter).merge_and_unload()
        print(f"[shim] merged midtrain adapter {merge_adapter}", flush=True)
    if adapter:
        model = PeftModel.from_pretrained(model, adapter)
        print(f"[shim] applied adapter {adapter}", flush=True)
    model.eval()
    return tok, model


def generate(messages, max_new, temperature=0.0):
    try:
        prompt = TOK.apply_chat_template(messages, tokenize=False, add_generation_prompt=True,
                                         enable_thinking=False)
    except TypeError:
        prompt = TOK.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
    enc = TOK(prompt, return_tensors="pt").to(MODEL.device)
    in_len = enc.input_ids.shape[1]
    # temperature==0 -> greedy/deterministic (the apples-to-apples eval default, unchanged);
    # temperature>0 -> sampling, needed so the verifier re-ranker gets DIVERSE candidates.
    gen_kwargs = dict(max_new_tokens=min(int(max_new or MAXCAP), MAXCAP),
                      pad_token_id=TOK.eos_token_id)
    if (temperature or 0) > 0:
        gen_kwargs.update(do_sample=True, temperature=float(temperature), top_p=0.95)
    else:
        gen_kwargs.update(do_sample=False)
    with torch.inference_mode():
        out = MODEL.generate(**enc, **gen_kwargs)
    gen = out[0, in_len:]
    text = TOK.decode(gen, skip_special_tokens=True)
    if "</think>" in text:
        text = text.rsplit("</think>", 1)[-1].strip()
    return text, in_len, int(gen.shape[0])


app = FastAPI()


class Msg(BaseModel):
    role: str
    content: Any


class ChatReq(BaseModel):
    model: Optional[str] = "local"
    messages: List[Msg]
    max_completion_tokens: Optional[int] = None
    max_tokens: Optional[int] = None
    temperature: Optional[float] = 0.0


@app.get("/health")
def health():
    return {"ok": MODEL is not None}


@app.get("/v1/models")
def models():
    return {"object": "list", "data": [{"id": "local", "object": "model"}]}


@app.post("/v1/chat/completions")
def chat(req: ChatReq):
    msgs = [{"role": m.role, "content": (m.content if isinstance(m.content, str) else str(m.content))}
            for m in req.messages]
    max_new = req.max_completion_tokens or req.max_tokens or MAXCAP
    text, in_tok, out_tok = generate(msgs, max_new, req.temperature or 0.0)
    return {
        "id": "chatcmpl-" + uuid.uuid4().hex[:12],
        "object": "chat.completion",
        "created": int(time.time()),
        "model": req.model or "local",
        "choices": [{"index": 0, "message": {"role": "assistant", "content": text},
                     "finish_reason": "stop"}],
        "usage": {"prompt_tokens": in_tok, "completion_tokens": out_tok,
                  "total_tokens": in_tok + out_tok},
    }


def main():
    global TOK, MODEL, MAXCAP
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True)
    ap.add_argument("--tokenizer", default=None, help="tokenizer dir; defaults to --base (same template both arms)")
    ap.add_argument("--merge-adapter", default=None)
    ap.add_argument("--adapter", default=None)
    ap.add_argument("--port", type=int, default=8000)
    ap.add_argument("--max-new", type=int, default=512)
    a = ap.parse_args()
    MAXCAP = a.max_new
    TOK, MODEL = build(a.base, a.tokenizer or a.base, a.merge_adapter, a.adapter)
    print(f"[shim] ready on :{a.port} (max_new<= {MAXCAP})", flush=True)
    uvicorn.run(app, host="127.0.0.1", port=a.port, log_level="warning")


if __name__ == "__main__":
    main()
