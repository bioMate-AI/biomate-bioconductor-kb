/**
 * McpServerForm — the REAL connect surface for a user's OWN remote MCP server.
 *
 * BioMate can expose an MCP server; this form lets a user register THEIR remote
 * MCP server so its tools become callable by the BioMate agent in chat. Backed by
 * real backend endpoints (built concurrently):
 *
 *   POST   /api/mcp/servers      → register + discover tools
 *   GET    /api/mcp/servers      → list registered servers (with discovered tools)
 *   DELETE /api/mcp/servers/:id   → remove
 *
 * MVP is REMOTE servers only (SSE / HTTP) — stdio (local command) is deferred
 * because launching an arbitrary user command is an RCE surface. The form says so.
 * An auth header, if supplied, is encrypted at rest and never rendered back.
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
import { Loader2, Trash2, Server } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { ResidencyBadge } from './connector-residency';

type Transport = 'sse' | 'http';

// A registered server as the LIST endpoint returns it. `tools` is the set of tool
// NAMES the backend discovered via the MCP `tools/list` handshake; the auth header
// value is never returned (only whether one is set).
interface McpServer {
  id: string;
  name: string;
  transport: Transport;
  url: string;
  tools?: string[];
  hasAuth?: boolean;
}

interface DraftServer {
  name: string;
  transport: Transport;
  url: string;
  authHeader: string;
}

const EMPTY_DRAFT: DraftServer = { name: '', transport: 'sse', url: '', authHeader: '' };

export function McpServerForm() {
  const { toast } = useToast();
  const [draft, setDraft] = useState<DraftServer>(EMPTY_DRAFT);
  const [adding, setAdding] = useState(false);
  const [servers, setServers] = useState<McpServer[]>([]);
  const [loadingList, setLoadingList] = useState(false);

  const update = (field: keyof DraftServer) =>
    (e: React.ChangeEvent<HTMLInputElement>) =>
      setDraft(prev => ({ ...prev, [field]: e.target.value }));

  const refresh = useCallback(async () => {
    setLoadingList(true);
    try {
      const res = await fetch('/api/mcp/servers', { credentials: 'include' });
      if (!res.ok) throw new Error(`list failed (${res.status})`);
      const data = await res.json();
      setServers(Array.isArray(data) ? data : (data.servers ?? []));
    } catch {
      // Endpoint may not exist yet in this working tree — degrade to empty list.
      setServers([]);
    } finally {
      setLoadingList(false);
    }
  }, []);

  useEffect(() => { refresh(); }, [refresh]);

  const canSubmit = draft.name.trim() && draft.url.trim();

  const add = async () => {
    setAdding(true);
    try {
      const res = await fetch('/api/mcp/servers', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          name: draft.name.trim(),
          transport: draft.transport,
          url: draft.url.trim(),
          authHeader: draft.authHeader.trim() || undefined,
        }),
      });
      const body = await res.json().catch(() => ({}));
      if (!res.ok || body.success === false) {
        throw new Error(body.error || body.message || `Registration failed (${res.status}).`);
      }
      const toolCount = Array.isArray(body.tools) ? body.tools.length : undefined;
      toast({
        title: 'MCP server added',
        description: toolCount !== undefined
          ? `${draft.name} — discovered ${toolCount} tool${toolCount === 1 ? '' : 's'}.`
          : `${draft.name} registered.`,
      });
      setDraft(EMPTY_DRAFT);
      await refresh();
    } catch (e) {
      toast({
        title: 'Could not add MCP server',
        description: e instanceof Error ? e.message : 'Unknown error',
        variant: 'destructive',
      });
    } finally {
      setAdding(false);
    }
  };

  const remove = async (server: McpServer) => {
    try {
      const res = await fetch(`/api/mcp/servers/${encodeURIComponent(server.id)}`, {
        method: 'DELETE',
        credentials: 'include',
      });
      if (!res.ok) throw new Error(`Delete failed (${res.status}).`);
      toast({ title: 'MCP server removed', description: server.name });
      await refresh();
    } catch (e) {
      toast({
        title: 'Could not remove MCP server',
        description: e instanceof Error ? e.message : 'Unknown error',
        variant: 'destructive',
      });
    }
  };

  return (
    <div className="space-y-4" data-testid="mcp-section">
      <Card data-testid="mcp-server-form">
        <CardHeader className="pb-3">
          <CardTitle className="text-sm font-medium flex items-center gap-2">
            <Server className="h-4 w-4" />
            Add an MCP server
            <ResidencyBadge residency="cloud" />
          </CardTitle>
          <CardDescription className="text-xs mt-1">
            Register <strong>your own</strong> remote MCP server so its tools become callable by
            the BioMate agent in chat. <strong>Remote servers only</strong> (SSE / HTTP) — local
            stdio commands are deferred. An auth header, if provided, is encrypted at rest.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label htmlFor="mcp-name" className="text-xs">Server name</Label>
              <Input
                id="mcp-name"
                placeholder="Lab tools MCP"
                value={draft.name}
                onChange={update('name')}
                data-testid="mcp-input-name"
                className="text-xs h-8"
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="mcp-transport" className="text-xs">Transport</Label>
              <Select value={draft.transport} onValueChange={(v: Transport) => setDraft(prev => ({ ...prev, transport: v }))}>
                <SelectTrigger id="mcp-transport" className="h-8 text-xs" data-testid="mcp-input-transport">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="sse">SSE</SelectItem>
                  <SelectItem value="http">HTTP (streamable)</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5 col-span-2">
              <Label htmlFor="mcp-url" className="text-xs">Server URL</Label>
              <Input
                id="mcp-url"
                placeholder="https://mcp.example.org/sse"
                value={draft.url}
                onChange={update('url')}
                data-testid="mcp-input-url"
                className="font-mono text-xs h-8"
              />
            </div>
            <div className="space-y-1.5 col-span-2">
              <Label htmlFor="mcp-auth" className="text-xs">Auth header (optional)</Label>
              <Input
                id="mcp-auth"
                type="password"
                placeholder="Authorization: Bearer …"
                value={draft.authHeader}
                onChange={update('authHeader')}
                autoComplete="new-password"
                data-testid="mcp-input-auth"
                className="font-mono text-xs h-8"
              />
            </div>
          </div>

          <div className="flex gap-2 pt-1">
            <Button
              size="sm"
              className="h-7 text-xs gap-1.5"
              onClick={add}
              disabled={!canSubmit || adding}
              data-testid="mcp-add-server"
            >
              {adding && <Loader2 className="h-3 w-3 animate-spin" />}
              Add server
            </Button>
          </div>
        </CardContent>
      </Card>

      {/* Registered servers list */}
      <Card data-testid="mcp-servers-list">
        <CardHeader className="pb-3">
          <CardTitle className="text-sm font-medium">Your MCP servers</CardTitle>
          <CardDescription className="text-xs mt-1">
            {loadingList
              ? 'Loading…'
              : servers.length === 0
                ? 'No MCP servers registered yet.'
                : `${servers.length} server${servers.length === 1 ? '' : 's'} — their tools are available to BioMate chat.`}
          </CardDescription>
        </CardHeader>
        {servers.length > 0 && (
          <CardContent className="space-y-2">
            {servers.map(server => (
              <div
                key={server.id}
                data-testid={`mcp-server-${server.id}`}
                className="rounded border border-border p-2.5"
              >
                <div className="flex items-center justify-between gap-3">
                  <div className="min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="text-sm font-medium truncate">{server.name}</span>
                      <Badge variant="secondary" className="text-[10px] font-normal uppercase">{server.transport}</Badge>
                      {server.hasAuth && (
                        <Badge variant="secondary" className="text-[10px] font-normal">auth set</Badge>
                      )}
                    </div>
                    <div className="text-[11px] text-muted-foreground font-mono truncate mt-0.5">{server.url}</div>
                  </div>
                  <Button
                    variant="ghost"
                    size="sm"
                    className="h-7 text-xs text-muted-foreground shrink-0"
                    onClick={() => remove(server)}
                    data-testid={`mcp-delete-${server.id}`}
                  >
                    <Trash2 className="h-3.5 w-3.5" />
                  </Button>
                </div>
                {/* Discovered tools — honest empty state when the handshake found none. */}
                <div className="flex flex-wrap gap-1 mt-2" data-testid={`mcp-tools-${server.id}`}>
                  {server.tools && server.tools.length > 0
                    ? server.tools.map(t => (
                        <Badge key={t} variant="outline" className="text-[10px] font-mono font-normal">{t}</Badge>
                      ))
                    : <span className="text-[11px] text-muted-foreground italic">no tools discovered</span>}
                </div>
              </div>
            ))}
          </CardContent>
        )}
      </Card>
    </div>
  );
}
