import { describe, it, expect } from 'vitest';
import {
  datasetForValue,
  mismatchForParam,
  deriveInputMappingRows,
  blockingInputRows,
  runIsBlockedByInputs,
  derivePrerunInputs,
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


describe('derivePrerunInputs (rnaseq-like schema)', () => {
  // As buildViewerParameters renders nf-core/rnaseq: the required samplesheet
  // `input` is a STRING param; references are optional FILE params whose value
  // falls back to the default (null, or a pipeline default like the rRNA manifest).
  const params = [
    { id: 'input', name: 'input', label: 'Input', type: 'string', required: true, value: '', defaultValue: null },
    { id: 'genome', name: 'genome', label: 'Genome', type: 'string', required: false, value: 'GRCh38', defaultValue: null },
    { id: 'fasta', name: 'fasta', label: 'Fasta', type: 'file', required: false, value: '', defaultValue: null },
    { id: 'gtf', name: 'gtf', label: 'Gtf', type: 'file', required: false, value: '', defaultValue: null },
    { id: 'ribo_database_manifest', name: 'ribo_database_manifest', label: 'Ribo Database Manifest', type: 'file', required: false, value: 'rrna-db-defaults.txt', defaultValue: 'rrna-db-defaults.txt' },
  ];
  const defs: ParamDef[] = [
    { name: 'input', type: 'string', description: 'Samplesheet CSV' },
    { name: 'fasta', type: 'file' },
    { name: 'gtf', type: 'file' },
    { name: 'ribo_database_manifest', type: 'file' },
  ];

  it('lists the required samplesheet as the primary input even though it is not typed file', () => {
    const m = derivePrerunInputs(params, DS, defs);
    expect(m.primary.map(r => r.param.id)).toEqual(['input']);
    expect(m.primary[0].status).toBe('unresolved');
    expect(m.requiredCount).toBe(1);
    expect(m.requiredUnset).toBe(1);
    expect(m.boundCount).toBe(0);
    expect(runIsBlockedByInputs([...m.primary, ...m.overrides])).toBe(true);
  });

  it('groups default-backed reference files as overrides, not as mapped inputs', () => {
    const m = derivePrerunInputs(params, DS, defs);
    expect(m.overrides.map(r => r.param.id)).toEqual(['fasta', 'gtf', 'ribo_database_manifest']);
    expect(m.overrides.map(r => r.status)).toEqual(['optional-empty', 'optional-empty', 'resolved']);
    // Plain settings (genome) are neither inputs nor overrides.
    expect([...m.primary, ...m.overrides].some(r => r.param.id === 'genome')).toBe(false);
  });

  it('binding the samplesheet resolves it; a user-bound optional file becomes a mapped input', () => {
    const bound = params.map(p =>
      p.id === 'input' ? { ...p, value: 's3://b/counts.csv' }
      : p.id === 'gtf' ? { ...p, value: 'https://x/design.tsv' } : p);
    const m = derivePrerunInputs(bound, DS, defs);
    expect(m.primary.map(r => [r.param.id, r.status])).toEqual([['input', 'resolved'], ['gtf', 'resolved']]);
    expect(m.requiredUnset).toBe(0);
    expect(m.boundCount).toBe(2);
    expect(m.overrides.map(r => r.param.id)).toEqual(['fasta', 'ribo_database_manifest']);
    expect(runIsBlockedByInputs([...m.primary, ...m.overrides])).toBe(false);
  });

  it('uses schema metadata from the param defs (data_input flag) for optional data files', () => {
    const m = derivePrerunInputs(
      [{ id: 'sce2', name: 'sce2', type: 'file', required: false, value: '' }],
      DS,
      [{ name: 'sce2', type: 'file', data_input: true }],
    );
    expect(m.primary.map(r => [r.param.id, r.status])).toEqual([['sce2', 'optional-empty']]);
    expect(m.overrides).toEqual([]);
  });
});
