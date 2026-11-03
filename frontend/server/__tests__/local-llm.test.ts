import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { localCompletion, localMessages, localMessagesClient, validateToolInput, jsonObjectText, openaiCompatMessagesClient } from '../local-llm';
import { llmGenerate } from '../llm-client';
const original = { ...process.env };
beforeEach(() => {
  process.env.BIOMATE_LOCAL_ONLY = '1';
  process.env.BIOMATE_LOCAL_LLM_URL = 'http://localhost:8000/v1';
  process.env.BIOMATE_LOCAL_LLM_ORIGIN = 'http://localhost:8000';
  process.env.BIOMATE_LOCAL_LLM_MODEL = 'trial-model';
});
afterEach(() => { process.env = { ...original }; vi.unstubAllGlobals(); });
function reply(message: any, finish_reason = 'stop') {
  return new Response(JSON.stringify({ model: 'trial-model', choices: [{ message, finish_reason }] }));
}
describe('local inference boundary and tool protocol', () => {
  it('accepts the observed single JSON fence but rejects commentary, partial JSON and non-objects', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(reply({ content: '```json\n{"accession":"GSE12345","platform":"GPL96"}\n```' })));
    const result = await llmGenerate({ prompt: 'identifiers', jsonMode: true });
    expect(JSON.parse(result.text)).toEqual({ accession: 'GSE12345', platform: 'GPL96' });
    for (const text of ['Here is JSON: {"x":1}', '```json\n{"x":\n```', 'null', '[1]', '{"x":1} extra', '{"x":1e999}']) {
      expect(() => jsonObjectText(text)).toThrow();
    }
  });
  it('rejects an unapproved origin without making a request', async () => {
    const fetch = vi.fn(); vi.stubGlobal('fetch', fetch);
    process.env.BIOMATE_LOCAL_LLM_URL = 'https://example.com/v1';
    await expect(localCompletion({})).rejects.toThrow('origin'); expect(fetch).not.toHaveBeenCalled();
  });
  it('never falls back when local inference fails, even with cloud credentials', async () => {
    process.env.ANTHROPIC_API_KEY = 'test';
    const fetch = vi.fn().mockResolvedValue(new Response('', { status: 503 })); vi.stubGlobal('fetch', fetch);
    await expect(llmGenerate({ prompt: 'hello' })).rejects.toThrow('503');
    expect(fetch).toHaveBeenCalledTimes(1);
    expect(fetch.mock.calls[0][1].redirect).toBe('error');
  });
  it('routes text and JSON requests locally and rejects truncation', async () => {
    const fetch = vi.fn().mockResolvedValueOnce(reply({ content: '{"ok":true}' }))
      .mockResolvedValueOnce(reply({ content: 'partial' }, 'length')); vi.stubGlobal('fetch', fetch);
    expect((await llmGenerate({ prompt: 'hello', jsonMode: true })).fallbackDepth).toBe(0);
    expect(JSON.parse(fetch.mock.calls[0][1].body).response_format.type).toBe('json_object');
    await expect(llmGenerate({ prompt: 'hello' })).rejects.toThrow('complete');
  });
  it('preserves tool-call IDs and observations over a complete two-turn exchange', async () => {
    const fetch = vi.fn().mockResolvedValueOnce(reply({ tool_calls: [{ id: 'call-1', type: 'function',
      function: { name: 'list_history', arguments: '{}' } }] }, 'tool_calls'))
      .mockResolvedValueOnce(reply({ content: 'There are two datasets.' })); vi.stubGlobal('fetch', fetch);
    const client = localMessagesClient();
    const tools = [{ name: 'list_history', input_schema: { type: 'object', properties: {} } }];
    const first: any = await client.messages.create({ messages: [{ role: 'user', content: 'List datasets' }], tools });
    expect(first.stop_reason).toBe('tool_use');
    const final: any = await client.messages.create({ tools, messages: [
      { role: 'user', content: 'List datasets' }, { role: 'assistant', content: first.content },
      { role: 'user', content: [{ type: 'tool_result', tool_use_id: 'call-1', content: '{"count":2}' }] },
    ] });
    const sent = JSON.parse(fetch.mock.calls[1][1].body);
    expect(sent.messages[1].tool_calls[0].id).toBe('call-1');
    expect(sent.messages[2]).toEqual({ role: 'tool', tool_call_id: 'call-1', content: '{"count":2}' });
    expect(final.content[0].text).toContain('two');
  });
  it('emits compatible tool stream events and rejects unknown tools', async () => {
    vi.stubGlobal('fetch', vi.fn().mockImplementation(() => Promise.resolve(reply({ tool_calls: [
      { id: 'c', type: 'function', function: { name: 'lookup', arguments: '{"id":"GSE1"}' } },
    ] }, 'tool_calls'))));
    const client = localMessagesClient();
    const params = { messages: [{ role: 'user', content: 'lookup' }], stream: true,
      tools: [{ name: 'lookup', input_schema: { type: 'object' } }] };
    const events = []; for await (const event of await client.messages.create(params) as any) events.push(event);
    expect(events.find(e => e.type === 'content_block_delta').delta.partial_json).toBe('{"id":"GSE1"}');
    await expect(client.messages.create({ ...params, tools: [] })).rejects.toThrow('tool call');
  });
  it('fails explicitly for unsupported image content', () => {
    expect(() => localMessages({ messages: [{ role: 'user', content: [{ type: 'image' }] }] })).toThrow('does not support');
  });
});

it('rejects invalid tool parameters before execution', () => {
  const schema = { type: 'object', required: ['language', 'code'], properties: {
    language: { type: 'string', enum: ['python', 'r'] }, code: { type: 'string' },
  } };
  expect(() => validateToolInput({ language: 'python' }, schema)).toThrow('missing code');
  expect(() => validateToolInput({ language: 'shell', code: 'x' }, schema)).toThrow('enum');
  expect(() => validateToolInput({ language: 'python', code: ['x'] }, schema)).toThrow('string');
});

it('passes the configured local reasoning mode without changing existing callers', async () => {
  process.env.BIOMATE_LOCAL_LLM_REASONING_EFFORT = 'none';
  const fetch = vi.fn().mockResolvedValue(reply({ content: 'ok' })); vi.stubGlobal('fetch', fetch);
  await localCompletion({ messages: [{ role: 'user', content: 'test' }] });
  expect(JSON.parse(fetch.mock.calls[0][1].body).reasoning_effort).toBe('none');
});

// The config-parameterized shim that gives OpenRouter (and any OpenAI-compatible
// provider) the SAME agentic tool loop as on-prem. It takes an explicit cfg from a
// TRUSTED caller instead of the BIOMATE_LOCAL_* env + origin allowlist, so these
// tests delete that env to prove the two paths are independent.
describe('OpenAI-compatible agentic shim (OpenRouter / any base_url)', () => {
  beforeEach(() => {
    delete process.env.BIOMATE_LOCAL_ONLY;
    delete process.env.BIOMATE_LOCAL_LLM_URL;
    delete process.env.BIOMATE_LOCAL_LLM_ORIGIN;
    delete process.env.BIOMATE_LOCAL_LLM_MODEL;
  });
  it('targets the configured endpoint with bearer auth + model, no redirects, no env/origin allowlist', async () => {
    const fetch = vi.fn().mockResolvedValue(reply({ content: 'hi' })); vi.stubGlobal('fetch', fetch);
    const client = openaiCompatMessagesClient({ url: 'https://openrouter.ai/api/v1', model: 'z-ai/glm-5.3-prime', key: 'sk-or-test' });
    const res: any = await client.messages.create({ messages: [{ role: 'user', content: 'hello' }] });
    expect(res.content[0].text).toBe('hi');
    expect(res.model).toBe('z-ai/glm-5.3-prime');
    expect(fetch).toHaveBeenCalledTimes(1);
    const [url, opts] = fetch.mock.calls[0];
    expect(url).toBe('https://openrouter.ai/api/v1/chat/completions');
    expect(opts.headers.Authorization).toBe('Bearer sk-or-test');
    expect(opts.redirect).toBe('error');
    const body = JSON.parse(opts.body);
    expect(body.model).toBe('z-ai/glm-5.3-prime');
    expect(body.stream).toBe(false);
  });
  it('gives OpenRouter models the same validated tool loop (tool_use + ID + unknown-tool reject)', async () => {
    const fetch = vi.fn().mockImplementation(() => Promise.resolve(reply({ tool_calls: [{ id: 'call-9', type: 'function',
      function: { name: 'search_literature', arguments: '{"query":"PCSK9"}' } }] }, 'tool_calls')));
    vi.stubGlobal('fetch', fetch);
    const cfg = { url: 'https://openrouter.ai/api/v1/', model: 'moonshotai/kimi-k3', key: 'k' };
    const client = openaiCompatMessagesClient(cfg);
    const tools = [{ name: 'search_literature', input_schema: { type: 'object', properties: { query: { type: 'string' } }, required: ['query'] } }];
    const first: any = await client.messages.create({ messages: [{ role: 'user', content: 'lit search PCSK9' }], tools });
    expect(first.stop_reason).toBe('tool_use');
    expect(first.content.find((b: any) => b.type === 'tool_use')).toMatchObject({ id: 'call-9', name: 'search_literature', input: { query: 'PCSK9' } });
    // trailing-slash in url is normalized (no double slash)
    expect(fetch.mock.calls[0][0]).toBe('https://openrouter.ai/api/v1/chat/completions');
    // same unknown-tool guard as the local path
    await expect(client.messages.create({ messages: [{ role: 'user', content: 'x' }], tools: [] })).rejects.toThrow('tool call');
  });
  it('rejects a tool call whose arguments violate the schema (guardrail parity)', async () => {
    const fetch = vi.fn().mockResolvedValue(reply({ tool_calls: [{ id: 'c', type: 'function',
      function: { name: 'run_code', arguments: '{"language":"ruby","code":"1"}' } }] }, 'tool_calls')); vi.stubGlobal('fetch', fetch);
    const client = openaiCompatMessagesClient({ url: 'https://openrouter.ai/api/v1', model: 'm' });
    const tools = [{ name: 'run_code', input_schema: { type: 'object', required: ['language', 'code'],
      properties: { language: { type: 'string', enum: ['python', 'r'] }, code: { type: 'string' } } } }];
    await expect(client.messages.create({ messages: [{ role: 'user', content: 'run' }], tools })).rejects.toThrow('enum');
  });
});
