import { describe, expect, it } from 'vitest';
import { selectReferencedDatasets } from './dataset-reference-selection';

const DATASETS = [
  { id: 'result-a-v1', name: 'result-A.csv', type: 'csv' },
  { id: 'result-b-v2', name: 'result-B.csv', type: 'csv' },
  { id: 'unrelated-v4', name: 'other-result.csv', type: 'csv' },
];

describe('selectReferencedDatasets', () => {
  it('keeps exactly the two files explicitly attached to a comparison request', () => {
    const result = selectReferencedDatasets(DATASETS, [
      { id: 'result-a-v1', name: 'result-A.csv' },
      { id: 'result-b-v2', name: 'result-B.csv' },
    ]);
    expect(result.datasets.map((dataset) => dataset.id)).toEqual(['result-a-v1', 'result-b-v2']);
    expect(result.missingIds).toEqual([]);
  });

  it('never silently substitutes another session file for a missing explicit reference', () => {
    const result = selectReferencedDatasets(DATASETS, [{ id: 'deleted-v1', name: 'result-A.csv' }]);
    expect(result.datasets).toEqual([]);
    expect(result.missingIds).toEqual(['deleted-v1']);
  });

  it('keeps the ordinary session set when the user made no explicit selection', () => {
    expect(selectReferencedDatasets(DATASETS, undefined).datasets).toEqual(DATASETS);
  });
});
