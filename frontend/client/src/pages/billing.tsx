import { useState, useEffect, useCallback } from "react"
import { useLocation } from "wouter"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import {
  ChevronDown,
  ExternalLink,
  Loader2,
  AlertCircle,
  CheckCircle2,
  RefreshCw,
  Zap,
  TrendingUp,
  RotateCcw,
  CreditCard,
} from "lucide-react"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Switch } from "@/components/ui/switch"
import { Label } from "@/components/ui/label"
import { useToast } from "@/hooks/use-toast"
import { cn } from "@/lib/utils"

// ── credit packs ───────────────────────────────────────────────────────────

const CREDIT_PACKS = [
  { label: "$10", cents: 1000, description: "~500K tokens or 2 hrs CPU" },
  { label: "$25", cents: 2500, description: "~1.3M tokens or 5 hrs CPU", popular: true },
  { label: "$50", cents: 5000, description: "~2.6M tokens or 1 hr GPU" },
]

const AUTO_CHARGE_KEY = "biomate_auto_charge"

interface AutoChargePrefs {
  enabled: boolean
  thresholdPct: number   // trigger at this quota %
  amountCents: number    // how much to top up
}

function loadAutoCharge(): AutoChargePrefs {
  try {
    const raw = localStorage.getItem(AUTO_CHARGE_KEY)
    if (raw) return JSON.parse(raw) as AutoChargePrefs
  } catch {}
  return { enabled: false, thresholdPct: 80, amountCents: 2500 }
}

function saveAutoCharge(prefs: AutoChargePrefs) {
  localStorage.setItem(AUTO_CHARGE_KEY, JSON.stringify(prefs))
}

// ── types ──────────────────────────────────────────────────────────────────

interface LLMBreakdown {
  total_usd: number
  input_usd: number
  output_usd: number
  tokens_in: number
  tokens_out: number
  calls: number
}

interface ComputeBreakdown {
  total_usd: number
  vcpu_usd: number
  gpu_usd: number
  mem_usd: number
  jobs: number
  total_hours: number
}

interface StorageBreakdown {
  total_usd: number
  size_gb: number
  put_count: number
}

interface UsageData {
  user_id: string
  month: string
  committed_usd: number
  running_estimate_usd: number
  total_usd: number
  quota_usd: number | null
  quota_pct: number | null
  breakdown: {
    llm: LLMBreakdown
    compute: ComputeBreakdown
    storage: StorageBreakdown
  }
  running_jobs: any[]
  currency: string
}

interface Subscription {
  plan: string
  status: string
  currentPeriodStart?: number
  currentPeriodEnd?: number
  cancelAtPeriodEnd?: boolean
}

// ── helpers ────────────────────────────────────────────────────────────────

function fmt(v: number): string {
  if (v === 0) return "$0.00"
  return `$${v.toFixed(2)}`
}

function fmtTokens(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M tokens`
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K tokens`
  return `${n} tokens`
}

function fmtPct(pct: number | null): string {
  if (pct === null) return "—"
  return `${pct.toFixed(1)}%`
}

function cycleLabel(month: string): string {
  // month = "2026-02"
  const [year, m] = month.split("-").map(Number)
  const start = new Date(year, m - 1, 1)
  const end = new Date(year, m, 0) // last day of month
  const opts: Intl.DateTimeFormatOptions = { month: "short", day: "numeric", year: "numeric" }
  return `${start.toLocaleDateString("en-US", opts)} - ${end.toLocaleDateString("en-US", opts)}`
}

function monthLabel(month: string): string {
  const [year, m] = month.split("-").map(Number)
  return new Date(year, m - 1, 1).toLocaleDateString("en-US", { month: "long", year: "numeric" })
}

function authHeader(): HeadersInit {
  const token = localStorage.getItem("auth_token")
  return token ? { Authorization: `Bearer ${token}` } : {}
}

// ── data hooks ─────────────────────────────────────────────────────────────

function useCurrentUsage() {
  const [data, setData] = useState<UsageData | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetch_ = useCallback(async () => {
    try {
      const res = await fetch("/api/billing/usage", { headers: authHeader() })
      if (res.status === 401) { setError("Not authenticated"); return }
      if (!res.ok) { setError(`Error ${res.status}`); return }
      setData(await res.json())
      setError(null)
    } catch {
      setError("Failed to load usage data")
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { fetch_() }, [fetch_])
  return { data, loading, error, refresh: fetch_ }
}

function useUsageHistory(months: number) {
  const [history, setHistory] = useState<UsageData[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    async function load() {
      try {
        const res = await fetch(`/api/billing/usage/history?months=${months}`, {
          headers: authHeader(),
        })
        if (res.ok) {
          const body = await res.json()
          setHistory(body.history ?? [])
        }
      } catch {
        // non-critical
      } finally {
        setLoading(false)
      }
    }
    load()
  }, [months])

  return { history, loading }
}

function useSubscription() {
  const [sub, setSub] = useState<Subscription | null>(null)

  useEffect(() => {
    async function load() {
      try {
        const res = await fetch("/api/payments/subscription", { headers: authHeader() })
        if (res.ok) setSub(await res.json())
      } catch {
        // non-critical
      }
    }
    load()
  }, [])

  return sub
}

// ── sub-components ─────────────────────────────────────────────────────────

// ── AddCreditsDialog ───────────────────────────────────────────────────────

function AddCreditsDialog({
  open,
  onOpenChange,
}: {
  open: boolean
  onOpenChange: (v: boolean) => void
}) {
  const { toast } = useToast()
  const [selected, setSelected] = useState(2500)  // default $25
  const [loading, setLoading] = useState(false)

  async function handleCheckout() {
    setLoading(true)
    try {
      const res = await fetch("/api/payments/add-credits", {
        method: "POST",
        headers: {
          ...authHeader(),
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          amountCents: selected,
          returnUrl: window.location.href,
        }),
      })
      if (!res.ok) {
        const err = await res.json().catch(() => ({})) as { message?: string }
        throw new Error(err.message ?? `HTTP ${res.status}`)
      }
      const { url } = await res.json() as { url?: string }
      if (url) {
        window.location.href = url
      } else {
        // Stripe not configured — simulate success for dev
        toast({ title: "Credits added (dev mode)", description: `+$${(selected / 100).toFixed(2)} added to your quota.` })
        onOpenChange(false)
      }
    } catch (e: any) {
      toast({ title: "Payment failed", description: e.message, variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Add Credits</DialogTitle>
          <DialogDescription>
            Credits are added to your monthly quota immediately after payment.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3 py-2">
          {CREDIT_PACKS.map((pack) => (
            <button
              key={pack.cents}
              onClick={() => setSelected(pack.cents)}
              className={cn(
                "w-full flex items-center justify-between rounded-lg border px-4 py-3 text-left transition-colors",
                selected === pack.cents
                  ? "border-primary bg-primary/5"
                  : "border-border hover:border-primary/50 hover:bg-muted/50"
              )}
            >
              <div>
                <span className="font-semibold text-base">{pack.label}</span>
                {pack.popular && (
                  <span className="ml-2 text-xs bg-primary/10 text-primary px-1.5 py-0.5 rounded-full">
                    Popular
                  </span>
                )}
                <p className="text-xs text-muted-foreground mt-0.5">{pack.description}</p>
              </div>
              <div className={cn(
                "w-4 h-4 rounded-full border-2 flex-shrink-0",
                selected === pack.cents ? "border-primary bg-primary" : "border-muted-foreground"
              )} />
            </button>
          ))}
        </div>

        <div className="flex gap-3 pt-2">
          <Button variant="outline" className="flex-1" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button className="flex-1 gap-2" onClick={handleCheckout} disabled={loading}>
            {loading ? <Loader2 className="w-4 h-4 animate-spin" /> : <Zap className="w-4 h-4" />}
            Pay ${(selected / 100).toFixed(0)}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}

// ── QuotaWarningBanner ─────────────────────────────────────────────────────

function QuotaWarningBanner({
  pct,
  used,
  quota,
  onAddCredits,
  onUpgrade,
  autoCharge,
  onAutoChargeChange,
}: {
  pct: number
  used: number
  quota: number | null
  onAddCredits: () => void
  onUpgrade: () => void
  autoCharge: AutoChargePrefs
  onAutoChargeChange: (prefs: AutoChargePrefs) => void
}) {
  if (pct < 80) return null

  const isExceeded = pct >= 100
  const autoPackLabel = CREDIT_PACKS.find((p) => p.cents === autoCharge.amountCents)?.label ?? "$25"

  return (
    <div className={cn(
      "rounded-xl border px-5 py-4 mb-6",
      isExceeded
        ? "border-destructive/40 bg-destructive/5"
        : "border-yellow-400/40 bg-yellow-50/50 dark:bg-yellow-900/10"
    )}>
      <div className="flex items-start gap-3">
        <AlertCircle className={cn(
          "w-5 h-5 mt-0.5 flex-shrink-0",
          isExceeded ? "text-destructive" : "text-yellow-600 dark:text-yellow-400"
        )} />
        <div className="flex-1 min-w-0">
          <p className={cn(
            "font-semibold text-sm",
            isExceeded ? "text-destructive" : "text-yellow-800 dark:text-yellow-200"
          )}>
            {isExceeded
              ? "Quota exceeded — new jobs are paused"
              : `${pct.toFixed(0)}% of your monthly quota used`}
          </p>
          <p className="text-xs text-muted-foreground mt-0.5">
            {fmt(used)} used
            {quota ? ` of ${fmt(quota)} limit` : ""}
            {isExceeded && " — add credits or upgrade to resume workflows"}
          </p>

          {/* Action buttons */}
          <div className="flex flex-wrap items-center gap-2 mt-3">
            <Button size="sm" className="gap-1.5" onClick={onAddCredits}>
              <Zap className="w-3.5 h-3.5" />
              Add Credits
            </Button>
            <Button size="sm" variant="outline" className="gap-1.5" onClick={onUpgrade}>
              <TrendingUp className="w-3.5 h-3.5" />
              Upgrade Plan
            </Button>
          </div>

          {/* Auto-charge toggle */}
          <div className="flex items-center justify-between mt-4 pt-3 border-t border-border/50">
            <div className="flex items-center gap-2">
              <RotateCcw className="w-3.5 h-3.5 text-muted-foreground" />
              <Label htmlFor="auto-charge" className="text-sm cursor-pointer">
                Auto-charge {autoPackLabel} when quota reaches {autoCharge.thresholdPct}%
              </Label>
            </div>
            <Switch
              id="auto-charge"
              checked={autoCharge.enabled}
              onCheckedChange={(checked) => {
                const next = { ...autoCharge, enabled: checked }
                saveAutoCharge(next)
                onAutoChargeChange(next)
              }}
            />
          </div>
          {autoCharge.enabled && (
            <p className="text-xs text-muted-foreground mt-1.5 ml-5">
              Your saved card will be charged {autoPackLabel} automatically when usage hits {autoCharge.thresholdPct}%.
              <button
                className="ml-1 underline hover:no-underline"
                onClick={onUpgrade}
              >
                Manage payment method
              </button>
            </p>
          )}
        </div>
      </div>
    </div>
  )
}

// ── SectionCard ────────────────────────────────────────────────────────────

function SectionCard({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <div className={cn("rounded-xl border border-border bg-card", className)}>
      {children}
    </div>
  )
}

function InvoiceStatusBadge({ status, refundAmount }: { status: string; refundAmount?: number }) {
  if (status === "paid") {
    return (
      <span className="inline-flex items-center gap-1 text-sm text-green-600 dark:text-green-400">
        <CheckCircle2 className="w-3.5 h-3.5" />
        Paid
      </span>
    )
  }
  if (status === "refunded" && refundAmount) {
    return (
      <span className="text-sm text-muted-foreground">
        Refunded ({fmt(refundAmount)})
      </span>
    )
  }
  if (status === "pending") {
    return (
      <span className="inline-flex items-center gap-1 text-sm text-yellow-600 dark:text-yellow-400">
        <Loader2 className="w-3.5 h-3.5 animate-spin" />
        Pending
      </span>
    )
  }
  return <span className="text-sm text-muted-foreground capitalize">{status}</span>
}

// ── main page ──────────────────────────────────────────────────────────────

export default function BillingPage() {
  const [, setLocation] = useLocation()
  const { data: usage, loading, error, refresh } = useCurrentUsage()
  const sub = useSubscription()

  // invoice history — default to 6 months
  const [historyMonths] = useState(6)
  const { history, loading: historyLoading } = useUsageHistory(historyMonths)

  // selected month for invoice filter; "all" = show everything
  const [invoiceMonth, setInvoiceMonth] = useState<string>("all")
  useEffect(() => {
    if (history.length > 0 && invoiceMonth === "all") {
      setInvoiceMonth(history[0]?.month ?? "all")
    }
  }, [history, invoiceMonth])

  const [portalLoading, setPortalLoading] = useState(false)
  const [showAddCredits, setShowAddCredits] = useState(false)
  const [autoCharge, setAutoCharge] = useState<AutoChargePrefs>(loadAutoCharge)
  const { toast } = useToast()

  // ── derived values (hoisted so useEffect below can reference them) ─────────
  const quota = usage?.quota_usd ?? null
  const total = usage?.total_usd ?? 0
  const pct = usage?.quota_pct ?? (quota ? Math.min((total / quota) * 100, 100) : null)
  const over = pct !== null && pct >= 100
  const running = usage?.running_estimate_usd ?? 0

  // Auto-charge: trigger checkout automatically when threshold hit
  useEffect(() => {
    if (!autoCharge.enabled || !pct || pct < autoCharge.thresholdPct) return
    // Only fire once per session (guard via sessionStorage)
    const guardKey = `biomate_autocharged_${new Date().toISOString().slice(0, 7)}`
    if (sessionStorage.getItem(guardKey)) return
    sessionStorage.setItem(guardKey, "1")
    toast({
      title: "Auto-charge triggered",
      description: `Adding ${CREDIT_PACKS.find(p => p.cents === autoCharge.amountCents)?.label ?? "$25"} in credits automatically.`,
    })
    // Small delay so toast is visible before redirect
    setTimeout(async () => {
      const res = await fetch("/api/payments/add-credits", {
        method: "POST",
        headers: { ...authHeader(), "Content-Type": "application/json" },
        body: JSON.stringify({ amountCents: autoCharge.amountCents, returnUrl: window.location.href }),
      }).catch(() => null)
      const body = res?.ok ? await res.json().catch(() => ({})) as { url?: string } : {}
      if (body.url) window.location.href = body.url
    }, 1500)
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [autoCharge.enabled, pct])

  async function handleManageSubscription() {
    setPortalLoading(true)
    try {
      const res = await fetch("/api/payments/create-portal-session", {
        method: "POST",
        headers: { ...authHeader(), "Content-Type": "application/json" },
        body: JSON.stringify({ returnUrl: window.location.href }),
      })
      if (res.ok) {
        const { url } = await res.json()
        if (url) window.location.href = url
      }
    } catch {
      // fallback: go to pricing
      setLocation("/pricing")
    } finally {
      setPortalLoading(false)
    }
  }

  // ── further breakdown derivations ─────────────────────────────────────────

  const llm = usage?.breakdown?.llm
  const compute = usage?.breakdown?.compute
  const storage = usage?.breakdown?.storage

  const totalTokens = (llm?.tokens_in ?? 0) + (llm?.tokens_out ?? 0)

  // plan included token quota (approximate: quota_usd / $0.02 per 1K tokens = N tokens)
  const TOKEN_COST_PER_K = 0.02 / 1000
  const includedTokens = quota ? Math.round(quota / TOKEN_COST_PER_K) : null

  const tokenPct = includedTokens && totalTokens
    ? Math.min((totalTokens / includedTokens) * 100, 100)
    : 0

  // invoice history filtered to selected month
  const invoiceRows = history.map((h) => ({
    month: h.month,
    label: monthLabel(h.month),
    total: h.total_usd,
    status: h.total_usd > 0 ? "paid" : "pending",
  }))

  const filteredInvoice = invoiceMonth && invoiceMonth !== "all"
    ? invoiceRows.filter((r) => r.month === invoiceMonth)
    : invoiceRows

  // current billing cycle label
  const cycleStr = usage ? cycleLabel(usage.month) : "—"

  const planName = sub?.plan
    ? sub.plan.charAt(0).toUpperCase() + sub.plan.slice(1)
    : "Free"

  // ── render ────────────────────────────────────────────────────────────────

  return (
    <div className="min-h-screen bg-background">
      <div className="max-w-5xl mx-auto px-6 py-10">

        {/* ── Page header ── */}
        <div className="flex items-center justify-between mb-8">
          <h1 className="text-2xl font-semibold tracking-tight">Billing &amp; Invoices</h1>
          <div className="flex items-center gap-2">
            <Button
              variant="outline"
              onClick={() => setShowAddCredits(true)}
              className="gap-1.5"
            >
              <Zap className="w-3.5 h-3.5" />
              Add Credits
            </Button>
            <Button
              variant="outline"
              onClick={handleManageSubscription}
              disabled={portalLoading}
              className="gap-1.5"
              title="Update payment method, cancel, or change plan"
            >
              {portalLoading ? (
                <Loader2 className="w-3.5 h-3.5 animate-spin" />
              ) : (
                <CreditCard className="w-3.5 h-3.5" />
              )}
              Payment method
            </Button>
            <Button
              variant="outline"
              onClick={handleManageSubscription}
              disabled={portalLoading}
              className="gap-1.5"
            >
              {portalLoading ? (
                <Loader2 className="w-3.5 h-3.5 animate-spin" />
              ) : (
                <ChevronDown className="w-3.5 h-3.5" />
              )}
              Manage plan
            </Button>
          </div>
        </div>

        {/* Add Credits Dialog */}
        <AddCreditsDialog open={showAddCredits} onOpenChange={setShowAddCredits} />

        {/* ── Error / loading ── */}
        {error && (
          <div className="flex items-center gap-2 mb-6 text-sm text-destructive bg-destructive/10 border border-destructive/20 rounded-lg px-4 py-3">
            <AlertCircle className="w-4 h-4 flex-shrink-0" />
            {error}
            <button onClick={refresh} className="ml-auto underline hover:no-underline">
              Retry
            </button>
          </div>
        )}

        {loading && (
          <div className="flex justify-center py-20">
            <Loader2 className="w-6 h-6 animate-spin text-muted-foreground" />
          </div>
        )}

        {/* Quota warning banner — shown outside the loading guard so it appears immediately */}
        {!loading && pct !== null && pct >= 80 && (
          <QuotaWarningBanner
            pct={pct}
            used={total}
            quota={quota}
            onAddCredits={() => setShowAddCredits(true)}
            onUpgrade={handleManageSubscription}
            autoCharge={autoCharge}
            onAutoChargeChange={setAutoCharge}
          />
        )}

        {!loading && (
          <div className="space-y-6">

            {/* ── 1. Included Usage ── */}
            <SectionCard>
              <div className="px-6 pt-5 pb-2">
                <h2 className="text-base font-semibold">Included Usage</h2>
                <p className="text-sm text-muted-foreground mt-0.5">{cycleStr}</p>
              </div>

              <Table>
                <TableHeader>
                  <TableRow className="border-t border-border">
                    <TableHead className="pl-6 text-xs font-medium text-muted-foreground uppercase tracking-wide">Item</TableHead>
                    <TableHead className="text-xs font-medium text-muted-foreground uppercase tracking-wide">Tokens / Usage</TableHead>
                    <TableHead className="text-right pr-6 text-xs font-medium text-muted-foreground uppercase tracking-wide">Usage %</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {/* AI / LLM */}
                  <TableRow className="border-none">
                    <TableCell className="pl-6 font-medium">AI Workflows</TableCell>
                    <TableCell className="text-muted-foreground">
                      {totalTokens > 0 ? fmtTokens(totalTokens) : "0 tokens"}
                    </TableCell>
                    <TableCell className="text-right pr-6 text-muted-foreground">
                      {tokenPct > 0 ? `${tokenPct.toFixed(1)}%` : "0.0%"}
                    </TableCell>
                  </TableRow>

                  {/* Input tokens sub-row */}
                  {llm && llm.tokens_in > 0 && (
                    <TableRow className="border-none bg-transparent">
                      <TableCell className="pl-10 text-sm text-muted-foreground/70">
                        ↳ Input
                      </TableCell>
                      <TableCell className="text-sm text-muted-foreground/70">
                        {fmtTokens(llm.tokens_in)}
                      </TableCell>
                      <TableCell className="pr-6 text-right text-sm text-muted-foreground/70">
                        {includedTokens ? `${((llm.tokens_in / includedTokens) * 100).toFixed(1)}%` : "—"}
                      </TableCell>
                    </TableRow>
                  )}

                  {/* Output tokens sub-row */}
                  {llm && llm.tokens_out > 0 && (
                    <TableRow className="border-none bg-transparent">
                      <TableCell className="pl-10 text-sm text-muted-foreground/70">
                        ↳ Output
                      </TableCell>
                      <TableCell className="text-sm text-muted-foreground/70">
                        {fmtTokens(llm.tokens_out)}
                      </TableCell>
                      <TableCell className="pr-6 text-right text-sm text-muted-foreground/70">
                        {includedTokens ? `${((llm.tokens_out / includedTokens) * 100).toFixed(1)}%` : "—"}
                      </TableCell>
                    </TableRow>
                  )}

                  {/* Compute */}
                  <TableRow className="border-none">
                    <TableCell className="pl-6 font-medium">Compute (Batch)</TableCell>
                    <TableCell className="text-muted-foreground">
                      {compute && compute.jobs > 0
                        ? `${compute.jobs} job${compute.jobs !== 1 ? "s" : ""} · ${compute.total_hours.toFixed(1)} hrs`
                        : "0 jobs"}
                    </TableCell>
                    <TableCell className="text-right pr-6 text-muted-foreground">
                      {pct !== null && compute && compute.total_usd > 0
                        ? `${((compute.total_usd / ((quota ?? total) || 1)) * 100).toFixed(1)}%`
                        : "0.0%"}
                    </TableCell>
                  </TableRow>

                  {/* Storage */}
                  <TableRow className="border-none">
                    <TableCell className="pl-6 font-medium">Storage (S3)</TableCell>
                    <TableCell className="text-muted-foreground">
                      {storage && storage.size_gb > 0
                        ? `${storage.size_gb.toFixed(2)} GB`
                        : "0 GB"}
                    </TableCell>
                    <TableCell className="text-right pr-6 text-muted-foreground">
                      {pct !== null && storage && storage.total_usd > 0
                        ? `${((storage.total_usd / ((quota ?? total) || 1)) * 100).toFixed(1)}%`
                        : "0.0%"}
                    </TableCell>
                  </TableRow>
                </TableBody>
              </Table>

              {/* Quota bar */}
              {pct !== null && (
                <div className="px-6 py-4 border-t border-border">
                  <div className="flex justify-between text-xs text-muted-foreground mb-1.5">
                    <span>
                      {fmt(total)} used
                      {running > 0 && (
                        <span className="ml-1 text-yellow-600 dark:text-yellow-400">
                          + ~{fmt(running)} running
                        </span>
                      )}
                    </span>
                    <span>{quota ? fmt(quota) : "Unlimited"} plan limit · {planName}</span>
                  </div>
                  <div className="h-2 bg-muted rounded-full overflow-hidden">
                    <div
                      className={cn(
                        "h-full rounded-full transition-all duration-500",
                        over ? "bg-destructive" : pct > 80 ? "bg-yellow-500" : "bg-primary"
                      )}
                      style={{ width: `${Math.min(pct, 100)}%` }}
                    />
                  </div>
                  {over && (
                    <p className="flex items-center gap-1 mt-2 text-xs text-destructive">
                      <AlertCircle className="w-3.5 h-3.5" />
                      You've exceeded your plan limit.{" "}
                      <button
                        onClick={handleManageSubscription}
                        className="underline hover:no-underline"
                      >
                        Upgrade now
                      </button>
                    </p>
                  )}
                </div>
              )}
            </SectionCard>

            {/* ── 2. On-Demand Usage ── */}
            <SectionCard>
              <div className="px-6 pt-5 pb-2 flex items-start justify-between">
                <div>
                  <h2 className="text-base font-semibold">On-Demand Usage</h2>
                  <p className="text-sm text-muted-foreground mt-0.5">{cycleStr}</p>
                </div>
                <div className="flex items-center gap-1.5 text-sm text-muted-foreground border border-border rounded-md px-3 py-1.5 cursor-default select-none">
                  Cycle starting {usage?.month ? monthLabel(usage.month).split(" ").slice(0, 2).join(" ") : "—"}
                  <ChevronDown className="w-3.5 h-3.5" />
                </div>
              </div>

              <div className="px-6 pb-2">
                <p className="text-3xl font-semibold tabular-nums">{fmt(total)}</p>
              </div>

              <Table>
                <TableHeader>
                  <TableRow className="border-t border-border">
                    <TableHead className="pl-6 text-xs font-medium text-muted-foreground uppercase tracking-wide">Type</TableHead>
                    <TableHead className="text-xs font-medium text-muted-foreground uppercase tracking-wide">Detail</TableHead>
                    <TableHead className="text-xs font-medium text-muted-foreground uppercase tracking-wide">Rate</TableHead>
                    <TableHead className="text-xs font-medium text-muted-foreground uppercase tracking-wide">Qty</TableHead>
                    <TableHead className="text-right pr-6 text-xs font-medium text-muted-foreground uppercase tracking-wide">Total</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {llm && llm.total_usd > 0 && (
                    <>
                      <TableRow>
                        <TableCell className="pl-6 font-medium">AI / LLM</TableCell>
                        <TableCell className="text-muted-foreground">Input tokens</TableCell>
                        <TableCell className="text-muted-foreground">$0.003 / 1K</TableCell>
                        <TableCell className="text-muted-foreground">{fmtTokens(llm.tokens_in)}</TableCell>
                        <TableCell className="text-right pr-6">{fmt(llm.input_usd)}</TableCell>
                      </TableRow>
                      <TableRow className="border-none bg-transparent">
                        <TableCell className="pl-6 text-muted-foreground/60" />
                        <TableCell className="text-muted-foreground">Output tokens</TableCell>
                        <TableCell className="text-muted-foreground">$0.015 / 1K</TableCell>
                        <TableCell className="text-muted-foreground">{fmtTokens(llm.tokens_out)}</TableCell>
                        <TableCell className="text-right pr-6">{fmt(llm.output_usd)}</TableCell>
                      </TableRow>
                    </>
                  )}

                  {compute && compute.total_usd > 0 && (
                    <>
                      {compute.vcpu_usd > 0 && (
                        <TableRow>
                          <TableCell className="pl-6 font-medium">Compute</TableCell>
                          <TableCell className="text-muted-foreground">vCPU time</TableCell>
                          <TableCell className="text-muted-foreground">$0.10 / hr</TableCell>
                          <TableCell className="text-muted-foreground">{compute.total_hours.toFixed(1)} hrs</TableCell>
                          <TableCell className="text-right pr-6">{fmt(compute.vcpu_usd)}</TableCell>
                        </TableRow>
                      )}
                      {compute.gpu_usd > 0 && (
                        <TableRow className={compute.vcpu_usd > 0 ? "border-none bg-transparent" : ""}>
                          <TableCell className="pl-6 font-medium">{compute.vcpu_usd > 0 ? "" : "Compute"}</TableCell>
                          <TableCell className="text-muted-foreground">GPU time</TableCell>
                          <TableCell className="text-muted-foreground">$1.50 / hr</TableCell>
                          <TableCell className="text-muted-foreground">{compute.total_hours.toFixed(1)} hrs</TableCell>
                          <TableCell className="text-right pr-6">{fmt(compute.gpu_usd)}</TableCell>
                        </TableRow>
                      )}
                    </>
                  )}

                  {storage && storage.total_usd > 0 && (
                    <TableRow>
                      <TableCell className="pl-6 font-medium">Storage</TableCell>
                      <TableCell className="text-muted-foreground">S3 objects</TableCell>
                      <TableCell className="text-muted-foreground">$0.15 / GB</TableCell>
                      <TableCell className="text-muted-foreground">{storage.size_gb.toFixed(2)} GB</TableCell>
                      <TableCell className="text-right pr-6">{fmt(storage.total_usd)}</TableCell>
                    </TableRow>
                  )}

                  {/* Empty state */}
                  {total === 0 && (
                    <TableRow>
                      <TableCell colSpan={5} className="text-center text-muted-foreground py-8">
                        No on-demand usage this cycle
                      </TableCell>
                    </TableRow>
                  )}
                </TableBody>
              </Table>

              {/* Subtotal */}
              <div className="flex justify-end px-6 py-4 border-t border-border">
                <div className="flex items-center gap-6 text-sm">
                  <span className="text-muted-foreground">Subtotal:</span>
                  <span className="font-semibold tabular-nums w-20 text-right">{fmt(total)}</span>
                </div>
              </div>

              {/* Running jobs */}
              {usage?.running_jobs && usage.running_jobs.length > 0 && (
                <div className="px-6 pb-4 border-t border-border pt-3">
                  <p className="text-xs text-muted-foreground flex items-center gap-1.5">
                    <Loader2 className="w-3 h-3 animate-spin text-yellow-500" />
                    {usage.running_jobs.length} job{usage.running_jobs.length !== 1 ? "s" : ""} currently running · estimated additional ~{fmt(running)}
                  </p>
                </div>
              )}
            </SectionCard>

            {/* ── 3. Invoices ── */}
            <SectionCard>
              <div className="px-6 pt-5 pb-2 flex items-start justify-between">
                <h2 className="text-base font-semibold">Invoices</h2>
                <Select value={invoiceMonth} onValueChange={setInvoiceMonth}>
                  <SelectTrigger className="w-44 h-8 text-sm">
                    <SelectValue placeholder="All months" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">All months</SelectItem>
                    {history.map((h) => (
                      <SelectItem key={h.month} value={h.month}>
                        {monthLabel(h.month)}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

              <Table>
                <TableHeader>
                  <TableRow className="border-t border-border">
                    <TableHead className="pl-6 text-xs font-medium text-muted-foreground uppercase tracking-wide">Date</TableHead>
                    <TableHead className="text-xs font-medium text-muted-foreground uppercase tracking-wide">Description</TableHead>
                    <TableHead className="text-xs font-medium text-muted-foreground uppercase tracking-wide">Status</TableHead>
                    <TableHead className="text-xs font-medium text-muted-foreground uppercase tracking-wide">Amount</TableHead>
                    <TableHead className="text-right pr-6 text-xs font-medium text-muted-foreground uppercase tracking-wide">Invoice</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {historyLoading && (
                    <TableRow>
                      <TableCell colSpan={5} className="text-center py-10">
                        <Loader2 className="w-5 h-5 animate-spin text-muted-foreground mx-auto" />
                      </TableCell>
                    </TableRow>
                  )}

                  {!historyLoading && filteredInvoice.length === 0 && (
                    <TableRow>
                      <TableCell colSpan={5} className="text-center text-muted-foreground py-8">
                        No invoices found
                      </TableCell>
                    </TableRow>
                  )}

                  {!historyLoading && filteredInvoice.map((row) => (
                    <TableRow key={row.month}>
                      <TableCell className="pl-6 text-muted-foreground">
                        {monthLabel(row.month)}
                      </TableCell>
                      <TableCell className="text-muted-foreground">
                        BioMate {planName} plan
                      </TableCell>
                      <TableCell>
                        <InvoiceStatusBadge status={row.status} />
                      </TableCell>
                      <TableCell className="font-medium tabular-nums">
                        {fmt(row.total)} USD
                      </TableCell>
                      <TableCell className="text-right pr-6">
                        <Button
                          variant="ghost"
                          size="sm"
                          className="h-7 gap-1.5 text-xs text-primary hover:text-primary"
                          onClick={handleManageSubscription}
                        >
                          <ExternalLink className="w-3 h-3" />
                          View
                        </Button>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>

              {/* Footer note */}
              <div className="px-6 py-4 border-t border-border flex items-center justify-between">
                <p className="text-xs text-muted-foreground">
                  Invoices are generated at the end of each billing cycle. Full invoice PDFs are available via{" "}
                  <button onClick={handleManageSubscription} className="underline hover:no-underline">
                    the billing portal
                  </button>
                  .
                </p>
                <Button
                  variant="ghost"
                  size="sm"
                  className="gap-1.5 text-xs text-muted-foreground"
                  onClick={refresh}
                >
                  <RefreshCw className="w-3 h-3" />
                  Refresh
                </Button>
              </div>
            </SectionCard>

          </div>
        )}
      </div>
    </div>
  )
}
