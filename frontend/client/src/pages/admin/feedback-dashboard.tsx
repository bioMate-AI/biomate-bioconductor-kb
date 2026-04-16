import { useState, useEffect, useCallback } from "react";
import { useLocation } from "wouter";
import { useAuth } from "@/contexts/auth-context";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Progress } from "@/components/ui/progress";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { RefreshCw, ArrowLeft, AlertCircle, CheckCircle2, XCircle, AlertTriangle } from "lucide-react";
import { UX_FEEDBACK_ADMIN_ENABLED } from "@/lib/feature-flags";

interface FeedbackSummary {
  total: number;
  byType: Record<string, number>;
  byRating: Record<string, number>;
  byReason: Record<string, number>;
  byDate: Array<{ date: string; count: number }>;
}

interface FeedbackIssue {
  reason: string;
  count: number;
  sampleIds: string[];
  lastSeen: string;
}

interface TelemetrySummary {
  total?: number;
  byEventName?: Record<string, number>;
  byDay?: Array<{ date: string; count: number }>;
  [key: string]: unknown;
}

interface ConfusionTriageRow {
  rootRunId: string;
  latestSignalAt: string;
  totalSignals: number;
  signalsByType: Record<string, number>;
  runIds: string[];
  sessionIds: string[];
  latestSeverity?: string;
}

interface ConfusionTriageResponse {
  totalGroups: number;
  rows: ConfusionTriageRow[];
}

interface PilotKpiSummary {
  respondents: number;
  sessions_submitted: number;
  sessions_no_correction: number;
  // H1
  avg_workflow_quality_pct: number | null;
  h1_pass_count: number;
  // H2
  avg_time_minutes: number | null;
  h2_pass_count: number;
  avg_prior_time_hours: number | null;
  avg_time_saved_hours: number | null;
  // H3
  avg_qc_rating: number | null;
  qc_pass_count: number;
  // H4
  pricing_yes_count: number;
  pricing_maybe_count: number;
  // H5
  total_hallucinations: number;
  h5_pass: boolean;
  // Overall
  avg_overall_rating: number | null;
  avg_recommend_rating: number | null;
  coauthor_yes_count: number;
}

function formatDateForInput(d: Date): string {
  return d.toISOString().slice(0, 10);
}

export default function AdminFeedbackDashboardPage() {
  if (!UX_FEEDBACK_ADMIN_ENABLED) {
    return (
      <div className="min-h-screen bg-background">
        <div className="max-w-3xl mx-auto px-4 py-12">
          <Alert variant="destructive">
            <AlertCircle className="h-4 w-4" />
            <AlertDescription>
              UX feedback dashboard is currently disabled by feature flag.
            </AlertDescription>
          </Alert>
          <Button variant="outline" className="mt-4" onClick={() => setLocation("/dashboard")}>
            <ArrowLeft className="mr-2 h-4 w-4" />
            Back to Dashboard
          </Button>
        </div>
      </div>
    );
  }

  const [, setLocation] = useLocation();
  const { isAuthenticated } = useAuth();
  const [from, setFrom] = useState(formatDateForInput(new Date(Date.now() - 30 * 24 * 60 * 60 * 1000)));
  const [to, setTo] = useState(formatDateForInput(new Date()));
  const [summary, setSummary] = useState<FeedbackSummary | null>(null);
  const [issues, setIssues] = useState<FeedbackIssue[]>([]);
  const [telemetry, setTelemetry] = useState<TelemetrySummary | null>(null);
  const [confusionTriage, setConfusionTriage] = useState<ConfusionTriageResponse | null>(null);
  const [pilotKpi, setPilotKpi] = useState<PilotKpiSummary | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [authError, setAuthError] = useState<"unauthorized" | "forbidden" | null>(null);

  const fetchData = useCallback(async () => {
    if (!isAuthenticated) {
      setAuthError("unauthorized");
      return;
    }
    setLoading(true);
    setError(null);
    setAuthError(null);
    setSummary(null);
      setIssues([]);
      setTelemetry(null);
      setConfusionTriage(null);
      setPilotKpi(null);

    const params = new URLSearchParams({ from, to });

    try {
      const [summaryRes, issuesRes, telemetryRes, confusionTriageRes, pilotKpiRes] = await Promise.all([
        fetch(`/api/feedback/summary?${params}`, { credentials: "include" }),
        fetch(`/api/feedback/issues?${params}&limit=10`, { credentials: "include" }),
        fetch(`/api/telemetry/summary?${params}`, { credentials: "include" }),
        fetch(`/api/telemetry/confusion-triage?${params}&limit=10`, { credentials: "include" }),
        fetch(`/api/feedback/pilot-kpi?${params}`, { credentials: "include" }),
      ]);

      if (summaryRes.status === 401) {
        setAuthError("unauthorized");
        return;
      }
      if (summaryRes.status === 403) {
        setAuthError("forbidden");
        return;
      }
      if (!summaryRes.ok) {
        setError("Failed to load feedback summary");
        return;
      }
      const summaryData = await summaryRes.json();
      setSummary(summaryData);

      if (issuesRes.status === 401) {
        setAuthError("unauthorized");
        return;
      }
      if (issuesRes.status === 403) {
        setAuthError("forbidden");
        return;
      }
      if (issuesRes.ok) {
        const issuesData = await issuesRes.json();
        setIssues(issuesData.issues ?? []);
      }

      if (telemetryRes.ok) {
        const telemetryData = await telemetryRes.json();
        setTelemetry(telemetryData);
      }
      // 404 or other errors for telemetry are handled gracefully - leave telemetry null

      if (confusionTriageRes.ok) {
        const triageData = (await confusionTriageRes.json()) as ConfusionTriageResponse;
        const sortedRows = [...(triageData.rows ?? [])].sort((a, b) => {
          if (b.totalSignals !== a.totalSignals) return b.totalSignals - a.totalSignals;
          return new Date(b.latestSignalAt).getTime() - new Date(a.latestSignalAt).getTime();
        });
        setConfusionTriage({
          totalGroups: triageData.totalGroups ?? sortedRows.length,
          rows: sortedRows,
        });
      }
      // 404 or other errors for confusion triage are handled gracefully - leave state null

      if (pilotKpiRes.ok) {
        const kpiData = await pilotKpiRes.json();
        setPilotKpi(kpiData);
      }
    } catch (err) {
      setError("Failed to load data. Please try again.");
    } finally {
      setLoading(false);
    }
  }, [from, to, isAuthenticated]);

  useEffect(() => {
    fetchData();
  }, [fetchData]);

  if (!isAuthenticated && !authError) {
    return (
      <div className="min-h-screen bg-background">
        <div className="max-w-3xl mx-auto px-4 py-12">
          <Alert variant="destructive">
            <AlertCircle className="h-4 w-4" />
            <AlertDescription>
              Please log in to access the admin feedback dashboard.
            </AlertDescription>
          </Alert>
          <Button variant="outline" className="mt-4" onClick={() => setLocation("/login")}>
            Go to Login
          </Button>
        </div>
      </div>
    );
  }

  if (authError === "unauthorized") {
    return (
      <div className="min-h-screen bg-background">
        <div className="max-w-3xl mx-auto px-4 py-12">
          <Alert variant="destructive">
            <AlertCircle className="h-4 w-4" />
            <AlertDescription>
              Please log in to access the admin feedback dashboard.
            </AlertDescription>
          </Alert>
          <Button variant="outline" className="mt-4" onClick={() => setLocation("/login")}>
            Go to Login
          </Button>
        </div>
      </div>
    );
  }

  if (authError === "forbidden") {
    return (
      <div className="min-h-screen bg-background">
        <div className="max-w-3xl mx-auto px-4 py-12">
          <Alert variant="destructive">
            <AlertCircle className="h-4 w-4" />
            <AlertDescription>
              Admin access required. You do not have permission to view this page.
            </AlertDescription>
          </Alert>
          <Button variant="outline" className="mt-4" onClick={() => setLocation("/dashboard")}>
            <ArrowLeft className="mr-2 h-4 w-4" />
            Back to Dashboard
          </Button>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-background">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div className="flex items-center justify-between mb-8">
          <div>
            <Button
              variant="ghost"
              size="sm"
              onClick={() => setLocation("/dashboard")}
              className="mb-2"
            >
              <ArrowLeft className="mr-2 h-4 w-4" />
              Back to Dashboard
            </Button>
            <h1 className="text-3xl font-bold">UX Feedback Dashboard</h1>
            <p className="text-muted-foreground mt-1">
              Inspect feedback and telemetry summaries
            </p>
          </div>
        </div>

        {/* Date range & refresh */}
        <Card className="mb-6">
          <CardHeader>
            <CardTitle>Date Range</CardTitle>
            <CardDescription>Filter feedback and issues by date</CardDescription>
          </CardHeader>
          <CardContent className="flex flex-wrap items-end gap-4">
            <div className="space-y-2">
              <Label htmlFor="from">From</Label>
              <Input
                id="from"
                type="date"
                value={from}
                onChange={(e) => setFrom(e.target.value)}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="to">To</Label>
              <Input
                id="to"
                type="date"
                value={to}
                onChange={(e) => setTo(e.target.value)}
              />
            </div>
            <Button onClick={fetchData} disabled={loading}>
              <RefreshCw className={`mr-2 h-4 w-4 ${loading ? "animate-spin" : ""}`} />
              Refresh
            </Button>
          </CardContent>
        </Card>

        {/* ── Pilot Evaluation KPI Panel ─────────────────────────────────────── */}
        {pilotKpi && (
          <Card className="mb-6 border-blue-200 dark:border-blue-800" data-testid="pilot-kpi-panel">
            <CardHeader className="pb-2">
              <CardTitle className="flex items-center gap-2 text-base">
                Pilot Evaluation KPIs
                <span className="text-xs font-normal text-muted-foreground">
                  — {pilotKpi.sessions_submitted} sessions · {pilotKpi.respondents} exit {pilotKpi.respondents === 1 ? "survey" : "surveys"}
                </span>
              </CardTitle>
              <CardDescription>
                Aggregated from post-run surveys and end-of-pilot exit surveys.
                Targets from the pilot evaluation model (April 2026).
              </CardDescription>
            </CardHeader>
            <CardContent>
              <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-5 gap-4">
                {/* Sessions overview */}
                <div className="space-y-1">
                  <div className="text-xs font-medium text-muted-foreground">Sessions Submitted</div>
                  <div className="text-2xl font-bold">{pilotKpi.sessions_submitted}</div>
                  <p className="text-[10px] text-muted-foreground">
                    {pilotKpi.sessions_no_correction} without correction
                    {pilotKpi.sessions_submitted > 0
                      ? ` (${Math.round((pilotKpi.sessions_no_correction / pilotKpi.sessions_submitted) * 100)}%)`
                      : ""}
                  </p>
                </div>
                {/* H1 — Workflow quality */}
                {(() => {
                  const pct = pilotKpi.avg_workflow_quality_pct;
                  const pass = pct !== null && pct >= 80;
                  return (
                    <div className="space-y-1">
                      <div className="flex items-center gap-1 text-xs font-medium text-muted-foreground">
                        {pass ? <CheckCircle2 className="h-3.5 w-3.5 text-green-500" /> : <AlertTriangle className="h-3.5 w-3.5 text-amber-500" />}
                        H1 — Workflow Quality
                      </div>
                      <div className="text-2xl font-bold">
                        {pct !== null ? `${Math.round(pct)}%` : "—"}
                      </div>
                      <Progress value={pct ?? 0} className="h-1.5" />
                      <p className="text-[10px] text-muted-foreground">Target ≥ 80%</p>
                    </div>
                  );
                })()}
                {/* H2 — Time to result */}
                {(() => {
                  const mins = pilotKpi.avg_time_minutes;
                  const pass = mins !== null && mins <= 30;
                  return (
                    <div className="space-y-1">
                      <div className="flex items-center gap-1 text-xs font-medium text-muted-foreground">
                        {pass ? <CheckCircle2 className="h-3.5 w-3.5 text-green-500" /> : <AlertTriangle className="h-3.5 w-3.5 text-amber-500" />}
                        H2 — Time to Result
                      </div>
                      <div className="text-2xl font-bold">
                        {mins !== null ? `${Math.round(mins)} min` : "—"}
                      </div>
                      {pilotKpi.avg_time_saved_hours !== null && (
                        <p className="text-xs text-green-600 dark:text-green-400">
                          saves ~{pilotKpi.avg_time_saved_hours.toFixed(1)} h/run
                        </p>
                      )}
                      <p className="text-[10px] text-muted-foreground">Target ≤ 30 min</p>
                    </div>
                  );
                })()}
                {/* H3 — QC defensibility */}
                {(() => {
                  const rating = pilotKpi.avg_qc_rating;
                  const passPct = pilotKpi.respondents > 0
                    ? Math.round((pilotKpi.qc_pass_count / pilotKpi.respondents) * 100)
                    : null;
                  const pass = passPct !== null && passPct >= 70;
                  return (
                    <div className="space-y-1">
                      <div className="flex items-center gap-1 text-xs font-medium text-muted-foreground">
                        {pass ? <CheckCircle2 className="h-3.5 w-3.5 text-green-500" /> : <AlertTriangle className="h-3.5 w-3.5 text-amber-500" />}
                        H3 — QC Defensibility
                      </div>
                      <div className="text-2xl font-bold">
                        {rating !== null ? `${rating.toFixed(1)}/5` : "—"}
                      </div>
                      {passPct !== null && (
                        <Progress value={passPct} className="h-1.5" />
                      )}
                      <p className="text-[10px] text-muted-foreground">
                        {passPct !== null ? `${passPct}% rated ≥4` : ""} · Target ≥ 70%
                      </p>
                    </div>
                  );
                })()}
                {/* H4 — Pricing */}
                {(() => {
                  const yesPct = pilotKpi.respondents > 0
                    ? Math.round((pilotKpi.pricing_yes_count / pilotKpi.respondents) * 100)
                    : null;
                  const maybePct = pilotKpi.respondents > 0
                    ? Math.round((pilotKpi.pricing_maybe_count / pilotKpi.respondents) * 100)
                    : null;
                  const pass = yesPct !== null && yesPct >= 60;
                  return (
                    <div className="space-y-1">
                      <div className="flex items-center gap-1 text-xs font-medium text-muted-foreground">
                        {pass ? <CheckCircle2 className="h-3.5 w-3.5 text-green-500" /> : <AlertTriangle className="h-3.5 w-3.5 text-amber-500" />}
                        H4 — Pricing ($29/mo)
                      </div>
                      <div className="text-2xl font-bold">
                        {yesPct !== null ? `${yesPct}%` : "—"}
                      </div>
                      {maybePct !== null && (
                        <p className="text-xs text-muted-foreground">+{maybePct}% maybe</p>
                      )}
                      <p className="text-[10px] text-muted-foreground">Target ≥ 60% Yes</p>
                    </div>
                  );
                })()}
                {/* H5 — Hallucinations */}
                {(() => {
                  const total = pilotKpi.total_hallucinations;
                  const pass = total === 0;
                  return (
                    <div className="space-y-1">
                      <div className="flex items-center gap-1 text-xs font-medium text-muted-foreground">
                        {pass ? <CheckCircle2 className="h-3.5 w-3.5 text-green-500" /> : <XCircle className="h-3.5 w-3.5 text-red-500" />}
                        H5 — Hallucinations
                      </div>
                      <div className={`text-2xl font-bold ${pass ? "text-green-600" : "text-red-600"}`}>
                        {total}
                      </div>
                      <p className="text-xs text-muted-foreground">reported incidents</p>
                      <p className="text-[10px] text-muted-foreground">Target = 0</p>
                    </div>
                  );
                })()}
              </div>

              {/* Overall scores */}
              {(pilotKpi.avg_overall_rating !== null || pilotKpi.avg_recommend_rating !== null) && (
                <div className="mt-4 pt-4 border-t flex flex-wrap gap-6 text-sm">
                  {pilotKpi.avg_overall_rating !== null && (
                    <div>
                      <span className="text-muted-foreground">Overall satisfaction:</span>{" "}
                      <span className="font-semibold">{pilotKpi.avg_overall_rating.toFixed(1)}/5</span>
                    </div>
                  )}
                  {pilotKpi.avg_recommend_rating !== null && (
                    <div>
                      <span className="text-muted-foreground">Would recommend:</span>{" "}
                      <span className="font-semibold">{pilotKpi.avg_recommend_rating.toFixed(1)}/5</span>
                    </div>
                  )}
                  {pilotKpi.coauthor_yes_count > 0 && (
                    <div>
                      <span className="text-muted-foreground">Open to co-authoring:</span>{" "}
                      <span className="font-semibold">{pilotKpi.coauthor_yes_count} participant{pilotKpi.coauthor_yes_count > 1 ? "s" : ""}</span>
                    </div>
                  )}
                </div>
              )}
            </CardContent>
          </Card>
        )}

        {error && (
          <Alert variant="destructive" className="mb-6">
            <AlertCircle className="h-4 w-4" />
            <AlertDescription>{error}</AlertDescription>
          </Alert>
        )}

        <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
          {/* Feedback Summary */}
          <Card className="lg:col-span-2">
            <CardHeader>
              <CardTitle>Feedback Summary</CardTitle>
              <CardDescription>Aggregated counts by type, rating, and reason</CardDescription>
            </CardHeader>
            <CardContent>
              {loading && !summary ? (
                <p className="text-muted-foreground">Loading...</p>
              ) : summary ? (
                <div className="space-y-4">
                  <div className="text-2xl font-bold">{summary.total} total feedback</div>
                  <div className="grid gap-4 sm:grid-cols-2">
                    <div>
                      <div className="text-sm font-medium text-muted-foreground mb-2">
                        By Type
                      </div>
                      <ul className="space-y-1 text-sm">
                        {Object.entries(summary.byType).map(([k, v]) => (
                          <li key={k}>
                            {k}: <strong>{v}</strong>
                          </li>
                        ))}
                        {Object.keys(summary.byType).length === 0 && (
                          <li className="text-muted-foreground">No data</li>
                        )}
                      </ul>
                    </div>
                    <div>
                      <div className="text-sm font-medium text-muted-foreground mb-2">
                        By Rating
                      </div>
                      <ul className="space-y-1 text-sm">
                        {Object.entries(summary.byRating).map(([k, v]) => (
                          <li key={k}>
                            {k}: <strong>{v}</strong>
                          </li>
                        ))}
                        {Object.keys(summary.byRating).length === 0 && (
                          <li className="text-muted-foreground">No data</li>
                        )}
                      </ul>
                    </div>
                  </div>
                  {Object.keys(summary.byReason).length > 0 && (
                    <div>
                      <div className="text-sm font-medium text-muted-foreground mb-2">
                        By Reason
                      </div>
                      <ul className="space-y-1 text-sm">
                        {Object.entries(summary.byReason).map(([k, v]) => (
                          <li key={k}>
                            {k}: <strong>{v}</strong>
                          </li>
                        ))}
                      </ul>
                    </div>
                  )}
                </div>
              ) : (
                <p className="text-muted-foreground">No summary data</p>
              )}
            </CardContent>
          </Card>

          {/* Telemetry Summary */}
          <Card>
            <CardHeader>
              <CardTitle>Telemetry Summary</CardTitle>
              <CardDescription>Event counts (if available)</CardDescription>
            </CardHeader>
            <CardContent>
              {loading && !telemetry ? (
                <p className="text-muted-foreground">Loading...</p>
              ) : telemetry ? (
                <div className="space-y-2 text-sm">
                  {typeof telemetry.total === "number" && (
                    <div className="font-medium">{telemetry.total} total events</div>
                  )}
                  {telemetry.byEventName && Object.keys(telemetry.byEventName).length > 0 ? (
                    <ul className="space-y-1">
                      {Object.entries(telemetry.byEventName).map(([k, v]) => (
                        <li key={k}>
                          {k}: <strong>{v}</strong>
                        </li>
                      ))}
                    </ul>
                  ) : (
                    !telemetry.total && (
                      <p className="text-muted-foreground">
                        Telemetry summary not available
                      </p>
                    )
                  )}
                </div>
              ) : (
                <p className="text-muted-foreground">
                  Telemetry summary endpoint not available
                </p>
              )}
            </CardContent>
          </Card>
        </div>

        {/* Top Issues */}
        <Card className="mt-6">
          <CardHeader>
            <CardTitle>Top Issues</CardTitle>
            <CardDescription>Negative feedback reasons (highest count first)</CardDescription>
          </CardHeader>
          <CardContent>
            {loading && issues.length === 0 ? (
              <p className="text-muted-foreground">Loading...</p>
            ) : issues.length > 0 ? (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Reason</TableHead>
                    <TableHead>Count</TableHead>
                    <TableHead>Last Seen</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {issues.map((issue, i) => (
                    <TableRow key={i}>
                      <TableCell>{issue.reason}</TableCell>
                      <TableCell>{issue.count}</TableCell>
                      <TableCell className="text-muted-foreground text-xs">
                        {issue.lastSeen
                          ? new Date(issue.lastSeen).toLocaleString()
                          : "—"}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            ) : (
              <p className="text-muted-foreground">No issues in this date range</p>
            )}
          </CardContent>
        </Card>

        {/* Confusion Triage */}
        <Card className="mt-6" data-testid="confusion-triage-card">
          <CardHeader>
            <CardTitle>Confusion Triage</CardTitle>
            <CardDescription>
              Grouped confusion signals by run lineage for PM/ops prioritization
            </CardDescription>
          </CardHeader>
          <CardContent>
            {loading && !confusionTriage ? (
              <p className="text-muted-foreground">Loading...</p>
            ) : confusionTriage?.rows?.length ? (
              <div className="space-y-3">
                <p className="text-sm text-muted-foreground">
                  {confusionTriage.totalGroups} grouped run clusters
                </p>
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Root Run</TableHead>
                      <TableHead>Signals</TableHead>
                      <TableHead>Signal Types</TableHead>
                      <TableHead>Latest Severity</TableHead>
                      <TableHead>Latest Signal</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {confusionTriage.rows.map((row, idx) => (
                      <TableRow key={row.rootRunId} data-testid={`confusion-triage-row-${idx}`}>
                        <TableCell className="font-mono text-xs">{row.rootRunId}</TableCell>
                        <TableCell data-testid={`confusion-triage-total-${idx}`}>{row.totalSignals}</TableCell>
                        <TableCell className="text-xs">
                          {Object.entries(row.signalsByType)
                            .sort((a, b) => b[1] - a[1])
                            .map(([signal, count]) => `${signal} (${count})`)
                            .join(", ")}
                        </TableCell>
                        <TableCell>{row.latestSeverity || "—"}</TableCell>
                        <TableCell className="text-muted-foreground text-xs">
                          {row.latestSignalAt ? new Date(row.latestSignalAt).toLocaleString() : "—"}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>
            ) : (
              <p className="text-muted-foreground">No confusion clusters in this date range</p>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
