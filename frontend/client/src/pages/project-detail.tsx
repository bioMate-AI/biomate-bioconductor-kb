import { useState, useEffect, useCallback } from "react"
import { useLocation } from "wouter"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Textarea } from "@/components/ui/textarea"
import { Input } from "@/components/ui/input"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog"
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import {
  ArrowLeft,
  MessageCircle,
  FileText,
  FlaskConical,
  Plus,
  Edit3,
  Save,
  X,
  Clock,
  Tag,
  CheckCircle2,
  XCircle,
  Loader2,
  Circle,
  ExternalLink,
  RefreshCw,
  MoreHorizontal,
  Archive,
  Trash2,
  Pencil,
} from "lucide-react"
import { projectService } from "@/lib/projects"
import { ProjectFileTree } from "@/components/project-file-tree"
import { NextflowWorkflowViewer } from "@/components/nextflow-workflow-viewer"
import type { Project } from "@shared/schema"
import { cn } from "@/lib/utils"

interface ProjectDetailPageProps {
  projectId: string
  onBack: () => void
  initialTab?: string
}

export default function ProjectDetailPage({ projectId, onBack, initialTab }: ProjectDetailPageProps) {
  const [, navigate] = useLocation()
  const [project, setProject] = useState<Project | null>(null)
  const [loadingProject, setLoadingProject] = useState(true)
  const [isEditingInstructions, setIsEditingInstructions] = useState(false)
  const [instructionsValue, setInstructionsValue] = useState("")
  const validTabs = ["chat", "files", "workflows"]
  const [activeTab, setActiveTab] = useState(validTabs.includes(initialTab || "") ? initialTab! : "files")

  const [sessions, setSessions] = useState<any[]>([])
  const [sessionsLoading, setSessionsLoading] = useState(false)

  const [runs, setRuns] = useState<any[]>([])
  const [runsLoading, setRunsLoading] = useState(false)
  const [selectedRunId, setSelectedRunId] = useState<string | null>(null)
  const [projectFiles, setProjectFiles] = useState<{ name: string; size?: number }[]>([])

  // Inline tag editing
  const [editingTags, setEditingTags] = useState<string[]>([])
  const [addingTag, setAddingTag] = useState(false)
  const [tagInput, setTagInput] = useState("")

  useEffect(() => {
    if (project) setEditingTags(project.tags || [])
  }, [project?.id]) // eslint-disable-line react-hooks/exhaustive-deps

  const removeTag = async (tag: string) => {
    if (!project) return
    const prev = editingTags
    const next = editingTags.filter(t => t !== tag)
    setEditingTags(next)
    try {
      const r = await fetch(`/api/projects/${project.id}`, {
        method: "PATCH", headers: { "Content-Type": "application/json" },
        credentials: "include", body: JSON.stringify({ tags: next }),
      })
      if (!r.ok) setEditingTags(prev)
    } catch { setEditingTags(prev) }
  }

  const addTag = async (tag: string) => {
    const trimmed = tag.trim()
    if (!project || !trimmed || editingTags.includes(trimmed)) { setAddingTag(false); setTagInput(""); return }
    const prev = editingTags
    const next = [...editingTags, trimmed]
    setEditingTags(next)
    setAddingTag(false)
    setTagInput("")
    try {
      const r = await fetch(`/api/projects/${project.id}`, {
        method: "PATCH", headers: { "Content-Type": "application/json" },
        credentials: "include", body: JSON.stringify({ tags: next }),
      })
      if (!r.ok) setEditingTags(prev)
    } catch { setEditingTags(prev) }
  }

  // Project lifecycle dialogs
  const [renameOpen, setRenameOpen] = useState(false)
  const [renameValue, setRenameValue] = useState("")
  const [archiveOpen, setArchiveOpen] = useState(false)
  const [deleteOpen, setDeleteOpen] = useState(false)
  const [actionLoading, setActionLoading] = useState(false)

  useEffect(() => {
    setLoadingProject(true)
    fetch(`/api/projects/${projectId}`, { credentials: "include" })
      .then(r => r.ok ? r.json() : null)
      .then(data => {
        const p = data?.project
        if (p) {
          setProject({
            ...p,
            tags: p.tags ?? [],
            documents: p.documents ?? [],
            progress: p.progress ?? 0,
            category: p.primaryDomain ?? p.category ?? null,
            instructions: p.researchGoal ?? p.research_goal ?? p.instructions ?? "",
            lastActivity: new Date(p.updatedAt ?? p.createdAt),
            createdAt: new Date(p.createdAt),
            updatedAt: new Date(p.updatedAt ?? p.createdAt),
          } as any)
          setInstructionsValue(p.researchGoal ?? p.research_goal ?? p.instructions ?? "")
        } else {
          const loc = projectService.getProject(projectId)
          if (loc) { setProject(loc); setInstructionsValue(loc.instructions || "") }
        }
      })
      .catch(() => {
        const loc = projectService.getProject(projectId)
        if (loc) { setProject(loc); setInstructionsValue(loc.instructions || "") }
      })
      .finally(() => setLoadingProject(false))
  }, [projectId])

  const loadSessions = useCallback(async () => {
    setSessionsLoading(true)
    try {
      const r = await fetch(`/api/projects/${projectId}/sessions`, { credentials: "include" })
      if (r.ok) setSessions((await r.json()).sessions ?? [])
    } catch { /* ignore */ }
    finally { setSessionsLoading(false) }
  }, [projectId])

  useEffect(() => { loadSessions() }, [loadSessions])

  const loadRuns = useCallback(async () => {
    setRunsLoading(true)
    try {
      const r = await fetch(`/api/workflows/runs?projectId=${projectId}&limit=50`, { credentials: "include" })
      const data = r.ok ? await r.json() : []
      setRuns(Array.isArray(data) ? data : [])
    } catch { setRuns([]) }
    finally { setRunsLoading(false) }
  }, [projectId])

  useEffect(() => { if (activeTab === "workflows") loadRuns() }, [activeTab, loadRuns])

  const handleSaveInstructions = async () => {
    if (!project) return
    try {
      const r = await fetch(`/api/projects/${project.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        credentials: "include",
        body: JSON.stringify({ researchGoal: instructionsValue.trim() || null }),
      })
      if (r.ok) {
        setProject(prev => prev ? { ...prev, instructions: instructionsValue.trim() } : prev)
        setIsEditingInstructions(false)
      }
    } catch { /* keep editing open */ }
  }

  const openChatWithProject = (sessionId?: string, prefilledMessage?: string) => {
    try { localStorage.setItem("biomate-active-project-id", projectId) } catch { /* ignore */ }
    let url = sessionId ? `/?session=${encodeURIComponent(sessionId)}` : "/"
    if (prefilledMessage && !sessionId) url += `?q=${encodeURIComponent(prefilledMessage)}`
    window.location.assign(url)
  }

  const handleAnalyzeClick = () => {
    let msg: string | undefined
    if (projectFiles.length > 0) {
      const fileList = projectFiles.map(f => `- ${f.name}`).join("\n")
      msg = `I've uploaded these files to my project:\n${fileList}\nPlease suggest the right workflow and run it.`
    }
    openChatWithProject(undefined, msg)
  }

  const handleRename = async () => {
    if (!project || !renameValue.trim()) return
    setActionLoading(true)
    try {
      const r = await fetch(`/api/projects/${project.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        credentials: "include",
        body: JSON.stringify({ name: renameValue.trim() }),
      })
      if (r.ok) {
        setProject(prev => prev ? { ...prev, name: renameValue.trim() } : prev)
        setRenameOpen(false)
      }
    } catch { /* keep open */ }
    finally { setActionLoading(false) }
  }

  const handleToggleStatus = async () => {
    if (!project) return
    const newStatus = project.status === "completed" ? "active" : "completed"
    try {
      const r = await fetch(`/api/projects/${project.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        credentials: "include",
        body: JSON.stringify({ status: newStatus }),
      })
      if (r.ok) setProject(prev => prev ? { ...prev, status: newStatus } : prev)
    } catch { /* ignore */ }
  }

  const handleArchive = async () => {
    if (!project) return
    setActionLoading(true)
    try {
      const r = await fetch(`/api/projects/${project.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        credentials: "include",
        body: JSON.stringify({ status: "archived" }),
      })
      if (r.ok) navigate("/projects")
    } catch { /* ignore */ }
    finally { setActionLoading(false) }
  }

  const handleDelete = async () => {
    if (!project) return
    setActionLoading(true)
    try {
      const r = await fetch(`/api/projects/${project.id}`, {
        method: "DELETE",
        credentials: "include",
      })
      if (r.ok) navigate("/projects")
    } catch { /* ignore */ }
    finally { setActionLoading(false) }
  }

  const relTime = (d?: string | Date | null) => {
    if (!d) return "—"
    const diff = Date.now() - new Date(d as any).getTime()
    const h = Math.floor(diff / 3_600_000)
    const days = Math.floor(diff / 86_400_000)
    if (h < 1) return "just now"
    if (h < 24) return `${h}h ago`
    if (days < 7) return `${days}d ago`
    return new Date(d as any).toLocaleDateString()
  }

  const statusIcon = (status: string) => {
    if (status === "completed") return <CheckCircle2 className="w-4 h-4 text-green-500 shrink-0" />
    if (status === "failed" || status === "errored") return <XCircle className="w-4 h-4 text-red-500 shrink-0" />
    if (status === "running") return <Loader2 className="w-4 h-4 text-blue-500 animate-spin shrink-0" />
    return <Circle className="w-4 h-4 text-muted-foreground shrink-0" />
  }

  if (loadingProject) {
    return (
      <div className="h-full flex items-center justify-center">
        <Loader2 className="w-6 h-6 animate-spin text-muted-foreground" />
      </div>
    )
  }

  if (!project) {
    return (
      <div className="h-full flex items-center justify-center">
        <div className="text-center">
          <h2 className="text-xl font-semibold mb-2">Project not found</h2>
          <Button onClick={onBack}><ArrowLeft className="w-4 h-4 mr-2" />Back to Projects</Button>
        </div>
      </div>
    )
  }

  return (
    <div className="h-full flex flex-col overflow-hidden">
      {/* Header */}
      <div className="border-b border-border px-6 py-4 shrink-0">
        <div className="flex items-center gap-3 mb-3">
          <Button variant="ghost" size="sm" onClick={onBack} data-testid="button-back-to-projects">
            <ArrowLeft className="w-4 h-4 mr-2" />All projects
          </Button>
        </div>
        <div className="flex items-start justify-between gap-4">
          <div className="min-w-0">
            <h1 className="text-2xl font-bold truncate">{project.name}</h1>
            {project.description && (
              <p className="text-muted-foreground text-sm mt-1 line-clamp-2">{project.description}</p>
            )}
            <div className="flex items-center gap-2 mt-2 flex-wrap">
              {project.category && <Badge variant="outline" className="text-xs">{project.category}</Badge>}
              <Badge variant="secondary" className={cn(
                "text-xs",
                project.status === "completed" && "bg-green-100 text-green-700",
                project.status === "archived" && "bg-gray-100 text-gray-600",
                project.status === "active" && "bg-blue-100 text-blue-700",
              )}>{project.status}</Badge>
              {editingTags.map(tag => (
                <span
                  key={tag}
                  className="inline-flex items-center gap-1 rounded-full border border-border bg-secondary text-secondary-foreground px-2 py-0.5 text-xs"
                >
                  <Tag className="w-3 h-3 opacity-60" />{tag}
                  <button
                    onClick={() => removeTag(tag)}
                    className="ml-0.5 opacity-50 hover:opacity-100 leading-none"
                    aria-label={`Remove tag ${tag}`}
                  >×</button>
                </span>
              ))}
              {addingTag ? (
                <input
                  autoFocus
                  value={tagInput}
                  onChange={e => setTagInput(e.target.value)}
                  onKeyDown={e => {
                    if (e.key === "Enter") addTag(tagInput)
                    if (e.key === "Escape") { setAddingTag(false); setTagInput("") }
                  }}
                  onBlur={() => { if (tagInput.trim()) addTag(tagInput); else { setAddingTag(false); setTagInput("") } }}
                  placeholder="tag name"
                  className="h-5 w-24 rounded-full border border-primary/50 bg-background px-2 text-xs outline-none focus:border-primary"
                />
              ) : (
                <button
                  onClick={() => setAddingTag(true)}
                  className="inline-flex items-center gap-0.5 rounded-full border border-dashed border-border px-2 py-0.5 text-xs text-muted-foreground hover:border-primary/50 hover:text-foreground transition-colors"
                  aria-label="Add tag"
                  data-testid="button-add-tag"
                >
                  <Plus className="w-3 h-3" />tag
                </button>
              )}
            </div>
          </div>
          <div className="flex items-center gap-2 shrink-0">
            <Button onClick={() => openChatWithProject()} data-testid="button-open-project-chat">
              <MessageCircle className="w-4 h-4 mr-2" />Chat
            </Button>
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button variant="ghost" size="icon" data-testid="button-project-actions">
                  <MoreHorizontal className="w-4 h-4" />
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end">
                <DropdownMenuItem onClick={() => { setRenameValue(project.name); setRenameOpen(true) }}>
                  <Pencil className="w-4 h-4 mr-2" />Rename
                </DropdownMenuItem>
                <DropdownMenuItem onClick={handleToggleStatus}>
                  <CheckCircle2 className="w-4 h-4 mr-2" />
                  {project.status === "completed" ? "Mark as Active" : "Mark as Complete"}
                </DropdownMenuItem>
                <DropdownMenuSeparator />
                <DropdownMenuItem onClick={() => setArchiveOpen(true)} className="text-muted-foreground">
                  <Archive className="w-4 h-4 mr-2" />Archive
                </DropdownMenuItem>
                <DropdownMenuItem onClick={() => setDeleteOpen(true)} className="text-destructive focus:text-destructive">
                  <Trash2 className="w-4 h-4 mr-2" />Delete
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        </div>
      </div>

      {/* Body */}
      <div className="flex flex-1 min-h-0 overflow-hidden">
        <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
          <Tabs value={activeTab} onValueChange={setActiveTab} className="flex-1 flex flex-col min-h-0">
            <TabsList className="w-fit mx-4 mt-3 mb-0 shrink-0">
              <TabsTrigger value="chat" className="flex items-center gap-1.5" data-testid="tab-project-chat">
                <MessageCircle className="w-3.5 h-3.5" />Chat
                {sessions.length > 0 && (
                  <span className="text-xs bg-muted rounded px-1">{sessions.length}</span>
                )}
              </TabsTrigger>
              <TabsTrigger value="files" className="flex items-center gap-1.5" data-testid="tab-project-files">
                <FileText className="w-3.5 h-3.5" />Files
              </TabsTrigger>
              <TabsTrigger value="workflows" className="flex items-center gap-1.5" data-testid="tab-project-workflows">
                <FlaskConical className="w-3.5 h-3.5" />Workflow Runs
              </TabsTrigger>
            </TabsList>

            {/* CHAT TAB */}
            <TabsContent value="chat" className="flex-1 m-0 overflow-hidden">
              <div className="h-full flex flex-col p-4 gap-4 overflow-y-auto">
                <div
                  className="rounded-xl border-2 border-dashed border-border p-6 text-center cursor-pointer hover:border-primary/50 hover:bg-muted/30 transition-all shrink-0"
                  onClick={() => openChatWithProject()}
                  data-testid="panel-new-project-chat"
                >
                  <MessageCircle className="w-8 h-8 mx-auto mb-3 text-muted-foreground/60" />
                  <p className="font-medium mb-1">Start a new chat about this project</p>
                  <p className="text-sm text-muted-foreground mb-4">
                    BioMate tracks project files, workflow runs, and research context automatically.
                  </p>
                  <Button
                    onClick={e => { e.stopPropagation(); openChatWithProject() }}
                    data-testid="button-new-project-chat"
                  >
                    <Plus className="w-4 h-4 mr-2" />New Chat
                  </Button>
                </div>

                {sessionsLoading ? (
                  <div className="flex items-center gap-2 text-sm text-muted-foreground justify-center py-4">
                    <Loader2 className="w-4 h-4 animate-spin" />Loading sessions…
                  </div>
                ) : sessions.length > 0 ? (
                  <>
                    <div className="flex items-center justify-between shrink-0">
                      <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                        Recent chats ({sessions.length})
                      </p>
                      <button onClick={loadSessions} className="text-muted-foreground hover:text-foreground">
                        <RefreshCw className="w-3 h-3" />
                      </button>
                    </div>
                    <div className="space-y-1.5">
                      {sessions.map((s: any) => {
                        const id = s.session_id ?? s.id
                        return (
                          <div
                            key={id}
                            className="flex items-center gap-3 rounded-lg border border-border px-3 py-2.5 hover:bg-muted/40 cursor-pointer group"
                            onClick={() => openChatWithProject(id)}
                            data-testid={`session-row-${id}`}
                          >
                            <MessageCircle className="w-3.5 h-3.5 text-muted-foreground shrink-0" />
                            <div className="flex-1 min-w-0">
                              <p className="text-sm font-medium truncate">{s.title || "Untitled chat"}</p>
                              <p className="text-xs text-muted-foreground">
                                {s.message_count ?? 0} messages · {relTime(s.last_activity ?? s.created_at)}
                              </p>
                            </div>
                            <ExternalLink className="w-3.5 h-3.5 text-muted-foreground opacity-0 group-hover:opacity-100 shrink-0" />
                          </div>
                        )
                      })}
                    </div>
                  </>
                ) : null}
              </div>
            </TabsContent>

            {/* FILES TAB */}
            <TabsContent value="files" className="flex-1 m-0 min-h-0" style={{ display: "flex", flexDirection: "column" }}>
              <div className="flex-1 p-4 min-h-0 flex flex-col">
                <ProjectFileTree
                  projectId={projectId}
                  onFilesChanged={(files) => setProjectFiles(files)}
                />
              </div>
              <div className="border-t border-border px-4 py-3 bg-muted/20 shrink-0 flex items-center justify-between gap-4">
                <p className="text-xs text-muted-foreground">
                  Upload data files, then let BioMate select and run the right workflow for you.
                </p>
                <Button
                  size="sm"
                  onClick={handleAnalyzeClick}
                  className="gap-1.5 shrink-0"
                  data-testid="button-analyze-files"
                >
                  <MessageCircle className="w-3.5 h-3.5" />
                  Analyze with BioMate
                </Button>
              </div>
            </TabsContent>

            {/* WORKFLOW RUNS TAB */}
            <TabsContent value="workflows" className="flex-1 m-0 min-h-0 overflow-hidden" data-testid="tab-content-workflows">
              <div className="h-full flex min-h-0">
                {/* Run list */}
                <div className="w-72 border-r border-border flex flex-col shrink-0">
                  <div className="flex items-center justify-between px-3 py-2 border-b border-border bg-muted/30 shrink-0">
                    <span className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Runs</span>
                    <button onClick={loadRuns} className="text-muted-foreground hover:text-foreground">
                      <RefreshCw className="w-3 h-3" />
                    </button>
                  </div>
                  <div className="flex-1 overflow-y-auto">
                    {runsLoading ? (
                      <div className="flex items-center gap-2 text-sm text-muted-foreground p-4 justify-center">
                        <Loader2 className="w-4 h-4 animate-spin" />Loading…
                      </div>
                    ) : runs.length === 0 ? (
                      <div className="flex flex-col items-center justify-center py-10 text-center text-muted-foreground px-4">
                        <FlaskConical className="w-8 h-8 mb-2 opacity-30" />
                        <p className="text-xs font-medium">No runs yet</p>
                        <p className="text-xs mt-1">Start a chat and ask BioMate to run a workflow.</p>
                      </div>
                    ) : (
                      <div className="py-1">
                        {runs.map((run: any) => {
                          const id = run.id ?? run.runId
                          const status = run.execution?.status ?? run.status ?? "unknown"
                          const name = run.workflowName ?? id
                          const ts = run.createdAt ?? run.execution?.createdAt
                          const isSel = selectedRunId === id
                          return (
                            <button
                              key={id}
                              className={cn(
                                "w-full flex items-center gap-2.5 px-3 py-2.5 text-left hover:bg-muted/40 transition-colors border-b border-border/50",
                                isSel && "bg-muted"
                              )}
                              onClick={() => setSelectedRunId(isSel ? null : id)}
                              data-testid={`run-row-${id}`}
                            >
                              {statusIcon(status)}
                              <div className="flex-1 min-w-0">
                                <p className="text-xs font-medium truncate">{name}</p>
                                <p className="text-xs text-muted-foreground">{relTime(ts)}</p>
                              </div>
                            </button>
                          )
                        })}
                      </div>
                    )}
                  </div>
                </div>

                {/* Workflow viewer */}
                <div className="flex-1 overflow-y-auto">
                  {selectedRunId ? (
                    (() => {
                      const run = runs.find((r: any) => (r.id ?? r.runId) === selectedRunId)
                      const status = run?.execution?.status ?? run?.status ?? "unknown"
                      const wfStatus: "idle" | "running" | "paused" | "completed" | "failed" | "pending_review" =
                        status === "completed" ? "completed" :
                        status === "failed" || status === "errored" ? "failed" :
                        status === "running" ? "running" : "idle"
                      return (
                        <NextflowWorkflowViewer
                          runId={selectedRunId}
                          sessionId={run?.chatSessionId}
                          workflowId={run?.workflowName}
                          workflowDefinition={run?.workflowDefinition}
                          status={wfStatus}
                          errorMessage={run?.execution?.errorMessage}
                        />
                      )
                    })()
                  ) : (
                    <div className="flex flex-col items-center justify-center h-full text-center text-muted-foreground px-6">
                      <FlaskConical className="w-10 h-10 mb-3 opacity-20" />
                      <p className="text-sm font-medium">Select a run to view its workflow panel</p>
                      <p className="text-xs mt-1">Phases, steps, QC gates, and output files appear here.</p>
                    </div>
                  )}
                </div>
              </div>
            </TabsContent>
          </Tabs>
        </div>

        {/* Right sidebar */}
        <div className="w-72 border-l border-border bg-muted/20 shrink-0 flex flex-col overflow-hidden">
          <div className="p-4 flex-1 overflow-y-auto">
            <div className="flex items-center justify-between mb-3">
              <h3 className="font-medium text-sm">Instructions</h3>
              {!isEditingInstructions && (
                <Button
                  variant="ghost" size="sm" className="h-7 w-7 p-0"
                  onClick={() => setIsEditingInstructions(true)}
                  data-testid="button-edit-instructions"
                >
                  <Edit3 className="w-3.5 h-3.5" />
                </Button>
              )}
            </div>

            {isEditingInstructions ? (
              <div className="space-y-2">
                <Textarea
                  value={instructionsValue}
                  onChange={e => setInstructionsValue(e.target.value)}
                  placeholder="Add context, guidelines, or background for this project…"
                  className="min-h-[160px] resize-none text-sm"
                  data-testid="textarea-edit-instructions"
                />
                <div className="flex gap-1.5">
                  <Button size="sm" className="h-7 text-xs" onClick={handleSaveInstructions} data-testid="button-save-instructions">
                    <Save className="w-3 h-3 mr-1" />Save
                  </Button>
                  <Button
                    variant="outline" size="sm" className="h-7 text-xs"
                    onClick={() => { setInstructionsValue(project.instructions || ""); setIsEditingInstructions(false) }}
                    data-testid="button-cancel-instructions"
                  >
                    <X className="w-3 h-3 mr-1" />Cancel
                  </Button>
                </div>
              </div>
            ) : project.instructions ? (
              <p className="text-sm text-muted-foreground whitespace-pre-wrap">{project.instructions}</p>
            ) : (
              <div className="text-center py-6 text-muted-foreground">
                <FileText className="w-7 h-7 mx-auto mb-2 opacity-30" />
                <p className="text-xs">No instructions yet</p>
                <p className="text-xs opacity-70 mt-0.5">Add context to help BioMate</p>
              </div>
            )}
          </div>

          <div className="border-t border-border p-4 shrink-0">
            <h4 className="font-medium text-xs uppercase tracking-wide text-muted-foreground mb-2">Details</h4>
            <div className="space-y-1.5 text-xs">
              <div className="flex justify-between">
                <span className="text-muted-foreground flex items-center gap-1">
                  <Clock className="w-3 h-3" />Created
                </span>
                <span>{new Date(project.createdAt).toLocaleDateString()}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">Chats</span>
                <span>{sessions.length > 0 ? sessions.length : "—"}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">Runs</span>
                <span>{runs.length > 0 ? runs.length : "—"}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">Updated</span>
                <span>{relTime((project as any).updatedAt ?? project.lastActivity)}</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Rename Dialog */}
      <Dialog open={renameOpen} onOpenChange={setRenameOpen}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader>
            <DialogTitle>Rename project</DialogTitle>
          </DialogHeader>
          <Input
            value={renameValue}
            onChange={e => setRenameValue(e.target.value)}
            placeholder="Project name"
            onKeyDown={e => e.key === "Enter" && handleRename()}
            autoFocus
          />
          <DialogFooter>
            <Button variant="outline" onClick={() => setRenameOpen(false)}>Cancel</Button>
            <Button onClick={handleRename} disabled={actionLoading || !renameValue.trim()}>
              {actionLoading ? <Loader2 className="w-4 h-4 animate-spin" /> : "Save"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Archive Confirmation */}
      <AlertDialog open={archiveOpen} onOpenChange={setArchiveOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Archive this project?</AlertDialogTitle>
            <AlertDialogDescription>
              The project and its linked chats and runs will be archived. You can restore it later by changing its status.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={handleArchive} disabled={actionLoading}>
              {actionLoading ? "Archiving…" : "Archive"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Delete Confirmation */}
      <AlertDialog open={deleteOpen} onOpenChange={setDeleteOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete this project?</AlertDialogTitle>
            <AlertDialogDescription>
              This permanently deletes the project and all linked data. This action cannot be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={handleDelete}
              disabled={actionLoading}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              {actionLoading ? "Deleting…" : "Delete"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  )
}
