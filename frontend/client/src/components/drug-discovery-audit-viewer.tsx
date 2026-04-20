/**
 * Drug Discovery Audit Trail Viewer — Surface 3
 *
 * Displays the 21 CFR Part 11 SHA-256 hash-chain audit log for a campaign.
 * Verifies chain integrity on mount. Supports filter by user/action/date range.
 *
 * API:
 *   GET /api/drug-discovery/audit?resource_id=&limit=&offset=&user=&action=&from=&to=
 *   GET /api/drug-discovery/audit/verify
 *   GET /api/drug-discovery/audit/export?campaign_id=&format=csv|json
 *
 * data-testid attributes (matched by E2E test DD-CRO-3):
 *   chain-validity-badge, audit-export-button
 */
import { useState, useEffect, useCallback } from "react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import {
  Shield,
  ShieldAlert,
  Download,
  RotateCcw,
  User,
  Bot,
  PenLine,
  ChevronDown,
  ChevronUp,
  Loader2,
  AlertTriangle,
} from "lucide-react"
import { cn } from "@/lib/utils"

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface AuditRecord {
  id: number
  ts: string
  who: string
  kind: "user" | "system" | "esig"
  action: string
  resource: string
  payload_sha256: string  // hex, 64 chars
  record_hash: string     // hex, 64 chars
  prev_hash: string       // "0000…" for genesis
  detail?: string
  // eSig fields
  meaning?: string
  sig_id?: string
}

interface VerifyResult {
  valid: boolean
  verified_at: string
  broken_at?: number
  total_records: number
}

interface AuditPage {
  records: AuditRecord[]
  total: number
}

export interface AuditViewerProps {
  campaignId: string
  className?: string
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function hashShort(h: string, expanded: boolean): string {
  if (!h) return ""
  if (h.replace(/0/g, "").length === 0) return "genesis"
  return expanded ? h : h.slice(0, 8) + "…"
}

const KIND_ICON: Record<string, React.ReactNode> = {
  user:   <User   className="h-3 w-3 shrink-0" />,
  system: <Bot    className="h-3 w-3 shrink-0" />,
  esig:   <PenLine className="h-3 w-3 shrink-0" />,
}

const PAGE_SIZE = 10

// ---------------------------------------------------------------------------
// AuditRow
// ---------------------------------------------------------------------------

function AuditRow({
  rec,
  tampered,
}: {
  rec: AuditRecord
  tampered: boolean
}) {
  const [expanded, setExpanded] = useState(false)

  const rowCn = cn(
    "border-b border-border last:border-0 px-3 py-2 text-xs cursor-pointer",
    "hover:bg-muted/40 transition-colors",
    tampered && "bg-red-50 dark:bg-red-950/30 border-l-2 border-l-red-500",
    rec.kind === "esig" && !tampered && "bg-violet-50/40 dark:bg-violet-950/20",
    rec.kind === "system" && !tampered && "bg-muted/20",
  )

  return (
    <div className={rowCn} onClick={() => setExpanded((v) => !v)}>
      {/* Row 1: timestamp + expand toggle */}
      <div className="flex items-center justify-between text-muted-foreground mb-0.5">
        <span className="font-mono">{rec.ts}</span>
        {expanded ? (
          <ChevronUp className="h-3 w-3" />
        ) : (
          <ChevronDown className="h-3 w-3" />
        )}
      </div>

      {/* Row 2: who · action · resource */}
      <div className="flex items-center gap-1.5 flex-wrap">
        {KIND_ICON[rec.kind] ?? KIND_ICON.user}
        <span className="font-medium text-foreground">{rec.who}</span>
        <span className="text-muted-foreground">·</span>
        <span className="font-mono text-blue-700 dark:text-blue-400">{rec.action}</span>
        <span className="text-muted-foreground">·</span>
        <span className="text-muted-foreground truncate max-w-[180px]">{rec.resource}</span>
        {rec.detail && (
          <>
            <span className="text-muted-foreground">·</span>
            <span className="text-muted-foreground italic">{rec.detail}</span>
          </>
        )}
      </div>

      {/* eSig meaning */}
      {rec.meaning && (
        <div className="mt-1 text-violet-700 dark:text-violet-400 italic">
          "{rec.meaning}"
        </div>
      )}

      {/* Row 3: hashes */}
      <div className="flex items-center gap-2 mt-1 font-mono text-muted-foreground flex-wrap">
        <span>payload: <span className="text-foreground/60">{hashShort(rec.payload_sha256, expanded)}</span></span>
        <span>·</span>
        <span>hash: <span className="text-foreground/60">{hashShort(rec.record_hash, expanded)}</span></span>
        <span>←</span>
        <span>prev: <span className="text-foreground/60">{hashShort(rec.prev_hash, expanded)}</span></span>
        {rec.sig_id && (
          <>
            <span>·</span>
            <span>sig: <span className="text-foreground/60">{rec.sig_id}</span></span>
          </>
        )}
      </div>

      {tampered && (
        <div className="mt-1 text-red-600 dark:text-red-400 font-medium flex items-center gap-1">
          <AlertTriangle className="h-3 w-3" />
          Hash chain broken at this record
        </div>
      )}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Main component
// ---------------------------------------------------------------------------

export function DrugDiscoveryAuditViewer({ campaignId, className }: AuditViewerProps) {
  const [records, setRecords] = useState<AuditRecord[]>([])
  const [total, setTotal] = useState(0)
  const [offset, setOffset] = useState(0)
  const [loading, setLoading] = useState(false)
  const [loadError, setLoadError] = useState<string | null>(null)

  const [verify, setVerify] = useState<VerifyResult | null>(null)
  const [verifying, setVerifying] = useState(false)

  const [userFilter, setUserFilter] = useState("all")
  const [actionFilter, setActionFilter] = useState("all")
  const [dateRange, setDateRange] = useState("7d")

  const [exporting, setExporting] = useState(false)

  // Derived unique filter options from loaded records
  const users = ["all", ...Array.from(new Set(records.map((r) => r.who)))]
  const actions = ["all", ...Array.from(new Set(records.map((r) => r.action)))]

  const fetchRecords = useCallback(
    async (newOffset = 0) => {
      setLoading(true)
      setLoadError(null)
      const params = new URLSearchParams({
        resource_id: campaignId,
        limit: String(PAGE_SIZE),
        offset: String(newOffset),
      })
      if (userFilter !== "all") params.set("user", userFilter)
      if (actionFilter !== "all") params.set("action", actionFilter)
      if (dateRange !== "all") params.set("from", _dateRangeFrom(dateRange))

      try {
        const res = await fetch(`/api/drug-discovery/audit?${params}`, {
          credentials: "include",
        })
        if (!res.ok) {
          const err = await res.json().catch(() => ({ detail: res.statusText }))
          throw new Error(err.detail || `HTTP ${res.status}`)
        }
        const page: AuditPage = await res.json()
        if (newOffset === 0) {
          setRecords(page.records)
        } else {
          setRecords((prev) => [...prev, ...page.records])
        }
        setTotal(page.total)
        setOffset(newOffset + page.records.length)
      } catch (e: any) {
        setLoadError(e.message)
      } finally {
        setLoading(false)
      }
    },
    [campaignId, userFilter, actionFilter, dateRange],
  )

  const verifyChain = useCallback(async () => {
    setVerifying(true)
    try {
      const res = await fetch(
        `/api/drug-discovery/audit/verify?resource_id=${encodeURIComponent(campaignId)}`,
        { credentials: "include" },
      )
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      setVerify(await res.json())
    } catch (e: any) {
      setVerify({ valid: false, verified_at: new Date().toISOString(), total_records: 0 })
    } finally {
      setVerifying(false)
    }
  }, [campaignId])

  useEffect(() => {
    fetchRecords(0)
  }, [fetchRecords])

  useEffect(() => {
    verifyChain()
    // Re-verify every 30s while mounted
    const t = setInterval(verifyChain, 30_000)
    return () => clearInterval(t)
  }, [verifyChain])

  const exportAudit = async (format: "csv" | "json") => {
    setExporting(true)
    try {
      const res = await fetch(
        `/api/drug-discovery/audit/export?campaign_id=${encodeURIComponent(campaignId)}&format=${format}`,
        { credentials: "include" },
      )
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const blob = await res.blob()
      const url = URL.createObjectURL(blob)
      const a = document.createElement("a")
      a.href = url
      a.download = `audit_${campaignId}_${_isoDate()}.${format}`
      a.click()
      URL.revokeObjectURL(url)
    } finally {
      setExporting(false)
    }
  }

  const tamperedId = verify?.valid === false ? verify.broken_at : undefined

  // Empty state
  if (!loading && records.length === 0 && !loadError) {
    return (
      <div className={cn("space-y-4", className)}>
        <AuditHeader verify={verify} verifying={verifying} />
        <div className="flex flex-col items-center justify-center py-12 text-center gap-3">
          <Shield className="h-10 w-10 text-muted-foreground/40" />
          <p className="font-medium text-sm text-muted-foreground">No audit records yet</p>
          <p className="text-xs text-muted-foreground max-w-xs">
            Records are created automatically when you ingest assay data, export CRO
            orders, or generate proposals for this campaign.
          </p>
        </div>
      </div>
    )
  }

  return (
    <div className={cn("space-y-3", className)}>
      <AuditHeader verify={verify} verifying={verifying} onReVerify={verifyChain} />

      <p className="text-xs text-muted-foreground">
        Every regulated action is recorded immutably. Each record references the previous
        record's hash, forming a tamper-evident chain (21 CFR §11.10(e)).
      </p>

      {/* Filters */}
      <div className="flex items-center gap-2 flex-wrap">
        <Select value={userFilter} onValueChange={(v) => { setUserFilter(v); setOffset(0) }}>
          <SelectTrigger className="h-7 text-xs w-36">
            <SelectValue placeholder="All users" />
          </SelectTrigger>
          <SelectContent>
            {users.map((u) => (
              <SelectItem key={u} value={u} className="text-xs">
                {u === "all" ? "All users" : u}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>

        <Select value={actionFilter} onValueChange={(v) => { setActionFilter(v); setOffset(0) }}>
          <SelectTrigger className="h-7 text-xs w-40">
            <SelectValue placeholder="All actions" />
          </SelectTrigger>
          <SelectContent>
            {actions.map((a) => (
              <SelectItem key={a} value={a} className="text-xs">
                {a === "all" ? "All actions" : a}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>

        <Select value={dateRange} onValueChange={(v) => { setDateRange(v); setOffset(0) }}>
          <SelectTrigger className="h-7 text-xs w-32">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="24h" className="text-xs">Last 24h</SelectItem>
            <SelectItem value="7d" className="text-xs">Last 7 days</SelectItem>
            <SelectItem value="30d" className="text-xs">Last 30 days</SelectItem>
            <SelectItem value="all" className="text-xs">All time</SelectItem>
          </SelectContent>
        </Select>

        <div className="flex-1" />

        <Button
          size="sm"
          variant="outline"
          className="h-7 text-xs gap-1.5"
          disabled={exporting || verify?.valid === false}
          onClick={() => exportAudit("csv")}
          data-testid="audit-export-button"
        >
          {exporting ? (
            <Loader2 className="h-3 w-3 animate-spin" />
          ) : (
            <Download className="h-3 w-3" />
          )}
          Export CSV
        </Button>
      </div>

      {loadError && (
        <div className="rounded-md border border-red-200 bg-red-50 dark:bg-red-950/30 p-3 flex items-start gap-2 text-red-700 dark:text-red-400 text-xs">
          <AlertTriangle className="h-3.5 w-3.5 mt-0.5 shrink-0" />
          {loadError}
        </div>
      )}

      {/* Records list */}
      <div className="rounded-md border border-border overflow-hidden">
        {records.map((rec) => (
          <AuditRow key={rec.id} rec={rec} tampered={rec.id === tamperedId} />
        ))}
        {loading && (
          <div className="flex items-center justify-center py-6 text-muted-foreground">
            <Loader2 className="h-4 w-4 animate-spin" />
          </div>
        )}
      </div>

      {/* Footer */}
      <div className="flex items-center justify-between text-xs text-muted-foreground">
        <span>
          Showing {records.length} of {total} records
        </span>
        {records.length < total && (
          <Button
            size="sm"
            variant="ghost"
            className="h-7 text-xs"
            onClick={() => fetchRecords(offset)}
            disabled={loading}
          >
            {loading ? <Loader2 className="h-3 w-3 animate-spin mr-1" /> : null}
            Load more
          </Button>
        )}
      </div>

      {verify?.valid === false && (
        <div className="rounded-md border border-red-300 bg-red-50 dark:bg-red-950/40 p-3 text-xs text-red-700 dark:text-red-400 font-medium flex items-start gap-2">
          <ShieldAlert className="h-3.5 w-3.5 mt-0.5 shrink-0" />
          Chain verification failed at record #{verify.broken_at}. Contact your
          administrator immediately. Export is disabled until the issue is resolved.
        </div>
      )}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Sub-component: header with chain validity badge
// ---------------------------------------------------------------------------

function AuditHeader({
  verify,
  verifying,
  onReVerify,
}: {
  verify: VerifyResult | null
  verifying: boolean
  onReVerify?: () => void
}) {
  let badge: React.ReactNode
  if (verifying || verify === null) {
    badge = (
      <Badge variant="outline" className="text-xs gap-1 font-mono" data-testid="chain-validity-badge">
        <Loader2 className="h-3 w-3 animate-spin" />
        Verifying…
      </Badge>
    )
  } else if (verify.valid) {
    badge = (
      <Badge
        variant="outline"
        className="text-xs gap-1 font-mono bg-green-50 text-green-700 border-green-300 dark:bg-green-950/30 dark:text-green-400"
        data-testid="chain-validity-badge"
      >
        <Shield className="h-3 w-3" />
        Chain: VALID
      </Badge>
    )
  } else {
    badge = (
      <Badge
        variant="outline"
        className="text-xs gap-1 font-mono bg-red-50 text-red-700 border-red-400 dark:bg-red-950/30 dark:text-red-400"
        data-testid="chain-validity-badge"
      >
        <ShieldAlert className="h-3 w-3" />
        TAMPERED — record #{verify.broken_at}
      </Badge>
    )
  }

  return (
    <div className="flex items-center gap-2 flex-wrap">
      <h3 className="font-semibold text-sm">Audit Trail</h3>
      {badge}
      <Badge variant="outline" className="text-xs font-mono">21 CFR §11.10(e)</Badge>
      <Badge variant="outline" className="text-xs font-mono">SHA-256 hash chain</Badge>
      <div className="flex-1" />
      {onReVerify && (
        <Button
          size="sm"
          variant="ghost"
          className="h-7 text-xs gap-1.5"
          onClick={onReVerify}
          disabled={verifying}
        >
          <RotateCcw className="h-3 w-3" />
          Re-verify
        </Button>
      )}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

function _dateRangeFrom(range: string): string {
  const d = new Date()
  if (range === "24h") d.setHours(d.getHours() - 24)
  else if (range === "7d") d.setDate(d.getDate() - 7)
  else if (range === "30d") d.setDate(d.getDate() - 30)
  return d.toISOString()
}

function _isoDate(): string {
  return new Date().toISOString().slice(0, 10)
}
