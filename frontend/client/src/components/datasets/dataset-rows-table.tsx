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
import { lazy, Suspense, useMemo, useRef, useState } from "react"
import * as DialogPrimitive from "@radix-ui/react-dialog"
import { Button } from "@/components/ui/button"
import { Dialog, DialogOverlay, DialogPortal } from "@/components/ui/dialog"
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
  /** Edit mode: cells become inputs. Edits are keyed `${row}:${col}` by the row's position in
   *  the file (as loaded, before sort/filter) and keep the value the user saw (`from`). */
  editable?: boolean
  edits?: Record<string, { from: string; value: string }>
  onEdit?: (row: number, col: number, from: string, value: string) => void
}

/** Short structural label for a nested cell (a JSONL list/object), instead of truncated JSON text. */
function nestedLabel(n: NestedValue): string {
  if (n.kind === "matrix") return t("dataset_obj.nested_table", { rows: n.rows, cols: n.cols })
  if (n.kind === "list") return t("dataset_obj.nested_list", { n: n.rows })
  return t("dataset_obj.nested_object", { n: n.rows })
}

// Read-only JSON tree (json-edit-react: MIT, no runtime dependencies), loaded only when a record opens.
const JsonViewer = lazy(() => import("json-edit-react").then((m) => ({ default: m.JsonViewer })))

/** Theme from the app's tokens, so the tree follows light/dark mode. */
const JSON_THEME = {
  container: { backgroundColor: "transparent", color: "var(--foreground, inherit)", fontSize: 12, padding: 0 },
  property: { color: "var(--bm-accent-ink, inherit)" },
  bracket: { color: "var(--muted-foreground, inherit)" },
  itemCount: { color: "var(--muted-foreground, inherit)", fontStyle: "normal" },
  string: { color: "var(--foreground, inherit)" },
  number: { color: "var(--bm-accent, inherit)" },
  boolean: { color: "var(--bm-accent, inherit)" },
  null: { color: "var(--muted-foreground, inherit)" },
  iconCollection: "var(--muted-foreground, currentColor)",
  iconCopy: "var(--muted-foreground, currentColor)",
}

/** Searchable, collapsible view of any nested JSON value. */
function JsonTree({ value, name, search }: { value: unknown; name: string; search: string }) {
  return (
    <Suspense fallback={<span className="font-mono text-xs text-muted-foreground">…</span>}>
      <div data-testid="dataset-json-tree">
        <JsonViewer
          data={value}
          rootName={name}
          collapse={1}
          searchText={search}
          searchFilter="all"
          showCollectionCount="when-collapsed"
          showClipboardButton
          theme={JSON_THEME}
          minWidth="100%"
          maxWidth="100%"
        />
      </div>
    </Suspense>
  )
}

/**
 * One record, structured: scalar fields, embedded tables (with a matching header list), JSON trees.
 * `focusField` (the nested cell the user clicked) is marked and receives focus when the record opens.
 */
function RecordView({ columns, row, index, focusField, onClose }: {
  columns: string[]; row: string[]; index: number; focusField?: string | null; onClose: () => void
}) {
  const [search, setSearch] = useState("")
  const tables = recordTables(columns, row)
  const inTable = new Set(tables.flatMap((tb) => [tb.field, ...(tb.headerField ? [tb.headerField] : [])]))
  const focusRing = "rounded outline-none ring-2 ring-primary/50 bg-[var(--bm-accent-soft)]"
  return (
    <div className="space-y-2" data-testid="dataset-record-view">
      <div className="flex items-center gap-2">
        <DialogPrimitive.Title className="text-xs font-semibold flex-1">{t("dataset_obj.record_title", { n: index + 1 })}</DialogPrimitive.Title>
        <Button size="sm" variant="ghost" className="h-6 px-2 text-xs" onClick={onClose} data-testid="dataset-record-close">
          {t("dataset_obj.record_close")}
        </Button>
      </div>
      {columns.some((c, i) => !inTable.has(c) && parseNested(row[i])) && (
        <input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder={t("dataset_obj.record_search")}
          aria-label={t("dataset_obj.record_search")}
          data-testid="dataset-record-search"
          className="w-full rounded border bg-background px-2 py-1 text-xs"
        />
      )}
      <dl className="grid grid-cols-[max-content_1fr] gap-x-3 gap-y-0.5 text-xs">
        {columns.map((c, i) => {
          if (inTable.has(c)) return null
          const n = parseNested(row[i])
          const focused = focusField === c
          return [
            <dt key={`k${i}`} className={`text-muted-foreground font-mono${focused ? " font-semibold text-foreground" : ""}`}>{c}</dt>,
            <dd
              key={`v${i}`}
              className={`font-mono break-all${focused ? ` ${focusRing}` : ""}`}
              data-testid={`dataset-record-field-${c}`}
              data-focused={focused ? "true" : undefined}
              tabIndex={focused ? -1 : undefined}
            >
              {n ? <JsonTree value={n.value} name={c} search={search} /> : (row[i] ?? "")}
            </dd>,
          ]
        })}
      </dl>
      {tables.map((tb) => {
        const focused = focusField != null && (focusField === tb.field || focusField === tb.headerField)
        return (
          <div
            key={tb.field}
            className={`space-y-1${focused ? ` p-1 ${focusRing}` : ""}`}
            data-testid="dataset-record-table"
            data-field={tb.field}
            data-focused={focused ? "true" : undefined}
            tabIndex={focused ? -1 : undefined}
          >
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
        )
      })}
    </div>
  )
}

/**
 * The record opens in a dialog over the table — where the user is looking — rather than
 * below a 60vh scroll box, where it landed off-screen. Focus goes to the clicked field (or
 * the dialog), Esc / Close return focus to the cell that opened it.
 */
function RecordDialog({ columns, open, onClose, returnFocusTo }: {
  columns: string[]
  open: { row: string[]; index: number; field: string | null } | null
  onClose: () => void
  /** The control that opened the record; focus goes back to it on close. */
  returnFocusTo: React.RefObject<HTMLElement | null>
}) {
  const contentRef = useRef<HTMLDivElement>(null)
  return (
    <Dialog open={open != null} onOpenChange={(o) => { if (!o) onClose() }}>
      {open && (
        <DialogPortal>
          <DialogOverlay className="bg-black/40" />
          <DialogPrimitive.Content
            ref={contentRef}
            aria-describedby={undefined}
            className="fixed left-1/2 top-1/2 z-50 -translate-x-1/2 -translate-y-1/2 overflow-auto rounded-lg border bg-background p-3 shadow-lg"
            style={{ width: "min(56rem, calc(100vw - 2rem))", maxHeight: "85vh" }}
            data-testid="dataset-record-dialog"
            onCloseAutoFocus={(e) => {
              const el = returnFocusTo.current
              if (el && el.isConnected) { e.preventDefault(); el.focus() }
            }}
            onOpenAutoFocus={(e) => {
              const el = contentRef.current?.querySelector<HTMLElement>('[data-focused="true"]')
              if (!el) return
              e.preventDefault()
              el.focus({ preventScroll: true })
              el.scrollIntoView?.({ block: "center" })
            }}
          >
            <RecordView columns={columns} row={open.row} index={open.index} focusField={open.field} onClose={onClose} />
          </DialogPrimitive.Content>
        </DialogPortal>
      )}
    </Dialog>
  )
}

/** One-line display of a value: line breaks shown as ↵ (a "two\nlines" value must not read "twolines"). */
function showBreaks(v: string): string {
  return /\r|\n/.test(v) ? v.replace(/\r\n|\r|\n/g, " ↵ ") : v
}

export function DatasetRowsTable({
  columns, rows, total, loading, error, onNeedMore, onLoadAll, onRetry, loadAllCap = Infinity,
  editable = false, edits = {}, onEdit,
}: DatasetRowsTableProps) {
  const [sortCol, setSortCol] = useState<number | null>(null)
  const [sortAsc, setSortAsc] = useState(true)
  const [filterText, setFilterText] = useState("")
  const [scrollTop, setScrollTop] = useState(0)
  const [openRow, setOpenRow] = useState<{ row: string[]; index: number; field: string | null } | null>(null)
  const boxRef = useRef<HTMLDivElement>(null)
  const openerRef = useRef<HTMLElement | null>(null)

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
  // Row → its position in the file (rows load in file order); stable under sort / filter.
  const rowIndex = useMemo(() => new Map(rows.map((r, i) => [r, i] as const)), [rows])
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
                className={`odd:bg-muted/20${hasNested && !editable ? " cursor-pointer hover:bg-muted/40" : ""}`}
                style={{ height: ROW_H }}
                data-testid="dataset-preview-row"
                onClick={hasNested && !editable ? () => { openerRef.current = null; setOpenRow({ row: r, index: rowIndex.get(r) ?? 0, field: null }) } : undefined}
              >
                {columns.map((_, ci) => {
                  if (editable) {
                    const ri = rowIndex.get(r) ?? 0
                    const shown = r[ci] ?? ""
                    const key = `${ri}:${ci}`
                    const ed = edits[key]
                    const value = ed ? ed.value : shown
                    const cls = `w-full min-w-[6rem] rounded px-1 py-0.5 font-mono text-xs bg-transparent border ${ed ? "border-amber-500/60 bg-amber-500/5" : "border-transparent hover:border-border"}`
                    const common = {
                      value,
                      "aria-label": `${columns[ci]} · ${ri + 1}`,
                      "data-testid": `dataset-edit-cell-${ri}-${ci}`,
                    }
                    return (
                      <td key={ci} className="px-0.5 py-0 border-b">
                        {/\r|\n/.test(value) ? (
                          // An <input> strips line breaks: editing a multi-line value in one would
                          // silently save it without them. A one-row textarea keeps them.
                          <textarea
                            {...common}
                            rows={1}
                            className={`${cls} resize-none overflow-hidden whitespace-pre align-middle`}
                            style={{ height: ROW_H - 4 }}
                            onChange={(e) => onEdit?.(ri, ci, shown, e.target.value)}
                          />
                        ) : (
                          <input {...common} className={cls} onChange={(e) => onEdit?.(ri, ci, shown, e.target.value)} />
                        )}
                      </td>
                    )
                  }
                  const n = hasNested ? parseNested(r[ci]) : null
                  return (
                    <td
                      key={ci}
                      className="whitespace-nowrap px-2 py-0.5 font-mono border-b overflow-hidden text-ellipsis"
                      style={{ maxWidth: 360 }}
                      title={n ? undefined : (r[ci] ?? "")}
                    >
                      {n ? (
                        // A real control: click / Enter / Space opens this record on this field.
                        <button
                          type="button"
                          className="rounded border px-1.5 py-px text-[11px] text-muted-foreground font-sans hover:bg-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
                          data-testid="dataset-nested-cell"
                          aria-haspopup="dialog"
                          aria-label={`${t("dataset_obj.record_title", { n: (rowIndex.get(r) ?? 0) + 1 })} · ${columns[ci]}: ${nestedLabel(n)}`}
                          onClick={(e) => {
                            e.stopPropagation()
                            openerRef.current = e.currentTarget
                            setOpenRow({ row: r, index: rowIndex.get(r) ?? 0, field: columns[ci] })
                          }}
                        >
                          {nestedLabel(n)}
                        </button>
                      ) : showBreaks(r[ci] ?? "")}
                    </td>
                  )
                })}
              </tr>
            ))}
            {end < view.length && <tr aria-hidden style={{ height: (view.length - end) * ROW_H }} />}
            {total === 0 && rows.length === 0 && !loading && (
              // A header-only file: its columns are real, it just has no data rows yet.
              <tr data-testid="dataset-preview-no-rows">
                <td colSpan={Math.max(1, columns.length)} className="px-2 py-2 text-muted-foreground">{t("dataset_obj.no_data_rows")}</td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
      <RecordDialog columns={columns} open={openRow} onClose={() => setOpenRow(null)} returnFocusTo={openerRef} />
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted-foreground" data-testid="dataset-preview-rowcount">
        {hasNested && !openRow && !editable && <span>{t("dataset_obj.record_hint")}</span>}
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
