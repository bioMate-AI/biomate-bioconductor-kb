"""Chinese-LLM region policy, Galaxy side (docs/20261112_CN_LLM_REGION_POLICY.md).

The Node frontend classifies every request (UI / Settings language, primary Accept-Language, client
IP in CN / HK / MO / TW) and, on every request it sends to Galaxy, sets

    X-BioMate-LLM-Policy: region=cn; model=<chinese-model-slug>     (a China user)
    X-BioMate-LLM-Policy: region=intl                               (everyone else)

``LlmPolicyMiddleware`` reads that header into a ContextVar for the duration of the request. Every
Galaxy LLM chokepoint (LLMClient.generate_async, the fallback chain, gemini_flash and the modules
that build SDK clients directly) asks :func:`cn_route` first: for a China user the call goes to a
Chinese model through an OpenAI-compatible endpoint, or fails closed with
:class:`ChineseModelUnavailable` (code ``cn_model_unavailable``) — never Gemini / Claude / GPT.

Trust: the header can only RESTRICT a request to Chinese models; it can never lift a restriction,
because "no header" and ``region=intl`` both mean the deployment's ordinary chain. A forged
``region=cn`` therefore only restricts the forger (and spends the deployment's Chinese-model key,
which the same user could equally do through the chat). ``model=`` is honoured only when it is a
Chinese model; anything else becomes the Chinese default. Node also strips any inbound copy of the
header from browser requests before setting its own.

Requests that outlive their HTTP request (threads, after-run findings, the completion poller) carry
the policy explicitly: :func:`run_with_policy` / :func:`wrap_with_policy` copy it into threads, and
runs record ``llm_policy`` at launch so background paths re-enter it with :func:`policy_scope`.
"""
from __future__ import annotations

import contextlib
import contextvars
import logging
import os
import re
from dataclasses import dataclass
from typing import Any, Callable, Dict, Iterator, List, Optional, TypeVar

log = logging.getLogger(__name__)

LLM_POLICY_HEADER = "x-biomate-llm-policy"

# Mirror of CHINESE_MODEL_VENDORS in frontend/server/llm-region-policy.ts (parity-tested).
CHINESE_MODEL_VENDORS = (
    "deepseek", "qwen", "z-ai", "moonshotai", "minimax", "baidu", "tencent", "bytedance",
    "bytedance-seed", "stepfun", "inclusionai", "meituan", "xiaomi", "thudm", "01-ai",
)
# Bare (provider-native, no vendor prefix) Chinese model names, e.g. an on-prem LLM_MODEL.
_CHINESE_BARE_MODEL = re.compile(r"^(qwen|qwq|deepseek|glm|chatglm|kimi|moonshot|ernie|hunyuan|doubao|abab|minimax|step-|yi-)", re.I)

# Mirror of ZH_VISION_DEFAULT_MODEL in frontend/server/response-language.ts.
ZH_DEFAULT_MODEL = "deepseek/deepseek-v4.1-flash"
OPENROUTER_URL = "https://openrouter.ai/api/v1"


def is_chinese_model(model: Any) -> bool:
    m = str(model or "").strip().lower()
    if not m:
        return False
    if "/" in m:
        return m.split("/", 1)[0] in CHINESE_MODEL_VENDORS
    return bool(_CHINESE_BARE_MODEL.match(m))


# Mirror of CN_MODEL_SET.galaxyChain in frontend/server/llm-region-policy.ts (parity-tested): the
# backend chain for China-region requests. The model Node names in the header is tried first, then
# these in order; a failure falls through to the next, and nothing outside the list is ever used.
CN_GALAXY_CHAIN = ("deepseek/deepseek-v4.1-flash", "z-ai/glm-5.2", "qwen/qwen3.5-plus-20260420")
CN_GALAXY_CHAIN_ENV = "BIOMATE_CN_GALAXY_CHAIN"


def zh_default_model() -> str:
    """The response role's model: BIOMATE_CN_RESPONSE_MODEL, else the older OPENROUTER_ZH_DEFAULT_MODEL
    / OPENROUTER_CN_DEFAULT_MODEL alias, else the set's default — a non-Chinese value is ignored."""
    for name in ("BIOMATE_CN_RESPONSE_MODEL", "OPENROUTER_ZH_DEFAULT_MODEL", "OPENROUTER_CN_DEFAULT_MODEL"):
        value = (os.environ.get(name) or "").strip()
        if value and is_chinese_model(value):
            return value
    return ZH_DEFAULT_MODEL


def cn_galaxy_chain(env: Optional[Dict[str, str]] = None) -> List[str]:
    """The backend chain with its env override (comma list); non-Chinese entries are dropped, and an
    override with none left falls back to the default chain."""
    env = os.environ if env is None else env
    override = [m.strip() for m in (env.get(CN_GALAXY_CHAIN_ENV) or "").split(",") if m.strip()]
    chinese = [m for m in override if is_chinese_model(m)]
    if len(chinese) != len(override):
        log.warning("[llm-region] %s has non-Chinese models — ignored: %s", CN_GALAXY_CHAIN_ENV,
                    [m for m in override if not is_chinese_model(m)])
    return chinese or list(CN_GALAXY_CHAIN)


def models_for(route: "CnRoute") -> List[str]:
    """The models a China-region backend call may try, in order: the route's model (the one Node
    named), then the chain. An on-prem route has its one model only."""
    if route.source == "onprem":
        return [route.model]
    out = [route.model]
    for m in cn_galaxy_chain():
        if m not in out:
            out.append(m)
    return out


@dataclass(frozen=True)
class LlmPolicy:
    region: str  # "cn" | "intl"
    model: Optional[str] = None

    @property
    def is_cn(self) -> bool:
        return self.region == "cn"

    def to_dict(self) -> Dict[str, Any]:
        return {"region": self.region, "model": self.model}

    @classmethod
    def from_dict(cls, value: Any) -> Optional["LlmPolicy"]:
        if not isinstance(value, dict) or value.get("region") not in ("cn", "intl"):
            return None
        model = value.get("model")
        return cls(region=value["region"], model=model if isinstance(model, str) else None)


def parse_policy_header(value: Optional[str]) -> Optional[LlmPolicy]:
    """``region=cn; model=deepseek/x`` → LlmPolicy. Unknown or malformed → None (ordinary chain)."""
    if not value:
        return None
    fields: Dict[str, str] = {}
    for part in str(value).split(";"):
        if "=" in part:
            k, v = part.split("=", 1)
            fields[k.strip().lower()] = v.strip()
    region = fields.get("region", "").lower()
    if region not in ("cn", "intl"):
        return None
    model = fields.get("model") or None
    if region == "cn" and model and not is_chinese_model(model):
        model = None  # only a Chinese model may be named; otherwise the Chinese default
    return LlmPolicy(region=region, model=model if region == "cn" else None)


_policy: contextvars.ContextVar[Optional[LlmPolicy]] = contextvars.ContextVar("biomate_llm_policy", default=None)


def current_policy() -> Optional[LlmPolicy]:
    return _policy.get()


@contextlib.contextmanager
def policy_scope(policy: Optional[LlmPolicy]) -> Iterator[None]:
    """Run a block under ``policy`` (a background path re-entering the policy its run was launched with)."""
    token = _policy.set(policy)
    try:
        yield
    finally:
        _policy.reset(token)


T = TypeVar("T")


def wrap_with_policy(fn: Callable[..., T]) -> Callable[..., T]:
    """``fn`` bound to the CURRENT context, for a thread / executor that would otherwise start empty."""
    ctx = contextvars.copy_context()

    def _run(*args: Any, **kwargs: Any) -> T:
        return ctx.run(fn, *args, **kwargs)

    return _run


class ChineseModelUnavailable(RuntimeError):
    code = "cn_model_unavailable"
    status_code = 503

    def __init__(self) -> None:
        super().__init__("Chinese model unavailable — contact the administrator. 国产大模型暂不可用，请联系管理员。")


@dataclass(frozen=True)
class CnRoute:
    url: str
    key: str
    model: str
    source: str


def resolve_cn_route(policy: LlmPolicy, env: Optional[Dict[str, str]] = None) -> Optional[CnRoute]:
    """The deployment's credential for a Chinese model (never the user's own key: Node does not send
    it). Order mirrors Node's resolveCnRoute: OPENROUTER_ZH_API_KEY → OPENROUTER_API_KEY → an on-prem
    OpenAI-compatible LLM_API_URL whose model is Chinese."""
    env = os.environ if env is None else env
    model = policy.model if policy.model and is_chinese_model(policy.model) else zh_default_model()
    if env.get("OPENROUTER_ZH_API_KEY"):
        return CnRoute(OPENROUTER_URL, env["OPENROUTER_ZH_API_KEY"], model, "openrouter_zh_key")
    if env.get("OPENROUTER_API_KEY"):
        return CnRoute(OPENROUTER_URL, env["OPENROUTER_API_KEY"], model, "openrouter_system_key")
    onprem_model = env.get("LLM_MODEL") or env.get("GALAXY_AI_LLM_MODEL") or "qwen-max"
    if env.get("LLM_API_URL") and is_chinese_model(onprem_model):
        key = env.get("LLM_API_KEY") or "none"
        return CnRoute(env["LLM_API_URL"].rstrip("/"), key, onprem_model, "onprem")
    return None


def cn_route() -> Optional[CnRoute]:
    """None for a request outside the region (use the ordinary chain). For a China user: the route,
    or ChineseModelUnavailable when the deployment has no Chinese-model credential (fail closed)."""
    p = _policy.get()
    if p is None or not p.is_cn:
        return None
    route = resolve_cn_route(p)
    if route is None:
        log.warning("[llm-region] China-region request but no Chinese-model credential is configured — refusing the LLM call")
        raise ChineseModelUnavailable()
    return route


def _chat_body(route: CnRoute, messages: List[Dict[str, Any]], max_tokens: int, temperature: float, json_mode: bool) -> Dict[str, Any]:
    body: Dict[str, Any] = {"model": route.model, "messages": messages, "max_tokens": max_tokens, "temperature": temperature}
    if json_mode:
        body["response_format"] = {"type": "json_object"}
    return body


def _headers(route: CnRoute) -> Dict[str, str]:
    h = {"Content-Type": "application/json"}
    if route.key and route.key != "none":
        h["Authorization"] = f"Bearer {route.key}"
    if route.url == OPENROUTER_URL:
        h["HTTP-Referer"] = "https://biomate.ai"
        h["X-Title"] = "BioMate"
    return h


def build_messages(prompt: Any = None, system: Optional[str] = None, messages: Optional[List[Dict[str, Any]]] = None) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    if system:
        out.append({"role": "system", "content": system})
    for m in messages or []:
        role = m.get("role") or "user"
        content = m.get("content", "")
        if not isinstance(content, (str, list)):
            content = str(content)
        out.append({"role": "assistant" if role in ("assistant", "model") else ("system" if role == "system" else "user"), "content": content})
    if prompt is not None and prompt != "":
        out.append({"role": "user", "content": prompt if isinstance(prompt, (str, list)) else str(prompt)})
    return out


def _text(result: Dict[str, Any]) -> str:
    content = result["choices"][0]["message"].get("content")
    if isinstance(content, list):  # some providers return content parts
        content = "".join(p.get("text", "") for p in content if isinstance(p, dict))
    return (content or "").strip()


async def cn_generate(route: CnRoute, prompt: Any = None, *, system: Optional[str] = None,
                      messages: Optional[List[Dict[str, Any]]] = None, max_tokens: int = 1024,
                      temperature: float = 0.0, json_mode: bool = False, timeout: float = 120.0) -> str:
    import httpx  # noqa: PLC0415

    msgs = build_messages(prompt, system, messages)
    last: Optional[Exception] = None
    for model in models_for(route):
        attempt = CnRoute(route.url, route.key, model, route.source)
        try:
            async with httpx.AsyncClient(timeout=timeout) as client:
                response = await client.post(f"{route.url}/chat/completions", headers=_headers(attempt),
                                             json=_chat_body(attempt, msgs, max_tokens, temperature, json_mode))
            if response.status_code != 200:
                raise RuntimeError(f"Chinese model ({model}) error: {response.status_code} {response.text[:300]}")
            return _text(response.json())
        except Exception as exc:  # noqa: BLE001 — fall through to the next Chinese model
            last = exc
            log.warning("[llm-region] %s failed (%s) — trying the next Chinese model", model, str(exc)[:160])
    raise last if last else RuntimeError("no Chinese model to try")


def cn_generate_sync(route: CnRoute, prompt: Any = None, *, system: Optional[str] = None,
                     messages: Optional[List[Dict[str, Any]]] = None, max_tokens: int = 1024,
                     temperature: float = 0.0, json_mode: bool = False, timeout: float = 120.0) -> str:
    import httpx  # noqa: PLC0415

    msgs = build_messages(prompt, system, messages)
    last: Optional[Exception] = None
    for model in models_for(route):
        attempt = CnRoute(route.url, route.key, model, route.source)
        try:
            with httpx.Client(timeout=timeout) as client:
                response = client.post(f"{route.url}/chat/completions", headers=_headers(attempt),
                                       json=_chat_body(attempt, msgs, max_tokens, temperature, json_mode))
            if response.status_code != 200:
                raise RuntimeError(f"Chinese model ({model}) error: {response.status_code} {response.text[:300]}")
            return _text(response.json())
        except Exception as exc:  # noqa: BLE001 — fall through to the next Chinese model
            last = exc
            log.warning("[llm-region] %s failed (%s) — trying the next Chinese model", model, str(exc)[:160])
    raise last if last else RuntimeError("no Chinese model to try")


def image_part(image_b64: str, mime_type: str = "image/png") -> Dict[str, Any]:
    """An OpenAI-format image content part (the Chinese default model reads images)."""
    return {"type": "image_url", "image_url": {"url": f"data:{mime_type};base64,{image_b64}"}}


class LlmPolicyMiddleware:
    """Pure ASGI middleware: the request's X-BioMate-LLM-Policy header → the policy ContextVar for the
    whole request, including its background tasks and the threadpool its sync endpoints run in
    (Starlette copies the context into both). A China request with no Chinese-model credential is
    still served: only its LLM calls fail (cn_model_unavailable)."""

    def __init__(self, app: Any) -> None:
        self.app = app

    async def __call__(self, scope: Dict[str, Any], receive: Any, send: Any) -> None:
        if scope.get("type") != "http":
            await self.app(scope, receive, send)
            return
        raw = None
        for k, v in scope.get("headers") or []:
            if k.decode("latin-1").lower() == LLM_POLICY_HEADER:
                raw = v.decode("latin-1")
                break
        token = _policy.set(parse_policy_header(raw))
        try:
            await self.app(scope, receive, send)
        finally:
            _policy.reset(token)


def cn_complete(prompt: Any = None, *, system: Optional[str] = None, messages: Optional[List[Dict[str, Any]]] = None,
                max_tokens: int = 1024, temperature: float = 0.0, json_mode: bool = False) -> Optional[str]:
    """For a module that builds its own Gemini / Anthropic / OpenAI client: None outside the region
    (carry on with that client), else the Chinese model's answer (or ChineseModelUnavailable)."""
    route = cn_route()
    if route is None:
        return None
    return cn_generate_sync(route, prompt, system=system, messages=messages, max_tokens=max_tokens,
                            temperature=temperature, json_mode=json_mode)


def current_policy_dict() -> Optional[Dict[str, Any]]:
    """The current policy as a run-record field (``llm_policy``), or None outside any request."""
    p = _policy.get()
    return p.to_dict() if p is not None else None


@contextlib.contextmanager
def run_policy_scope(run_record: Optional[Dict[str, Any]]) -> Iterator[None]:
    """Re-enter the policy a run was launched under (its ``llm_policy`` field) for a path that
    handles the run outside that request — the completion poller / orphan finalizer."""
    policy = LlmPolicy.from_dict((run_record or {}).get("llm_policy"))
    if policy is None:
        yield
        return
    with policy_scope(policy):
        yield


_THREAD_PROPAGATION_INSTALLED = False


def install_thread_context_propagation() -> None:
    """Make work handed to another thread inherit the submitting thread's context.

    Python 3.9 starts every new thread — a ``threading.Thread`` or a ``ThreadPoolExecutor`` worker —
    with an EMPTY context, so a request's LLM region policy was lost the moment a handler handed
    work to a thread (research fan-out, the run launch / monitor thread, parallel re-rankers …), and
    any LLM call made there silently used the deployment's Gemini → Claude → GPT chain. That is the
    boundary to fix, once, rather than ~50 call sites:

    - ``ThreadPoolExecutor.submit`` (which ``map`` and ``loop.run_in_executor`` use) runs the work with
      the submitter's policy set;
    - ``threading.Thread.start`` runs ``run`` with the starter's policy set.
    Only the policy is carried, never the rest of the request context (see below).

    Threads started at boot (pollers) copy the boot context, which has no policy — unchanged.
    Idempotent; called from initialize_fast_app.
    """
    global _THREAD_PROPAGATION_INSTALLED
    if _THREAD_PROPAGATION_INSTALLED:
        return
    import concurrent.futures.thread as _cft  # noqa: PLC0415
    import threading  # noqa: PLC0415

    # Only the policy crosses the boundary — never the whole context. Galaxy scopes its SQLAlchemy
    # session by the REQUEST_ID ContextVar (galaxy.model.base.request_scopefunc), so a thread that
    # copied the request's context would share the request's session across threads and keep
    # using it after the request closed it.
    def _with_policy(policy: "LlmPolicy", fn):  # type: ignore[no-untyped-def]
        def _call(*a, **k):  # type: ignore[no-untyped-def]
            token = _policy.set(policy)
            try:
                return fn(*a, **k)
            finally:
                _policy.reset(token)
        return _call

    _orig_submit = _cft.ThreadPoolExecutor.submit

    def submit(self, fn, /, *args, **kwargs):  # type: ignore[no-untyped-def]
        policy = _policy.get()
        if policy is None:
            return _orig_submit(self, fn, *args, **kwargs)
        return _orig_submit(self, _with_policy(policy, fn), *args, **kwargs)

    _cft.ThreadPoolExecutor.submit = submit  # type: ignore[assignment]

    _orig_start = threading.Thread.start

    def start(self):  # type: ignore[no-untyped-def]
        policy = _policy.get()
        if policy is not None:
            self.run = _with_policy(policy, self.run)  # type: ignore[assignment]
        return _orig_start(self)

    threading.Thread.start = start  # type: ignore[assignment]
    _THREAD_PROPAGATION_INSTALLED = True
