"""Offline wire and failure-boundary checks; no Galaxy app or model required."""
import asyncio
import importlib.util
import os
from pathlib import Path
import unittest
from unittest.mock import patch
import httpx
spec = importlib.util.spec_from_file_location('local_inference', Path(__file__).parents[1] / 'lib/galaxy/ai/local_inference.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class LocalInferenceTests(unittest.TestCase):
    def setUp(self):
        self.env = patch.dict(os.environ, {
            'BIOMATE_LOCAL_ONLY': '1', 'BIOMATE_LOCAL_LLM_URL': 'http://localhost:8000/v1',
            'BIOMATE_LOCAL_LLM_ORIGIN': 'http://localhost:8000', 'BIOMATE_LOCAL_LLM_MODEL': 'trial',
        }); self.env.start()
    def tearDown(self): self.env.stop()
    def test_unapproved_origin(self):
        with patch.dict(os.environ, {'BIOMATE_LOCAL_LLM_URL': 'https://example.com/v1'}):
            with self.assertRaisesRegex(ValueError, 'origin'): module.local_config()
    def test_complete_wire_and_truncation(self):
        bodies = []
        import json
        def handler(request):
            bodies.append(json.loads(request.content))
            return httpx.Response(200, json={'choices': [{'finish_reason': 'stop' if len(bodies) == 1 else 'length', 'message': {'content': '{}'}}]})
        real = httpx.AsyncClient
        with patch.object(module.httpx, 'AsyncClient', side_effect=lambda **kw: real(transport=httpx.MockTransport(handler), **kw)):
            self.assertEqual(asyncio.run(module.generate_local('question', system='rules', json_mode=True)), '{}')
            with self.assertRaisesRegex(ValueError, 'complete'): asyncio.run(module.generate_local('question'))
        self.assertEqual(bodies[0]['messages'][0], {'role': 'system', 'content': 'rules'})
        self.assertEqual(bodies[0]['model'], 'trial')
        self.assertEqual(bodies[0]['response_format'], {'type': 'json_object'})
    def test_no_redirect_or_retry(self):
        requests = []
        def handler(request):
            requests.append(request)
            return httpx.Response(302, headers={'Location': 'https://example.com'})
        real = httpx.AsyncClient
        with patch.object(module.httpx, 'AsyncClient', side_effect=lambda **kw: real(transport=httpx.MockTransport(handler), **kw)):
            with self.assertRaises(httpx.HTTPStatusError): asyncio.run(module.generate_local('question'))
        self.assertEqual(len(requests), 1)
    def test_fenced_json_and_invalid_objects(self):
        outputs = iter(['```json\n{"accession":"GSE12345"}\n```', 'Prefix {"x":1}', 'null', '[1]', '{"x":NaN}', '{"x":', '{"x":1e999}'])
        def handler(request):
            return httpx.Response(200, json={'choices': [{'finish_reason': 'stop', 'message': {'content': next(outputs)}}]})
        real = httpx.AsyncClient
        with patch.object(module.httpx, 'AsyncClient', side_effect=lambda **kw: real(transport=httpx.MockTransport(handler), **kw)):
            self.assertEqual(asyncio.run(module.generate_local('question', json_mode=True)), '{"accession":"GSE12345"}')
            for _ in range(6):
                with self.assertRaises(ValueError): asyncio.run(module.generate_local('question', json_mode=True))

if __name__ == '__main__': unittest.main()
