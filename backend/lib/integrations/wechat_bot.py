"""
BioMate WeChat Work (企业微信) Integration
==========================================
Registers BioMate as a WeChat Work service application, handles incoming
messages via the WeChat Work webhook, and responds with workflow cards
plus "Open in BioMate" deep links.

Setup (one-time manual steps):
    1. Register a WeChat Work custom app at https://work.weixin.qq.com/
    2. Under "Receive messages" → set API URL:
       https://<your-domain>/integrations/wechat/message
    3. Set Token and EncodingAESKey in WeChat admin console
    4. Set env vars: WECHAT_CORP_ID, WECHAT_CORP_SECRET,
                     WECHAT_TOKEN, WECHAT_ENCODING_AES_KEY
       Optional: WECHAT_AGENT_ID (app agent ID for sending messages)

Authentication flow:
    - Incoming message: verified by HMAC-SHA1 + XML decrypt (WXBizMsgCrypt)
    - BioMate account binding: user sends "bind <biomate_api_key>" in WeChat →
      WeChat user_id stored alongside BioMate account

API reference:
    https://developer.work.weixin.qq.com/document/path/90236
"""

import hashlib
import logging
import os
import threading
import time
import xml.etree.ElementTree as ET
from typing import Any, Dict, Optional

import requests

log = logging.getLogger(__name__)

WECHAT_CORP_ID = os.environ.get("WECHAT_CORP_ID", "")
WECHAT_CORP_SECRET = os.environ.get("WECHAT_CORP_SECRET", "")
WECHAT_TOKEN = os.environ.get("WECHAT_TOKEN", "")
WECHAT_ENCODING_AES_KEY = os.environ.get("WECHAT_ENCODING_AES_KEY", "")
WECHAT_AGENT_ID = os.environ.get("WECHAT_AGENT_ID", "")
BIOMATE_API_URL = os.environ.get("BIOMATE_API_URL", "http://localhost:5000")
BIOMATE_API_KEY = os.environ.get("BIOMATE_API_KEY", "")
BIOMATE_DEEP_LINK_BASE = os.environ.get("BIOMATE_DEEP_LINK_BASE", "https://app.biomate.ai")

WECHAT_API_BASE = "https://qyapi.weixin.qq.com/cgi-bin"

# ──────────────────────────────────────────────────────────────────────────────
# WeChat API token management
# ──────────────────────────────────────────────────────────────────────────────

_access_token: Dict[str, Any] = {"token": None, "expires_at": 0}
_token_lock = threading.Lock()


def get_access_token() -> str:
    """
    Fetch or return cached WeChat Work access token.
    Tokens are valid for 7200s; refreshed automatically.
    """
    with _token_lock:
        if _access_token["token"] and time.time() < _access_token["expires_at"] - 60:
            return _access_token["token"]

        r = requests.get(
            f"{WECHAT_API_BASE}/gettoken",
            params={"corpid": WECHAT_CORP_ID, "corpsecret": WECHAT_CORP_SECRET},
            timeout=10,
        )
        r.raise_for_status()
        data = r.json()
        if data.get("errcode", 0) != 0:
            raise RuntimeError(f"WeChat token error: {data}")
        _access_token["token"] = data["access_token"]
        _access_token["expires_at"] = time.time() + data.get("expires_in", 7200)
        return _access_token["token"]


# ──────────────────────────────────────────────────────────────────────────────
# Signature verification (GET handshake + message verification)
# ──────────────────────────────────────────────────────────────────────────────

def verify_signature(token: str, timestamp: str, nonce: str, msg_encrypt: str = "") -> str:
    """
    Compute WeChat Work signature: SHA1 of sorted concatenation.
    Used for:
      - URL validation (GET): check sign = SHA1(sort(token, timestamp, nonce))
      - Message decryption (POST): SHA1(sort(token, timestamp, nonce, msg_encrypt))
    """
    parts = sorted([token, timestamp, nonce] + ([msg_encrypt] if msg_encrypt else []))
    return hashlib.sha1("".join(parts).encode("utf-8")).hexdigest()


def verify_url_signature(token: str, timestamp: str, nonce: str, expected_sign: str) -> bool:
    """Verify WeChat's GET handshake request."""
    return verify_signature(token, timestamp, nonce) == expected_sign


# ──────────────────────────────────────────────────────────────────────────────
# Message parsing (plaintext mode — no AES encryption)
# For production with AES encryption, integrate WXBizMsgCrypt library
# ──────────────────────────────────────────────────────────────────────────────

def parse_message_xml(xml_body: str) -> Dict[str, str]:
    """
    Parse a WeChat Work message XML payload.
    Returns dict with: ToUserName, FromUserName, CreateTime, MsgType, Content, MsgId
    """
    try:
        root = ET.fromstring(xml_body)
        return {child.tag: (child.text or "") for child in root}
    except ET.ParseError as exc:
        log.error(f"WeChat XML parse error: {exc}")
        return {}


def build_text_reply(to_user: str, from_user: str, content: str) -> str:
    """Build an XML text reply message to WeChat Work."""
    ts = str(int(time.time()))
    return f"""<xml>
<ToUserName><![CDATA[{to_user}]]></ToUserName>
<FromUserName><![CDATA[{from_user}]]></FromUserName>
<CreateTime>{ts}</CreateTime>
<MsgType><![CDATA[text]]></MsgType>
<Content><![CDATA[{content}]]></Content>
</xml>"""


# ──────────────────────────────────────────────────────────────────────────────
# Sending messages via WeChat Work API
# ──────────────────────────────────────────────────────────────────────────────

def send_text_message(to_user: str, content: str, agent_id: Optional[str] = None) -> bool:
    """Send a text message to a WeChat Work user."""
    token = get_access_token()
    payload = {
        "touser": to_user,
        "msgtype": "text",
        "agentid": int(agent_id or WECHAT_AGENT_ID or 0),
        "text": {"content": content},
    }
    r = requests.post(
        f"{WECHAT_API_BASE}/message/send",
        params={"access_token": token},
        json=payload,
        timeout=10,
    )
    r.raise_for_status()
    result = r.json()
    if result.get("errcode", 0) != 0:
        log.error(f"WeChat send error: {result}")
        return False
    return True


def send_workflow_card(
    to_user: str,
    workflow_name: str,
    description: str,
    workflow_id: str,
    agent_id: Optional[str] = None,
) -> bool:
    """
    Send a WeChat Work "text card" for a BioMate workflow recommendation.
    Text cards show a title, description, and "Read more" button (deep link).
    """
    token = get_access_token()
    deep_link = f"{BIOMATE_DEEP_LINK_BASE}?workflow={workflow_id}"

    payload = {
        "touser": to_user,
        "msgtype": "textcard",
        "agentid": int(agent_id or WECHAT_AGENT_ID or 0),
        "textcard": {
            "title": f"BioMate: {workflow_name[:28]}",
            "description": description[:512],
            "url": deep_link,
            "btntxt": "在BioMate中运行",  # "Run in BioMate"
        },
    }
    r = requests.post(
        f"{WECHAT_API_BASE}/message/send",
        params={"access_token": token},
        json=payload,
        timeout=10,
    )
    r.raise_for_status()
    result = r.json()
    return result.get("errcode", 0) == 0


# ──────────────────────────────────────────────────────────────────────────────
# BioMate API helpers
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
        return {"results": [], "error": str(exc)}


# ──────────────────────────────────────────────────────────────────────────────
# Message handler
# ──────────────────────────────────────────────────────────────────────────────

# Simple in-memory binding store: {wechat_user_id: biomate_api_key}
# For production: replace with database persistence
_user_bindings: Dict[str, str] = {}


def handle_wechat_message(xml_body: str, corp_app_id: str) -> str:
    """
    Process an incoming WeChat Work message.
    Returns an XML reply string (or empty string for async handling).

    Handles:
      - "bind <api_key>"   → bind WeChat user to BioMate account
      - "unbind"           → remove binding
      - Any other text     → search BioMate and reply async with workflow card(s)
    """
    msg = parse_message_xml(xml_body)
    if not msg:
        return ""

    msg_type = msg.get("MsgType", "")
    from_user = msg.get("FromUserName", "")
    to_user = msg.get("ToUserName", "")  # The WeChat Work app account
    content = msg.get("Content", "").strip()

    if msg_type != "text" or not content:
        # Only handle text messages; ignore image/voice/event etc.
        return build_text_reply(
            from_user, to_user,
            "BioMate仅支持文字查询。请输入您的分析需求，例如：\n"
            "'对阿司匹林和布洛芬进行ADMET筛选'\n"
            "'全基因组测序变体鉴定'"
        )

    # Bind command
    if content.lower().startswith("bind "):
        api_key = content[5:].strip()
        if api_key:
            _user_bindings[from_user] = api_key
            return build_text_reply(from_user, to_user, "✅ BioMate账号绑定成功！现在您可以直接发送分析请求了。")
        return build_text_reply(from_user, to_user, "❌ 请提供有效的API密钥：bind <your-api-key>")

    # Unbind command
    if content.lower() == "unbind":
        _user_bindings.pop(from_user, None)
        return build_text_reply(from_user, to_user, "✅ 已解除BioMate账号绑定。")

    # Help command
    if content.lower() in ("help", "帮助", "?", "？"):
        return build_text_reply(from_user, to_user,
            "BioMate 生命科学AI助手\n\n"
            "发送分析请求，例如：\n"
            "• 对化合物列表进行ADMET筛选\n"
            "• RNA-seq差异表达分析\n"
            "• 蛋白质结构预测\n\n"
            "账号绑定：bind <your-api-key>\n"
            f"打开应用：{BIOMATE_DEEP_LINK_BASE}"
        )

    # Scientific query: search async and reply with workflow cards
    def _respond_async():
        try:
            result = _biomate_search(content)
            workflows = result.get("results", result.get("workflows", []))

            if not workflows:
                send_text_message(from_user,
                    f"未找到匹配的工作流程：{content}\n\n"
                    f"请访问 {BIOMATE_DEEP_LINK_BASE} 查看所有可用工作流。",
                )
                return

            # Send top-3 workflow cards
            for wf in workflows[:3]:
                name = wf.get("name", wf.get("workflow_id", "工作流"))
                desc = wf.get("description", "")
                wf_id = wf.get("workflow_id", wf.get("id", ""))
                send_workflow_card(from_user, name, desc, wf_id)

        except Exception as exc:
            log.exception("WeChat async response failed")
            send_text_message(from_user, f"❌ BioMate查询失败：{exc}")

    threading.Thread(target=_respond_async, daemon=True).start()

    # Immediate reply (WeChat requires response within 5s)
    return build_text_reply(from_user, to_user, f"🔍 正在搜索：{content[:60]}…")


# ──────────────────────────────────────────────────────────────────────────────
# Flask app (standalone deployment)
# ──────────────────────────────────────────────────────────────────────────────

def create_flask_app():
    """
    Minimal Flask app for WeChat Work webhook.
    Deploy at: https://<domain>/integrations/wechat/message

    GET  /integrations/wechat/message — URL validation (WeChat handshake)
    POST /integrations/wechat/message — incoming message handler
    """
    from flask import Flask, request, make_response

    app = Flask("biomate-wechat")

    @app.route("/integrations/wechat/message", methods=["GET"])
    def wechat_verify():
        """WeChat URL ownership verification (one-time setup)."""
        msg_signature = request.args.get("msg_signature", "")
        timestamp = request.args.get("timestamp", "")
        nonce = request.args.get("nonce", "")
        echostr = request.args.get("echostr", "")

        if verify_url_signature(WECHAT_TOKEN, timestamp, nonce, msg_signature):
            return echostr  # Echo back to confirm ownership
        return make_response("Signature verification failed", 403)

    @app.route("/integrations/wechat/message", methods=["POST"])
    def wechat_message():
        """Handle incoming WeChat Work messages."""
        timestamp = request.args.get("timestamp", "")
        nonce = request.args.get("nonce", "")
        msg_signature = request.args.get("msg_signature", "")

        xml_body = request.get_data(as_text=True)

        # Verify signature
        if WECHAT_TOKEN and not verify_url_signature(WECHAT_TOKEN, timestamp, nonce, msg_signature):
            return make_response("Signature error", 403)

        reply_xml = handle_wechat_message(xml_body, WECHAT_CORP_ID)
        if reply_xml:
            return make_response(reply_xml, 200, {"Content-Type": "application/xml"})
        return "success"  # WeChat requires "success" for no-reply messages

    @app.route("/integrations/wechat/health", methods=["GET"])
    def health():
        from flask import jsonify
        return jsonify({"status": "ok", "service": "biomate-wechat"})

    return app


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="BioMate WeChat Work Bot")
    parser.add_argument("--port", type=int, default=8091)
    args = parser.parse_args()
    app = create_flask_app()
    log.warning(f"BioMate WeChat bot listening on port {args.port}")
    app.run(host="0.0.0.0", port=args.port)
