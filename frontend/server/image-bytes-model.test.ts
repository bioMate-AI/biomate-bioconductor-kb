import { describe, it, expect } from 'vitest';
import fs from 'fs/promises';
import os from 'os';
import path from 'path';
import { GalaxyAssistant, stripImageBytesForModel, plotImageBlocks } from './galaxy-assistant';
import { localMessages } from './local-llm';
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
