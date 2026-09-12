"""Explicit local-only text inference; failures never enter a cloud fallback chain."""
import os
import json
import re
import math
from urllib.parse import urlsplit
import httpx


def local_only():
    return os.environ.get('BIOMATE_LOCAL_ONLY') == '1'


def _reject_nonfinite(value):
    raise ValueError('Non-finite value in local JSON output: ' + value)


def _check_finite(value):
    if isinstance(value, float) and not math.isfinite(value):
        raise ValueError('Non-finite value in local JSON output')
    if isinstance(value, dict):
        for item in value.values(): _check_finite(item)
    elif isinstance(value, list):
        for item in value: _check_finite(item)


def local_config():
    raw = os.environ.get('BIOMATE_LOCAL_LLM_URL', '')
    model = os.environ.get('BIOMATE_LOCAL_LLM_MODEL', '')
    url = urlsplit(raw)
    if not model or url.scheme not in ('http', 'https') or not url.hostname or url.username or url.password or url.query or url.fragment:
        raise ValueError('Invalid or missing local inference configuration')
    if f'{url.scheme}://{url.netloc}' != os.environ.get('BIOMATE_LOCAL_LLM_ORIGIN'):
        raise ValueError('Local inference origin is not approved')
    timeout = float(os.environ.get('BIOMATE_LOCAL_LLM_TIMEOUT_MS', '120000')) / 1000
    if not 0 < timeout <= 600:
        raise ValueError('Invalid local inference timeout')
    return raw.rstrip('/'), model, timeout


async def generate_local(prompt, **kwargs):
    url, model, timeout = local_config()
    messages = []
    system = kwargs.get('system') or kwargs.get('system_prompt')
    if system:
        messages.append({'role': 'system', 'content': system})
    messages.append({'role': 'user', 'content': prompt})
    body = {'chat_template_kwargs': {'enable_thinking': False}, 'model': model, 'messages': messages, 'stream': False,
            'max_tokens': kwargs.get('max_tokens', 4096), 'temperature': kwargs.get('temperature', 0)}
    if kwargs.get('json_mode'):
        body['response_format'] = {'type': 'json_object'}
    headers = {}
    if os.environ.get('BIOMATE_LOCAL_LLM_KEY'):
        headers['Authorization'] = 'Bearer ' + os.environ['BIOMATE_LOCAL_LLM_KEY']
    async with httpx.AsyncClient(timeout=timeout, follow_redirects=False) as client:
        response = await client.post(url + '/chat/completions', json=body, headers=headers)
        response.raise_for_status()
        result = response.json()
    choice = result['choices'][0]
    if choice.get('finish_reason') != 'stop' or not isinstance(choice.get('message', {}).get('content'), str):
        raise ValueError('Local inference did not produce a complete text answer')
    content = choice['message']['content']
    if kwargs.get('json_mode'):
        text = content.strip()
        fenced = re.fullmatch(r'```(?:json)?\s*\n([\s\S]*?)\n```', text, re.IGNORECASE)
        object_text = (fenced.group(1) if fenced else text).strip()
        value = json.loads(object_text, parse_constant=_reject_nonfinite)
        if not isinstance(value, dict):
            raise ValueError('Local JSON output must be an object')
        _check_finite(value)
        content = object_text
    return content
