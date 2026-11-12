/**
 * Cell edits on a delimited text file (CSV/TSV) that change ONLY the edited cells.
 *
 * The dataset Preview shows rows parsed by the Python rows reader (galaxy.ai.data_perception
 * `_iter_table`, Python's csv module). An edit says "data row r, column c": this module finds
 * that same cell with the same rules and rewrites just that field —
 *   - quote-aware records (a quoted field may hold the delimiter, `""` quotes and newlines);
 *   - `\r\n`, `\n` and `\r` all end a record, and every record keeps its own terminator;
 *   - data rows are counted like the reader counts them: after the header record, skipping
 *     blank / all-empty records;
 *   - every byte outside the edited fields is kept (other fields' quoting, spacing, line
 *     endings, BOM, trailing newline).
 * Each edit carries the value the user saw (`from`); if the file's cell differs, NOTHING is
 * written — a stale version or a row-mapping mismatch must never land on the wrong cell.
 *
 * Replaces line.split(delim) editing, which broke quoted fields (`1,"x, y"` → `1,new, y"`)
 * and turned CRLF files into LF (2026-11-11).
 */

export interface CellEdit {
  /** 0-based data row, numbered as the Preview / rows reader numbers rows. */
  row: number
  /** 0-based column index. */
  col: number
  /** The value the user saw before editing; required to match the file. */
  from: string
  value: string
  /** Optionally the whole row as the user saw it: the record must hold exactly these values,
   *  so a mis-numbered edit cannot land on another row that holds the same cell value. */
  rowFrom?: string[]
}

export interface EditResult {
  text: string
  applied: number
  /** Edits whose `from` did not match the file (nothing is written when non-empty). */
  conflicts: Array<{ row: number; col: number; expected: string; actual: string | null; rowMismatch?: boolean }>
}

interface Span { start: number; end: number }

/** Records as [start, end) spans (terminator excluded) plus their terminators. */
export function splitRecords(text: string, delim: string): Array<Span & { term: string }> {
  const out: Array<Span & { term: string }> = []
  let i = 0
  let start = 0
  let inQuotes = false
  let fieldStart = true
  const n = text.length
  while (i < n) {
    const ch = text[i]
    if (inQuotes) {
      if (ch === '"') {
        if (text[i + 1] === '"') { i += 2; continue }
        inQuotes = false
      }
      i++
      continue
    }
    if (ch === '"' && fieldStart) { inQuotes = true; fieldStart = false; i++; continue }
    if (ch === "\r" || ch === "\n") {
      const term = ch === "\r" && text[i + 1] === "\n" ? "\r\n" : ch
      out.push({ start, end: i, term })
      i += term.length
      start = i
      fieldStart = true
      continue
    }
    fieldStart = ch === delim
    i++
  }
  if (start < n) out.push({ start, end: n, term: "" })
  return out
}

/** Field spans inside one record, and their unquoted values. `open` marks a quoted field the
 *  text ends inside (no closing quote — Python's csv reads it to the end of the data). */
export function parseRecord(raw: string, delim: string): Array<Span & { value: string; open?: boolean }> {
  const fields: Array<Span & { value: string; open?: boolean }> = []
  let i = 0
  const n = raw.length
  for (;;) {
    const start = i
    let value = ""
    let open = false
    if (raw[i] === '"') {
      i++
      for (;;) {
        if (i >= n) { open = true; break }
        if (raw[i] === '"') {
          if (raw[i + 1] === '"') { value += '"'; i += 2; continue }
          i++
          break
        }
        value += raw[i++]
      }
      // Python csv is lenient: text after a closing quote is kept literally.
      while (i < n && raw[i] !== delim) value += raw[i++]
    } else {
      while (i < n && raw[i] !== delim) value += raw[i++]
    }
    // Python reads text with universal newlines: "\r\n" and "\r" inside a value arrive as "\n".
    fields.push({ start, end: i, value: value.replace(/\r\n?/g, "\n"), ...(open ? { open } : {}) })
    if (i >= n) break
    i++ // delimiter
    if (i === n) { fields.push({ start: i, end: i, value: "" }); break }
  }
  return fields
}

/** A record's values equal the row the user saw (trailing empty fields are not significant:
 *  the reader pads short rows to the header width). */
function sameRow(actual: string[], seen: string[]): boolean {
  const trim = (a: string[]) => { let n = a.length; while (n > 0 && a[n - 1] === "") n--; return a.slice(0, n) }
  const a = trim(actual), b = trim(seen)
  return a.length === b.length && a.every((v, i) => v === b[i])
}

/** Minimal quoting (Python csv QUOTE_MINIMAL). */
export function quoteField(value: string, delim: string): string {
  return value.includes(delim) || value.includes('"') || value.includes("\n") || value.includes("\r")
    ? `"${value.replace(/"/g, '""')}"`
    : value
}

/** A record the reader skips: empty, or every field empty. */
function isBlank(raw: string, delim: string): boolean {
  return raw === "" || parseRecord(raw, delim).every((f) => f.value === "")
}

export function applyCellEdits(text: string, delim: string, edits: CellEdit[], opts: { headerRows?: number } = {}): EditResult {
  const headerRows = opts.headerRows ?? 1
  const records = splitRecords(text, delim)
  // data row index → record index (header records first, then non-blank records)
  const dataRecord: number[] = []
  let seenHeader = 0
  for (let k = 0; k < records.length; k++) {
    if (seenHeader < headerRows) { seenHeader++; continue }
    const raw = text.slice(records[k].start, records[k].end)
    if (!isBlank(raw, delim)) dataRecord.push(k)
  }

  const byRecord = new Map<number, CellEdit[]>()
  const conflicts: EditResult["conflicts"] = []
  for (const e of edits) {
    const k = dataRecord[e.row]
    if (k === undefined || !Number.isInteger(e.col) || e.col < 0) {
      conflicts.push({ row: e.row, col: e.col, expected: e.from, actual: null })
      continue
    }
    const fields = parseRecord(text.slice(records[k].start, records[k].end), delim)
    const actual = e.col < fields.length ? fields[e.col].value : ""
    if (actual !== e.from) { conflicts.push({ row: e.row, col: e.col, expected: e.from, actual }); continue }
    if (e.rowFrom && !sameRow(fields.map((f) => f.value), e.rowFrom)) {
      conflicts.push({ row: e.row, col: e.col, expected: e.from, actual, rowMismatch: true })
      continue
    }
    const list = byRecord.get(k) || []
    list.push(e)
    byRecord.set(k, list)
  }
  if (conflicts.length) return { text, applied: 0, conflicts }

  let out = ""
  let cursor = 0
  let applied = 0
  for (const k of [...byRecord.keys()].sort((a, b) => a - b)) {
    const rec = records[k]
    const raw = text.slice(rec.start, rec.end)
    const fields = parseRecord(raw, delim)
    const vals: Array<string | null> = fields.map(() => null)
    for (const e of byRecord.get(k)!) {
      while (vals.length <= e.col) vals.push(null)
      vals[e.col] = e.value
      applied++
    }
    // Rebuild the record: untouched fields keep their raw text, edited ones are re-quoted. A
    // field the file ends inside (`1,"x` at EOF) is closed when anything follows it — otherwise
    // the delimiter and the fields after it would be read as part of that quoted value.
    const parts: string[] = []
    for (let j = 0; j < vals.length; j++) {
      const v = vals[j]
      if (v !== null) { parts.push(quoteField(v, delim)); continue }
      if (j >= fields.length) { parts.push(""); continue }
      const rawField = raw.slice(fields[j].start, fields[j].end)
      parts.push(fields[j].open && j < vals.length - 1 ? rawField + '"' : rawField)
    }
    out += text.slice(cursor, rec.start) + parts.join(delim)
    cursor = rec.end
  }
  out += text.slice(cursor)
  return { text: out, applied, conflicts }
}

/** Delimiter as the rows reader picks it: by extension, else tab vs comma count in the first line. */
export function pickDelimiter(text: string, ext: string): string {
  const e = (ext || "").toLowerCase()
  if (e === "tsv" || e === "tab") return "\t"
  if (e === "csv") return ","
  const nl = text.search(/\r|\n/)
  const first = nl >= 0 ? text.slice(0, nl) : text
  return first.split("\t").length > first.split(",").length ? "\t" : ","
}

/** All records' values (blank / all-empty records dropped, as the rows reader drops them). */
export function parseDelimited(text: string, delim: string, maxRecords = Infinity): string[][] {
  const out: string[][] = []
  for (const rec of splitRecords(text, delim)) {
    if (out.length >= maxRecords) break
    const vals = parseRecord(text.slice(rec.start, rec.end), delim).map((f) => f.value)
    if (vals.every((v) => v === "")) continue
    out.push(vals)
  }
  return out
}

/** The value of one cell, located exactly as applyCellEdits locates it (null if absent). */
export function readCell(text: string, delim: string, row: number, col: number, opts: { headerRows?: number } = {}): string | null {
  const probe = applyCellEdits(text, delim, [{ row, col, from: "\u0000__probe__", value: "" }], opts)
  const c = probe.conflicts[0]
  return c ? c.actual : null
}
