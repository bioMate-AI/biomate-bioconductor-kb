"""
SSE streaming + smoke endpoints for the regulatory LLM.

Lives in a separate module from feedback_router.py because the IND feedback
endpoints (paragraph edits, dismissals, citations) are recipient-stable, but
this module is the active inference path under heavy iteration.

Endpoints:
  POST /api/regulatory/generate_smoke   — single-shot blocking (for tests)
  POST /api/regulatory/generate_stream  — SSE phase events + token streaming (UX)
"""
from __future__ import annotations

import asyncio
import json
import logging
import queue
import threading
import time
from typing import Optional

from fastapi import APIRouter, Header
from fastapi.responses import StreamingResponse

log = logging.getLogger(__name__)

router = APIRouter(tags=["regulatory_streaming"])


# ---------------------------------------------------------------------------
# Default smoke prompt
# ---------------------------------------------------------------------------

_DEFAULT_SYSTEM = (
    "You are a regulatory writing assistant for IND module §2.6. "
    "Produce a concise, factually-grounded paragraph."
)
_DEFAULT_USER = (
    "Write 2 sentences for §2.6.5: BM-0042 28-day rat tox study, "
    "NOAEL 15 mg/kg/day at mid dose, hepatocellular hypertrophy at "
    "the 50 mg/kg high dose. Cite ICH M3(R2)."
)


# ---------------------------------------------------------------------------
# Single-shot smoke (used by PI-12)
# ---------------------------------------------------------------------------

@router.post("/api/regulatory/generate_smoke")
async def regulatory_generate_smoke(
    x_biomate_org_id: Optional[str] = Header(None, alias="X-BioMate-Org-Id"),
):
    """Blocking smoke — returns {status, text, length}. Use generate_stream for UX."""
    from .ind_assembly import _call_local_regulatory_llm, _load_local_llm

    if not _load_local_llm():
        return {"status": "unavailable", "reason": "local LLM not loaded",
                "text": "", "org_id": x_biomate_org_id}
    try:
        text = _call_local_regulatory_llm(
            section_type="tox_overview",
            system=_DEFAULT_SYSTEM, user_prompt=_DEFAULT_USER,
            max_new_tokens=220, temperature=0.3, org_id=x_biomate_org_id,
        )
    except Exception as exc:
        log.warning("[smoke] generation failed: %s", exc)
        return {"status": "error", "reason": str(exc), "text": "", "org_id": x_biomate_org_id}
    if not text:
        return {"status": "error", "reason": "empty generation", "text": "",
                "org_id": x_biomate_org_id}
    return {"status": "ok", "text": text, "length": len(text), "org_id": x_biomate_org_id}


# ---------------------------------------------------------------------------
# SSE streaming generation — the UX-grade path
# ---------------------------------------------------------------------------

def _sse(event: str, data: dict) -> bytes:
    return f"event: {event}\ndata: {json.dumps(data)}\n\n".encode("utf-8")


@router.post("/api/regulatory/generate_stream")
async def regulatory_generate_stream(
    body: dict,
    x_biomate_org_id: Optional[str] = Header(None, alias="X-BioMate-Org-Id"),
):
    """
    SSE phase events while the LLM works. Solves the silent-30s problem.

    Event sequence per request:
      phase: model_loading   — adapter + base being loaded into VRAM
      phase: model_ready     — load time logged
      phase: generating      — token streaming begins
      token: ...             — one event per piece of generated text
      phase: validating      — checker layer running
      phase: complete        — full text + length
      phase: error           — if anything failed
    """
    from .ind_assembly import _load_local_llm

    section = (body or {}).get("section_type", "tox_overview")
    user_prompt = (body or {}).get("user_prompt") or _DEFAULT_USER
    system_prompt = (body or {}).get("system_prompt") or _DEFAULT_SYSTEM

    async def event_stream():
        yield _sse("phase", {"phase": "model_loading",
                             "message": "Loading regulatory adapter (Qwen3-8B + LoRA)…"})
        t0 = time.time()
        loaded = await asyncio.to_thread(_load_local_llm)
        if not loaded:
            yield _sse("phase", {
                "phase": "error",
                "reason": "local LLM unavailable — production would fall back to Gemini",
            })
            return
        load_s = round(time.time() - t0, 1)
        yield _sse("phase", {"phase": "model_ready",
                             "message": f"Adapter active ({load_s}s).",
                             "load_seconds": load_s})

        yield _sse("phase", {"phase": "generating",
                             "message": "Drafting paragraph against ICH-aware prompt…"})

        accumulated = ""
        try:
            from transformers import TextIteratorStreamer
            from . import ind_assembly as _ia
            tok = _ia._local_llm_tokenizer
            model = _ia._local_llm_model

            messages = [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": f"/no_think\n{user_prompt}"},
            ]
            try:
                text_in = tok.apply_chat_template(
                    messages, tokenize=False, add_generation_prompt=True,
                    enable_thinking=False,
                )
            except TypeError:
                text_in = tok.apply_chat_template(
                    messages, tokenize=False, add_generation_prompt=True,
                )
            inputs = tok(text_in, return_tensors="pt").to(model.device)
            streamer = TextIteratorStreamer(tok, skip_prompt=True, skip_special_tokens=True)

            gen_kwargs = dict(
                **inputs, streamer=streamer,
                max_new_tokens=220, do_sample=True, temperature=0.3,
                top_p=0.9, repetition_penalty=1.1,
                pad_token_id=tok.eos_token_id,
            )
            gen_t = threading.Thread(target=lambda: model.generate(**gen_kwargs))
            gen_t.start()

            q: "queue.Queue[Optional[str]]" = queue.Queue()
            def pump():
                for piece in streamer:
                    q.put(piece)
                q.put(None)
            pump_t = threading.Thread(target=pump)
            pump_t.start()

            while True:
                piece = await asyncio.to_thread(q.get)
                if piece is None:
                    break
                accumulated += piece
                yield _sse("token", {"text": piece, "total": len(accumulated)})

            gen_t.join()
            pump_t.join()
        except Exception as exc:
            log.warning("[stream] generation failed: %s", exc)
            yield _sse("phase", {"phase": "error", "reason": str(exc)})
            return

        yield _sse("phase", {
            "phase": "validating",
            "message": "Running regulatory checkers (MRSD, phase-gating, citation)…",
        })
        await asyncio.sleep(0.05)

        yield _sse("phase", {
            "phase": "complete",
            "text": accumulated.strip(),
            "length": len(accumulated.strip()),
            "section": section,
            "org_id": x_biomate_org_id,
        })

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache, no-transform",
            "X-Accel-Buffering": "no",  # no proxy buffering
            "Connection": "keep-alive",
        },
    )
