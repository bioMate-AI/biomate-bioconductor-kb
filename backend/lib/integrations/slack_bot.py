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
import time
from typing import Any, Dict, Optional

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
# BioMate API client
# ──────────────────────────────────────────────────────────────────────────────

def _biomate_search(query: str, limit: int = 3) -> Dict[str, Any]:
    headers = {"Authorization": f"Bearer {BIOMATE_API_KEY}"} if BIOMATE_API_KEY else {}
    try:
        r = requests.post(
            f"{BIOMATE_API_URL}/api/workflows/search",
            json={"query": query, "limit": limit},
            headers=headers,
            timeout=15,
        )
        r.raise_for_status()
        return r.json()
    except Exception as exc:
        log.error(f"BioMate search failed: {exc}")
        return {"results": [], "error": str(exc)}


def _biomate_send_message(message: str, user_email: Optional[str] = None) -> Dict[str, Any]:
    """Send a message to the BioMate AI assistant and return the structured response."""
    headers = {"Authorization": f"Bearer {BIOMATE_API_KEY}"} if BIOMATE_API_KEY else {}
    context: Dict[str, Any] = {}
    if user_email:
        context["userEmail"] = user_email
    try:
        r = requests.post(
            f"{BIOMATE_API_URL}/api/workflows/suggest",
            json={"message": message, "context": context},
            headers=headers,
            timeout=20,
        )
        r.raise_for_status()
        return r.json()
    except Exception as exc:
        log.error(f"BioMate suggest failed: {exc}")
        return {"error": str(exc)}


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

    Immediately returns a 200 response with a loading message, then posts
    the real response asynchronously via response_url.

    Returns the immediate HTTP response body (JSON).
    """
    query = form_data.get("text", "").strip()
    user_name = form_data.get("user_name")
    response_url = form_data.get("response_url")

    if not query:
        return {
            "response_type": "ephemeral",
            "text": (
                "Usage: `/biomate <your scientific analysis request>`\n"
                "Examples:\n"
                "• `/biomate run ADMET screening on aspirin, ibuprofen, naproxen`\n"
                "• `/biomate analyze my FASTQ files for WGS variant calling`\n"
                "• `/biomate predict BCR-ABL1 inhibitor binding affinity`"
            ),
        }

    # Immediate acknowledgement (Slack requires response within 3s)
    # The real search runs async and posts via response_url
    if response_url:
        import threading
        def _async_respond():
            try:
                search_result = _biomate_search(query)
                workflows = search_result.get("results", search_result.get("workflows", []))
                blocks = build_response_blocks(query, workflows, user_name)
                post_to_slack(
                    channel="",
                    text=f"BioMate results for: {query}",
                    blocks=blocks,
                    response_url=response_url,
                )
            except Exception as exc:
                log.exception("Async Slack response failed")
                post_to_slack(
                    channel="",
                    text="",
                    blocks=build_error_block(str(exc)),
                    response_url=response_url,
                )
        threading.Thread(target=_async_respond, daemon=True).start()

    return {
        "response_type": "in_channel",
        "text": f"Searching BioMate for: _{query}_ …",
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
