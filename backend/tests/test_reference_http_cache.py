"""Unit test for the in-process TTL cache on AIAssistant._http_get_json (speedup 1-C).

Verifies that near-static external reference lookups are cached: repeat calls hit
the cache (no network), distinct URLs miss, TTL expiry re-fetches, and failed
responses are NOT cached (so transient errors retry). No network required.

Run:  cd backend && PYTHONPATH=lib python3.9 tests/test_reference_http_cache.py
"""
import json
import os
import sys
import types
import urllib.request

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))
from galaxy.ai.ai_assistant import AIAssistant  # noqa: E402

_http_get_json = AIAssistant._http_get_json
calls = {"n": 0}
raise_urls = set()


class _FakeResp:
    def __init__(self, payload):
        self._b = json.dumps(payload).encode()
    def read(self):
        return self._b
    def __enter__(self):
        return self
    def __exit__(self, *a):
        return False


def _fake_urlopen(req, timeout=None):
    calls["n"] += 1
    url = req.full_url
    if url in raise_urls:
        raise RuntimeError("simulated network error")
    return _FakeResp({"url": url, "call": calls["n"]})


urllib.request.urlopen = _fake_urlopen

fails = 0
def check(desc, cond):
    global fails
    print(("  PASS: " if cond else "  FAIL: ") + desc)
    if not cond:
        fails += 1


obj = types.SimpleNamespace()  # minimal 'self' — method only uses cache attrs

# 1. First call hits the network once.
d1 = _http_get_json(obj, "https://ref/a")
check("first call fetches (1 HTTP)", calls["n"] == 1 and d1 is not None)

# 2. Same URL -> cache hit, NO new HTTP.
d2 = _http_get_json(obj, "https://ref/a")
check("repeat call is a cache hit (still 1 HTTP)", calls["n"] == 1 and d2 == d1)

# 3. Different URL -> new fetch.
_http_get_json(obj, "https://ref/b")
check("distinct URL misses (2 HTTP)", calls["n"] == 2)

# 4. TTL expiry -> re-fetch.
obj._ref_http_cache_ttl = 0
_http_get_json(obj, "https://ref/a")
check("ttl=0 forces re-fetch (3 HTTP)", calls["n"] == 3)

# 5. Failed response is NOT cached -> retries.
obj._ref_http_cache_ttl = 21600
raise_urls.add("https://ref/err")
r1 = _http_get_json(obj, "https://ref/err")
n_after_first_err = calls["n"]
r2 = _http_get_json(obj, "https://ref/err")
check("failure returns None and is not cached (retries)",
      r1 is None and r2 is None and calls["n"] == n_after_first_err + 1)

print("ALL CACHE TESTS PASSED" if fails == 0 else f"{fails} CHECK(S) FAILED")
sys.exit(fails)
