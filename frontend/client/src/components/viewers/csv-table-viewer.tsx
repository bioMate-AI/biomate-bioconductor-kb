/**
 * CSV/TSV Table Viewer Component
 * Displays tabular data files (CSV, TSV) with sortable columns, search, and statistics.
 * Follows the same pattern as VCFViewer — no external grid library needed.
 */

import { useState, useMemo } from "react"
import { useQuery } from "@tanstack/react-query"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Skeleton } from "@/components/ui/skeleton"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import {
  Download,
  Search,
  ArrowUpDown,
  ArrowUp,
  ArrowDown,
  Table2,
} from "lucide-react"
import type { OutputDataset } from "@shared/schema"

interface CsvTableViewerProps {
  output: OutputDataset
  className?: string
  defaultExpanded?: boolean
}

interface ParsedTable {
  headers: string[]
  rows: string[][]
  delimiter: ',' | '\t' | ';' | 'json'
  totalLines: number
  hasMore: boolean
}

type SortDirection = 'asc' | 'desc' | null

interface SortState {
  column: number | null
  direction: SortDirection
}

function detectDelimiter(firstLine: string): ',' | '\t' | ';' {
  const tabCount = (firstLine.match(/\t/g) || []).length
  const commaCount = (firstLine.match(/,/g) || []).length
  const semicolonCount = (firstLine.match(/;/g) || []).length
  if (tabCount >= commaCount && tabCount >= semicolonCount) return '\t'
  if (semicolonCount > commaCount) return ';'
  return ','
}

function parseCSVLine(line: string, delimiter: string): string[] {
  if (delimiter !== ',') return line.split(delimiter)
  // Handle quoted fields for CSV
  const result: string[] = []
  let current = ''
  let inQuotes = false
  for (let i = 0; i < line.length; i++) {
    const ch = line[i]
    if (ch === '"') {
      if (inQuotes && line[i + 1] === '"') { current += '"'; i++ }
      else inQuotes = !inQuotes
    } else if (ch === ',' && !inQuotes) {
      result.push(current.trim())
      current = ''
    } else {
      current += ch
    }
  }
  result.push(current.trim())
  return result
}

function isNumeric(value: string): boolean {
  return value !== '' && !isNaN(Number(value))
}

export function CsvTableViewer({ output, className, defaultExpanded = true }: CsvTableViewerProps) {
  const [search, setSearch] = useState('')
  const [sort, setSort] = useState<SortState>({ column: null, direction: null })
  const [showPreview, setShowPreview] = useState(defaultExpanded)

  const { data, isLoading, error } = useQuery<ParsedTable>({
    queryKey: ['csv-preview', output.id],
    queryFn: async () => {
      const res = await fetch(`/api/outputs/${output.id}/preview?lines=200`)
      if (!res.ok) throw new Error('Failed to fetch table preview')
      const json = await res.json() as { lines: string[]; totalLines: number; hasMore: boolean }
      if (!json.lines || json.lines.length === 0) throw new Error('Empty file')

      // JSON array detection: join all preview lines and try to parse as JSON array
      const fullContent = json.lines.join('\n').trim()
      if (fullContent.startsWith('[')) {
        try {
          const parsed = JSON.parse(fullContent)
          if (Array.isArray(parsed) && parsed.length > 0 && typeof parsed[0] === 'object') {
            const headers = Object.keys(parsed[0])
            const rows = parsed.map((item: Record<string, any>) =>
              headers.map(h => item[h] != null ? String(item[h]) : '')
            )
            return { headers, rows, delimiter: 'json', totalLines: parsed.length, hasMore: false }
          }
        } catch {
          // Not valid JSON — fall through to CSV parsing
        }
      }

      const delimiter = detectDelimiter(json.lines[0])
      const headers = parseCSVLine(json.lines[0], delimiter)
      const rows = json.lines.slice(1)
        .filter(l => l.trim() !== '')
        .map(l => parseCSVLine(l, delimiter))

      return { headers, rows, delimiter, totalLines: json.totalLines, hasMore: json.hasMore }
    },
    enabled: showPreview,
  })

  const delimiterLabel = data?.delimiter === 'json' ? 'JSON' : data?.delimiter === '\t' ? 'TSV' : data?.delimiter === ';' ? 'CSV (;)' : 'CSV'

  const filteredRows = useMemo(() => {
    if (!data) return []
    let rows = data.rows

    if (search.trim()) {
      const q = search.toLowerCase()
      rows = rows.filter(row => row.some(cell => cell.toLowerCase().includes(q)))
    }

    if (sort.column !== null && sort.direction !== null) {
      const col = sort.column
      const asc = sort.direction === 'asc'
      rows = [...rows].sort((a, b) => {
        const av = a[col] ?? ''
        const bv = b[col] ?? ''
        if (isNumeric(av) && isNumeric(bv)) {
          return asc ? Number(av) - Number(bv) : Number(bv) - Number(av)
        }
        return asc ? av.localeCompare(bv) : bv.localeCompare(av)
      })
    }

    return rows.slice(0, 500)
  }, [data, search, sort])

  function handleSort(colIndex: number) {
    setSort(prev => {
      if (prev.column === colIndex) {
        if (prev.direction === 'asc') return { column: colIndex, direction: 'desc' }
        if (prev.direction === 'desc') return { column: null, direction: null }
      }
      return { column: colIndex, direction: 'asc' }
    })
  }

  function handleDownload() {
    window.open(`/api/outputs/${output.id}/download`, '_blank')
  }

  const displayedRows = data ? Math.min(filteredRows.length, 500) : 0
  const totalDataRows = data ? data.rows.length : 0

  return (
    <Card className={className}>
      <CardHeader className="pb-3">
        <div className="flex items-start justify-between gap-2">
          <div className="min-w-0 flex-1">
            <CardTitle className="text-base truncate flex items-center gap-2">
              <Table2 className="h-4 w-4 shrink-0 text-muted-foreground" />
              {output.name}
            </CardTitle>
            <CardDescription className="text-xs mt-1 flex flex-wrap gap-x-3 gap-y-1">
              {data && <span>{delimiterLabel}</span>}
              {(output.metadata?.rows ?? (data && totalDataRows)) && (
                <span>{(output.metadata?.rows ?? totalDataRows).toLocaleString()} rows</span>
              )}
              {(output.metadata?.columns ?? (data && data.headers.length)) && (
                <span>{output.metadata?.columns ?? data?.headers.length} columns</span>
              )}
              <span>{(output.size / 1024).toFixed(1)} KB</span>
            </CardDescription>
          </div>
          <Button variant="outline" size="sm" onClick={handleDownload} className="shrink-0">
            <Download className="h-3 w-3 mr-1" />
            Download
          </Button>
        </div>
      </CardHeader>

      <CardContent className="space-y-3">
        <Button
          variant="outline"
          size="sm"
          onClick={() => setShowPreview(v => !v)}
          className="w-full"
        >
          {showPreview ? 'Hide Table' : 'Show Table'}
        </Button>

        {showPreview && (
          <>
            {isLoading && (
              <div className="space-y-2">
                <Skeleton className="h-8 w-full" />
                <Skeleton className="h-8 w-full" />
                <Skeleton className="h-8 w-full" />
              </div>
            )}

            {error && (
              <div className="text-sm text-destructive p-3 rounded-md bg-destructive/10">
                Failed to load table: {(error as Error).message}
              </div>
            )}

            {data && (
              <>
                {/* Search + delimiter badge */}
                <div className="flex gap-2 items-center">
                  <div className="relative flex-1">
                    <Search className="absolute left-2 top-2.5 h-3.5 w-3.5 text-muted-foreground" />
                    <Input
                      placeholder="Search all columns..."
                      value={search}
                      onChange={e => setSearch(e.target.value)}
                      className="pl-7 h-8 text-sm"
                    />
                  </div>
                  <Badge variant="secondary" className="shrink-0 font-mono text-xs">
                    {delimiterLabel}
                  </Badge>
                </div>

                {/* Table */}
                <ScrollArea className="h-[400px] rounded-lg border">
                  <Table>
                    <TableHeader className="sticky top-0 bg-background z-10">
                      <TableRow>
                        {data.headers.map((header, i) => (
                          <TableHead key={i} className="whitespace-nowrap">
                            <Button
                              variant="ghost"
                              size="sm"
                              className="h-auto p-0 font-semibold text-xs hover:bg-transparent"
                              onClick={() => handleSort(i)}
                            >
                              <span className="max-w-[120px] truncate">{header || `Col ${i + 1}`}</span>
                              {sort.column === i ? (
                                sort.direction === 'asc'
                                  ? <ArrowUp className="ml-1 h-3 w-3 shrink-0" />
                                  : <ArrowDown className="ml-1 h-3 w-3 shrink-0" />
                              ) : (
                                <ArrowUpDown className="ml-1 h-3 w-3 shrink-0 opacity-40" />
                              )}
                            </Button>
                          </TableHead>
                        ))}
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {filteredRows.length === 0 ? (
                        <TableRow>
                          <TableCell
                            colSpan={data.headers.length}
                            className="text-center text-muted-foreground text-sm py-8"
                          >
                            No rows match the search
                          </TableCell>
                        </TableRow>
                      ) : (
                        filteredRows.map((row, ri) => (
                          <TableRow key={ri} className="hover:bg-muted/40">
                            {data.headers.map((_, ci) => {
                              const cell = row[ci] ?? ''
                              const numeric = isNumeric(cell)
                              return (
                                <TableCell
                                  key={ci}
                                  className={`text-xs py-2 px-3 max-w-[200px] truncate font-mono ${numeric ? 'text-right tabular-nums' : ''}`}
                                  title={cell}
                                >
                                  {cell}
                                </TableCell>
                              )
                            })}
                          </TableRow>
                        ))
                      )}
                    </TableBody>
                  </Table>
                </ScrollArea>

                {/* Footer */}
                <div className="flex items-center justify-between text-xs text-muted-foreground">
                  <span>
                    Showing {displayedRows.toLocaleString()} of{' '}
                    {(data.hasMore ? `${totalDataRows}+` : totalDataRows.toLocaleString())} rows
                    {search ? ` (filtered)` : ''}
                  </span>
                  {(displayedRows === 500 || data.hasMore) && (
                    <span className="text-amber-500">
                      First {displayedRows} shown — download for full dataset
                    </span>
                  )}
                </div>
              </>
            )}
          </>
        )}
      </CardContent>
    </Card>
  )
}
