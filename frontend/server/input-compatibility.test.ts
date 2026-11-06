import { describe, it, expect } from 'vitest';
import {
  parseHeaderColumns,
  checkTabularCompatibility,
  formatFromName,
  type FileSchema,
} from './input-compatibility';

const f = (name: string, columns: string[], format = 'csv'): FileSchema => ({ name, format, columns });

describe('parseHeaderColumns', () => {
  it('parses a CSV header', () => {
    expect(parseHeaderColumns('gene,value\nTP53,1', 'csv')).toEqual(['gene', 'value']);
  });
  it('parses a TSV header', () => {
    expect(parseHeaderColumns('gene\tvalue\nTP53\t1', 'tsv')).toEqual(['gene', 'value']);
  });
  it('strips quotes/whitespace', () => {
    expect(parseHeaderColumns('"gene", "value" ', 'csv')).toEqual(['gene', 'value']);
  });
  it('auto-detects tab delimiter when format unknown', () => {
    expect(parseHeaderColumns('a\tb\tc')).toEqual(['a', 'b', 'c']);
  });
  it('returns [] for empty header', () => {
    expect(parseHeaderColumns('', 'csv')).toEqual([]);
    expect(parseHeaderColumns('\n\n', 'csv')).toEqual([]);
  });
});

describe('formatFromName', () => {
  it('extracts lowercase extension', () => {
    expect(formatFromName('comparison-a.CSV')).toBe('csv');
    expect(formatFromName('noext')).toBe('');
  });
});

describe('checkTabularCompatibility', () => {
  it('is compatible for identical column sets', () => {
    const r = checkTabularCompatibility([f('a.csv', ['gene', 'value']), f('b.csv', ['gene', 'value'])]);
    expect(r.compatible).toBe(true);
    expect(r.sharedColumns).toEqual(['gene', 'value']);
    expect(r.needsTypedMapping).toBe(false);
  });

  it('is compatible when column order differs (set equality)', () => {
    const r = checkTabularCompatibility([f('a.csv', ['gene', 'value']), f('b.csv', ['value', 'gene'])]);
    expect(r.compatible).toBe(true);
  });

  it('is incompatible across different formats', () => {
    const r = checkTabularCompatibility([f('a.csv', ['gene'], 'csv'), f('b.vcf', [], 'vcf')]);
    expect(r.compatible).toBe(false);
    expect(r.reason).toMatch(/different formats/i);
  });

  it('requests a typed mapping when names differ but arity matches', () => {
    const r = checkTabularCompatibility([f('a.csv', ['gene', 'value']), f('b.csv', ['symbol', 'score'])]);
    expect(r.compatible).toBe(false);
    expect(r.needsTypedMapping).toBe(true);
    expect(r.suggestedMapping).toEqual([
      { file: 'b.csv', map: [{ from: 'symbol', to: 'gene' }, { from: 'score', to: 'value' }] },
    ]);
  });

  it('is incompatible (no mapping) when column counts differ', () => {
    const r = checkTabularCompatibility([f('a.csv', ['gene', 'value']), f('b.csv', ['gene'])]);
    expect(r.compatible).toBe(false);
    expect(r.needsTypedMapping).toBe(false);
    expect(r.reason).toMatch(/different column counts/i);
    expect(r.perFile.find((p) => p.name === 'b.csv')?.missing).toContain('value');
  });

  it('treats a single file as trivially compatible', () => {
    expect(checkTabularCompatibility([f('a.csv', ['gene'])]).compatible).toBe(true);
  });
});
