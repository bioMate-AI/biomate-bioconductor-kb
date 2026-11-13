/**
 * Regression: multi-SMILES list value handling (the "CN1C" bogus-param bug).
 *
 * Symptom (docs/20261020 E2E ADMET capture): a 3-SMILES ADMET query
 *   "Screen these SMILES …: CC(=O)Oc1ccccc1C(=O)O, CN1C=NC2=C1C(=O)N(C(=O)N2C)C,
 *    CC(C)Cc1ccc(cc1)C(C)C(=O)O"
 * rendered a spurious "CN1C — Recommended" param row AND mis-handled the SMILES
 * value. Root cause: an LLM inline extractor can mis-read caffeine's "CN1C=NC2…"
 * prefix as a key=value pair, emitting a bogus key "CN1C".
 *
 * General fix (NOT a per-value-type rule):
 *   1. Schema-authoritative param rows — galaxy-assistant.ts intersects
 *      workflow_ga.inline_parameters with the workflow's real schema
 *      (required ∪ optional) before the viewer renders rows, so NO key the schema
 *      doesn't declare can become a param row, whatever produced it. (Covered by
 *      the integration path; asserted at source level here.)
 *   2. normalizeAdmetSmiles value handling — parse JSON-array / comma-list SMILES
 *      values without first-token truncation or double-wrapping, so a correctly
 *      extracted multi-SMILES value survives intact. (Unit-tested below.)
 */
import { describe, expect, it } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';
import { normalizeAdmetSmiles } from './galaxy-assistant.js';

const ASPIRIN = 'CC(=O)Oc1ccccc1C(=O)O';
const CAFFEINE = 'CN1C=NC2=C1C(=O)N(C(=O)N2C)C';
const IBUPROFEN = 'CC(C)Cc1ccc(cc1)C(C)C(=O)O';

describe('normalizeAdmetSmiles — multi-SMILES value handling', () => {
  const WF = 'Predict ADMET Properties (AI)';

  it('preserves ALL compounds from a JSON-array-string value (no double-wrap, no loss)', () => {
    const out = normalizeAdmetSmiles(WF, { smiles: JSON.stringify([ASPIRIN, CAFFEINE, IBUPROFEN]) });
    expect(JSON.parse(out.smiles_list)).toEqual([ASPIRIN, CAFFEINE, IBUPROFEN]);
  });

  it('splits a raw comma-separated smiles_list instead of taking only the first token', () => {
    const out = normalizeAdmetSmiles(WF, { smiles_list: `${ASPIRIN}, ${CAFFEINE}, ${IBUPROFEN}` });
    expect(JSON.parse(out.smiles_list)).toEqual([ASPIRIN, CAFFEINE, IBUPROFEN]);
  });

  it('keeps a single SMILES as a 1-element array', () => {
    const out = normalizeAdmetSmiles(WF, { smiles_list: ASPIRIN });
    expect(JSON.parse(out.smiles_list)).toEqual([ASPIRIN]);
  });

  it('accepts a real JS array value', () => {
    const out = normalizeAdmetSmiles(WF, { smiles_list: [ASPIRIN, CAFFEINE] as any });
    expect(JSON.parse(out.smiles_list)).toEqual([ASPIRIN, CAFFEINE]);
  });

  it('does not fabricate extra param keys (only smiles_list + model type survive)', () => {
    const out = normalizeAdmetSmiles(WF, {
      smiles: JSON.stringify([ASPIRIN, CAFFEINE, IBUPROFEN]),
      ADMET_model_type: 'MPNN',
    });
    expect(Object.keys(out).sort()).toEqual(['ADMET_model_type', 'smiles_list']);
  });

  it('is a no-op for non-SMILES workflows', () => {
    const raw = { matrix: 's3://b/counts.csv', foo: 'bar' };
    expect(normalizeAdmetSmiles('nf-core/rnaseq', raw)).toEqual(raw);
  });
});

describe('schema-authoritative inline params — source contract', () => {
  const SRC = fs.readFileSync(path.join(__dirname, 'galaxy-assistant.ts'), 'utf-8');

  it('intersects inline_parameters with the workflow schema before the viewer renders rows', () => {
    // Non-empty schema: drop keys the schema does not declare.
    // Empty schema: clear inline_parameters entirely (fail closed) so missing-.nf
    // orphans cannot promote LLM phantoms as Recommended (2026-11-13 Admet Pred).
    expect(SRC).toMatch(/Dropping inline param/);
    expect(SRC).toMatch(/Clearing inline param/);
    expect(SRC).toMatch(/_schemaNames\.size === 0/);
    expect(SRC).toMatch(/!_schemaNames\.has\(_k\)/);
  });
});
