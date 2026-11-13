/**
 * Empty-schema phantom guard (2026-11-13 Admet Pred incident).
 * When required_params/optional_params are empty because the .nf was not found,
 * LLM inline_parameters must NOT become Recommended rows.
 */
import { describe, it, expect } from 'vitest';
import { buildViewerParameters } from './nextflow-workflow-viewer';

describe('buildViewerParameters — empty schema does not promote inline phantoms', () => {
  const phantomInline = {
    target_pdb: 's3://bucket/uploads/1IEP.pdb',
    library_file: 's3://bucket/uploads/candidate_library.csv',
    reference_actives: 's3://bucket/uploads/pilot_reference_actives.smi',
    target_info: 's3://bucket/uploads/pilot_target_info.json',
  };

  it('returns no Recommended rows when schema is empty and only inline_parameters exist', () => {
    const rows = buildViewerParameters(
      {
        name: 'Admet Pred',
        required_params: [],
        optional_params: [],
        inline_parameters: phantomInline,
      },
      {},
    );
    expect(rows).toEqual([]);
    expect(rows.every((r) => !r.autoFilled)).toBe(true);
  });

  it('still seeds structured schema params; extra inline may appear as Recommended when schema present', () => {
    const rows = buildViewerParameters(
      {
        name: 'Predict ADMET Properties (AI)',
        required_params: [{ name: 'smiles', type: 'string', required: true, value: 'CCO' }],
        optional_params: [],
        inline_parameters: { target_pdb: 's3://bucket/1IEP.pdb' },
      },
      {},
    );
    const smiles = rows.find((r) => r.id === 'smiles');
    expect(smiles?.value).toBe('CCO');
    // Extra inline not in schema may still appear as autoFilled when schema is present
    // (server-side intersect normally drops it; viewer keeps prior behaviour for non-empty schema).
    const phantom = rows.find((r) => r.id === 'target_pdb');
    expect(phantom?.autoFilled).toBe(true);
  });

  it('keeps explicit parameters / currentParams without promoting inline as Recommended', () => {
    const rows = buildViewerParameters(
      {
        required_params: [],
        optional_params: [],
        parameters: { smiles: 'CCO' },
        inline_parameters: phantomInline,
      },
      { smiles: 'CCN' },
    );
    expect(rows).toHaveLength(1);
    expect(rows[0].id).toBe('smiles');
    expect(rows[0].value).toBe('CCN');
    expect(rows[0].autoFilled).toBe(false);
  });
});
