import { describe, expect, it, vi } from 'vitest';
import { decomposeViaOpenRouter } from './galaxy-assistant';

// Decomposition via a benchmark-chosen OpenRouter model (docs/20261103 §12.2). Providers throttle
// concurrent ≈21k-token requests; failures must surface (the caller falls back to Gemini Flash, then a
// marked-degraded keyword path) instead of silently becoming a heuristic decomposition.
const ok = (text: string) => ({ ok: true, json: async () => ({ choices: [{ message: { content: text } }] }), text: async () => '' });
const bad = (status: number) => ({ ok: false, status, text: async () => 'Rate limit exceeded', json: async () => ({}) });

describe('decomposeViaOpenRouter', () => {
  it('retries once after a provider error, then returns the text', async () => {
    const f = vi.fn().mockResolvedValueOnce(bad(429)).mockResolvedValueOnce(ok('{"type":"workflow_generation"}'));
    expect(await decomposeViaOpenRouter('z-ai/glm-5.2', 'k', 'sys', 'msg', f as any)).toBe('{"type":"workflow_generation"}');
    expect(f).toHaveBeenCalledTimes(2);
    const body = JSON.parse((f.mock.calls[0] as any)[1].body);
    expect(body.model).toBe('z-ai/glm-5.2');
    expect(body.messages[0]).toEqual({ role: 'system', content: 'sys' });
    expect((f.mock.calls[0] as any)[1].headers.Authorization).toBe('Bearer k');
    // Reasoning is capped separately so 4096 stays the ANSWER budget (glm-5.3-prime spent 4094/4096 thinking).
    expect(body.reasoning).toEqual({ max_tokens: 2048 });
    expect(body.max_tokens).toBe(4096 + 2048);
  });
  it('names a reasoning-exhausted reply instead of passing on an empty answer', async () => {
    const exhausted = { ok: true, text: async () => '', json: async () => ({
      choices: [{ finish_reason: 'length', message: { content: '' } }],
      usage: { completion_tokens_details: { reasoning_tokens: 4094 } } }) };
    await expect(decomposeViaOpenRouter('m', 'k', 's', 'u', vi.fn().mockResolvedValue(exhausted) as any))
      .rejects.toThrow(/output budget on reasoning \(4094 reasoning tokens\)/);
  });
  it('throws after two failures and treats an empty answer as a failure', async () => {
    await expect(decomposeViaOpenRouter('m', 'k', 's', 'u', vi.fn().mockResolvedValue(bad(503)) as any)).rejects.toThrow(/HTTP 503/);
    await expect(decomposeViaOpenRouter('m', 'k', 's', 'u', vi.fn().mockResolvedValue(ok('  ')) as any)).rejects.toThrow(/empty response/);
  });
});
