import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { _buildImageContentBlocks, GalaxyAssistant } from './galaxy-assistant';
import { mkdirSync, writeFileSync, rmSync, existsSync } from 'fs';
import { join } from 'path';

// Integration test for the ad-hoc image → biomedical-opinion vision path.
// _buildImageContentBlocks resolves attached image chips to local files via the
// routes uploaded-file registry, which falls back to scanning <cwd>/data/uploads
// for "<datasetId>.<ext>". We drop real files there and assert the Anthropic
// image content blocks are built correctly, with size-gating, unsupported-type
// skipping, dedup, and the per-turn image cap all exercised together.

const uploadsDir = join(process.cwd(), 'data', 'uploads', 'vision-test');
// Injected resolver maps a dataset id → the temp file we wrote for it. Mirrors
// what the routes registry does, without importing the heavy routes module.
const idToPath = new Map<string, string>();
const resolve = (id: string) => {
  const filePath = idToPath.get(id);
  return filePath ? { filePath } : undefined;
};
const ids = {
  png: 'aaaaaaaa-0000-0000-0000-000000000001',
  jpg: 'aaaaaaaa-0000-0000-0000-000000000002',
  tiff: 'aaaaaaaa-0000-0000-0000-000000000003',
  huge: 'aaaaaaaa-0000-0000-0000-000000000004',
  csv: 'aaaaaaaa-0000-0000-0000-000000000005',
  webp: 'aaaaaaaa-0000-0000-0000-000000000006',
};
const created: string[] = [];

function put(id: string, ext: string, bytes: Buffer) {
  const p = join(uploadsDir, `${id}.${ext}`);
  writeFileSync(p, bytes);
  created.push(p);
  idToPath.set(id, p);
}

beforeAll(() => {
  mkdirSync(uploadsDir, { recursive: true });
  put(ids.png, 'png', Buffer.from('fake-png-bytes-for-a-histology-slide'));
  put(ids.jpg, 'jpg', Buffer.from('fake-jpeg-bytes-for-a-western-blot'));
  put(ids.tiff, 'tiff', Buffer.from('fake-tiff-bytes'));
  put(ids.huge, 'png', Buffer.alloc(4_000_000, 1)); // > 3.75MB → size-gated
  put(ids.csv, 'csv', Buffer.from('a,b\n1,2'));
  put(ids.webp, 'webp', Buffer.from('fake-webp-bytes'));
});

afterAll(() => {
  for (const p of created) { try { if (existsSync(p)) rmSync(p); } catch { /* ignore */ } }
  try { if (existsSync(uploadsDir)) rmSync(uploadsDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

describe('_buildImageContentBlocks — multi-file', () => {
  it('attaches supported images, skips oversized + unsupported, ignores non-images', async () => {
    const message =
      `Please give a biomedical read on these. ` +
      `[Dataset: slide.png (id: ${ids.png})] ` +
      `[Dataset: blot.jpg (id: ${ids.jpg})] ` +
      `[Dataset: scan.tiff (id: ${ids.tiff})] ` +
      `[Dataset: huge.png (id: ${ids.huge})] ` +
      `[Dataset: counts.csv (id: ${ids.csv})]`;

    const { blocks, attached, skipped } = await _buildImageContentBlocks(message, resolve);

    // png + jpg attached
    expect(attached.sort()).toEqual(['blot.jpg', 'slide.png']);
    expect(blocks).toHaveLength(2);
    for (const b of blocks) {
      expect(b.type).toBe('image');
      expect(b.source.type).toBe('base64');
      expect(['image/png', 'image/jpeg']).toContain(b.source.media_type);
      expect(typeof b.source.data).toBe('string');
      expect(b.source.data.length).toBeGreaterThan(0);
    }

    // tiff (unsupported) and huge.png (oversized) both reported as skipped
    const skippedNames = skipped.map((s) => s.name).sort();
    expect(skippedNames).toEqual(['huge.png', 'scan.tiff']);
    expect(skipped.find((s) => s.name === 'scan.tiff')!.reason).toMatch(/not a format/i);
    expect(skipped.find((s) => s.name === 'huge.png')!.reason).toMatch(/limit|MB/i);

    // csv is a non-image → silently ignored (neither attached nor skipped)
    expect(skippedNames).not.toContain('counts.csv');
    expect(attached).not.toContain('counts.csv');
  });

  it('correctly maps media types including webp', async () => {
    const message = `[Dataset: fig.webp (id: ${ids.webp})]`;
    const { blocks, attached } = await _buildImageContentBlocks(message, resolve);
    expect(attached).toEqual(['fig.webp']);
    expect(blocks[0].source.media_type).toBe('image/webp');
  });

  it('de-duplicates the same file referenced twice', async () => {
    const message = `[Dataset: slide.png (id: ${ids.png})] and again [Dataset: slide.png (id: ${ids.png})]`;
    const { blocks } = await _buildImageContentBlocks(message, resolve);
    expect(blocks).toHaveLength(1);
  });

  it('supports the legacy [Uploaded datasets: …] chip format', async () => {
    const message =
      `[Attached files: slide.png]\n[Uploaded datasets: slide.png: dataset_id=${ids.png}]`;
    const { attached, blocks } = await _buildImageContentBlocks(message, resolve);
    expect(attached).toEqual(['slide.png']);
    expect(blocks).toHaveLength(1);
  });

  it('returns nothing for a message with no attachments', async () => {
    const { blocks, attached, skipped } = await _buildImageContentBlocks('just a text question about TP53', resolve);
    expect(blocks).toHaveLength(0);
    expect(attached).toHaveLength(0);
    expect(skipped).toHaveLength(0);
  });

  it('caps the number of images per turn at 8', async () => {
    // Create 10 tiny pngs and reference them all.
    const capIds: string[] = [];
    const parts: string[] = [];
    for (let i = 0; i < 10; i++) {
      const id = `bbbbbbbb-0000-0000-0000-0000000000${String(i).padStart(2, '0')}`;
      put(id, 'png', Buffer.from(`img-${i}`));
      capIds.push(id);
      parts.push(`[Dataset: img${i}.png (id: ${id})]`);
    }
    const { blocks, skipped } = await _buildImageContentBlocks(parts.join(' '), resolve);
    expect(blocks).toHaveLength(8);
    // The 2 beyond the cap are reported, not silently dropped.
    expect(skipped.filter((s) => /images are analyzed/i.test(s.reason))).toHaveLength(2);
  });
});

describe('GalaxyAssistant.toolResultContent — on-demand image view by id', () => {
  it('passes an image tool output through as text + image blocks', () => {
    const out = {
      __imageBlocks: [{ type: 'image', source: { type: 'base64', media_type: 'image/png', data: 'QUJD' } }],
      format_hint: 'image',
      message: 'Image "gel.png" is shown below.',
    };
    const content = GalaxyAssistant.toolResultContent(out) as any[];
    expect(Array.isArray(content)).toBe(true);
    expect(content[0].type).toBe('text');
    // The base64 goes in the image block, not duplicated into the text block.
    expect(content[0].text).not.toContain('QUJD');
    expect(content[0].text).toContain('gel.png');
    expect(content[1]).toEqual(out.__imageBlocks[0]);
  });

  it('stringifies a normal (non-image) tool output', () => {
    const out = { lines: ['a', 'b'], format_hint: 'CSV', has_more: false };
    const content = GalaxyAssistant.toolResultContent(out);
    expect(typeof content).toBe('string');
    expect(JSON.parse(content as string)).toEqual(out);
  });
});
