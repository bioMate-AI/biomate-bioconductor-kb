/**
 * DatasetRowsTable — the Preview table over a file's FULL rows (paged in from
 * GET /api/projects/:id/files/:fileId/rows), not a fixed sample.
 *
 * - Windowed rendering: only the rows in view (+ overscan) are in the DOM, so tens
 *   of thousands of loaded rows stay smooth; spacer rows keep the scrollbar honest.
 * - Scrolling near the bottom asks for the next page (`onNeedMore`).
 * - Sort / filter run client-side over the LOADED rows, and the footer says so
 *   ("sorting and filtering apply to the loaded rows only") until every row is
 *   loaded; "Load all rows" makes them whole-file operations.
 */
import { useMemo, useRef, useState } from "react"
import { Button } from "@/components/ui/button"
import { t } from "@/lib/i18n"
import { parseNested, recordTables, type NestedValue } from "./nested-json"

const ROW_H = 26
const OVERSCAN = 20
const FALLBACK_VIEW_H = 600

export interface DatasetRowsTableProps {
  columns: string[]
  rows: string[][]
  /** True total row count (null = not known yet). */
  total: number | null
  loading: boolean
  error: number | null
  onNeedMore: () => void
  onLoadAll?: () => void
  onRetry?: () => void
  /** Hide "Load all" above this many rows (browser memory). */
  loadAllCap?: number
}

/** Short structural label for a nested cell (a JSONL list/object), instead of truncated JSON text. */
function nestedLabel(n: NestedValue): string {
  if (n.kind === "matrix") return t("dataset_obj.nested_table", { rows: n.rows, cols: n.cols })
  if (n.kind === "list") return t("dataset_obj.nested_list", { n: n.rows })
  return t("dataset_obj.nested_object", { n: n.rows })
}

/** Collapsible view of any nested JSON value. */
function JsonTree({ value, depth = 0 }: { value: unknown; depth?: number }) {
  if (value === null || typeof value !== "object") {
    return <span className="font-mono text-xs">{value === null ? "null" : JSON.stringify(value)}</span>
  }
  const entries = Array.isArray(value) ? value.map((v, i) => [String(i), v] as const) : Object.entries(value as object)
  return (
    <details open={depth < 1} className="text-xs">
      <summary className="cursor-pointer text-muted-foreground">
        {Array.isArray(value) ? `[${entries.length}]` : `{${entries.length}}`}
      </summary>
      <div className="pl-4 space-y-0.5">
        {entries.map(([k, v]) => (
          <div key={k}><span className="text-muted-foreground font-mono">{k}: </span><JsonTree value={v} depth={depth + 1} /></div>
        ))}
      </div>
    </details>
  )
}

/** One record, structured: scalar fields, embedded tables (with a matching header list), JSON trees. */
function RecordView({ columns, row, index, onClose }: { columns: string[]; row: string[]; index: number; onClose: () => void }) {
  const tables = recordTables(columns, row)
  const inTable = new Set(tables.flatMap((tb) => [tb.field, ...(tb.headerField ? [tb.headerField] : [])]))
  return (
    <div className="rounded border p-2 space-y-2" data-testid="dataset-record-view">
      <div className="flex items-center gap-2">
        <span className="text-xs font-semibold flex-1">{t("dataset_obj.record_title", { n: index + 1 })}</span>
        <Button size="sm" variant="ghost" className="h-6 px-2 text-xs" onClick={onClose} data-testid="dataset-record-close">
          {t("dataset_obj.record_close")}
        </Button>
      </div>
      <dl className="grid grid-cols-[max-content_1fr] gap-x-3 gap-y-0.5 text-xs">
        {columns.map((c, i) => {
          if (inTable.has(c)) return null
          const n = parseNested(row[i])
          return [
            <dt key={`k${i}`} className="text-muted-foreground font-mono">{c}</dt>,
            <dd key={`v${i}`} className="font-mono break-all">{n ? <JsonTree value={n.value} /> : (row[i] ?? "")}</dd>,
          ]
        })}
      </dl>
      {tables.map((tb) => (
        <div key={tb.field} className="space-y-1" data-testid="dataset-record-table">
          <div className="text-xs text-muted-foreground font-mono">
            {tb.headerField ? `${tb.headerField} + ${tb.field}` : tb.field}
          </div>
          <div className="overflow-auto rounded border" style={{ maxHeight: "50vh" }}>
            <table className="border-collapse text-xs">
              {tb.header && (
                <thead><tr>{tb.header.map((h, i) => (
                  <th key={i} className="border px-2 py-1 text-left font-semibold align-top" style={{ background: "var(--bm-accent-soft)" }}>{h}</th>
                ))}</tr></thead>
              )}
              <tbody>{tb.body.map((r, ri) => (
                <tr key={ri}>{(Array.isArray(r) ? r : [r]).map((c, ci) => (
                  <td key={ci} className="border px-2 py-1 align-top whitespace-pre-wrap" style={{ minWidth: 60, maxWidth: 420 }}>
                    {c == null ? "" : typeof c === "object" ? JSON.stringify(c) : String(c)}
                  </td>
                ))}</tr>
              ))}</tbody>
            </table>
          </div>
        </div>
      ))}
    </div>
  )
}

export function DatasetRowsTable({
  columns, rows, total, loading, error, onNeedMore, onLoadAll, onRetry, loadAllCap = Infinity,
}: DatasetRowsTableProps) {
  const [sortCol, setSortCol] = useState<number | null>(null)
  const [sortAsc, setSortAsc] = useState(true)
  const [filterText, setFilterText] = useState("")
  const [scrollTop, setScrollTop] = useState(0)
  const [openRow, setOpenRow] = useState<{ row: string[]; index: number } | null>(null)
  const boxRef = useRef<HTMLDivElement>(null)

  const allLoaded = total != null && rows.length >= total
  const view = useMemo(() => {
    const q = filterText.trim().toLowerCase()
    let out = q ? rows.filter((r) => r.some((c) => String(c ?? "").toLowerCase().includes(q))) : rows
    if (sortCol !== null) {
      out = out.slice().sort((a, b) => {
        const av = a[sortCol] ?? "", bv = b[sortCol] ?? ""
        const an = Number(av), bn = Number(bv)
        const cmp = av !== "" && bv !== "" && Number.isFinite(an) && Number.isFinite(bn)
          ? an - bn
          : String(av).localeCompare(String(bv))
        return sortAsc ? cmp : -cmp
      })
    }
    return out
  }, [rows, filterText, sortCol, sortAsc])
  // Columns holding nested JSON (JSONL lists/objects) — then rows open as structured records.
  const hasNested = useMemo(
    () => rows.slice(0, 50).some((r) => r.some((c) => parseNested(c) !== null)),
    [rows],
  )

  const viewH = boxRef.current?.clientHeight || FALLBACK_VIEW_H
  const start = Math.max(0, Math.floor(scrollTop / ROW_H) - OVERSCAN)
  const end = Math.min(view.length, Math.ceil((scrollTop + viewH) / ROW_H) + OVERSCAN)
  const slice = view.slice(start, end)

  const onScroll = (e: React.UIEvent<HTMLDivElement>) => {
    const el = e.currentTarget
    setScrollTop(el.scrollTop)
    if (!allLoaded && !loading && error == null && el.scrollTop + el.clientHeight >= el.scrollHeight - ROW_H * 10) {
      onNeedMore()
    }
  }

  const fmt = (n: number) => n.toLocaleString()
  return (
    <div className="space-y-1" data-testid="dataset-preview-table">
      <input
        value={filterText}
        onChange={(e) => setFilterText(e.target.value)}
        placeholder={t("dataset_obj.filter_placeholder")}
        aria-label={t("dataset_obj.filter_placeholder")}
        data-testid="dataset-preview-filter"
        className="w-full rounded border bg-background px-2 py-1 text-xs mb-1"
      />
      <div
        ref={boxRef}
        onScroll={onScroll}
        className="overflow-auto rounded border"
        style={{ maxHeight: "60vh" }}
        data-testid="dataset-preview-scroll"
      >
        <table className="w-full border-collapse text-sm">
          <thead>
            <tr style={{ background: "var(--bm-accent-soft)" }}>
              {columns.map((c, i) => (
                <th
                  key={i}
                  onClick={() => { if (sortCol === i) setSortAsc((a) => !a); else { setSortCol(i); setSortAsc(true) } }}
                  data-testid={`dataset-col-sort-${i}`}
                  title={t("dataset_obj.sort_title")}
                  className="whitespace-nowrap px-2 py-1 text-left font-semibold border-b cursor-pointer select-none"
                  style={{ color: "var(--bm-accent-ink)", position: "sticky", top: 0, background: "var(--bm-accent-soft)", zIndex: 1 }}
                >
                  {c}{sortCol === i ? (sortAsc ? " ▲" : " ▼") : ""}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {start > 0 && <tr aria-hidden style={{ height: start * ROW_H }} />}
            {slice.map((r, ri) => (
              <tr
                key={start + ri}
                className={`odd:bg-muted/20${hasNested ? " cursor-pointer hover:bg-muted/40" : ""}`}
                style={{ height: ROW_H }}
                data-testid="dataset-preview-row"
                onClick={hasNested ? () => setOpenRow({ row: r, index: rows.indexOf(r) }) : undefined}
              >
                {columns.map((_, ci) => {
                  const n = hasNested ? parseNested(r[ci]) : null
                  return (
                    <td
                      key={ci}
                      className="whitespace-nowrap px-2 py-0.5 font-mono border-b overflow-hidden text-ellipsis"
                      style={{ maxWidth: 360 }}
                      title={n ? undefined : (r[ci] ?? "")}
                    >
                      {n ? (
                        <span className="rounded border px-1.5 py-px text-[11px] text-muted-foreground font-sans" data-testid="dataset-nested-cell">
                          {nestedLabel(n)}
                        </span>
                      ) : (r[ci] ?? "")}
                    </td>
                  )
                })}
              </tr>
            ))}
            {end < view.length && <tr aria-hidden style={{ height: (view.length - end) * ROW_H }} />}
          </tbody>
        </table>
      </div>
      {openRow && (
        <RecordView columns={columns} row={openRow.row} index={openRow.index} onClose={() => setOpenRow(null)} />
      )}
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted-foreground" data-testid="dataset-preview-rowcount">
        {hasNested && !openRow && <span>{t("dataset_obj.record_hint")}</span>}
        <span>
          {allLoaded
            ? t("dataset_obj.rows_all_loaded", { total: fmt(total!) })
            : t("dataset_obj.rows_loaded", { loaded: fmt(rows.length), total: total != null ? fmt(total) : "?" })}
        </span>
        {filterText.trim() && <span>{t("dataset_obj.rows_matching", { n: fmt(view.length) })}</span>}
        <span data-testid="dataset-preview-scope">
          {allLoaded ? t("dataset_obj.rows_scope_full") : t("dataset_obj.rows_scope_partial")}
        </span>
        {loading && <span role="status">{t("dataset_obj.loading_more")}</span>}
        {error != null && (
          <span role="alert" className="text-destructive">
            {t("dataset_obj.rows_error", { status: error || "—" })}{" "}
            {onRetry && (
              <button type="button" className="underline" onClick={onRetry} data-testid="dataset-rows-retry">
                {t("dataset_obj.rows_retry")}
              </button>
            )}
          </span>
        )}
        {!allLoaded && onLoadAll && (total == null || total <= loadAllCap) && (
          <Button
            size="sm" variant="outline" className="h-6 px-2 text-xs ml-auto"
            disabled={loading} onClick={onLoadAll} data-testid="dataset-rows-load-all"
          >
            {t("dataset_obj.load_all")}
          </Button>
        )}
      </div>
    </div>
  )
}
