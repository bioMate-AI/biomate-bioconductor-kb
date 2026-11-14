/**
 * E2E (dev): multi-round conversation with MULTIPLE files (PDF + image).
 *
 * Verifies the two fixes shipped in c26262b29 end-to-end on the live dev stack:
 *   1. Reading a PDF never leaks tool-call internals (<function_calls>/<invoke>
 *      XML, import PyPDF2, print(text[:5000])) into the visible answer.
 *   2. An ad-hoc image upload gets a grounded biomedical read (vision path),
 *      not a refusal, and also never leaks.
 *   3. Both hold across a multi-round conversation in one session.
 *
 * API-driven (login -> upload -> /api/chat/stream), following the canonical
 * pdf-upload-research-verify.e2e.ts pattern. No mocks (per CLAUDE.md).
 */
import { test, expect } from '@playwright/test';
import { resolveE2eBaseUrl } from "./_e2e-base-url";
import * as zlib from 'zlib';

const BASE_URL = resolveE2eBaseUrl('https://dev-public.biomate.ai');
const EMAIL = 'lifeifei163361@163.com';
const PASSWORD = process.env.E2E_FIXTURE_PASSWORD || 'WpmFixture!2026';
const E2E_TOKEN = 'biomate-e2e-bypass-token-dev-only';

// A minimal valid PDF whose "Methods" section includes a small table, so we can
// confirm both prose and tabular (technical) detail come through.
const TEST_PDF = Buffer.from(
  '%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n' +
  '2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n' +
  '3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]/Contents 4 0 R' +
  '/Resources<</Font<</F1 5 0 R>>>>>>\nendobj\n' +
  '4 0 obj<</Length 360>>stream\n' +
  'BT /F1 12 Tf 72 720 Td\n' +
  '(Methods: The KRAS-G12C inhibitor was purified by Ni-NTA affinity chromatography.) Tj 0 -20 Td\n' +
  '(Protein was expressed in Sf9 cells and cleaved with TEV protease.) Tj 0 -20 Td\n' +
  '(Table 1 IC50 values: compound A 12 nM; compound B 45 nM; compound C 210 nM.) Tj 0 -20 Td\n' +
  '(Final homogeneity was 95 percent by SDS-PAGE.) Tj\n' +
  'ET\nendstream endobj\n' +
  '5 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj\n' +
  'xref\n0 6\n0000000000 65535 f \n' +
  'trailer<</Size 6/Root 1 0 R>>\nstartxref\n560\n%%EOF'
);

// Build a real, valid NxN PNG (colored bands) with zero external deps so the
// vision model receives genuine pixels — proves the image content block path.
function makePng(size = 24): Buffer {
  const raw = Buffer.alloc(size * (size * 3 + 1));
  let p = 0;
  for (let y = 0; y < size; y++) {
    raw[p++] = 0; // filter byte
    for (let x = 0; x < size; x++) {
      // three horizontal bands: red / green / blue
      const band = Math.floor((y / size) * 3);
      raw[p++] = band === 0 ? 220 : 20;
      raw[p++] = band === 1 ? 200 : 20;
      raw[p++] = band === 2 ? 220 : 20;
    }
  }
  const crcTable = (() => {
    const t: number[] = [];
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      t[n] = c >>> 0;
    }
    return t;
  })();
  const crc32 = (buf: Buffer) => {
    let c = 0xffffffff;
    for (let i = 0; i < buf.length; i++) c = crcTable[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  };
  const chunk = (type: string, data: Buffer) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length, 0);
    const typeBuf = Buffer.from(type, 'ascii');
    const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(Buffer.concat([typeBuf, data])), 0);
    return Buffer.concat([len, typeBuf, data, crc]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0); ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8; ihdr[9] = 2; // 8-bit, RGB
  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  return Buffer.concat([sig, chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}

const TEST_PNG = makePng();

// Assertions that must hold on EVERY assistant response, whatever the model does.
const LEAK_RE = /<\/?(?:antml:)?function_calls|<(?:antml:)?invoke\s+name=|import\s+PyPDF2|print\(text\[|<parameter\s+name=/i;
function assertNoLeak(label: string, text: string) {
  const m = text.match(LEAK_RE);
  expect(m, `${label}: tool-call internals leaked into the answer: ${m?.[0]}`).toBeNull();
}

async function login(request: any): Promise<string> {
  const r = await request.post(`${BASE_URL}/api/auth/login`, {
    headers: { 'x-e2e-test-token': E2E_TOKEN },
    data: { email: EMAIL, password: PASSWORD },
  });
  expect(r.ok(), `login failed: ${r.status()}`).toBeTruthy();
  const { token } = await r.json();
  expect(token, 'no token').toBeTruthy();
  return token;
}

async function upload(request: any, token: string, name: string, mimeType: string, buffer: Buffer): Promise<{ id: string; name: string }> {
  const r = await request.post(`${BASE_URL}/api/datasets/upload`, {
    headers: { Authorization: `Bearer ${token}`, 'x-e2e-test-token': E2E_TOKEN },
    multipart: { file: { name, mimeType, buffer } },
  });
  expect(r.ok(), `upload ${name} failed: ${r.status()} ${await r.text().catch(() => '')}`).toBeTruthy();
  const d = await r.json();
  expect(d.dataset_id, `no dataset_id for ${name}`).toBeTruthy();
  return { id: d.dataset_id, name: d.name || name };
}

async function chat(request: any, token: string, sessionId: string, message: string): Promise<string> {
  const r = await request.post(`${BASE_URL}/api/chat/stream`, {
    headers: { Authorization: `Bearer ${token}`, 'x-e2e-test-token': E2E_TOKEN, Accept: 'text/event-stream' },
    data: { message, sessionId, context: {} },
    timeout: 120_000,
  });
  expect(r.ok(), `chat failed: ${r.status()}`).toBeTruthy();
  const body = await r.text();
  let full = '';
  for (const line of body.split('\n')) {
    const raw = line.startsWith('data:') ? line.slice(5).trim() : null;
    if (!raw || raw === '[DONE]' || raw === '{"ok":true}') continue;
    try {
      const d = JSON.parse(raw);
      if (d.text) full += d.text;
      const cand = d.response || d.content || '';
      if (typeof cand === 'string' && cand.length > full.length) full = cand;
    } catch { /* ignore */ }
  }
  return full;
}

test.describe('multi-round PDF + image, no leak, vision read', () => {
  test.setTimeout(300_000);

  test('reads PDF (no leak), reads image (vision), stays clean across rounds', async ({ request }) => {
    const token = await login(request);
    const sessionId = `e2e-mr-vision-${Date.now()}`;

    const pdf = await upload(request, token, 'kras_methods.pdf', 'application/pdf', TEST_PDF);
    const png = await upload(request, token, 'assay_gel.png', 'image/png', TEST_PNG);
    console.log(`uploaded pdf=${pdf.id} png=${png.id}`);

    // ── Round 1: read the PDF's methods/protocol ─────────────────────────────
    const r1 = await chat(request, token, sessionId,
      `Read the attached paper and summarize the protein purification protocol and the Table 1 IC50 values. [Dataset: ${pdf.name} (id: ${pdf.id})]`);
    console.log(`R1 (${r1.length} chars): ${r1.slice(0, 300)}`);
    assertNoLeak('R1 PDF read', r1);
    expect(r1.trim().length, 'R1 must be substantive').toBeGreaterThan(50);
    expect(r1.includes("I'm having trouble generating a response"), 'R1 not error fallback').toBe(false);
    expect(/Ni-?NTA|TEV|purif|IC50|12 ?nM|SDS-?PAGE|KRAS/i.test(r1), 'R1 must reflect PDF methods/table content').toBe(true);

    // ── Round 2 (same session): ad-hoc image → biomedical read ───────────────
    const r2 = await chat(request, token, sessionId,
      `Here is a gel image from the assay. Give me your biomedical read of what you see. [Dataset: ${png.name} (id: ${png.id})]`);
    console.log(`R2 (${r2.length} chars): ${r2.slice(0, 300)}`);
    assertNoLeak('R2 image read', r2);
    expect(r2.trim().length, 'R2 must be substantive').toBeGreaterThan(50);
    // The model must NOT claim it categorically cannot see images (vision path active).
    const hardRefusal = /I (?:can'?t|cannot|am unable to|don'?t have the ability to) (?:see|view|analyze|process|interpret) (?:the |this |your )?(?:image|picture|photo)/i.test(r2);
    expect(hardRefusal, `R2 must not hard-refuse image analysis. Got: ${r2.slice(0, 200)}`).toBe(false);

    // ── Round 3: follow-up referencing both, no new attachment ───────────────
    const r3 = await chat(request, token, sessionId,
      `Given the paper's IC50 table and the gel, which compound would you prioritize and why?`);
    console.log(`R3 (${r3.length} chars): ${r3.slice(0, 300)}`);
    assertNoLeak('R3 follow-up', r3);
    expect(r3.trim().length, 'R3 must be substantive').toBeGreaterThan(50);

    // ── Round 4: view the image BY ID (no chip, not re-attached) ─────────────
    // The id is given in prose only (no [Dataset:] chip), so _buildImageContentBlocks
    // does NOT attach it — the model must call read_file(id) to see it. The stored
    // PNG has three horizontal bands (red / green / blue). If read_file returns the
    // pixels, the model describes them; if it returned utf8 garbage (the old bug),
    // it can't. Phrased like R2 (a plain inspection question) to avoid the
    // workflow-generation intent route.
    const r4 = await chat(request, token, sessionId,
      `Please look at the image with dataset id ${png.id} and describe the colours and visual pattern in it in detail.`);
    console.log(`R4 (${r4.length} chars): ${r4.slice(0, 300)}`);
    assertNoLeak('R4 read_file image', r4);
    expect(r4.trim().length, 'R4 must be substantive').toBeGreaterThan(50);
    // Must NOT deflect into a workflow card — that means it never viewed the image.
    expect(
      /is ready in the panel|Confirm & Run/i.test(r4),
      `R4 must not deflect to a workflow. Got: ${r4.slice(0, 200)}`,
    ).toBe(false);
    // Must actually describe the image's bands/colours (proves read_file gave pixels).
    expect(
      /\b(red|green|blue|band|stripe|colou?r|horizontal)\b/i.test(r4),
      `R4 must describe the image (read_file returned viewable pixels). Got: ${r4.slice(0, 200)}`,
    ).toBe(true);

    console.log('=== multi-round PDF+image vision + view-by-id: ALL ASSERTIONS PASSED ===');
  });
});
