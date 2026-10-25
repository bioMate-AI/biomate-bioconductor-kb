/**
 * Generic findings extractor — one function turns ANY PatternDescriptor into a
 * FindingsDocument. Replaces the 4 bespoke `_parseXOutput` parsers; adding a domain is a
 * descriptor (findings-descriptors.ts), not code here.
 *
 * See docs/20261025_FINDINGS_PROVENANCE_FRAMEWORK.md §3.
 */
import type { FindingRecord, FindingsDocument, FindingEntity, FindingAssessment, Provenance } from './findings';
import type { PatternDescriptor, MetricSpec } from './findings-descriptors';
import { looksLikeSmiles } from './findings-descriptors';

type RawEntity = { id: string; metrics: Record<string, string> };

/** Unwrap an ADMET-style JSON wrapper to its inner result text, else return as-is. */
function unwrapResultText(content: string): string {
  try {
    const parsed = JSON.parse(content);
    if (typeof parsed.result === 'string') return parsed.result;
    if (typeof parsed.results === 'string') return parsed.results;
  } catch { /* not JSON — plain text */ }
  return content;
}

function parseKvBlocks(content: string, headerRe: RegExp): RawEntity[] {
  const text = unwrapResultText(content);
  const out: RawEntity[] = [];
  let cur: RawEntity | null = null;
  for (const raw of text.split('\n')) {
    const line = raw.trim();
    const head = headerRe.exec(line);
    if (head) {
      if (cur) out.push(cur);
      cur = { id: (head[1] || '').trim(), metrics: {} };
    } else if (cur) {
      const i = line.indexOf(':');
      if (i > 0) {
        const key = line.slice(0, i).trim();
        const val = line.slice(i + 1).trim();
        if (val && /^[<>]?\s*[-\d.]/.test(val)) cur.metrics[key] = val;
      }
    }
  }
  if (cur) out.push(cur);
  return out;
}

function parseDelimited(content: string, delim: string, entityCol: string | RegExp | undefined, metrics: MetricSpec[]): RawEntity[] {
  const lines = content.split('\n').filter(l => l.trim() && !l.startsWith('##'));
  if (lines.length < 2) return [];
  const header = lines[0].split(delim).map(h => h.replace(/"/g, '').trim());
  const colIdx = (m: string | RegExp) => header.findIndex(h => typeof m === 'string' ? h.toLowerCase() === m.toLowerCase() : m.test(h));
  const entIdx = entityCol ? colIdx(entityCol) : -1;
  const metricIdx = new Map<string, number>();
  for (const spec of metrics) {
    const idx = colIdx(spec.source);
    if (idx >= 0) metricIdx.set(spec.name, idx);
  }
  const out: RawEntity[] = [];
  for (const line of lines.slice(1)) {
    const cols = line.split(delim).map(c => c.replace(/"/g, '').trim());
    const metricsMap: Record<string, string> = {};
    for (const [name, idx] of metricIdx) if (cols[idx] !== undefined) metricsMap[name] = cols[idx];
    out.push({ id: entIdx >= 0 ? cols[entIdx] : `row_${out.length + 1}`, metrics: metricsMap });
  }
  return out;
}

/** Resolve a metric spec's raw value from an entity's metrics map (by key match). */
function readMetric(metricsMap: Record<string, string>, spec: MetricSpec): string | undefined {
  // For delimited parsing the map is already keyed by spec.name; for kvBlocks it is keyed
  // by the original line key, so match spec.source against the keys.
  if (metricsMap[spec.name] !== undefined) return metricsMap[spec.name];
  for (const [k, v] of Object.entries(metricsMap)) {
    if (typeof spec.source === 'string' ? k.toLowerCase() === spec.source.toLowerCase() : spec.source.test(k)) return v;
  }
  return undefined;
}

/** Split a raw value into {comparator, number, display} — preserves a censored inequality. */
function splitValue(raw: string): { comparator?: '<' | '>' | '<=' | '>='; num: number; text: string } {
  const m = /^\s*(<=|>=|<|>)?\s*(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)/.exec(raw);
  const comparator = (m?.[1] as '<' | '>' | '<=' | '>=' | undefined) || undefined;
  const num = m ? parseFloat(m[2]) : NaN;
  return { comparator, num, text: raw.trim() };
}

function assess(num: number, spec: MetricSpec): FindingAssessment | undefined {
  if (!spec.threshold) {
    return isNaN(num) ? undefined : { flag: 'neutral', interpretation: `${spec.label || spec.name}: ${num}` };
  }
  const t = spec.threshold;
  const label = spec.label || spec.name;
  if (isNaN(num)) return undefined;
  if (t.direction === 'high_bad' && num >= t.value) return { threshold: t, flag: 'liability', interpretation: `Elevated ${label} (${num}) — potential liability` };
  if (t.direction === 'low_bad' && num < t.value) return { threshold: t, flag: 'liability', interpretation: `Low ${label} (${num}) — potential liability` };
  return { threshold: t, flag: 'pass', interpretation: `Acceptable ${label} (${num})` };
}

function buildEntity(descriptor: PatternDescriptor, id: string): FindingEntity {
  const scheme = descriptor.entity.scheme;
  const type = descriptor.entity.type;
  let identifier: FindingEntity['identifier'];
  if (scheme && id) {
    if (scheme === 'SMILES') { if (looksLikeSmiles(id)) identifier = { scheme, value: id }; }
    else identifier = { scheme, value: id };
  }
  return { type, label: id || '(unnamed)', identifier, identitySource: 'output_column', scope: 'per_entity' };
}

/** Core: descriptor + matched file → FindingsDocument (records + shared provenance). */
export function buildFindingsDocument(
  descriptor: PatternDescriptor,
  file: { name: string; content: string },
): FindingsDocument {
  const raw: RawEntity[] =
    descriptor.parse === 'kvBlocks'
      ? parseKvBlocks(file.content, descriptor.entity.blockHeaderRegex || /^(?:Drug|Compound):\s*(\S.*)$/i)
      : parseDelimited(file.content, descriptor.parse === 'tsv' ? '\t' : ',', descriptor.entity.column, descriptor.metrics);

  // Row selection for high-cardinality entities (e.g. DE genes).
  let entities = raw;
  const sel = descriptor.select;
  if (sel?.significant) {
    const s = sel.significant;
    entities = entities.filter(e => {
      const v = readMetric(e.metrics, descriptor.metrics.find(m => m.name === s.metric)!);
      if (v === undefined) return false;
      const n = splitValue(v).num;
      return s.op === '<' ? n < s.value : n > s.value;
    });
  }
  if (sel?.sortByAbs) {
    const spec = descriptor.metrics.find(m => m.name === sel.sortByAbs)!;
    entities = [...entities].sort((a, b) => Math.abs(splitValue(readMetric(b.metrics, spec) || '0').num) - Math.abs(splitValue(readMetric(a.metrics, spec) || '0').num));
  }
  if (sel?.topN) entities = entities.slice(0, sel.topN);

  const provId = 'p0';
  const provenance: Record<string, Provenance> = {
    [provId]: { id: provId, source: { file: file.name }, evidenceClass: descriptor.evidenceClass },
  };

  const multi = entities.length > 1;
  const records: FindingRecord[] = [];
  for (const e of entities) {
    const entity = buildEntity(descriptor, e.id);
    for (const spec of descriptor.metrics) {
      const rawVal = readMetric(e.metrics, spec);
      if (rawVal === undefined) continue;
      const { comparator, num, text } = splitValue(rawVal);
      records.push({
        entity: multi ? entity : { ...entity, scope: 'per_entity' },
        metric: { name: spec.name, value: text, units: spec.units, comparator },
        assessment: assess(num, spec),
        provenanceRef: provId,
      });
    }
  }

  const liabilities = Array.from(new Set(records.filter(r => r.assessment?.flag === 'liability').map(r => r.metric.name)));
  const entType = descriptor.entity.type;
  const summary = entities.length === 1
    ? `Assessment completed for 1 ${entType}. ${liabilities.length ? `Potential liabilities: ${liabilities.join(', ')}.` : 'No major liabilities flagged.'}`
    : `Assessment completed for ${entities.length} ${entType}s against standard thresholds.${liabilities.length ? ` Liabilities flagged: ${liabilities.join(', ')}.` : ''}`;

  return {
    status: 'ready',
    summary,
    entityRoster: entities.map(e => ({ type: entType, label: e.id })),
    records,
    provenance,
    caveats: [],
    nextSteps: [],
  };
}
