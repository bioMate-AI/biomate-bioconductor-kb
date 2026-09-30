import { useState, useEffect, useCallback } from "react"
import { useLocation } from "wouter"
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { SettingsDialog } from "./settings-dialog"
import { WorkflowHistoryDialog } from "./workflow-history-dialog"
import { RecentToolsDialog } from "./recent-tools-dialog"
import { ConnectorsDialog } from "./connectors-dialog"
import { projectService } from "@/lib/projects"
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
} from "lucide-react"
import { cn } from "@/lib/utils"
import { t } from "@/lib/i18n"
import { analytics } from "@/lib/analytics"
import { useAuth } from "@/contexts/auth-context"
import userAvatar from "@assets/generated_images/User_avatar_placeholder_d2803d15.png"

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
  const [sessionStatusMap, setSessionStatusMap] = useState<Map<string, 'running' | 'completed' | 'failed'>>(new Map())
  const fetchSessionStatuses = useCallback(async () => {
    try {
      const res = await fetch('/api/workflows/runs?limit=50')
      if (!res.ok) return
      const runs: Array<{ id: string; chatSessionId?: string; execution?: { status?: string } }> = await res.json()
      const map = new Map<string, 'running' | 'completed' | 'failed'>()
      for (const run of runs) {
        if (!run.chatSessionId) continue
        const s = run.execution?.status ?? ''
        const bucket: 'running' | 'completed' | 'failed' =
          ['running', 'configuring', 'queued'].some(v => s.includes(v)) ? 'running'
          : ['failed', 'error'].some(v => s.includes(v)) ? 'failed'
          : s === 'completed' ? 'completed'
          : 'completed'
        // Prefer 'running' > 'failed' > 'completed' for a session with multiple runs
        const existing = map.get(run.chatSessionId)
        if (!existing || bucket === 'running' || (bucket === 'failed' && existing === 'completed')) {
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

  const [showConnectorsDialog, setShowConnectorsDialog] = useState(false);
  const [showRecentToolsDialog, setShowRecentToolsDialog] = useState(false);
  const [, setLocation] = useLocation();
  const { user, logout } = useAuth();

  // Projects — fetched from API (not localStorage) so they survive page reload
  const [apiProjects, setApiProjects] = useState<Array<{ id: string; name: string; status: string; userId?: string }>>([]);
  const [expandedProjectIds, setExpandedProjectIds] = useState<Set<string>>(new Set());
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
  const recentProjects = projectService.getAllProjects().slice(0, 5);

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
          position: 'relative',
          display: 'block',
          padding: 0,
          margin: '-14px -10px 12px',
          borderBottom: '1px solid var(--bm-border, hsl(var(--border)))',
          background: 'var(--bm-bg-elev, white)',
          width: 'auto',
        }}
      >
        <img
          src="/biomate-logo.png"
          alt="BioMate"
          style={{ display: 'block', width: '100%', height: 'auto', objectFit: 'cover' }}
        />
        <span
          title="Early-access beta — features may change"
          style={{
            position: 'absolute',
            top: 6,
            right: 30,
            fontSize: 9.5,
            fontWeight: 700,
            letterSpacing: '0.06em',
            textTransform: 'uppercase',
            padding: '1px 5px',
            borderRadius: 3,
            background: 'oklch(0.78 0.15 65)',
            color: '#fff',
            lineHeight: 1.3,
            boxShadow: '0 1px 3px rgba(0,0,0,0.15)',
          }}
        >
          BETA
        </span>
        <button
          onClick={onToggleSidebar}
          data-testid="button-sidebar-toggle"
          style={{
            position: 'absolute', top: 4, right: 4,
            background: 'rgba(255,255,255,0.85)', border: 'none', padding: 4,
            borderRadius: 4, cursor: 'pointer', color: 'var(--bm-text-dim)',
            backdropFilter: 'blur(4px)',
          }}
          title="Collapse sidebar"
        >
          <PanelLeft className="h-4 w-4" />
        </button>
      </div>

      {/* Workspace nav */}
      <div style={{ marginBottom: 8 }}>
        <div style={{ fontSize: 10.5, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--bm-text-dim)', padding: '0 10px', marginBottom: 4, fontWeight: 600 }}>Workspace</div>
        <button className="side-link" onClick={onNewChat} data-testid="button-new-chat" style={{ display: 'flex', alignItems: 'flex-start', gap: 9, padding: '6px 10px', borderRadius: 6, color: 'var(--bm-text-muted, oklch(0.48 0.012 260))', fontSize: 13, cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }}>
          <Plus className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0, marginTop: 2 }} />
          <span style={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
            <span>{t('chat.new_chat')}</span>
            <span style={{ fontSize: 11, color: 'var(--bm-text-dim)', fontWeight: 400 }}>Start a fresh AI conversation</span>
          </span>
        </button>
        <button
          className="side-link"
          data-testid="button-workflows-nav"
          style={{ display: 'flex', alignItems: 'flex-start', gap: 9, padding: '6px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 13, cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }}
          onClick={() => { analytics.track('workflows_sidebar_opened'); setHistoryInitialTab('runs'); setShowHistoryDialog(true); }}
        >
          <FlaskConical className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0, marginTop: 2 }} />
          <span style={{ display: 'flex', flexDirection: 'column', gap: 1, flex: 1 }}>
            <span style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
              {t('nav.workflows')}
              {runningCount > 0 && (<span data-testid="workflows-running-badge" style={{ fontSize: 10, fontWeight: 600, padding: '1px 6px', borderRadius: 999, background: 'oklch(0.92 0.04 230)', color: 'oklch(0.40 0.13 230)' }}>{runningCount}</span>)}
            </span>
            <span style={{ fontSize: 11, color: 'var(--bm-text-dim)', fontWeight: 400 }}>Run history, browse & import pipelines</span>
          </span>
        </button>
        <button
          className="side-link"
          data-testid="button-connectors-nav"
          style={{ display: 'flex', alignItems: 'flex-start', gap: 9, padding: '6px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 13, cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }}
          onClick={() => setShowConnectorsDialog(true)}
        >
          <Cable className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0, marginTop: 2 }} />
          <span style={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
            <span>Connectors</span>
            <span style={{ fontSize: 11, color: 'var(--bm-text-dim)', fontWeight: 400 }}>Databases, LLMs & platform integrations</span>
          </span>
        </button>
        {/* IND Report hidden from sidebar for now (per request 2026-09-22). Route still exists. */}
        {/* <button className="side-link" data-testid="button-ind-report" style={{ display: 'flex', alignItems: 'flex-start', gap: 9, padding: '6px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 13, cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }} onClick={() => setLocation('/ind-report')}>
          <FileText className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0, marginTop: 2 }} />
          <span style={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
            <span>IND Report</span>
            <span style={{ fontSize: 11, color: 'var(--bm-text-dim)', fontWeight: 400 }}>Generate regulatory submission documents</span>
          </span>
        </button> */}
        <button className="side-link" data-testid="button-data-nav" style={{ display: 'flex', alignItems: 'flex-start', gap: 9, padding: '6px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 13, cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }} onClick={() => setLocation('/files')}>
          <Database className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0, marginTop: 2 }} />
          <span style={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
            <span>Data</span>
            <span style={{ fontSize: 11, color: 'var(--bm-text-dim)', fontWeight: 400 }}>Datasets, quality & lineage</span>
          </span>
        </button>
        <button className="side-link" data-testid="button-models-nav" style={{ display: 'flex', alignItems: 'flex-start', gap: 9, padding: '6px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 13, cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }} onClick={() => setLocation('/models')}>
          <Layers className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0, marginTop: 2 }} />
          <span style={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
            <span>Models</span>
            <span style={{ fontSize: 11, color: 'var(--bm-text-dim)', fontWeight: 400 }}>Train, adapt & run models · registry</span>
          </span>
        </button>
        <button className="side-link" data-testid="button-design-generate-nav" style={{ display: 'flex', alignItems: 'flex-start', gap: 9, padding: '6px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 13, cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }} onClick={() => setLocation('/design')}>
          <FlaskConical className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0, marginTop: 2 }} />
          <span style={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
            <span>Design &amp; Generate</span>
            <span style={{ fontSize: 11, color: 'var(--bm-text-dim)', fontWeight: 400 }}>Generate candidates against property objectives</span>
          </span>
        </button>
        <button className="side-link" data-testid="button-recent-tools" style={{ display: 'flex', alignItems: 'flex-start', gap: 9, padding: '6px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 13, cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }} onClick={() => setShowRecentToolsDialog(true)}>
          <Wrench className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0, marginTop: 2 }} />
          <span style={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
            <span>Recent Tools</span>
            <span style={{ fontSize: 11, color: 'var(--bm-text-dim)', fontWeight: 400 }}>Tools you have used recently</span>
          </span>
        </button>
        {/* Billing hidden — /billing page crashes (BillingPage toFixed on undefined).
            Restore this nav entry once the page is hardened. */}
        {/* <button className="side-link" data-testid="button-billing-nav" style={{ display: 'flex', alignItems: 'flex-start', gap: 9, padding: '6px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 13, cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }} onClick={() => setLocation('/billing')}>
          <CreditCard className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0, marginTop: 2 }} />
          <span style={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
            <span>{t('nav.billing')}</span>
            <span style={{ fontSize: 11, color: 'var(--bm-text-dim)', fontWeight: 400 }}>Usage & subscription</span>
          </span>
        </button> */}
      </div>

      {/* Projects section — always visible */}
      <div style={{ marginBottom: 8, borderTop: '1px solid var(--bm-border)', paddingTop: 8 }}>
          <button
            style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '0 10px 4px', fontSize: 10.5, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--bm-text-dim)', fontWeight: 600, width: '100%', background: 'transparent', border: 'none', cursor: 'pointer' }}
            onClick={() => setProjectsExpanded(p => !p)}
            data-testid="button-projects-section"
          >
            {projectsExpanded ? <ChevronDown className="w-3 h-3" /> : <ChevronRight className="w-3 h-3" />}
            <FolderOpen className="w-3 h-3" style={{ opacity: 0.7 }} />
            {t('nav.projects')}
          </button>
          {projectsExpanded && apiProjects.map((proj) => {
            const isExpanded = expandedProjectIds.has(proj.id);
            return (
              <div key={proj.id}>
                <button
                  style={{ display: 'flex', alignItems: 'center', gap: 7, padding: '4px 10px', borderRadius: 5, color: activeProjectId === proj.id ? 'var(--bm-text)' : 'var(--bm-text-muted)', background: activeProjectId === proj.id ? 'var(--bm-surface-3)' : 'transparent', fontSize: 12.5, cursor: 'pointer', border: 'none', width: '100%', textAlign: 'left' }}
                  onClick={() => { onProjectSelect(proj.id); setExpandedProjectIds(prev => { const n = new Set(prev); if (n.has(proj.id)) n.delete(proj.id); else n.add(proj.id); return n; }); }}
                  data-testid={`button-project-${proj.id}`}
                >
                  {isExpanded ? <ChevronDown className="w-3 h-3 shrink-0" /> : <ChevronRight className="w-3 h-3 shrink-0" />}
                  <FolderOpen className="w-3.5 h-3.5 shrink-0" style={{ color: 'var(--bm-accent, oklch(0.55 0.14 245))', opacity: 0.9 }} />
                  <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{proj.name}</span>
                  {proj.userId && user && proj.userId !== user.id && (
                    <span style={{ fontSize: 9.5, fontWeight: 600, letterSpacing: '0.04em', textTransform: 'uppercase', color: 'var(--bm-accent, oklch(0.55 0.14 245))', opacity: 0.8, flexShrink: 0 }}>shared</span>
                  )}
                </button>
                {isExpanded && (
                  <div style={{ paddingLeft: 28 }}>
                    <button style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '3px 10px', fontSize: 11.5, color: 'var(--bm-text-muted)', background: 'transparent', border: 'none', cursor: 'pointer', width: '100%', borderRadius: 4 }} onClick={() => setLocation(`/projects?project=${proj.id}&tab=chat`)} data-testid={`project-link-chats-${proj.id}`}>
                      <MessageCircle className="w-3 h-3 shrink-0" style={{ opacity: 0.6 }} />
                      Chats
                    </button>
                    <button style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '3px 10px', fontSize: 11.5, color: 'var(--bm-text-muted)', background: 'transparent', border: 'none', cursor: 'pointer', width: '100%', borderRadius: 4 }} onClick={() => setLocation(`/projects?project=${proj.id}&tab=files`)} data-testid={`project-link-files-${proj.id}`}>
                      <FileText className="w-3 h-3 shrink-0" style={{ opacity: 0.6 }} />
                      Files
                    </button>
                    <button style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '3px 10px', fontSize: 11.5, color: 'var(--bm-text-muted)', background: 'transparent', border: 'none', cursor: 'pointer', width: '100%', borderRadius: 4 }} onClick={() => setLocation(`/projects?project=${proj.id}&tab=workflows`)} data-testid={`project-link-workflows-${proj.id}`}>
                      <FlaskConical className="w-3 h-3 shrink-0" style={{ opacity: 0.6 }} />
                      Workflows
                    </button>
                  </div>
                )}
              </div>
            );
          })}
          <button
            style={{ display: 'flex', alignItems: 'center', gap: 7, padding: '3px 10px', borderRadius: 5, color: 'var(--bm-text-dim)', fontSize: 11.5, cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left', marginTop: 2 }}
            onClick={onNewProject}
            data-testid="button-new-project"
          >
            <Plus className="w-3 h-3 shrink-0" style={{ opacity: 0.6 }} />
            New project
          </button>
        </div>

      {/* Chat history — scrollable, takes remaining space */}
      <div style={{ flex: 1, overflowY: 'auto', minHeight: 0 }}>
        {recentChats.length > 0 && (
          <>
            <div style={{ fontSize: 10.5, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--bm-text-dim)', padding: '0 10px', marginBottom: 4, fontWeight: 600, marginTop: 8 }}>Current</div>
            {recentChats.slice(0, 6).map((chat) => {
              const dotStatus = sessionStatusMap.get(chat.id)
              const isActive = activeChatId === chat.id
              return (
                <button
                  key={chat.id}
                  onClick={() => onChatSelect(chat.id)}
                  data-testid={`button-chat-${chat.id}`}
                  style={{
                    display: 'flex', alignItems: 'center', gap: 9,
                    padding: '5px 10px', borderRadius: 6,
                    color: isActive ? 'var(--bm-text)' : 'var(--bm-text-muted)',
                    background: isActive ? 'var(--bm-surface-3, oklch(0.945 0.005 240))' : 'transparent',
                    fontWeight: isActive ? 500 : 400,
                    fontSize: 12.5, cursor: 'pointer', border: 'none',
                    width: '100%', textAlign: 'left',
                  }}
                >
                  <span style={{
                    width: 8, height: 8, borderRadius: '50%', flexShrink: 0,
                    background: dotStatus === 'running' ? 'var(--bm-accent, oklch(0.55 0.14 245))' :
                                dotStatus === 'failed'  ? 'var(--bm-err, oklch(0.58 0.18 25))' :
                                dotStatus === 'completed' ? 'var(--bm-ok, oklch(0.62 0.13 150))' :
                                'var(--bm-border-strong, oklch(0.80 0.008 240))',
                    animation: dotStatus === 'running' ? 'pulse 1.5s infinite' : 'none',
                  }} title={dotStatus || 'idle'} data-testid={`history-dot-${chat.id}`} />
                  <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{chat.title}</span>
                </button>
              )
            })}
            {recentChats.length > 6 && (
              <>
                <div style={{ fontSize: 10.5, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--bm-text-dim)', padding: '0 10px', marginBottom: 4, fontWeight: 600, marginTop: 14 }}>Recent</div>
                {recentChats.slice(6, 12).map((chat) => (
                  <button
                    key={chat.id}
                    onClick={() => onChatSelect(chat.id)}
                    data-testid={`button-chat-${chat.id}`}
                    style={{
                      display: 'flex', alignItems: 'center', gap: 9,
                      padding: '5px 10px', borderRadius: 6,
                      color: activeChatId === chat.id ? 'var(--bm-text)' : 'var(--bm-text-muted)',
                      background: activeChatId === chat.id ? 'var(--bm-surface-3)' : 'transparent',
                      fontSize: 12.5, cursor: 'pointer', border: 'none',
                      width: '100%', textAlign: 'left',
                    }}
                  >
                    <span style={{ width: 8, flexShrink: 0 }} />
                    <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{chat.title}</span>
                  </button>
                ))}
              </>
            )}
          </>
        )}
        {recentChats.length === 0 && (
          <div style={{ padding: '10px', fontSize: 12, color: 'var(--bm-text-dim)', textAlign: 'center' }}>
            No chats yet
          </div>
        )}

        {/* Settings entry — visible in sidebar nav as well as the footer gear icon */}
        <div style={{ marginTop: 12, borderTop: '1px solid var(--bm-border)', paddingTop: 8 }}>
          <button
            style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '5px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 12.5, cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }}
            onClick={() => { analytics.track('settings_opened'); setShowSettingsDialog(true); }}
            data-testid="button-settings-sidebar"
          >
            <Settings className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0 }} />
            <span>{t('settings.title')} &amp; {t('settings.api_keys')}</span>
          </button>
        </div>
      </div>

      {/* Footer */}
      <div style={{ borderTop: '1px solid var(--bm-border)', padding: '10px 10px 4px', display: 'flex', alignItems: 'center', gap: 9 }}>
        <div style={{
          width: 26, height: 26, borderRadius: '50%',
          background: 'oklch(0.85 0.05 60)', color: 'oklch(0.35 0.08 60)',
          display: 'grid', placeItems: 'center', fontSize: 11, fontWeight: 600, flexShrink: 0,
        }}>
          {user?.name ? user.name.split(' ').map(w => w[0]).join('').slice(0, 2).toUpperCase() : 'U'}
        </div>
        <div style={{ flex: 1, minWidth: 0, lineHeight: 1.2 }}>
          <div style={{ fontWeight: 500, fontSize: 12, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', color: 'var(--bm-text)' }}>{user?.name || user?.email?.split('@')[0] || 'Researcher'}</div>
          <div style={{ color: 'var(--bm-text-dim)', fontSize: 11, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{user?.email || 'researcher@biomate.ai'}</div>
        </div>
        <button
          onClick={() => { analytics.track('settings_opened'); setShowSettingsDialog(true); }}
          data-testid="button-settings"
          title="Settings"
          style={{
            flexShrink: 0, border: 'none', background: 'transparent', cursor: 'pointer',
            padding: '4px 6px', borderRadius: 6, display: 'grid', placeItems: 'center', color: 'var(--bm-text-muted)',
          }}
        >
          <Settings className="w-3.5 h-3.5" style={{ opacity: 0.8 }} />
        </button>
        <button
          onClick={async () => { await logout(); setLocation('/login'); }}
          data-testid="button-logout"
          title="Sign out"
          style={{
            flexShrink: 0, border: 'none', background: 'transparent', cursor: 'pointer',
            padding: '4px 8px', borderRadius: 6, fontSize: 11, color: 'var(--bm-text-muted)',
          }}
        >
          Sign&nbsp;out
        </button>
      </div>

      {/* Dialogs */}
      <SettingsDialog open={showSettingsDialog} onOpenChange={setShowSettingsDialog} />
      <WorkflowHistoryDialog open={showHistoryDialog} onOpenChange={setShowHistoryDialog} initialTab={historyInitialTab} onOpenRun={(row) => { if (row.chatSessionId) { window.location.assign(`/?session=${encodeURIComponent(row.chatSessionId)}`); } }} onRunAgain={(row) => { window.location.assign(`/?reuseWorkflow=${encodeURIComponent(row.runId)}`); }} />
      <ConnectorsDialog open={showConnectorsDialog} onOpenChange={setShowConnectorsDialog} />
<RecentToolsDialog open={showRecentToolsDialog} onOpenChange={setShowRecentToolsDialog}
        onToolSelect={(tool) => { if (onToolSelect) onToolSelect(tool as any); }}
      />
    </div>
  )
}

