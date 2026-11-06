import { readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { ALLOWED_UPLOAD_EXTENSIONS, isAllowedUploadName, UnsupportedUploadTypeError } from './upload-file-types';

// The cold-start UI attaches these demo files to its examples and uploads them through
// POST /api/datasets/upload. If the allowlist rejects one, the example silently loses its
// input (2026-11-04: four PDB structures and the SMILES reference actives were rejected).
const DEMO = resolve(__dirname, '../client/public/demo');

describe('upload allowlist covers every demo asset the UI attaches', () => {
  for (const dir of ['cold-start', 'mg_demo']) {
    it(`accepts every file in client/public/demo/${dir}`, () => {
      const rejected = readdirSync(resolve(DEMO, dir)).filter(n => !isAllowedUploadName(n));
      expect(rejected).toEqual([]);
    });
  }

  it('accepts structure and cheminformatics formats, case-insensitively', () => {
    for (const n of ['1IEP.pdb', 'x.cif', 'lig.sdf', 'lig.mol2', 'actives.smi', 'rec.pdbqt', 'airway.RData', 'A.PDB']) {
      expect(isAllowedUploadName(n), n).toBe(true);
    }
  });

  it('still rejects types outside the list', () => {
    for (const n of ['run.exe', 'script.sh', 'noext']) expect(isAllowedUploadName(n), n).toBe(false);
    expect(ALLOWED_UPLOAD_EXTENSIONS).not.toContain('.exe');
  });

  it('rejection is a 415 client error, not a 500', () => {
    const e = new UnsupportedUploadTypeError('File type not supported: .exe');
    expect(e.status).toBe(415);
    expect(e).toBeInstanceOf(Error);
  });
});
