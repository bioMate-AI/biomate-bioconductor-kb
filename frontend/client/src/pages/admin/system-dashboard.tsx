import { useState, useEffect, useCallback, useRef } from "react";
import { useLocation } from "wouter";
import { useAuth } from "@/contexts/auth-context";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Separator } from "@/components/ui/separator";
import {
  CheckCircle2, XCircle, AlertCircle, Loader2, RefreshCw, ArrowLeft,
  Copy, Check, Server, Database, Cpu, Bot, Users, Activity, Wifi,
  MemoryStick, Layers, Clock, ChevronDown, ChevronRight, Terminal,
  List, AlertTriangle, Square, FileText, X, DollarSign,
} from "lucide-react";

// ── Types ─────────────────────────────────────────────────────────────────────

interface ServiceStatus {
  label: string;
  status: "ok" | "degraded" | "down";
  code?: number;
  error?: string;
  data?: any;
}

interface HealthSummary {
  overall: "ok" | "degraded" | "down";
  services: ServiceStatus[];
  checkedAt: string;
}

interface RunStats {
  active: number;
  completed_24h: number;
  failed_24h: number;
  completed_7d: number;
  failed_7d: number;
  total: number;
}

interface UserStats {
  total: number;
  new_24h: number;
  new_7d: number;
  admins: number;
}

interface LLMProbe {
  status: "ok" | "error" | "no_key" | "unknown_provider";
  provider: string;
  latency_ms: number | null;
  http?: number;
  error?: string;
}

interface SystemConfig {
  effective: { provider: string; model: string };
  env: {
    hasAnthropicKey: boolean; hasOpenaiKey: boolean;
    hasZhipuKey: boolean; hasDeepseekKey: boolean;
    hasGeminiKey: boolean; ollamaUrl: string;
  };
  saved: { provider: string; model: string; ollamaUrl: string; updatedAt: string; updatedBy: string } | null;
}

interface LogLine {
  ts: string;
  level: string;
  logger: string;
  msg: string;
}

interface RunRow {
  id: string;
  workflow_name: string | null;
  status: string;
  started_at: string | null;
  completed_at: string | null;
  duration_s: number | null;
  error_message: string | null;
}

// ── Constants ─────────────────────────────────────────────────────────────────

const PROVIDERS = [
  { value: "anthropic",  label: "Anthropic Claude",       defaultModel: "claude-sonnet-4-5",             needsKey: "ANTHROPIC_API_KEY" },
  { value: "deepseek",   label: "DeepSeek (国内)",          defaultModel: "deepseek-chat",                 needsKey: "DEEPSEEK_API_KEY" },
  { value: "zhipu",      label: "智谱 GLM (国内)",            defaultModel: "glm-4.7",                       needsKey: "ZHIPU_API_KEY" },
  { value: "openrouter", label: "OpenRouter (多模型)",       defaultModel: "deepseek/deepseek-chat-v3-5",   needsKey: "OPENROUTER_API_KEY" },
  { value: "ollama",     label: "Ollama (本地离线)",          defaultModel: "qwen3:32b",                     needsKey: null },
  { value: "openai",     label: "OpenAI GPT",              defaultModel: "gpt-4o",                        needsKey: "OPENAI_API_KEY" },
  { value: "gemini",     label: "Google Gemini",           defaultModel: "gemini-2.0-flash",              needsKey: "GOOGLE_API_KEY" },
];

// ── Helpers ───────────────────────────────────────────────────────────────────

function StatusBadge({ status }: { status: "ok" | "degraded" | "down" }) {
  if (status === "ok")
    return <Badge className="bg-green-500/10 text-green-700 border-green-500/20 gap-1"><CheckCircle2 className="h-3 w-3" /> 正常</Badge>;
  if (status === "degraded")
    return <Badge className="bg-yellow-500/10 text-yellow-700 border-yellow-500/20 gap-1"><AlertCircle className="h-3 w-3" /> 降级</Badge>;
  return <Badge className="bg-red-500/10 text-red-700 border-red-500/20 gap-1"><XCircle className="h-3 w-3" /> 离线</Badge>;
}

function RunStatusBadge({ status }: { status: string }) {
  const s = status?.toLowerCase() ?? "";
  if (s === "completed") return <span className="text-green-600 font-medium text-xs">完成</span>;
  if (s === "failed") return <span className="text-red-600 font-medium text-xs">失败</span>;
  if (s === "running") return <span className="text-blue-600 font-medium text-xs">运行中</span>;
  if (s === "cancelled") return <span className="text-muted-foreground text-xs">已取消</span>;
  return <span className="text-muted-foreground text-xs">{status}</span>;
}

function CopyBlock({ text, label }: { text: string; label: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <div className="space-y-1">
      <p className="text-xs text-muted-foreground">{label}</p>
      <div className="relative">
        <pre className="rounded bg-muted px-3 py-2 text-xs font-mono overflow-x-auto pr-10">{text}</pre>
        <button
          onClick={() => { navigator.clipboard.writeText(text).then(() => { setCopied(true); setTimeout(() => setCopied(false), 2000); }); }}
          className="absolute right-2 top-2 text-muted-foreground hover:text-foreground"
        >
          {copied ? <Check className="h-3.5 w-3.5 text-green-600" /> : <Copy className="h-3.5 w-3.5" />}
        </button>
      </div>
    </div>
  );
}

function fmtDuration(s: number | null): string {
  if (s == null || s < 0) return "—";
  if (s < 60) return `${s}s`;
  if (s < 3600) return `${Math.floor(s / 60)}m ${s % 60}s`;
  return `${Math.floor(s / 3600)}h ${Math.floor((s % 3600) / 60)}m`;
}

function fmtTime(iso: string | null): string {
  if (!iso) return "—";
  const d = new Date(iso);
  return d.toLocaleString("zh-CN", { month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" });
}

// ── Log Viewer ────────────────────────────────────────────────────────────────

function levelColor(level: string): string {
  const l = level?.toUpperCase() ?? "";
  if (l === "ERROR" || l === "CRITICAL") return "text-red-400";
  if (l === "WARNING" || l === "WARN") return "text-yellow-400";
  if (l === "INFO") return "text-slate-300";
  return "text-slate-500";
}

function LogViewer({ lines, buffered, loading, error }: {
  lines: LogLine[];
  buffered: number;
  loading: boolean;
  error: string;
}) {
  const bottomRef = useRef<HTMLDivElement>(null);
  useEffect(() => { bottomRef.current?.scrollIntoView(); }, [lines]);

  return (
    <div className="mt-2 rounded-md border border-slate-700 bg-slate-900 overflow-hidden">
      <div className="flex items-center justify-between px-3 py-1.5 bg-slate-800 border-b border-slate-700">
        <div className="flex items-center gap-1.5 text-xs text-slate-400">
          <Terminal className="h-3 w-3" />
          <span>Galaxy 后端日志</span>
          {buffered > 0 && <span className="text-slate-500">（缓冲 {buffered} 条）</span>}
        </div>
        {loading && <Loader2 className="h-3 w-3 animate-spin text-slate-400" />}
      </div>
      <div className="h-64 overflow-y-auto p-2 font-mono text-fs-xs leading-5 space-y-0.5">
        {error && <div className="text-red-400 p-2">{error}</div>}
        {!loading && lines.length === 0 && !error && (
          <div className="text-slate-500 p-2 text-center">暂无日志记录（worker 刚启动或无新日志）</div>
        )}
        {lines.map((ln, i) => (
          <div key={i} className="flex gap-2 hover:bg-slate-800/50 px-1 rounded">
            <span className="text-slate-600 shrink-0 w-16 truncate">{ln.ts?.slice(11)}</span>
            <span className={`shrink-0 w-12 ${levelColor(ln.level)}`}>{ln.level?.slice(0, 4)}</span>
            <span className="text-slate-500 shrink-0 w-20 truncate">{ln.logger}</span>
            <span className="text-slate-300 break-all">{ln.msg}</span>
          </div>
        ))}
        <div ref={bottomRef} />
      </div>
    </div>
  );
}

// ── Run Log Drawer ────────────────────────────────────────────────────────────

interface RunLogsData {
  run_id: string;
  status: string;
  is_batch: boolean;
  nf_log: string[];
  nf_log_path?: string;
  nf_log_total_lines?: number;
  nf_log_error?: string;
  batch_jobs: string[];
  cloudwatch_logs: Array<{ job_id: string; status?: string; ts?: number; msg: string }>;
  cloudwatch_error?: string;
}

function RunLogDrawer({ runId, runName, onClose }: {
  runId: string;
  runName: string;
  onClose: () => void;
}) {
  const [data, setData] = useState<RunLogsData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [tab, setTab] = useState<"nf"|"cw">("nf");
  const bottomRef = useRef<HTMLDivElement>(null);

  const load = useCallback(async () => {
    setLoading(true); setError("");
    try {
      const r = await fetch(`/api/admin/run-logs?run_id=${encodeURIComponent(runId)}&lines=200`, { credentials: "include" });
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      setData(await r.json());
    } catch (e: any) { setError(e.message); }
    finally { setLoading(false); }
  }, [runId]);

  useEffect(() => { load(); }, [load]);
  useEffect(() => { bottomRef.current?.scrollIntoView(); }, [data, tab]);

  const cwFmtTime = (ts?: number) => ts ? new Date(ts).toLocaleTimeString("zh-CN") : "";

  return (
    <div className="fixed inset-0 z-50 bg-black/50 flex items-end justify-center sm:items-center" onClick={onClose}>
      <div className="w-full max-w-3xl bg-background rounded-t-xl sm:rounded-xl shadow-2xl flex flex-col max-h-[85vh]"
           onClick={(e) => e.stopPropagation()}>
        {/* Header */}
        <div className="flex items-center justify-between px-4 py-3 border-b">
          <div>
            <h3 className="text-sm font-semibold flex items-center gap-1.5">
              <FileText className="h-4 w-4 text-muted-foreground" /> 执行日志
            </h3>
            <p className="text-xs text-muted-foreground mt-0.5 font-mono truncate max-w-[450px]">
              {runName} · {runId}
            </p>
          </div>
          <div className="flex items-center gap-2">
            <Button variant="ghost" size="sm" className="h-7 text-xs gap-1 px-2" onClick={load} disabled={loading}>
              {loading ? <Loader2 className="h-3 w-3 animate-spin" /> : <RefreshCw className="h-3 w-3" />} 刷新
            </Button>
            <button onClick={onClose} className="text-muted-foreground hover:text-foreground p-1">
              <X className="h-4 w-4" />
            </button>
          </div>
        </div>

        {/* Tab bar */}
        {data && (
          <div className="flex border-b px-4 gap-4">
            <button
              className={`text-xs py-2 border-b-2 transition-colors ${tab === "nf" ? "border-primary text-primary font-medium" : "border-transparent text-muted-foreground hover:text-foreground"}`}
              onClick={() => setTab("nf")}
            >
              流水线日志
              {data.nf_log_total_lines ? ` (共 ${data.nf_log_total_lines} 行)` : ""}
            </button>
            <button
              className={`text-xs py-2 border-b-2 transition-colors ${tab === "cw" ? "border-primary text-primary font-medium" : "border-transparent text-muted-foreground hover:text-foreground"}`}
              onClick={() => setTab("cw")}
            >
              CloudWatch
              {data.batch_jobs.length > 0 ? ` (${data.batch_jobs.length} 个 Job)` : ""}
            </button>
          </div>
        )}

        {/* Content */}
        <div className="flex-1 overflow-hidden bg-slate-900 rounded-b-xl">
          {loading && (
            <div className="flex items-center justify-center h-40 text-slate-400 text-sm gap-2">
              <Loader2 className="h-4 w-4 animate-spin" /> 加载日志中…
            </div>
          )}
          {error && (
            <div className="p-4 text-red-400 text-xs">{error}</div>
          )}
          {data && tab === "nf" && (
            <div className="h-full overflow-y-auto p-3 font-mono text-fs-xs leading-5">
              {data.nf_log_error && (
                <div className="text-yellow-400 mb-2">[本地日志读取失败: {data.nf_log_error}]</div>
              )}
              {data.nf_log.length === 0 && !data.nf_log_error && (
                <div className="text-slate-500 text-center py-8">
                  暂无本地流水线日志<br/>
                  <span className="text-xs">（Batch 任务日志请查看 CloudWatch 标签）</span>
                </div>
              )}
              {data.nf_log.map((line, i) => {
                const isErr = /ERROR|Exception|FAILED/.test(line);
                const isWarn = /WARN/.test(line);
                return (
                  <div key={i} className={`hover:bg-slate-800/50 px-1 rounded ${isErr ? "text-red-400" : isWarn ? "text-yellow-400" : "text-slate-300"}`}>
                    {line || " "}
                  </div>
                );
              })}
              <div ref={tab === "nf" ? bottomRef : undefined} />
            </div>
          )}
          {data && tab === "cw" && (
            <div className="h-full overflow-y-auto p-3 font-mono text-fs-xs leading-5">
              {data.cloudwatch_error && (
                <div className="text-yellow-400 mb-2">[CloudWatch 错误: {data.cloudwatch_error}]</div>
              )}
              {data.batch_jobs.length === 0 && (
                <div className="text-slate-500 text-center py-8">
                  未找到 Batch Job ID<br/>
                  <span className="text-xs">（该任务可能使用本地执行器）</span>
                </div>
              )}
              {data.cloudwatch_logs.length === 0 && data.batch_jobs.length > 0 && !data.cloudwatch_error && (
                <div className="text-slate-500 text-center py-8">
                  CloudWatch 暂无日志<br/>
                  <span className="text-xs">Job IDs: {data.batch_jobs.slice(0, 3).map(j => j.slice(0, 8)).join(", ")}</span>
                </div>
              )}
              {data.cloudwatch_logs.map((ev, i) => (
                <div key={i} className="flex gap-2 hover:bg-slate-800/50 px-1 rounded">
                  <span className="text-slate-600 shrink-0 w-14">{cwFmtTime(ev.ts)}</span>
                  <span className="text-slate-500 shrink-0 w-16 truncate">{ev.job_id}</span>
                  <span className={`shrink-0 w-10 text-fs-xs ${ev.status === "FAILED" ? "text-red-400" : ev.status === "SUCCEEDED" ? "text-green-400" : "text-slate-500"}`}>
                    {ev.status?.slice(0, 7)}
                  </span>
                  <span className={`break-all ${/error|Error|ERROR|exception|Exception/.test(ev.msg) ? "text-red-400" : "text-slate-300"}`}>
                    {ev.msg}
                  </span>
                </div>
              ))}
              <div ref={tab === "cw" ? bottomRef : undefined} />
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

// ── Run List Drill-down ───────────────────────────────────────────────────────

function RunListDrilldown({ statusFilter, days, label }: {
  statusFilter: string;
  days?: number;
  label: string;
}) {
  const [runs, setRuns] = useState<RunRow[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [killing, setKilling] = useState<string | null>(null);
  const [killResult, setKillResult] = useState<{ id: string; msg: string } | null>(null);
  const [logTarget, setLogTarget] = useState<{ id: string; name: string } | null>(null);

  const load = useCallback(async () => {
    setLoading(true); setError("");
    try {
      const p = new URLSearchParams({ status: statusFilter, limit: "30" });
      if (days) p.set("days", String(days));
      const r = await fetch(`/api/admin/run-list?${p}`, { credentials: "include" });
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      const d = await r.json();
      setRuns(d.runs || []);
    } catch (e: any) { setError(e.message); }
    finally { setLoading(false); }
  }, [statusFilter, days]);

  useEffect(() => { load(); }, [load]);

  const handleKill = async (run: RunRow) => {
    if (!confirm(`确认强制终止「${run.workflow_name || run.id}」？\n\n此操作将取消 AWS Batch 任务并标记为失败，不可撤销。`)) return;
    setKilling(run.id); setKillResult(null);
    try {
      const r = await fetch("/api/admin/kill-run", {
        method: "POST", credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ run_id: run.id }),
      });
      const d = await r.json();
      if (!r.ok) throw new Error(d.error || `HTTP ${r.status}`);
      setKillResult({ id: run.id, msg: `已终止 · 取消了 ${d.batch_cancelled} 个 Batch job` });
      setTimeout(load, 1500);
    } catch (e: any) {
      setKillResult({ id: run.id, msg: `终止失败: ${e.message}` });
    } finally {
      setKilling(null);
    }
  };

  const isActive = (status: string) => {
    const s = status?.toLowerCase() ?? "";
    return s === "running" || s === "active" || s === "queued" || s === "submitted";
  };

  return (
    <>
      {logTarget && (
        <RunLogDrawer
          runId={logTarget.id}
          runName={logTarget.name}
          onClose={() => setLogTarget(null)}
        />
      )}
      <div className="mt-3 rounded-md border bg-muted/30 overflow-hidden">
        <div className="flex items-center justify-between px-3 py-2 bg-muted/50 border-b">
          <div className="flex items-center gap-1.5 text-xs font-medium">
            <List className="h-3 w-3" /> {label}
          </div>
          <Button variant="ghost" size="sm" className="h-6 text-xs gap-1 px-2" onClick={load} disabled={loading}>
            {loading ? <Loader2 className="h-3 w-3 animate-spin" /> : <RefreshCw className="h-3 w-3" />}
          </Button>
        </div>

        {killResult && (
          <div className={`text-xs px-3 py-1.5 border-b flex items-center gap-1.5 ${killResult.msg.startsWith("终止失败") ? "bg-destructive/10 text-destructive" : "bg-green-500/10 text-green-700"}`}>
            {killResult.msg.startsWith("终止失败") ? <XCircle className="h-3 w-3" /> : <CheckCircle2 className="h-3 w-3" />}
            {killResult.msg}
          </div>
        )}

        <div className="max-h-80 overflow-y-auto">
          {error && <div className="text-xs text-destructive p-3">{error}</div>}
          {loading && runs.length === 0 && (
            <div className="flex items-center gap-2 text-xs text-muted-foreground p-3">
              <Loader2 className="h-3 w-3 animate-spin" /> 加载中…
            </div>
          )}
          {!loading && runs.length === 0 && !error && (
            <div className="text-xs text-muted-foreground p-3 text-center">暂无记录</div>
          )}
          {runs.length > 0 && (
            <table className="w-full text-xs">
              <thead className="sticky top-0 bg-muted/80">
                <tr className="border-b">
                  <th className="text-left px-3 py-1.5 font-medium text-muted-foreground">状态</th>
                  <th className="text-left px-3 py-1.5 font-medium text-muted-foreground">工作流</th>
                  <th className="text-left px-3 py-1.5 font-medium text-muted-foreground">开始</th>
                  <th className="text-left px-3 py-1.5 font-medium text-muted-foreground">时长</th>
                  <th className="text-left px-3 py-1.5 font-medium text-muted-foreground">错误</th>
                  <th className="text-left px-3 py-1.5 font-medium text-muted-foreground">操作</th>
                </tr>
              </thead>
              <tbody>
                {runs.map((run) => (
                  <tr key={run.id} className="border-b last:border-0 hover:bg-muted/40">
                    <td className="px-3 py-2"><RunStatusBadge status={run.status} /></td>
                    <td className="px-3 py-2 max-w-[140px] truncate font-medium" title={run.workflow_name ?? undefined}>
                      {run.workflow_name || <span className="text-muted-foreground italic">未知</span>}
                    </td>
                    <td className="px-3 py-2 text-muted-foreground whitespace-nowrap">{fmtTime(run.started_at)}</td>
                    <td className="px-3 py-2 text-muted-foreground whitespace-nowrap">{fmtDuration(run.duration_s)}</td>
                    <td className="px-3 py-2 max-w-[140px] truncate text-red-600/80" title={run.error_message ?? undefined}>
                      {run.error_message || "—"}
                    </td>
                    <td className="px-3 py-2">
                      <div className="flex items-center gap-1">
                        <button
                          onClick={() => setLogTarget({ id: run.id, name: run.workflow_name || run.id })}
                          className="text-muted-foreground hover:text-foreground p-0.5 rounded"
                          title="查看日志"
                        >
                          <FileText className="h-3.5 w-3.5" />
                        </button>
                        {isActive(run.status) && (
                          <button
                            onClick={() => handleKill(run)}
                            disabled={killing === run.id}
                            className="text-red-500/70 hover:text-red-600 p-0.5 rounded disabled:opacity-40"
                            title="强制终止"
                          >
                            {killing === run.id
                              ? <Loader2 className="h-3.5 w-3.5 animate-spin" />
                              : <Square className="h-3.5 w-3.5" />}
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>
    </>
  );
}

// ── Health Panel ──────────────────────────────────────────────────────────────

const SERVICE_ICONS: Record<string, any> = {
  galaxy_version: Server, index_health: Database, process_health: Cpu, postgres: Database,
};

const SERVICE_LABELS: Record<string, string> = {
  galaxy_version: "Galaxy 后端", index_health: "工作流索引", process_health: "进程监控", postgres: "PostgreSQL",
};

function ProcessDetail({ data }: { data: any }) {
  if (!data?.checks) return null;
  const { active_runs, redis, workers, memory } = data.checks;
  return (
    <div className="mt-2 ml-9 space-y-1 text-xs text-muted-foreground">
      {active_runs != null && (
        <div className="flex gap-4">
          <span>运行中: <span className="font-medium text-foreground">{active_runs.count}</span></span>
          {workers?.count != null && workers.count >= 0 && (
            <span>Worker: <span className="font-medium text-foreground">{workers.count}</span></span>
          )}
        </div>
      )}
      {redis && (
        <div className="flex gap-2">
          <span>Redis:</span>
          {redis.status === "ok"
            ? <span className="text-green-600">正常 {redis.latency_ms}ms</span>
            : redis.status === "not_configured"
            ? <span className="text-muted-foreground/70">未配置（使用内存存储）</span>
            : <span className="text-red-600">{redis.error}</span>}
        </div>
      )}
      {memory && (
        <div>
          内存: <span className="font-medium text-foreground">{memory.used_mb}MB / {memory.total_mb}MB</span>
          <span className={memory.percent > 80 ? " text-yellow-600" : ""}> ({memory.percent}%)</span>
        </div>
      )}
    </div>
  );
}

function ServiceCard({ svc }: { svc: ServiceStatus }) {
  const [expanded, setExpanded] = useState(false);
  const [logLines, setLogLines] = useState<LogLine[]>([]);
  const [logBuffered, setLogBuffered] = useState(0);
  const [logLoading, setLogLoading] = useState(false);
  const [logError, setLogError] = useState("");
  const canExpand = svc.label === "process_health" || svc.label === "galaxy_version";
  const Icon = SERVICE_ICONS[svc.label] || Server;

  const loadLogs = useCallback(async () => {
    setLogLoading(true); setLogError("");
    try {
      const r = await fetch("/api/admin/galaxy-logs?lines=100", { credentials: "include" });
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      const d = await r.json();
      if (d.error) throw new Error(d.error);
      setLogLines(d.lines || []);
      setLogBuffered(d.buffered || 0);
    } catch (e: any) { setLogError(e.message); }
    finally { setLogLoading(false); }
  }, []);

  const toggle = () => {
    if (!canExpand) return;
    const next = !expanded;
    setExpanded(next);
    if (next && logLines.length === 0) loadLogs();
  };

  return (
    <div className={`rounded-lg border p-3 ${canExpand ? "cursor-pointer hover:bg-muted/30 transition-colors" : ""}`}
         onClick={toggle}>
      <div className="flex items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <div className="rounded-md bg-muted p-2">
            <Icon className="h-4 w-4 text-muted-foreground" />
          </div>
          <div>
            <p className="text-sm font-medium">{SERVICE_LABELS[svc.label] || svc.label}</p>
            {svc.error && <p className="text-xs text-muted-foreground truncate max-w-[200px]">{svc.error}</p>}
            {svc.data?.version && <p className="text-xs text-muted-foreground">v{svc.data.version}</p>}
            {svc.label === "index_health" && svc.data?.total != null && (
              <p className="text-xs text-muted-foreground">{svc.data.total.toLocaleString()} 工作流</p>
            )}
          </div>
        </div>
        <div className="flex items-center gap-2" onClick={(e) => e.stopPropagation()}>
          <StatusBadge status={svc.status} />
          {canExpand && (
            <button
              onClick={(e) => { e.stopPropagation(); toggle(); }}
              className="text-muted-foreground hover:text-foreground transition-colors"
              title={expanded ? "收起日志" : "查看日志"}
            >
              {expanded
                ? <ChevronDown className="h-4 w-4" />
                : <ChevronRight className="h-4 w-4" />}
            </button>
          )}
        </div>
      </div>

      {/* Process detail (always visible) */}
      {svc.label === "process_health" && <ProcessDetail data={svc.data} />}

      {/* Expandable log viewer */}
      {canExpand && expanded && (
        <div onClick={(e) => e.stopPropagation()}>
          <div className="flex items-center justify-between mt-3 mb-1">
            <span className="text-xs text-muted-foreground font-medium flex items-center gap-1">
              <Terminal className="h-3 w-3" /> 最近 100 条日志
            </span>
            <Button variant="ghost" size="sm" className="h-6 text-xs gap-1 px-2" onClick={loadLogs} disabled={logLoading}>
              {logLoading ? <Loader2 className="h-3 w-3 animate-spin" /> : <RefreshCw className="h-3 w-3" />} 刷新
            </Button>
          </div>
          <LogViewer lines={logLines} buffered={logBuffered} loading={logLoading} error={logError} />
        </div>
      )}
    </div>
  );
}

function HealthPanel() {
  const [health, setHealth] = useState<HealthSummary | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const fetch_ = useCallback(async () => {
    setLoading(true); setError("");
    try {
      const r = await fetch("/api/admin/health-summary", { credentials: "include" });
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      setHealth(await r.json());
    } catch (e: any) { setError(e.message); }
    finally { setLoading(false); }
  }, []);
  useEffect(() => { fetch_(); }, [fetch_]);
  return (
    <Card>
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between">
          <div>
            <CardTitle className="text-base flex items-center gap-2">
              服务健康状态 {health && <StatusBadge status={health.overall} />}
            </CardTitle>
            {health && <CardDescription className="text-xs mt-1">最后检查：{new Date(health.checkedAt).toLocaleString("zh-CN")}</CardDescription>}
          </div>
          <Button variant="outline" size="sm" className="h-7 text-xs gap-1" onClick={fetch_} disabled={loading}>
            {loading ? <Loader2 className="h-3 w-3 animate-spin" /> : <RefreshCw className="h-3 w-3" />} 刷新
          </Button>
        </div>
      </CardHeader>
      <CardContent className="space-y-2">
        {error && <div className="flex items-center gap-2 text-xs text-destructive bg-destructive/10 rounded p-2"><XCircle className="h-3.5 w-3.5 shrink-0" /> {error}</div>}
        {loading && !health && <div className="flex items-center gap-2 text-xs text-muted-foreground p-2"><Loader2 className="h-3.5 w-3.5 animate-spin" /> 检查中…</div>}
        {health?.services.map((svc) => <ServiceCard key={svc.label} svc={svc} />)}
        {health && (
          <p className="text-fs-xs text-muted-foreground/60 pt-1">
            点击「Galaxy 后端」或「进程监控」卡片可展开查看实时日志
          </p>
        )}
      </CardContent>
    </Card>
  );
}

// ── Run Stats Panel ───────────────────────────────────────────────────────────

interface DrillTarget { statusFilter: string; days?: number; label: string }

function ClickableStatCell({ label, value, drill, active, onClick }: {
  label: string;
  value: number | string;
  drill?: DrillTarget;
  active?: boolean;
  onClick?: () => void;
}) {
  const clickable = !!drill;
  return (
    <div
      className={`flex flex-col items-center gap-0.5 rounded-lg p-2 transition-colors
        ${clickable ? "cursor-pointer hover:bg-muted/60" : ""}
        ${active ? "bg-muted ring-1 ring-primary/30" : ""}`}
      onClick={onClick}
    >
      <span className={`text-lg font-semibold tabular-nums ${active ? "text-primary" : ""}`}>{value}</span>
      <span className="text-xs text-muted-foreground">{label}</span>
      {clickable && <span className="text-fs-xs text-primary/60">{active ? "▲ 收起" : "点击查看"}</span>}
    </div>
  );
}

function RunStatsPanel() {
  const [stats, setStats] = useState<RunStats | null>(null);
  const [userStats, setUserStats] = useState<UserStats | null>(null);
  const [loading, setLoading] = useState(false);
  const [drill, setDrill] = useState<DrillTarget | null>(null);

  const fetch_ = useCallback(async () => {
    setLoading(true);
    try {
      const [r1, r2] = await Promise.all([
        fetch("/api/admin/run-stats", { credentials: "include" }),
        fetch("/api/admin/user-stats", { credentials: "include" }),
      ]);
      if (r1.ok) setStats(await r1.json());
      if (r2.ok) setUserStats(await r2.json());
    } catch {}
    finally { setLoading(false); }
  }, []);
  useEffect(() => { fetch_(); }, [fetch_]);

  const toggleDrill = (d: DrillTarget) => {
    setDrill((prev) => (prev?.statusFilter === d.statusFilter && prev?.days === d.days ? null : d));
  };

  return (
    <Card>
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between">
          <CardTitle className="text-base flex items-center gap-2">
            <Activity className="h-4 w-4" /> 运行统计
          </CardTitle>
          <Button variant="outline" size="sm" className="h-7 text-xs gap-1" onClick={fetch_} disabled={loading}>
            {loading ? <Loader2 className="h-3 w-3 animate-spin" /> : <RefreshCw className="h-3 w-3" />} 刷新
          </Button>
        </div>
      </CardHeader>
      <CardContent className="space-y-4">
        {loading && !stats && <div className="flex items-center gap-2 text-xs text-muted-foreground p-2"><Loader2 className="h-3.5 w-3.5 animate-spin" /> 加载中…</div>}

        {stats && (
          <div>
            <p className="text-xs font-medium text-muted-foreground mb-2 flex items-center gap-1.5">
              <Layers className="h-3.5 w-3.5" /> 工作流执行
            </p>
            <div className="grid grid-cols-3 gap-1 text-center">
              {[
                { label: "进行中", value: stats.active, d: { statusFilter: "active", label: "进行中的工作流" } },
                { label: "24h 完成", value: stats.completed_24h, d: { statusFilter: "completed", days: 1, label: "近 24h 完成" } },
                { label: "24h 失败", value: stats.failed_24h, d: { statusFilter: "failed", days: 1, label: "近 24h 失败" } },
              ].map(({ label, value, d }) => (
                <ClickableStatCell
                  key={label} label={label} value={value} drill={d}
                  active={drill?.statusFilter === d.statusFilter && drill?.days === d.days}
                  onClick={() => toggleDrill(d)}
                />
              ))}
            </div>
            <Separator className="my-3" />
            <div className="grid grid-cols-3 gap-1 text-center">
              {[
                { label: "7d 完成", value: stats.completed_7d, d: { statusFilter: "completed", days: 7, label: "近 7d 完成" } },
                { label: "7d 失败", value: stats.failed_7d, d: { statusFilter: "failed", days: 7, label: "近 7d 失败" } },
                { label: "累计总数", value: stats.total, d: null },
              ].map(({ label, value, d }) => (
                <ClickableStatCell
                  key={label} label={label} value={value} drill={d ?? undefined}
                  active={d ? drill?.statusFilter === d.statusFilter && drill?.days === d.days : false}
                  onClick={d ? () => toggleDrill(d) : undefined}
                />
              ))}
            </div>

            {/* Drill-down run list */}
            {drill && (
              <RunListDrilldown
                statusFilter={drill.statusFilter}
                days={drill.days}
                label={drill.label}
              />
            )}

            {stats.failed_24h > 0 && !drill && (
              <div className="mt-3 flex items-center gap-2 text-xs bg-yellow-500/10 text-yellow-800 rounded p-2">
                <AlertTriangle className="h-3.5 w-3.5 shrink-0" />
                过去 24h 有 {stats.failed_24h} 个任务失败 — 点击「24h 失败」查看详情
              </div>
            )}
          </div>
        )}

        {userStats && (
          <>
            <Separator />
            <div>
              <p className="text-xs font-medium text-muted-foreground mb-2 flex items-center gap-1.5">
                <Users className="h-3.5 w-3.5" /> 用户
              </p>
              <div className="grid grid-cols-3 gap-3 text-center">
                <ClickableStatCell label="总用户" value={userStats.total} />
                <ClickableStatCell label="24h 新增" value={userStats.new_24h} />
                <ClickableStatCell label="7d 新增" value={userStats.new_7d} />
              </div>
            </div>
          </>
        )}
      </CardContent>
    </Card>
  );
}

// ── Cost estimate / compare (admin ops only) ──────────────────────────────────
// Lives on the existing /admin SystemDashboard — do NOT add a parallel /admin/cost page.

interface HonestCostEstimate {
  confidence: "historical" | "prior" | "unavailable";
  basis: string;
  assumptions: string[];
  sample_count?: number | null;
  nextflow_path?: string | null;
  domain?: string | null;
  range: { min_vcpu_hrs: number; max_vcpu_hrs: number };
  usd_range?: { min_usd: number; max_usd: number; label?: string } | null;
}

interface CostCompareRow {
  runId: string;
  workflowName: string | null;
  status: string | null;
  estimated_vcpu_hrs: number | null;
  actual_vcpu_hrs: number | null;
  delta_pct: number | null;
  estimate_confidence: string | null;
}

function CostPanel() {
  const [path, setPath] = useState("nf-core/rnaseq");
  const [domain, setDomain] = useState("");
  const [runId, setRunId] = useState("");
  const [estimate, setEstimate] = useState<HonestCostEstimate | null>(null);
  const [compareRows, setCompareRows] = useState<CostCompareRow[]>([]);
  const [runDetail, setRunDetail] = useState<any>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const runEstimate = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const qs = new URLSearchParams();
      if (path.trim()) qs.set("nextflow_path", path.trim());
      if (domain.trim()) qs.set("domain", domain.trim());
      const r = await fetch(`/api/admin/cost/estimate?${qs}`, { credentials: "include" });
      if (r.status === 403) { setError("需要管理员权限"); return; }
      if (!r.ok) { setError(`estimate ${r.status}`); return; }
      setEstimate(await r.json());
    } catch (e: any) {
      setError(e?.message || "estimate failed");
    } finally {
      setLoading(false);
    }
  }, [path, domain]);

  const runCompare = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const qs = new URLSearchParams({ limit: "15" });
      if (path.trim()) qs.set("nextflow_path", path.trim());
      const r = await fetch(`/api/admin/cost/compare?${qs}`, { credentials: "include" });
      if (!r.ok) { setError(`compare ${r.status}`); return; }
      const body = await r.json();
      setCompareRows(Array.isArray(body.rows) ? body.rows : []);
    } catch (e: any) {
      setError(e?.message || "compare failed");
    } finally {
      setLoading(false);
    }
  }, [path]);

  const loadRun = useCallback(async () => {
    if (!runId.trim()) return;
    setLoading(true);
    setError(null);
    try {
      const r = await fetch(`/api/admin/cost/runs/${encodeURIComponent(runId.trim())}`, { credentials: "include" });
      if (r.status === 404) { setError("run not found"); setRunDetail(null); return; }
      if (!r.ok) { setError(`run ${r.status}`); return; }
      setRunDetail(await r.json());
    } catch (e: any) {
      setError(e?.message || "run lookup failed");
    } finally {
      setLoading(false);
    }
  }, [runId]);

  const confColor =
    estimate?.confidence === "historical" ? "text-green-700"
      : estimate?.confidence === "prior" ? "text-yellow-700"
        : "text-muted-foreground";

  return (
    <Card data-testid="admin-cost-panel">
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between">
          <CardTitle className="text-base flex items-center gap-2">
            <DollarSign className="h-4 w-4" /> 成本估算（运维）
          </CardTitle>
          <Badge variant="outline" className="text-[10px]">admin only · 不对用户展示</Badge>
        </div>
        <CardDescription className="text-xs">
          honest vCPU-hrs：historical / prior / unavailable — 无假美元报价
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
          <div>
            <Label className="text-xs">nextflow_path</Label>
            <Input className="h-8 text-xs" value={path} onChange={(e) => setPath(e.target.value)} placeholder="nf-core/rnaseq" />
          </div>
          <div>
            <Label className="text-xs">domain（可选）</Label>
            <Input className="h-8 text-xs" value={domain} onChange={(e) => setDomain(e.target.value)} placeholder="rnaseq" />
          </div>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button size="sm" className="h-7 text-xs" onClick={runEstimate} disabled={loading}>估算</Button>
          <Button size="sm" variant="outline" className="h-7 text-xs" onClick={runCompare} disabled={loading}>对比近期</Button>
        </div>
        {error && <p className="text-xs text-destructive">{error}</p>}
        {estimate && (
          <div className="rounded border p-2 text-xs space-y-1" data-testid="admin-cost-estimate">
            <p className={confColor}>confidence: <strong>{estimate.confidence}</strong> · {estimate.basis}</p>
            <p>vCPU-hrs: {estimate.range.min_vcpu_hrs} – {estimate.range.max_vcpu_hrs}</p>
            {estimate.usd_range ? (
              <p className="text-muted-foreground">
                rough USD: ${estimate.usd_range.min_usd} – ${estimate.usd_range.max_usd}
                {estimate.usd_range.label ? ` (${estimate.usd_range.label})` : ""}
              </p>
            ) : (
              <p className="text-muted-foreground">无 USD 带（unavailable 或无费率）</p>
            )}
            <ul className="list-disc pl-4 text-muted-foreground">
              {(estimate.assumptions || []).slice(0, 5).map((a, i) => <li key={i}>{a}</li>)}
            </ul>
          </div>
        )}
        {compareRows.length > 0 && (
          <div className="overflow-auto max-h-48 border rounded" data-testid="admin-cost-compare">
            <table className="w-full text-[11px]">
              <thead>
                <tr className="text-left text-muted-foreground border-b">
                  <th className="p-1">run</th>
                  <th className="p-1">est</th>
                  <th className="p-1">actual</th>
                  <th className="p-1">Δ%</th>
                </tr>
              </thead>
              <tbody>
                {compareRows.map((row) => (
                  <tr key={row.runId} className="border-b last:border-0">
                    <td className="p-1 font-mono truncate max-w-[8rem]" title={row.runId}>{row.runId.slice(0, 8)}</td>
                    <td className="p-1">{row.estimated_vcpu_hrs ?? "—"}</td>
                    <td className="p-1">{row.actual_vcpu_hrs ?? "—"}</td>
                    <td className="p-1">{row.delta_pct != null ? `${row.delta_pct}%` : "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <Separator />
        <div className="flex gap-2 items-end">
          <div className="flex-1">
            <Label className="text-xs">runId</Label>
            <Input className="h-8 text-xs font-mono" value={runId} onChange={(e) => setRunId(e.target.value)} placeholder="execution run uuid" />
          </div>
          <Button size="sm" variant="outline" className="h-8 text-xs" onClick={loadRun} disabled={loading || !runId.trim()}>查 run</Button>
        </div>
        {runDetail && (
          <pre className="text-[10px] bg-muted/40 rounded p-2 overflow-auto max-h-40" data-testid="admin-cost-run">
            {JSON.stringify(runDetail, null, 2)}
          </pre>
        )}
      </CardContent>
    </Card>
  );
}

// ── LLM Probe Panel ───────────────────────────────────────────────────────────

function LLMProbePanel() {
  const [probe, setProbe] = useState<LLMProbe | null>(null);
  const [loading, setLoading] = useState(false);

  const run = useCallback(async () => {
    setLoading(true);
    try {
      const r = await fetch("/api/admin/llm-probe", { credentials: "include" });
      if (r.ok) setProbe(await r.json());
    } catch {}
    finally { setLoading(false); }
  }, []);

  const statusColor = probe?.status === "ok" ? "text-green-600"
    : probe?.status === "no_key" ? "text-yellow-600" : "text-red-600";

  const statusText = probe?.status === "ok" ? "可达"
    : probe?.status === "no_key" ? "未配置 API Key"
    : probe?.status === "unknown_provider" ? "未知 provider"
    : `连接失败${probe?.error ? "：" + probe.error : ""}`;

  return (
    <Card>
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between">
          <div>
            <CardTitle className="text-base flex items-center gap-2">
              <Wifi className="h-4 w-4" /> LLM 连通性探活
            </CardTitle>
            <CardDescription className="text-xs mt-1">发起真实 API 调用，验证当前配置的 LLM 是否可达</CardDescription>
          </div>
          <Button variant="outline" size="sm" className="h-7 text-xs gap-1" onClick={run} disabled={loading}>
            {loading ? <Loader2 className="h-3 w-3 animate-spin" /> : <Activity className="h-3 w-3" />}
            {loading ? "探测中…" : "立即探测"}
          </Button>
        </div>
      </CardHeader>
      <CardContent>
        {!probe && !loading && (
          <p className="text-xs text-muted-foreground text-center py-4">点击「立即探测」发起探活</p>
        )}
        {probe && (
          <div className="flex items-center justify-between rounded-lg border p-3">
            <div className="flex items-center gap-3">
              <div className="rounded-md bg-muted p-2"><Bot className="h-4 w-4 text-muted-foreground" /></div>
              <div>
                <p className="text-sm font-medium">{probe.provider}</p>
                <p className={`text-xs ${statusColor}`}>{statusText}</p>
              </div>
            </div>
            {probe.latency_ms != null && (
              <div className="flex items-center gap-1 text-xs text-muted-foreground">
                <Clock className="h-3 w-3" /> {probe.latency_ms}ms
              </div>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  );
}

// ── LLM Config Panel ──────────────────────────────────────────────────────────

function LLMConfigPanel() {
  const [config, setConfig] = useState<SystemConfig | null>(null);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [successMsg, setSuccessMsg] = useState("");
  const [envVars, setEnvVars] = useState<Record<string, string> | null>(null);
  const [provider, setProvider] = useState("anthropic");
  const [model, setModel] = useState("claude-sonnet-4-5");
  const [ollamaUrl, setOllamaUrl] = useState("http://ollama:11434");

  const load = useCallback(async () => {
    setLoading(true); setError("");
    try {
      const r = await fetch("/api/admin/system-config", { credentials: "include" });
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      const d: SystemConfig = await r.json();
      setConfig(d);
      const src = d.saved || d.effective;
      setProvider(src.provider); setModel(src.model || "");
      if (d.saved?.ollamaUrl) setOllamaUrl(d.saved.ollamaUrl);
      else if (d.env.ollamaUrl) setOllamaUrl(d.env.ollamaUrl);
    } catch (e: any) { setError(e.message); }
    finally { setLoading(false); }
  }, []);
  useEffect(() => { load(); }, [load]);

  const onProviderChange = (v: string) => {
    setProvider(v);
    setModel(PROVIDERS.find((p) => p.value === v)?.defaultModel || "");
  };

  const save = async () => {
    setSaving(true); setError(""); setSuccessMsg(""); setEnvVars(null);
    try {
      const r = await fetch("/api/admin/system-config", {
        method: "POST", credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ provider, model, ollamaUrl: provider === "ollama" ? ollamaUrl : undefined }),
      });
      const d = await r.json();
      if (!r.ok) throw new Error(d.error || `HTTP ${r.status}`);
      setSuccessMsg(d.note); setEnvVars(d.envVars); await load();
    } catch (e: any) { setError(e.message); }
    finally { setSaving(false); }
  };

  const selectedProvider = PROVIDERS.find((p) => p.value === provider);
  const hasRequiredKey = !selectedProvider?.needsKey
    || (provider === "anthropic" && config?.env.hasAnthropicKey)
    || (provider === "openai" && config?.env.hasOpenaiKey)
    || (provider === "zhipu" && config?.env.hasZhipuKey)
    || (provider === "deepseek" && config?.env.hasDeepseekKey)
    || (provider === "gemini" && config?.env.hasGeminiKey)
    || provider === "ollama" || provider === "openrouter";

  const envVarBlock = envVars ? Object.entries(envVars).map(([k, v]) => `${k}=${v}`).join("\n") : null;

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-base flex items-center gap-2">
          <Bot className="h-4 w-4" /> 系统 LLM 配置
        </CardTitle>
        <CardDescription className="text-xs">配置 Galaxy 后端使用的 AI 大模型。保存后需重启后端容器生效。</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {loading && <div className="flex items-center gap-2 text-xs text-muted-foreground p-2"><Loader2 className="h-3.5 w-3.5 animate-spin" /> 加载中…</div>}
        {config && (
          <div className="rounded-md bg-muted/50 px-3 py-2 space-y-1">
            <p className="text-xs font-medium text-muted-foreground">当前运行中</p>
            <p className="text-sm font-mono">{config.effective.provider} / {config.effective.model || "默认"}</p>
          </div>
        )}
        <Separator />
        <div className="space-y-1.5">
          <Label className="text-xs">AI 提供商</Label>
          <Select value={provider} onValueChange={onProviderChange}>
            <SelectTrigger className="h-8 text-xs"><SelectValue /></SelectTrigger>
            <SelectContent>
              {PROVIDERS.map((p) => (
                <SelectItem key={p.value} value={p.value} className="text-xs">
                  {p.label}{p.needsKey && <span className="ml-2 text-muted-foreground">(需要 {p.needsKey})</span>}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-1.5">
          <Label className="text-xs">模型名称</Label>
          <Input className="h-8 text-xs font-mono" placeholder={selectedProvider?.defaultModel || "model-name"} value={model} onChange={(e) => setModel(e.target.value)} />
        </div>
        {provider === "ollama" && (
          <div className="space-y-1.5">
            <Label className="text-xs">Ollama 服务地址</Label>
            <Input className="h-8 text-xs font-mono" placeholder="http://ollama:11434" value={ollamaUrl} onChange={(e) => setOllamaUrl(e.target.value)} />
            <p className="text-xs text-muted-foreground">Docker Compose 内部用 <code className="bg-muted px-1 rounded">http://ollama:11434</code>，本地直连用 <code className="bg-muted px-1 rounded">http://localhost:11434</code></p>
          </div>
        )}
        {selectedProvider?.needsKey && !hasRequiredKey && (
          <div className="flex items-start gap-2 text-xs rounded p-2 bg-yellow-500/10 text-yellow-800">
            <AlertCircle className="h-3.5 w-3.5 mt-0.5 shrink-0" />
            <span>当前环境变量中未检测到 <code className="bg-muted px-1 rounded">{selectedProvider.needsKey}</code>。保存配置后，请确认已在 .env 文件中设置对应的 API Key。</span>
          </div>
        )}
        {error && <div className="flex items-start gap-2 text-xs rounded p-2 bg-destructive/10 text-destructive"><XCircle className="h-3.5 w-3.5 mt-0.5 shrink-0" /> {error}</div>}
        {successMsg && <div className="flex items-start gap-2 text-xs rounded p-2 bg-green-500/10 text-green-700"><CheckCircle2 className="h-3.5 w-3.5 mt-0.5 shrink-0" /> {successMsg}</div>}
        {envVarBlock && <CopyBlock text={envVarBlock} label="将以下内容追加到后端 .env 文件，然后重启容器：" />}
        {envVarBlock && <CopyBlock text="docker restart biomate-engine" label="重启 BioMate 引擎：" />}
        <Button size="sm" className="h-8 text-xs gap-1.5 w-full" onClick={save} disabled={saving || loading}>
          {saving ? <Loader2 className="h-3 w-3 animate-spin" /> : null} 保存配置
        </Button>
        {config?.saved && <p className="text-xs text-muted-foreground">上次由 {config.saved.updatedBy} 保存于 {new Date(config.saved.updatedAt).toLocaleString("zh-CN")}</p>}
      </CardContent>
    </Card>
  );
}

// ── Page ──────────────────────────────────────────────────────────────────────

export default function SystemDashboardPage() {
  const { user } = useAuth();
  const [, setLocation] = useLocation();

  if (user && user.subscriptionTier !== "admin") {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <p className="text-muted-foreground text-sm">需要管理员权限</p>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-background">
      <div className="max-w-3xl mx-auto px-4 py-8 space-y-6">
        <div className="flex items-center gap-3">
          <Button variant="ghost" size="sm" className="h-7 text-xs gap-1" onClick={() => setLocation("/")}>
            <ArrowLeft className="h-3.5 w-3.5" /> 返回
          </Button>
          <div>
            <h1 className="text-xl font-semibold">系统管理</h1>
            <p className="text-xs text-muted-foreground">服务健康 · 运行统计 · 成本估算 · LLM 配置</p>
          </div>
        </div>

        <HealthPanel />
        <RunStatsPanel />
        <CostPanel />
        <LLMProbePanel />
        <LLMConfigPanel />
      </div>
    </div>
  );
}
