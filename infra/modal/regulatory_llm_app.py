"""Modal serverless GPU deploy for the BioMate regulatory LLM.

Hosts Qwen3-8B + per-org LoRA adapters as an OpenAI-compatible HTTP server
on Modal's L4 GPU. Scales to zero when idle (no cost when nobody is
generating IND prose); cold-start ~10-15s for the first request after
the keep-warm window expires.

Cost model (Modal L4 = $0.000222/s):
  * Cold start + 3s generation:       ~$0.003 / call
  * Within 5-min warm window:         ~$0.0007 / call
  * Idle warm keep (per session):     ~$0.067 / 5-min idle window

  Sporadic use (10 calls/day):        ~$5/mo
  Bursty use (1000 calls/day):        ~$25/mo
  Continuous use (always-warm 8h/d):  ~$160/mo

Compare to the original 5-node vLLM ASG plan at ~$1,760/mo. Once usage
crosses ~$200/mo on Modal we should migrate back to the ASG.

Deploy:
  modal deploy infra/modal/regulatory_llm_app.py

After deploy, Modal prints a URL like
  https://your-workspace--biomate-regulatory-llm-serve.modal.run
Set that on the Galaxy backend:
  export MODAL_REGULATORY_LLM_ENDPOINT=https://...modal.run
  export MODAL_REGULATORY_LLM_KEY=<set via `modal token` if you want auth>

The Galaxy backend (_call_modal_regulatory_llm in ind_assembly.py) hits
the /v1/chat/completions path, same shape as vLLM, so the production code
path is unchanged.

Adapters: drop new LoRAs into the Modal Volume `biomate-adapters` under
`<adapter_name>/lora_adapter/`. Trigger a rolling restart with
  modal app restart biomate-regulatory-llm
"""
from __future__ import annotations

import os
import time
from pathlib import Path

import modal

# ---------------------------------------------------------------------------
# Image + Volume
# ---------------------------------------------------------------------------
#
# Image is a thin wrapper around vllm-openai so we serve the same
# /v1/chat/completions surface as the ASG path. Pin to a known-good vLLM
# release so cold-starts are deterministic.

VLLM_TAG = "v0.6.4"

image = (
    modal.Image.from_registry(
        f"vllm/vllm-openai:{VLLM_TAG}", add_python="3.11"
    )
    .pip_install("hf_transfer==0.1.8")
    .env({
        "HF_HUB_ENABLE_HF_TRANSFER": "1",
        "VLLM_WORKER_MULTIPROC_METHOD": "spawn",
    })
)

# Adapters live in a Modal Volume so a redeploy doesn't re-download them
# and a new adapter version doesn't require an image rebuild.
adapters_vol = modal.Volume.from_name(
    "biomate-adapters", create_if_missing=True,
)
hf_cache_vol = modal.Volume.from_name(
    "biomate-hf-cache", create_if_missing=True,
)

ADAPTERS_DIR = Path("/adapters")
HF_CACHE_DIR = Path("/hf-cache")

app = modal.App("biomate-regulatory-llm", image=image)


# ---------------------------------------------------------------------------
# OpenAI-compatible chat completion server
# ---------------------------------------------------------------------------
#
# `@modal.asgi_app` wraps an ASGI app (FastAPI) so callers hit it like any
# HTTP endpoint. vLLM's openai api_server gives us /v1/chat/completions
# and /v1/models for free.
#
# Lifecycle:
#   - @modal.enter() runs once per container start: load Qwen3-8B base +
#     glob all LoRA adapters from the volume, start vLLM's engine.
#   - The container stays warm for `container_idle_timeout` seconds after
#     the last request; subsequent calls in that window skip the cold start.

@app.cls(
    gpu="L4",                       # 24 GB VRAM, $0.80/hr on-demand
    cpu=4,
    memory=32 * 1024,
    volumes={
        str(ADAPTERS_DIR): adapters_vol,
        str(HF_CACHE_DIR): hf_cache_vol,
    },
    timeout=10 * 60,                # 10-min max per request (safety net)
    scaledown_window=300,           # 5-min warm window after last request
    secrets=[
        # Optional. Set BIOMATE_VLLM_API_KEY in the Modal secret if you
        # want bearer-token auth on the endpoint.
        modal.Secret.from_name(
            "biomate-vllm-secret", required_keys=[]
        ),
    ],
)
@modal.concurrent(max_inputs=8)     # match vLLM's natural batching width
class RegulatoryLLM:
    BASE_MODEL: str = "Qwen/Qwen3-8B"

    @modal.enter()
    def load(self):
        """Boot the vLLM engine + register every LoRA adapter on disk."""
        from vllm import AsyncEngineArgs, AsyncLLMEngine
        from vllm.lora.request import LoRARequest

        # Glob adapter manifest from the volume.
        lora_modules: list[LoRARequest] = []
        if ADAPTERS_DIR.exists():
            for entry in sorted(ADAPTERS_DIR.iterdir()):
                lora_path = entry / "lora_adapter"
                if lora_path.is_dir() and (lora_path / "adapter_config.json").exists():
                    lora_modules.append(
                        LoRARequest(
                            lora_name=entry.name,
                            lora_int_id=len(lora_modules) + 1,
                            lora_local_path=str(lora_path),
                        )
                    )
                    print(f"[regulatory_llm] adapter: {entry.name}")
        if not lora_modules:
            print(
                "[regulatory_llm] WARNING: no LoRA adapters under "
                f"{ADAPTERS_DIR} — serving base Qwen3-8B only"
            )

        args = AsyncEngineArgs(
            model=self.BASE_MODEL,
            tokenizer=self.BASE_MODEL,
            download_dir=str(HF_CACHE_DIR),
            gpu_memory_utilization=0.85,
            max_model_len=4096,
            quantization="bitsandbytes",
            enforce_eager=True,
            enable_lora=bool(lora_modules),
            max_loras=max(1, len(lora_modules)),
            max_lora_rank=16,
        )
        self.engine = AsyncLLMEngine.from_engine_args(args)
        self.lora_modules = {m.lora_name: m for m in lora_modules}
        print(f"[regulatory_llm] ready (adapters={list(self.lora_modules)})")

    @modal.asgi_app()
    def serve(self):
        """Mount vLLM's OpenAI-compatible FastAPI app."""
        from fastapi import FastAPI, HTTPException, Request
        from fastapi.responses import JSONResponse

        api = FastAPI(title="biomate-regulatory-llm")

        @api.get("/health")
        async def health():
            return {"ok": True, "adapters": list(self.lora_modules)}

        @api.get("/v1/models")
        async def list_models():
            base = {"id": self.BASE_MODEL, "object": "model"}
            adapters = [{"id": n, "object": "model"} for n in self.lora_modules]
            return {"object": "list", "data": [base, *adapters]}

        @api.post("/v1/chat/completions")
        async def chat_completions(req: Request):
            body = await req.json()
            model = body.get("model") or self.BASE_MODEL
            messages = body.get("messages", [])
            if not messages:
                raise HTTPException(400, "messages is required")

            # Stitch system+user into a single prompt; Qwen3 chat template
            # would also work but this keeps the path branchless.
            sys = next(
                (m["content"] for m in messages if m.get("role") == "system"), ""
            )
            user = next(
                (m["content"] for m in messages if m.get("role") == "user"), ""
            )
            prompt = (
                f"<|im_start|>system\n{sys}<|im_end|>\n"
                f"<|im_start|>user\n{user}<|im_end|>\n"
                f"<|im_start|>assistant\n"
            )

            from vllm import SamplingParams
            sp = SamplingParams(
                max_tokens=int(body.get("max_tokens", 512)),
                temperature=float(body.get("temperature", 0.3)),
                top_p=float(body.get("top_p", 0.9)),
                repetition_penalty=float(body.get("repetition_penalty", 1.1)),
                stop=["<|im_end|>"],
            )

            lora = self.lora_modules.get(model)
            request_id = f"req-{int(time.time()*1000)}"
            text = ""
            async for out in self.engine.generate(
                prompt, sp, request_id, lora_request=lora,
            ):
                if out.finished:
                    text = out.outputs[0].text

            return JSONResponse(
                {
                    "id": request_id,
                    "object": "chat.completion",
                    "model": model,
                    "choices": [
                        {
                            "index": 0,
                            "message": {"role": "assistant", "content": text.strip()},
                            "finish_reason": "stop",
                        }
                    ],
                }
            )

        # Optional bearer-token auth via Modal Secret env var
        bearer = os.environ.get("BIOMATE_VLLM_API_KEY")
        if bearer:
            @api.middleware("http")
            async def require_bearer(request: Request, call_next):
                if request.url.path == "/health":
                    return await call_next(request)
                auth = request.headers.get("authorization", "")
                if auth != f"Bearer {bearer}":
                    return JSONResponse({"error": "unauthorized"}, status_code=401)
                return await call_next(request)

        return api


# ---------------------------------------------------------------------------
# Adapter deploy helper — `modal run infra/modal/regulatory_llm_app.py::upload_adapter --path …`
# ---------------------------------------------------------------------------

@app.function(volumes={str(ADAPTERS_DIR): adapters_vol})
def upload_adapter(name: str, local_files: dict[str, bytes]):
    """Drop a new LoRA adapter into the Modal volume.

    Pair with a tiny client script that walks
    `models/<name>/lora_adapter/` and passes `{relative_path: bytes}`.
    Returns the count of files written.
    """
    target = ADAPTERS_DIR / name / "lora_adapter"
    target.mkdir(parents=True, exist_ok=True)
    for rel, blob in local_files.items():
        (target / rel).write_bytes(blob)
    adapters_vol.commit()
    return {"adapter": name, "files": len(local_files)}
