/** Local inference transport. No fallback and no redirects to other endpoints. */
import { Agent } from 'undici';
export const localOnly = () => process.env.BIOMATE_LOCAL_ONLY === '1';
export const localOffline = () => localOnly() && process.env.BIOMATE_OFFLINE === '1';

export function localConfig() {
  const raw = process.env.BIOMATE_LOCAL_LLM_URL;
  const model = process.env.BIOMATE_LOCAL_LLM_MODEL;
  if (!raw || !model) throw new Error('Local inference requires BIOMATE_LOCAL_LLM_URL and BIOMATE_LOCAL_LLM_MODEL');
  const url = new URL(raw);
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.search || url.hash) {
    throw new Error('Invalid local inference URL');
  }
  // Exact operator-approved origin, including port. Network isolation remains a deployment gate.
  if (url.origin !== process.env.BIOMATE_LOCAL_LLM_ORIGIN) throw new Error('Local inference origin is not approved');
  const timeout = Number(process.env.BIOMATE_LOCAL_LLM_TIMEOUT_MS || 120000);
  if (!Number.isInteger(timeout) || timeout <= 0 || timeout > 600000) throw new Error('Invalid local inference timeout');
  return { url: url.toString().replace(/\/$/, ''), model, timeout };
}

export async function localCompletion(body: Record<string, any>) {
  const cfg = localConfig();
  // Node's default 300s header deadline otherwise preempts a longer CPU timeout.
  // Keep this dispatcher local to the request; never alter global cloud clients.
  const dispatcher = new Agent({ headersTimeout: cfg.timeout, bodyTimeout: cfg.timeout });
  try {
    const options: RequestInit & { dispatcher: Agent } = {
      dispatcher,
      method: 'POST', redirect: 'error', signal: AbortSignal.timeout(cfg.timeout),
      headers: { 'Content-Type': 'application/json', ...(process.env.BIOMATE_LOCAL_LLM_KEY
        ? { Authorization: `Bearer ${process.env.BIOMATE_LOCAL_LLM_KEY}` } : {}) },
      body: JSON.stringify({ chat_template_kwargs: { enable_thinking: false },
        ...(process.env.BIOMATE_LOCAL_LLM_REASONING_EFFORT ? { reasoning_effort: process.env.BIOMATE_LOCAL_LLM_REASONING_EFFORT } : {}),
        ...body, model: cfg.model, stream: false }),
    };
    const response = await fetch(`${cfg.url}/chat/completions`, options);
    if (!response.ok) throw new Error(`Local inference HTTP ${response.status}`);
    const result = await response.json();
    const choice = result.choices?.[0];
    if (!choice?.message || !['stop', 'length', 'tool_calls'].includes(choice.finish_reason)) {
      throw new Error('Invalid or unsupported local completion');
    }
    if (body.response_format?.type === 'json_object') {
      if (choice.finish_reason !== 'stop') throw new Error('Local inference did not produce a complete JSON object');
      choice.message.content = jsonObjectText(choice.message.content);
    }
    return result;
  } finally {
    await dispatcher.destroy();
  }
}

/** Accept only a complete object, optionally enclosed in one Markdown JSON fence.
 * No substring extraction, repair, invented keys, or acceptance of partial output.
 */
export function jsonObjectText(content: unknown): string {
  if (typeof content !== 'string') throw new Error('Local JSON output must be text');
  const text = content.trim();
  const fenced = /^```(?:json)?\s*\n([\s\S]*?)\n```$/i.exec(text);
  const objectText = (fenced ? fenced[1] : text).trim();
  const value = JSON.parse(objectText);
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Local JSON output must be an object');
  const check = (item: any): void => {
    if (typeof item === 'number' && !Number.isFinite(item)) throw new Error('Non-finite value in local JSON output');
    if (item && typeof item === 'object') Object.values(item).forEach(check);
  };
  check(value);
  return objectText;
}

function textBlocks(content: any): string {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) throw new Error('Unsupported local message content');
  return content.map(b => {
    if (b.type !== 'text') throw new Error(`Local text trial does not support ${b.type} content`);
    return b.text;
  }).join('\n');
}

/** Translate the Messages API subset used by GalaxyAssistant, retaining tool IDs. */
export function localMessages(params: any): any[] {
  const messages: any[] = [];
  if (params.system) messages.push({ role: 'system', content: textBlocks(params.system) });
  for (const message of params.messages) {
    if (typeof message.content === 'string') { messages.push(message); continue; }
    const content = message.content;
    if (message.role === 'assistant') {
      const calls = content.filter((b: any) => b.type === 'tool_use');
      const other = content.filter((b: any) => b.type !== 'tool_use');
      messages.push({ role: 'assistant', content: other.length ? textBlocks(other) : null,
        ...(calls.length ? { tool_calls: calls.map((b: any) => ({ id: b.id, type: 'function',
          function: { name: b.name, arguments: JSON.stringify(b.input) } })) } : {}) });
    } else {
      const results = content.filter((b: any) => b.type === 'tool_result');
      for (const b of results) messages.push({ role: 'tool', tool_call_id: b.tool_use_id,
        content: textBlocks(b.content) });
      const other = content.filter((b: any) => b.type !== 'tool_result');
      if (other.length) messages.push({ role: 'user', content: textBlocks(other) });
    }
  }
  return messages;
}

/** Validate the object/string/number/array schemas used by BioMate's agent tools. */
export function validateToolInput(value: any, schema: any, path = 'arguments'): void {
  const supported = new Set(['type', 'properties', 'required', 'items', 'enum', 'description', 'title', 'default', 'additionalProperties', 'minimum', 'maximum']);
  for (const key of Object.keys(schema)) if (!supported.has(key)) throw new Error(`Unsupported local tool schema keyword: ${key}`);
  if (schema.enum && !schema.enum.some((v: any) => JSON.stringify(v) === JSON.stringify(value))) throw new Error(`Invalid ${path}: enum`);
  if (schema.type === 'object') {
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error(`Invalid ${path}: object required`);
    for (const key of schema.required || []) if (!Object.hasOwn(value, key)) throw new Error(`Invalid ${path}: missing ${key}`);
    for (const [key, child] of Object.entries(value)) {
      if (schema.properties?.[key]) validateToolInput(child, schema.properties[key], `${path}.${key}`);
      else if (schema.additionalProperties === false) throw new Error(`Invalid ${path}: unexpected ${key}`);
      else if (typeof schema.additionalProperties === 'object') validateToolInput(child, schema.additionalProperties, `${path}.${key}`);
    }
  } else if (schema.type === 'array') {
    if (!Array.isArray(value)) throw new Error(`Invalid ${path}: array required`);
    if (schema.items) value.forEach((v, i) => validateToolInput(v, schema.items, `${path}[${i}]`));
  } else if (schema.type === 'integer' || schema.type === 'number') {
    if (typeof value !== 'number' || !Number.isFinite(value) || (schema.type === 'integer' && !Number.isInteger(value))) throw new Error(`Invalid ${path}: number required`);
    if (schema.minimum !== undefined && value < schema.minimum || schema.maximum !== undefined && value > schema.maximum) throw new Error(`Invalid ${path}: range`);
  } else if (schema.type === 'string' || schema.type === 'boolean') {
    if (typeof value !== schema.type) throw new Error(`Invalid ${path}: ${schema.type} required`);
  } else if (schema.type) throw new Error(`Unsupported local tool schema type: ${schema.type}`);
}

async function* events(message: any) {
  yield { type: 'message_start', message: { ...message, content: [] } };
  for (const [index, block] of message.content.entries()) {
    yield { type: 'content_block_start', index, content_block: block.type === 'text'
      ? { type: 'text', text: '' } : { ...block, input: {} } };
    yield { type: 'content_block_delta', index, delta: block.type === 'text'
      ? { type: 'text_delta', text: block.text }
      : { type: 'input_json_delta', partial_json: JSON.stringify(block.input) } };
    yield { type: 'content_block_stop', index };
  }
  yield { type: 'message_delta', delta: { stop_reason: message.stop_reason }, usage: message.usage };
  yield { type: 'message_stop' };
}

export function localMessagesClient() {
  return { messages: { create: async (params: any) => {
    const tools = params.tools?.map((t: any) => {
      if (!t.input_schema || !t.name) throw new Error('Unsupported local tool definition');
      return { type: 'function', function: { name: t.name, description: t.description, parameters: t.input_schema } };
    });
    const result = await localCompletion({ messages: localMessages(params),
      max_tokens: params.max_tokens ?? 4096, temperature: params.temperature ?? 0,
      ...(params.stop_sequences ? { stop: params.stop_sequences } : {}),
      ...(tools?.length ? { tools, tool_choice: 'auto' } : {}) });
    const choice = result.choices[0];
    const calls = choice.message.tool_calls || [];
    if (calls.length && choice.finish_reason !== 'tool_calls') throw new Error('Incomplete local tool call');
    const seen = new Set();
    const blocks = calls.map((call: any) => {
      if (!call.id || seen.has(call.id) || call.type !== 'function'
          || !tools?.some((t: any) => t.function.name === call.function?.name)) throw new Error('Invalid local tool call');
      seen.add(call.id);
      const input = JSON.parse(call.function.arguments);
      if (!input || typeof input !== 'object' || Array.isArray(input)) throw new Error('Invalid local tool arguments');
      validateToolInput(input, tools.find((t: any) => t.function.name === call.function.name).function.parameters);
      return { type: 'tool_use', id: call.id, name: call.function.name, input };
    });
    const message = { id: result.id, type: 'message', role: 'assistant', model: localConfig().model,
      content: [...(choice.message.content ? [{ type: 'text', text: choice.message.content }] : []), ...blocks],
      stop_reason: choice.finish_reason === 'tool_calls' ? 'tool_use' : choice.finish_reason === 'length' ? 'max_tokens' : 'end_turn',
      usage: { input_tokens: result.usage?.prompt_tokens ?? 0, output_tokens: result.usage?.completion_tokens ?? 0 } };
    // Buffered compatibility events; deliberately not advertised as token streaming.
    return params.stream ? events(message) : message;
  } } };
}
