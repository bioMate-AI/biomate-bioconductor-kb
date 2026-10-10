import { describe, expect, it } from 'vitest';
import { readFileSync, statSync } from 'node:fs';
import { resolve } from 'node:path';
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
  it('does not silently attach a default dataset to a custom goal', () => {
    expect(coldDemoFor('Analyze my own experiment')).toBeUndefined();
  });
});
