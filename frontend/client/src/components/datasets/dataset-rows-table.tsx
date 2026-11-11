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

export function DatasetRowsTable({
  columns, rows, total, loading, error, onNeedMore, onLoadAll, onRetry, loadAllCap = Infinity,
}: DatasetRowsTableProps) {
  const [sortCol, setSortCol] = useState<number | null>(null)
  const [sortAsc, setSortAsc] = useState(true)
  const [filterText, setFilterText] = useState("")
  const [scrollTop, setScrollTop] = useState(0)
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
              <tr key={start + ri} className="odd:bg-muted/20" style={{ height: ROW_H }} data-testid="dataset-preview-row">
                {columns.map((_, ci) => (
                  <td
                    key={ci}
                    className="whitespace-nowrap px-2 py-0.5 font-mono border-b overflow-hidden text-ellipsis"
                    style={{ maxWidth: 360 }}
                    title={r[ci] ?? ""}
                  >
                    {r[ci] ?? ""}
                  </td>
                ))}
              </tr>
            ))}
            {end < view.length && <tr aria-hidden style={{ height: (view.length - end) * ROW_H }} />}
          </tbody>
        </table>
      </div>
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted-foreground" data-testid="dataset-preview-rowcount">
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
