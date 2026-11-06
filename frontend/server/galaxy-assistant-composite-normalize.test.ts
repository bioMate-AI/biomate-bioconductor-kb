import { describe, it, expect } from 'vitest';
import { normalizeCompositeDatasetRef } from './galaxy-assistant.js';

// Regression for the cryo "Dataset Id" composite leak: an uploaded-dataset context
// entry ("<id>, s3_uri=<uri>") reached the Dataset Id param instead of a clean token.
// It leaked through the inlineParameters map (merged into the viewer's params as the
// top-precedence userValue), which value/default normalization never touched.
describe('normalizeCompositeDatasetRef', () => {
  it('strips the exact leaked cryo value (uuid + s3_uri, trailing "]")', () => {
    const leaked =
      '3db52842-665a-438f-8911-44ba6feaef24, s3_uri=s3://biomate-nextflow-work/uploads/3db52842-665a-438f-8911-44ba6feaef24/cryo_inputs.json]';
    expect(normalizeCompositeDatasetRef(leaked)).toBe('3db52842-665a-438f-8911-44ba6feaef24');
  });

  it('strips galaxy_dataset_id and dataset_id composite forms', () => {
    expect(normalizeCompositeDatasetRef('abc123, galaxy_dataset_id=42')).toBe('abc123');
    expect(normalizeCompositeDatasetRef('abc123, dataset_id=xyz')).toBe('abc123');
    expect(normalizeCompositeDatasetRef('abc123, name=reads.fastq')).toBe('abc123');
  });

  it('strips an s3:// uri composite down to the leading s3 uri', () => {
    expect(
      normalizeCompositeDatasetRef('s3://bucket/uploads/x/reads.fastq, s3_uri=s3://bucket/uploads/x/reads.fastq'),
    ).toBe('s3://bucket/uploads/x/reads.fastq');
  });

  it('leaves a clean single token unchanged', () => {
    expect(normalizeCompositeDatasetRef('3db52842-665a-438f-8911-44ba6feaef24')).toBe(
      '3db52842-665a-438f-8911-44ba6feaef24',
    );
    expect(normalizeCompositeDatasetRef('s3://bucket/path/reads.fastq')).toBe('s3://bucket/path/reads.fastq');
    expect(normalizeCompositeDatasetRef('GRCh38')).toBe('GRCh38');
  });

  it('does not mangle legitimate comma-bearing values that are not dataset composites', () => {
    // No "<key>=" after the comma → not a composite, leave intact.
    expect(normalizeCompositeDatasetRef('treated, untreated')).toBe('treated, untreated');
    expect(normalizeCompositeDatasetRef('gene1,gene2,gene3')).toBe('gene1,gene2,gene3');
  });

  it('passes non-string values through untouched', () => {
    expect(normalizeCompositeDatasetRef(42)).toBe(42);
    expect(normalizeCompositeDatasetRef(true)).toBe(true);
    expect(normalizeCompositeDatasetRef(null)).toBe(null);
    expect(normalizeCompositeDatasetRef(undefined)).toBe(undefined);
  });
});
