import { describe, it, expect } from 'vitest';
import { parseOutputFormats, outputRequirementsToPrompt, EXAMPLE_OUTPUT_FORMATS, exampleOutputFormats, appendMissingOutputFormats } from './output-requirements';

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
