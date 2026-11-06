"""Offline tests for the Paperclip client (fake transport; the live service needs a key)."""
import os
import unittest

from galaxy.ai import paperclip_client as pc

TOOLS = {"tools": [
    {"name": "search", "inputSchema": {"properties": {"query": {}, "source": {}, "n": {}}}},
    {"name": "grep", "inputSchema": {"properties": {"pattern": {}, "path": {}}}},
    {"name": "map", "inputSchema": {"properties": {"query": {}, "from": {}}}},
]}


def fake(calls, search_text="", status=200, call_status=200):
    def t(url, headers, payload, timeout):
        calls.append((payload["method"], payload["params"], headers))
        if payload["method"] == "initialize":
            return status, {"jsonrpc": "2.0", "id": payload["id"], "result": {}}
        if payload["method"] == "tools/list":
            return status, {"jsonrpc": "2.0", "id": payload["id"], "result": TOOLS}
        return call_status, {"jsonrpc": "2.0", "id": payload["id"],
                             "result": {"content": [{"type": "text", "text": search_text}]}}
    return t


class PaperclipTests(unittest.TestCase):
    def setUp(self):
        self._env = dict(os.environ)
        for k in ("PAPERCLIP_API_KEY", "BIOMATE_OFFLINE", "TARGET_ID_OFFLINE"):
            os.environ.pop(k, None)

    def tearDown(self):
        os.environ.clear(); os.environ.update(self._env)

    def test_disabled_without_key_and_makes_no_network_call(self):
        calls = []
        r = pc.PaperclipClient(transport=fake(calls)).search("x")
        self.assertEqual(r["status"], "disabled"); self.assertEqual(calls, [])

    def test_offline_mode_blocks_even_with_a_key(self):
        os.environ["PAPERCLIP_API_KEY"] = "gxl_x"; os.environ["BIOMATE_OFFLINE"] = "1"
        calls = []
        self.assertEqual(pc.PaperclipClient(transport=fake(calls)).search("x")["status"], "offline")
        self.assertEqual(calls, []); self.assertFalse(pc.is_enabled())

    def test_search_maps_argument_names_from_the_tool_schema_and_sends_the_key(self):
        os.environ["PAPERCLIP_API_KEY"] = "gxl_x"
        calls = []
        r = pc.PaperclipClient(transport=fake(calls, "/papers/PMC123 Switch-like genes PMID: 12345678")).search("q", source="pmc", limit=3)
        self.assertEqual(r["status"], "ok")
        method, params, headers = calls[-1]
        self.assertEqual(method, "tools/call")
        self.assertEqual(params["arguments"], {"query": "q", "source": "pmc", "n": 3})
        self.assertEqual(headers["X-API-Key"], "gxl_x")

    def test_map_uses_the_from_argument_and_unknown_tool_is_reported(self):
        os.environ["PAPERCLIP_API_KEY"] = "gxl_x"
        calls = []
        c = pc.PaperclipClient(transport=fake(calls))
        c.map_results("what is the endpoint?", "s_1907a2d0")
        self.assertEqual(calls[-1][1]["arguments"], {"query": "what is the endpoint?", "from": "s_1907a2d0"})
        self.assertEqual(c.call_tool("nope")["status"], "error")

    def test_auth_and_rate_limit_are_reported_not_raised(self):
        os.environ["PAPERCLIP_API_KEY"] = "bad"
        self.assertEqual(pc.PaperclipClient(transport=fake([], status=401)).search("x")["status"], "auth_error")
        self.assertEqual(pc.PaperclipClient(transport=fake([], call_status=429)).search("x")["status"], "rate_limited")
        def boom(*a, **k): raise OSError("down")
        self.assertEqual(pc.PaperclipClient(transport=boom, key="k").search("x")["status"], "error")

    def test_parse_search_text_extracts_ids_and_path(self):
        rows = pc.parse_search_text("/papers/PMC99 Switch genes and trials PMID 12345678 doi 10.1126/science.aeg6779.\nnoise line")
        self.assertEqual(rows[0]["paperclip_path"], "/papers/PMC99")
        self.assertEqual(rows[0]["pmid"], "12345678"); self.assertEqual(rows[0]["doi"], "10.1126/science.aeg6779")
        self.assertEqual(len(rows), 1)

    def test_sse_reply_is_parsed(self):
        self.assertEqual(pc._parse_body('event: message\ndata: {"a": 1}\n\n', "text/event-stream"), {"a": 1})

    def test_federation_shape_when_disabled(self):
        out = pc.fetch_for_federation("q")
        self.assertEqual((out["source"], out["results"], out["status"]), ("paperclip", [], "disabled"))


if __name__ == "__main__":
    unittest.main()
