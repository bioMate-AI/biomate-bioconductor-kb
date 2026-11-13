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
    // Text-only rendering: an image block (an attached image read by read_file, a run_code plot)
    // becomes a short note instead of throwing and aborting the whole agent turn.
    if (b.type === 'image') return `[image (${b.source?.media_type || 'image'}) — not visible to this model]`;
    if (b.type !== 'text') throw new Error(`Local text trial does not support ${b.type} content`);
    return b.text;
  }).join('\n');
}

/** Anthropic base64 image block → OpenAI `image_url` content part (data URI). */
function imagePart(b: any): any {
  if (b?.source?.type !== 'base64' || !b.source.media_type || !b.source.data) return null;
  return { type: 'image_url', image_url: { url: `data:${b.source.media_type};base64,${b.source.data}` } };
}

function hasImages(params: any): boolean {
  const walk = (c: any): boolean => Array.isArray(c) && c.some((b: any) => b?.type === 'image'
    || (b?.type === 'tool_result' && walk(b.content)));
  return (params.messages || []).some((m: any) => walk(m.content));
}

/** Translate the Messages API subset used by GalaxyAssistant, retaining tool IDs.
 *  With `vision`, images reach the model as OpenAI `image_url` parts. The OpenAI `tool` role
 *  carries text only, so a tool result's images follow the turn's tool messages as one user
 *  message (tool messages must stay contiguous after the assistant's tool_calls). Without it,
 *  each image becomes a text note. */
export function localMessages(params: any, opts: { vision?: boolean } = {}): any[] {
  const messages: any[] = [];
  const split = (content: any) => {
    if (!opts.vision || !Array.isArray(content)) return { text: textBlocks(content), images: [] as any[] };
    const images = content.filter((b: any) => b.type === 'image').map(imagePart).filter(Boolean);
    return { text: textBlocks(content.filter((b: any) => b.type !== 'image' || !imagePart(b))), images };
  };
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
      const toolImages: any[] = [];
      for (const b of results) {
        const { text, images } = split(b.content);
        messages.push({ role: 'tool', tool_call_id: b.tool_use_id, content: text });
        if (images.length) toolImages.push({ type: 'text', text: `Image output of tool call ${b.tool_use_id}:` }, ...images);
      }
      const other = content.filter((b: any) => b.type !== 'tool_result');
      const { text, images } = split(other.length ? other : []);
      const parts = [...toolImages, ...(other.length ? [{ type: 'text', text }, ...images] : [])];
      if (!parts.length) continue;
      messages.push({ role: 'user', content: toolImages.length || images.length ? parts : text });
    }
  }
  return messages;
}

const _imageInputCache = new Map<string, boolean>();
/** Whether an OpenAI-compatible model accepts image input, from the provider's model listing
 *  (OpenRouter: `architecture.input_modalities`). Unknown or unreachable → false (text note). */
export async function modelAcceptsImages(cfg: { url: string; model: string; key?: string }): Promise<boolean> {
  const cacheKey = `${cfg.url}|${cfg.model}`;
  const hit = _imageInputCache.get(cacheKey);
  if (hit !== undefined) return hit;
  let ok = false;
  try {
    const r = await fetch(`${cfg.url.replace(/\/$/, '')}/models`, { redirect: 'error', signal: AbortSignal.timeout(10000),
      headers: cfg.key ? { Authorization: `Bearer ${cfg.key}` } : {} });
    if (r.ok) {
      const m = ((await r.json())?.data || []).find((x: any) => x?.id === cfg.model);
      ok = Array.isArray(m?.architecture?.input_modalities) && m.architecture.input_modalities.includes('image');
      _imageInputCache.set(cacheKey, ok);
    }
  } catch { /* not cached: retried on the next image-bearing turn */ }
  return ok;
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

/** Anthropic tool_choice → OpenAI tool_choice. {type:'none'} must reach the provider: the agentic
 *  loop's final-answer turn keeps the tools declared (the transcript has tool calls) but disabled. */
export function openaiToolChoice(choice: any): 'auto' | 'none' {
  return choice?.type === 'none' || choice === 'none' ? 'none' : 'auto';
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
      ...(tools?.length ? { tools, tool_choice: openaiToolChoice(params.tool_choice) } : {}) });
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

/** Config-parameterized OpenAI-compatible completion. Same transport discipline as
 *  localCompletion (no redirects, explicit timeout, strict finish_reason, strict JSON),
 *  but the endpoint/model/key are supplied by a TRUSTED caller (e.g. the fixed OpenRouter
 *  origin) rather than read from the BIOMATE_LOCAL_* env + origin allowlist. Reuses
 *  jsonObjectText. Used to give OpenRouter the same agentic transport as on-prem. */
export async function openaiCompatCompletion(
  cfg: { url: string; model: string; key?: string; timeout?: number },
  body: Record<string, any>,
) {
  const timeout = cfg.timeout ?? 120000;
  const dispatcher = new Agent({ headersTimeout: timeout, bodyTimeout: timeout });
  try {
    const options: RequestInit & { dispatcher: Agent } = {
      dispatcher, method: 'POST', redirect: 'error', signal: AbortSignal.timeout(timeout),
      headers: { 'Content-Type': 'application/json', ...(cfg.key ? { Authorization: `Bearer ${cfg.key}` } : {}) },
      body: JSON.stringify({ ...body, model: cfg.model, stream: false }),
    };
    const response = await fetch(`${cfg.url.replace(/\/$/, '')}/chat/completions`, options);
    if (!response.ok) throw new Error(`Inference HTTP ${response.status}`);
    const result = await response.json();
    const choice = result.choices?.[0];
    if (!choice?.message || !['stop', 'length', 'tool_calls'].includes(choice.finish_reason)) {
      throw new Error('Invalid or unsupported completion');
    }
    if (body.response_format?.type === 'json_object') {
      if (choice.finish_reason !== 'stop') throw new Error('Inference did not produce a complete JSON object');
      choice.message.content = jsonObjectText(choice.message.content);
    }
    return result;
  } finally {
    await dispatcher.destroy();
  }
}

/** OpenRouter counts hidden reasoning tokens against `max_tokens`. A reasoning model given the
 *  caller's answer budget (e.g. analyzeIntent's 4096) could spend all of it thinking and return
 *  `finish_reason: "length"` with empty content (glm-5.3-prime: reasoning_tokens 4094 / 4096,
 *  docs/20261111_OPENROUTER_VISION_AND_REASONING_BUDGET.md §2). Cap reasoning separately and add the
 *  cap on top, so the caller's budget stays an ANSWER budget. OpenRouter-only: `reasoning` is its
 *  parameter (ignored by models without reasoning); other OpenAI-compatible servers are untouched. */
export function reasoningBudgetBody(url: string, answerTokens: number): Record<string, any> {
  if (!/(^|\/\/)([^/]*\.)?openrouter\.ai(\/|$)/.test(url)) return { max_tokens: answerTokens };
  const r = Number(process.env.BIOMATE_OPENROUTER_REASONING_TOKENS || 2048);
  const reasoning = Number.isFinite(r) && r > 0 ? Math.floor(r) : 2048;
  return { max_tokens: answerTokens + reasoning, reasoning: { max_tokens: reasoning } };
}

/** No silent skip: a length-stopped reply with no content and no tool call means the budget went to
 *  reasoning — fail loudly (callers fall back and log) instead of passing on an empty answer. */
export function assertNotReasoningExhausted(result: any): void {
  const c = result?.choices?.[0];
  if (c?.finish_reason === 'length' && !String(c?.message?.content || '').trim() && !(c?.message?.tool_calls || []).length) {
    const rt = result?.usage?.completion_tokens_details?.reasoning_tokens;
    throw new Error(`Model spent its output budget on reasoning${rt != null ? ` (${rt} reasoning tokens)` : ''} and returned no answer`);
  }
}

/** Anthropic-shaped message for a `finish_reason: "length"` reply: its text, plus one marked
 *  `tool_use` per cut tool call (name only, empty input, `truncated: true`) — never executed. */
export function lengthStopMessage(result: any, choice: any, calls: any[], model: string) {
  const text = String(choice?.message?.content || '');
  return { id: result?.id, type: 'message', role: 'assistant', model,
    content: [...(text ? [{ type: 'text', text }] : []),
      ...calls.map((c: any, i: number) => ({ type: 'tool_use', id: c?.id || `truncated_${i}`, name: c?.function?.name || 'unknown', input: {}, truncated: true }))],
    stop_reason: 'max_tokens',
    usage: { input_tokens: result?.usage?.prompt_tokens ?? 0, output_tokens: result?.usage?.completion_tokens ?? 0 } };
}

/** Config-parameterized Anthropic-Messages shim over any OpenAI-compatible endpoint.
 *  Generalizes localMessagesClient so OpenRouter (and any OpenAI-compatible provider)
 *  gets the SAME agentic tool loop as on-prem: BIOMATE_TOOLS → OpenAI functions,
 *  tool_calls → validated tool_use, Anthropic-shaped message/stream. */
export function openaiCompatMessagesClient(cfg: { url: string; model: string; key?: string; timeout?: number }) {
  return { messages: { create: async (params: any) => {
    const tools = params.tools?.map((t: any) => {
      if (!t.input_schema || !t.name) throw new Error('Unsupported tool definition');
      return { type: 'function', function: { name: t.name, description: t.description, parameters: t.input_schema } };
    });
    const vision = hasImages(params) && await modelAcceptsImages(cfg);
    const result = await openaiCompatCompletion(cfg, { messages: localMessages(params, { vision }),
      ...reasoningBudgetBody(cfg.url, params.max_tokens ?? 4096), temperature: params.temperature ?? 0,
      ...(params.stop_sequences ? { stop: params.stop_sequences } : {}),
      ...(tools?.length ? { tools, tool_choice: openaiToolChoice(params.tool_choice) } : {}) });
    const choice = result.choices[0];
    const calls = choice.message.tool_calls || [];
    // Length stop in the agent loop: return it as a max_tokens turn instead of throwing, so the loop
    // can ask the model to continue (galaxy-assistant truncatedTurnNeedsFollowUp). A tool call cut
    // mid-arguments is passed as a marked, never-executed tool_use (stop_reason max_tokens never
    // reaches tool execution) so the loop knows the turn was mid-work.
    if (choice?.finish_reason === 'length') {
      const rt = result?.usage?.completion_tokens_details?.reasoning_tokens;
      console.warn(`[openaiCompat] ${cfg.model} stopped on the output-length limit` +
        `${rt != null ? ` (${rt} reasoning tokens)` : ''}${calls.length ? ' inside a tool call' : ''}`);
      return params.stream ? events(lengthStopMessage(result, choice, calls, cfg.model)) : lengthStopMessage(result, choice, calls, cfg.model);
    }
    if (calls.length && choice.finish_reason !== 'tool_calls') throw new Error('Incomplete tool call');
    const seen = new Set();
    const blocks = calls.map((call: any) => {
      if (!call.id || seen.has(call.id) || call.type !== 'function'
          || !tools?.some((t: any) => t.function.name === call.function?.name)) throw new Error('Invalid tool call');
      seen.add(call.id);
      const input = JSON.parse(call.function.arguments);
      if (!input || typeof input !== 'object' || Array.isArray(input)) throw new Error('Invalid tool arguments');
      validateToolInput(input, tools.find((t: any) => t.function.name === call.function.name).function.parameters);
      return { type: 'tool_use', id: call.id, name: call.function.name, input };
    });
    const message = { id: result.id, type: 'message', role: 'assistant', model: cfg.model,
      content: [...(choice.message.content ? [{ type: 'text', text: choice.message.content }] : []), ...blocks],
      stop_reason: choice.finish_reason === 'tool_calls' ? 'tool_use' : choice.finish_reason === 'length' ? 'max_tokens' : 'end_turn',
      usage: { input_tokens: result.usage?.prompt_tokens ?? 0, output_tokens: result.usage?.completion_tokens ?? 0 } };
    return params.stream ? events(message) : message;
  } } };
}
