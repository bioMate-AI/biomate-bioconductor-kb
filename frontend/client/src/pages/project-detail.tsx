import { locale, t, tOr } from "@/lib/i18n"

/** Notes card removed from the project page (see the JSX comment); API kept. */
const PROJECT_NOTES_VISIBLE = false
import { useState, useEffect, useCallback } from "react"
import { useLocation } from "wouter"
import { useActiveProjectSafe } from "@/contexts/active-project-context"
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
  UserPlus,
  Users,
  Download,
  Crown,
} from "lucide-react"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import { projectService } from "@/lib/projects"
import { ProjectGuidanceCards, ProjectInheritanceCard, ProjectInstructionsPage } from "@/components/project-guidance-cards"
import { ProjectFileTree } from "@/components/project-file-tree"
import { NextflowWorkflowViewer } from "@/components/nextflow-workflow-viewer"
import { type RoleCapability } from "@/components/roles-verify"
import type { Project } from "@shared/schema"
import { cn } from "@/lib/utils"

/** The three concrete project roles the server assigns (owner|editor|viewer). */
export type ProjectRole = "owner" | "editor" | "viewer"

/**
 * Prettify a raw domain/tag token (e.g. "transcriptomics", "drug_discovery") for
 * display: a localized `domains.*` label when one exists, else a Title-Cased
 * version of the raw token — never the bare lowercase internal string.
 */
export function prettyTag(tag: string): string {
  return tOr(`domains.${tag}`, tag.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase()))
}

/** Localized label for a project lifecycle status (active|completed|archived|…). */
export function prettyStatus(status: string): string {
  return tOr(`projects.status_${status}`, status.charAt(0).toUpperCase() + status.slice(1))
}

// Rank so a role satisfies any capability requiring an equal-or-lower role.
// owner ⊃ editor ⊃ viewer (owner can do everything an editor can, etc.).
const ROLE_RANK: Record<ProjectRole, number> = { viewer: 0, editor: 1, owner: 2 }

/**
 * The per-project capability map (spec §0.14) as {capability, needs} — the
 * `allowed` flag is derived per-user from their real role below. This is the
 * single source of truth fed to <RolesCard>; it never grants a capability the
 * server wouldn't (every "needs" role matches the server's write/owner gates:
 * editor+ writes via _canWrite; owner-only for members/status/external actions).
 */
const PROJECT_CAP_MAP: Array<{ capability: string; needs: ProjectRole; needsLabel: string }> = [
  { capability: "Read & download files", needs: "viewer", needsLabel: "Viewer" },
  { capability: "Run analyses & edit project content", needs: "editor", needsLabel: "Editor" },
  { capability: "Edit & publish the report", needs: "owner", needsLabel: "Owner" },
  { capability: "Approve external transfer / spend / publish", needs: "owner", needsLabel: "Owner" },
  { capability: "Manage members & roles", needs: "owner", needsLabel: "Owner" },
]

/** Build the RolesCard capability list for a given real role (disabled-not-hidden). */
export function buildRoleCapabilities(role: ProjectRole): RoleCapability[] {
  return PROJECT_CAP_MAP.map((c) => ({
    capability: c.capability,
    needs: c.needsLabel,
    allowed: ROLE_RANK[role] >= ROLE_RANK[c.needs],
  }))
}

interface ProjectDetailPageProps {
  projectId: string
  onBack: () => void
  initialTab?: string
}

export default function ProjectDetailPage({ projectId, onBack, initialTab }: ProjectDetailPageProps) {
  const [, navigate] = useLocation()
  const projectContext = useActiveProjectSafe()
  useEffect(() => { projectContext?.setActiveProjectId(projectId) }, [projectId])
  const [project, setProject] = useState<Project | null>(null)
  const [loadingProject, setLoadingProject] = useState(true)
  const [isEditingInstructions, setIsEditingInstructions] = useState(false)
  const [instructionsValue, setInstructionsValue] = useState("")
  const validTabs = ["chat", "files", "instructions"]
  const [activeTab, setActiveTab] = useState(validTabs.includes(initialTab || "") ? initialTab! : "files")

  const [sessions, setSessions] = useState<any[]>([])
  const [sessionsLoading, setSessionsLoading] = useState(false)

  const [runs, setRuns] = useState<any[]>([])
  const [runsLoading, setRunsLoading] = useState(false)
  const [selectedRunId, setSelectedRunId] = useState<string | null>(null)
  const [savingOutputs, setSavingOutputs] = useState(false)
  const [saveOutputsMsg, setSaveOutputsMsg] = useState<string | null>(null)
  const [projectFiles, setProjectFiles] = useState<{ name: string; size?: number }[]>([])

  // Plan / hypothesis objects (project_plans). Listed + created here.
  const [plans, setPlans] = useState<any[]>([])
  const [plansLoading, setPlansLoading] = useState(false)
  const [newPlanGoal, setNewPlanGoal] = useState("")
  const [newPlanHypothesis, setNewPlanHypothesis] = useState("")
  const [creatingPlan, setCreatingPlan] = useState(false)

  // Human-only notes (project_knowledge / knowledgeType='user_notes').
  // NOT read by the assistant — distinct from Standing instructions (researchGoal).
  const [notes, setNotes] = useState<any[]>([])
  const [notesLoading, setNotesLoading] = useState(false)
  const [newNote, setNewNote] = useState("")
  const [savingNote, setSavingNote] = useState(false)

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

  // Project sharing
  const [isOwner, setIsOwner] = useState(false)
  // canEdit = owner OR editor member. Viewers are read-only; gates content controls.
  const [canEdit, setCanEdit] = useState(false)
  // The current user's REAL role for this project (owner|editor|viewer), as
  // returned by GET /api/projects/:id. Feeds RolesCard so the capability
  // verdicts reflect actual server-side rights — never fabricated.
  const [myRole, setMyRole] = useState<ProjectRole>("viewer")
  const [members, setMembers] = useState<Array<{ user_id: string; email: string; fullName?: string; role: string }>>([])
  const [shareEmail, setShareEmail] = useState("")
  const [shareRole, setShareRole] = useState<"viewer" | "editor">("viewer")
  const [inviting, setInviting] = useState(false)
  const [inviteError, setInviteError] = useState<string | null>(null)
  const [inviteNotice, setInviteNotice] = useState<string | null>(null)
  // Ownership transfer — the member we're about to promote to owner (null = dialog closed).
  const [transferTarget, setTransferTarget] = useState<{ user_id: string; email: string; fullName?: string } | null>(null)
  const [transferring, setTransferring] = useState(false)
  const [transferError, setTransferError] = useState<string | null>(null)

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
          if (data.isOwner !== undefined) setIsOwner(data.isOwner)
          // canEdit from server (owner|editor); fall back to isOwner for older payloads.
          setCanEdit(data.canEdit ?? data.isOwner ?? false)
          // Real role from server; derive from isOwner/canEdit for older payloads.
          const serverRole: ProjectRole | undefined =
            data.role === "owner" || data.role === "editor" || data.role === "viewer" ? data.role : undefined
          setMyRole(serverRole ?? (data.isOwner ? "owner" : data.canEdit ? "editor" : "viewer"))
        } else {
          const loc = projectService.getProject(projectId)
          if (loc) { setProject(loc); setInstructionsValue(loc.instructions || ""); setIsOwner(true); setCanEdit(true); setMyRole("owner") }
        }
      })
      .catch(() => {
        const loc = projectService.getProject(projectId)
        if (loc) { setProject(loc); setInstructionsValue(loc.instructions || ""); setIsOwner(true); setMyRole("owner") }
      })
      .finally(() => setLoadingProject(false))
  }, [projectId])

  const loadMembers = useCallback(async () => {
    try {
      const r = await fetch(`/api/projects/${projectId}/members`, { credentials: "include" })
      if (r.ok) setMembers((await r.json()).members ?? [])
    } catch { /* ignore */ }
  }, [projectId])

  useEffect(() => { loadMembers() }, [loadMembers])

  // Share links are now created+emailed server-side on invite of a new address
  // (POST /api/projects/:id/members), so the separate generate/copy/revoke UI
  // and its mount-time fetch were removed.

  const handleInvite = async () => {
    if (!shareEmail.trim()) return
    setInviting(true)
    setInviteError(null)
    setInviteNotice(null)
    try {
      const invitedEmail = shareEmail.trim()
      const r = await fetch(`/api/projects/${projectId}/members`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        credentials: "include",
        body: JSON.stringify({ email: invitedEmail, role: shareRole }),
      })
      const data = await r.json()
      if (!r.ok) { setInviteError(data.error ?? "Failed to invite"); return }
      setShareEmail("")
      if (data.pending) {
        // New (unregistered) email: the server emailed them the join link.
        setInviteNotice(t('project_members.invite_sent', { email: invitedEmail }))
      } else {
        loadMembers()
      }
    } catch { setInviteError("Failed to invite") }
    finally { setInviting(false) }
  }

  const handleRemoveMember = async (memberId: string) => {
    try {
      await fetch(`/api/projects/${projectId}/members/${memberId}`, {
        method: "DELETE", credentials: "include",
      })
      setMembers(prev => prev.filter(m => m.user_id !== memberId))
    } catch { /* ignore */ }
  }

  const handleRoleChange = async (memberId: string, newRole: "viewer" | "editor") => {
    try {
      const r = await fetch(`/api/projects/${projectId}/members/${memberId}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        credentials: "include",
        body: JSON.stringify({ role: newRole }),
      })
      if (r.ok) setMembers(prev => prev.map(m => m.user_id === memberId ? { ...m, role: newRole } : m))
    } catch { /* ignore */ }
  }

  // Transfer ownership to a current member. Irreversible: the server promotes the
  // target to owner and demotes the current user to editor. On success we reflect
  // that demotion locally (isOwner → false, myRole → editor) and reload members.
  const handleTransferOwnership = async () => {
    if (!transferTarget) return
    setTransferring(true)
    setTransferError(null)
    try {
      const r = await fetch(`/api/projects/${projectId}/owner`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        credentials: "include",
        body: JSON.stringify({ newOwnerId: transferTarget.user_id }),
      })
      const data = await r.json().catch(() => ({}))
      if (!r.ok) { setTransferError(data.error ?? "Failed to transfer ownership"); return }
      setIsOwner(false)
      setMyRole("editor")
      setTransferTarget(null)
      loadMembers()
    } catch { setTransferError("Failed to transfer ownership") }
    finally { setTransferring(false) }
  }

  const handleLeaveProject = async () => {
    try {
      const r = await fetch(`/api/projects/${projectId}/members/me`, {
        method: "DELETE", credentials: "include",
      })
      if (r.ok) onBack()
    } catch { /* ignore */ }
  }

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
        window.dispatchEvent(new CustomEvent("biomate:projects-updated"))
      }
    } catch { /* keep editing open */ }
  }

  const loadPlans = useCallback(async () => {
    setPlansLoading(true)
    try {
      const r = await fetch(`/api/projects/${projectId}/plans`, { credentials: "include" })
      if (r.ok) setPlans((await r.json()).plans ?? [])
    } catch { /* ignore */ }
    finally { setPlansLoading(false) }
  }, [projectId])

  useEffect(() => { loadPlans() }, [loadPlans])

  const handleCreatePlan = async () => {
    const goal = newPlanGoal.trim()
    if (!goal) return
    setCreatingPlan(true)
    try {
      const r = await fetch(`/api/projects/${projectId}/plans`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        credentials: "include",
        body: JSON.stringify({ goal, hypothesis: newPlanHypothesis.trim() || null }),
      })
      if (r.ok) {
        setNewPlanGoal("")
        setNewPlanHypothesis("")
        loadPlans()
      }
    } catch { /* keep form open */ }
    finally { setCreatingPlan(false) }
  }

  const loadNotes = useCallback(async () => {
    setNotesLoading(true)
    try {
      const r = await fetch(`/api/projects/${projectId}/notes-list`, { credentials: "include" })
      if (r.ok) setNotes((await r.json()).notes ?? [])
    } catch { /* ignore */ }
    finally { setNotesLoading(false) }
  }, [projectId])

  useEffect(() => { loadNotes() }, [loadNotes])

  const handleSaveNote = async () => {
    const content = newNote.trim()
    if (!content) return
    setSavingNote(true)
    try {
      const r = await fetch(`/api/projects/${projectId}/notes-list`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        credentials: "include",
        body: JSON.stringify({ content }),
      })
      if (r.ok) { setNewNote(""); loadNotes() }
    } catch { /* keep text */ }
    finally { setSavingNote(false) }
  }

  // Append a note's text into the Standing instructions (researchGoal), then
  // persist via the same PATCH the instructions save uses. Trust boundary:
  // Notes are human-only until explicitly promoted.
  const handlePromoteNote = async (text: string) => {
    if (!project) return
    const line = (text || "").trim()
    if (!line) return
    const current = (instructionsValue || "").trim()
    const next = current ? `${current}\n${line}` : line
    try {
      const r = await fetch(`/api/projects/${project.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        credentials: "include",
        body: JSON.stringify({ researchGoal: next }),
      })
      if (r.ok) {
        setInstructionsValue(next)
        setProject(prev => prev ? { ...prev, instructions: next } as any : prev)
      }
    } catch { /* ignore */ }
  }

  const openChatWithProject = (sessionId?: string, prefilledMessage?: string) => {
    try { localStorage.setItem("biomate-active-project-id", projectId) } catch { /* ignore */ }
    let url = sessionId ? `/?session=${encodeURIComponent(sessionId)}` : "/"
    // Use ?draft= (not ?q=) so the message is pre-filled into the chat input for the
    // user to review/edit before sending — NOT auto-submitted. Analyze-generated
    // messages are generic ("I've uploaded these files…") and almost always need the
    // user to add scientific context (organism, design, comparison) before running.
    if (prefilledMessage && !sessionId) url += `?draft=${encodeURIComponent(prefilledMessage)}`
    window.location.assign(url)
  }

  const handleAnalyzeClick = () => {
    let msg: string | undefined
    if (projectFiles.length > 0) {
      const fmt = (n?: number) => !n ? "" : n < 1024 ? ` (${n} B)` : n < 1048576 ? ` (${(n/1024).toFixed(1)} KB)` : ` (${(n/1048576).toFixed(1)} MB)`
      const fileList = projectFiles.map(f => `- ${f.name}${fmt(f.size)}`).join("\n")
      msg = `I've uploaded these files to my project:\n${fileList}\nPlease analyze these files and suggest the right workflow.`
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
    if (h < 1) return tOr('runs_ui.fresh_just_now', 'just now')
    if (h < 24) return tOr('runs_ui.fresh_hours', '{{n}}h ago', { n: h })
    if (days < 7) return tOr('runs_ui.fresh_days', '{{n}}d ago', { n: days })
    return new Date(d as any).toLocaleDateString(locale === 'zh' ? 'zh-CN' : locale)
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
          <h2 className="text-xl font-semibold mb-2">{tOr('projects.page.not_found', "Project not found")}</h2>
          <Button onClick={onBack}><ArrowLeft className="w-4 h-4 mr-2" />{tOr('projects.page.back_to_projects', "Back to Projects")}</Button>
        </div>
      </div>
    )
  }

  return (
    <div className="h-full min-h-0 min-w-0 flex flex-col overflow-hidden [overflow-wrap:anywhere]">
      {/* Header */}
      <div className="border-b border-border px-6 py-4 shrink-0" style={activeTab === "instructions" ? { display: "none" } : undefined}>
        <div className="flex items-center gap-3 mb-3">
          <Button variant="ghost" size="sm" onClick={onBack} data-testid="button-back-to-projects">
            <ArrowLeft className="w-4 h-4 mr-2" />{tOr('projects.all_projects', 'All projects')}
          </Button>
        </div>
        <div className="flex items-start justify-between gap-4">
          <div className="min-w-0">
            <h1 className="text-2xl font-bold truncate">{project.name}</h1>
            {project.description && (
              <p className="text-muted-foreground text-sm mt-1 line-clamp-2">{project.description}</p>
            )}
            <div className="flex items-center gap-2 mt-2 flex-wrap">
              {project.category && <Badge variant="outline" className="text-xs">{prettyTag(project.category)}</Badge>}
              <Badge variant="secondary" className={cn(
                "text-xs",
                project.status === "completed" && "bg-green-100 text-green-700",
                project.status === "archived" && "bg-gray-100 text-gray-600",
                project.status === "active" && "bg-blue-100 text-blue-700",
              )}>{prettyStatus(project.status)}</Badge>
              {editingTags.map(tag => (
                <span
                  key={tag}
                  className="inline-flex items-center gap-1 rounded-full border border-border bg-secondary text-secondary-foreground px-2 py-0.5 text-xs"
                >
                  <Tag className="w-3 h-3 opacity-60" />{prettyTag(tag)}
                  {canEdit && (
                  <button
                    onClick={() => removeTag(tag)}
                    className="ml-0.5 opacity-50 hover:opacity-100 leading-none"
                    aria-label={`Remove tag ${tag}`}
                  >×</button>
                  )}
                </span>
              ))}
              {!canEdit ? null : addingTag ? (
                <input
                  autoFocus
                  value={tagInput}
                  onChange={e => setTagInput(e.target.value)}
                  onKeyDown={e => {
                    if (e.key === "Enter") addTag(tagInput)
                    if (e.key === "Escape") { setAddingTag(false); setTagInput("") }
                  }}
                  onBlur={() => { if (tagInput.trim()) addTag(tagInput); else { setAddingTag(false); setTagInput("") } }}
                  placeholder={tOr('projects.page.tag_placeholder', "tag name")}
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
            {/* Redundant top-right "Chat" entry point removed — the Chat tab navigates here
                and the center "New Chat" panel is the single primary chat-start action. */}
            {isOwner && (
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button variant="ghost" size="icon" data-testid="button-project-actions">
                  <MoreHorizontal className="w-4 h-4" />
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end">
                <DropdownMenuItem onClick={() => { setRenameValue(project.name); setRenameOpen(true) }}>
                  <Pencil className="w-4 h-4 mr-2" />{tOr('projects.page.rename', "Rename")}
                </DropdownMenuItem>
                <DropdownMenuItem onClick={handleToggleStatus}>
                  <CheckCircle2 className="w-4 h-4 mr-2" />
                  {project.status === "completed" ? "Mark as Active" : "Mark as Complete"}
                </DropdownMenuItem>
                <DropdownMenuSeparator />
                <DropdownMenuItem onClick={() => setArchiveOpen(true)} className="text-muted-foreground">
                  <Archive className="w-4 h-4 mr-2" />{tOr('projects.page.archive', "Archive")}
                </DropdownMenuItem>
                <DropdownMenuItem onClick={() => setDeleteOpen(true)} className="text-destructive focus:text-destructive">
                  <Trash2 className="w-4 h-4 mr-2" />{tOr('projects.page.delete', "Delete")}
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
            )}
          </div>
        </div>
      </div>

      {/* Body */}
      <div className="flex flex-1 min-h-0 overflow-hidden">
        <div className="flex-1 flex flex-col min-w-0 overflow-hidden" style={activeTab === "instructions" ? { display: "none" } : undefined}>
          <Tabs value={activeTab} onValueChange={setActiveTab} className="flex-1 flex flex-col min-h-0">
            <TabsList className="w-fit mx-4 mt-3 mb-0 shrink-0">
              <TabsTrigger value="chat" className="flex items-center gap-1.5" data-testid="tab-project-chat">
                <MessageCircle className="w-3.5 h-3.5" />{tOr('projects.page.tab_chat', "Chat")}
                {sessions.length > 0 && (
                  <span className="text-xs bg-muted rounded px-1">{sessions.length}</span>
                )}
              </TabsTrigger>
              <TabsTrigger value="files" className="flex items-center gap-1.5" data-testid="tab-project-files">
                <FileText className="w-3.5 h-3.5" />{tOr('projects.page.tab_files', "Files")}
              </TabsTrigger>
              {/* Project Runs tab hidden to avoid duplicating chat execution history. */}
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
                  <p className="font-medium mb-1">{tOr('projects.new_chat_title', 'Start a new chat about this project')}</p>
                  <p className="text-sm text-muted-foreground mb-4">
                    {tOr('projects.new_chat_desc', 'BioMate tracks project files, workflow runs, and research context automatically.')}
                  </p>
                  <Button
                    onClick={e => { e.stopPropagation(); openChatWithProject() }}
                    data-testid="button-new-project-chat"
                  >
                    <Plus className="w-4 h-4 mr-2" />{tOr('projects.new_chat', 'New Chat')}
                  </Button>
                </div>

                {sessionsLoading ? (
                  <div className="flex items-center gap-2 text-sm text-muted-foreground justify-center py-4">
                    <Loader2 className="w-4 h-4 animate-spin" />{tOr('projects.loading_sessions', 'Loading sessions…')}
                  </div>
                ) : sessions.length > 0 ? (
                  <>
                    <div className="flex items-center justify-between shrink-0">
                      <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                        {tOr('projects.recent_chats', 'Recent chats ({{count}})', { count: sessions.length })}
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
                                {tOr('projects.page.message_count', '{{n}} messages', { n: s.message_count ?? 0 })} · {relTime(s.last_activity ?? s.created_at)}
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
            <TabsContent value="files" className="flex-1 m-0 min-h-0" style={{ display: activeTab === "files" ? "flex" : "none", flexDirection: "column" }}>
              <div className="flex-1 p-4 min-h-0 flex flex-col">
                <ProjectFileTree
                  projectId={projectId}
                  onFilesChanged={(files) => setProjectFiles(files)}
                  canEdit={canEdit}
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

            {/* Duplicate project Runs view retired at user request; history remains in Run Manager. */}

          </Tabs>
        </div>

        {/* Right sidebar */}
        <div data-testid="project-instructions-panel" className={activeTab === "instructions" ? "flex-1 min-w-0 flex flex-col overflow-y-auto bg-background" : "w-72 border-l border-border bg-muted/20 shrink-0 flex flex-col overflow-hidden"}>
          {activeTab === "instructions" && <ProjectInstructionsPage projectId={projectId} projectName={project.name} canEdit={canEdit} instructions={project.instructions || ""} onInstructionsSaved={(t) => { setInstructionsValue(t); setProject(prev => prev ? { ...prev, instructions: t } : prev); }} />}
          {activeTab !== "instructions" && <div className="p-4 flex-1 overflow-y-auto space-y-6">
            {/* Standing instructions — the agent-read directives (persist to researchGoal). */}
            <div data-testid="standing-instructions-card" className={activeTab === "instructions" ? "rounded-lg border border-border p-5" : undefined}>
              <div className="flex items-center justify-between mb-1">
                <h3 className="font-medium text-sm">{tOr('projects.standing_instructions', 'Standing instructions')}</h3>
                {canEdit && !isEditingInstructions && (
                  <Button
                    variant="ghost" size="sm" className="h-7 w-7 p-0"
                    onClick={() => setIsEditingInstructions(true)}
                    data-testid="button-edit-instructions"
                  >
                    <Edit3 className="w-3.5 h-3.5" />
                  </Button>
                )}
              </div>
              <p className="text-fs-xs text-muted-foreground mb-3">{tOr('projects.standing_instructions_hint', 'Read by the assistant on every chat in this project.')}</p>

              {isEditingInstructions ? (
                <div className="space-y-2">
                  <Textarea
                    value={instructionsValue}
                    onChange={e => setInstructionsValue(e.target.value)}
                    placeholder={tOr('projects.page.instructions_placeholder', "Add context, guidelines, or background the assistant should follow\u2026")}
                    className="min-h-[140px] resize-none text-sm"
                    data-testid="textarea-edit-instructions"
                  />
                  <div className="flex gap-1.5">
                    <Button size="sm" className="h-7 text-xs" onClick={handleSaveInstructions} data-testid="button-save-instructions">
                      <Save className="w-3 h-3 mr-1" />{tOr('projects.page.save', "Save")}
                    </Button>
                    <Button
                      variant="outline" size="sm" className="h-7 text-xs"
                      onClick={() => { setInstructionsValue(project.instructions || ""); setIsEditingInstructions(false) }}
                      data-testid="button-cancel-instructions"
                    >
                      <X className="w-3 h-3 mr-1" />{tOr('projects.page.cancel', "Cancel")}
                    </Button>
                  </div>
                </div>
              ) : project.instructions ? (
                <p className="text-sm text-muted-foreground whitespace-pre-wrap">{project.instructions}</p>
              ) : (
                <div className="text-center py-6 text-muted-foreground">
                  <FileText className="w-7 h-7 mx-auto mb-2 opacity-30" />
                  <p className="text-xs">{tOr('projects.page.no_instructions', "No instructions yet")}</p>
                  <p className="text-xs opacity-70 mt-0.5">{tOr('projects.page.no_instructions_hint', "Add context to help BioMate")}</p>
                </div>
              )}
            </div>

            {activeTab === "instructions" && <ProjectGuidanceCards projectId={projectId} canEdit={canEdit} onOpenFiles={() => navigate("/files")} />}

            <div className={activeTab === "instructions" ? "grid md:grid-cols-2 gap-4" : undefined}>
            {/* Notes — human-only free text, NOT read by the assistant. Removed from the page
                (founder review 2026-11-10, removenewchat_remove_sidebar.png): a second
                free-text box beside 常驻指令 confused what the assistant reads. The
                notes API and stored notes are kept. */}
            {PROJECT_NOTES_VISIBLE && <div className={activeTab === "instructions" ? "rounded-lg border border-border p-5" : "border-t border-border pt-4"} data-testid="notes-card">
              <h3 className="font-medium text-sm">Notes</h3>
              <p className="text-fs-xs text-muted-foreground mb-3">
                Private to you — <span className="font-medium">not read by the assistant</span>. Promote a note to make it a standing instruction.
              </p>

              {canEdit && (
                <div className="space-y-1.5 mb-3">
                  <Textarea
                    value={newNote}
                    onChange={e => setNewNote(e.target.value)}
                    placeholder="Jot a note for yourself…"
                    className="min-h-[64px] resize-none text-sm"
                    data-testid="textarea-new-note"
                  />
                  <div className="flex gap-1.5">
                    <Button
                      size="sm" className="h-7 text-xs"
                      onClick={handleSaveNote}
                      disabled={savingNote || !newNote.trim()}
                      data-testid="button-save-note"
                    >
                      {savingNote ? <Loader2 className="w-3 h-3 mr-1 animate-spin" /> : <Save className="w-3 h-3 mr-1" />}Add note
                    </Button>
                    {canEdit && newNote.trim() && (
                      <Button
                        variant="outline" size="sm" className="h-7 text-xs"
                        onClick={() => handlePromoteNote(newNote)}
                        title={tOr('projects.promote_tooltip_text', 'Append this text to Standing instructions')}
                        data-testid="button-promote-new-note"
                      >
                        Promote to instruction ↑
                      </Button>
                    )}
                  </div>
                </div>
              )}

              {notesLoading ? (
                <div className="flex items-center gap-2 text-xs text-muted-foreground py-2">
                  <Loader2 className="w-3.5 h-3.5 animate-spin" />Loading notes…
                </div>
              ) : notes.length === 0 ? (
                <p className="text-xs text-muted-foreground" data-testid="notes-empty">No notes yet</p>
              ) : (
                <div className="space-y-2" data-testid="notes-list">
                  {notes.map((n: any) => (
                    <div key={n.id} className="rounded-md border border-border bg-background p-2.5" data-testid={`note-row-${n.id}`}>
                      <p className="text-sm whitespace-pre-wrap">{n.content}</p>
                      <div className="flex items-center justify-between mt-1.5">
                        <span className="text-fs-xs text-muted-foreground">{relTime(n.createdAt)}</span>
                        {canEdit && (
                          <button
                            onClick={() => handlePromoteNote(n.content)}
                            className="text-fs-xs text-muted-foreground hover:text-primary"
                            title={tOr('projects.promote_tooltip_note', 'Append this note to Standing instructions')}
                            data-testid={`button-promote-note-${n.id}`}
                          >
                            Promote to instruction ↑
                          </button>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>}

            {activeTab === "instructions" && <ProjectInheritanceCard onOpenFiles={() => navigate("/files")} />}
            </div>

            {/* Plan / hypothesis — first-class objects a run can cite (project_plans). */}
            {activeTab !== "instructions" && <div className="border-t border-border pt-4" data-testid="plans-card">
              <h3 className="font-medium text-sm mb-3">{tOr('projects.page.plan_title', "Plan / hypothesis")}</h3>

              {canEdit && (
                <div className="space-y-1.5 mb-3" data-testid="new-plan-form">
                  <Input
                    value={newPlanGoal}
                    onChange={e => setNewPlanGoal(e.target.value)}
                    placeholder={tOr('projects.page.plan_goal', "Goal (required)")}
                    className="h-8 text-sm"
                    data-testid="input-plan-goal"
                  />
                  <Textarea
                    value={newPlanHypothesis}
                    onChange={e => setNewPlanHypothesis(e.target.value)}
                    placeholder={tOr('projects.page.plan_hypothesis', "Hypothesis (optional)")}
                    className="min-h-[56px] resize-none text-sm"
                    data-testid="textarea-plan-hypothesis"
                  />
                  <Button
                    size="sm" className="h-7 text-xs"
                    onClick={handleCreatePlan}
                    disabled={creatingPlan || !newPlanGoal.trim()}
                    data-testid="button-create-plan"
                  >
                    {creatingPlan ? <Loader2 className="w-3 h-3 mr-1 animate-spin" /> : <Plus className="w-3 h-3 mr-1" />}New plan
                  </Button>
                </div>
              )}

              {plansLoading ? (
                <div className="flex items-center gap-2 text-xs text-muted-foreground py-2">
                  <Loader2 className="w-3.5 h-3.5 animate-spin" />{tOr('projects.page.loading_plans', "Loading plans\u2026")}
                </div>
              ) : plans.length === 0 ? (
                <p className="text-xs text-muted-foreground" data-testid="plans-empty">{tOr('projects.page.no_plans', "No plans yet")}</p>
              ) : (
                <div className="space-y-2" data-testid="plans-list">
                  {plans.map((p: any) => (
                    <div key={p.id} className="rounded-md border border-border bg-background p-2.5" data-testid={`plan-row-${p.id}`}>
                      <p className="text-sm font-medium whitespace-pre-wrap">{p.goal}</p>
                      {p.hypothesis && (
                        <p className="text-xs text-muted-foreground whitespace-pre-wrap mt-1">{p.hypothesis}</p>
                      )}
                      <span className="text-fs-xs text-muted-foreground block mt-1.5">{relTime(p.created_at)}</span>
                    </div>
                  ))}
                </div>
              )}
            </div>}
          </div>}

          {/* Members & roles — owner-only invite UI + member list visible to all.
              Rendered on every tab where the project panel is visible, INCLUDING
              instructions: the files/chat tabs that used to host this panel now
              redirect to /files (App.tsx), and the workflows tab hides the whole
              panel, so instructions is the only reachable home — and T7 documents
              Standing instructions + Members & roles together here. On instructions
              it aligns to the same centered content column as the cards above. */}
          {project && <div className={`border-t border-border p-4 shrink-0${activeTab === "instructions" ? " w-full max-w-4xl mx-auto sm:px-6" : ""}`} data-testid="members-panel">
            <div className="flex items-center gap-1.5 mb-3">
              <Users className="w-3.5 h-3.5 text-muted-foreground" />
              <h4 className="font-medium text-xs uppercase tracking-wide text-muted-foreground flex-1">{t('project_members.title')}</h4>
              {/* The current user's OWN role for this project (real, from the server). */}
              <span
                data-testid="my-role-badge"
                className="inline-flex items-center rounded-full border border-primary/40 bg-primary/10 px-1.5 py-0.5 text-fs-xs font-medium text-primary capitalize"
                title={t('project_members.your_role')}
              >
                {t('project_members.you')}: {t(`project_members.${myRole}`)}
              </span>
            </div>

            {isOwner && (
              <div className="space-y-2 mb-3">
                <div className="flex gap-1.5">
                  <Input
                    value={shareEmail}
                    onChange={e => { setShareEmail(e.target.value); setInviteError(null) }}
                    placeholder="email@example.com"
                    className="h-7 text-xs flex-1"
                    onKeyDown={e => e.key === "Enter" && handleInvite()}
                    data-testid="input-share-email"
                  />
                  <Select value={shareRole} onValueChange={v => setShareRole(v as "viewer" | "editor")}>
                    <SelectTrigger className="h-7 w-20 text-xs" data-testid="select-share-role">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="viewer">{t('project_members.viewer')}</SelectItem>
                      <SelectItem value="editor">{t('project_members.editor')}</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <Button
                  size="sm" className="h-7 text-xs w-full gap-1.5"
                  onClick={handleInvite}
                  disabled={inviting || !shareEmail.trim()}
                  data-testid="button-share-invite"
                >
                  {inviting ? <Loader2 className="w-3 h-3 animate-spin" /> : <UserPlus className="w-3 h-3" />}
                  {t('project_members.invite')}
                </Button>
                {inviteError && <p className="text-xs text-destructive">{inviteError}</p>}
                {inviteNotice && <p className="text-xs text-emerald-600 dark:text-emerald-400">{inviteNotice}</p>}
                <p className="text-fs-xs text-muted-foreground leading-snug">{t('project_members.invite_help')}</p>
              </div>
            )}

            {members.length === 0 && isOwner ? (
              <p className="text-xs text-muted-foreground">{t('project_members.no_members')}</p>
            ) : (
              <div className="space-y-1.5">
                {members.map(m => {
                  const initials = (m.fullName || m.email)
                    .split(/\s+|@/)
                    .filter(Boolean)
                    .slice(0, 2)
                    .map((s: string) => s[0].toUpperCase())
                    .join("")
                  return (
                    <div key={m.user_id} className="flex items-center gap-2 text-xs" data-testid={`member-row-${m.user_id}`}>
                      {/* Initials avatar */}
                      <div className="w-6 h-6 rounded-full bg-primary/10 flex items-center justify-center text-fs-xs font-semibold text-primary shrink-0">
                        {initials}
                      </div>
                      <div className="flex-1 min-w-0">
                        <p className="truncate font-medium leading-tight">{m.fullName || m.email}</p>
                        {m.fullName && <p className="text-muted-foreground truncate text-fs-xs">{m.email}</p>}
                      </div>
                      {/* Role badge / change dropdown */}
                      {m.role === "owner" ? (
                        <span className="text-fs-xs font-semibold px-1.5 py-0.5 rounded bg-primary/10 text-primary shrink-0">{t('project_members.owner')}</span>
                      ) : isOwner ? (
                        <Select value={m.role} onValueChange={(v) => handleRoleChange(m.user_id, v as "viewer" | "editor")}>
                          <SelectTrigger className="h-5 w-16 text-fs-xs px-1.5 border-0 bg-muted/60 rounded shrink-0" data-testid={`select-role-${m.user_id}`}>
                            <SelectValue />
                          </SelectTrigger>
                          <SelectContent>
                            <SelectItem value="viewer">{t('project_members.viewer')}</SelectItem>
                            <SelectItem value="editor">{t('project_members.editor')}</SelectItem>
                          </SelectContent>
                        </Select>
                      ) : (
                        <span className={`text-fs-xs font-medium px-1.5 py-0.5 rounded shrink-0 ${m.role === "editor" ? "bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400" : "bg-muted text-muted-foreground"}`}>
                          {t(`project_members.${m.role}`)}
                        </span>
                      )}
                      {/* Make owner — transfers ownership to this member (owner-only, confirm dialog) */}
                      {isOwner && m.role !== "owner" && (
                        <button
                          onClick={() => { setTransferError(null); setTransferTarget(m) }}
                          className="text-muted-foreground hover:text-primary shrink-0"
                          aria-label={`Make ${m.email} owner`}
                          title={t('project_members.transfer')}
                          data-testid={`button-transfer-owner-${m.user_id}`}
                        >
                          <Crown className="w-3 h-3" />
                        </button>
                      )}
                      {/* Remove (owner can remove members, not the owner row itself) */}
                      {isOwner && m.role !== "owner" && (
                        <button
                          onClick={() => handleRemoveMember(m.user_id)}
                          className="text-muted-foreground hover:text-destructive shrink-0"
                          aria-label={`Remove ${m.email}`}
                          data-testid={`button-remove-member-${m.user_id}`}
                        >
                          <X className="w-3 h-3" />
                        </button>
                      )}
                    </div>
                  )
                })}
                {/* Leave project — visible to non-owner members */}
                {!isOwner && (
                  <button
                    onClick={handleLeaveProject}
                    className="mt-1 text-fs-xs text-muted-foreground hover:text-destructive"
                    data-testid="button-leave-project"
                  >
                    {t('project_members.leave')}
                  </button>
                )}
              </div>
            )}

            {/* Permissions summary removed at user request; server role checks remain in force. */}
          </div>}

          {activeTab !== "instructions" && <div className="border-t border-border p-4 shrink-0">
            <h4 className="font-medium text-xs uppercase tracking-wide text-muted-foreground mb-2">{tOr('projects.page.details', "Details")}</h4>
            <div className="space-y-1.5 text-xs">
              <div className="flex justify-between">
                <span className="text-muted-foreground flex items-center gap-1">
                  <Clock className="w-3 h-3" />{tOr('projects.page.created', "Created")}
                </span>
                <span>{new Date(project.createdAt).toLocaleDateString(locale === 'zh' ? 'zh-CN' : locale)}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">{tOr('projects.page.chats', "Chats")}</span>
                <span>{sessions.length > 0 ? sessions.length : "—"}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">{tOr('projects.page.runs', "Runs")}</span>
                <span>{runs.length > 0 ? runs.length : "—"}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">{tOr('projects.page.updated', "Updated")}</span>
                <span>{relTime((project as any).updatedAt ?? project.lastActivity)}</span>
              </div>
            </div>
          </div>}
        </div>
      </div>

      {/* Rename Dialog */}
      <Dialog open={renameOpen} onOpenChange={setRenameOpen}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader>
            <DialogTitle>{tOr('projects.page.rename_title', "Rename project")}</DialogTitle>
          </DialogHeader>
          <Input
            value={renameValue}
            onChange={e => setRenameValue(e.target.value)}
            placeholder={tOr('projects.page.name_placeholder', "Project name")}
            onKeyDown={e => e.key === "Enter" && handleRename()}
            autoFocus
          />
          <DialogFooter>
            <Button variant="outline" onClick={() => setRenameOpen(false)}>{tOr('projects.page.cancel', "Cancel")}</Button>
            <Button onClick={handleRename} disabled={actionLoading || !renameValue.trim()}>
              {actionLoading ? <Loader2 className="w-4 h-4 animate-spin" /> : tOr('projects.page.save', "Save")}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Archive Confirmation */}
      <AlertDialog open={archiveOpen} onOpenChange={setArchiveOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{tOr('projects.page.archive_title', "Archive this project?")}</AlertDialogTitle>
            <AlertDialogDescription>
              {tOr('projects.page.archive_body', "The project and its linked chats and runs will be archived. You can restore it later by changing its status.")}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{tOr('projects.page.cancel', "Cancel")}</AlertDialogCancel>
            <AlertDialogAction onClick={handleArchive} disabled={actionLoading}>
              {actionLoading ? tOr('projects.page.archiving', "Archiving\u2026") : tOr('projects.page.archive', "Archive")}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Delete Confirmation */}
      <AlertDialog open={deleteOpen} onOpenChange={setDeleteOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{tOr('projects.page.delete_title', "Delete this project?")}</AlertDialogTitle>
            <AlertDialogDescription>
              {tOr('projects.page.delete_body', "This permanently deletes the project and all linked data. This action cannot be undone.")}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{tOr('projects.page.cancel', "Cancel")}</AlertDialogCancel>
            <AlertDialogAction
              onClick={handleDelete}
              disabled={actionLoading}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              {actionLoading ? tOr('projects.page.deleting', "Deleting\u2026") : tOr('projects.page.delete', "Delete")}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Transfer ownership confirm */}
      <AlertDialog open={!!transferTarget} onOpenChange={(open) => { if (!open) { setTransferTarget(null); setTransferError(null) } }}>
        <AlertDialogContent data-testid="dialog-transfer-owner">
          <AlertDialogHeader>
            <AlertDialogTitle>{tOr('projects.page.transfer_title', "Transfer ownership?")}</AlertDialogTitle>
            <AlertDialogDescription>
              {tOr('projects.page.transfer_body', "This makes {{name}} the owner of this project. You will be demoted to an editor and lose owner-only controls. This cannot be undone by you.", { name: transferTarget?.fullName || transferTarget?.email || '' })}
            </AlertDialogDescription>
          </AlertDialogHeader>
          {transferError && <p className="text-xs text-destructive px-1">{transferError}</p>}
          <AlertDialogFooter>
            <AlertDialogCancel disabled={transferring}>{tOr('projects.page.cancel', "Cancel")}</AlertDialogCancel>
            <AlertDialogAction
              onClick={(e) => { e.preventDefault(); handleTransferOwnership() }}
              disabled={transferring}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
              data-testid="button-confirm-transfer-owner"
            >
              {transferring ? tOr('projects.page.transferring', "Transferring\u2026") : tOr('projects.page.transfer', "Transfer ownership")}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  )
}
