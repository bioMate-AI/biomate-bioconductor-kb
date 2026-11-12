import { describe, it, expect } from 'vitest';
import { sampleDataTable, parseListParam } from './nextflow-workflow-viewer';

// The "built-in sample data" an example runs on is the workflow's default
// params. These assert the readable preview against the REAL default shapes of
// the immunology workflows, so an evaluator can see the data pre-run.
describe('sampleDataTable — readable built-in-data preview', () => {
  it('renders an object-of-objects (EBV ELISA raw_od_data) as a per-sample table', () => {
    const raw = '{"sample1": {"VCA_IgG": 0.85, "VCA_IgM": 0.12}, "sample2": {"VCA_IgG": 1.2, "VCA_IgM": 0.65}}';
    const t = sampleDataTable(raw)!;
    expect(t.headers).toEqual(['', 'VCA_IgG', 'VCA_IgM']);
    expect(t.rows).toEqual([['sample1', '0.85', '0.12'], ['sample2', '1.2', '0.65']]);
  });

  it('renders an array-of-objects (bcell antigens) as a columns=keys table', () => {
    const raw = '[{"id":"demo_antigen","sequence":"MKLVTS"}]';
    const t = sampleDataTable(raw)!;
    expect(t.headers).toEqual(['id', 'sequence']);
    expect(t.rows).toEqual([['demo_antigen', 'MKLVTS']]);
  });

  it('renders an object with array values (standard_curve_data) as key/value', () => {
    const raw = '{"IgG": [[10, 0.15], [50, 0.45]], "IgM": [[5, 0.08]]}';
    const t = sampleDataTable(raw)!;
    expect(t.headers).toEqual(['key', 'value']);
    expect(t.rows[0][0]).toBe('IgG');
    expect(t.rows[0][1]).toBe('[[10,0.15],[50,0.45]]');
  });

  it('returns null for scalars, scalar arrays and non-JSON (plain editor stays)', () => {
    expect(sampleDataTable('CD19')).toBeNull();
    expect(sampleDataTable('["GILGFVFTL","SIINFEKL"]')).toBeNull(); // scalar array → list editor
    expect(sampleDataTable('not json {')).toBeNull();
    expect(sampleDataTable('{}')).toBeNull();
  });
});

describe('parseListParam — only scalar arrays get the one-item-per-row editor', () => {
  it('keeps a scalar array (mhc peptides/alleles) as an editable list', () => {
    expect(parseListParam({ value: '["GILGFVFTL","SIINFEKL","NLVPMVATV"]' })).toEqual({
      items: ['GILGFVFTL', 'SIINFEKL', 'NLVPMVATV'], fmt: 'json',
    });
    expect(parseListParam({ value: ['HLA-A*02:01', 'HLA-B*07:02'] })).toEqual({
      items: ['HLA-A*02:01', 'HLA-B*07:02'], fmt: 'array',
    });
  });

  it('rejects an array of objects so it is not mangled into "[object Object]" rows', () => {
    expect(parseListParam({ value: '[{"id":"demo_antigen","sequence":"MKLVTS"}]' })).toBeNull();
    expect(parseListParam({ value: [{ id: 'x' }] })).toBeNull();
  });
});
