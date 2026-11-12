/**
 * Nested JSON in dataset cells (JSONL records whose fields are lists / objects).
 *
 * The rows reader keeps a nested value as compact JSON text (lossless). These helpers turn it back
 * into structure for the Preview: a short summary for the cell, and — for the record view — tables
 * where the data IS a table. Generic (no field names): a list of lists is a matrix; a list of
 * strings whose length equals a matrix's width in the same record is that matrix's header row
 * (e.g. EPAR extracted tables: `headers` + `rows`).
 */

export type NestedKind = "matrix" | "list" | "object"

export interface NestedValue {
  kind: NestedKind
  value: unknown
  /** rows × columns for a matrix; item count for a list; key count for an object. */
  rows: number
  cols: number
}

/** Parse a cell that holds a JSON list/object; null for scalars and non-JSON text. */
export function parseNested(cell: unknown): NestedValue | null {
  const s = typeof cell === "string" ? cell.trim() : ""
  if (!s || (s[0] !== "[" && s[0] !== "{")) return null
  let v: unknown
  try { v = JSON.parse(s) } catch { return null }
  if (Array.isArray(v)) {
    if (v.length > 0 && v.every((r) => Array.isArray(r))) {
      const cols = Math.max(0, ...(v as unknown[][]).map((r) => r.length))
      return { kind: "matrix", value: v, rows: v.length, cols }
    }
    return { kind: "list", value: v, rows: v.length, cols: 0 }
  }
  if (v && typeof v === "object") return { kind: "object", value: v, rows: Object.keys(v as object).length, cols: 0 }
  return null
}

export interface RecordTable {
  /** Field holding the matrix. */
  field: string
  /** Header row: a sibling list of the same width, else null. */
  header: string[] | null
  headerField: string | null
  body: unknown[][]
}

const isScalarList = (v: unknown): v is unknown[] =>
  Array.isArray(v) && v.length > 0 && v.every((x) => x == null || typeof x !== "object")

/** Tables inside one record: every matrix field, paired with a same-width scalar list when one exists. */
export function recordTables(columns: string[], row: string[]): RecordTable[] {
  const parsed = columns.map((c, i) => ({ field: c, n: parseNested(row[i]) }))
  const lists = parsed.filter((p) => p.n?.kind === "list" && isScalarList(p.n.value))
  const used = new Set<string>()
  const out: RecordTable[] = []
  for (const p of parsed) {
    if (p.n?.kind !== "matrix") continue
    const hdr = lists.find((l) => !used.has(l.field) && (l.n!.value as unknown[]).length === p.n!.cols)
    if (hdr) used.add(hdr.field)
    out.push({
      field: p.field,
      header: hdr ? (hdr.n!.value as unknown[]).map((x) => (x == null ? "" : String(x))) : null,
      headerField: hdr ? hdr.field : null,
      body: p.n.value as unknown[][],
    })
  }
  return out
}
