import { describe, it, expect } from 'vitest';
import {
  datasetForValue,
  mismatchForParam,
  perceptionMismatch,
  expectedViewKindsForParam,
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

describe('perceptionMismatch / expectedViewKindsForParam', () => {
  it('maps param families to accepted viewKinds', () => {
    expect([...expectedViewKindsForParam('reads')!]).toEqual(['reads']);
    expect(expectedViewKindsForParam('bam')!.has('alignment')).toBe(true);
    expect(expectedViewKindsForParam('samplesheet')!.has('table')).toBe(true);
    expect(expectedViewKindsForParam('genome')).toBeNull();
  });
  it('flags CSV on reads; accepts FASTQ; skips blocked quality', () => {
    expect(perceptionMismatch('reads', { id: '1', name: 'x.csv' })).toMatch(/table/);
    expect(perceptionMismatch('reads', { id: '1', name: 'x.fastq.gz', viewKind: 'reads' })).toBeNull();
    expect(perceptionMismatch('bam', { id: '1', name: 'x.bam', viewKind: 'reads' })).toMatch(/alignment/);
    expect(perceptionMismatch('reads', { id: '1', name: 'x.csv', quality: 'blocked' })).toBeNull();
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

  it('blocks when extension sniff contradicts the param kind (CSV on reads)', () => {
    const rows = deriveInputMappingRows(
      [{ id: 'reads', name: 'reads', type: 'file', required: true, value: 'ds-1' }],
      DS,
      [{ name: 'reads' }],
    );
    expect(rows[0].status).toBe('needs-mapping');
    expect(rows[0].mismatch).toMatch(/reads/i);
    expect(runIsBlockedByInputs(rows)).toBe(true);
  });

  it('does not block samplesheet/input bound to a table CSV', () => {
    const rows = deriveInputMappingRows(
      [{ id: 'samplesheet', name: 'samplesheet', type: 'file', required: true, value: 'ds-1' }],
      DS,
      [],
    );
    expect(rows[0].status).toBe('resolved');
    expect(rows[0].formatChecked).toBe(true);
    expect(runIsBlockedByInputs(rows)).toBe(false);
  });

  it('does not block when kind is unknown / unprofiled', () => {
    const rows = deriveInputMappingRows(
      [{ id: 'reads', name: 'reads', type: 'file', required: true, value: 'mystery' }],
      [{ id: 'mystery', name: 'mystery.bin' }],
      [],
    );
    expect(rows[0].status).toBe('resolved');
    expect(rows[0].formatChecked).toBe(false);
    expect(runIsBlockedByInputs(rows)).toBe(false);
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
    const withGtf: SessionDataset[] = [...DS, { id: 'ds-gtf', name: 'genes.gtf', file_path: 's3://b/genes.gtf' }];
    const bound = params.map(p =>
      p.id === 'input' ? { ...p, value: 's3://b/counts.csv' }
      : p.id === 'gtf' ? { ...p, value: 's3://b/genes.gtf' } : p);
    const m = derivePrerunInputs(bound, withGtf, defs);
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

// Live dev 2026-11-11: nf-core/differentialabundance's schema declares no required
// params, so a BOUND samplesheet + matrix were dropped and the settings tab said
// "no required data inputs · no data upload needed". Bound user data is a mapped input.
describe('derivePrerunInputs — bound user data counts even when the schema marks nothing required', () => {
  const S3 = 's3://biomate-nextflow-work/uploads/0238d454-8be2-42db-9bc7-9e76e274f317/sample_metadata.csv';
  it('canonical-named / stored-file params with a value are primary + counted', () => {
    const m = derivePrerunInputs([
      { id: 'samplesheet', name: 'samplesheet', label: 'Samplesheet', type: 'string', value: S3, required: false },
      { id: 'matrix', name: 'matrix', label: 'Matrix', type: 'string', value: 's3://b/uploads/x/counts_matrix.csv', required: false },
      { id: 'study_type', name: 'study_type', label: 'Study type', type: 'string', value: 'rnaseq', required: false },
    ] as any, [], []);
    expect(m.primary.map(r => r.param.id)).toEqual(['samplesheet', 'matrix']);
    expect(m.boundCount).toBe(2);
    expect(m.requiredUnset).toBe(0);
  });
  it('an UNBOUND optional canonical param is not invented as a mapped/required input', () => {
    const m = derivePrerunInputs([{ id: 'contrasts', name: 'contrasts', type: 'string', value: '', required: false }] as any, [], []);
    expect(m.primary).toEqual([]);
    expect(m.requiredUnset).toBe(0);
  });
});
