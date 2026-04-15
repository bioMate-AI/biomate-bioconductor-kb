"""
baseline_llm_client.py
----------------------
Drop-in replacement for BioMateEvalClient that sends prompts directly to the
Claude API (via Anthropic SDK) without any BioMate-specific routing, prereq
checking, or workflow infrastructure.

Intended use: comparison benchmarking to quantify BioMate's added value over
a raw LLM baseline.

Usage:
    client = BaselineLLMClient.from_config(config)
    resp = client.ask("What parameters should I set for a WGS germline pipeline?")
    print(resp.text)
    # resp.workflow_card is always None
"""

from __future__ import annotations

import os
import uuid
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

import anthropic

from .biomate_client import ChatResponse

_DEFAULT_MODEL = "claude-sonnet-4-6"

_SYSTEM_PROMPT = (
    "You are an expert bioinformatics AI assistant. "
    "Answer concisely and accurately."
)


class BaselineLLMClient:
    """
    Minimal Claude API client that exposes the same ask() interface as
    BioMateEvalClient so that any BenchmarkAdapter.run() can accept it as a
    drop-in client argument.

    What it does NOT do (by design — it is the *baseline*):
      - Routing to Nextflow / Galaxy workflows
      - Prerequisite validation or license gating
      - Parameter auto-filling from a workflow schema
      - Session memory, context stacks, or multi-turn state
    """

    def __init__(
        self,
        model: str = _DEFAULT_MODEL,
        api_key: Optional[str] = None,
        system_prompt: str = _SYSTEM_PROMPT,
        max_tokens: int = 1024,
        temperature: float = 0.0,
    ):
        self.model = model
        self.system_prompt = system_prompt
        self.max_tokens = max_tokens
        self.temperature = temperature

        resolved_key = api_key or os.environ.get("ANTHROPIC_API_KEY", "")
        if not resolved_key:
            raise ValueError(
                "ANTHROPIC_API_KEY is not set. "
                "Export the environment variable or pass api_key= explicitly."
            )
        self._client = anthropic.Anthropic(api_key=resolved_key)

    # ------------------------------------------------------------------
    # Factory
    # ------------------------------------------------------------------

    @classmethod
    def from_config(cls, config: Dict[str, Any]) -> "BaselineLLMClient":
        """
        Create a BaselineLLMClient from the evaluation config dict.

        Reads from config["baseline"]:
          model   (default: "claude-sonnet-4-6")
          api_key (fallback: ANTHROPIC_API_KEY env var)
        """
        baseline_cfg = config.get("baseline", {})
        model = baseline_cfg.get("model", _DEFAULT_MODEL)
        api_key = (
            os.environ.get("ANTHROPIC_API_KEY")
            or baseline_cfg.get("api_key")
        )
        return cls(model=model, api_key=api_key)

    # ------------------------------------------------------------------
    # Public API  (mirrors BioMateEvalClient)
    # ------------------------------------------------------------------

    def ask(self, question: str, conversation_id: Optional[str] = None) -> ChatResponse:
        """
        Send a single question to Claude and return a ChatResponse.

        workflow_card is always None (no routing infrastructure).
        needs_input is always False.
        run_id is always None.
        """
        msg = self._client.messages.create(
            model=self.model,
            max_tokens=self.max_tokens,
            temperature=self.temperature,
            system=self.system_prompt,
            messages=[{"role": "user", "content": question}],
        )
        response_text = msg.content[0].text if msg.content else ""
        return ChatResponse(
            text=response_text,
            workflow_card=None,
            needs_input=False,
            missing_items=[],
            run_id=None,
            raw={"model": self.model, "usage": dict(msg.usage or {})},
        )

    def create_conversation(self) -> str:
        """Return a dummy conversation ID (baseline has no server-side state)."""
        return f"baseline-{uuid.uuid4().hex[:12]}"

    def ask_in_conversation(self, conversation_id: str, message: str) -> ChatResponse:
        """
        Send a message in a 'conversation'.

        Note: the baseline client is stateless — conversation_id is ignored and
        each call is independent. Multi-turn benchmarks should be aware of this
        limitation when comparing scores against BioMate.
        """
        return self.ask(message, conversation_id=conversation_id)

    # ------------------------------------------------------------------
    # Stub methods  (keep API surface compatible; not meaningful for baseline)
    # ------------------------------------------------------------------

    def confirm_workflow(self, run_id: str) -> bool:
        """No-op: baseline has no workflow execution."""
        return False

    def run_workflow(self, question: str):
        """
        Stub: baseline cannot execute workflows.
        Returns a minimal WorkflowResult with status='not_supported'.
        """
        from .biomate_client import WorkflowResult
        return WorkflowResult(
            run_id="",
            status="not_supported",
            error="BaselineLLMClient does not support workflow execution.",
        )
