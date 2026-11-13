import { LanguageSelector } from "./language-selector";
import { useState, useEffect, useCallback } from "react"
import { MfaSettings } from "./mfa-settings"
import { RetrainAdapterCard } from "./RetrainAdapterCard"
import { useLocation } from "wouter"
import { useAuth } from "@/contexts/auth-context"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Label } from "@/components/ui/label"
import { Input } from "@/components/ui/input"
import { Switch } from "@/components/ui/switch"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Separator } from "@/components/ui/separator"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { userSettingsService } from "@/lib/user-settings"
import { notifyVoiceSettingsChanged } from "@/hooks/use-voice-settings"
import { t, tOr, setLanguagePreference } from "@/lib/i18n"
import { useLlmPolicy, modelGroups, effectivePick, pickRejected, INTL_DEFAULT_MODEL, CHINESE_MODELS } from "@/lib/llm-region"
import { HintTabsTrigger } from "@/components/ui/hint-tip"
import type { UserSettings } from "@shared/schema"
import {
  User,
  Settings,
  // Palette,  (Appearance tab hidden)
  MessageSquare,
  Database,
  Bell,
  Shield,
  Code,
  Download,
  Upload,
  RotateCcw,
  HelpCircle,
  ExternalLink,
  LogOut,
  Languages,
  CheckCircle2,
  XCircle,
  Loader2,
  Eye,
  EyeOff,
  Key,
  Copy,
  Plus,
  Trash2,
  Mic,
} from "lucide-react"

// ---------------------------------------------------------------------------
// Per-user API keys (biomate-connector / headless access)
// ---------------------------------------------------------------------------
interface ApiKeyRow {
  id: string;
  name: string | null;
  keyPrefix: string;
  createdAt: string;
  lastUsedAt: string | null;
  revokedAt: string | null;
}

function useApiKeys(open: boolean) {
  const [keys, setKeys] = useState<ApiKeyRow[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [newName, setNewName] = useState('');
  const [creating, setCreating] = useState(false);
  // Plaintext of the key just created — shown ONCE, then cleared.
  const [freshKey, setFreshKey] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const r = await fetch('/api/user/api-keys', { credentials: 'include' });
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      setKeys(await r.json());
    } catch (e: any) {
      setError(e.message || 'Failed to load API keys');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (open) { setFreshKey(null); load(); }
  }, [open, load]);

  const create = useCallback(async () => {
    setCreating(true);
    setError('');
    setFreshKey(null);
    try {
      const r = await fetch('/api/user/api-keys', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: newName.trim() || undefined }),
      });
      if (!r.ok) {
        const e = await r.json().catch(() => ({}));
        throw new Error(e.error || `HTTP ${r.status}`);
      }
      const d = await r.json();
      setFreshKey(d.key);
      setNewName('');
      await load();
    } catch (e: any) {
      setError(e.message || 'Failed to create API key');
    } finally {
      setCreating(false);
    }
  }, [newName, load]);

  const revoke = useCallback(async (id: string) => {
    setError('');
    try {
      const r = await fetch(`/api/user/api-keys/${id}`, { method: 'DELETE', credentials: 'include' });
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      await load();
    } catch (e: any) {
      setError(e.message || 'Failed to revoke API key');
    }
  }, [load]);

  const copyFresh = useCallback(() => {
    if (!freshKey) return;
    navigator.clipboard.writeText(freshKey).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }).catch(() => {});
  }, [freshKey]);

  return { keys, loading, error, newName, setNewName, creating, create, revoke, freshKey, dismissFresh: () => setFreshKey(null), copyFresh, copied };
}

// ---------------------------------------------------------------------------
// LLM Provider selection (BioMate default or OpenRouter)
// ---------------------------------------------------------------------------

/** The server's reason for refusing a save (e.g. a non-Chinese model for a China-region user). */
async function saveError(r: Response): Promise<Error> {
  const body = await r.json().catch(() => null);
  return new Error(body?.error || `HTTP ${r.status}`);
}

function useLlmApiKeys(open: boolean) {
  const [hasAnthropicKey, setHasAnthropicKey] = useState(false);
  const [hasOpenrouterKey, setHasOpenrouterKey] = useState(false);
  // Region policy (lib/llm-region.ts): China users are offered Chinese models only.
  const policy = useLlmPolicy(open);
  const [storedPick, setStoredPick] = useState<string | null>(null);
  const [selectedModel, setSelectedModel] = useState(INTL_DEFAULT_MODEL);
  useEffect(() => { if (policy) setSelectedModel(effectivePick(policy, storedPick)); }, [policy, storedPick]);
  const modelRejected = pickRejected(policy, selectedModel);

  const [provider, setProvider] = useState<'default' | 'anthropic' | 'openrouter'>('default');
  // A China-region user's stored Anthropic key is never used (the server drops it), so its option is hidden.
  useEffect(() => { if (policy?.anthropicKeyAllowed === false) setProvider(p => (p === 'anthropic' ? 'default' : p)); }, [policy]);
  const [anthropicInput, setAnthropicInput] = useState('');
  const [openrouterInput, setOpenrouterInput] = useState('');
  const [showKey, setShowKey] = useState(false);
  const [saving, setSaving] = useState(false);
  const [removing, setRemoving] = useState(false);
  const [statusMsg, setStatusMsg] = useState('');
  const [isError, setIsError] = useState(false);

  useEffect(() => {
    if (!open) return;
    fetch('/api/user/llm-api-keys', { credentials: 'include' })
      .then(r => r.ok ? r.json() : null)
      .then(d => {
        if (!d) return;
        setHasAnthropicKey(!!d.anthropic);
        setHasOpenrouterKey(!!d.openrouter);
        if (d.selected_model) { setStoredPick(d.selected_model); setSelectedModel(d.selected_model); }
        if (d.openrouter) setProvider('openrouter');
        else if (d.anthropic) setProvider('anthropic');
        else setProvider('default');
      })
      .catch(() => {});
  }, [open]);

  const saveAnthropicKey = useCallback(async () => {
    if (!anthropicInput.trim()) { setIsError(true); setStatusMsg('Paste your Anthropic API key first.'); return; }
    setSaving(true); setStatusMsg(''); setIsError(false);
    try {
      const r = await fetch('/api/user/llm-api-keys', {
        method: 'PATCH', credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ provider: 'anthropic', key: anthropicInput.trim() }),
      });
      if (!r.ok) throw await saveError(r);
      setHasAnthropicKey(true); setAnthropicInput('');
      setStatusMsg('Anthropic key saved — your chats use your own quota.');
    } catch (err: any) { setIsError(true); setStatusMsg(err.message); }
    finally { setSaving(false); }
  }, [anthropicInput]);

  const saveOpenrouterKey = useCallback(async () => {
    if (!openrouterInput.trim()) { setIsError(true); setStatusMsg('Paste your OpenRouter API key first.'); return; }
    if (modelRejected) { setIsError(true); setStatusMsg(t('settings.api.region_cn_model_rejected')); return; }
    setSaving(true); setStatusMsg(''); setIsError(false);
    try {
      const r = await fetch('/api/user/llm-api-keys', {
        method: 'PATCH', credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ provider: 'openrouter', key: openrouterInput.trim(), selected_model: selectedModel }),
      });
      if (!r.ok) throw await saveError(r);
      setHasOpenrouterKey(true); setOpenrouterInput('');
      setStatusMsg(`OpenRouter key saved — chats will use ${selectedModel}.`);
    } catch (err: any) { setIsError(true); setStatusMsg(err.message); }
    finally { setSaving(false); }
  }, [openrouterInput, selectedModel, modelRejected]);

  const saveModelOnly = useCallback(async () => {
    if (modelRejected) { setIsError(true); setStatusMsg(t('settings.api.region_cn_model_rejected')); return; }
    setSaving(true); setStatusMsg(''); setIsError(false);
    try {
      const r = await fetch('/api/user/llm-api-keys', {
        method: 'PATCH', credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ selected_model: selectedModel }),
      });
      if (!r.ok) throw await saveError(r);
      setStatusMsg(`Model updated to ${selectedModel}.`);
    } catch (err: any) { setIsError(true); setStatusMsg(err.message); }
    finally { setSaving(false); }
  }, [selectedModel, modelRejected]);

  const removeProvider = useCallback(async (prov: 'anthropic' | 'openrouter') => {
    setRemoving(true); setStatusMsg(''); setIsError(false);
    try {
      const r = await fetch('/api/user/llm-api-keys', {
        method: 'PATCH', credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ provider: prov, key: '' }),
      });
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      if (prov === 'anthropic') setHasAnthropicKey(false);
      if (prov === 'openrouter') setHasOpenrouterKey(false);
      setProvider('default');
      setStatusMsg('Key removed — chats now use the BioMate system model.');
    } catch (err: any) { setIsError(true); setStatusMsg(err.message); }
    finally { setRemoving(false); }
  }, []);

  return {
    provider, setProvider,
    hasAnthropicKey, anthropicInput, setAnthropicInput,
    hasOpenrouterKey, openrouterInput, setOpenrouterInput,
    selectedModel, setSelectedModel,
    policy, modelRejected,
    showKey, setShowKey,
    saving, removing,
    saveAnthropicKey, saveOpenrouterKey, saveModelOnly,
    removeProvider,
    statusMsg, isError,
  };
}

// ---------------------------------------------------------------------------
// S3 credential state
// ---------------------------------------------------------------------------
interface S3Creds {
  aws_access_key_id: string;
  aws_secret_access_key: string;
  aws_region: string;
  s3_bucket: string;
}
type S3VerifyStatus = 'idle' | 'saving' | 'verifying' | 'ok' | 'error';

function useS3Credentials(open: boolean) {
  const [creds, setCreds] = useState<S3Creds>({ aws_access_key_id: '', aws_secret_access_key: '', aws_region: 'us-east-1', s3_bucket: '' });
  const [status, setStatus] = useState<S3VerifyStatus>('idle');
  const [statusMsg, setStatusMsg] = useState('');
  const [hasSaved, setHasSaved] = useState(false);
  const [showSecret, setShowSecret] = useState(false);

  // Load whether credentials were previously saved (we can't read the secret back)
  useEffect(() => {
    if (!open) return;
    fetch('/api/users/credentials/s3', { credentials: 'include' })
      .then(r => r.ok ? r.json() : null)
      .then(d => { if (d?.has_credential) setHasSaved(true); })
      .catch(() => {});
  }, [open]);

  const update = (field: keyof S3Creds) => (e: React.ChangeEvent<HTMLInputElement>) => {
    setCreds(c => ({ ...c, [field]: e.target.value }));
    setStatus('idle');
  };

  const save = useCallback(async () => {
    if (!creds.aws_access_key_id || !creds.aws_secret_access_key || !creds.s3_bucket) {
      setStatus('error');
      setStatusMsg('Access Key ID, Secret Access Key, and bucket name are required.');
      return;
    }
    setStatus('saving');
    setStatusMsg('');
    try {
      const r = await fetch('/api/users/credentials', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ tool: 's3', data: { ...creds } }),
      });
      if (!r.ok) {
        const e = await r.json().catch(() => ({}));
        throw new Error(e.detail || e.error || `HTTP ${r.status}`);
      }
      setHasSaved(true);
      setStatus('ok');
      setStatusMsg('Credentials saved.');
    } catch (err: any) {
      setStatus('error');
      setStatusMsg(err.message);
    }
  }, [creds]);

  const verify = useCallback(async () => {
    if (!creds.aws_access_key_id || !creds.aws_secret_access_key || !creds.s3_bucket) {
      setStatus('error');
      setStatusMsg('Fill in all fields before verifying.');
      return;
    }
    setStatus('verifying');
    setStatusMsg('');
    try {
      const r = await fetch('/api/users/credentials/s3/verify', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ...creds }),
      });
      const d = await r.json();
      if (d.ok) {
        setStatus('ok');
        setStatusMsg(`Connected — bucket "${d.bucket}" is accessible (region: ${d.region})`);
      } else {
        setStatus('error');
        setStatusMsg(d.error || 'Connection failed');
      }
    } catch (err: any) {
      setStatus('error');
      setStatusMsg(err.message);
    }
  }, [creds]);

  const clear = useCallback(async () => {
    setCreds({ aws_access_key_id: '', aws_secret_access_key: '', aws_region: 'us-east-1', s3_bucket: '' });
    setHasSaved(false);
    setStatus('idle');
    setStatusMsg('');
    await fetch('/api/users/credentials/s3', { method: 'DELETE', credentials: 'include' }).catch(() => {});
  }, []);

  return { creds, update, save, verify, clear, status, statusMsg, hasSaved, showSecret, setShowSecret };
}

interface SettingsDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  onImportWorkflow?: () => void
}

export function SettingsDialog({ open, onOpenChange, onImportWorkflow }: SettingsDialogProps) {
  const { logout } = useAuth()
  const [, setLocation] = useLocation()
  const [settings, setSettings] = useState<UserSettings>(userSettingsService.getSettings())
  const [activeTab, setActiveTab] = useState("api-keys")
  const s3 = useS3Credentials(open)
  const apiKeysState = useApiKeys(open)
  const llmKeys = useLlmApiKeys(open)

  const handleLogout = async () => {
    onOpenChange(false)
    await logout()
    setLocation('/login')
  }

  useEffect(() => {
    if (open) {
      setSettings(userSettingsService.getSettings())
    }
  }, [open])

  const updateSetting = <K extends keyof UserSettings>(key: K, value: UserSettings[K]) => {
    const updatedSettings = userSettingsService.updateSetting(key, value)
    setSettings(updatedSettings)
    if (key === 'voiceEnabled' || key === 'voiceHandsFree') notifyVoiceSettingsChanged()
  }

  const resetToDefaults = () => {
    const defaultSettings = userSettingsService.resetToDefaults()
    setSettings(defaultSettings)
    notifyVoiceSettingsChanged()
  }

  const exportSettings = () => {
    const settingsJson = userSettingsService.exportSettings()
    const blob = new Blob([settingsJson], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = 'biomate-settings.json'
    a.click()
    URL.revokeObjectURL(url)
  }

  const importSettings = (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0]
    if (file) {
      const reader = new FileReader()
      reader.onload = (e) => {
        try {
          const settingsJson = e.target?.result as string
          const importedSettings = userSettingsService.importSettings(settingsJson)
          setSettings(importedSettings)
        } catch (error) {
          console.error('Error importing settings:', error)
        }
      }
      reader.readAsText(file)
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="flex h-[min(90dvh,48rem)] max-h-[90dvh] w-[95vw] max-w-2xl min-h-0 flex-col overflow-hidden p-0" data-testid="settings-dialog">
        <DialogHeader className="shrink-0 p-4 pb-0 sm:p-6 sm:pb-0">
          <DialogTitle className="flex items-center gap-2">
            <Settings className="w-5 h-5" />
            {t('settings.title')}
          </DialogTitle>
          <LanguageSelector />
        </DialogHeader>

        {/* Settings panel — tabbed. API Keys is one tab inside Settings (not a
            standalone modal). Only genuinely-functional tabs are enabled; the
            stale stub tabs stay gated (enabling them would ship broken forms). */}
        <div className="flex min-h-0 flex-1 overflow-hidden">
          <Tabs value={activeTab} onValueChange={setActiveTab} className="flex min-h-0 min-w-0 flex-1" orientation="vertical">
            <div className="w-36 sm:w-48 shrink-0 overflow-y-auto overscroll-contain border-r bg-muted/50 p-2 sm:p-4">
              <TabsList className="grid w-full grid-cols-1 h-auto gap-1 bg-transparent">
                <HintTabsTrigger hint={t('hint.settings.api_keys')} side="right" value="api-keys" className="justify-start gap-2 p-3" data-testid="tab-api-keys">
                  <Key className="w-4 h-4" />
                  {t('settings.api_keys')}
                </HintTabsTrigger>
                <TabsTrigger value="voice" className="justify-start gap-2 p-3" data-testid="tab-voice">
                  <Mic className="w-4 h-4" />
                  {tOr('settings.voice', 'Voice')}
                </TabsTrigger>
                {/* Appearance (theme) tab hidden — light only for now; dark mode not reviewed.
                <TabsTrigger value="appearance" className="justify-start gap-2 p-3" data-testid="tab-appearance">
                  <Palette className="w-4 h-4" />
                  {tOr('settings.appearance', 'Appearance')}
                </TabsTrigger>
                */}
                <HintTabsTrigger hint={t('hint.settings.connectors')} side="right" value="connections" className="justify-start gap-2 p-3" data-testid="tab-settings-connectors">{t('nav.connectors')}</HintTabsTrigger>
                {onImportWorkflow && <HintTabsTrigger hint={t('hint.settings.import')} side="right" value="imports" className="justify-start gap-2 p-3" data-testid="tab-settings-imports">{t('nav.import_workflow')}</HintTabsTrigger>}
                {/* Stale stub tabs (profile/general/chat/data/notifications/privacy/
                    security/advanced) remain gated below until rebuilt. */}
              </TabsList>

              {/* Quick Actions and Help sections commented out — not needed for API keys only view */}
            </div>

            {/* Settings Content */}
            <div className="min-h-0 min-w-0 flex-1 overflow-y-auto overscroll-contain p-4 sm:p-6" data-testid="settings-scroll-content" role="region" aria-label={t("settings.content")} tabIndex={0}>
              {/* Non-api-keys tabs commented out — only API Keys needed for now */}
              {false && (<>
              {/* Profile Tab */}
              <TabsContent value="profile" className="space-y-6 m-0">
                <div>
                  <h3 className="text-lg font-semibold mb-4">Profile Information</h3>
                  
                  <Card>
                    <CardHeader>
                      <CardTitle className="flex items-center gap-2">
                        <Avatar className="w-12 h-12">
                          <AvatarImage src={settings.avatar} alt="Profile" />
                          <AvatarFallback>{settings.displayName?.charAt(0) || 'U'}</AvatarFallback>
                        </Avatar>
                        <div>
                          <div className="flex items-center gap-2">
                            <span>{settings.displayName}</span>
                            <Badge variant="secondary">Pro Plan</Badge>
                          </div>
                          <p className="text-sm text-muted-foreground">{settings.email}</p>
                        </div>
                      </CardTitle>
                    </CardHeader>
                    <CardContent className="space-y-4">
                      <div className="grid grid-cols-2 gap-4">
                        <div className="space-y-2">
                          <Label htmlFor="display-name">Display Name</Label>
                          <Input
                            id="display-name"
                            value={settings.displayName || ''}
                            onChange={(e) => updateSetting('displayName', e.target.value)}
                            data-testid="input-display-name"
                          />
                        </div>
                        <div className="space-y-2">
                          <Label htmlFor="email">Email</Label>
                          <Input
                            id="email"
                            type="email"
                            value={settings.email || ''}
                            onChange={(e) => updateSetting('email', e.target.value)}
                            data-testid="input-email"
                          />
                        </div>
                      </div>
                      <div className="space-y-2">
                        <Label htmlFor="role">Role</Label>
                        <Input
                          id="role"
                          value={settings.role}
                          onChange={(e) => updateSetting('role', e.target.value)}
                          data-testid="input-role"
                        />
                      </div>
                    </CardContent>
                  </Card>
                </div>
              </TabsContent>

              {/* General Tab */}
              <TabsContent value="general" className="space-y-6 m-0">
                <div>
                  <h3 className="text-lg font-semibold mb-4">General Settings</h3>
                  
                  <Card>
                    <CardHeader>
                      <CardTitle className="flex items-center gap-2">
                        <Languages className="w-5 h-5" />
                        Language & Region
                      </CardTitle>
                      <CardDescription>
                        Configure your language preferences
                      </CardDescription>
                    </CardHeader>
                    <CardContent>
                      <div className="space-y-2">
                        <Label htmlFor="language">{t('settings.language')}</Label>
                        <Select
                          value={settings.language}
                          onValueChange={(value: any) => {
                            // Persist + reload FIRST (captures the true previous
                            // value so a real change triggers the reload that lets
                            // lib/i18n.ts — which resolves locale once at module
                            // load from this same localStorage key — apply it).
                            setLanguagePreference(value)
                            // Fallback local-state update if the value is unchanged
                            // (no reload) so the Select still reflects the choice.
                            updateSetting('language', value)
                          }}
                        >
                          <SelectTrigger data-testid="select-language">
                            <SelectValue />
                          </SelectTrigger>
                          <SelectContent>
                            <SelectItem value="english">English</SelectItem>
                            <SelectItem value="spanish">Español</SelectItem>
                            <SelectItem value="french">Français</SelectItem>
                            <SelectItem value="german">Deutsch</SelectItem>
                            <SelectItem value="chinese">中文</SelectItem>
                          </SelectContent>
                        </Select>
                      </div>
                    </CardContent>
                  </Card>
                </div>
              </TabsContent>

              {/* Appearance tab moved OUT of this gated block (it's functional) —
                  see the active TabsContent after the gate closes. */}

              {/* Chat Tab */}
              <TabsContent value="chat" className="space-y-6 m-0">
                <div>
                  <h3 className="text-lg font-semibold mb-4">Chat Preferences</h3>
                  
                  <Card>
                    <CardContent className="space-y-6 pt-6">
                      <div className="flex items-center justify-between">
                        <div className="space-y-0.5">
                          <Label>Chat Suggestions</Label>
                          <p className="text-sm text-muted-foreground">
                            Show suggestion chips after assistant responses
                          </p>
                        </div>
                        <Switch
                          checked={settings.chatSuggestions}
                          onCheckedChange={(checked) => updateSetting('chatSuggestions', checked)}
                          data-testid="switch-chat-suggestions"
                        />
                      </div>
                      
                      <Separator />
                      
                      <div className="flex items-center justify-between">
                        <div className="space-y-0.5">
                          <Label>Typing Indicator</Label>
                          <p className="text-sm text-muted-foreground">
                            Show typing indicator when assistant is responding
                          </p>
                        </div>
                        <Switch
                          checked={settings.typingIndicator}
                          onCheckedChange={(checked) => updateSetting('typingIndicator', checked)}
                          data-testid="switch-typing-indicator"
                        />
                      </div>
                      
                      <Separator />
                      
                      <div className="flex items-center justify-between">
                        <div className="space-y-0.5">
                          <Label>Message Timestamps</Label>
                          <p className="text-sm text-muted-foreground">
                            Show timestamps on chat messages
                          </p>
                        </div>
                        <Switch
                          checked={settings.messageTimestamps}
                          onCheckedChange={(checked) => updateSetting('messageTimestamps', checked)}
                          data-testid="switch-message-timestamps"
                        />
                      </div>

                      {/* Voice toggles live on the active Voice tab — not here.
                          This whole Chat Preferences block is inside {false && …}. */}
                    </CardContent>
                  </Card>
                </div>
              </TabsContent>

              {/* Data Tab */}
              <TabsContent value="data" className="space-y-6 m-0">
                <div className="space-y-6">
                  <h3 className="text-lg font-semibold">Data Management</h3>

                  {/* Storage type */}
                  <Card>
                    <CardHeader className="pb-3">
                      <CardTitle className="text-sm font-medium">Default Storage</CardTitle>
                    </CardHeader>
                    <CardContent className="space-y-4">
                      <div className="space-y-2">
                        <Label htmlFor="default-storage">Storage Type</Label>
                        <Select value={settings.defaultStorageType} onValueChange={(value: any) => updateSetting('defaultStorageType', value)}>
                          <SelectTrigger data-testid="select-default-storage">
                            <SelectValue />
                          </SelectTrigger>
                          <SelectContent>
                            <SelectItem value="replit_storage">Replit Storage</SelectItem>
                            <SelectItem value="local">Local Storage</SelectItem>
                            <SelectItem value="s3">Amazon S3</SelectItem>
                          </SelectContent>
                        </Select>
                      </div>

                      <Separator />

                      <div className="flex items-center justify-between">
                        <div className="space-y-0.5">
                          <Label>Auto-delete Temporary Files</Label>
                          <p className="text-xs text-muted-foreground">Clean up temporary workflow files automatically</p>
                        </div>
                        <Switch checked={settings.autoDeleteTempFiles} onCheckedChange={(v) => updateSetting('autoDeleteTempFiles', v)} data-testid="switch-auto-delete-temp" />
                      </div>

                      <div className="space-y-2">
                        <Label htmlFor="retention-days">Data Retention (Days)</Label>
                        <Input id="retention-days" type="number" value={settings.dataRetentionDays} onChange={(e) => updateSetting('dataRetentionDays', parseInt(e.target.value) || 30)} data-testid="input-retention-days" />
                      </div>
                    </CardContent>
                  </Card>

                  {/* AWS S3 credentials — always visible so users can set up their bucket */}
                  <Card data-testid="s3-credentials-card">
                    <CardHeader className="pb-3">
                      <div className="flex items-center justify-between">
                        <div>
                          <CardTitle className="text-sm font-medium flex items-center gap-2">
                            Amazon S3 Credentials
                            {s3.hasSaved && s3.status !== 'error' && (
                              <Badge variant="secondary" className="text-xs font-normal gap-1">
                                <CheckCircle2 className="h-3 w-3 text-green-600" />
                                Saved
                              </Badge>
                            )}
                          </CardTitle>
                          <CardDescription className="text-xs mt-1">
                            Provide your own AWS credentials to access private S3 buckets during workflow execution.
                            Create a read-only IAM user with <code className="bg-muted px-1 rounded text-fs-xs">s3:GetObject</code> and <code className="bg-muted px-1 rounded text-fs-xs">s3:ListBucket</code> on your data bucket.
                          </CardDescription>
                        </div>
                        {s3.hasSaved && (
                          <Button variant="ghost" size="sm" className="text-xs text-muted-foreground h-7" onClick={s3.clear} data-testid="button-s3-clear">
                            Clear
                          </Button>
                        )}
                      </div>
                    </CardHeader>
                    <CardContent className="space-y-4">
                      <div className="grid grid-cols-2 gap-3">
                        <div className="space-y-1.5">
                          <Label htmlFor="aws-access-key-id" className="text-xs">Access Key ID</Label>
                          <Input
                            id="aws-access-key-id"
                            placeholder="AKIAIOSFODNN7EXAMPLE"
                            value={s3.creds.aws_access_key_id}
                            onChange={s3.update('aws_access_key_id')}
                            autoComplete="off"
                            data-testid="input-aws-access-key-id"
                            className="font-mono text-xs h-8"
                          />
                        </div>
                        <div className="space-y-1.5">
                          <Label htmlFor="aws-secret-access-key" className="text-xs">Secret Access Key</Label>
                          <div className="relative">
                            <Input
                              id="aws-secret-access-key"
                              type={s3.showSecret ? 'text' : 'password'}
                              placeholder="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
                              value={s3.creds.aws_secret_access_key}
                              onChange={s3.update('aws_secret_access_key')}
                              autoComplete="new-password"
                              data-testid="input-aws-secret-access-key"
                              className="font-mono text-xs h-8 pr-8"
                            />
                            <button
                              type="button"
                              className="absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
                              onClick={() => s3.setShowSecret(!s3.showSecret)}
                              data-testid="button-toggle-secret-visibility"
                              tabIndex={-1}
                            >
                              {s3.showSecret ? <EyeOff className="h-3.5 w-3.5" /> : <Eye className="h-3.5 w-3.5" />}
                            </button>
                          </div>
                        </div>
                        <div className="space-y-1.5">
                          <Label htmlFor="aws-region" className="text-xs">Region</Label>
                          <Input
                            id="aws-region"
                            placeholder="us-east-1"
                            value={s3.creds.aws_region}
                            onChange={s3.update('aws_region')}
                            data-testid="input-aws-region"
                            className="font-mono text-xs h-8"
                          />
                        </div>
                        <div className="space-y-1.5">
                          <Label htmlFor="s3-bucket" className="text-xs">Bucket Name</Label>
                          <Input
                            id="s3-bucket"
                            placeholder="my-cryo-data-bucket"
                            value={s3.creds.s3_bucket}
                            onChange={s3.update('s3_bucket')}
                            data-testid="input-s3-bucket"
                            className="font-mono text-xs h-8"
                          />
                        </div>
                      </div>

                      {/* Status message */}
                      {s3.statusMsg && (
                        <div className={`flex items-start gap-2 text-xs rounded p-2 ${s3.status === 'ok' ? 'bg-green-50 text-green-700 dark:bg-green-900/20 dark:text-green-400' : 'bg-destructive/10 text-destructive'}`} data-testid="s3-status-message">
                          {s3.status === 'ok'
                            ? <CheckCircle2 className="h-3.5 w-3.5 mt-0.5 shrink-0" />
                            : <XCircle className="h-3.5 w-3.5 mt-0.5 shrink-0" />}
                          <span>{s3.statusMsg}</span>
                        </div>
                      )}

                      <div className="flex gap-2 pt-1">
                        <Button
                          size="sm"
                          className="h-7 text-xs gap-1.5"
                          onClick={s3.save}
                          disabled={s3.status === 'saving' || s3.status === 'verifying'}
                          data-testid="button-save-s3-credentials"
                        >
                          {s3.status === 'saving' && <Loader2 className="h-3 w-3 animate-spin" />}
                          Save credentials
                        </Button>
                        <Button
                          variant="outline"
                          size="sm"
                          className="h-7 text-xs gap-1.5"
                          onClick={s3.verify}
                          disabled={s3.status === 'saving' || s3.status === 'verifying'}
                          data-testid="button-verify-s3-credentials"
                        >
                          {s3.status === 'verifying' && <Loader2 className="h-3 w-3 animate-spin" />}
                          Test connection
                        </Button>
                      </div>
                    </CardContent>
                  </Card>
                </div>
              </TabsContent>

              {/* Notifications Tab */}
              <TabsContent value="notifications" className="space-y-6 m-0">
                <div>
                  <h3 className="text-lg font-semibold mb-4">Notification Preferences</h3>
                  
                  <Card>
                    <CardContent className="space-y-6 pt-6">
                      <div className="flex items-center justify-between">
                        <div className="space-y-0.5">
                          <Label>Workflow Completion Notifications</Label>
                          <p className="text-sm text-muted-foreground">
                            Get notified when workflows complete
                          </p>
                        </div>
                        <Switch
                          checked={settings.workflowCompletionNotifications}
                          onCheckedChange={(checked) => updateSetting('workflowCompletionNotifications', checked)}
                          data-testid="switch-workflow-notifications"
                        />
                      </div>
                      
                      <Separator />
                      
                      <div className="flex items-center justify-between">
                        <div className="space-y-0.5">
                          <Label>Error Notifications</Label>
                          <p className="text-sm text-muted-foreground">
                            Get notified when errors occur
                          </p>
                        </div>
                        <Switch
                          checked={settings.errorNotifications}
                          onCheckedChange={(checked) => updateSetting('errorNotifications', checked)}
                          data-testid="switch-error-notifications"
                        />
                      </div>
                    </CardContent>
                  </Card>
                </div>
              </TabsContent>

              {/* Privacy Tab */}
              <TabsContent value="privacy" className="space-y-6 m-0">
                <div>
                  <h3 className="text-lg font-semibold mb-4">Privacy Settings</h3>
                  
                  <Card>
                    <CardContent className="space-y-6 pt-6">
                      <div className="flex items-center justify-between">
                        <div className="space-y-0.5">
                          <Label>Share Usage Data</Label>
                          <p className="text-sm text-muted-foreground">
                            Help improve BioMate by sharing anonymous usage data
                          </p>
                        </div>
                        <Switch
                          checked={settings.shareUsageData}
                          onCheckedChange={(checked) => updateSetting('shareUsageData', checked)}
                          data-testid="switch-share-usage"
                        />
                      </div>
                      
                      <Separator />
                      
                      <div className="flex items-center justify-between">
                        <div className="space-y-0.5">
                          <Label>Share Error Reports</Label>
                          <p className="text-sm text-muted-foreground">
                            Automatically send error reports to help us fix issues
                          </p>
                        </div>
                        <Switch
                          checked={settings.shareErrorReports}
                          onCheckedChange={(checked) => updateSetting('shareErrorReports', checked)}
                          data-testid="switch-share-errors"
                        />
                      </div>
                    </CardContent>
                  </Card>
                </div>
              </TabsContent>

              {/* Security Tab */}
              <TabsContent value="security" className="space-y-6 m-0">
                <div>
                  <h3 className="text-lg font-semibold mb-1">Security</h3>
                  <p className="text-sm text-muted-foreground mb-4">
                    Manage authentication security for your account.
                  </p>
                  <MfaSettings />
                </div>
              </TabsContent>
              </>)}{/* end commented-out non-api-keys tabs */}

              {/* Voice — must stay outside the {false && …} gate. Sidebar only
                  exposes api-keys / voice / connectors / imports; Chat was never
                  a reachable tab, so earlier "Settings → Chat → Voice" was a lie. */}
              <TabsContent value="voice" className="space-y-6 m-0" data-testid="tab-content-voice">
                <div>
                  <h3 className="text-lg font-semibold mb-4">{tOr('settings.voice', 'Voice')}</h3>
                  <Card>
                    <CardContent className="space-y-6 pt-6">
                      <div className="flex items-center justify-between">
                        <div className="space-y-0.5">
                          <Label>Voice in chat</Label>
                          <p className="text-sm text-muted-foreground">
                            Show compact Speak and Live icons in the composer toolbar.
                          </p>
                        </div>
                        <Switch
                          checked={settings.voiceEnabled === true}
                          onCheckedChange={(checked) => updateSetting('voiceEnabled', checked)}
                          data-testid="switch-voice-enabled"
                        />
                      </div>
                      <Separator />
                      <div className="flex items-center justify-between">
                        <div className="space-y-0.5">
                          <Label>Hands-free</Label>
                          <p className="text-sm text-muted-foreground">
                            During a live session, send when you pause. Review gene names and sample IDs before relying on auto-send.
                          </p>
                        </div>
                        <Switch
                          checked={settings.voiceHandsFree === true}
                          disabled={settings.voiceEnabled !== true}
                          onCheckedChange={(checked) => updateSetting('voiceHandsFree', checked)}
                          data-testid="switch-voice-hands-free"
                        />
                      </div>
                    </CardContent>
                  </Card>
                </div>
              </TabsContent>

              <TabsContent value="connections" className="space-y-4 m-0">
                <Button data-testid="button-connectors-settings" onClick={() => { onOpenChange(false); setLocation('/settings/connections'); }}>{t('nav.connectors')}</Button>
              </TabsContent>
              <TabsContent value="imports" className="space-y-4 m-0">
                <Button data-testid="button-import-workflow-settings" onClick={onImportWorkflow}>{t('nav.import_workflow')}</Button>
              </TabsContent>
              {/* Appearance tab content hidden — light only for now.
              <TabsContent value="appearance" className="space-y-6 m-0" data-testid="tab-content-appearance">
                <div>
                  <h3 className="text-lg font-semibold mb-4">{tOr('settings.appearance', 'Appearance')}</h3>
                  <Card>
                    <CardHeader>
                      <CardTitle>{t('settings.theme')}</CardTitle>
                      <CardDescription>{tOr('settings.theme_desc', 'Choose your preferred appearance')}</CardDescription>
                    </CardHeader>
                    <CardContent>
                      <div className="space-y-2">
                        <Label htmlFor="theme">{t('settings.theme')}</Label>
                        <Select value={settings.theme} onValueChange={(value: any) => updateSetting('theme', value)}>
                          <SelectTrigger data-testid="select-theme">
                            <SelectValue />
                          </SelectTrigger>
                          <SelectContent>
                            <SelectItem value="system">{t('settings.system')}</SelectItem>
                            <SelectItem value="light">{t('settings.light')}</SelectItem>
                            <SelectItem value="dark">{t('settings.dark')}</SelectItem>
                          </SelectContent>
                        </Select>
                      </div>
                    </CardContent>
                  </Card>
                </div>
              </TabsContent>
              */}

              {/* API Keys Tab */}
              <TabsContent value="api-keys" className="space-y-6 m-0" data-testid="tab-content-api-keys">
                <div>
                  <h3 className="text-lg font-semibold mb-1">{t('settings.api_keys')}</h3>
                  <p className="text-xs text-muted-foreground mb-4">
                    {t('settings.api.conn_desc_pre')} <code className="bg-muted px-1 rounded text-fs-xs">Authorization: Bearer &lt;key&gt;</code>{t('settings.api.conn_desc_mid')} <span className="font-medium">{t('settings.api.you')}</span> {t('settings.api.conn_desc_post')}
                  </p>

                  {/* Freshly created key — shown once */}
                  {apiKeysState.freshKey && (
                    <Card className="mb-4 border-green-500/40" data-testid="fresh-api-key-card">
                      <CardHeader className="pb-2">
                        <CardTitle className="text-sm font-medium flex items-center gap-2">
                          <CheckCircle2 className="h-4 w-4 text-green-600" />
                          {t('settings.api.new_key_created')}
                        </CardTitle>
                        <CardDescription className="text-xs">
                          {t('settings.api.copy_now_pre')} <span className="font-medium">{t('settings.api.not_shown_again')}</span>.
                        </CardDescription>
                      </CardHeader>
                      <CardContent className="space-y-2">
                        <div className="flex items-center gap-2">
                          <Input
                            readOnly
                            value={apiKeysState.freshKey}
                            className="font-mono text-xs h-8"
                            data-testid="input-fresh-api-key"
                            onFocus={(e) => e.currentTarget.select()}
                          />
                          <Button size="sm" variant="outline" className="h-8 text-xs gap-1 shrink-0" onClick={apiKeysState.copyFresh} data-testid="button-copy-fresh-key">
                            <Copy className="h-3.5 w-3.5" />
                            {apiKeysState.copied ? t('settings.api.copied') : t('settings.api.copy')}
                          </Button>
                          <Button size="sm" variant="ghost" className="h-8 text-xs shrink-0" onClick={apiKeysState.dismissFresh} data-testid="button-dismiss-fresh-key">
                            {t('settings.api.done')}
                          </Button>
                        </div>
                      </CardContent>
                    </Card>
                  )}

                  {/* Create new key */}
                  <Card className="mb-4">
                    <CardContent className="pt-4">
                      <div className="flex items-end gap-2">
                        <div className="flex-1 space-y-1.5">
                          <Label htmlFor="api-key-name" className="text-xs">{t('settings.api.name_optional')}</Label>
                          <Input
                            id="api-key-name"
                            placeholder={t('settings.api.name_placeholder')}
                            value={apiKeysState.newName}
                            onChange={(e) => apiKeysState.setNewName(e.target.value)}
                            className="text-xs h-8"
                            data-testid="input-api-key-name"
                          />
                        </div>
                        <Button
                          size="sm"
                          className="h-8 text-xs gap-1.5"
                          onClick={apiKeysState.create}
                          disabled={apiKeysState.creating}
                          data-testid="button-create-api-key"
                        >
                          {apiKeysState.creating ? <Loader2 className="h-3 w-3 animate-spin" /> : <Plus className="h-3.5 w-3.5" />}
                          {t('settings.api.generate_key')}
                        </Button>
                      </div>
                    </CardContent>
                  </Card>

                  {apiKeysState.error && (
                    <div className="flex items-start gap-2 text-xs rounded p-2 mb-4 bg-destructive/10 text-destructive" data-testid="api-keys-error">
                      <XCircle className="h-3.5 w-3.5 mt-0.5 shrink-0" />
                      <span>{apiKeysState.error}</span>
                    </div>
                  )}

                  {/* Existing keys */}
                  <div className="space-y-2" data-testid="api-keys-list">
                    {apiKeysState.loading && (
                      <div className="flex items-center gap-2 text-xs text-muted-foreground p-2">
                        <Loader2 className="h-3.5 w-3.5 animate-spin" /> {t('settings.api.loading')}
                      </div>
                    )}
                    {!apiKeysState.loading && apiKeysState.keys.length === 0 && (
                      <p className="text-xs text-muted-foreground p-2">{t('settings.api.no_keys')}</p>
                    )}
                    {apiKeysState.keys.map((k) => (
                      <div
                        key={k.id}
                        className="flex items-center justify-between gap-3 rounded border p-3"
                        data-testid={`api-key-row-${k.id}`}
                      >
                        <div className="min-w-0">
                          <div className="flex items-center gap-2">
                            <span className="text-sm font-medium truncate">{k.name || t('settings.api.unnamed_key')}</span>
                            {k.revokedAt
                              ? <Badge variant="secondary" className="text-fs-xs">{t('settings.api.revoked')}</Badge>
                              : <Badge variant="secondary" className="text-fs-xs gap-1"><CheckCircle2 className="h-3 w-3 text-green-600" />{t('settings.api.active')}</Badge>}
                          </div>
                          <div className="text-fs-xs text-muted-foreground font-mono mt-0.5">{k.keyPrefix}</div>
                          <div className="text-fs-xs text-muted-foreground mt-0.5">
                            {t('settings.api.created', { date: new Date(k.createdAt).toLocaleDateString() })}
                            {k.lastUsedAt ? t('settings.api.last_used', { date: new Date(k.lastUsedAt).toLocaleDateString() }) : t('settings.api.never_used')}
                          </div>
                        </div>
                        {!k.revokedAt && (
                          <Button
                            size="sm"
                            variant="ghost"
                            className="h-7 text-xs text-destructive hover:text-destructive gap-1 shrink-0"
                            onClick={() => apiKeysState.revoke(k.id)}
                            data-testid={`button-revoke-api-key-${k.id}`}
                          >
                            <Trash2 className="h-3.5 w-3.5" /> {t('settings.api.revoke')}
                          </Button>
                        )}
                      </div>
                    ))}
                  </div>
                </div>

                {/* ── LLM Provider selection ───────────────────────────── */}
                <Separator />
                <div>
                  <h3 className="text-lg font-semibold mb-1">{t('settings.api.llm_provider')}</h3>
                  <p className="text-xs text-muted-foreground mb-4">
                    {t('settings.api.llm_desc')}
                  </p>

                  {/* Provider radio group */}
                  <div className="space-y-2 mb-4">
                  {llmKeys.policy?.region === 'cn' && (
                    <p className="text-xs text-muted-foreground mb-3 rounded-md border bg-muted/40 px-3 py-2" data-testid="llm-region-note">
                      {t('settings.api.region_cn_note')}
                    </p>
                  )}
                    {([
                      { value: 'default', label: t('settings.api.provider_default_label'), desc: t('settings.api.provider_default_desc') },
                      { value: 'openrouter', label: 'OpenRouter', desc: t('settings.api.provider_openrouter_desc') },
                      // China-region users cannot use an Anthropic key (it only ever reaches Claude).
                      ...(llmKeys.policy?.anthropicKeyAllowed === false ? [] : [
                        { value: 'anthropic' as const, label: t('settings.api.provider_anthropic_label'), desc: t('settings.api.provider_anthropic_desc') },
                      ]),
                    ] as const).map(opt => (
                      <button
                        key={opt.value}
                        type="button"
                        onClick={() => llmKeys.setProvider(opt.value)}
                        className={`w-full flex items-start gap-3 rounded-md border px-3 py-2.5 text-left transition-colors ${llmKeys.provider === opt.value ? 'border-primary bg-primary/5' : 'border-border hover:bg-muted/50'}`}
                      >
                        <div className={`mt-0.5 h-4 w-4 rounded-full border-2 shrink-0 flex items-center justify-center ${llmKeys.provider === opt.value ? 'border-primary' : 'border-muted-foreground/40'}`}>
                          {llmKeys.provider === opt.value && <div className="h-2 w-2 rounded-full bg-primary" />}
                        </div>
                        <div>
                          <p className="text-sm font-medium leading-none mb-0.5">{opt.label}</p>
                          <p className="text-xs text-muted-foreground">{opt.desc}</p>
                        </div>
                      </button>
                    ))}
                  </div>

                  {/* OpenRouter section */}
                  {llmKeys.provider === 'openrouter' && (
                    <Card className="mb-3">
                      <CardContent className="pt-4 space-y-3">
                        {/* Model selector */}
                        <div className="space-y-1.5">
                          <Label className="text-xs">{t('settings.api.model')} <span className="text-muted-foreground font-normal">{t('settings.api.model_hint')}</span></Label>
                          <Input
                            className="font-mono text-xs h-8"
                            placeholder={t('settings.api.model_placeholder')}
                            value={llmKeys.selectedModel}
                            onChange={e => llmKeys.setSelectedModel(e.target.value)}
                            data-testid="input-llm-model"
                            aria-invalid={llmKeys.modelRejected || undefined}
                          />
                          {llmKeys.modelRejected && (
                            <p className="text-xs text-destructive" role="alert" data-testid="llm-model-region-error">
                              {t('settings.api.region_cn_model_rejected')}
                            </p>
                          )}
                          {/* Quick-pick the models BioMate has been tested against,
                              so the panel reflects the backend's supported set instead
                              of an opaque free-text box. Click to fill; still editable.
                              Slugs verified against OpenRouter's live /models list and
                              BioMate's routing benchmark (evaluation/.../models.yaml,
                              _wfgenB_summary.json). Open flagships first — glm-5.3-prime
                              is the recommended open default (best routing recall + lowest
                              cost); all are function-calling capable so they get the full
                              agentic pipeline (tools + workflows + run_code). */}
                          <div className="space-y-2 pt-0.5" data-testid="llm-model-quickpick">
                            {modelGroups(llmKeys.policy?.region).map(g => ({
                              label: t(g.key === 'chinese' ? 'settings.api.models_chinese' : g.key === 'open' ? 'settings.api.models_open' : 'settings.api.models_proprietary'),
                              slugs: g.slugs,
                            })).map(group => (
                              <div key={group.label}>
                                <p className="text-fs-xs uppercase tracking-wide text-muted-foreground/70 mb-1">{group.label}</p>
                                <div className="flex flex-wrap gap-1.5">
                                  {group.slugs.map(slug => {
                                    const recommended = slug === (llmKeys.policy?.region === 'cn' ? (llmKeys.policy.defaultModel || CHINESE_MODELS[0]) : INTL_DEFAULT_MODEL);
                                    return (
                                      <button
                                        key={slug}
                                        type="button"
                                        title={recommended ? t('settings.api.model_recommended') : undefined}
                                        onClick={() => llmKeys.setSelectedModel(slug)}
                                        className={`font-mono text-fs-xs rounded-full border px-2 py-0.5 transition-colors ${llmKeys.selectedModel === slug ? 'border-primary bg-primary/10 text-primary' : 'border-border text-muted-foreground hover:bg-muted/50'}`}
                                      >
                                        {recommended ? '★ ' : ''}{slug.split('/').pop()}
                                      </button>
                                    );
                                  })}
                                </div>
                              </div>
                            ))}
                          </div>
                          <p className="text-xs text-muted-foreground">
                            {t('settings.api.browse_pre')} <span className="font-mono">openrouter.ai/models</span> {t('settings.api.browse_post')}
                          </p>
                        </div>
                        {/* API key input */}
                        {llmKeys.hasOpenrouterKey ? (
                          <div className="flex items-center justify-between gap-3 rounded-md bg-green-500/10 px-3 py-2">
                            <div className="flex items-center gap-2 text-xs text-green-700">
                              <CheckCircle2 className="h-3.5 w-3.5 shrink-0" />
                              <span>{t('settings.api.openrouter_saved')}</span>
                            </div>
                            <div className="flex items-center gap-1.5">
                              <Button size="sm" variant="outline" className="h-7 text-xs gap-1"
                                onClick={llmKeys.saveModelOnly} disabled={llmKeys.saving}>
                                {llmKeys.saving ? <Loader2 className="h-3 w-3 animate-spin" /> : null}
                                {t('settings.api.update_model')}
                              </Button>
                              <Button size="sm" variant="ghost" className="h-7 text-xs text-destructive hover:text-destructive gap-1"
                                onClick={() => llmKeys.removeProvider('openrouter')} disabled={llmKeys.removing}
                                data-testid="button-remove-openrouter-key">
                                {llmKeys.removing ? <Loader2 className="h-3 w-3 animate-spin" /> : <Trash2 className="h-3.5 w-3.5" />}
                                {t('settings.api.remove')}
                              </Button>
                            </div>
                          </div>
                        ) : (
                          <div className="space-y-1.5">
                            <Label htmlFor="openrouter-api-key" className="text-xs">{t('settings.api.openrouter_key_label')}</Label>
                            <div className="flex items-center gap-2">
                              <div className="relative flex-1">
                                <Input
                                  id="openrouter-api-key"
                                  type={llmKeys.showKey ? 'text' : 'password'}
                                  placeholder="sk-or-…"
                                  value={llmKeys.openrouterInput}
                                  onChange={e => llmKeys.setOpenrouterInput(e.target.value)}
                                  className="font-mono text-xs h-8 pr-8"
                                  data-testid="input-openrouter-api-key"
                                />
                                <Button type="button" size="icon" variant="ghost"
                                  className="absolute right-1 top-1 h-6 w-6 text-muted-foreground"
                                  onClick={() => llmKeys.setShowKey(v => !v)} tabIndex={-1}>
                                  {llmKeys.showKey ? <EyeOff className="h-3.5 w-3.5" /> : <Eye className="h-3.5 w-3.5" />}
                                </Button>
                              </div>
                              <Button size="sm" className="h-8 text-xs gap-1.5 shrink-0"
                                onClick={llmKeys.saveOpenrouterKey} disabled={llmKeys.saving}
                                data-testid="button-save-openrouter-key">
                                {llmKeys.saving ? <Loader2 className="h-3 w-3 animate-spin" /> : <Key className="h-3.5 w-3.5" />}
                                {t('settings.api.save_key')}
                              </Button>
                            </div>
                            <p className="text-xs text-muted-foreground">
                              {t('settings.api.get_key_pre')} <span className="font-mono">openrouter.ai</span> {t('settings.api.get_key_post')}
                            </p>
                          </div>
                        )}
                      </CardContent>
                    </Card>
                  )}

                  {/* Anthropic BYOK section */}
                  {llmKeys.provider === 'anthropic' && (
                    <Card className="mb-3">
                      <CardContent className="pt-4 space-y-3">
                        {llmKeys.hasAnthropicKey ? (
                          <div className="flex items-center justify-between gap-3 rounded-md bg-green-500/10 px-3 py-2">
                            <div className="flex items-center gap-2 text-xs text-green-700">
                              <CheckCircle2 className="h-3.5 w-3.5 shrink-0" />
                              <span>{t('settings.api.anthropic_saved')}</span>
                            </div>
                            <Button size="sm" variant="ghost"
                              className="h-7 text-xs text-destructive hover:text-destructive gap-1 shrink-0"
                              onClick={() => llmKeys.removeProvider('anthropic')} disabled={llmKeys.removing}
                              data-testid="button-remove-llm-key">
                              {llmKeys.removing ? <Loader2 className="h-3 w-3 animate-spin" /> : <Trash2 className="h-3.5 w-3.5" />}
                              {t('settings.api.remove')}
                            </Button>
                          </div>
                        ) : (
                          <div className="space-y-1.5">
                            <Label htmlFor="anthropic-api-key" className="text-xs">{t('settings.api.anthropic_key_label')}</Label>
                            <div className="flex items-center gap-2">
                              <div className="relative flex-1">
                                <Input
                                  id="anthropic-api-key"
                                  type={llmKeys.showKey ? 'text' : 'password'}
                                  placeholder="sk-ant-…"
                                  value={llmKeys.anthropicInput}
                                  onChange={e => llmKeys.setAnthropicInput(e.target.value)}
                                  className="font-mono text-xs h-8 pr-8"
                                  data-testid="input-anthropic-api-key"
                                />
                                <Button type="button" size="icon" variant="ghost"
                                  className="absolute right-1 top-1 h-6 w-6 text-muted-foreground"
                                  onClick={() => llmKeys.setShowKey(v => !v)} tabIndex={-1}>
                                  {llmKeys.showKey ? <EyeOff className="h-3.5 w-3.5" /> : <Eye className="h-3.5 w-3.5" />}
                                </Button>
                              </div>
                              <Button size="sm" className="h-8 text-xs gap-1.5 shrink-0"
                                onClick={llmKeys.saveAnthropicKey} disabled={llmKeys.saving}
                                data-testid="button-save-llm-key">
                                {llmKeys.saving ? <Loader2 className="h-3 w-3 animate-spin" /> : <Key className="h-3.5 w-3.5" />}
                                {t('settings.api.save_key')}
                              </Button>
                            </div>
                          </div>
                        )}
                      </CardContent>
                    </Card>
                  )}

                  {llmKeys.statusMsg && (
                    <div className={`flex items-start gap-2 text-xs rounded p-2 ${llmKeys.isError ? 'bg-destructive/10 text-destructive' : 'bg-green-500/10 text-green-700'}`}
                      data-testid="llm-key-status">
                      {llmKeys.isError
                        ? <XCircle className="h-3.5 w-3.5 mt-0.5 shrink-0" />
                        : <CheckCircle2 className="h-3.5 w-3.5 mt-0.5 shrink-0 text-green-600" />}
                      <span>{llmKeys.statusMsg}</span>
                    </div>
                  )}
                </div>
              </TabsContent>

              {/* Advanced Tab — commented out */}
              {false && <TabsContent value="advanced" className="space-y-6 m-0">
                <div>
                  <h3 className="text-lg font-semibold mb-4">Advanced Settings</h3>

                  {/* B3 — Per-org regulatory LLM adaptation queue. The
                      RetrainAdapterCard self-fetches state on mount and
                      handles its own loading/error display. */}
                  <Card style={{ marginBottom: 16 }}>
                    <CardHeader>
                      <CardTitle className="text-base">Regulatory LLM adaptation</CardTitle>
                      <CardDescription>
                        Train a per-organisation rule pack from your accumulated edit
                        history so the regulatory LLM matches your house style on the
                        next inference call.
                      </CardDescription>
                    </CardHeader>
                    <CardContent>
                      <RetrainAdapterCard />
                    </CardContent>
                  </Card>

                  <Card>
                    <CardContent className="space-y-6 pt-6">
                      <div className="flex items-center justify-between">
                        <div className="space-y-0.5">
                          <Label>Debug Mode</Label>
                          <p className="text-sm text-muted-foreground">
                            Enable detailed logging for troubleshooting
                          </p>
                        </div>
                        <Switch
                          checked={settings.debugMode}
                          onCheckedChange={(checked) => updateSetting('debugMode', checked)}
                          data-testid="switch-debug-mode"
                        />
                      </div>
                      
                      <Separator />
                      
                      <div className="flex items-center justify-between">
                        <div className="space-y-0.5">
                          <Label>Experimental Features</Label>
                          <p className="text-sm text-muted-foreground">
                            Access beta features and new functionality
                          </p>
                        </div>
                        <Switch
                          checked={settings.experimentalFeatures}
                          onCheckedChange={(checked) => updateSetting('experimentalFeatures', checked)}
                          data-testid="switch-experimental"
                        />
                      </div>
                    </CardContent>
                  </Card>
                </div>
              </TabsContent>}
            </div>
          </Tabs>
        </div>
      </DialogContent>
    </Dialog>
  )
}