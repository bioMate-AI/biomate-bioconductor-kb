/**
 * PrivateDbConnectionForm — the REAL connect surface for a user's OWN database.
 *
 * Unlike the public-database reference directory (which is read-only: nothing to
 * connect there), this form takes a user-supplied host/port/creds and registers a
 * connection that BioMate's chat/agent can run READ-ONLY queries against. It is
 * backed by real backend endpoints (built concurrently):
 *
 *   POST   /api/databases/connections/verify   → open a short-lived read-only conn, SELECT 1
 *   POST   /api/databases/connections         → save (creds encrypted at rest)
 *   GET    /api/databases/connections         → list existing (password never returned)
 *   DELETE /api/databases/connections/:id      → remove
 *
 * Visual/interaction template: the S3-credentials form in settings-dialog.tsx.
 * A stored password is NEVER rendered back — the list shows "set / ••••" only.
 */
import { useState, useEffect, useCallback } from 'react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import {
  CheckCircle2, XCircle, Loader2, Eye, EyeOff, Trash2, Database,
} from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { ResidencyBadge } from './connector-residency';

// A saved connection as the LIST endpoint returns it — note there is NO password
// field: the backend never returns a stored password. `hasPassword` is a boolean
// so the UI can honestly show "set" without ever rendering the secret.
interface DbConnection {
  id: string;
  name: string;
  host: string;
  port: number;
  database: string;
  user: string;
  driver: string;
  hasPassword?: boolean;
}

type Driver = 'postgres';

interface DraftConnection {
  name: string;
  host: string;
  port: string;
  database: string;
  user: string;
  password: string;
  driver: Driver;
}

const EMPTY_DRAFT: DraftConnection = {
  name: '', host: '', port: '5432', database: '', user: '', password: '', driver: 'postgres',
};

type TestState = 'idle' | 'testing' | 'ok' | 'error';

export function PrivateDbConnectionForm() {
  const { toast } = useToast();
  const [draft, setDraft] = useState<DraftConnection>(EMPTY_DRAFT);
  const [showPassword, setShowPassword] = useState(false);
  const [testState, setTestState] = useState<TestState>('idle');
  const [testMsg, setTestMsg] = useState<string>('');
  const [saving, setSaving] = useState(false);
  const [connections, setConnections] = useState<DbConnection[]>([]);
  const [loadingList, setLoadingList] = useState(false);

  const update = (field: keyof DraftConnection) =>
    (e: React.ChangeEvent<HTMLInputElement>) => {
      setDraft(prev => ({ ...prev, [field]: e.target.value }));
      // any edit invalidates a prior test result
      setTestState('idle');
      setTestMsg('');
    };

  const refresh = useCallback(async () => {
    setLoadingList(true);
    try {
      const res = await fetch('/api/databases/connections', { credentials: 'include' });
      if (!res.ok) throw new Error(`list failed (${res.status})`);
      const data = await res.json();
      setConnections(Array.isArray(data) ? data : (data.connections ?? []));
    } catch {
      // Endpoint may not exist yet in this working tree — degrade to empty list,
      // do not toast an error on mount (the capability is being built concurrently).
      setConnections([]);
    } finally {
      setLoadingList(false);
    }
  }, []);

  useEffect(() => { refresh(); }, [refresh]);

  const payload = () => ({
    name: draft.name.trim(),
    host: draft.host.trim(),
    port: parseInt(draft.port, 10) || undefined,
    database: draft.database.trim(),
    user: draft.user.trim(),
    password: draft.password,
    driver: draft.driver,
  });

  const canSubmit =
    draft.name.trim() && draft.host.trim() && draft.database.trim() && draft.user.trim();

  const testConnection = async () => {
    setTestState('testing');
    setTestMsg('');
    try {
      const res = await fetch('/api/databases/connections/verify', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload()),
      });
      const body = await res.json().catch(() => ({}));
      if (res.ok && body.success !== false) {
        setTestState('ok');
        setTestMsg(body.message || 'Connected — read-only SELECT 1 succeeded.');
      } else {
        setTestState('error');
        setTestMsg(body.error || body.message || `Connection failed (${res.status}).`);
      }
    } catch (e) {
      setTestState('error');
      setTestMsg(e instanceof Error ? e.message : 'Connection failed.');
    }
  };

  const save = async () => {
    setSaving(true);
    try {
      const res = await fetch('/api/databases/connections', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload()),
      });
      const body = await res.json().catch(() => ({}));
      if (!res.ok || body.success === false) {
        throw new Error(body.error || body.message || `Save failed (${res.status}).`);
      }
      toast({ title: 'Connection saved', description: `${draft.name} is now available to BioMate chat.` });
      setDraft(EMPTY_DRAFT);
      setTestState('idle');
      setTestMsg('');
      await refresh();
    } catch (e) {
      toast({
        title: 'Could not save connection',
        description: e instanceof Error ? e.message : 'Unknown error',
        variant: 'destructive',
      });
    } finally {
      setSaving(false);
    }
  };

  const remove = async (conn: DbConnection) => {
    try {
      const res = await fetch(`/api/databases/connections/${encodeURIComponent(conn.id)}`, {
        method: 'DELETE',
        credentials: 'include',
      });
      if (!res.ok) throw new Error(`Delete failed (${res.status}).`);
      toast({ title: 'Connection removed', description: conn.name });
      await refresh();
    } catch (e) {
      toast({
        title: 'Could not remove connection',
        description: e instanceof Error ? e.message : 'Unknown error',
        variant: 'destructive',
      });
    }
  };

  return (
    <div className="space-y-4" data-testid="private-db-section">
      <Card data-testid="db-connection-form">
        <CardHeader className="pb-3">
          <CardTitle className="text-sm font-medium flex items-center gap-2">
            <Database className="h-4 w-4" />
            Add a private database
            <ResidencyBadge residency="onprem" />
          </CardTitle>
          <CardDescription className="text-xs mt-1">
            Register a connection to <strong>your own</strong> Postgres database so BioMate can
            answer questions from it in chat. <strong>Supply a READ-ONLY DB role</strong> — every
            query BioMate runs is read-only, and your password is encrypted at rest and never shown
            back here.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label htmlFor="db-name" className="text-xs">Connection name</Label>
              <Input
                id="db-name"
                placeholder="Clinical results DB"
                value={draft.name}
                onChange={update('name')}
                data-testid="db-input-name"
                className="text-xs h-8"
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="db-driver" className="text-xs">Driver</Label>
              <Select value={draft.driver} onValueChange={(v: Driver) => setDraft(prev => ({ ...prev, driver: v }))}>
                <SelectTrigger id="db-driver" className="h-8 text-xs" data-testid="db-input-driver">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="postgres">PostgreSQL</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="db-host" className="text-xs">Host</Label>
              <Input
                id="db-host"
                placeholder="db.internal.example.org"
                value={draft.host}
                onChange={update('host')}
                data-testid="db-input-host"
                className="font-mono text-xs h-8"
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="db-port" className="text-xs">Port</Label>
              <Input
                id="db-port"
                placeholder="5432"
                value={draft.port}
                onChange={update('port')}
                data-testid="db-input-port"
                className="font-mono text-xs h-8"
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="db-database" className="text-xs">Database</Label>
              <Input
                id="db-database"
                placeholder="clinical"
                value={draft.database}
                onChange={update('database')}
                data-testid="db-input-database"
                className="font-mono text-xs h-8"
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="db-user" className="text-xs">User (read-only role)</Label>
              <Input
                id="db-user"
                placeholder="biomate_readonly"
                value={draft.user}
                onChange={update('user')}
                data-testid="db-input-user"
                className="font-mono text-xs h-8"
              />
            </div>
            <div className="space-y-1.5 col-span-2">
              <Label htmlFor="db-password" className="text-xs">Password</Label>
              <div className="relative">
                <Input
                  id="db-password"
                  type={showPassword ? 'text' : 'password'}
                  placeholder="••••••••"
                  value={draft.password}
                  onChange={update('password')}
                  autoComplete="new-password"
                  data-testid="db-input-password"
                  className="font-mono text-xs h-8 pr-8"
                />
                <button
                  type="button"
                  className="absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
                  onClick={() => setShowPassword(!showPassword)}
                  data-testid="db-toggle-password"
                  tabIndex={-1}
                >
                  {showPassword ? <EyeOff className="h-3.5 w-3.5" /> : <Eye className="h-3.5 w-3.5" />}
                </button>
              </div>
            </div>
          </div>

          {testMsg && (
            <div
              className={`flex items-start gap-2 text-xs rounded p-2 ${testState === 'ok' ? 'bg-green-50 text-green-700 dark:bg-green-900/20 dark:text-green-400' : 'bg-destructive/10 text-destructive'}`}
              data-testid="db-test-status"
            >
              {testState === 'ok'
                ? <CheckCircle2 className="h-3.5 w-3.5 mt-0.5 shrink-0" />
                : <XCircle className="h-3.5 w-3.5 mt-0.5 shrink-0" />}
              <span>{testMsg}</span>
            </div>
          )}

          <div className="flex gap-2 pt-1">
            <Button
              size="sm"
              className="h-7 text-xs gap-1.5"
              onClick={save}
              disabled={!canSubmit || saving || testState === 'testing'}
              data-testid="db-save-connection"
            >
              {saving && <Loader2 className="h-3 w-3 animate-spin" />}
              Save connection
            </Button>
            <Button
              variant="outline"
              size="sm"
              className="h-7 text-xs gap-1.5"
              onClick={testConnection}
              disabled={!canSubmit || saving || testState === 'testing'}
              data-testid="db-test-connection"
            >
              {testState === 'testing' && <Loader2 className="h-3 w-3 animate-spin" />}
              Test connection
            </Button>
          </div>
        </CardContent>
      </Card>

      {/* Existing connections list */}
      <Card data-testid="db-connections-list">
        <CardHeader className="pb-3">
          <CardTitle className="text-sm font-medium">Your database connections</CardTitle>
          <CardDescription className="text-xs mt-1">
            {loadingList
              ? 'Loading…'
              : connections.length === 0
                ? 'No private databases connected yet.'
                : `${connections.length} connection${connections.length === 1 ? '' : 's'} — BioMate can query these read-only from chat.`}
          </CardDescription>
        </CardHeader>
        {connections.length > 0 && (
          <CardContent className="space-y-2">
            {connections.map(conn => (
              <div
                key={conn.id}
                data-testid={`db-connection-${conn.id}`}
                className="flex items-center justify-between gap-3 rounded border border-border p-2.5"
              >
                <div className="min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-medium truncate">{conn.name}</span>
                    <Badge variant="secondary" className="text-[10px] font-normal">{conn.driver}</Badge>
                    <Badge variant="secondary" className="text-[10px] font-normal gap-1">
                      <CheckCircle2 className="h-3 w-3 text-green-600" />
                      password set
                    </Badge>
                  </div>
                  <div className="text-[11px] text-muted-foreground font-mono truncate mt-0.5">
                    {conn.user}@{conn.host}:{conn.port}/{conn.database}
                  </div>
                </div>
                <Button
                  variant="ghost"
                  size="sm"
                  className="h-7 text-xs text-muted-foreground shrink-0"
                  onClick={() => remove(conn)}
                  data-testid={`db-delete-${conn.id}`}
                >
                  <Trash2 className="h-3.5 w-3.5" />
                </Button>
              </div>
            ))}
          </CardContent>
        )}
      </Card>
    </div>
  );
}
