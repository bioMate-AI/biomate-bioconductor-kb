"""
Chinese-LLM region policy, Galaxy side (docs/20261112_CN_LLM_REGION_POLICY.md).

A China-region request (X-BioMate-LLM-Policy: region=cn; model=… set by the Node frontend) must run
every Galaxy LLM call on a Chinese model, or fail closed with cn_model_unavailable — never Gemini /
Claude / GPT. These tests cover:

* the header → policy parsing, and that a header can never name a non-Chinese model;
* the ASGI middleware putting the policy in the request context (and nothing without the header);
* fail-closed with no Chinese-model credential;
* the chokepoints: gemini_flash, LLMClient.generate_async / generate (its worker thread), the
  fallback chain;
* work handed to another thread keeping the policy (install_thread_context_propagation);
* a run handled outside its request (orphan finalizer) re-entering the policy recorded at launch;
* the vendor allow-list equal to the Node module's.

The package is loaded WITHOUT running galaxy/ai/__init__.py (it imports SciPy and the full stack),
so this runs anywhere: cd backend && python3.9 lib/galaxy/ai/tests/test_llm_region.py
"""
from __future__ import annotations

import asyncio
import concurrent.futures
import os
import re
import sys
import threading
import types

_HERE = os.path.dirname(os.path.abspath(__file__))
_AI = os.path.abspath(os.path.join(_HERE, ".."))
_LIB = os.path.abspath(os.path.join(_AI, "..", ".."))
_REPO = os.path.abspath(os.path.join(_LIB, "..", ".."))


def _stub_package(name: str, path: str) -> None:
    if name in sys.modules and getattr(sys.modules[name], "__path__", None):
        return
    mod = types.ModuleType(name)
    mod.__path__ = [path]  # type: ignore[attr-defined]
    sys.modules[name] = mod


_stub_package("galaxy", os.path.join(_LIB, "galaxy"))
_stub_package("galaxy.ai", _AI)
_stub_package("galaxy.ai.runs", os.path.join(_AI, "runs"))

import galaxy.ai.llm_region as lr  # noqa: E402

CN_ENV_KEYS = ("OPENROUTER_ZH_API_KEY", "OPENROUTER_API_KEY", "LLM_API_URL", "LLM_MODEL", "GALAXY_AI_LLM_MODEL")


class _Env:
    """Set / clear the Chinese-model credential env vars for one test."""

    def __init__(self, **values: str) -> None:
        self.values = values
        self.saved: dict = {}

    def __enter__(self) -> "_Env":
        for k in CN_ENV_KEYS:
            self.saved[k] = os.environ.pop(k, None)
        os.environ.update(self.values)
        return self

    def __exit__(self, *exc: object) -> None:
        for k in CN_ENV_KEYS:
            os.environ.pop(k, None)
            if self.saved.get(k) is not None:
                os.environ[k] = self.saved[k]


CN = lr.LlmPolicy(region="cn", model="moonshotai/kimi-k3")


# ── header parsing / trust ───────────────────────────────────────────────────────────────────

def test_1_header_parsing_and_no_non_chinese_model():
    p = lr.parse_policy_header("region=cn; model=moonshotai/kimi-k3")
    assert p == lr.LlmPolicy("cn", "moonshotai/kimi-k3"), p
    # A forged header naming a non-Chinese model gets the Chinese default, never that model.
    forged = lr.parse_policy_header("region=cn; model=anthropic/claude-opus-5.5")
    assert forged == lr.LlmPolicy("cn", None), forged
    assert lr.parse_policy_header("region=intl").is_cn is False
    # Junk / absent → no policy (the ordinary chain) — the same as region=intl: a header can only
    # restrict a request, never lift a restriction.
    for junk in (None, "", "region=moon", "model=deepseek/x"):
        assert lr.parse_policy_header(junk) is None, junk


def test_2_middleware_sets_the_policy_for_the_request_only():
    seen: list = []

    async def app(scope, receive, send):
        seen.append(lr.current_policy())

    mw = lr.LlmPolicyMiddleware(app)

    async def run(headers):
        await mw({"type": "http", "headers": headers}, None, None)

    asyncio.run(run([(b"x-biomate-llm-policy", b"region=cn; model=qwen/qwen3-235b-a22b-2507")]))
    asyncio.run(run([(b"content-type", b"application/json")]))
    assert seen[0] == lr.LlmPolicy("cn", "qwen/qwen3-235b-a22b-2507"), seen
    assert seen[1] is None, seen
    assert lr.current_policy() is None  # reset after the request


# ── fail closed / route ──────────────────────────────────────────────────────────────────────

def test_3_fail_closed_without_a_chinese_credential():
    with _Env(), lr.policy_scope(CN):
        try:
            lr.cn_route()
        except lr.ChineseModelUnavailable as exc:
            assert exc.code == "cn_model_unavailable"
        else:
            raise AssertionError("a China-region request with no Chinese-model credential must fail closed")
    # An on-prem model that is not Chinese is not a Chinese route either.
    with _Env(LLM_API_URL="http://llm:8000/v1", LLM_MODEL="llama-3-70b"), lr.policy_scope(CN):
        try:
            lr.cn_route()
            raise AssertionError("a non-Chinese on-prem model must not serve a China-region request")
        except lr.ChineseModelUnavailable:
            pass
    with _Env(OPENROUTER_ZH_API_KEY="k-zh", OPENROUTER_API_KEY="k-sys"), lr.policy_scope(CN):
        r = lr.cn_route()
        assert (r.key, r.model, r.source) == ("k-zh", "moonshotai/kimi-k3", "openrouter_zh_key"), r
    with _Env(OPENROUTER_API_KEY="k-sys"), lr.policy_scope(lr.LlmPolicy("cn", None)):
        r = lr.cn_route()
        assert r.model == lr.ZH_DEFAULT_MODEL and r.source == "openrouter_system_key", r
    # Outside the region: no route, the ordinary chain.
    with _Env(), lr.policy_scope(lr.LlmPolicy("intl")):
        assert lr.cn_route() is None


# ── chokepoints ──────────────────────────────────────────────────────────────────────────────

class _Capture:
    """Replaces the network calls: records which route answered."""

    def __init__(self) -> None:
        self.calls: list = []

    def sync(self, route, prompt=None, **kw):
        self.calls.append(("sync", route.model, prompt, kw.get("system"), kw.get("messages")))
        return "cn-answer"

    async def aio(self, route, prompt=None, **kw):
        self.calls.append(("async", route.model, prompt, kw.get("system")))
        return "cn-answer"


def _patched_lr():
    cap = _Capture()
    lr.cn_generate_sync, lr.cn_generate = cap.sync, cap.aio  # type: ignore[assignment]
    return cap


def test_4_gemini_flash_never_calls_gemini_for_a_china_request():
    import galaxy.ai.gemini_flash as gf

    orig = (lr.cn_generate_sync, lr.cn_generate, gf._get_client)
    cap = _patched_lr()

    def _no_gemini():
        raise AssertionError("Gemini client built for a China-region request")

    gf._get_client = _no_gemini  # type: ignore[assignment]
    try:
        with _Env(OPENROUTER_ZH_API_KEY="k"), lr.policy_scope(CN):
            out = gf.call_gemini_flash(messages=[{"role": "user", "content": "classify"}], system="sys")
            vis = gf.call_gemini_flash_vision(image_b64="aGk=", prompt="read the plot")
        assert out == "cn-answer" and vis == "cn-answer", (out, vis)
        assert cap.calls[0][1] == "moonshotai/kimi-k3" and cap.calls[0][3] == "sys", cap.calls
        # The image reaches the Chinese model as an image part.
        assert cap.calls[1][2][0]["type"] == "image_url", cap.calls[1]
        # Outside the region the Gemini path is used (here: the stub refusing).
        with lr.policy_scope(lr.LlmPolicy("intl")):
            try:
                gf.call_gemini_flash(messages=[{"role": "user", "content": "x"}])
                raise AssertionError("intl request did not reach the Gemini client")
            except AssertionError as exc:
                assert "Gemini client built" in str(exc)
    finally:
        lr.cn_generate_sync, lr.cn_generate, gf._get_client = orig  # type: ignore[assignment]


def test_5_llm_client_and_fallback_chain_route_a_china_request():
    from galaxy.ai import llm_client_fallback_implementation as fb
    from galaxy.ai.llm_client import LLMClient

    orig = (lr.cn_generate_sync, lr.cn_generate)
    cap = _patched_lr()
    try:
        client = LLMClient.__new__(LLMClient)  # no provider setup / keys needed for this path
        client.provider, client.model, client.user_id = "gemini", "gemini-x", ""
        with _Env(OPENROUTER_ZH_API_KEY="k"), lr.policy_scope(CN):
            assert asyncio.run(client.generate_async("hi", system="s")) == "cn-answer"
            # generate() from inside a running loop hands off to a worker thread: the policy must
            # follow it there.
            async def inside_loop():
                return client.generate("again")
            assert asyncio.run(inside_loop()) == "cn-answer"
            assert asyncio.run(fb.generate_with_fallback(client, "chain")) == "cn-answer"
        assert [c[2] for c in cap.calls] == ["hi", "again", "chain"], cap.calls
    finally:
        lr.cn_generate_sync, lr.cn_generate = orig  # type: ignore[assignment]


def test_6_work_handed_to_threads_keeps_the_policy():
    lr.install_thread_context_propagation()
    with lr.policy_scope(CN):
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as ex:
            via_submit = ex.submit(lr.current_policy).result()
            via_map = list(ex.map(lambda _: lr.current_policy(), [1]))[0]
        box: list = []
        t = threading.Thread(target=lambda: box.append(lr.current_policy()))
        t.start(); t.join()

        async def via_executor():
            return await asyncio.get_running_loop().run_in_executor(None, lr.current_policy)
        via_loop = asyncio.run(via_executor())
    assert via_submit == CN and via_map == CN and box == [CN] and via_loop == CN, (via_submit, via_map, box, via_loop)
    # A thread started outside any request has no policy.
    box2: list = []
    t2 = threading.Thread(target=lambda: box2.append(lr.current_policy()))
    t2.start(); t2.join()
    assert box2 == [None], box2


def test_7_background_run_reenters_the_policy_it_was_launched_with():
    with lr.policy_scope(CN):
        record = {"run_id": "r1", "llm_policy": lr.current_policy_dict()}
    assert record["llm_policy"] == {"region": "cn", "model": "moonshotai/kimi-k3"}, record

    from galaxy.ai.runs import orphan_finalizer as of

    seen: list = []
    orig = of._finalize_orphaned_run_impl
    of._finalize_orphaned_run_impl = lambda store, run_id, rec: seen.append(lr.current_policy())  # type: ignore[assignment]
    try:
        of.finalize_orphaned_run(None, "r1", record)            # poller thread: no request context
        of.finalize_orphaned_run(None, "r2", {"run_id": "r2"})  # a run launched before this change
    finally:
        of._finalize_orphaned_run_impl = orig  # type: ignore[assignment]
    assert seen == [CN, None], seen
    assert lr.current_policy() is None


def test_8_vendor_allow_list_equals_the_node_module():
    ts = open(os.path.join(_REPO, "frontend", "server", "llm-region-policy.ts")).read()
    block = re.search(r"CHINESE_MODEL_VENDORS = \[(.*?)\]", ts, re.S).group(1)
    node = tuple(re.findall(r"'([^']+)'", block))
    assert node == lr.CHINESE_MODEL_VENDORS, (node, lr.CHINESE_MODEL_VENDORS)
    rl = open(os.path.join(_REPO, "frontend", "server", "response-language.ts")).read()
    assert f"ZH_VISION_DEFAULT_MODEL = '{lr.ZH_DEFAULT_MODEL}'" in rl


def main():
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    failed = 0
    for t in tests:
        try:
            t()
            print(f"PASS {t.__name__}")
        except Exception as exc:  # noqa: BLE001
            failed += 1
            print(f"FAIL {t.__name__}: {type(exc).__name__}: {str(exc)[:300]}")
    print(f"\n{len(tests) - failed}/{len(tests)} llm-region tests passed.")
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
