/**
 * /workspaces — UI for the LTM project framework.
 *
 * "Workspace" is the user-facing label; the backend table is `projects`
 * (`ltm-schema.ts`). The legacy /projects route (pages/projects.tsx)
 * targets a different concept (project-service, IND-related) — kept
 * separate to avoid disruption.
 *
 * List active workspaces with a status indicator + active selector.
 * Create / rename / archive / delete. Setting "active" persists the
 * selection to localStorage; the chat-stream context picks it up and
 * threads projectId into every chat request.
 *
 * Policy (docs/20260612_DATASET_STORAGE_AND_SESSION_BOUNDARIES.md):
 * a chat can have NO workspace, so "Clear active workspace" is a
 * first-class action (not just "switch to another").
 */
import { useState } from "react"
import { useLocation } from "wouter"
import { useActiveProject } from "@/contexts/active-project-context"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Textarea } from "@/components/ui/textarea"
import { Badge } from "@/components/ui/badge"
import { FolderOpen, Plus, Archive, Trash2, Edit2, Check, X } from "lucide-react"

export default function WorkspacesPage() {
  const [, setLocation] = useLocation()
  const {
    projects, activeProjectId, loading, setActiveProjectId,
    createProject, archiveProject, deleteProject, renameProject,
  } = useActiveProject()

  const [createOpen, setCreateOpen] = useState(false)
  const [createName, setCreateName] = useState("")
  const [createDesc, setCreateDesc] = useState("")
  const [createDomain, setCreateDomain] = useState("")
  const [busy, setBusy] = useState(false)
  const [editingId, setEditingId] = useState<string | null>(null)
  const [editingName, setEditingName] = useState("")
  const [error, setError] = useState<string | null>(null)

  async function handleCreate() {
    if (!createName.trim()) return
    setBusy(true); setError(null)
    try {
      const p = await createProject(createName.trim(), {
        description: createDesc.trim() || undefined,
        primaryDomain: createDomain.trim() || undefined,
      })
      setActiveProjectId(p.id)
      setCreateOpen(false); setCreateName(""); setCreateDesc(""); setCreateDomain("")
    } catch (e: any) {
      setError(e?.message ?? "Failed to create workspace")
    } finally { setBusy(false) }
  }

  async function handleArchive(id: string) {
    setBusy(true)
    try { await archiveProject(id) } catch (e: any) { setError(e?.message) } finally { setBusy(false) }
  }

  async function handleDelete(id: string) {
    if (!confirm("Delete this workspace? Episodes and learned procedures will be removed. Chat sessions are kept (just unlinked).")) return
    setBusy(true)
    try { await deleteProject(id) } catch (e: any) { setError(e?.message) } finally { setBusy(false) }
  }

  async function handleRename(id: string) {
    if (!editingName.trim()) return
    setBusy(true)
    try { await renameProject(id, editingName.trim()); setEditingId(null) }
    catch (e: any) { setError(e?.message) }
    finally { setBusy(false) }
  }

  return (
    <div className="container mx-auto px-4 py-8 max-w-5xl">
      <header className="flex items-start justify-between mb-6">
        <div>
          <h1 className="text-2xl font-semibold flex items-center gap-2">
            <FolderOpen className="h-6 w-6" /> Workspaces
          </h1>
          <p className="text-sm text-muted-foreground mt-1 max-w-2xl">
            Group related chats, runs, and memory. The active workspace scopes
            procedures, episodes, knowledge, and dataset recovery across
            sessions. A chat can also have no workspace — that's the default.
          </p>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" onClick={() => setLocation("/")}>Back to chat</Button>
          <Button data-testid="button-new-workspace" onClick={() => setCreateOpen(true)}>
            <Plus className="h-4 w-4 mr-1" /> New workspace
          </Button>
        </div>
      </header>

      <Card className="mb-4" data-testid="active-workspace-card">
        <CardHeader>
          <CardTitle className="text-base">Active workspace</CardTitle>
        </CardHeader>
        <CardContent>
          {activeProjectId
            ? (<div className="flex items-center justify-between">
                <div className="text-sm">
                  <span className="font-medium" data-testid="active-workspace-name">
                    {projects.find(p => p.id === activeProjectId)?.name ?? "(unknown)"}
                  </span>
                  <span className="ml-2 text-xs text-muted-foreground">id={activeProjectId.slice(0, 8)}…</span>
                </div>
                <Button variant="ghost" size="sm" data-testid="button-clear-active" onClick={() => setActiveProjectId(null)}>
                  Clear (chat will be project-less)
                </Button>
              </div>)
            : (<div className="text-sm text-muted-foreground" data-testid="no-active-workspace">
                No active workspace. New chats will be project-less.
              </div>)}
        </CardContent>
      </Card>

      {error && (
        <div className="mb-4 rounded border border-red-300 bg-red-50 p-3 text-sm text-red-700">{error}</div>
      )}

      {createOpen && (
        <Card className="mb-4">
          <CardHeader><CardTitle className="text-base">New workspace</CardTitle></CardHeader>
          <CardContent className="space-y-3">
            <Input data-testid="input-new-workspace-name" placeholder="Name (required)"
              value={createName} onChange={e => setCreateName(e.target.value)} disabled={busy} />
            <Textarea data-testid="input-new-workspace-desc" placeholder="Description (optional)"
              value={createDesc} onChange={e => setCreateDesc(e.target.value)} disabled={busy} />
            <Input data-testid="input-new-workspace-domain" placeholder="Primary domain — transcriptomics, drug_discovery, etc. (optional)"
              value={createDomain} onChange={e => setCreateDomain(e.target.value)} disabled={busy} />
            <div className="flex gap-2">
              <Button data-testid="button-create-workspace-submit" onClick={handleCreate} disabled={busy || !createName.trim()}>
                Create + set active
              </Button>
              <Button variant="ghost" onClick={() => { setCreateOpen(false); setCreateName(""); setCreateDesc(""); setCreateDomain("") }}>Cancel</Button>
            </div>
          </CardContent>
        </Card>
      )}

      <div className="space-y-2" data-testid="workspace-list">
        {loading && projects.length === 0 && (
          <div className="text-sm text-muted-foreground py-8 text-center">Loading…</div>
        )}
        {!loading && projects.length === 0 && (
          <Card>
            <CardContent className="py-8 text-center text-sm text-muted-foreground" data-testid="workspace-list-empty">
              No workspaces yet. Use "New workspace" above to create one.
            </CardContent>
          </Card>
        )}
        {projects.map(p => (
          <Card key={p.id} data-testid={`workspace-row-${p.id}`}
            className={p.id === activeProjectId ? "border-primary" : ""}>
            <CardContent className="flex items-center justify-between p-4">
              <div className="flex-1 min-w-0">
                {editingId === p.id ? (
                  <div className="flex items-center gap-2">
                    <Input value={editingName} onChange={e => setEditingName(e.target.value)} disabled={busy}
                      data-testid={`input-rename-${p.id}`} />
                    <Button size="sm" variant="ghost" onClick={() => handleRename(p.id)} disabled={busy}>
                      <Check className="h-4 w-4" />
                    </Button>
                    <Button size="sm" variant="ghost" onClick={() => setEditingId(null)}>
                      <X className="h-4 w-4" />
                    </Button>
                  </div>
                ) : (
                  <>
                    <div className="font-medium" data-testid={`workspace-name-${p.id}`}>{p.name}</div>
                    {(p as any).description && <div className="text-xs text-muted-foreground mt-0.5">{(p as any).description}</div>}
                    {(p as any).primaryDomain && <Badge variant="outline" className="mt-1 text-xs">{(p as any).primaryDomain}</Badge>}
                  </>
                )}
              </div>
              <div className="flex items-center gap-1 ml-4">
                {p.id === activeProjectId
                  ? <Badge data-testid={`badge-active-${p.id}`}>Active</Badge>
                  : <Button variant="outline" size="sm" data-testid={`button-set-active-${p.id}`}
                      onClick={() => setActiveProjectId(p.id)}>Set active</Button>}
                <Button variant="ghost" size="sm" onClick={() => { setEditingId(p.id); setEditingName(p.name) }}
                  data-testid={`button-rename-${p.id}`}>
                  <Edit2 className="h-4 w-4" />
                </Button>
                <Button variant="ghost" size="sm" onClick={() => handleArchive(p.id)}
                  data-testid={`button-archive-${p.id}`}>
                  <Archive className="h-4 w-4" />
                </Button>
                <Button variant="ghost" size="sm" onClick={() => handleDelete(p.id)}
                  data-testid={`button-delete-${p.id}`}>
                  <Trash2 className="h-4 w-4 text-red-500" />
                </Button>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>

      <div className="mt-6 text-xs text-muted-foreground">
        Tip: cross-session dataset recovery only works within the same workspace.
      </div>
    </div>
  )
}
