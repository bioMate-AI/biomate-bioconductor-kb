"""Paperclip (paperclip.gxl.ai) client: 8M+ biomedical papers (bioRxiv, medRxiv, arXiv, PMC, FDA documents,
ClinicalTrials.gov) exposed as a searchable, greppable filesystem, plus a parallel ``map`` over a result set.

This is the corpus layer behind the Virtual Biotech (Zhang & Zou, Science 2026). It is a HOSTED third-party service:

  * It is enabled only when ``PAPERCLIP_API_KEY`` is set (create one at https://paperclip.gxl.ai/keys).
  * Queries leave BioMate, so it is disabled whenever ``BIOMATE_OFFLINE=1`` or ``TARGET_ID_OFFLINE=1`` (hospital / on-prem mode).
  * Documented limits (2026-11): 120 req/s, 10 concurrent short commands, 8 concurrent long commands (map, verify),
    100 map/verify calls per day. A 429 is reported as ``rate_limited`` and is never retried in a loop.

The transport is MCP over HTTP (JSON-RPC, ``X-API-Key``). No vendor wheel is installed. Tool argument names are read
from the server's ``tools/list`` schema at runtime instead of being hard-coded. Everything fails soft: methods return a
dict with ``status`` in ok / disabled / offline / auth_error / rate_limited / error and never raise.

Python 3.9-safe.
"""
from __future__ import annotations

import json
import logging
import os
import re
import threading
import urllib.error
import urllib.request
from typing import Any, Callable, Dict, List, Optional, Tuple

log = logging.getLogger(__name__)

MCP_URL = os.environ.get("PAPERCLIP_MCP_URL", "https://paperclip.gxl.ai/mcp")
# transport(url, headers, payload, timeout) -> (http_status, parsed_json_or_None). Injectable for tests.
Transport = Callable[[str, Dict[str, str], Dict[str, Any], float], Tuple[int, Any]]


def is_offline() -> bool:
    return os.environ.get("BIOMATE_OFFLINE") == "1" or os.environ.get("TARGET_ID_OFFLINE") == "1"


def api_key() -> str:
    return (os.environ.get("PAPERCLIP_API_KEY") or "").strip()


def is_enabled() -> bool:
    return bool(api_key()) and not is_offline()


def _urllib_transport(url: str, headers: Dict[str, str], payload: Dict[str, Any], timeout: float) -> Tuple[int, Any]:
    req = urllib.request.Request(url, data=json.dumps(payload).encode(), headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, _parse_body(r.read().decode("utf-8", "replace"), r.headers.get("Content-Type", ""))
    except urllib.error.HTTPError as e:
        try:
            return e.code, _parse_body(e.read().decode("utf-8", "replace"), e.headers.get("Content-Type", ""))
        except Exception:
            return e.code, None


def _parse_body(text: str, content_type: str) -> Any:
    """MCP streamable HTTP answers either application/json or an SSE stream whose ``data:`` line is the JSON-RPC reply."""
    if "text/event-stream" in content_type:
        last = None
        for line in text.splitlines():
            if line.startswith("data:"):
                try:
                    last = json.loads(line[5:].strip())
                except ValueError:
                    continue
        return last
    try:
        return json.loads(text)
    except ValueError:
        return None


class PaperclipClient:
    def __init__(self, transport: Optional[Transport] = None, timeout: float = 30.0, key: Optional[str] = None):
        self._transport = transport or _urllib_transport
        self._timeout = timeout
        self._key = key
        self._session: Optional[str] = None
        self._tools: Optional[Dict[str, Dict[str, Any]]] = None
        self._id = 0
        self._lock = threading.Lock()

    # ------------------------------------------------------------------ plumbing
    def _gate(self) -> Optional[Dict[str, Any]]:
        if is_offline():
            return {"status": "offline", "detail": "Paperclip is a hosted service and is disabled in offline / on-prem mode"}
        if not (self._key or api_key()):
            return {"status": "disabled", "detail": "PAPERCLIP_API_KEY is not set (create a key at https://paperclip.gxl.ai/keys)"}
        return None

    def _rpc(self, method: str, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        with self._lock:
            self._id += 1
            rid = self._id
        headers = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream",
                   "X-API-Key": self._key or api_key()}
        if self._session:
            headers["Mcp-Session-Id"] = self._session
        payload = {"jsonrpc": "2.0", "id": rid, "method": method, "params": params or {}}
        try:
            status, body = self._transport(MCP_URL, headers, payload, self._timeout)
        except Exception as exc:
            return {"status": "error", "detail": "%s: %s" % (type(exc).__name__, exc)}
        if status in (401, 403):
            return {"status": "auth_error", "detail": "Paperclip rejected the API key (HTTP %s)" % status}
        if status == 429:
            return {"status": "rate_limited", "detail": "Paperclip rate limit or daily map/verify cap reached (HTTP 429)"}
        if status >= 400 or not isinstance(body, dict):
            return {"status": "error", "detail": "HTTP %s from Paperclip" % status}
        if body.get("error"):
            return {"status": "error", "detail": str(body["error"].get("message") or body["error"])[:300]}
        return {"status": "ok", "result": body.get("result")}

    def _ensure_tools(self) -> Optional[Dict[str, Any]]:
        if self._tools is not None:
            return None
        init = self._rpc("initialize", {"protocolVersion": "2025-03-26", "capabilities": {},
                                        "clientInfo": {"name": "biomate", "version": "1"}})
        if init["status"] != "ok":
            return init
        listed = self._rpc("tools/list")
        if listed["status"] != "ok":
            return listed
        tools = ((listed.get("result") or {}).get("tools")) or []
        self._tools = {t.get("name"): t for t in tools if isinstance(t, dict) and t.get("name")}
        return None

    @staticmethod
    def _map_args(tool: Dict[str, Any], wanted: Dict[str, Any]) -> Dict[str, Any]:
        """Map semantic argument names (query/source/limit/path/question/from_results) onto the tool's real schema."""
        props = ((tool.get("inputSchema") or {}).get("properties")) or {}
        patterns = {
            "query": r"^(query|q|pattern|text)$", "source": r"source", "limit": r"^(n|limit|max_results|top_k)$",
            "path": r"^(path|paper|paper_id|id)$", "question": r"^(question|query|prompt)$",
            "from_results": r"(from|results?_?id)",
        }
        out: Dict[str, Any] = {}
        for key, val in wanted.items():
            if val is None:
                continue
            for name in props:
                if re.search(patterns.get(key, "^%s$" % key), name, re.I) and name not in out:
                    out[name] = val
                    break
        return out

    def call_tool(self, name: str, **semantic_args: Any) -> Dict[str, Any]:
        gate = self._gate()
        if gate:
            return gate
        err = self._ensure_tools()
        if err:
            return err
        tool = (self._tools or {}).get(name)
        if tool is None:
            return {"status": "error", "detail": "Paperclip has no tool %r (available: %s)" % (name, ", ".join(sorted(self._tools or {})) or "none")}
        res = self._rpc("tools/call", {"name": name, "arguments": self._map_args(tool, semantic_args)})
        if res["status"] != "ok":
            return res
        r = res.get("result") or {}
        text = "\n".join(c.get("text", "") for c in (r.get("content") or []) if isinstance(c, dict) and c.get("type") == "text")
        if r.get("isError"):
            return {"status": "error", "detail": text[:300] or "tool reported an error"}
        return {"status": "ok", "text": text, "structured": r.get("structuredContent")}

    # ------------------------------------------------------------------ operations
    def search(self, query: str, source: Optional[str] = None, limit: int = 10) -> Dict[str, Any]:
        return self.call_tool("search", query=query, source=source, limit=limit)

    def grep(self, pattern: str, path: Optional[str] = None) -> Dict[str, Any]:
        return self.call_tool("grep", query=pattern, path=path)

    def read(self, path: str) -> Dict[str, Any]:
        return self.call_tool("cat", path=path)

    def map_results(self, question: str, from_results: str) -> Dict[str, Any]:
        """Paperclip's parallel per-paper reading over an earlier search result id. Capped at 100 calls/day by the service."""
        return self.call_tool("map", question=question, from_results=from_results)


# ---------------------------------------------------------------------- federated-query adapter
def parse_search_text(text: str, limit: int = 5) -> List[Dict[str, Any]]:
    """Best-effort conversion of the CLI-style search text into BioMate literature rows (title, ids, url).
    Rows keep ``paperclip_path`` so the full text can be fetched; unparseable output yields a single raw row."""
    rows: List[Dict[str, Any]] = []
    for line in (text or "").splitlines():
        line = line.strip()
        if not line:
            continue
        m_path = re.search(r"(/papers/[\w.\-/]+)", line)
        m_pmid = re.search(r"\bPMID[:\s]*(\d{5,9})\b", line, re.I)
        m_doi = re.search(r"\b(10\.\d{4,9}/[^\s\"<>]+)", line)
        if not (m_path or m_pmid or m_doi):
            continue
        title = re.sub(r"\s+", " ", re.sub(r"(/papers/\S+|PMID[:\s]*\d+|10\.\d{4,9}/\S+)", "", line)).strip(" -|:\t")
        rows.append({"title": title[:300], "pmid": m_pmid.group(1) if m_pmid else None,
                     "doi": m_doi.group(1).rstrip(".,;") if m_doi else None,
                     "paperclip_path": m_path.group(1) if m_path else None, "source": "paperclip"})
        if len(rows) >= limit:
            break
    if not rows and (text or "").strip():
        rows.append({"title": "", "raw": text.strip()[:1500], "source": "paperclip"})
    return rows


def fetch_for_federation(query: str, client: Optional[PaperclipClient] = None, limit: int = 5) -> Dict[str, Any]:
    """Shape expected by federated_query._FETCHERS: {"source": ..., "results": [...]} (+ status when not ok)."""
    res = (client or PaperclipClient()).search(query, limit=limit)
    if res["status"] != "ok":
        return {"source": "paperclip", "results": [], "status": res["status"], "detail": res.get("detail")}
    return {"source": "paperclip", "results": parse_search_text(res.get("text", ""), limit), "status": "ok"}
