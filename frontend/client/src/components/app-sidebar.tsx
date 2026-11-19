import { useState, useEffect, useCallback } from "react"
import { useLocation } from "wouter"
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { SettingsDialog } from "./settings-dialog"
import { WorkflowHistoryDialog } from "./workflow-history-dialog"
import { WorkflowsLibraryDialog } from "./workflows-library-dialog"
import type { Project } from "@shared/schema"
import {
  MessageCircle,
  Plus,
  Settings,
  ChevronRight,
  ChevronDown,
  FileText,
  FolderOpen,
  PanelLeft,
  FlaskConical,
  Cable,
  Database,
  Layers,
  CreditCard,
  Wrench,
  Workflow,
  Server,
  Trash2,
  Check,
  X,
} from "lucide-react"
import { cn } from "@/lib/utils"
import { t, tOr } from "@/lib/i18n"
import { HintTip } from "@/components/ui/hint-tip"
import { chatHistoryService } from "@/lib/chat-history"
import { analytics } from "@/lib/analytics"
import { useActiveProject } from "@/contexts/active-project-context"
import { useAuth } from "@/contexts/auth-context"
import userAvatar from "@assets/generated_images/User_avatar_placeholder_d2803d15.png"
import { IND_REPORT_ENABLED } from "@/lib/feature-flags";

interface ToolItem {
  id: string
  name: string
  description: string
  complexity: 'simple' | 'intermediate' | 'complex'
  category: string
  icon: any
}

interface AppSidebarProps {
  onNewChat?: () => void
  onChatSelect?: (chatId: string) => void
  onToolSelect?: (tool: ToolItem) => void
  onProjectSelect?: (projectId: string) => void
  onNewProject?: () => void
  onToggleSidebar?: () => void
  activeChatId?: string
  activeCategory?: string
  activeTool?: string
  activeProjectId?: string
  chatSessions?: any[]
}

type SidebarChatRow = { session_id: string; title: string }

/**
 * A project's chats in the sidebar: the server's list for it, plus the chats this browser already
 * holds that were STARTED in it (`projectId` set at creation / first send). The server lists a chat
 * only after its session has synced and the list is refetched — "Run full QC" sat under "Other
 * chats" for ~46 s (2026-11-12 round 5). An untouched empty chat is not listed until it is used.
 */
export function projectChatRows(
  projectId: string, serverRows: SidebarChatRow[] | undefined, localSessions: any[], hidden: ReadonlySet<string>,
): SidebarChatRow[] {
  const rows = (serverRows ?? []).filter((r) => !hidden.has(r.session_id))
  const seen = new Set(rows.map((r) => r.session_id))
  const local = localSessions
    .filter((c) => c && c.projectId === projectId && !seen.has(c.id) && !hidden.has(c.id) && (c.messages?.length ?? 0) > 0)
    .map((c) => ({ session_id: String(c.id), title: String(c.title ?? "") }))
  return [...local, ...rows]
}

export function AppSidebar({ 
  onNewChat = () => console.log('New chat triggered'),
  onChatSelect = (id) => console.log('Chat selected:', id),
  onToolSelect = (tool) => console.log('Tool selected:', tool.name),
  onProjectSelect = (id) => console.log('Project selected:', id),
  onNewProject = () => console.log('New project triggered'),
  onToggleSidebar = () => console.log('Toggle sidebar triggered'),
  activeChatId,
  activeCategory,
  activeTool,
  activeProjectId,
  chatSessions = []
}: AppSidebarProps) {
  // Map chatSessionId → status dot ('running' | 'completed' | 'failed' | undefined).
  // Fetched from the run list API independently so no state lifting is needed.
  const [sessionStatusMap, setSessionStatusMap] = useState<Map<string, 'running' | 'completed' | 'failed' | 'cancelled'>>(new Map())
  const fetchSessionStatuses = useCallback(async () => {
    try {
      const res = await fetch('/api/workflows/runs?limit=50')
      if (!res.ok) return
      const runs: Array<{ id: string; chatSessionId?: string; execution?: { status?: string } }> = await res.json()
      const map = new Map<string, 'running' | 'completed' | 'failed' | 'cancelled'>()
      for (const run of runs) {
        if (!run.chatSessionId) continue
        const s = run.execution?.status ?? ''
        // A cancelled / paused run is NOT a failure — it gets its own neutral
        // bucket so the sidebar dot is grey, not red or (misleadingly) green
        // (UI refinement item 2).
        const bucket: 'running' | 'completed' | 'failed' | 'cancelled' =
          ['running', 'configuring', 'queued'].some(v => s.includes(v)) ? 'running'
          : ['failed', 'error'].some(v => s.includes(v)) ? 'failed'
          : ['cancelled', 'canceled', 'paused'].some(v => s.includes(v)) ? 'cancelled'
          : 'completed'
        // Prefer running > failed > cancelled > completed for a multi-run session.
        const existing = map.get(run.chatSessionId)
        if (!existing
            || bucket === 'running'
            || (bucket === 'failed' && existing !== 'running')
            || (bucket === 'cancelled' && (existing === 'completed'))) {
          map.set(run.chatSessionId, bucket)
        }
      }
      setSessionStatusMap(map)
    } catch { /* ignore */ }
  }, [])
  useEffect(() => {
    fetchSessionStatuses()
    const id = setInterval(fetchSessionStatuses, 15000)
    return () => clearInterval(id)
  }, [fetchSessionStatuses])
  const [projectsExpanded, setProjectsExpanded] = useState(true);
  const [showSettingsDialog, setShowSettingsDialog] = useState(false);
  const [showHistoryDialog, setShowHistoryDialog] = useState(false);
  const [historyInitialTab, setHistoryInitialTab] = useState<'runs' | 'imports' | 'upload'>('runs');
  const [showWorkflowsLibrary, setShowWorkflowsLibrary] = useState(false);
  const [runningCount, setRunningCount] = useState<number>(0);
  useEffect(() => {
    let cancelled = false;
    const tick = () => {
      fetch('/api/workflows/runs/overview?scope=all_chats&status=running&limit=1', { credentials: 'include' })
        .then((r) => r.ok ? r.json() : { total: 0 })
        .then((d) => { if (!cancelled) setRunningCount(d?.total ?? 0); })
        .catch(() => {});
    };
    tick();
    const id = setInterval(tick, 30000);
    return () => { cancelled = true; clearInterval(id); };
  }, []);

  const [, setLocation] = useLocation();
  const { user, logout } = useAuth();
  const { activeProjectId: contextProjectId, setActiveProjectId: setContextProjectId } = useActiveProject();
  const selectedProjectId = activeProjectId || contextProjectId;
  const [projectSessions, setProjectSessions] = useState<Record<string, Array<{ session_id: string; title: string }>>>({});

  // Per-chat delete: `confirmingDeleteChatId` drives the inline confirm (trash →
  // check/cancel); `deletedChatIds` optimistically hides a row the moment its
  // DELETE succeeds (the parent-owned `chatSessions` prop lags one render).
  const [confirmingDeleteChatId, setConfirmingDeleteChatId] = useState<string | null>(null);
  const [deletedChatIds, setDeletedChatIds] = useState<Set<string>>(new Set());
  const handleDeleteChat = useCallback(async (chatId: string) => {
    setConfirmingDeleteChatId(null);
    // Optimistically remove the row first so the UI feels instant.
    setDeletedChatIds(prev => new Set(prev).add(chatId));
    try {
      // Explicit, caller-driven backend delete (same philosophy as
      // fetchSessionDetail) — not gated on the background-sync flag. The route
      // (DELETE /api/sessions/:sessionId) scopes to the owner via the JWT.
      const res = await fetch(`/api/sessions/${encodeURIComponent(chatId)}`, {
        method: 'DELETE',
        credentials: 'include',
      });
      if (!res.ok && res.status !== 404) {
        // Roll back the optimistic hide on a real server error.
        setDeletedChatIds(prev => { const n = new Set(prev); n.delete(chatId); return n; });
        return;
      }
    } catch {
      setDeletedChatIds(prev => { const n = new Set(prev); n.delete(chatId); return n; });
      return;
    }
    // Keep localStorage truthful so the parent's next getAllSessions() won't
    // resurrect the row (backend already deleted above — local-only purge).
    chatHistoryService.removeSessionLocal(chatId);
    // If we just deleted the chat the user is viewing, start a fresh chat.
    if (activeChatId === chatId) onNewChat();
  }, [activeChatId, onNewChat]);

  // Projects — fetched from API (not localStorage) so they survive page reload
  const [apiProjects, setApiProjects] = useState<Array<{ id: string; name: string; status: string; userId?: string }>>([]);
  const [expandedProjectIds, setExpandedProjectIds] = useState<Set<string>>(new Set());
  // Per-project chat lists the user folded (founder: "make chat list foldable"); remembered locally.
  const [collapsedChatLists, setCollapsedChatLists] = useState<Set<string>>(() => {
    try { return new Set(JSON.parse(localStorage.getItem('biomate.sidebar.foldedChatLists') || '[]')); } catch { return new Set(); }
  });
  useEffect(() => {
    try { localStorage.setItem('biomate.sidebar.foldedChatLists', JSON.stringify(Array.from(collapsedChatLists))); } catch { /* private mode */ }
  }, [collapsedChatLists]);
  useEffect(() => {
    let cancelled = false;
    const ids = Array.from(expandedProjectIds);
    Promise.allSettled(ids.map(async id => {
      const response = await fetch(`/api/projects/${encodeURIComponent(id)}/sessions`, { credentials: 'include' });
      if (!response.ok) return;
      const data = await response.json();
      if (!cancelled) setProjectSessions(prev => ({ ...prev, [id]: data.sessions || [] }));
    }));
    return () => { cancelled = true; };
  }, [expandedProjectIds, activeChatId]);
  useEffect(() => {
    if (selectedProjectId) setExpandedProjectIds(prev => new Set([...prev, selectedProjectId]));
  }, [selectedProjectId]);
  const refreshProjects = () => {
    fetch("/api/projects", { credentials: "include" })
      .then((r) => r.ok ? r.json() : { projects: [] })
      // Archived projects are soft-deleted — never show them in the sidebar.
      // (The API returns all statuses when unfiltered; keep active/completed only.)
      .then((d) => setApiProjects(
        (d.projects ?? [])
          .filter((p: { status?: string }) => p.status !== "archived")
          .slice(0, 12)
      ))
      .catch(() => {});
  };
  useEffect(() => {
    refreshProjects();
    window.addEventListener('biomate:projects-updated', refreshProjects);
    return () => window.removeEventListener('biomate:projects-updated', refreshProjects);
  }, []);

  function getRelativeTime(date: Date): string {
    const now = new Date()
    const diffMs = now.getTime() - new Date(date).getTime()
    const diffHours = Math.floor(diffMs / (1000 * 60 * 60))
    const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24))
    
    if (diffHours < 1) return 'Just now'
    if (diffHours < 24) return `${diffHours} hour${diffHours > 1 ? 's' : ''} ago`
    if (diffDays < 7) return `${diffDays} day${diffDays > 1 ? 's' : ''} ago`
    return `${Math.floor(diffDays / 7)} week${Math.floor(diffDays / 7) > 1 ? 's' : ''} ago`
  }

  // Chats started in a project the sidebar lists show under that project at once (projectChatRows),
  // never first under "Other chats" until the server's per-project list catches up.
  // (Only an EXPANDED project shows its chats — a collapsed one's stay under "Other chats", as before.)
  const listedProjectIds = new Set(apiProjects.map((p) => p.id).filter((id) => expandedProjectIds.has(id)))
  const filedInListedProject = new Set(
    chatSessions.filter((c: any) => c && typeof c.projectId === "string" && listedProjectIds.has(c.projectId) && (c.messages?.length ?? 0) > 0).map((c: any) => String(c.id)),
  )
  // Use chat sessions from props; empty list until backend syncs (no mock fallback)
  const recentChats = [...chatSessions]
    .sort((a, b) => new Date(b.lastActivity ?? 0).getTime() - new Date(a.lastActivity ?? 0).getTime())
    .slice(0, 20).map(session => ({
    id: session.id,
    title: session.title,
    timestamp: getRelativeTime(session.lastActivity)
  }));
  return (
    <div className="h-full flex flex-col" style={{
      background: 'var(--bm-surface, hsl(var(--sidebar)))',
      borderRight: '1px solid var(--bm-border, hsl(var(--border)))',
      padding: '14px 10px',
      gap: 0,
      width: '100%',
      minWidth: 0,
      overflow: 'hidden',
    }}>
      {/* Brand — full-width logo header (matches Research Agent UI design).
          Negates the sidebar's 14/10px padding so the image touches both
          column edges. Beta chip overlays the top-right; collapse button overlays
          the top-right corner. */}
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          gap: 8,
          padding: '10px 12px',
          margin: '-14px -10px 12px',
          borderBottom: '1px solid var(--bm-border, hsl(var(--border)))',
          background: 'var(--bm-bg-elev, white)',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 7, minWidth: 0 }}>
          <img
            src="/biomate-logo.png"
            alt="BioMate"
            style={{ height: 26, width: 'auto', display: 'block', flexShrink: 0 }}
          />
          {/* BETA tag restored 2026-11-01 (per user request — re-add it back).
              Reverts the 2026-10-20 "refinement 1c" removal. */}
          <HintTip hint={t('nav.beta_tooltip')} side="bottom">
          <span
            style={{
              flexShrink: 0,
              fontSize: 'var(--fs-xs)',
              fontWeight: 700,
              letterSpacing: '0.08em',
              textTransform: 'uppercase',
              color: 'var(--bm-accent, hsl(var(--primary)))',
              background: 'var(--bm-accent-soft, hsl(var(--primary) / 0.1))',
              border: '1px solid var(--bm-accent, hsl(var(--primary) / 0.3))',
              borderRadius: 4,
              padding: '1px 5px',
              lineHeight: 1.4,
            }}
          >
            BETA
          </span>
          </HintTip>
        </div>
        <HintTip hint={t('hint.nav.collapse')} side="bottom">
        <button
          onClick={onToggleSidebar}
          aria-label={t('nav.collapse_sidebar')}
          data-testid="button-sidebar-toggle"
          style={{
            background: 'transparent', border: 'none', padding: 4,
            borderRadius: 4, cursor: 'pointer', color: 'var(--bm-text-dim)',
            flexShrink: 0,
          }}
        >
          <PanelLeft className="h-4 w-4" />
        </button>
        </HintTip>
      </div>

      {/* Workspace nav */}
      <div style={{ marginBottom: 8 }}>
        <div style={{ fontSize: 'var(--fs-xs)', textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--bm-text-dim)', padding: '0 10px', marginBottom: 4, fontWeight: 600 }}>{t('nav.workspace')}</div>
        {/* Top "New Chat" removed per founder request — it was redundant with the
            per-project New Chat and the collapsed-rail New Chat icon (App.tsx). A
            standalone new chat is still reachable from the collapsed sidebar rail. */}
        {/* Data — the dataset object is a first-class surface (spec 04). */}
        <HintTip hint={t('hint.nav.data')}>
        <button className="side-link" data-testid="button-data-nav" style={{ display: 'flex', alignItems: 'flex-start', gap: 9, padding: '6px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 'var(--fs-meta)', cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }} onClick={() => setLocation('/files')}>
          <Database className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0, marginTop: 2 }} />
          <span style={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
            <span>{t('nav.data')}</span>
          </span>
        </button>
        </HintTip>

        {/* Workflows — unified library: ranked catalog search + the user's
            uploaded/personal workflows + upload. Opens WorkflowsLibraryDialog
            (replaces the dead StarredWorkflowsDialog). */}
        <HintTip hint={t('hint.nav.workflows')}>
        <button className="side-link" data-testid="button-workflows-nav" style={{ display: 'flex', alignItems: 'flex-start', gap: 9, padding: '6px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 'var(--fs-meta)', cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }} onClick={() => setShowWorkflowsLibrary(true)}>
          <Workflow className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0, marginTop: 2 }} />
          <span style={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
            <span>{tOr('nav.workflows', 'Workflows')}</span>
          </span>
        </button>
        </HintTip>



        {/* IND Report is paused — see IND_REPORT_ENABLED (feature-flags.ts). */}
        {IND_REPORT_ENABLED && (<button className="side-link" data-testid="button-ind-report" style={{ display: 'flex', alignItems: 'flex-start', gap: 9, padding: '6px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 'var(--fs-meta)', cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }} onClick={() => setLocation('/ind-report')}>
          <FileText className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0, marginTop: 2 }} />
          <span style={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
            <span>IND Report</span>
          </span>
        </button>)}

        <HintTip hint={t('hint.nav.models')}>
        <button className="side-link" data-testid="button-models-nav" style={{ display: 'flex', alignItems: 'flex-start', gap: 9, padding: '6px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 'var(--fs-meta)', cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }} onClick={() => setLocation('/models')}>
          <Layers className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0, marginTop: 2 }} />
          <span style={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
            <span>{t('nav.models')}</span>
          </span>
        </button>
        </HintTip>


        {/* Billing hidden — /billing page crashes (BillingPage toFixed on undefined).
            Restore this nav entry once the page is hardened. */}
        {/* <button className="side-link" data-testid="button-billing-nav" style={{ display: 'flex', alignItems: 'flex-start', gap: 9, padding: '6px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 'var(--fs-meta)', cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }} onClick={() => setLocation('/billing')}>
          <CreditCard className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0, marginTop: 2 }} />
          <span style={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
            <span>{t('nav.billing')}</span>
          </span>
        </button> */}
      </div>

      {/* Projects section — always visible */}
      <div style={{ marginBottom: 8, borderTop: '1px solid var(--bm-border)', paddingTop: 8, maxHeight: '50vh', overflowY: 'auto', flexShrink: 1 }}>
          <div style={{ display: 'flex', alignItems: 'center', padding: '0 6px 4px 10px' }}>
          <HintTip hint={t('hint.nav.projects')}>
          <button
            style={{ display: 'flex', alignItems: 'center', gap: 6, flex: 1, minWidth: 0, fontSize: 'var(--fs-xs)', textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--bm-text-dim)', fontWeight: 600, background: 'transparent', border: 'none', cursor: 'pointer', textAlign: 'left' }}
            onClick={() => setProjectsExpanded(p => !p)}
            data-testid="button-projects-section"
          >
            {projectsExpanded ? <ChevronDown className="w-3 h-3" /> : <ChevronRight className="w-3 h-3" />}
            <FolderOpen className="w-3 h-3" style={{ opacity: 0.7 }} />
            {t('nav.projects')}
          </button>
          </HintTip>
          <HintTip hint={t('hint.nav.new_project')}>
          <button
            style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 3, borderRadius: 4, color: 'var(--bm-text-dim)', background: 'transparent', border: 'none', cursor: 'pointer', flexShrink: 0 }}
            onClick={onNewProject}
            data-testid="button-new-project"
            aria-label={t('nav.new_project')}
          >
            <Plus className="w-3.5 h-3.5" style={{ opacity: 0.7 }} />
          </button>
          </HintTip>
          </div>
          {projectsExpanded && apiProjects.map((proj) => {
            const isExpanded = expandedProjectIds.has(proj.id);
            return (
              <div key={proj.id}>
                <HintTip hint={`${proj.name} — ${t('hint.nav.project_row')}`}>
                <button
                  style={{ display: 'flex', alignItems: 'center', gap: 7, padding: '4px 10px', borderRadius: 5, color: selectedProjectId === proj.id ? 'var(--bm-text)' : 'var(--bm-text-muted)', background: selectedProjectId === proj.id ? 'var(--bm-surface-3)' : 'transparent', fontSize: 'var(--fs-meta)', cursor: 'pointer', border: 'none', width: '100%', textAlign: 'left' }}
                  onClick={() => { setContextProjectId(proj.id); setExpandedProjectIds(prev => { const n = new Set(prev); if (n.has(proj.id)) n.delete(proj.id); else n.add(proj.id); return n; }); }}
                  data-testid={`button-project-${proj.id}`}
                >
                  {isExpanded ? <ChevronDown className="w-3 h-3 shrink-0" /> : <ChevronRight className="w-3 h-3 shrink-0" />}
                  <FolderOpen className="w-3.5 h-3.5 shrink-0" style={{ color: selectedProjectId === proj.id ? 'var(--bm-accent, oklch(0.55 0.14 245))' : 'var(--bm-text-dim)', opacity: 0.8 }} />
                  <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{proj.name}</span>
                  {proj.userId && user && proj.userId !== user.id && (
                    <span style={{ fontSize: 'var(--fs-xs)', fontWeight: 600, letterSpacing: '0.04em', textTransform: 'uppercase', color: 'var(--bm-accent, oklch(0.55 0.14 245))', opacity: 0.8, flexShrink: 0 }}>{tOr('nav.shared', 'shared')}</span>
                  )}
                </button>
                </HintTip>
                {isExpanded && (
                  <div style={{ paddingLeft: 28 }}>
                    {/* Project-child rows render in the design's accent blue (UI
                        refinement 1b) rather than muted gray. Active chat keeps its
                        background highlight. */}
                    <HintTip hint={t('hint.nav.project_instructions')}>
                    <button className="side-link" style={{ display: 'flex', gap: 6, padding: '3px 10px', fontSize: 'var(--fs-micro)', width: '100%', textAlign: 'left', color: 'var(--bm-accent, oklch(0.55 0.14 245))' }} onClick={() => { setContextProjectId(proj.id); setLocation(`/projects?project=${proj.id}&tab=instructions`); }} data-testid={`project-link-instructions-${proj.id}`}><Settings className="w-3 h-3" />{t("project_instructions.instructions")}</button>
                    </HintTip>
                    <HintTip hint={t('hint.nav.project_files')}>
                    <button style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '3px 10px', fontSize: 'var(--fs-micro)', color: 'var(--bm-accent, oklch(0.55 0.14 245))', background: 'transparent', border: 'none', cursor: 'pointer', width: '100%', borderRadius: 4 }} onClick={() => (() => { setContextProjectId(proj.id); setLocation("/files"); })()} data-testid={`project-link-files-${proj.id}`}>
                      <FileText className="w-3 h-3 shrink-0" style={{ opacity: 0.7 }} />
                      {t("project_instructions.files")}
                    </button>
                    </HintTip>
                    {/* Project Runs navigation hidden: executions are accessible from their chats. */}
                    {/* Chats folder header with an inline "+" new-chat (concise); the list folds under it. */}
                    <div style={{ display: 'flex', alignItems: 'center' }}>
                      <button
                        type="button"
                        className="side-link"
                        style={{ display: 'flex', alignItems: 'center', gap: 6, flex: 1, minWidth: 0, padding: '3px 10px', fontSize: 'var(--fs-micro)', textAlign: 'left', color: 'var(--bm-text-dim)', background: 'transparent', border: 'none', cursor: 'pointer' }}
                        aria-expanded={!collapsedChatLists.has(proj.id)}
                        onClick={() => setCollapsedChatLists(prev => { const n = new Set(prev); if (n.has(proj.id)) n.delete(proj.id); else n.add(proj.id); return n; })}
                        data-testid={`project-chats-toggle-${proj.id}`}
                      >
                        {collapsedChatLists.has(proj.id) ? <ChevronRight className="w-3 h-3 shrink-0" /> : <ChevronDown className="w-3 h-3 shrink-0" />}
                        {t('nav.project_chats', { n: projectChatRows(proj.id, projectSessions[proj.id], chatSessions, deletedChatIds).length })}
                      </button>
                      <HintTip hint={t('hint.nav.project_new_chat')}>
                      <button
                        style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 3, marginRight: 4, borderRadius: 4, color: 'var(--bm-accent, oklch(0.55 0.14 245))', background: 'transparent', border: 'none', cursor: 'pointer', flexShrink: 0 }}
                        data-testid={`project-new-chat-${proj.id}`}
                        onClick={() => { setContextProjectId(proj.id); onNewChat(); }}
                        aria-label={t("New Chat")}
                      ><Plus className="w-3.5 h-3.5" /></button>
                      </HintTip>
                    </div>
                    {!collapsedChatLists.has(proj.id) && projectChatRows(proj.id, projectSessions[proj.id], chatSessions, deletedChatIds).map(chat => {
                      const isConfirming = confirmingDeleteChatId === chat.session_id;
                      const isActive = activeChatId === chat.session_id;
                      return (
                        <div key={chat.session_id} className="sidebar-chat-row" data-testid={`project-chat-row-${chat.session_id}`} style={{ display: 'flex', alignItems: 'center', gap: 4, borderRadius: 5, background: isActive ? 'var(--bm-bg-elev)' : 'transparent' }}>
                          <HintTip hint={chat.title}>
                          <button data-testid={`button-project-chat-${chat.session_id}`} onClick={() => { setContextProjectId(proj.id); onChatSelect(chat.session_id); }} style={{ display: 'flex', alignItems: 'center', gap: 7, padding: '5px 10px', borderRadius: 5, fontSize: 'var(--fs-meta)', flex: 1, minWidth: 0, textAlign: 'left', color: 'var(--bm-accent, oklch(0.55 0.14 245))', background: 'transparent', border: 'none', cursor: 'pointer' }}>
                            <span style={{ flexShrink: 0 }}>·</span>
                            <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{chat.title}</span>
                          </button>
                          </HintTip>
                          {isConfirming ? (
                            <span style={{ display: 'flex', alignItems: 'center', gap: 2, flexShrink: 0, paddingRight: 6 }}>
                              <HintTip hint={tOr('chat.delete_confirm', 'Delete chat')} side="top">
                              <button onClick={() => handleDeleteChat(chat.session_id)} data-testid={`confirm-delete-chat-${chat.session_id}`} aria-label={tOr('chat.delete_confirm', 'Delete chat')} style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 3, border: 'none', borderRadius: 4, background: 'transparent', cursor: 'pointer', color: 'var(--bm-err, oklch(0.58 0.18 25))' }}><Check className="w-3.5 h-3.5" /></button>
                              </HintTip>
                              <HintTip hint={tOr('common.cancel', 'Cancel')} side="top">
                              <button onClick={() => setConfirmingDeleteChatId(null)} data-testid={`cancel-delete-chat-${chat.session_id}`} aria-label={tOr('common.cancel', 'Cancel')} style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 3, border: 'none', borderRadius: 4, background: 'transparent', cursor: 'pointer', color: 'var(--bm-text-dim)' }}><X className="w-3.5 h-3.5" /></button>
                              </HintTip>
                            </span>
                          ) : (
                            <HintTip hint={tOr('chat.delete_chat', 'Delete chat')} side="top">
                            <button onClick={(e) => { e.stopPropagation(); setConfirmingDeleteChatId(chat.session_id); }} data-testid={`button-delete-project-chat-${chat.session_id}`} aria-label={tOr('chat.delete_chat', 'Delete chat')} className="sidebar-chat-delete" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 3, marginRight: 6, border: 'none', borderRadius: 4, background: 'transparent', cursor: 'pointer', color: 'var(--bm-text-dim)', opacity: 0.55, flexShrink: 0 }}><Trash2 className="w-3.5 h-3.5" /></button>
                            </HintTip>
                          )}
                        </div>
                      );
                    })}
                  </div>
                )}
              </div>
            );
          })}
        </div>

      {/* Chat history — scrollable, takes remaining space */}
      <div style={{ flex: 1, overflowY: 'auto', minHeight: 0 }}>
        {recentChats.length > 0 && (
          <>
            <button
              type="button"
              onClick={() => setCollapsedChatLists(prev => { const n = new Set(prev); if (n.has('__other__')) n.delete('__other__'); else n.add('__other__'); return n; })}
              aria-expanded={!collapsedChatLists.has('__other__')}
              data-testid="other-chats-toggle"
              style={{ display: 'flex', alignItems: 'center', gap: 6, width: '100%', background: 'transparent', border: 'none', cursor: 'pointer', textAlign: 'left', fontSize: 'var(--fs-xs)', textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--bm-text-dim)', padding: '0 10px', marginBottom: 4, fontWeight: 600, marginTop: 8 }}
            >
              {collapsedChatLists.has('__other__') ? <ChevronRight className="w-3 h-3" /> : <ChevronDown className="w-3 h-3" />}
              {t('nav.other_chats')}
            </button>
            {!collapsedChatLists.has('__other__') && recentChats.filter(chat => !deletedChatIds.has(chat.id) && !filedInListedProject.has(chat.id) && !Object.values(projectSessions).some(sessions => sessions.some(session => session.session_id === chat.id))).slice(0, 12).map((chat) => {
              const dotStatus = sessionStatusMap.get(chat.id)
              const isActive = activeChatId === chat.id
              const isConfirming = confirmingDeleteChatId === chat.id
              return (
                <div
                  key={chat.id}
                  className="sidebar-chat-row"
                  data-testid={`chat-row-${chat.id}`}
                  style={{
                    display: 'flex', alignItems: 'center', gap: 4,
                    borderRadius: 6,
                    background: isActive ? 'var(--bm-surface-3, oklch(0.945 0.005 240))' : 'transparent',
                  }}
                >
                  <HintTip hint={`${chat.title} — ${t(`hint.chat_status.${dotStatus || 'idle'}`)}`}>
                  <button
                    onClick={() => onChatSelect(chat.id)}
                    data-testid={`button-chat-${chat.id}`}
                    style={{
                      display: 'flex', alignItems: 'center', gap: 9,
                      padding: '5px 10px', borderRadius: 6,
                      color: isActive ? 'var(--bm-text)' : 'var(--bm-text-muted)',
                      background: 'transparent',
                      fontWeight: isActive ? 500 : 400,
                      fontSize: 'var(--fs-meta)', cursor: 'pointer', border: 'none',
                      flex: 1, minWidth: 0, textAlign: 'left',
                    }}
                  >
                    <span style={{
                      width: 8, height: 8, borderRadius: '50%', flexShrink: 0,
                      background: dotStatus === 'running' ? 'var(--bm-accent, oklch(0.55 0.14 245))' :
                                  dotStatus === 'failed'  ? 'var(--bm-err, oklch(0.58 0.18 25))' :
                                  dotStatus === 'cancelled' ? 'var(--bm-text-dim, oklch(0.62 0.01 260))' :
                                  dotStatus === 'completed' ? 'var(--bm-ok, oklch(0.62 0.13 150))' :
                                  'var(--bm-border-strong, oklch(0.80 0.008 240))',
                      animation: dotStatus === 'running' ? 'pulse 1.5s infinite' : 'none',
                    }} data-status={dotStatus || 'idle'} data-testid={`history-dot-${chat.id}`} />
                    <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{chat.title}</span>
                  </button>
                  </HintTip>
                  {isConfirming ? (
                    <span style={{ display: 'flex', alignItems: 'center', gap: 2, flexShrink: 0, paddingRight: 6 }}>
                      <HintTip hint={tOr('chat.delete_confirm', 'Delete chat')} side="top">
                      <button
                        onClick={() => handleDeleteChat(chat.id)}
                        data-testid={`confirm-delete-chat-${chat.id}`}
                        aria-label={tOr('chat.delete_confirm', 'Delete chat')}
                        style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 3, border: 'none', borderRadius: 4, background: 'transparent', cursor: 'pointer', color: 'var(--bm-err, oklch(0.58 0.18 25))' }}
                      >
                        <Check className="w-3.5 h-3.5" />
                      </button>
                      </HintTip>
                      <HintTip hint={tOr('common.cancel', 'Cancel')} side="top">
                      <button
                        onClick={() => setConfirmingDeleteChatId(null)}
                        data-testid={`cancel-delete-chat-${chat.id}`}
                        aria-label={tOr('common.cancel', 'Cancel')}
                        style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 3, border: 'none', borderRadius: 4, background: 'transparent', cursor: 'pointer', color: 'var(--bm-text-dim)' }}
                      >
                        <X className="w-3.5 h-3.5" />
                      </button>
                      </HintTip>
                    </span>
                  ) : (
                    <HintTip hint={tOr('chat.delete_chat', 'Delete chat')} side="top">
                    <button
                      onClick={(e) => { e.stopPropagation(); setConfirmingDeleteChatId(chat.id); }}
                      data-testid={`button-delete-chat-${chat.id}`}
                      aria-label={tOr('chat.delete_chat', 'Delete chat')}
                      className="sidebar-chat-delete"
                      style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 3, marginRight: 6, border: 'none', borderRadius: 4, background: 'transparent', cursor: 'pointer', color: 'var(--bm-text-dim)', opacity: 0.55, flexShrink: 0 }}
                    >
                      <Trash2 className="w-3.5 h-3.5" />
                    </button>
                    </HintTip>
                  )}
                </div>
              )
            })}

          </>
        )}
        {recentChats.length === 0 && (
          <div style={{ padding: '10px', fontSize: 'var(--fs-meta)', color: 'var(--bm-text-dim)', textAlign: 'center' }}>
            {t('No chats yet')}
          </div>
        )}

        {/* One Settings entry; imports and connectors live inside its panel. */}
        <div style={{ marginTop: 12, borderTop: '1px solid var(--bm-border)', paddingTop: 8 }}>
          <HintTip hint={t('hint.nav.settings')}>
          <button
            style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '5px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 'var(--fs-meta)', cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }}
            onClick={() => { analytics.track('settings_opened'); setShowSettingsDialog(true); }}
            data-testid="button-settings-sidebar"
          >
            <Settings className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0 }} />
            <span>{t('settings.title')}</span>
          </button>
          </HintTip>
          {user?.subscriptionTier === 'admin' && (
            <HintTip hint={t('hint.nav.admin')}>
            <button
              style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '5px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 'var(--fs-meta)', cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }}
              onClick={() => setLocation('/admin')}
              data-testid="button-admin-dashboard"
            >
              <Server className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0 }} />
              <span>{t('nav.admin')}</span>
            </button>
            </HintTip>
          )}
        </div>
      </div>

      {/* Footer */}
      <div style={{ borderTop: '1px solid var(--bm-border)', padding: '10px 10px 4px', display: 'flex', alignItems: 'center', gap: 9 }}>
        <div style={{
          width: 26, height: 26, borderRadius: '50%',
          background: 'oklch(0.85 0.05 60)', color: 'oklch(0.35 0.08 60)',
          display: 'grid', placeItems: 'center', fontSize: 'var(--fs-micro)', fontWeight: 600, flexShrink: 0,
        }}>
          {user?.name ? user.name.split(' ').map(w => w[0]).join('').slice(0, 2).toUpperCase() : 'U'}
        </div>
        <div style={{ flex: 1, minWidth: 0, lineHeight: 1.2 }}>
          <div style={{ fontWeight: 500, fontSize: 'var(--fs-meta)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', color: 'var(--bm-text)' }}>{user?.name || user?.email?.split('@')[0] || 'Researcher'}</div>
          <div style={{ color: 'var(--bm-text-dim)', fontSize: 'var(--fs-micro)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{user?.email || 'researcher@biomate.ai'}</div>
        </div>

        <HintTip hint={t('hint.nav.sign_out')} side="top">
        <button
          onClick={async () => { await logout(); setLocation('/login'); }}
          data-testid="button-logout"
          style={{
            flexShrink: 0, border: 'none', background: 'transparent', cursor: 'pointer',
            padding: '4px 8px', borderRadius: 6, fontSize: 'var(--fs-micro)', color: 'var(--bm-text-muted)',
          }}
        >
          {t('nav.sign_out')}
        </button>
        </HintTip>
      </div>

      {/* Dialogs */}
      <SettingsDialog open={showSettingsDialog} onOpenChange={setShowSettingsDialog} onImportWorkflow={() => { setShowSettingsDialog(false); setHistoryInitialTab("upload"); setShowHistoryDialog(true); }} />
      <WorkflowHistoryDialog open={showHistoryDialog} onOpenChange={setShowHistoryDialog} initialTab={historyInitialTab} importOnly onOpenRun={(row) => { if (row.chatSessionId) { window.location.assign(`/?session=${encodeURIComponent(row.chatSessionId)}`); } }} onRunAgain={(row) => { window.location.assign(`/?reuseWorkflow=${encodeURIComponent(row.runId)}`); }} />
      <WorkflowsLibraryDialog open={showWorkflowsLibrary} onOpenChange={setShowWorkflowsLibrary} />

    </div>
  )
}

