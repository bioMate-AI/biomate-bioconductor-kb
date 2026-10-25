import { describe, it, expect } from 'vitest';
import { formatMetricValue, findingEntityLabel, type FindingEntity } from './findings';

describe('formatMetricValue — never a bare number', () => {
  it('appends units', () => {
    expect(formatMetricValue({ value: 0.875, units: '' })).toBe('0.875');
    expect(formatMetricValue({ value: '-1.2', units: 'kcal/mol' })).toBe('-1.2 kcal/mol');
  });
  it('preserves a censored inequality (never coerced)', () => {
    expect(formatMetricValue({ value: 30, units: 'µM', comparator: '>' })).toBe('> 30 µM');
    expect(formatMetricValue({ value: 0.012, units: 'µM', comparator: '<' })).toBe('< 0.012 µM');
  });
  it('omits an explicit equals', () => {
    expect(formatMetricValue({ value: '432.4246', units: 'µM', comparator: '=' })).toBe('432.4246 µM');
  });
});

describe('findingEntityLabel — honest identity states', () => {
  const base: FindingEntity = { type: 'compound', label: 'caffeine', scope: 'per_entity' };
  it('shows the plain label for a per-entity result', () => {
    expect(findingEntityLabel(base)).toBe('caffeine');
  });
  it('marks a batch-level value as not attributed to one entity', () => {
    expect(findingEntityLabel({ ...base, label: 'hERG IC50', scope: 'batch' })).toBe('hERG IC50 (batch)');
    expect(findingEntityLabel({ type: 'none', label: '', scope: 'batch' })).toBe('Batch-level');
  });
  it('flags unresolved identity instead of fabricating one', () => {
    expect(findingEntityLabel({ ...base, label: 'row 4', identitySource: 'unresolved' }))
      .toBe('row 4 (unattributed)');
  });
  it('labels a run-level/global metric', () => {
    expect(findingEntityLabel({ type: 'none', label: 'N50', scope: 'global' })).toBe('N50');
  });
});
