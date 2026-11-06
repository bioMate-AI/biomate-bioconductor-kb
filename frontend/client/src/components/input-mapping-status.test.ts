import { describe, it, expect } from 'vitest';
import {
  datasetForValue,
  mismatchForParam,
  deriveInputMappingRows,
  blockingInputRows,
  runIsBlockedByInputs,
  type SessionDataset,
  type ParamDef,
} from './input-mapping-status';

const DS: SessionDataset[] = [
  { id: 'ds-1', name: 'counts.csv', file_path: 's3://b/counts.csv' },
  { id: 'ds-2', name: 'design.tsv', source_url: 'https://x/design.tsv' },
];

describe('datasetForValue', () => {
  it('resolves by file_path, source_url, id, or name', () => {
    expect(datasetForValue('s3://b/counts.csv', DS)?.id).toBe('ds-1');
    expect(datasetForValue('https://x/design.tsv', DS)?.id).toBe('ds-2');
    expect(datasetForValue('ds-1', DS)?.id).toBe('ds-1');
    expect(datasetForValue('design.tsv', DS)?.id).toBe('ds-2');
  });
  it('returns null for empty/unmatched values', () => {
    expect(datasetForValue('', DS)).toBeNull();
    expect(datasetForValue(undefined, DS)).toBeNull();
    expect(datasetForValue(null, DS)).toBeNull();
    expect(datasetForValue('nope', DS)).toBeNull();
  });
});

describe('mismatchForParam', () => {
  const defs: ParamDef[] = [{ name: 'reads', format_mismatch_warning: 'expected FASTQ, got CSV' }, { name: 'ref' }];
  it('returns the declared warning, else null (never a fabricated ok)', () => {
    expect(mismatchForParam('reads', defs)).toBe('expected FASTQ, got CSV');
    expect(mismatchForParam('ref', defs)).toBeNull();
    expect(mismatchForParam('absent', defs)).toBeNull();
    expect(mismatchForParam(undefined, defs)).toBeNull();
  });
});

describe('deriveInputMappingRows + run-block condition', () => {
  it('marks a bound input resolved (compat not fabricated) and does NOT block', () => {
    const rows = deriveInputMappingRows(
      [{ id: 'counts', name: 'counts', type: 'file', required: true, value: 'ds-1' }],
      DS,
      [{ name: 'counts' }],
    );
    expect(rows[0].status).toBe('resolved');
    expect(rows[0].dataset?.id).toBe('ds-1');
    expect(rows[0].mismatch).toBeNull();
    expect(runIsBlockedByInputs(rows)).toBe(false);
  });

  it('blocks when a REQUIRED input is unset', () => {
    const rows = deriveInputMappingRows(
      [{ id: 'counts', name: 'counts', type: 'file', required: true, value: '' }],
      DS,
      [],
    );
    expect(rows[0].status).toBe('unresolved');
    expect(runIsBlockedByInputs(rows)).toBe(true);
    expect(blockingInputRows(rows)).toHaveLength(1);
  });

  it('does NOT block when an OPTIONAL input is empty', () => {
    const rows = deriveInputMappingRows(
      [{ id: 'extra', name: 'extra', type: 'file', required: false, value: '' }],
      DS,
      [],
    );
    expect(rows[0].status).toBe('optional-empty');
    expect(runIsBlockedByInputs(rows)).toBe(false);
  });

  it('blocks a bound-but-mismatched input (needs-mapping), even when a value is present', () => {
    const rows = deriveInputMappingRows(
      [{ id: 'reads', name: 'reads', type: 'file', required: true, value: 'ds-1' }],
      DS,
      [{ name: 'reads', format_mismatch_warning: 'expected FASTQ, got CSV' }],
    );
    expect(rows[0].status).toBe('needs-mapping');
    expect(rows[0].mismatch).toContain('FASTQ');
    expect(runIsBlockedByInputs(rows)).toBe(true);
  });

  it('required-and-empty outranks a mismatch (unresolved wins) so the block reason is the missing file', () => {
    const rows = deriveInputMappingRows(
      [{ id: 'reads', name: 'reads', type: 'file', required: true, value: '' }],
      DS,
      [{ name: 'reads', format_mismatch_warning: 'ignored while empty' }],
    );
    expect(rows[0].status).toBe('unresolved');
  });

  it('mixed set: blocks on the one unresolved required input, keeps the resolved one', () => {
    const rows = deriveInputMappingRows(
      [
        { id: 'counts', name: 'counts', type: 'file', required: true, value: 'ds-1' },
        { id: 'design', name: 'design', type: 'file', required: true, value: '' },
      ],
      DS,
      [],
    );
    expect(rows.map(r => r.status)).toEqual(['resolved', 'unresolved']);
    expect(blockingInputRows(rows).map(r => r.param.id)).toEqual(['design']);
    expect(runIsBlockedByInputs(rows)).toBe(true);
  });
});
