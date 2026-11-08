import { describe, expect, it } from 'vitest';
import { parseInputKinds, INPUT_KIND_VOCAB } from './galaxy-assistant';

// The classifier's input_kinds (what the user HAS) replace the backend's text regex when present.
describe('parseInputKinds', () => {
  it('keeps vocabulary terms only, lower-cased and de-duplicated; [] stays [] (states no data)', () => {
    expect(parseInputKinds(['Protein_Table', 'protein_table', 'mzml', 'fastq'])).toEqual(['protein_table', 'fastq']);
    expect(parseInputKinds([])).toEqual([]);
  });
  it('is undefined when the field is absent or malformed (backend falls back to text detection)', () => {
    expect(parseInputKinds(undefined)).toBeUndefined();
    expect(parseInputKinds('fastq')).toBeUndefined();
  });
  it('matches the backend vocabulary size', () => {
    expect(INPUT_KIND_VOCAB.length).toBe(22);
  });
});
