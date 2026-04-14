"""
BioMate Slack Integration
=========================
Exposes BioMate's scientific AI as a Slack slash command and event handler.

Slash command: /biomate <natural language query>
Returns a Slack Block Kit message with a workflow card and a "Run in BioMate" button.

Setup (one-time):
    1. Create a Slack app at https://api.slack.com/apps
    2. Add slash command /biomate → POST https://<your-domain>/integrations/slack/command
    3. Add Bot Token Scopes: commands, chat:write, users:read
    4. Set SLACK_BOT_TOKEN and SLACK_SIGNING_SECRET env vars
    5. Run the Flask/FastAPI sub-service (see __main__ at bottom)

Environment variables:
    SLACK_BOT_TOKEN       Bot OAuth token (xoxb-...)
    SLACK_SIGNING_SECRET  Used to verify Slack request signatures
    BIOMATE_API_URL       BioMate API base URL (default: http://localhost:5000)
    BIOMATE_API_KEY       Service account API key for BioMate
"""

import hashlib
import hmac
import json
import logging
import os
import threading
import time
from collections import deque
from typing import Any, Deque, Dict, List, Optional, Tuple

import requests

log = logging.getLogger(__name__)

SLACK_BOT_TOKEN = os.environ.get("SLACK_BOT_TOKEN", "")
SLACK_SIGNING_SECRET = os.environ.get("SLACK_SIGNING_SECRET", "")
BIOMATE_API_URL = os.environ.get("BIOMATE_API_URL", "http://localhost:5000")
BIOMATE_API_KEY = os.environ.get("BIOMATE_API_KEY", "")

BIOMATE_DEEP_LINK_BASE = os.environ.get("BIOMATE_DEEP_LINK_BASE", "https://app.biomate.ai")


# ──────────────────────────────────────────────────────────────────────────────
# Slack signature verification
# ──────────────────────────────────────────────────────────────────────────────

def verify_slack_signature(
    signing_secret: str,
    request_body: bytes,
    timestamp: str,
    signature: str,
    max_age_seconds: int = 300,
) -> bool:
    """
    Verify that a Slack request is authentic by checking the HMAC-SHA256 signature.
    Rejects requests older than max_age_seconds to prevent replay attacks.
    """
    try:
        ts = int(timestamp)
    except (ValueError, TypeError):
        return False

    if abs(time.time() - ts) > max_age_seconds:
        log.warning(f"Slack request too old: ts={timestamp}")
        return False

    base_string = f"v0:{timestamp}:{request_body.decode('utf-8')}"
    expected = "v0=" + hmac.new(
        signing_secret.encode(),
        base_string.encode(),
        hashlib.sha256,
    ).hexdigest()

    return hmac.compare_digest(expected, signature or "")


# ──────────────────────────────────────────────────────────────────────────────
# Open Claw engine — routes Slack queries through /api/open-claw/stream
# Upgraded to full agentic loop (same pattern as WeChat bot).
# ──────────────────────────────────────────────────────────────────────────────

_MAX_HISTORY = 10
_conversation_history: Dict[str, Deque[Dict[str, str]]] = {}
_history_lock = threading.Lock()


def _get_history(user_id: str) -> List[Dict[str, str]]:
    with _history_lock:
        return list(_conversation_history.get(user_id, deque()))


def _push_history(user_id: str, role: str, content: str) -> None:
    with _history_lock:
        if user_id not in _conversation_history:
            _conversation_history[user_id] = deque(maxlen=_MAX_HISTORY)
        _conversation_history[user_id].append({"role": role, "content": content})


def _open_claw_query(
    user_id: str,
    query: str,
    api_key: Optional[str] = None,
    timeout: int = 55,
    _base_url_override: Optional[str] = None,
) -> Tuple[str, Optional[str]]:
    """
    Send a query through the BioMate Open Claw engine (/api/open-claw/stream).
    Returns (reply_text, workflow_id_or_None).
    Accumulates text_delta events; captures first workflow_id from tool_result.
    """
    history = _get_history(user_id)
    messages = history + [{"role": "user", "content": query}]

    headers: Dict[str, str] = {"Content-Type": "application/json", "Accept": "text/event-stream"}
    effective_key = api_key or BIOMATE_API_KEY
    if effective_key:
        headers["Authorization"] = f"Bearer {effective_key}"

    text_parts: List[str] = []
    workflow_id: Optional[str] = None

    base_url = _base_url_override or BIOMATE_API_URL
    try:
        with requests.post(
            f"{base_url}/api/open-claw/stream",
            json={"messages": messages},
            headers=headers,
            stream=True,
            timeout=timeout,
        ) as resp:
            if resp.status_code == 503:
                return ":x: BioMate Open Claw engine unavailable (API key not configured).", None
            if resp.status_code == 400:
                return ":x: Bad request format — please try again.", None
            if resp.status_code != 200:
                return f":x: BioMate returned error {resp.status_code}.", None

            current_event = "message"
            for raw_line in resp.iter_lines(decode_unicode=True):
                if not raw_line:
                    continue
                if raw_line.startswith("event:"):
                    current_event = raw_line[6:].strip()
                elif raw_line.startswith("data:"):
                    data_str = raw_line[5:].strip()
                    try:
                        data = json.loads(data_str)
                    except json.JSONDecodeError:
                        continue

                    evt = current_event or (data.get("type") if isinstance(data, dict) else "")

                    if evt in ("text_delta", "delta") or (
                        isinstance(data, dict) and data.get("type") in ("text_delta", "delta")
                    ):
                        text_parts.append(data.get("text", ""))

                    if evt == "tool_result" and isinstance(data, dict):
                        result_content = data.get("result", data.get("content", ""))
                        if isinstance(result_content, (dict, list)):
                            result_content = json.dumps(result_content)
                        try:
                            parsed = json.loads(result_content) if isinstance(result_content, str) else result_content
                            results = parsed.get("results", parsed.get("workflows", []))
                            if results and not workflow_id:
                                workflow_id = results[0].get("workflow_id", results[0].get("id"))
                        except (json.JSONDecodeError, AttributeError):
                            pass

                    if evt in ("done", "complete") or (
                        isinstance(data, dict) and data.get("type") in ("done", "complete")
                    ):
                        break

                    current_event = "message"

    except requests.exceptions.Timeout:
        return ":hourglass: BioMate response timed out. Please try again.", None
    except Exception as exc:
        log.exception(f"Open Claw query failed for Slack user {user_id}: {exc}")
        return f":x: BioMate query failed: {exc}", None

    reply_text = "".join(text_parts).strip()
    if not reply_text:
        reply_text = "BioMate is processing your request. Check the app for full results."

    _push_history(user_id, "user", query)
    _push_history(user_id, "assistant", reply_text)

    return reply_text, workflow_id


# ──────────────────────────────────────────────────────────────────────────────
# Slack Block Kit message builders
# ──────────────────────────────────────────────────────────────────────────────

def build_workflow_card(
    workflow_name: str,
    description: str,
    workflow_id: str,
    required_inputs: Optional[list] = None,
    estimated_time: Optional[str] = None,
    confidence: float = 0.0,
) -> Dict[str, Any]:
    """
    Build a Slack Block Kit section for a single workflow recommendation.
    """
    inputs_text = ""
    if required_inputs:
        inputs_text = f"\n*Required inputs:* {', '.join(required_inputs[:3])}"
        if len(required_inputs) > 3:
            inputs_text += f" +{len(required_inputs) - 3} more"

    time_text = f"\n*Est. time:* {estimated_time}" if estimated_time else ""
    confidence_text = f"  ·  {int(confidence * 100)}% match" if confidence > 0 else ""

    deep_link = f"{BIOMATE_DEEP_LINK_BASE}?workflow={workflow_id}"

    return {
        "type": "section",
        "text": {
            "type": "mrkdwn",
            "text": (
                f"*{workflow_name}*{confidence_text}\n"
                f"{description[:180]}{'…' if len(description) > 180 else ''}"
                f"{inputs_text}{time_text}"
            ),
        },
        "accessory": {
            "type": "button",
            "text": {"type": "plain_text", "text": "Run in BioMate", "emoji": False},
            "url": deep_link,
            "action_id": f"open_biomate_{workflow_id}",
        },
    }


def build_response_blocks(
    query: str,
    workflows: list,
    user_name: Optional[str] = None,
) -> list:
    """
    Build the full Slack Block Kit payload for a /biomate command response.
    """
    intro = f"<@{user_name}> Here's what I found for: *{query}*" if user_name else f"Results for: *{query}*"

    blocks = [
        {"type": "section", "text": {"type": "mrkdwn", "text": intro}},
        {"type": "divider"},
    ]

    if not workflows:
        blocks.append({
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": (
                    "No matching workflows found. Try a more specific query, "
                    "or <" + BIOMATE_DEEP_LINK_BASE + "|open BioMate> to explore all workflows."
                ),
            },
        })
        return blocks

    for wf in workflows[:3]:
        blocks.append(build_workflow_card(
            workflow_name=wf.get("name", wf.get("workflow_id", "Workflow")),
            description=wf.get("description", ""),
            workflow_id=wf.get("workflow_id", wf.get("id", "")),
            required_inputs=wf.get("required_params", wf.get("required_inputs", [])),
            estimated_time=wf.get("estimated_time"),
            confidence=float(wf.get("score", wf.get("confidence", 0))),
        ))

    blocks.append({"type": "divider"})
    blocks.append({
        "type": "context",
        "elements": [
            {
                "type": "mrkdwn",
                "text": (
                    f"<{BIOMATE_DEEP_LINK_BASE}|Open BioMate> for full AI conversation, "
                    "parameter editing, and real-time workflow execution."
                ),
            }
        ],
    })

    return blocks


def build_error_block(message: str) -> list:
    return [
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f":warning: BioMate error: {message}",
            },
        }
    ]


# ──────────────────────────────────────────────────────────────────────────────
# Slack API client
# ──────────────────────────────────────────────────────────────────────────────

def post_to_slack(
    channel: str,
    text: str,
    blocks: Optional[list] = None,
    response_url: Optional[str] = None,
) -> None:
    """
    Post a message to a Slack channel, or respond to a slash command via response_url.
    Prefers response_url (ephemeral, immediate) over channel post.
    """
    payload: Dict[str, Any] = {"text": text}
    if blocks:
        payload["blocks"] = blocks

    if response_url:
        payload["response_type"] = "in_channel"
        try:
            r = requests.post(response_url, json=payload, timeout=10)
            r.raise_for_status()
        except Exception as exc:
            log.error(f"Slack response_url post failed: {exc}")
        return

    if not SLACK_BOT_TOKEN:
        log.warning("SLACK_BOT_TOKEN not set — cannot post to channel")
        return

    payload["channel"] = channel
    try:
        r = requests.post(
            "https://slack.com/api/chat.postMessage",
            json=payload,
            headers={"Authorization": f"Bearer {SLACK_BOT_TOKEN}"},
            timeout=10,
        )
        r.raise_for_status()
        resp_json = r.json()
        if not resp_json.get("ok"):
            log.error(f"Slack API error: {resp_json.get('error')}")
    except Exception as exc:
        log.error(f"Slack channel post failed: {exc}")


# ──────────────────────────────────────────────────────────────────────────────
# Slash command handler (framework-agnostic)
# ──────────────────────────────────────────────────────────────────────────────

def handle_slash_command(form_data: Dict[str, str]) -> Dict[str, Any]:
    """
    Process a /biomate slash command payload (URL-decoded form fields).

    Routes through the full Open Claw agentic loop — Claude with BioMate tools —
    giving the same multi-step search+execute capability as the web UI and WeChat.

    Immediately returns a 200 acknowledgement (Slack requires response within 3s),
    then posts the real Open Claw response asynchronously via response_url.
    """
    query = form_data.get("text", "").strip()
    user_id = form_data.get("user_id", form_data.get("user_name", "unknown"))
    user_name = form_data.get("user_name")
    response_url = form_data.get("response_url")

    if not query or query in ("help", "--help"):
        return {
            "response_type": "ephemeral",
            "text": (
                "*BioMate Scientific AI* — powered by Open Claw (Claude + BioMate tools)\n\n"
                "Usage: `/biomate <your scientific analysis request>`\n\n"
                "*Examples:*\n"
                "• `/biomate run ADMET screening on aspirin, ibuprofen, naproxen`\n"
                "• `/biomate RNA-seq differential expression on my tumor vs normal samples`\n"
                "• `/biomate predict protein structure from this sequence: MSEQNN...`\n"
                "• `/biomate check status of run abc-123`\n"
                "• `/biomate what GWAS variants are associated with type 2 diabetes?`\n\n"
                "Supports multi-turn conversation — follow-up questions remember context.\n"
                f"<{BIOMATE_DEEP_LINK_BASE}|Open BioMate> for the full web UI."
            ),
        }

    if query.lower() in ("clear", "reset", "new session"):
        with _history_lock:
            _conversation_history.pop(user_id, None)
        return {"response_type": "ephemeral", "text": ":white_check_mark: Conversation history cleared."}

    # Immediate acknowledgement (Slack requires response within 3s)
    # Real Open Claw response sent async via response_url
    if response_url:
        def _async_respond():
            try:
                reply_text, workflow_id = _open_claw_query(user_id, query)

                # Slack message limit: 3000 chars per block
                if len(reply_text) > 2800:
                    reply_text = reply_text[:2800] + f"\n\n<{BIOMATE_DEEP_LINK_BASE}|View full results in BioMate>"

                blocks: list = [
                    {"type": "section", "text": {"type": "mrkdwn", "text": f"<@{user_name}> {reply_text}" if user_name else reply_text}},
                ]

                if workflow_id:
                    blocks.append({"type": "divider"})
                    blocks.append({
                        "type": "actions",
                        "elements": [{
                            "type": "button",
                            "text": {"type": "plain_text", "text": "Run in BioMate", "emoji": False},
                            "url": f"{BIOMATE_DEEP_LINK_BASE}?workflow={workflow_id}",
                            "style": "primary",
                        }],
                    })

                blocks.append({
                    "type": "context",
                    "elements": [{"type": "mrkdwn", "text": f"<{BIOMATE_DEEP_LINK_BASE}|Open BioMate> · Reply with follow-up questions"}],
                })

                post_to_slack(channel="", text=reply_text[:200], blocks=blocks, response_url=response_url)

            except Exception as exc:
                log.exception("Async Slack Open Claw response failed")
                post_to_slack(channel="", text="", blocks=build_error_block(str(exc)), response_url=response_url)

        threading.Thread(target=_async_respond, daemon=True).start()

    return {
        "response_type": "in_channel",
        "text": f":brain: BioMate is analyzing: _{query}_ …",
    }


# ──────────────────────────────────────────────────────────────────────────────
# Flask app (standalone deployment)
# ──────────────────────────────────────────────────────────────────────────────

def create_flask_app():
    """
    Create a minimal Flask app that handles Slack slash commands.
    Deploy separately from the main BioMate server.

    Recommended: run with gunicorn behind nginx/Cloudflare
        gunicorn 'backend.lib.integrations.slack_bot:create_flask_app()' -w 2 -b 0.0.0.0:8090
    """
    from flask import Flask, request, jsonify, abort

    app = Flask("biomate-slack")

    @app.route("/integrations/slack/command", methods=["POST"])
    def slack_command():
        # Verify Slack signature
        body = request.get_data()
        timestamp = request.headers.get("X-Slack-Request-Timestamp", "")
        signature = request.headers.get("X-Slack-Signature", "")

        if SLACK_SIGNING_SECRET and not verify_slack_signature(
            SLACK_SIGNING_SECRET, body, timestamp, signature
        ):
            abort(403, "Invalid Slack signature")

        form_data = {k: v for k, v in request.form.items()}
        response = handle_slash_command(form_data)
        return jsonify(response)

    @app.route("/integrations/slack/health", methods=["GET"])
    def health():
        return jsonify({"status": "ok", "service": "biomate-slack"})

    return app


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="BioMate Slack Bot")
    parser.add_argument("--port", type=int, default=8090)
    args = parser.parse_args()

    app = create_flask_app()
    log.warning(f"BioMate Slack bot listening on port {args.port}")
    app.run(host="0.0.0.0", port=args.port)
