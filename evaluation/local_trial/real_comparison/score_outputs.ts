/** Score downloaded real outputs through BioMate's production scorer, without network I/O. */
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseClusters, parseLabels, scoreBenchmark } from '../../../frontend/server/benchmark-orchestrator';

const root = dirname(fileURLToPath(import.meta.url));
const hash = (text: string) => createHash('sha256').update(text).digest('hex');
const manifest = JSON.parse(readFileSync(join(root, 'input_manifest.json'), 'utf8'));
const clusters: Record<string, Map<string, string>> = {};
const artifacts: Record<string, unknown> = {};
for (const method of ['snf', 'mfa']) {
  const file = join(root, 'outputs', `${method}_clusters.csv`);
  const text = readFileSync(file, 'utf8');
  const rows = text.trim().split(/\r?\n/);
  if (rows[0].replaceAll('"', '') !== 'sample,cluster') throw new Error(`Invalid header: ${file}`);
  const parsed = parseClusters(text);
  if (parsed.size !== rows.length - 1) throw new Error(`Duplicate or malformed samples: ${file}`);
  if (parsed.size !== 200 || new Set(parsed.values()).size !== 2) throw new Error(`Expected 200 samples and two clusters: ${file}`);
  clusters[method] = parsed;
  artifacts[method] = { file: `outputs/${method}_clusters.csv`, sha256: hash(text), samples: parsed.size };
}
const labelsText = readFileSync(join(root, 'inputs', 'ighv_labels.csv'), 'utf8');
if (hash(labelsText) !== manifest.labels.sha256) throw new Error('Labels differ from frozen input manifest');
const labels = parseLabels(labelsText);
const score = scoreBenchmark(clusters, labels);
if (score.common_samples.length !== 188) throw new Error('Expected frozen shared cohort of 188 labeled samples');
const result = {
  provenance: 'Local recomputation using production scoreBenchmark; separate from deployed benchmark API report.',
  automatic_end_to_end_pass: false,
  reason: 'Assistant produced no executable plan; execution required a direct benchmark API call.',
  artifacts, labels_sha256: hash(labelsText), score,
};
writeFileSync(join(root, 'verified_scores.json'), JSON.stringify(result, null, 2) + '\n');
console.log(JSON.stringify({ report: score.report, winner: score.winner, n: score.common_samples.length }, null, 2));
