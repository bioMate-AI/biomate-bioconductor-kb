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
  CheckCircle2,
  XCircle,
  AlertCircle,
  Loader2,
  RefreshCw,
  ArrowLeft,
  Copy,
  Check,
  Server,
  Database,
  Cpu,
  Bot,
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

interface SystemConfig {
  effective: { provider: string; model: string };
  env: {
    hasAnthropicKey: boolean;
    hasOpenaiKey: boolean;
    hasZhipuKey: boolean;
    hasDeepseekKey: boolean;
    hasGeminiKey: boolean;
    ollamaUrl: string;
  };
  saved: {
    provider: string;
    model: string;
    ollamaUrl: string;
    updatedAt: string;
    updatedBy: string;
  } | null;
}

// ── Constants ────────────────────────────────────────────────────────────────

const PROVIDERS = [
  { value: "anthropic", label: "Anthropic Claude", defaultModel: "claude-sonnet-4-5", needsKey: "ANTHROPIC_API_KEY" },
  { value: "deepseek", label: "DeepSeek (国内)", defaultModel: "deepseek-chat", needsKey: "DEEPSEEK_API_KEY" },
  { value: "zhipu", label: "智谱 GLM (国内)", defaultModel: "glm-4.7", needsKey: "ZHIPU_API_KEY" },
  { value: "openrouter", label: "OpenRouter (多模型)", defaultModel: "deepseek/deepseek-chat-v3-5", needsKey: "OPENROUTER_API_KEY" },
  { value: "ollama", label: "Ollama (本地离线)", defaultModel: "qwen3:32b", needsKey: null },
  { value: "openai", label: "OpenAI GPT", defaultModel: "gpt-4o", needsKey: "OPENAI_API_KEY" },
  { value: "gemini", label: "Google Gemini", defaultModel: "gemini-2.0-flash", needsKey: "GOOGLE_API_KEY" },
];

const SERVICE_ICONS: Record<string, any> = {
  galaxy_version: Server,
  index_health: Database,
  process_health: Cpu,
  postgres: Database,
};

// ── Sub-components ────────────────────────────────────────────────────────────

function StatusBadge({ status }: { status: "ok" | "degraded" | "down" }) {
  if (status === "ok")
    return (
      <Badge className="bg-green-500/10 text-green-700 border-green-500/20 gap-1">
        <CheckCircle2 className="h-3 w-3" /> 正常
      </Badge>
    );
  if (status === "degraded")
    return (
      <Badge className="bg-yellow-500/10 text-yellow-700 border-yellow-500/20 gap-1">
        <AlertCircle className="h-3 w-3" /> 降级
      </Badge>
    );
  return (
    <Badge className="bg-red-500/10 text-red-700 border-red-500/20 gap-1">
      <XCircle className="h-3 w-3" /> 离线
    </Badge>
  );
}

function ServiceCard({ svc }: { svc: ServiceStatus }) {
  const Icon = SERVICE_ICONS[svc.label] || Server;
  const labelMap: Record<string, string> = {
    galaxy_version: "Galaxy 后端",
    index_health: "工作流索引",
    process_health: "进程监控",
    postgres: "PostgreSQL",
  };
  return (
    <div className="flex items-center justify-between gap-3 rounded-lg border p-3">
      <div className="flex items-center gap-3">
        <div className="rounded-md bg-muted p-2">
          <Icon className="h-4 w-4 text-muted-foreground" />
        </div>
        <div>
          <p className="text-sm font-medium">{labelMap[svc.label] || svc.label}</p>
          {svc.error && <p className="text-xs text-muted-foreground truncate max-w-[200px]">{svc.error}</p>}
          {svc.data?.version && <p className="text-xs text-muted-foreground">v{svc.data.version}</p>}
        </div>
      </div>
      <StatusBadge status={svc.status} />
    </div>
  );
}

function CopyBlock({ text, label }: { text: string; label: string }) {
  const [copied, setCopied] = useState(false);
  const copy = () => {
    navigator.clipboard.writeText(text).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    });
  };
  return (
    <div className="space-y-1">
      <p className="text-xs text-muted-foreground">{label}</p>
      <div className="relative">
        <pre className="rounded bg-muted px-3 py-2 text-xs font-mono overflow-x-auto pr-10">{text}</pre>
        <button
          onClick={copy}
          className="absolute right-2 top-2 text-muted-foreground hover:text-foreground"
          title="复制"
        >
          {copied ? <Check className="h-3.5 w-3.5 text-green-600" /> : <Copy className="h-3.5 w-3.5" />}
        </button>
      </div>
    </div>
  );
}

// ── Health Panel ──────────────────────────────────────────────────────────────

function HealthPanel() {
  const [health, setHealth] = useState<HealthSummary | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  const fetch_ = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const r = await fetch("/api/admin/health-summary", { credentials: "include" });
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      setHealth(await r.json());
    } catch (e: any) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { fetch_(); }, [fetch_]);

  return (
    <Card>
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between">
          <div>
            <CardTitle className="text-base flex items-center gap-2">
              服务健康状态
              {health && <StatusBadge status={health.overall} />}
            </CardTitle>
            {health && (
              <CardDescription className="text-xs mt-1">
                最后检查：{new Date(health.checkedAt).toLocaleString("zh-CN")}
              </CardDescription>
            )}
          </div>
          <Button variant="outline" size="sm" className="h-7 text-xs gap-1" onClick={fetch_} disabled={loading}>
            {loading ? <Loader2 className="h-3 w-3 animate-spin" /> : <RefreshCw className="h-3 w-3" />}
            刷新
          </Button>
        </div>
      </CardHeader>
      <CardContent className="space-y-2">
        {error && (
          <div className="flex items-center gap-2 text-xs text-destructive bg-destructive/10 rounded p-2">
            <XCircle className="h-3.5 w-3.5 shrink-0" /> {error}
          </div>
        )}
        {loading && !health && (
          <div className="flex items-center gap-2 text-xs text-muted-foreground p-2">
            <Loader2 className="h-3.5 w-3.5 animate-spin" /> 检查中…
          </div>
        )}
        {health?.services.map((svc) => <ServiceCard key={svc.label} svc={svc} />)}
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
    setLoading(true);
    setError("");
    try {
      const r = await fetch("/api/admin/system-config", { credentials: "include" });
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      const d: SystemConfig = await r.json();
      setConfig(d);
      // Pre-fill form with saved config if available, else effective
      const src = d.saved || d.effective;
      setProvider(src.provider);
      setModel(src.model || "");
      if (d.saved?.ollamaUrl) setOllamaUrl(d.saved.ollamaUrl);
      else if (d.env.ollamaUrl) setOllamaUrl(d.env.ollamaUrl);
    } catch (e: any) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  const onProviderChange = (v: string) => {
    setProvider(v);
    const def = PROVIDERS.find((p) => p.value === v)?.defaultModel || "";
    setModel(def);
  };

  const save = async () => {
    setSaving(true);
    setError("");
    setSuccessMsg("");
    setEnvVars(null);
    try {
      const r = await fetch("/api/admin/system-config", {
        method: "POST",
        credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ provider, model, ollamaUrl: provider === "ollama" ? ollamaUrl : undefined }),
      });
      const d = await r.json();
      if (!r.ok) throw new Error(d.error || `HTTP ${r.status}`);
      setSuccessMsg(d.note);
      setEnvVars(d.envVars);
      await load();
    } catch (e: any) {
      setError(e.message);
    } finally {
      setSaving(false);
    }
  };

  const selectedProvider = PROVIDERS.find((p) => p.value === provider);
  const hasRequiredKey =
    !selectedProvider?.needsKey ||
    (provider === "anthropic" && config?.env.hasAnthropicKey) ||
    (provider === "openai" && config?.env.hasOpenaiKey) ||
    (provider === "zhipu" && config?.env.hasZhipuKey) ||
    (provider === "deepseek" && config?.env.hasDeepseekKey) ||
    (provider === "gemini" && config?.env.hasGeminiKey) ||
    provider === "ollama" ||
    provider === "openrouter";

  const envVarBlock = envVars
    ? Object.entries(envVars)
        .map(([k, v]) => `${k}=${v}`)
        .join("\n")
    : null;

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-base flex items-center gap-2">
          <Bot className="h-4 w-4" />
          系统 LLM 配置
        </CardTitle>
        <CardDescription className="text-xs">
          配置 Galaxy 后端使用的 AI 大模型。保存后需重启后端容器生效。
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {loading && (
          <div className="flex items-center gap-2 text-xs text-muted-foreground p-2">
            <Loader2 className="h-3.5 w-3.5 animate-spin" /> 加载中…
          </div>
        )}

        {/* Current effective config */}
        {config && (
          <div className="rounded-md bg-muted/50 px-3 py-2 space-y-1">
            <p className="text-xs font-medium text-muted-foreground">当前运行中</p>
            <p className="text-sm font-mono">
              {config.effective.provider} / {config.effective.model || "默认"}
            </p>
          </div>
        )}

        <Separator />

        {/* Provider selector */}
        <div className="space-y-1.5">
          <Label className="text-xs">AI 提供商</Label>
          <Select value={provider} onValueChange={onProviderChange}>
            <SelectTrigger className="h-8 text-xs">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {PROVIDERS.map((p) => (
                <SelectItem key={p.value} value={p.value} className="text-xs">
                  {p.label}
                  {p.needsKey && (
                    <span className="ml-2 text-muted-foreground">
                      (需要 {p.needsKey})
                    </span>
                  )}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>

        {/* Model input */}
        <div className="space-y-1.5">
          <Label className="text-xs">模型名称</Label>
          <Input
            className="h-8 text-xs font-mono"
            placeholder={selectedProvider?.defaultModel || "model-name"}
            value={model}
            onChange={(e) => setModel(e.target.value)}
          />
        </div>

        {/* Ollama URL */}
        {provider === "ollama" && (
          <div className="space-y-1.5">
            <Label className="text-xs">Ollama 服务地址</Label>
            <Input
              className="h-8 text-xs font-mono"
              placeholder="http://ollama:11434"
              value={ollamaUrl}
              onChange={(e) => setOllamaUrl(e.target.value)}
            />
            <p className="text-xs text-muted-foreground">
              Docker Compose 内部用 <code className="bg-muted px-1 rounded">http://ollama:11434</code>，本地直连用 <code className="bg-muted px-1 rounded">http://localhost:11434</code>
            </p>
          </div>
        )}

        {/* API key warning */}
        {selectedProvider?.needsKey && !hasRequiredKey && (
          <div className="flex items-start gap-2 text-xs rounded p-2 bg-yellow-500/10 text-yellow-800">
            <AlertCircle className="h-3.5 w-3.5 mt-0.5 shrink-0" />
            <span>
              当前环境变量中未检测到 <code className="bg-muted px-1 rounded">{selectedProvider.needsKey}</code>。
              保存配置后，请确认已在 .env 文件中设置对应的 API Key。
            </span>
          </div>
        )}

        {/* Error / success */}
        {error && (
          <div className="flex items-start gap-2 text-xs rounded p-2 bg-destructive/10 text-destructive">
            <XCircle className="h-3.5 w-3.5 mt-0.5 shrink-0" /> {error}
          </div>
        )}
        {successMsg && (
          <div className="flex items-start gap-2 text-xs rounded p-2 bg-green-500/10 text-green-700">
            <CheckCircle2 className="h-3.5 w-3.5 mt-0.5 shrink-0" /> {successMsg}
          </div>
        )}

        {/* Env vars to copy */}
        {envVarBlock && (
          <CopyBlock
            text={envVarBlock}
            label="将以下内容追加到后端 .env 文件，然后重启容器："
          />
        )}

        {/* Restart command */}
        {envVarBlock && (
          <CopyBlock
            text="docker restart biomate-galaxy"
            label="重启 Galaxy 后端："
          />
        )}

        {/* Save button */}
        <Button size="sm" className="h-8 text-xs gap-1.5 w-full" onClick={save} disabled={saving || loading}>
          {saving ? <Loader2 className="h-3 w-3 animate-spin" /> : null}
          保存配置
        </Button>

        {/* Saved config info */}
        {config?.saved && (
          <p className="text-xs text-muted-foreground">
            上次由 {config.saved.updatedBy} 保存于{" "}
            {new Date(config.saved.updatedAt).toLocaleString("zh-CN")}
          </p>
        )}
      </CardContent>
    </Card>
  );
}

// ── Page ──────────────────────────────────────────────────────────────────────

export default function SystemDashboardPage() {
  const { user } = useAuth();
  const [, setLocation] = useLocation();

  if (user && (user as any).subscriptionTier !== "admin") {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <p className="text-muted-foreground text-sm">需要管理员权限</p>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-background">
      <div className="max-w-3xl mx-auto px-4 py-8 space-y-6">
        {/* Header */}
        <div className="flex items-center gap-3">
          <Button variant="ghost" size="sm" className="h-7 text-xs gap-1" onClick={() => setLocation("/")}>
            <ArrowLeft className="h-3.5 w-3.5" /> 返回
          </Button>
          <div>
            <h1 className="text-xl font-semibold">系统管理</h1>
            <p className="text-xs text-muted-foreground">服务健康状态 + LLM 配置</p>
          </div>
        </div>

        <HealthPanel />
        <LLMConfigPanel />
      </div>
    </div>
  );
}
