import { describe, expect, it } from 'vitest';
import { readFileSync, statSync } from 'node:fs';
import { resolve } from 'node:path';
import { createHash } from 'node:crypto';
import { COLD_MODULES, COLD_DOMAINS, seedWithModality } from './cold-start-dashboard';
import { coldDemoFor, COLD_DEMO_BUNDLES } from './cold-start-demo-catalog';
import { PREPARED_EXAMPLES, INTERNAL_EXAMPLES } from './cold-start-examples';

const seeds = [...COLD_DOMAINS.flatMap(domain => domain.shapes.map(shape => shape.seed)), ...COLD_MODULES.flatMap(module => module.tracks.flatMap(track => track.exBy ? [...track.ex, ...Object.entries(track.exBy).flatMap(([mod, texts]) => texts.map(text => seedWithModality(text, mod as 'sm' | 'pep' | 'bio')))] : track.ex))];
const builtins = new Set<string>([...PREPARED_EXAMPLES.map(example => example.label), ...INTERNAL_EXAMPLES]);

describe('every cold-start path has prepared inputs', () => {
  it.each([...new Set(seeds)].filter(seed => !builtins.has(seed)))('%s', seed => {
    const demo = coldDemoFor(seed);
    expect(demo, 'An example must explicitly select its own dataset bundle').toBeDefined();
    expect(demo!.files.length).toBeGreaterThan(0);
    expect(demo!.context.length).toBeGreaterThan(100);
  });
  it('ships every selected asset rather than relying on an HTML SPA fallback', () => {
    const root = resolve(__dirname, '../../public/demo/cold-start');
    for (const name of new Set(Object.values(COLD_DEMO_BUNDLES).flatMap(bundle => bundle.files))) {
      const file = resolve(root, name);
      expect(statSync(file).size, name).toBeGreaterThan(0);
      expect(readFileSync(file).subarray(0, 100).toString().toLowerCase(), name).not.toContain('<html');
    }
  });
  it('ships every prepared-example (/demo/mg_demo) asset, not an SPA fallback', () => {
    // Guards the PREPARED_EXAMPLES `files:` assets in the SERVED publicDir
    // (frontend/client/public). Regression guard for the P6 Cox-PH break where
    // patient_clinical_data.csv lived only in frontend/public (unserved) and the
    // fetch returned the SPA index.html. Assets must exist here and not be HTML.
    const root = resolve(__dirname, '../../public/demo/mg_demo');
    const files = PREPARED_EXAMPLES.flatMap(example => ('files' in example ? example.files.map(name => ({ name, root: 'root' in example ? resolve(__dirname, '../../public', example.root.slice(1)) : root })) : []));
    for (const { name, root: fileRoot } of files) {
      const file = resolve(fileRoot, name);
      expect(statSync(file).size, name).toBeGreaterThan(0);
      expect(readFileSync(file).subarray(0, 100).toString().toLowerCase(), name).not.toContain('<html');
    }
  });
  it('does not silently attach a default dataset to a custom goal', () => {
    expect(coldDemoFor('Analyze my own experiment')).toBeUndefined();
  });
});

 it('preserves the original synthetic cohort identity and keeps truth separate from predictors', () => {
   const root = resolve(__dirname, '../../public/demo/sysucc_synthetic');
   const manifest = JSON.parse(readFileSync(resolve(root, 'provenance.json'), 'utf8'));
   expect(manifest.kind).toBe('synthetic_validation_inputs');
   expect(manifest.seed).toBe(20261105);
   for (const [name, entry] of Object.entries(manifest.files)) {
     expect(createHash('sha256').update(readFileSync(resolve(root, name))).digest('hex')).toBe((entry as { sha256: string }).sha256);
   }
   expect(manifest.files['rna.csv'].rows_excluding_header).toBe(1500);
   expect(manifest.files['mo_feature_matrix.csv'].rows_excluding_header).toBe(139);
   expect(manifest.files['mo_feature_matrix.csv'].columns).toBe(2502);
   const header = readFileSync(resolve(root, 'mo_feature_matrix.csv'), 'utf8').split(/\r?\n/)[0].split(',');
   expect(header[0]).toBe('sample_id'); expect(header[header.length - 1]).toBe('subtype');
 });

it('requires explicit built-in sample defaults when a prepared example has no files', () => {
  for (const example of PREPARED_EXAMPLES) {
    if (!('files' in example)) {
      expect(example.prompt, example.label).toMatch(/built-in/);
      expect(example.prompt, example.label).toMatch(/demo|sample|in-silico design exercise/);
    }
  }
});
