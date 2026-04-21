/**
 * Drug Discovery Auto-Retrain Loop — Surface 4
 *
 * DMTA Bayesian-optimization retrain loop: start/stop the loop,
 * trigger immediate retrains, view current and historical proposals,
 * manage the virtual library.
 *
 * API:
 *   GET  /api/drug-discovery/{id}/retrain/status      (polled every 5s)
 *   POST /api/drug-discovery/{id}/retrain/start
 *   POST /api/drug-discovery/{id}/retrain/stop
 *   POST /api/drug-discovery/{id}/retrain/trigger
 *   GET  /api/drug-discovery/{id}/auto-proposal
 *   GET  /api/drug-discovery/{id}/proposals
 *   GET  /api/drug-discovery/{id}/virtual-library
 *   POST /api/drug-discovery/{id}/virtual-library
 *
 * data-testid attributes (matched by E2E test DD-CRO-4):
 *   loop-status-badge, trigger-retrain-button, copy-smiles-button, download-csv-button
 */
import { useState, useEffect, useRef, useCallback } from "react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "@/components/ui/collapsible"
import {
  Play,
  Square,
  RefreshCw,
  Copy,
  Download,
  Upload,
  ExternalLink,
  ChevronDown,
  Loader2,
  AlertTriangle,
  FlaskConical,
} from "lucide-react"
import { cn } from "@/lib/utils"
import { useToast } from "@/hooks/use-toast"

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface RetrainStatus {
  running: boolean
  check_interval_s: number
  last_retrain_at: string | null
  next_check_in_s: number
  last_trigger: "manual" | "auto_retrain" | null
}

interface ProposalItem {
  rank: number
  smiles: string
  score: number
  ci_lo: number
  ci_hi: number
  ad: "in_domain" | "out_of_domain"
}

interface Proposal {
  round: number
  generated_at: string
  trigger: "manual" | "auto_retrain"
  items: ProposalItem[]
}

interface ProposalHistoryEntry {
  round: number
  ts: string
  n: number
  trigger: "manual" | "auto_retrain"
}

interface VirtualLibrary {
  n: number
  saved_at: string
  hash: string
  n_propose: number
  diversity_weight: number
}

export interface AutoRetrainProps {
  campaignId: string
  className?: string
}

// ---------------------------------------------------------------------------
// Score bar
// ---------------------------------------------------------------------------

function ScoreBar({ score }: { score: number }) {
  const pct = Math.round(Math.max(0, Math.min(1, score)) * 100)
  const color =
    pct >= 70 ? "bg-green-500" : pct >= 40 ? "bg-amber-500" : "bg-red-400"
  return (
    <div className="flex items-center gap-2">
      <div className="flex-1 h-1.5 bg-muted rounded-full overflow-hidden">
        <div className={cn("h-full rounded-full", color)} style={{ width: `${pct}%` }} />
      </div>
      <span className="font-mono text-xs w-10 text-right">{score.toFixed(3)}</span>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Proposal row
// ---------------------------------------------------------------------------

function ProposalRow({ item }: { item: ProposalItem }) {
  const [expanded, setExpanded] = useState(false)
  const wide = item.ci_hi - item.ci_lo > 0.2

  return (
    <tr
      onClick={() => setExpanded((v) => !v)}
      className={cn(
        "cursor-pointer hover:bg-muted/40 transition-colors text-xs",
        item.ad === "out_of_domain" && "opacity-50",
      )}
    >
      <td className="py-1.5 pl-3 pr-1 text-right font-mono text-muted-foreground w-8">
        {item.rank}
      </td>
      <td className="py-1.5 px-2 font-mono max-w-0">
        <span
          className="block truncate"
          title={item.smiles}
        >
          {expanded ? item.smiles : item.smiles.slice(0, 28) + (item.smiles.length > 28 ? "…" : "")}
        </span>
      </td>
      <td className="py-1.5 px-2 w-40">
        <ScoreBar score={item.score} />
      </td>
      <td
        className={cn(
          "py-1.5 px-2 font-mono w-28",
          wide ? "text-amber-600 dark:text-amber-400" : "text-muted-foreground",
        )}
      >
        {item.ci_lo.toFixed(2)}–{item.ci_hi.toFixed(2)}
      </td>
      <td className="py-1.5 px-2 w-28">
        <Badge
          variant="outline"
          className={cn(
            "text-xs font-mono",
            item.ad === "in_domain"
              ? "text-green-700 border-green-300 dark:text-green-400"
              : "text-amber-700 border-amber-300 dark:text-amber-400",
          )}
        >
          {item.ad === "in_domain" ? "In domain" : "OOD"}
        </Badge>
      </td>
    </tr>
  )
}

// ---------------------------------------------------------------------------
// Main component
// ---------------------------------------------------------------------------

export function DrugDiscoveryAutoRetrain({ campaignId, className }: AutoRetrainProps) {
  const { toast } = useToast()

  const [status, setStatus] = useState<RetrainStatus | null>(null)
  const [proposal, setProposal] = useState<Proposal | null>(null)
  const [history, setHistory] = useState<ProposalHistoryEntry[]>([])
  const [library, setLibrary] = useState<VirtualLibrary | null>(null)
  const [loadError, setLoadError] = useState<string | null>(null)

  const [actionLoading, setActionLoading] = useState<string | null>(null)
  const [countdown, setCountdown] = useState(0)

  const fileRef = useRef<HTMLInputElement>(null)
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null)

  // ---------------------------------------------------------------------------
  // Fetch helpers
  // ---------------------------------------------------------------------------

  const fetchStatus = useCallback(async () => {
    try {
      const res = await fetch(
        `/api/drug-discovery/${campaignId}/retrain/status`,
        { credentials: "include" },
      )
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const s: RetrainStatus = await res.json()
      setStatus(s)
      setCountdown(s.next_check_in_s)
    } catch (e: any) {
      setLoadError(e.message)
    }
  }, [campaignId])

  const fetchProposal = useCallback(async () => {
    try {
      const res = await fetch(
        `/api/drug-discovery/${campaignId}/auto-proposal?format=json`,
        { credentials: "include" },
      )
      if (res.status === 404) return  // no proposal yet — not an error
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      setProposal(await res.json())
    } catch (e: any) {
      setLoadError(e.message)
    }
  }, [campaignId])

  const fetchHistory = useCallback(async () => {
    try {
      const res = await fetch(
        `/api/drug-discovery/${campaignId}/proposals`,
        { credentials: "include" },
      )
      if (!res.ok) return
      const data = await res.json()
      setHistory(data.history || [])
    } catch {}
  }, [campaignId])

  const fetchLibrary = useCallback(async () => {
    try {
      const res = await fetch(
        `/api/drug-discovery/${campaignId}/virtual-library`,
        { credentials: "include" },
      )
      if (res.status === 404) return  // no library yet
      if (!res.ok) return
      setLibrary(await res.json())
    } catch {}
  }, [campaignId])

  // ---------------------------------------------------------------------------
  // Mount: initial load + polling
  // ---------------------------------------------------------------------------

  useEffect(() => {
    fetchStatus()
    fetchProposal()
    fetchHistory()
    fetchLibrary()

    pollRef.current = setInterval(fetchStatus, 5_000)
    return () => {
      if (pollRef.current) clearInterval(pollRef.current)
    }
  }, [fetchStatus, fetchProposal, fetchHistory, fetchLibrary])

  // Countdown ticker
  useEffect(() => {
    if (!status?.running) return
    const t = setInterval(
      () => setCountdown((c) => (c <= 0 ? status.check_interval_s : c - 1)),
      1000,
    )
    return () => clearInterval(t)
  }, [status])

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  const loopAction = async (action: "start" | "stop") => {
    setActionLoading(action)
    try {
      const res = await fetch(
        `/api/drug-discovery/${campaignId}/retrain/${action}`,
        { method: "POST", credentials: "include" },
      )
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      await fetchStatus()
    } catch (e: any) {
      toast({ variant: "destructive", title: `Failed to ${action} loop`, description: e.message })
    } finally {
      setActionLoading(null)
    }
  }

  const triggerRetrain = async () => {
    setActionLoading("trigger")
    try {
      const res = await fetch(
        `/api/drug-discovery/${campaignId}/retrain/trigger`,
        { method: "POST", credentials: "include" },
      )
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const newProposal: Proposal = await res.json()
      setProposal(newProposal)
      await fetchHistory()
      toast({ title: "Retrain complete", description: "Proposals refreshed." })
    } catch (e: any) {
      toast({ variant: "destructive", title: "Retrain failed", description: e.message })
    } finally {
      setActionLoading(null)
    }
  }

  const copySmiles = () => {
    if (!proposal?.items) return
    const text = proposal.items.map((p) => p.smiles).join("\n")
    navigator.clipboard?.writeText(text)
    toast({ title: `Copied ${proposal.items.length} SMILES` })
  }

  const downloadCsv = async () => {
    setActionLoading("download")
    try {
      const res = await fetch(
        `/api/drug-discovery/${campaignId}/auto-proposal?format=csv`,
        { credentials: "include" },
      )
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const blob = await res.blob()
      const url = URL.createObjectURL(blob)
      const a = document.createElement("a")
      a.href = url
      a.download = `${campaignId}_round${proposal?.round ?? "latest"}_proposals.csv`
      a.click()
      URL.revokeObjectURL(url)
    } catch (e: any) {
      toast({ variant: "destructive", title: "Download failed", description: e.message })
    } finally {
      setActionLoading(null)
    }
  }

  const uploadLibrary = async (file: File) => {
    const text = await file.text()
    const lines = text
      .split("\n")
      .map((l) => l.trim())
      .filter((l) => l && !l.startsWith("#") && !l.toLowerCase().startsWith("smiles"))

    setActionLoading("upload")
    try {
      const res = await fetch(
        `/api/drug-discovery/${campaignId}/virtual-library`,
        {
          method: "POST",
          credentials: "include",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            smiles: lines,
            n_propose: library?.n_propose ?? 10,
            diversity_weight: library?.diversity_weight ?? 0.2,
          }),
        },
      )
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const result = await res.json()
      await fetchLibrary()
      toast({
        title: "Library uploaded",
        description: `${result.n_valid} valid / ${result.n_invalid} invalid SMILES`,
      })
    } catch (e: any) {
      toast({ variant: "destructive", title: "Upload failed", description: e.message })
    } finally {
      setActionLoading(null)
    }
  }

  // ---------------------------------------------------------------------------
  // Empty state — no virtual library yet
  // ---------------------------------------------------------------------------

  if (status && !library && !loadError) {
    return (
      <div className={cn("space-y-4", className)}>
        <AutoRetrainHeader status={status} />
        <div className="flex flex-col items-center justify-center py-12 text-center gap-3">
          <FlaskConical className="h-10 w-10 text-muted-foreground/40" />
          <p className="font-medium text-sm text-muted-foreground">No virtual library yet</p>
          <p className="text-xs text-muted-foreground max-w-xs">
            Upload a library of candidate compounds (.csv or .smi) to enable
            auto-retrain proposals.
          </p>
          <Button
            size="sm"
            className="gap-2"
            onClick={() => fileRef.current?.click()}
            disabled={actionLoading === "upload"}
          >
            {actionLoading === "upload" ? (
              <Loader2 className="h-3.5 w-3.5 animate-spin" />
            ) : (
              <Upload className="h-3.5 w-3.5" />
            )}
            Upload Virtual Library
          </Button>
          <input
            ref={fileRef}
            type="file"
            accept=".csv,.smi,.txt"
            className="hidden"
            onChange={(e) => {
              const f = e.target.files?.[0]
              if (f) uploadLibrary(f)
            }}
          />
        </div>
      </div>
    )
  }

  // ---------------------------------------------------------------------------
  // Full view
  // ---------------------------------------------------------------------------

  return (
    <div className={cn("space-y-4", className)}>
      <AutoRetrainHeader status={status} />

      {loadError && (
        <div className="rounded-md border border-red-200 bg-red-50 dark:bg-red-950/30 p-3 flex items-start gap-2 text-red-700 dark:text-red-400 text-xs">
          <AlertTriangle className="h-3.5 w-3.5 mt-0.5 shrink-0" />
          {loadError}
        </div>
      )}

      {/* Loop control strip */}
      <div data-tour="loop-strip" className="flex items-center gap-3 flex-wrap rounded-md border border-border bg-muted/20 px-3 py-2">
        <Badge
          variant="outline"
          className={cn(
            "text-xs font-mono gap-1",
            status?.running
              ? "bg-blue-50 text-blue-700 border-blue-300 dark:bg-blue-950/30 dark:text-blue-400 animate-pulse"
              : "text-muted-foreground",
          )}
          data-testid="loop-status-badge"
        >
          {status?.running ? "RUNNING" : "STOPPED"}
        </Badge>

        {status?.running && (
          <span className="text-xs text-muted-foreground">
            Next check in <span className="font-mono font-medium">{countdown}s</span>
          </span>
        )}
        {status?.last_retrain_at && (
          <span className="text-xs text-muted-foreground">
            Last retrain: <span className="font-medium">{_fmtTs(status.last_retrain_at)}</span>
          </span>
        )}
        {status?.last_trigger && (
          <Badge variant="outline" className="text-xs font-mono">
            {status.last_trigger}
          </Badge>
        )}

        <div className="flex-1" />

        {status?.running ? (
          <Button
            size="sm"
            variant="outline"
            className="h-7 text-xs gap-1.5"
            onClick={() => loopAction("stop")}
            disabled={actionLoading === "stop"}
          >
            {actionLoading === "stop" ? (
              <Loader2 className="h-3 w-3 animate-spin" />
            ) : (
              <Square className="h-3 w-3" />
            )}
            Stop
          </Button>
        ) : (
          <Button
            size="sm"
            className="h-7 text-xs gap-1.5"
            onClick={() => loopAction("start")}
            disabled={actionLoading === "start"}
          >
            {actionLoading === "start" ? (
              <Loader2 className="h-3 w-3 animate-spin" />
            ) : (
              <Play className="h-3 w-3" />
            )}
            Start
          </Button>
        )}

        <Button
          size="sm"
          variant="outline"
          className="h-7 text-xs gap-1.5"
          onClick={triggerRetrain}
          disabled={actionLoading === "trigger"}
          data-testid="trigger-retrain-button"
        >
          {actionLoading === "trigger" ? (
            <Loader2 className="h-3 w-3 animate-spin" />
          ) : (
            <RefreshCw className="h-3 w-3" />
          )}
          Trigger now
        </Button>
      </div>

      {/* Current proposal */}
      {proposal && Array.isArray(proposal.items) ? (
        <div className="space-y-2">
          <div className="flex items-baseline gap-3">
            <span className="font-semibold text-sm">
              Latest Proposal — Round {proposal.round}
            </span>
            <span className="text-xs text-muted-foreground">
              {_fmtTs(proposal.generated_at)} · {proposal.items.length} compounds ·{" "}
              <Badge variant="outline" className="text-xs font-mono">
                {proposal.trigger}
              </Badge>
            </span>
          </div>

          <div className="rounded-md border border-border overflow-x-auto">
            <table className="w-full text-xs">
              <thead>
                <tr className="border-b border-border bg-muted/30">
                  <th className="py-1.5 pl-3 pr-1 text-right w-8 font-medium text-muted-foreground">#</th>
                  <th className="py-1.5 px-2 text-left font-medium text-muted-foreground">SMILES</th>
                  <th className="py-1.5 px-2 w-40 font-medium text-muted-foreground">Score</th>
                  <th className="py-1.5 px-2 w-28 font-medium text-muted-foreground">CI 95%</th>
                  <th className="py-1.5 px-2 w-28 font-medium text-muted-foreground">AD</th>
                </tr>
              </thead>
              <tbody>
                {proposal.items.map((item) => (
                  <ProposalRow key={item.rank} item={item} />
                ))}
              </tbody>
            </table>
          </div>

          <div className="flex items-center gap-2">
            <Button
              size="sm"
              variant="outline"
              className="h-7 text-xs gap-1.5"
              onClick={copySmiles}
              data-testid="copy-smiles-button"
            >
              <Copy className="h-3 w-3" />
              Copy SMILES
            </Button>
            <Button
              size="sm"
              variant="outline"
              className="h-7 text-xs gap-1.5"
              onClick={downloadCsv}
              disabled={actionLoading === "download"}
              data-testid="download-csv-button"
            >
              {actionLoading === "download" ? (
                <Loader2 className="h-3 w-3 animate-spin" />
              ) : (
                <Download className="h-3 w-3" />
              )}
              Download CSV
            </Button>
            <Button
              size="sm"
              className="h-7 text-xs gap-1.5"
              onClick={() => {
                window.dispatchEvent(
                  new CustomEvent("biomate:open-cro-export", {
                    detail: { campaignId, round: proposal.round },
                  }),
                )
              }}
            >
              <ExternalLink className="h-3 w-3" />
              Export to CRO
            </Button>
          </div>
        </div>
      ) : (
        !loadError && (
          <div className="text-xs text-muted-foreground py-4 text-center">
            No proposals yet. Trigger a retrain to generate the first round.
          </div>
        )
      )}

      {/* Proposal history */}
      {history.length > 0 && (
        <Collapsible>
          <CollapsibleTrigger asChild>
            <Button variant="ghost" size="sm" className="h-7 text-xs gap-1.5 w-full justify-start">
              <ChevronDown className="h-3.5 w-3.5" />
              Proposal History ({history.length} rounds)
            </Button>
          </CollapsibleTrigger>
          <CollapsibleContent>
            <div className="space-y-1.5 mt-2">
              {history.map((h) => (
                <div
                  key={h.round}
                  className="flex items-center gap-2 rounded-md border border-border px-3 py-2 text-xs"
                >
                  <span className="font-semibold">Round {h.round}</span>
                  <span className="font-mono text-muted-foreground">{_fmtTs(h.ts)}</span>
                  <span className="text-muted-foreground">· {h.n} proposals</span>
                  <Badge variant="outline" className="text-xs font-mono ml-auto">
                    {h.trigger}
                  </Badge>
                </div>
              ))}
            </div>
          </CollapsibleContent>
        </Collapsible>
      )}

      {/* Virtual library */}
      {library && (
        <Collapsible>
          <CollapsibleTrigger asChild>
            <Button variant="ghost" size="sm" className="h-7 text-xs gap-1.5 w-full justify-start">
              <ChevronDown className="h-3.5 w-3.5" />
              Virtual Library ({library.n.toLocaleString()} compounds cached)
            </Button>
          </CollapsibleTrigger>
          <CollapsibleContent>
            <div className="mt-2 space-y-3">
              <p className="text-xs text-muted-foreground">
                Saved {_fmtTs(library.saved_at)} · hash{" "}
                <span className="font-mono">{library.hash.slice(0, 4)}…{library.hash.slice(-4)}</span>
              </p>
              <div className="grid grid-cols-2 gap-3">
                <div className="space-y-1">
                  <label className="text-xs font-medium text-muted-foreground">
                    Proposals per round
                  </label>
                  <div className="text-sm font-medium">{library.n_propose}</div>
                </div>
                <div className="space-y-1">
                  <label className="text-xs font-medium text-muted-foreground">
                    Diversity weight
                  </label>
                  <div className="text-sm font-medium">{library.diversity_weight}</div>
                </div>
              </div>
              <Button
                size="sm"
                variant="outline"
                className="h-7 text-xs gap-1.5"
                onClick={() => fileRef.current?.click()}
                disabled={actionLoading === "upload"}
              >
                {actionLoading === "upload" ? (
                  <Loader2 className="h-3 w-3 animate-spin" />
                ) : (
                  <Upload className="h-3 w-3" />
                )}
                Replace virtual library
              </Button>
              <input
                ref={fileRef}
                type="file"
                accept=".csv,.smi,.txt"
                className="hidden"
                onChange={(e) => {
                  const f = e.target.files?.[0]
                  if (f) uploadLibrary(f)
                }}
              />
            </div>
          </CollapsibleContent>
        </Collapsible>
      )}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Sub-component: header
// ---------------------------------------------------------------------------

function AutoRetrainHeader({ status }: { status: RetrainStatus | null }) {
  return (
    <div className="flex items-center gap-2 flex-wrap">
      <h3 className="font-semibold text-sm">Auto-Retrain Loop</h3>
      <Badge variant="outline" className="text-xs font-mono">DMTA · Round-based retraining</Badge>
      {status === null && <Loader2 className="h-3.5 w-3.5 animate-spin text-muted-foreground" />}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

function _fmtTs(iso: string): string {
  try {
    return new Date(iso).toLocaleString(undefined, {
      month: "short",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    })
  } catch {
    return iso
  }
}
