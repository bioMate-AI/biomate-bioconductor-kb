"""
biomate_client.py
-----------------
HTTP client that submits evaluation tasks to a running BioMate instance
and extracts structured responses.

Covers:
  - Single-turn chat  (ask)
  - Multi-turn chat   (session-based)
  - Workflow execution with wait-for-terminal  (run_workflow)
  - File attachment upload
"""

from __future__ import annotations

import json
import os
import time
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

import requests


@dataclass
class ChatResponse:
    text: str
    workflow_card: Optional[Dict[str, Any]] = None   # present if AI returned a workflow
    # Structured needs_input signal from event: needs_input.
    # needs_input=True means BioMate is waiting for more information (not a workflow error).
    # missing_items lists the specific inputs BioMate named; empty list means the event
    # fired but no named items were provided (e.g. a general clarification question).
    needs_input: bool = False
    missing_items: List[str] = field(default_factory=list)
    run_id: Optional[str] = None
    raw: Optional[Dict[str, Any]] = None


@dataclass
class WorkflowResult:
    run_id: str
    status: str                          # completed | failed | running | timed_out
    outputs: List[Dict[str, Any]] = field(default_factory=list)
    cost_usd: Optional[float] = None
    audit_trail: Optional[Dict[str, Any]] = None
    error: Optional[str] = None


class BioMateEvalClient:
    """
    Thin HTTP client for BioMate's API surface.

    Usage:
        client = BioMateEvalClient.from_config(config)
        resp = client.ask("run differential expression on SRR123456")
        print(resp.text)
    """

    def __init__(self, base_url: str, token: str,
                 chat_timeout: int = 120, workflow_timeout: int = 600):
        self.base_url = base_url.rstrip("/")
        self.token = token
        self.chat_timeout = chat_timeout
        self.workflow_timeout = workflow_timeout
        self._session = requests.Session()
        self._session.headers.update({
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        })

    # ------------------------------------------------------------------
    # Auth
    # ------------------------------------------------------------------

    @classmethod
    def from_config(cls, config: Dict[str, Any]) -> "BioMateEvalClient":
        """Log in and return an authenticated client."""
        base_url = config["biomate"]["base_url"]
        email = config["biomate"]["eval_user_email"]
        password = (
            os.environ.get("BIOMATE_EVAL_PASSWORD")
            or config["biomate"].get("eval_user_password", "") or config["biomate"].get("eval_user", {}).get("password", "")
        )
        token = cls._login(base_url, email, password)
        return cls(
            base_url=base_url,
            token=token,
            chat_timeout=config.get("timeouts", {}).get("chat_response_sec", 120),
            workflow_timeout=config.get("timeouts", {}).get("workflow_terminal_sec", 600),
        )

    @staticmethod
    def _login(base_url: str, email: str, password: str) -> str:
        # Include the E2E bypass header so the eval harness is exempt from the
        # 5-attempts-per-15-min auth rate limit.  The server only honours this
        # header when E2E_TEST_TOKEN is set in its environment; it is a no-op
        # in production where the env var is absent.
        e2e_token = os.environ.get("E2E_TEST_TOKEN", "biomate-e2e-bypass-token-dev-only")
        resp = requests.post(
            f"{base_url}/api/auth/login",
            json={"email": email, "password": password},
            headers={"X-E2E-Test-Token": e2e_token},
            timeout=30,
        )
        resp.raise_for_status()
        return resp.json()["token"]

    # ------------------------------------------------------------------
    # Single-turn chat
    # ------------------------------------------------------------------

    def ask(self, question: str, conversation_id: Optional[str] = None) -> ChatResponse:
        """
        Send a single message to BioMate; return the full assistant response.
        Streams internally and assembles the response text.
        Retries the full request (including stream) on connection errors.
        """
        payload: Dict[str, Any] = {"message": question}
        if conversation_id:
            # BioMate reads session identity from context.memorySessionId (matching
            # the frontend's chat-interface.tsx payload format).  Top-level sessionId
            # is ignored by the server.
            payload["context"] = {"memorySessionId": conversation_id}

        max_retries = 3
        last_exc: Optional[Exception] = None

        for attempt in range(max_retries):
            if attempt > 0:
                wait = 10 * attempt  # 10s, 20s backoff
                time.sleep(wait)
                # Fresh session clears stale keep-alive connections
                self._session = requests.Session()
                self._session.headers.update({
                    "Authorization": f"Bearer {self.token}",
                    "Content-Type": "application/json",
                })

            try:
                resp = self._session.post(
                    f"{self.base_url}/api/chat/stream",
                    json=payload,
                    stream=True,
                    timeout=self.chat_timeout,
                )
                resp.raise_for_status()
            except Exception as e:
                last_exc = e
                continue

            # Stream phase — wrapped in try so broken connections trigger retry
            text_parts: List[str] = []
            workflow_card = None
            run_id = None
            needs_input_fired = False
            missing_from_event: List[str] = []

            deadline = time.time() + self.chat_timeout
            current_event = "message"
            try:
                for line in resp.iter_lines():
                    if time.time() > deadline:
                        resp.close()
                        raise TimeoutError(
                            f"SSE stream exceeded {self.chat_timeout}s wall-clock limit"
                        )
                    if not line:
                        current_event = "message"
                        continue
                    raw = line.decode("utf-8")

                    # Track SSE event type
                    if raw.startswith("event: "):
                        current_event = raw[7:].strip()
                        continue

                    if not raw.startswith("data: "):
                        continue
                    payload_str = raw[6:]
                    if payload_str == "[DONE]":
                        break
                    try:
                        chunk = json.loads(payload_str)
                    except json.JSONDecodeError:
                        continue

                    if current_event == "workflow_ready":
                        workflow_card = {
                            "name": chunk.get("workflow_name", ""),
                            "id": chunk.get("workflow_id", ""),
                            "workflow_type": chunk.get("workflow_type", ""),
                            "nextflow_path": chunk.get("nextflow_path", ""),
                            "source": chunk.get("source", ""),
                            "confidence": chunk.get("confidence"),
                            "chain_name": chunk.get("chain_name", ""),
                            "chain_steps": chunk.get("chain_steps", []),
                        }
                        current_event = "message"
                        continue

                    if current_event == "needs_input":
                        needs_input_fired = True
                        missing_from_event = chunk.get("missing", []) or []
                        current_event = "message"
                        continue

                    delta = chunk.get("text") or chunk.get("delta") or chunk.get("content", "")
                    if delta:
                        text_parts.append(delta)
                    if chunk.get("response"):
                        text_parts = [chunk["response"]]

                    meta = chunk.get("metadata", {})
                    if meta.get("workflow_card"):
                        workflow_card = meta["workflow_card"]
                    if meta.get("run_id"):
                        run_id = meta["run_id"]
                    if workflow_card is None:
                        wf = chunk.get("workflow")
                        if wf and isinstance(wf, dict):
                            ga = wf.get("workflow_ga") or {}
                            workflow_card = {
                                "name": ga.get("name", ""),
                                "id": ga.get("id", ""),
                                "source": wf.get("source", ""),
                                "confidence": wf.get("confidence"),
                                "workflow_type": wf.get("workflow_type", ""),
                                "nextflow_path": wf.get("nextflow_path", ""),
                                # Disambiguation: top-N candidates surfaced for user selection
                                "candidates": wf.get("candidates", []),
                            }

            except Exception as stream_err:
                last_exc = stream_err
                resp.close()
                continue  # retry the whole request

            # Stream completed without error
            break

        else:
            # All retries exhausted
            raise last_exc or RuntimeError("ask() failed after all retries")

        return ChatResponse(
            text="".join(text_parts),
            workflow_card=workflow_card,
            needs_input=needs_input_fired,
            missing_items=missing_from_event,
            run_id=run_id,
        )

    # ------------------------------------------------------------------
    # Multi-turn chat (session-based)
    # ------------------------------------------------------------------

    def create_conversation(self) -> str:
        """Return a new conversation/session ID for multi-turn chat.
        BioMate uses sessionId passed in the chat payload — no server-side creation needed."""
        import uuid
        return f"eval-{uuid.uuid4().hex[:12]}"

    def ask_in_conversation(self, conversation_id: str, message: str) -> ChatResponse:
        """Send a message within an existing conversation."""
        return self.ask(message, conversation_id=conversation_id)

    # ------------------------------------------------------------------
    # Workflow execution
    # ------------------------------------------------------------------

    def confirm_workflow(self, run_id: str) -> bool:
        """Confirm and start a pending workflow run."""
        resp = self._session.post(
            f"{self.base_url}/api/workflows/runs/{run_id}/confirm",
            json={},
            timeout=30,
        )
        return resp.status_code == 200

    def wait_for_terminal(self, run_id: str) -> WorkflowResult:
        """Poll workflow status until terminal state or timeout."""
        deadline = time.time() + self.workflow_timeout
        poll_interval = 5

        while time.time() < deadline:
            resp = self._session.get(
                f"{self.base_url}/api/workflows/runs/{run_id}/status",
                timeout=30,
            )
            if resp.status_code != 200:
                time.sleep(poll_interval)
                continue

            data = resp.json()
            status = data.get("status", "")

            if status in ("completed", "failed", "error"):
                outputs = self._get_outputs(run_id)
                cost = self._get_cost(run_id)
                return WorkflowResult(
                    run_id=run_id,
                    status=status,
                    outputs=outputs,
                    cost_usd=cost,
                )

            time.sleep(poll_interval)

        return WorkflowResult(run_id=run_id, status="timed_out")

    def run_workflow(self, question: str) -> WorkflowResult:
        """
        Full round-trip: ask BioMate → confirm workflow → wait for terminal.
        Returns WorkflowResult regardless of outcome.
        """
        chat_resp = self.ask(question)

        if not chat_resp.run_id:
            return WorkflowResult(
                run_id="",
                status="no_workflow_generated",
                error=f"BioMate response did not produce a workflow. Response: {chat_resp.text[:200]}",
            )

        self.confirm_workflow(chat_resp.run_id)
        return self.wait_for_terminal(chat_resp.run_id)

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _get_outputs(self, run_id: str) -> List[Dict[str, Any]]:
        try:
            resp = self._session.get(
                f"{self.base_url}/api/workflows/runs/{run_id}/output_files",
                timeout=30,
            )
            return resp.json().get("files", []) if resp.status_code == 200 else []
        except Exception:
            return []

    def _get_cost(self, run_id: str) -> Optional[float]:
        try:
            resp = self._session.get(
                f"{self.base_url}/api/workflows/runs/{run_id}/cost",
                timeout=30,
            )
            return resp.json().get("total_usd") if resp.status_code == 200 else None
        except Exception:
            return None

    # ------------------------------------------------------------------
    # Credential management (for license-gating benchmark)
    # ------------------------------------------------------------------

    def set_credential(self, tool_id: str, data: dict) -> None:
        """Store a per-tool credential for the authenticated eval user."""
        resp = self._session.post(
            f"{self.base_url}/api/users/credentials",
            json={"tool": tool_id, "data": data},
            timeout=30,
        )
        resp.raise_for_status()

    def clear_credential(self, tool_id: str) -> None:
        """Remove a per-tool credential for the authenticated eval user."""
        resp = self._session.delete(
            f"{self.base_url}/api/users/credentials/{tool_id}",
            timeout=30,
        )
        # 404 is fine — credential was never set
        if resp.status_code not in (200, 204, 404):
            resp.raise_for_status()

    def set_scenario_credentials(self, scenario: str) -> None:
        """
        Set or clear credentials to match one of the 3 license scenarios:
          scenario_a: full licenses (Schrödinger + MOE + AMBER agreement)
          scenario_b: no licenses — clear all
          scenario_c: Schrödinger only
        """
        # Tools to configure per scenario.  Values are the credential dicts
        # accepted by the backend credentials_api endpoint.
        SCENARIO_CREDS = {
            "scenario_a": {
                "schrodinger": {"license_server": "27008@test-license-biomate"},
                "moe":         {"license_server": "27001@test-license-biomate"},
                # alphafold3: provide Docker creds so AF3 routing is unblocked
                "alphafold3":  {"username": "biomate_eval_user", "token": "eval_docker_token"},
                # cryosparc: user must provide — store a test license key
                "cryosparc":   {"license_key": "TEST-CRYO-LICENSE-00000000"},
            },
            "scenario_b": {},  # all cleared below
            "scenario_c": {
                "schrodinger": {"license_server": "27008@test-license-biomate"},
            },
        }
        CLEARABLE = ["schrodinger", "moe", "alphafold3", "cryosparc", "boltz2"]

        for tid in CLEARABLE:
            try:
                self.clear_credential(tid)
            except Exception:
                pass

        for tid, cred_data in SCENARIO_CREDS.get(scenario, {}).items():
            self.set_credential(tid, cred_data)
