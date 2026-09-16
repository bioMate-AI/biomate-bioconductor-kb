import { useState, useEffect, useCallback } from "react";
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
  MemoryStick, Layers, Clock,
} from "lucide-react";

// ── Types ────────────────────────────────────────────────────────────────────

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

// ── Constants ────────────────────────────────────────────────────────────────

const PROVIDERS = [
  { value: "anthropic",  label: "Anthropic Claude",       defaultModel: "claude-sonnet-4-5",             needsKey: "ANTHROPIC_API_KEY" },
  { value: "deepseek",   label: "DeepSeek (国内)",          defaultModel: "deepseek-chat",                 needsKey: "DEEPSEEK_API_KEY" },
  { value: "zhipu",      label: "智谱 GLM (国内)",            defaultModel: "glm-4.7",                       needsKey: "ZHIPU_API_KEY" },
  { value: "openrouter", label: "OpenRouter (多模型)",       defaultModel: "deepseek/deepseek-chat-v3-5",   needsKey: "OPENROUTER_API_KEY" },
  { value: "ollama",     label: "Ollama (本地离线)",          defaultModel: "qwen3:32b",                     needsKey: null },
  { value: "openai",     label: "OpenAI GPT",              defaultModel: "gpt-4o",                        needsKey: "OPENAI_API_KEY" },
  { value: "gemini",     label: "Google Gemini",           defaultModel: "gemini-2.0-flash",              needsKey: "GOOGLE_API_KEY" },
];

// ── Helpers ──────────────────────────────────────────────────────────────────

function StatusBadge({ status }: { status: "ok" | "degraded" | "down" }) {
  if (status === "ok")
    return <Badge className="bg-green-500/10 text-green-700 border-green-500/20 gap-1"><CheckCircle2 className="h-3 w-3" /> 正常</Badge>;
  if (status === "degraded")
    return <Badge className="bg-yellow-500/10 text-yellow-700 border-yellow-500/20 gap-1"><AlertCircle className="h-3 w-3" /> 降级</Badge>;
  return <Badge className="bg-red-500/10 text-red-700 border-red-500/20 gap-1"><XCircle className="h-3 w-3" /> 离线</Badge>;
}

function StatCell({ label, value, sub }: { label: string; value: number | string; sub?: string }) {
  return (
    <div className="flex flex-col items-center gap-0.5">
      <span className="text-lg font-semibold tabular-nums">{value}</span>
      <span className="text-xs text-muted-foreground">{label}</span>
      {sub && <span className="text-[10px] text-muted-foreground/70">{sub}</span>}
    </div>
  );
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
          {redis.status === 'ok'
            ? <span className="text-green-600">正常 {redis.latency_ms}ms</span>
            : redis.status === 'not_configured'
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
  const Icon = SERVICE_ICONS[svc.label] || Server;
  return (
    <div className="rounded-lg border p-3">
      <div className="flex items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <div className="rounded-md bg-muted p-2">
            <Icon className="h-4 w-4 text-muted-foreground" />
          </div>
          <div>
            <p className="text-sm font-medium">{SERVICE_LABELS[svc.label] || svc.label}</p>
            {svc.error && <p className="text-xs text-muted-foreground truncate max-w-[200px]">{svc.error}</p>}
            {svc.data?.version && <p className="text-xs text-muted-foreground">v{svc.data.version}</p>}
            {svc.label === 'index_health' && svc.data?.total != null && (
              <p className="text-xs text-muted-foreground">{svc.data.total.toLocaleString()} 工作流</p>
            )}
          </div>
        </div>
        <StatusBadge status={svc.status} />
      </div>
      {svc.label === 'process_health' && <ProcessDetail data={svc.data} />}
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
      </CardContent>
    </Card>
  );
}

// ── Run Stats Panel ───────────────────────────────────────────────────────────

function RunStatsPanel() {
  const [stats, setStats] = useState<RunStats | null>(null);
  const [userStats, setUserStats] = useState<UserStats | null>(null);
  const [loading, setLoading] = useState(false);

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

        {/* Run stats */}
        {stats && (
          <div>
            <p className="text-xs font-medium text-muted-foreground mb-3 flex items-center gap-1.5">
              <Layers className="h-3.5 w-3.5" /> 工作流执行
            </p>
            <div className="grid grid-cols-3 gap-3 text-center">
              <StatCell label="进行中" value={stats.active} />
              <StatCell label="24h 完成" value={stats.completed_24h} />
              <StatCell label="24h 失败" value={stats.failed_24h} />
            </div>
            <Separator className="my-3" />
            <div className="grid grid-cols-3 gap-3 text-center">
              <StatCell label="7d 完成" value={stats.completed_7d} />
              <StatCell label="7d 失败" value={stats.failed_7d} />
              <StatCell label="累计总数" value={stats.total} />
            </div>
            {stats.failed_24h > 0 && (
              <div className="mt-3 flex items-center gap-2 text-xs bg-yellow-500/10 text-yellow-800 rounded p-2">
                <AlertCircle className="h-3.5 w-3.5 shrink-0" />
                过去 24h 有 {stats.failed_24h} 个任务失败
              </div>
            )}
          </div>
        )}

        {/* User stats */}
        {userStats && (
          <>
            <Separator />
            <div>
              <p className="text-xs font-medium text-muted-foreground mb-3 flex items-center gap-1.5">
                <Users className="h-3.5 w-3.5" /> 用户
              </p>
              <div className="grid grid-cols-3 gap-3 text-center">
                <StatCell label="总用户" value={userStats.total} />
                <StatCell label="24h 新增" value={userStats.new_24h} />
                <StatCell label="7d 新增" value={userStats.new_7d} />
              </div>
            </div>
          </>
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

  const statusColor = probe?.status === 'ok' ? 'text-green-600'
    : probe?.status === 'no_key' ? 'text-yellow-600' : 'text-red-600';

  const statusText = probe?.status === 'ok' ? '可达'
    : probe?.status === 'no_key' ? '未配置 API Key'
    : probe?.status === 'unknown_provider' ? '未知 provider'
    : `连接失败${probe?.error ? '：' + probe.error : ''}`;

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
            {loading ? '探测中…' : '立即探测'}
          </Button>
        </div>
      </CardHeader>
      <CardContent>
        {!probe && !loading && (
          <p className="text-xs text-muted-foreground text-center py-4">点击「立即探测」发起探活</p>
        )}
        {probe && (
          <div className="space-y-3">
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
        {envVarBlock && <CopyBlock text="docker restart biomate-galaxy" label="重启 Galaxy 后端：" />}
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
            <p className="text-xs text-muted-foreground">服务健康 · 运行统计 · LLM 配置</p>
          </div>
        </div>

        <HealthPanel />
        <RunStatsPanel />
        <LLMProbePanel />
        <LLMConfigPanel />
      </div>
    </div>
  );
}
