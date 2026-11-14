import { describe, expect, it } from 'vitest';
import { readFileSync, statSync } from 'node:fs';
import { resolve } from 'node:path';
import { createHash } from 'node:crypto';
import { COLD_MODULES, COLD_DOMAINS, seedWithModality } from './cold-start-dashboard';
import { coldDemoFor, COLD_DEMO_BUNDLES, COLD_DEMO_INTENTS } from './cold-start-demo-catalog';
import { PREPARED_EXAMPLES, INTERNAL_EXAMPLES } from './cold-start-examples';

const seeds = [...COLD_DOMAINS.flatMap(domain => domain.shapes.map(shape => shape.seed)), ...COLD_MODULES.flatMap(module => module.tracks.flatMap(track => track.exBy ? [...track.ex, ...Object.entries(track.exBy).flatMap(([mod, texts]) => texts.map(text => seedWithModality(text, mod as 'sm' | 'pep' | 'bio')))] : track.ex))];
const builtins = new Set<string>([...PREPARED_EXAMPLES.map(example => example.label), ...INTERNAL_EXAMPLES]);

// An example that points at the user's own data needs an explicit bundle to
// resolve "this/my/these/our"; a self-contained question names its subject.
const DEICTIC = /\b(this|these|my|our)\b/i;

describe('every cold-start path has prepared inputs', () => {
  it.each([...new Set(seeds)].filter(seed => !builtins.has(seed)))('%s', seed => {
    const demo = coldDemoFor(seed);
    if (!DEICTIC.test(seed) && !demo) return; // names its own subject, e.g. a literature question
    expect(demo, 'An example about the user\'s data must explicitly select its own dataset bundle').toBeDefined();
    expect(demo!.files.length).toBeGreaterThan(0);
    expect(demo!.context.length).toBeGreaterThan(100);
  });
  it('no card text (labels, shapes, needs, seeds) mentions storage paths', () => {
    const visible = [...seeds, ...COLD_DOMAINS.flatMap(d => d.shapes.flatMap(sh => [sh.t, sh.needs]))];
    for (const text of visible) expect(text).not.toMatch(/s3:\/\/|\bS3\b/i);
  });
  it('does not give the Search & evidence tracks one shared input set', () => {
    const search = COLD_MODULES.find(module => module.id === 'search')!;
    const perTrack = search.tracks.filter(track => track.k !== 'Internal').map(track =>
      [...new Set(track.ex.flatMap(text => coldDemoFor(text)?.files ?? []))].sort().join(',')).filter(Boolean);
    expect(new Set(perTrack).size, perTrack.join(' | ')).toBe(perTrack.length);
    // And within a track, two questions never silently reuse one bundle.
    for (const track of search.tracks.filter(track => track.k !== 'Internal')) {
      const bundles = track.ex.map(text => coldDemoFor(text)?.files.join(',')).filter(Boolean);
      expect(new Set(bundles).size, track.k).toBe(bundles.length);
    }
  });
  // Two examples printed side by side must not quietly resolve to the same
  // inputs: a shared bundle is how "QC a screen" ended up on data with no
  // replicates and how all three Search tracks attached one dataset
  // (docs/20261110_COLDSTART_EXAMPLES_LIVE_AUDIT.md §2.1, §4.3). Reuse is legal
  // only where it is the point — a design chain working on one candidate set.
  const SHARING_ALLOWLIST: Record<string, string> = {
    'design:molecules': 'the small-molecule design chain deliberately carries ONE candidate library through Generate → Predict → Optimise → Rank',
    'design:peptides': 'same chain, peptide modality: one candidate set through generate/predict/optimise/rank',
    'design:biologics': 'same chain, biologic modality: one nanobody/antibody design set end to end',
    'models:loop': 'the design–make–test loop example and its "next round" follow-up are two turns of one loop',
  };
  const bundleKey = (text: string) => COLD_DEMO_INTENTS.get(text.replace(/ \((peptide|protein) design\)$/, ''));
  const assertUnique = (scope: string, texts: string[]) => {
    const seen = new Map<string, string>();
    for (const text of texts) {
      const key = bundleKey(text);
      if (!key) continue;
      const first = seen.get(key);
      if (first === undefined) { seen.set(key, text); continue; }
      expect(SHARING_ALLOWLIST[`${scope}:${key}`], `${scope} reuses the "${key}" bundle for "${first}" and "${text}" — give one its own inputs, or allowlist the pair with a reason`).toBeTruthy();
    }
  };
  it('never shows two examples that silently resolve to the same inputs', () => {
    for (const module of COLD_MODULES) {
      for (const track of module.tracks) {
        const texts = track.exBy
          ? Object.entries(track.exBy).flatMap(([mod, list]) => list.map(text => seedWithModality(text, mod as 'sm' | 'pep' | 'bio')))
          : track.ex;
        assertUnique(module.id, texts.filter(text => !builtins.has(text)));
      }
    }
    for (const domain of COLD_DOMAINS) assertUnique(`domain-${domain.id}`, domain.shapes.map(shape => shape.seed));
  });
  it('allowlists only sharing that actually happens, so stale entries are removed', () => {
    const shared = new Set<string>();
    const record = (scope: string, texts: string[]) => {
      const seen = new Set<string>();
      for (const text of texts) {
        const key = bundleKey(text);
        if (!key) continue;
        if (seen.has(key)) shared.add(`${scope}:${key}`);
        seen.add(key);
      }
    };
    for (const module of COLD_MODULES) for (const track of module.tracks) {
      record(module.id, (track.exBy ? Object.entries(track.exBy).flatMap(([mod, list]) => list.map(text => seedWithModality(text, mod as 'sm' | 'pep' | 'bio'))) : track.ex).filter(text => !builtins.has(text)));
    }
    for (const domain of COLD_DOMAINS) record(`domain-${domain.id}`, domain.shapes.map(shape => shape.seed));
    expect([...Object.keys(SHARING_ALLOWLIST)].filter(entry => !shared.has(entry))).toEqual([]);
  });
  it('every bundle in the catalog is reachable from a printed example', () => {
    const used = new Set([...COLD_DEMO_INTENTS.values()]);
    expect(Object.keys(COLD_DEMO_BUNDLES).filter(key => !used.has(key))).toEqual([]);
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
  it('cryo demo exposes an absolute S3 movies_path for param binding', () => {
    const demo = coldDemoFor('Process this cryo-EM dataset to a density map and report the resolution.');
    expect(demo).toBeTruthy();
    expect(demo!.context).toMatch(/movies_path=s3:\/\/biomate-cryo-data\/empiar-10028\/Micrographs\//);
    const cryoJson = JSON.parse(
      readFileSync(resolve(__dirname, '../../public/demo/cold-start/cryo_inputs.json'), 'utf8'),
    );
    expect(cryoJson.movies_path).toBe('s3://biomate-cryo-data/empiar-10028/Micrographs/');
    expect(cryoJson.staged_movies_s3).toBe(cryoJson.movies_path);
  });
});

 it('preserves the original synthetic cohort identity and keeps truth separate from predictors', () => {
   const root = resolve(__dirname, '../../public/demo/hospital_synthetic');
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

// A file-less prepared example must read as a real, demo-free request: it names a
// concrete dataset/target the resolved workflow runs on (so routing and the card are
// honest), and it carries NO "built-in / sample data / demo" scaffolding. The
// workflow's example-data default (backend example_data.present) is what lets it run
// without an upload — the prompt no longer begs that behaviour with demo keywords.
// docs/20261111 example-data default.
it('every file-less prepared example is demo-free and names a concrete dataset/target', () => {
  // concrete subject each file-less example must name (keyed by a label substring).
  const SUBJECT: Array<[RegExp, RegExp]> = [
    [/cachexia/i,        /human_cachexia/],
    [/EBV antibody/i,    /VCA|EA|EBNA1/],
    [/flow cytometry/i,  /FSC|SSC|flow[_ ]?cytometry/i],
    [/CAR-T/i,           /CD19/],
    [/B-cell epitope/i,  /EBV/],
    [/HLA class-I/i,     /HLA-A|HLA-B/],
    [/ChIP-seq/i,        /CTCF|MACS|ChIP/],
    [/whole-slide/i,     /CMU-1|whole-slide|nuclei/i],
    [/ATAC/i,            /ATAC|differentially accessible/i],
    [/chemoproteomics/i, /pull-?down|proteinGroups|LFQ/i],
  ];
  const DEMO_SPEAK = /built-in|sample data|\bdemo\b|default sample|using the default/i;
  for (const example of PREPARED_EXAMPLES) {
    if ('files' in example) continue;
    expect(example.prompt, `${example.label}: must not use demo/built-in/sample-data scaffolding`)
      .not.toMatch(DEMO_SPEAK);
    const rule = SUBJECT.find(([label]) => label.test(example.label));
    expect(rule, `${example.label}: no concrete-subject rule declared for this file-less example`).toBeDefined();
    expect(example.prompt, `${example.label}: must name its concrete dataset/target`).toMatch(rule![1]);
  }
});
