import { describe, it, expect } from 'vitest';
import { parseOutputFormats, outputRequirementsToPrompt, EXAMPLE_OUTPUT_FORMATS, exampleOutputFormats, appendMissingOutputFormats, parseOutputRequirements, checkOutputConformance } from './output-requirements';

describe('output-requirements store parsing', () => {
  it('parses a JSON array of formats', () => {
    const raw = JSON.stringify([{ kind: 'figure', name: 'Fig spec', detail: 'SVG', on: true }]);
    expect(parseOutputFormats(raw)).toEqual([{ kind: 'figure', name: 'Fig spec', detail: 'SVG', on: true }]);
  });
  it('treats legacy free text as a single enabled report (no data lost)', () => {
    const got = parseOutputFormats('Write a two-page memo');
    expect(got).toHaveLength(1);
    expect(got[0]).toMatchObject({ kind: 'report', detail: 'Write a two-page memo', on: true });
  });
  it('coerces an unknown kind to report and empty detail to ""', () => {
    const got = parseOutputFormats(JSON.stringify([{ kind: 'weird', name: 'X' }]));
    expect(got[0].kind).toBe('report');
    expect(got[0].detail).toBe('');
    expect(got[0].on).toBe(true); // on defaults true unless explicitly false
  });
  it('returns [] for empty/blank input', () => {
    expect(parseOutputFormats('')).toEqual([]);
    expect(parseOutputFormats('   ')).toEqual([]);
    expect(parseOutputFormats(null)).toEqual([]);
  });
});

describe('outputRequirementsToPrompt — only enabled formats reach the model', () => {
  it('OMITS formats switched off (the bug being fixed)', () => {
    const raw = JSON.stringify([
      { kind: 'report', name: 'Keep me', detail: 'on', on: true },
      { kind: 'table', name: 'Drop me', detail: 'off', on: false },
    ]);
    const prompt = outputRequirementsToPrompt(raw);
    expect(prompt).toContain('Keep me');
    expect(prompt).not.toContain('Drop me');
  });
  it('renders prose, not raw JSON', () => {
    const raw = JSON.stringify([{ kind: 'figure', name: 'Fig', detail: 'SVG, 8pt', on: true }]);
    const prompt = outputRequirementsToPrompt(raw);
    expect(prompt).not.toContain('{');
    expect(prompt).not.toContain('"kind"');
    expect(prompt).toMatch(/Figure — Fig: SVG, 8pt/);
  });
  it('returns "" when nothing is enabled (honest-empty)', () => {
    const raw = JSON.stringify([{ kind: 'report', name: 'Off', detail: 'x', on: false }]);
    expect(outputRequirementsToPrompt(raw)).toBe('');
    expect(outputRequirementsToPrompt('')).toBe('');
  });
  it('a bare example (seeded off) contributes nothing until switched on', () => {
    // seeding examples must never silently take effect
    const seeded = JSON.stringify(EXAMPLE_OUTPUT_FORMATS);
    expect(outputRequirementsToPrompt(seeded)).toBe('');
    expect(EXAMPLE_OUTPUT_FORMATS.every(f => f.on === false)).toBe(true);
    // once a user turns one on, it appears
    const oneOn = JSON.stringify(EXAMPLE_OUTPUT_FORMATS.map((f, i) => i === 0 ? { ...f, on: true } : f));
    expect(outputRequirementsToPrompt(oneOn)).toContain(EXAMPLE_OUTPUT_FORMATS[0].name);
  });
});


describe('parseOutputRequirements — structured hints for non-LLM / server generators', () => {
  it('extracts only ENABLED formats (a switched-off format never contributes a hint)', () => {
    const raw = JSON.stringify([
      { kind: 'report', name: 'memo', detail: 'Findings first (≤200 words). 300 dpi greyscale.', on: true },
      { kind: 'report', name: 'off', detail: '≤50 words', on: false },
    ]);
    const r = parseOutputRequirements(raw);
    expect(r.formats).toHaveLength(1);
    expect(r.lengthCapWords).toBe(200); // not 50 — the 50-word format is off
    expect(r.findingsFirst).toBe(true);
    expect(r.figureDpi).toBe(300);
    expect(r.grayscaleSafe).toBe(true);
  });
  it('keeps the MOST restrictive word cap across enabled formats', () => {
    const raw = JSON.stringify([
      { kind: 'report', name: 'a', detail: 'no more than 300 words', on: true },
      { kind: 'report', name: 'b', detail: 'at most 120 words', on: true },
    ]);
    expect(parseOutputRequirements(raw).lengthCapWords).toBe(120);
  });
  it('parses varied phrasings of the word cap', () => {
    for (const d of ['≤200 words', '<= 200 words', 'under 200 words', 'max 200 words', 'up to 200 words', '200 words']) {
      const raw = JSON.stringify([{ kind: 'report', name: 'x', detail: d, on: true }]);
      expect(parseOutputRequirements(raw).lengthCapWords).toBe(200);
    }
  });
  it('is empty-safe: no formats ⇒ no hints', () => {
    const r = parseOutputRequirements('');
    expect(r.formats).toEqual([]);
    expect(r.lengthCapWords).toBeUndefined();
    expect(r.findingsFirst).toBeUndefined();
    expect(r.figureDpi).toBeUndefined();
    expect(r.grayscaleSafe).toBeUndefined();
  });
});

describe('checkOutputConformance — cheap, non-blocking, never fabricates', () => {
  it('flags a prose output that exceeds the word cap (beyond 10% tolerance)', () => {
    const reqs = parseOutputRequirements(JSON.stringify([{ kind: 'report', name: 'x', detail: '≤10 words', on: true }]));
    const long = Array.from({ length: 30 }, (_, i) => `w${i}`).join(' ');
    expect(checkOutputConformance(long, reqs)[0]).toMatch(/length cap/);
  });
  it('does NOT flag output within the cap (plus tolerance)', () => {
    const reqs = parseOutputRequirements(JSON.stringify([{ kind: 'report', name: 'x', detail: '≤10 words', on: true }]));
    expect(checkOutputConformance('one two three four five', reqs)).toEqual([]);
  });
  it('flags findings-first when methods are introduced before any finding/result', () => {
    const reqs = parseOutputRequirements(JSON.stringify([{ kind: 'report', name: 'x', detail: 'findings first', on: true }]));
    const dev = checkOutputConformance('METHODS: we aligned reads. RESULTS: 42 variants.', reqs);
    expect(dev.join(' ')).toMatch(/findings-first/);
  });
  it('does NOT flag when findings/results come first', () => {
    const reqs = parseOutputRequirements(JSON.stringify([{ kind: 'report', name: 'x', detail: 'findings first', on: true }]));
    expect(checkOutputConformance('RESULTS: 42 variants. METHODS: we aligned reads.', reqs)).toEqual([]);
  });
  it('returns [] for empty text or null reqs (safe, non-throwing)', () => {
    expect(checkOutputConformance('', parseOutputRequirements(''))).toEqual([]);
    expect(checkOutputConformance('anything', null)).toEqual([]);
    expect(checkOutputConformance(null, parseOutputRequirements('x'))).toEqual([]);
  });
});

describe('translated built-in output formats', () => {
  it('does not add translated duplicates or change existing enabled formats', () => {
    const saved = EXAMPLE_OUTPUT_FORMATS.map(format => ({ ...format, on: true }));
    expect(appendMissingOutputFormats(saved, exampleOutputFormats('zh'))).toEqual(saved);
    const chinese = exampleOutputFormats('zh');
    expect(chinese[0].name).toBe('内部备忘录');
    expect(appendMissingOutputFormats(chinese, exampleOutputFormats('en'))).toEqual(chinese);
    expect(outputRequirementsToPrompt(JSON.stringify(chinese))).toBe('');
  });
  it('preserves a user-edited template while adding the original example', () => {
    const custom = { ...exampleOutputFormats('zh')[0], detail: '保留用户自定义要求', on: true };
    const next = appendMissingOutputFormats([custom], [EXAMPLE_OUTPUT_FORMATS[0]]);
    expect(next).toHaveLength(2);
    expect(next[0]).toEqual(custom);
    expect(next[1].on).toBe(false);
  });
});
