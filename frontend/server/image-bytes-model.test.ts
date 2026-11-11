import { describe, it, expect } from 'vitest';
import fs from 'fs/promises';
import os from 'os';
import path from 'path';
import { GalaxyAssistant, stripImageBytesForModel, plotImageBlocks } from './galaxy-assistant';
import { localMessages, modelAcceptsImages, reasoningBudgetBody } from './local-llm';
import { scanOutputDir } from './code-runner';

// Committee review 2026-11-11 (blocker): run_code plot previews (image_data_uri, base64) were
// serialized into the model's tool_result text — ~100–250K tokens per plot, re-sent every loop
// iteration. Images must reach a model only as image blocks, never as text.

const B64 = 'A'.repeat(400_000); // ~300 KB of image bytes as base64
const runCodeOutput = (mime = 'image/png') => ({
  exit_code: 0, stdout: 'saved scatter.png',
  output_files: [{ name: 'scatter.png', size: 300_000, preview: '(binary)', image_data_uri: `data:${mime};base64,${B64}` }],
});

describe('no image bytes in model-facing text', () => {
  it('strips image_data_uri from tool_result text', () => {
    const content = GalaxyAssistant.toolResultContent(runCodeOutput());
    const text = typeof content === 'string' ? content : content[0].text;
    expect(text).not.toContain('data:image');
    expect(text).not.toContain(B64.slice(0, 1000));
    expect(text.length).toBeLessThan(2000);
    expect(text).toContain('scatter.png'); // the model still learns the plot exists
  });

  it('passes plots as image blocks and keeps the text free of their bytes', () => {
    const out = { ...runCodeOutput(), __imageBlocks: plotImageBlocks(runCodeOutput().output_files) };
    const content = GalaxyAssistant.toolResultContent(out) as any[];
    expect(Array.isArray(content)).toBe(true);
    expect(content[0].text).not.toContain(B64.slice(0, 1000));
    expect(content.slice(1).map(b => b.type)).toEqual(['image']);
    expect(content[1].source).toMatchObject({ type: 'base64', media_type: 'image/png' });
  });

  it('stripImageBytesForModel handles nesting and drops __imageBlocks', () => {
    const v = stripImageBytesForModel({ a: [{ image_data_uri: 'data:image/png;base64,xx' }], __imageBlocks: [1] });
    expect(JSON.stringify(v)).not.toContain('data:image');
    expect(v.__imageBlocks).toBeUndefined();
  });
});

describe('plotImageBlocks', () => {
  it('only raster formats the vision model reads', () => {
    expect(plotImageBlocks(runCodeOutput('image/svg+xml').output_files)).toHaveLength(0);
    expect(plotImageBlocks(runCodeOutput('image/jpeg').output_files)).toHaveLength(1);
  });
  it('skips images over the per-image limit and caps the count', () => {
    const big = [{ image_data_uri: `data:image/png;base64,${'A'.repeat(6_000_000)}` }];
    expect(plotImageBlocks(big)).toHaveLength(0);
    const many = Array.from({ length: 12 }, () => ({ image_data_uri: 'data:image/png;base64,AAAA' }));
    expect(plotImageBlocks(many)).toHaveLength(8);
  });
});

describe('text-only model path (OpenAI-compatible shim)', () => {
  it('turns an image block into a note instead of throwing', () => {
    const msgs = localMessages({ messages: [{ role: 'user', content: [
      { type: 'tool_result', tool_use_id: 't1', content: [{ type: 'text', text: '{"ok":1}' },
        { type: 'image', source: { type: 'base64', media_type: 'image/png', data: B64 } }] }] }] });
    const tool = msgs.find((m: any) => m.role === 'tool');
    expect(tool.content).toContain('not visible to this model');
    expect(tool.content).not.toContain(B64.slice(0, 1000));
  });
});

describe('vision-capable OpenAI-compatible model (OpenRouter)', () => {
  const turn = { messages: [
    { role: 'assistant', content: [{ type: 'tool_use', id: 't1', name: 'run_code', input: {} },
      { type: 'tool_use', id: 't2', name: 'run_code', input: {} }] },
    { role: 'user', content: [
      { type: 'tool_result', tool_use_id: 't1', content: [{ type: 'text', text: '{"ok":1}' },
        { type: 'image', source: { type: 'base64', media_type: 'image/png', data: 'AAAA' } }] },
      { type: 'tool_result', tool_use_id: 't2', content: '{"ok":2}' }] }] };

  it('keeps tool messages contiguous and sends the plot as an image_url part after them', () => {
    const msgs = localMessages(turn, { vision: true });
    expect(msgs.map((m: any) => m.role)).toEqual(['assistant', 'tool', 'tool', 'user']);
    expect(msgs[1].content).toBe('{"ok":1}');
    const parts = msgs[3].content;
    expect(parts[0]).toMatchObject({ type: 'text' });
    expect(parts[0].text).toContain('t1');
    expect(parts[1]).toEqual({ type: 'image_url', image_url: { url: 'data:image/png;base64,AAAA' } });
  });

  it('without vision the same turn has no image part and no extra message', () => {
    const msgs = localMessages(turn);
    expect(msgs.map((m: any) => m.role)).toEqual(['assistant', 'tool', 'tool']);
    expect(JSON.stringify(msgs)).not.toContain('image_url');
  });

  it('reads image support from the provider model listing; unreachable → text', async () => {
    const realFetch = globalThis.fetch;
    globalThis.fetch = (async () => ({ ok: true, json: async () => ({ data: [
      { id: 'v/model', architecture: { input_modalities: ['text', 'image'] } },
      { id: 't/model', architecture: { input_modalities: ['text'] } }] }) })) as any;
    try {
      expect(await modelAcceptsImages({ url: 'https://p.example/api/v1', model: 'v/model' })).toBe(true);
      expect(await modelAcceptsImages({ url: 'https://p.example/api/v1', model: 't/model' })).toBe(false);
      globalThis.fetch = (async () => { throw new Error('down'); }) as any;
      expect(await modelAcceptsImages({ url: 'https://q.example/api/v1', model: 'v/model' })).toBe(false);
    } finally { globalThis.fetch = realFetch; }
  });
});

describe('run_code preview byte cap', () => {
  it('stops attaching previews once the per-run total is reached', async () => {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'img-cap-'));
    try {
      for (const n of ['a.png', 'b.png', 'c.png']) await fs.writeFile(path.join(dir, n), Buffer.alloc(3_000_000, 1));
      const files = await scanOutputDir(dir);
      expect(files.filter(f => f.image_data_uri).length).toBe(2); // 6 MB ≤ 8 MB; a third would exceed it
    } finally {
      await fs.rm(dir, { recursive: true, force: true });
    }
  });
});

describe('reasoning budget (OpenRouter counts reasoning against max_tokens)', () => {
  it('adds a separate reasoning cap on OpenRouter and leaves other endpoints alone', () => {
    expect(reasoningBudgetBody('https://openrouter.ai/api/v1', 4096)).toEqual({ max_tokens: 6144, reasoning: { max_tokens: 2048 } });
    expect(reasoningBudgetBody('http://10.0.0.5:8000/v1', 4096)).toEqual({ max_tokens: 4096 });
    expect(reasoningBudgetBody('https://evil.example/openrouter.ai/v1', 4096)).toEqual({ max_tokens: 4096 });
  });
});

describe('attachmentDisposition (cross-origin downloads of generated files)', () => {
  it('builds an RFC 6266 attachment header with a UTF-8 name', async () => {
    const { attachmentDisposition } = await import('./content-disposition');
    expect(attachmentDisposition('QC_Report.txt')).toBe(`attachment; filename="QC_Report.txt"; filename*=UTF-8''QC_Report.txt`);
    expect(attachmentDisposition('generated/质控报告.txt')).toBe(`attachment; filename="____.txt"; filename*=UTF-8''${encodeURIComponent('质控报告.txt')}`);
    expect(attachmentDisposition('a"b\r\n.csv')).toContain('filename="a_b__.csv"');
  });
});
