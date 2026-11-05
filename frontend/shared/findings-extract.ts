/**
 * Generic findings extractor — one function turns ANY PatternDescriptor into a
 * FindingsDocument. Replaces the 4 bespoke `_parseXOutput` parsers; adding a domain is a
 * descriptor (findings-descriptors.ts), not code here.
 *
 * See docs/20261025_FINDINGS_PROVENANCE_FRAMEWORK.md §3.
 */
import type { FindingRecord, FindingsDocument, FindingEntity, FindingAssessment, Provenance } from './findings';
import { formatMetricValue } from './findings';
import type { PatternDescriptor, MetricSpec } from './findings-descriptors';
import { looksLikeSmiles } from './findings-descriptors';

type RawEntity = { id: string; metrics: Record<string, string> };

const MAX_ENTITIES = 200;

function unwrapResultText(content: string): string {
  try {
    const parsed = JSON.parse(content);
    if (typeof parsed.result === 'string') return parsed.result;
    if (typeof parsed.results === 'string') return parsed.results;
  } catch { /* plain text */ }
  return content;
}

function getByPath(obj: unknown, path?: string): unknown {
  if (!path) return obj;
  return path.split('.').reduce<unknown>((o, k) => (o && typeof o === 'object' ? (o as Record<string, unknown>)[k] : undefined), obj);
}

/** JSON object → string-valued metrics map (numbers/booleans coerced; arrays/objects skipped). */
function objToMetrics(obj: unknown): Record<string, string> {
  const out: Record<string, string> = {};
  if (obj && typeof obj === 'object') {
    for (const [k, v] of Object.entries(obj as Record<string, unknown>)) {
      if (v === null || v === undefined) continue;
      if (typeof v === 'number' || typeof v === 'string' || typeof v === 'boolean') out[k] = String(v);
    }
  }
  return out;
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
  const header = lines[0].split(delim).map(h => h.replace(/^#/, '').replace(/"/g, '').trim());
  const colIdx = (m: string | RegExp) => header.findIndex(h => typeof m === 'string' ? h.toLowerCase() === m.toLowerCase() : m.test(h));
  const entIdx = entityCol ? colIdx(entityCol) : -1;
  const metricIdx = new Map<string, number>();
  for (const spec of metrics) { const idx = colIdx(spec.source); if (idx >= 0) metricIdx.set(spec.name, idx); }
  const out: RawEntity[] = [];
  for (const line of lines.slice(1)) {
    const cols = line.split(delim).map(c => c.replace(/"/g, '').trim());
    const metricsMap: Record<string, string> = {};
    for (const [name, idx] of metricIdx) if (cols[idx] !== undefined) metricsMap[name] = cols[idx];
    out.push({ id: entIdx >= 0 ? cols[entIdx] : `row_${out.length + 1}`, metrics: metricsMap });
  }
  return out;
}

function parseEntities(descriptor: PatternDescriptor, file: { name: string; content: string }): { entities: RawEntity[]; batch: RawEntity | null } {
  if (descriptor.parse === 'kvBlocks') {
    return { entities: parseKvBlocks(file.content, descriptor.entity.blockHeaderRegex || /^(?:Drug|Compound):\s*(\S.*)$/i), batch: null };
  }
  if (descriptor.parse === 'jsonReport') {
    let json: unknown;
    try { json = JSON.parse(file.content); } catch { return { entities: [], batch: null }; }
    const idField = descriptor.entity.idField || 'id';
    const paths = Array.isArray(descriptor.entity.arrayPath)
      ? descriptor.entity.arrayPath
      : [descriptor.entity.arrayPath];
    // Merge every present array by id so parallel per-entity arrays (e.g. the ADMET-AI
    // probability rows and the RDKit heuristic rows, both keyed by SMILES) become one
    // record set with the union of their fields — never two divergent views of one compound.
    const merged = new Map<string, Record<string, string>>();
    const order: string[] = [];
    for (const p of paths) {
      const arr = getByPath(json, p);
      if (!Array.isArray(arr)) continue;
      arr.forEach((o, i) => {
        const id = String((o as Record<string, unknown>)?.[idField] ?? `item_${i + 1}`);
        if (!merged.has(id)) { merged.set(id, {}); order.push(id); }
        Object.assign(merged.get(id)!, objToMetrics(o));
      });
    }
    const entities: RawEntity[] = order.map(id => ({ id, metrics: merged.get(id)! }));
    const batch = descriptor.batch ? { id: 'panel', metrics: objToMetrics(getByPath(json, descriptor.batch.path)) } : null;
    return { entities, batch };
  }
  const delim = descriptor.parse === 'tsv' ? '\t' : descriptor.parse === 'autodelim' ? (file.content.includes('\t') ? '\t' : ',') : ',';
  return { entities: parseDelimited(file.content, delim, descriptor.entity.column, descriptor.metrics), batch: null };
}

function readMetric(metricsMap: Record<string, string>, spec: MetricSpec): string | undefined {
  if (metricsMap[spec.name] !== undefined) return metricsMap[spec.name];
  for (const [k, v] of Object.entries(metricsMap)) {
    if (typeof spec.source === 'string' ? k.toLowerCase() === spec.source.toLowerCase() : spec.source.test(k)) return v;
  }
  return undefined;
}

function splitValue(raw: string): { comparator?: '<' | '>' | '<=' | '>='; num: number; text: string } {
  const m = /^\s*(<=|>=|<|>)?\s*(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)/.exec(raw);
  const comparator = (m?.[1] as '<' | '>' | '<=' | '>=' | undefined) || undefined;
  return { comparator, num: m ? parseFloat(m[2]) : NaN, text: raw.trim() };
}

function assess(rawVal: string, spec: MetricSpec): FindingAssessment | undefined {
  // Categorical verdict (e.g. variant IMPACT, DILI risk tier).
  if (spec.categories) {
    for (const c of spec.categories) {
      const hit = typeof c.match === 'string' ? rawVal.toLowerCase() === c.match.toLowerCase() : c.match.test(rawVal);
      if (hit) return { flag: c.flag, interpretation: c.label || `${spec.label || spec.name}: ${rawVal}` };
    }
    return { flag: 'neutral', interpretation: `${spec.label || spec.name}: ${rawVal}` };
  }
  const { num } = splitValue(rawVal);
  if (isNaN(num)) return undefined;
  const label = spec.label || spec.name;
  if (!spec.threshold) return { flag: 'neutral', interpretation: `${label}: ${num}` };
  const t = spec.threshold;
  if (t.direction === 'high_bad' && num >= t.value) return { threshold: t, flag: 'liability', interpretation: `Elevated ${label} (${num}) — potential liability` };
  if (t.direction === 'low_bad' && num < t.value) return { threshold: t, flag: 'liability', interpretation: `Low ${label} (${num}) — potential liability` };
  return { threshold: t, flag: 'pass', interpretation: `Acceptable ${label} (${num})` };
}

function buildEntity(descriptor: PatternDescriptor, id: string): FindingEntity {
  const { scheme, type } = descriptor.entity;
  let identifier: FindingEntity['identifier'];
  if (scheme && id) {
    if (scheme === 'SMILES') { if (looksLikeSmiles(id)) identifier = { scheme, value: id }; }
    else identifier = { scheme, value: id };
  }
  return { type, label: id || '(unnamed)', identifier, identitySource: 'output_column', scope: 'per_entity' };
}

function recordsFor(entity: FindingEntity, metricsMap: Record<string, string>, specs: MetricSpec[], provId: string): FindingRecord[] {
  const out: FindingRecord[] = [];
  for (const spec of specs) {
    const rawVal = readMetric(metricsMap, spec);
    if (rawVal === undefined || rawVal === '') continue;
    const { comparator, text } = splitValue(rawVal);
    out.push({
      entity,
      metric: { name: spec.name, value: text, units: spec.units, comparator },
      assessment: assess(rawVal, spec),
      provenanceRef: provId,
    });
  }
  return out;
}

/** Core: descriptor + matched file → FindingsDocument (records + shared provenance). */
export function buildFindingsDocument(descriptor: PatternDescriptor, file: { name: string; content: string }): FindingsDocument {
  const parsed = parseEntities(descriptor, file);
  let entities = parsed.entities;
  const batch = parsed.batch;

  const sel = descriptor.select;
  if (sel?.significant) {
    const s = sel.significant;
    const spec = descriptor.metrics.find(m => m.name === s.metric)!;
    entities = entities.filter(e => { const v = readMetric(e.metrics, spec); if (v === undefined) return false; const n = splitValue(v).num; return s.op === '<' ? n < s.value : n > s.value; });
  }
  if (sel?.sort) {
    const spec = descriptor.metrics.find(m => m.name === sel.sort!.metric)!;
    const val = (e: RawEntity) => splitValue(readMetric(e.metrics, spec) || 'NaN').num;
    const mode = sel.sort.mode;
    entities = [...entities].sort((a, b) => mode === 'absDesc' ? Math.abs(val(b)) - Math.abs(val(a)) : mode === 'asc' ? val(a) - val(b) : val(b) - val(a));
  }
  entities = entities.slice(0, Math.min(sel?.topN ?? MAX_ENTITIES, MAX_ENTITIES));

  const provId = 'p0';
  const provenance: Record<string, Provenance> = { [provId]: { id: provId, source: { file: file.name }, evidenceClass: descriptor.evidenceClass } };

  const records: FindingRecord[] = [];
  for (const e of entities) records.push(...recordsFor(buildEntity(descriptor, e.id), e.metrics, descriptor.metrics, provId));

  // Batch/panel-level records (jsonReport) — belong to no single entity.
  if (batch && descriptor.batch) {
    const batchEntity: FindingEntity = { type: 'none', label: 'panel', scope: 'batch', identitySource: 'output_column' };
    records.push(...recordsFor(batchEntity, batch.metrics, descriptor.batch.metrics, provId));
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

/**
 * Bridge the legacy/LLM flat shape ({summary, key_results:[{metric,value,interpretation,
 * source_file,entity?}], …}) into a FindingsDocument, for the LLM fallback path. Entity is
 * a plain string when present (scope per_entity) else the value is unattributed (batch).
 */
export function legacyFindingsToDocument(parsed: {
  summary?: string;
  key_results?: Array<{ metric?: string; value?: string; interpretation?: string; source_file?: string; entity?: string }>;
  caveats?: string[];
  next_steps?: string[];
}): FindingsDocument {
  const provenance: Record<string, Provenance> = {};
  const provFor = (file?: string): string => {
    const id = file ? `p_${file}` : 'p_unknown';
    if (!provenance[id]) provenance[id] = { id, source: { file: file || '(unknown)' }, evidenceClass: 'Report' };
    return id;
  };
  const records: FindingRecord[] = (parsed.key_results || []).map(kr => {
    const label = (kr.entity || '').trim();
    const entity: FindingEntity = label
      ? { type: 'none', label, scope: 'per_entity', identitySource: 'output_column' }
      : { type: 'none', label: 'result', scope: 'batch', identitySource: 'unresolved' };
    return {
      entity,
      metric: { name: kr.metric || '(metric)', value: kr.value ?? '' },
      assessment: kr.interpretation ? { flag: 'neutral', interpretation: kr.interpretation } : undefined,
      provenanceRef: provFor(kr.source_file),
    };
  });
  const roster = Array.from(new Set(records.filter(r => r.entity.scope === 'per_entity').map(r => r.entity.label)))
    .map(label => ({ type: 'none' as const, label }));
  return { status: 'ready', summary: parsed.summary || '', entityRoster: roster, records, provenance, caveats: parsed.caveats || [], nextSteps: parsed.next_steps || [] };
}

/**
 * Project a FindingsDocument back to the flat legacy shape the current UI renders, so the
 * generic extractor can be the single source of truth in the findings path WITHOUT breaking
 * existing consumers (findings-card.tsx / AfterRunReport.tsx). The richer document is carried
 * alongside for the new per-entity renderer; this projection keeps today's render intact.
 */
export function documentToLegacy(doc: FindingsDocument): {
  summary: string;
  key_results: Array<{ metric: string; value: string; interpretation: string; source_file?: string; entity?: string }>;
  caveats: string[];
  next_steps: string[];
} {
  return {
    summary: doc.summary,
    key_results: doc.records.map(r => ({
      metric: r.metric.name,
      value: formatMetricValue(r.metric),
      interpretation: r.assessment?.interpretation ?? '',
      source_file: doc.provenance[r.provenanceRef]?.source.file,
      entity: r.entity.scope === 'per_entity' ? r.entity.label
        : r.entity.scope === 'batch' ? `${r.entity.label} (batch)` : undefined,
    })),
    caveats: doc.caveats,
    next_steps: doc.nextSteps,
  };
}

/** Distinct metric names the FindingsDocument flagged as a liability. */
export function documentLiabilities(doc: FindingsDocument): Set<string> {
  return new Set(doc.records.filter(r => r.assessment?.flag === 'liability').map(r => r.metric.name));
}

/**
 * Distinct liability metric names from the flat findings shape. The deterministic ADMET path
 * (`_parseAdmetOutput`) marks a liability by ending the interpretation with "potential liability";
 * we read that marker so the flat and document verdicts are compared on the same basis.
 */
export function flatLiabilities(findings: {
  key_results?: Array<{ metric?: string; interpretation?: string }>;
} | null | undefined): Set<string> {
  const out = new Set<string>();
  for (const kr of findings?.key_results || []) {
    if (kr.metric && /potential liability/i.test(kr.interpretation || '')) out.add(kr.metric);
  }
  return out;
}

function sameSet(a: Set<string>, b: Set<string>): boolean {
  if (a.size !== b.size) return false;
  for (const v of a) if (!b.has(v)) return false;
  return true;
}

/**
 * Reconciliation safeguard: one payload must never carry two contradictory liability verdicts.
 * The flat `summary`/`key_results` and the embedded `findings_document` are computed independently,
 * so if their liability sets disagree we log at error and make the embedded document DEFER to the
 * flat (primary) verdict — rewriting the document summary to the flat summary and recording a
 * caveat. When the sets agree (the intended steady state after the descriptor fix) this is a no-op.
 */
export function reconcileFindingsDocument(
  flat: { summary?: string; key_results?: Array<{ metric?: string; interpretation?: string }> } | null | undefined,
  doc: FindingsDocument,
  log: (msg: string) => void = (m) => console.error(m),
  flatIsDeterministic = false,
): FindingsDocument {
  const flatSet = flatLiabilities(flat);
  const docSet = documentLiabilities(doc);
  // Reconcile only when at least one path produced a liability signal AND the two disagree.
  if (flatSet.size + docSet.size === 0 || sameSet(flatSet, docSet)) return doc;
  // audit S3#1 (+ committee Opus-2): `flatLiabilities` only recognizes a liability via the
  // deterministic "potential liability" marker. On an LLM flat the flatSet is EMPTY, so an
  // empty flatSet vs a non-empty docSet is NOT a real disagreement — the entity document is the
  // reliable source; return doc unchanged. BUT on the DETERMINISTIC path an empty flatSet is
  // MEANINGFUL (the parser genuinely found zero liabilities): a document false-positive must not
  // silently override the clean primary verdict, so fall through to the defer-to-flat path (log +
  // reconcile the doc summary to the clean flat). Hence gate the early return on NOT deterministic.
  if (flatSet.size === 0 && !flatIsDeterministic) return doc;
  log(
    `[Findings] liability verdict mismatch — flat=[${[...flatSet].join(', ')}] ` +
    `document=[${[...docSet].join(', ')}]; embedded summary deferring to the flat (primary) verdict`,
  );
  return {
    ...doc,
    summary: (flat?.summary && flat.summary.trim()) ? flat.summary : doc.summary,
    caveats: [
      ...doc.caveats,
      'Embedded findings summary reconciled to the primary liability verdict (a mismatch between the two independently-computed verdicts was detected and logged).',
    ],
  };
}
