/**
 * Deterministic findings from MultiQC general stats (RNA-seq / WGS QC).
 *
 * When DESeq2 / enrichGO tables are absent, nf-core still writes
 * multiqc_data.json with alignment / duplication rates. Prefer those numbers
 * over LLM narration of MultiQC HTML bookkeeping.
 */
export interface EvidenceFile { name: string; content: string }

export interface MultiqcFindings {
  summary: string;
  key_results: Array<{
    metric: string;
    value: string;
    interpretation: string;
    source_file: string;
  }>;
  next_steps: string[];
  caveats: string[];
  evidence_version: 'multiqc-stats-v1';
}

const SCORE_KEYS: Array<{ re: RegExp; label: string; units?: string }> = [
  { re: /^(percent_aligned|pct_aligned|uniquely_mapped_percent|mapped_percent)$/i, label: 'percent aligned', units: '%' },
  { re: /^(percent_duplication|pct_duplication|duplicate_percent)$/i, label: 'percent duplication', units: '%' },
  { re: /^(total_sequences|total_reads|reads)$/i, label: 'total reads' },
  { re: /^(unique_reads|uniquely_mapped)$/i, label: 'uniquely mapped reads' },
  { re: /^(median_insert_size|insert_size_median)$/i, label: 'median insert size', units: 'bp' },
  { re: /^(percent_gc|gc_percent)$/i, label: 'percent GC', units: '%' },
  { re: /^(mean_coverage|median_coverage|avg_coverage)$/i, label: 'mean coverage', units: '×' },
];

function parseJson(file: EvidenceFile): Record<string, any> | null {
  try {
    const j = JSON.parse(file.content);
    return j && typeof j === 'object' ? j : null;
  } catch { return null; }
}

function fmt(n: number): string {
  if (!Number.isFinite(n)) return String(n);
  if (Math.abs(n) >= 1000) return String(Math.round(n));
  if (Math.abs(n) >= 1) return (Math.round(n * 100) / 100).toString();
  return (Math.round(n * 10000) / 10000).toString();
}

function collectSampleMaps(json: Record<string, any>): Array<{ sample: string; metrics: Record<string, number> }> {
  const out: Array<{ sample: string; metrics: Record<string, number> }> = [];
  const pushMap = (sample: string, obj: Record<string, unknown>) => {
    const metrics: Record<string, number> = {};
    for (const [k, v] of Object.entries(obj)) {
      if (typeof v === 'number' && Number.isFinite(v)) metrics[k] = v;
      else if (typeof v === 'string' && v.trim() !== '' && !Number.isNaN(Number(v))) metrics[k] = Number(v);
    }
    if (Object.keys(metrics).length) out.push({ sample, metrics });
  };

  const gsd = json.report_general_stats_data;
  if (Array.isArray(gsd)) {
    for (const block of gsd) {
      if (!block || typeof block !== 'object') continue;
      for (const [sample, vals] of Object.entries(block as Record<string, unknown>)) {
        if (vals && typeof vals === 'object' && !Array.isArray(vals)) {
          pushMap(sample, vals as Record<string, unknown>);
        }
      }
    }
  } else if (gsd && typeof gsd === 'object') {
    for (const [sample, vals] of Object.entries(gsd)) {
      if (vals && typeof vals === 'object' && !Array.isArray(vals)) {
        pushMap(sample, vals as Record<string, unknown>);
      }
    }
  }

  // nf-core sometimes nests under report_saved_raw_data.multiqc_*
  const raw = json.report_saved_raw_data;
  if (raw && typeof raw === 'object') {
    for (const table of Object.values(raw as Record<string, unknown>)) {
      if (!table || typeof table !== 'object') continue;
      for (const [sample, vals] of Object.entries(table as Record<string, unknown>)) {
        if (vals && typeof vals === 'object' && !Array.isArray(vals)) {
          pushMap(sample, vals as Record<string, unknown>);
        }
      }
    }
  }
  return out;
}

function matchScoreKey(key: string): { label: string; units?: string } | null {
  for (const s of SCORE_KEYS) {
    if (s.re.test(key)) return s;
  }
  return null;
}

/**
 * Parse MultiQC JSON into flat findings. Returns null when no known QC scores found.
 */
export function parseMultiqcFindings(
  files: EvidenceFile[],
  workflowName = 'QC',
): MultiqcFindings | null {
  const mqFile = files.find(f => /multiqc_data\.json$/i.test(f.name))
    || files.find(f => /multiqc.*\.json$/i.test(f.name) && /general_stats|report_general/i.test(f.content));
  if (!mqFile) return null;
  const json = parseJson(mqFile);
  if (!json) return null;

  const samples = collectSampleMaps(json);
  if (!samples.length) return null;

  // Aggregate means across samples for the score-card keys we care about.
  const agg = new Map<string, { sum: number; n: number; label: string; units?: string }>();
  for (const s of samples) {
    for (const [k, v] of Object.entries(s.metrics)) {
      const hit = matchScoreKey(k);
      if (!hit) continue;
      const cur = agg.get(hit.label) || { sum: 0, n: 0, label: hit.label, units: hit.units };
      cur.sum += v;
      cur.n += 1;
      agg.set(hit.label, cur);
    }
  }
  if (!agg.size) return null;

  const rows: MultiqcFindings['key_results'] = [];
  for (const [, a] of agg) {
    const mean = a.sum / a.n;
    const value = a.units ? `${fmt(mean)}${a.units === '%' ? '%' : a.units === '×' ? '×' : ` ${a.units}`}` : fmt(mean);
    rows.push({
      metric: a.n > 1 ? `${a.label} (mean, n=${a.n})` : a.label,
      value: value.replace(/\s+$/, ''),
      interpretation: a.n > 1 ? `Mean across ${a.n} samples from MultiQC general stats` : 'From MultiQC general stats',
      source_file: mqFile.name,
    });
  }

  // Cap table; prefer alignment / coverage first.
  rows.sort((a, b) => {
    const rank = (m: string) => /align|mapped|coverage/i.test(m) ? 0 : /duplicat|insert|gc/i.test(m) ? 1 : 2;
    return rank(a.metric) - rank(b.metric);
  });
  const top = rows.slice(0, 8);
  const bits = top.slice(0, 3).map(r => `${r.metric}=${r.value}`);

  return {
    summary: `${workflowName || 'QC'} finished. Key QC scores: ${bits.join('; ')}. Read the Key Results table (from MultiQC); full MultiQC HTML remains in Outputs.`,
    key_results: top,
    next_steps: [
      'Open multiqc_report.html in Outputs for per-sample plots.',
      'If alignment is low, check adapter content and genome/index choice before differential expression.',
    ],
    caveats: [
      'MultiQC aggregates tool-specific columns; means across samples are for triage — inspect outliers in the HTML report.',
    ],
    evidence_version: 'multiqc-stats-v1',
  };
}
