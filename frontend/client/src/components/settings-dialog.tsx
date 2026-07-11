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
import { ScrollArea } from "@/components/ui/scroll-area"
import { userSettingsService } from "@/lib/user-settings"
import type { UserSettings } from "@shared/schema"
import {
  User,
  Settings,
  Palette,
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
const OPENROUTER_QUICK_PICKS = [
  { id: 'deepseek/deepseek-chat', label: 'DeepSeek Chat' },
  { id: 'deepseek/deepseek-r1', label: 'DeepSeek R1' },
  { id: 'qwen/qwen-2.5-72b-instruct', label: 'Qwen 2.5' },
];

function useLlmApiKeys(open: boolean) {
  const [hasAnthropicKey, setHasAnthropicKey] = useState(false);
  const [hasOpenrouterKey, setHasOpenrouterKey] = useState(false);
  const [selectedModel, setSelectedModel] = useState('deepseek/deepseek-chat-v3-5');

  const [provider, setProvider] = useState<'default' | 'anthropic' | 'openrouter'>('default');
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
        if (d.selected_model) setSelectedModel(d.selected_model);
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
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      setHasAnthropicKey(true); setAnthropicInput('');
      setStatusMsg('Anthropic key saved — your chats use your own quota.');
    } catch (err: any) { setIsError(true); setStatusMsg(err.message); }
    finally { setSaving(false); }
  }, [anthropicInput]);

  const saveOpenrouterKey = useCallback(async () => {
    if (!openrouterInput.trim()) { setIsError(true); setStatusMsg('Paste your OpenRouter API key first.'); return; }
    setSaving(true); setStatusMsg(''); setIsError(false);
    try {
      const r = await fetch('/api/user/llm-api-keys', {
        method: 'PATCH', credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ provider: 'openrouter', key: openrouterInput.trim(), selected_model: selectedModel }),
      });
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      setHasOpenrouterKey(true); setOpenrouterInput('');
      setStatusMsg(`OpenRouter key saved — chats will use ${selectedModel}.`);
    } catch (err: any) { setIsError(true); setStatusMsg(err.message); }
    finally { setSaving(false); }
  }, [openrouterInput, selectedModel]);

  const saveModelOnly = useCallback(async () => {
    setSaving(true); setStatusMsg(''); setIsError(false);
    try {
      const r = await fetch('/api/user/llm-api-keys', {
        method: 'PATCH', credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ selected_model: selectedModel }),
      });
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      setStatusMsg(`Model updated to ${selectedModel}.`);
    } catch (err: any) { setIsError(true); setStatusMsg(err.message); }
    finally { setSaving(false); }
  }, [selectedModel]);

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
}

export function SettingsDialog({ open, onOpenChange }: SettingsDialogProps) {
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
  }

  const resetToDefaults = () => {
    const defaultSettings = userSettingsService.resetToDefaults()
    setSettings(defaultSettings)
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
      <DialogContent className="max-w-2xl w-[95vw] max-h-[90vh] p-0">
        <DialogHeader className="p-6 pb-0">
          <DialogTitle className="flex items-center gap-2">
            <Key className="w-5 h-5" />
            API Keys
          </DialogTitle>
        </DialogHeader>

        {/* Only the API Keys section is shown — other settings tabs are commented out until needed */}
        <div className="flex flex-1 overflow-hidden">
          <Tabs value={activeTab} onValueChange={setActiveTab} className="flex flex-1" orientation="vertical">
            {/* Settings Navigation — hidden on mobile since only API Keys tab exists */}
            <div className="hidden sm:block w-48 border-r bg-muted/50 p-4">
              <TabsList className="grid w-full grid-cols-1 h-auto gap-1 bg-transparent">
                {/* Other settings tabs commented out — only API Keys needed for now
                <TabsTrigger value="profile" ...>Profile</TabsTrigger>
                <TabsTrigger value="general" ...>General</TabsTrigger>
                <TabsTrigger value="appearance" ...>Appearance</TabsTrigger>
                <TabsTrigger value="chat" ...>Chat</TabsTrigger>
                <TabsTrigger value="data" ...>Data</TabsTrigger>
                <TabsTrigger value="notifications" ...>Notifications</TabsTrigger>
                <TabsTrigger value="privacy" ...>Privacy</TabsTrigger>
                <TabsTrigger value="security" ...>Security</TabsTrigger>
                <TabsTrigger value="advanced" ...>Advanced</TabsTrigger>
                */}
                <TabsTrigger value="api-keys" className="justify-start gap-2 p-3" data-testid="tab-api-keys">
                  <Key className="w-4 h-4" />
                  API Keys
                </TabsTrigger>
              </TabsList>

              {/* Quick Actions and Help sections commented out — not needed for API keys only view */}
            </div>

            {/* Settings Content */}
            <ScrollArea className="flex-1 p-6">
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
                        <Label htmlFor="language">Language</Label>
                        <Select value={settings.language} onValueChange={(value: any) => updateSetting('language', value)}>
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

              {/* Appearance Tab */}
              <TabsContent value="appearance" className="space-y-6 m-0">
                <div>
                  <h3 className="text-lg font-semibold mb-4">Appearance</h3>
                  
                  <Card>
                    <CardHeader>
                      <CardTitle>Theme</CardTitle>
                      <CardDescription>
                        Choose your preferred appearance
                      </CardDescription>
                    </CardHeader>
                    <CardContent>
                      <div className="space-y-2">
                        <Label htmlFor="theme">Theme</Label>
                        <Select value={settings.theme} onValueChange={(value: any) => updateSetting('theme', value)}>
                          <SelectTrigger data-testid="select-theme">
                            <SelectValue />
                          </SelectTrigger>
                          <SelectContent>
                            <SelectItem value="system">System</SelectItem>
                            <SelectItem value="light">Light</SelectItem>
                            <SelectItem value="dark">Dark</SelectItem>
                          </SelectContent>
                        </Select>
                      </div>
                    </CardContent>
                  </Card>
                </div>
              </TabsContent>

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
                            Create a read-only IAM user with <code className="bg-muted px-1 rounded text-[11px]">s3:GetObject</code> and <code className="bg-muted px-1 rounded text-[11px]">s3:ListBucket</code> on your data bucket.
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

              {/* API Keys Tab */}
              <TabsContent value="api-keys" className="space-y-6 m-0" data-testid="tab-content-api-keys">
                <div>
                  <h3 className="text-lg font-semibold mb-1">API Keys</h3>
                  <p className="text-xs text-muted-foreground mb-4">
                    Personal keys for connecting BioMate to external surfaces (Slack, Feishu, WeChat, MCP clients)
                    via biomate-connector. Send the key as <code className="bg-muted px-1 rounded text-[11px]">Authorization: Bearer &lt;key&gt;</code>.
                    Requests authenticate as <span className="font-medium">you</span> — your runs, quota, and history.
                  </p>

                  {/* Freshly created key — shown once */}
                  {apiKeysState.freshKey && (
                    <Card className="mb-4 border-green-500/40" data-testid="fresh-api-key-card">
                      <CardHeader className="pb-2">
                        <CardTitle className="text-sm font-medium flex items-center gap-2">
                          <CheckCircle2 className="h-4 w-4 text-green-600" />
                          New API key created
                        </CardTitle>
                        <CardDescription className="text-xs">
                          Copy it now — for your security it will <span className="font-medium">not be shown again</span>.
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
                            {apiKeysState.copied ? 'Copied' : 'Copy'}
                          </Button>
                          <Button size="sm" variant="ghost" className="h-8 text-xs shrink-0" onClick={apiKeysState.dismissFresh} data-testid="button-dismiss-fresh-key">
                            Done
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
                          <Label htmlFor="api-key-name" className="text-xs">Name (optional)</Label>
                          <Input
                            id="api-key-name"
                            placeholder="e.g. Feishu bot, Slack prod"
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
                          Generate key
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
                        <Loader2 className="h-3.5 w-3.5 animate-spin" /> Loading…
                      </div>
                    )}
                    {!apiKeysState.loading && apiKeysState.keys.length === 0 && (
                      <p className="text-xs text-muted-foreground p-2">No API keys yet.</p>
                    )}
                    {apiKeysState.keys.map((k) => (
                      <div
                        key={k.id}
                        className="flex items-center justify-between gap-3 rounded border p-3"
                        data-testid={`api-key-row-${k.id}`}
                      >
                        <div className="min-w-0">
                          <div className="flex items-center gap-2">
                            <span className="text-sm font-medium truncate">{k.name || 'Unnamed key'}</span>
                            {k.revokedAt
                              ? <Badge variant="secondary" className="text-[10px]">Revoked</Badge>
                              : <Badge variant="secondary" className="text-[10px] gap-1"><CheckCircle2 className="h-3 w-3 text-green-600" />Active</Badge>}
                          </div>
                          <div className="text-[11px] text-muted-foreground font-mono mt-0.5">{k.keyPrefix}</div>
                          <div className="text-[11px] text-muted-foreground mt-0.5">
                            Created {new Date(k.createdAt).toLocaleDateString()}
                            {k.lastUsedAt ? ` · last used ${new Date(k.lastUsedAt).toLocaleDateString()}` : ' · never used'}
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
                            <Trash2 className="h-3.5 w-3.5" /> Revoke
                          </Button>
                        )}
                      </div>
                    ))}
                  </div>
                </div>

                {/* ── LLM Provider selection ───────────────────────────── */}
                <Separator />
                <div>
                  <h3 className="text-lg font-semibold mb-1">LLM Provider</h3>
                  <p className="text-xs text-muted-foreground mb-4">
                    Choose which AI model powers your BioMate chats. The default uses BioMate's shared Claude quota
                    and supports full workflow execution. OpenRouter lets you use economic models (DeepSeek, Qwen, Llama)
                    with your own key — keys are stored encrypted and never returned to the browser.
                  </p>

                  {/* Provider radio group */}
                  <div className="space-y-2 mb-4">
                    {([
                      { value: 'default', label: 'BioMate Default', desc: 'Claude Sonnet — workflow execution, no key needed' },
                      { value: 'openrouter', label: 'OpenRouter', desc: '200+ models including DeepSeek, Qwen, Llama · bring your own key' },
                      { value: 'anthropic', label: 'Anthropic (BYOK)', desc: 'Your own Anthropic key and quota' },
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
                          <Label className="text-xs">Model <span className="text-muted-foreground font-normal">(any slug from openrouter.ai/models)</span></Label>
                          <Input
                            className="font-mono text-xs h-8"
                            placeholder="e.g. deepseek/deepseek-chat"
                            value={llmKeys.selectedModel}
                            onChange={e => llmKeys.setSelectedModel(e.target.value)}
                            data-testid="input-llm-model"
                          />
                          <div className="flex gap-1.5 flex-wrap">
                            {OPENROUTER_QUICK_PICKS.map(m => (
                              <button key={m.id} type="button"
                                className="text-xs px-2 py-0.5 rounded border border-border hover:bg-accent transition-colors"
                                onClick={() => llmKeys.setSelectedModel(m.id)}>
                                {m.label}
                              </button>
                            ))}
                          </div>
                        </div>
                        {/* API key input */}
                        {llmKeys.hasOpenrouterKey ? (
                          <div className="flex items-center justify-between gap-3 rounded-md bg-green-500/10 px-3 py-2">
                            <div className="flex items-center gap-2 text-xs text-green-700">
                              <CheckCircle2 className="h-3.5 w-3.5 shrink-0" />
                              <span>OpenRouter key saved</span>
                            </div>
                            <div className="flex items-center gap-1.5">
                              <Button size="sm" variant="outline" className="h-7 text-xs gap-1"
                                onClick={llmKeys.saveModelOnly} disabled={llmKeys.saving}>
                                {llmKeys.saving ? <Loader2 className="h-3 w-3 animate-spin" /> : null}
                                Update model
                              </Button>
                              <Button size="sm" variant="ghost" className="h-7 text-xs text-destructive hover:text-destructive gap-1"
                                onClick={() => llmKeys.removeProvider('openrouter')} disabled={llmKeys.removing}
                                data-testid="button-remove-openrouter-key">
                                {llmKeys.removing ? <Loader2 className="h-3 w-3 animate-spin" /> : <Trash2 className="h-3.5 w-3.5" />}
                                Remove
                              </Button>
                            </div>
                          </div>
                        ) : (
                          <div className="space-y-1.5">
                            <Label htmlFor="openrouter-api-key" className="text-xs">OpenRouter API Key</Label>
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
                                Save key
                              </Button>
                            </div>
                            <p className="text-xs text-muted-foreground">
                              Get a key at <span className="font-mono">openrouter.ai</span> — free tier available.
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
                              <span>Anthropic key saved — chats use your quota</span>
                            </div>
                            <Button size="sm" variant="ghost"
                              className="h-7 text-xs text-destructive hover:text-destructive gap-1 shrink-0"
                              onClick={() => llmKeys.removeProvider('anthropic')} disabled={llmKeys.removing}
                              data-testid="button-remove-llm-key">
                              {llmKeys.removing ? <Loader2 className="h-3 w-3 animate-spin" /> : <Trash2 className="h-3.5 w-3.5" />}
                              Remove
                            </Button>
                          </div>
                        ) : (
                          <div className="space-y-1.5">
                            <Label htmlFor="anthropic-api-key" className="text-xs">Anthropic API Key</Label>
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
                                Save key
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
            </ScrollArea>
          </Tabs>
        </div>
      </DialogContent>
    </Dialog>
  )
}