/**
 * Compatibility validation for file comparisons.
 *
 * When a user compares two (or more) result files, the operation is only
 * meaningful if the files share a schema. This module is the pure decision core:
 * given each file's header/format, it decides whether they are comparable and,
 * when the column names differ, proposes a typed column mapping — the plan's
 * "comparisons validate compatibility and request a typed mapping only when
 * needed". No I/O here so it is unit-testable; the route supplies the headers.
 */

export interface FileSchema {
  name: string;
  format?: string;       // normalized format/extension, e.g. 'csv', 'tsv', 'vcf'
  columns: string[];     // parsed header column names (empty if not tabular)
}

export interface CompatibilityResult {
  compatible: boolean;
  reason?: string;                       // set when not compatible
  sharedColumns: string[];               // intersection across all files
  perFile: Array<{ name: string; format?: string; columns: string[]; missing: string[] }>;
  needsTypedMapping: boolean;            // names differ but a mapping is possible
  suggestedMapping?: Array<{ file: string; map: Array<{ from: string; to: string }> }>;
}

const TAB_FORMATS = new Set(['csv', 'tsv', 'tab', 'txt']);

/** Whether a format is a delimited table whose header we can compare. */
export function isTabularFormat(format: string): boolean {
  return TAB_FORMATS.has(format);
}

/** Normalize a file name/extension to a lowercase format token. */
export function formatFromName(name: string): string {
  const ext = name.includes('.') ? name.split('.').pop()! : '';
  return ext.toLowerCase();
}

/**
 * Parse the header row of a tabular file into column names. Delimiter is chosen
 * from the format (tsv/tab → tab, else comma). Returns [] for empty input.
 */
export function parseHeaderColumns(headerText: string, format?: string): string[] {
  const firstLine = (headerText ?? '').split(/\r?\n/, 1)[0] ?? '';
  if (!firstLine.trim()) return [];
  const delim = format === 'tsv' || format === 'tab' ? '\t' : (firstLine.includes('\t') && !firstLine.includes(',') ? '\t' : ',');
  return firstLine
    .split(delim)
    .map((c) => c.trim().replace(/^["']|["']$/g, '').trim());
}

function setEqual(a: string[], b: string[]): boolean {
  if (a.length !== b.length) return false;
  const sb = new Set(b);
  return a.every((x) => sb.has(x));
}

/**
 * Decide whether the given tabular files are comparable.
 * - Same column set (order-independent) → compatible.
 * - Different formats → incompatible (no mapping).
 * - Same column COUNT but different names → incompatible, needsTypedMapping with
 *   a positional suggestion per divergent file.
 * - Different column counts → incompatible, no mapping.
 */
export function checkTabularCompatibility(files: FileSchema[]): CompatibilityResult {
  const perFile = files.map((f) => ({ name: f.name, format: f.format, columns: f.columns, missing: [] as string[] }));
  const base: CompatibilityResult = {
    compatible: false,
    sharedColumns: [],
    perFile,
    needsTypedMapping: false,
  };

  if (files.length < 2) {
    return { ...base, compatible: true, sharedColumns: files[0]?.columns ?? [] };
  }

  // Format check first — comparing a CSV to a VCF is not a column problem.
  const formats = new Set(files.map((f) => f.format || ''));
  if (formats.size > 1) {
    return { ...base, reason: `Files have different formats (${[...formats].filter(Boolean).join(', ')}); they cannot be compared directly.` };
  }

  // Non-tabular (no columns parsed): fall back to format-only equality.
  if (files.every((f) => f.columns.length === 0)) {
    return { ...base, compatible: true, reason: undefined };
  }

  const ref = files[0].columns;
  const shared = ref.filter((c) => files.every((f) => f.columns.includes(c)));

  if (files.every((f) => setEqual(f.columns, ref))) {
    return { ...base, compatible: true, sharedColumns: shared };
  }

  // Record what each file is missing relative to the reference union.
  const union = Array.from(new Set(files.flatMap((f) => f.columns)));
  for (const pf of perFile) pf.missing = union.filter((c) => !pf.columns.includes(c));

  const sameCount = files.every((f) => f.columns.length === ref.length);
  if (sameCount) {
    // Names differ but arity matches → a positional typed mapping is possible.
    const suggestedMapping = files.slice(1).map((f) => ({
      file: f.name,
      map: f.columns.map((from, i) => ({ from, to: ref[i] })).filter((m) => m.from !== m.to),
    })).filter((s) => s.map.length > 0);
    return {
      ...base,
      sharedColumns: shared,
      needsTypedMapping: true,
      suggestedMapping,
      reason: `Files have the same number of columns but different names. Provide a column mapping to compare them.`,
    };
  }

  return {
    ...base,
    sharedColumns: shared,
    reason: `Files have different column counts (${files.map((f) => `${f.name}: ${f.columns.length}`).join(', ')}); they are not directly comparable.`,
  };
}
