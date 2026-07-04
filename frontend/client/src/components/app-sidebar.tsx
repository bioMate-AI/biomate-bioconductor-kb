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
  Dna,
  BarChart3,
  Database,
  Settings,
  Workflow,
  Clock,
  Star,
  ChevronRight,
  ChevronDown,
  Zap,
  FileText,
  Activity,
  Target,
  Layers,
  GitBranch,
  Search,
  Filter,
  BarChart,
  PieChart,
  TrendingUp,
  FolderOpen,
  PanelLeft,
  DollarSign,
  FlaskConical,
  BookOpen,
  Upload,
  Cable,
} from "lucide-react"
import { cn } from "@/lib/utils"
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

interface ToolCategory {
  name: string
  icon: any
  count: number
  tools: ToolItem[]
}

const toolCategories: ToolCategory[] = [
  {
    name: "Genomics", 
    icon: Dna, 
    count: 45,
    tools: [
      { id: 'fastqc', name: 'FastQC', description: 'Quality assessment of sequencing data', complexity: 'simple', category: 'genomics', icon: Activity },
      { id: 'hisat2', name: 'HISAT2', description: 'Splice-aware RNA-seq alignment', complexity: 'intermediate', category: 'genomics', icon: Target },
      { id: 'bwa-mem', name: 'BWA-MEM', description: 'Fast and accurate read alignment', complexity: 'intermediate', category: 'genomics', icon: Target },
      { id: 'star', name: 'STAR', description: 'Ultrafast RNA-seq aligner', complexity: 'complex', category: 'genomics', icon: Star },
      { id: 'gatk', name: 'GATK', description: 'Variant discovery toolkit', complexity: 'complex', category: 'genomics', icon: Search },
      { id: 'freebayes', name: 'FreeBayes', description: 'Bayesian variant caller', complexity: 'intermediate', category: 'genomics', icon: Search }
    ]
  },
  {
    name: "Statistics", 
    icon: BarChart3, 
    count: 28,
    tools: [
      { id: 'deseq2', name: 'DESeq2', description: 'Differential gene expression analysis', complexity: 'complex', category: 'statistics', icon: BarChart },
      { id: 'edger', name: 'edgeR', description: 'Empirical analysis of digital gene expression', complexity: 'complex', category: 'statistics', icon: BarChart },
      { id: 'limma', name: 'limma', description: 'Linear models for microarray data', complexity: 'intermediate', category: 'statistics', icon: TrendingUp },
      { id: 'multiqc', name: 'MultiQC', description: 'Aggregate bioinformatics analyses', complexity: 'simple', category: 'statistics', icon: PieChart }
    ]
  },
  {
    name: "Data Sources", 
    icon: Database, 
    count: 32,
    tools: [
      { id: 'samtools', name: 'SAMtools', description: 'Tools for SAM/BAM manipulation', complexity: 'simple', category: 'data-sources', icon: Database },
      { id: 'bcftools', name: 'BCFtools', description: 'Tools for VCF/BCF files', complexity: 'intermediate', category: 'data-sources', icon: Database },
      { id: 'picard', name: 'Picard', description: 'Java tools for sequencing data', complexity: 'intermediate', category: 'data-sources', icon: Layers }
    ]
  },
  {
    name: "Workflows", 
    icon: Workflow, 
    count: 15,
    tools: [
      { id: 'rna-seq', name: 'RNA-seq Pipeline', description: 'Complete RNA sequencing workflow', complexity: 'complex', category: 'workflows', icon: GitBranch },
      { id: 'variant-calling', name: 'Variant Calling', description: 'SNP and indel discovery pipeline', complexity: 'complex', category: 'workflows', icon: GitBranch },
      { id: 'chip-seq', name: 'ChIP-seq Pipeline', description: 'Chromatin immunoprecipitation workflow', complexity: 'complex', category: 'workflows', icon: GitBranch }
    ]
  },
]


// ---------------------------------------------------------------------------
// Billing widget — disabled until billing page ships (BUG-10b)
// ---------------------------------------------------------------------------

function BillingWidget() {
  return null
}

interface AppSidebarProps {
  onNewChat?: () => void
  onChatSelect?: (chatId: string) => void
  onCategorySelect?: (category: string) => void
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
  onCategorySelect = (cat) => console.log('Category selected:', cat),
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
  const [expandedCategories, setExpandedCategories] = useState<string[]>([]);
  const [projectsExpanded, setProjectsExpanded] = useState(true);
  const [chatsExpanded, setChatsExpanded] = useState(true);
  const [toolCategoriesExpanded, setToolCategoriesExpanded] = useState(false);
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
  const [showUploadModal, setShowUploadModal] = useState(false);
  const [, setLocation] = useLocation();
  const { user, logout } = useAuth();

  // Projects — fetched from API (not localStorage) so they survive page reload
  const [apiProjects, setApiProjects] = useState<Array<{ id: string; name: string; status: string }>>([]);
  const [expandedProjectIds, setExpandedProjectIds] = useState<Set<string>>(new Set());
  useEffect(() => {
    fetch("/api/projects", { credentials: "include" })
      .then((r) => r.ok ? r.json() : { projects: [] })
      .then((d) => setApiProjects((d.projects ?? []).slice(0, 8)))
      .catch(() => {});
  }, []);
  const recentProjects = projectService.getAllProjects().slice(0, 5);

  const toggleCategory = (categoryName: string) => {
    setExpandedCategories(prev => 
      prev.includes(categoryName)
        ? prev.filter(name => name !== categoryName)
        : [...prev, categoryName]
    );
    onCategorySelect(categoryName);
  };

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
        <button className="side-link" onClick={onNewChat} data-testid="button-new-chat" style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '6px 10px', borderRadius: 6, color: 'var(--bm-text-muted, oklch(0.48 0.012 260))', fontSize: 13, cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }}>
          <Plus className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0 }} /><span>New Chat</span>
        </button>
        <button
          className="side-link"
          data-testid="button-workflows-nav"
          title="View run history, browse imported workflows, or upload a new Nextflow / Galaxy workflow"
          style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '6px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 13, cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }}
          onClick={() => { analytics.track('workflows_sidebar_opened'); setHistoryInitialTab('runs'); setShowHistoryDialog(true); }}
        >
          <FlaskConical className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0 }} /><span>Workflows</span>{runningCount > 0 && (<span data-testid="workflows-running-badge" style={{ marginLeft: 6, fontSize: 10, fontWeight: 600, padding: '1px 6px', borderRadius: 999, background: 'oklch(0.92 0.04 230)', color: 'oklch(0.40 0.13 230)' }}>{runningCount}</span>)}
        </button>
        <button
          className="side-link"
          data-testid="button-import-workflow"
          title="Upload your own Nextflow (.nf) or Galaxy (.ga / .yml) workflow"
          style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '6px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 13, cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }}
          onClick={() => { analytics.track('import_workflow_opened'); setHistoryInitialTab('upload'); setShowHistoryDialog(true); }}
        >
          <Upload className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0 }} /><span>Import Workflow</span>
        </button>
        {/* Connectors — commented out pending review
        <button
          className="side-link"
          data-testid="button-connectors-nav"
          title="Databases, LLM providers, scientific data sources, and AI platform integrations available in BioMate"
          style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '6px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 13, cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }}
          onClick={() => setShowConnectorsDialog(true)}
        >
          <Cable className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0 }} /><span>Connectors</span>
        </button>
        */}
        {/* Workspaces — commented out until create flow is stable (500 on POST /api/workspaces)
        <button className="side-link" data-testid="button-workspaces-nav" style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '6px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 13, cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }} onClick={() => setLocation('/workspaces')}>
          <FolderOpen className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0 }} /><span>Workspaces</span>
        </button>
        */}
        {/* CRO Library — commented out until fully implemented and validated
        <button className="side-link" data-testid="button-cro-compliance" style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '6px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 13, cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }} onClick={() => setLocation('/drug-discovery-cro')}>
          <Database className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0 }} /><span>CRO Library</span>
        </button>
        */}
        <button className="side-link" data-testid="button-ind-report" style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '6px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 13, cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }} onClick={() => setLocation('/ind-report')}>
          <FileText className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0 }} /><span>IND Report</span>
        </button>
        {/*
        <button className="side-link" data-testid="button-capabilities" style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '6px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 13, cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }} onClick={() => setLocation('/capabilities')}>
          <BookOpen className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0 }} /><span>Capabilities</span>
        </button>
        <button className="side-link" data-testid="button-blog" style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '6px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 13, cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }} onClick={() => setLocation('/blog')}>
          <BookOpen className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0 }} /><span>Research notes</span>
        </button>
        */}
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
            Projects
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
                </button>
                {isExpanded && (
                  <div style={{ paddingLeft: 28 }}>
                    <button style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '3px 10px', fontSize: 11.5, color: 'var(--bm-text-muted)', background: 'transparent', border: 'none', cursor: 'pointer', width: '100%', borderRadius: 4 }} onClick={() => onProjectSelect(proj.id)} data-testid={`project-link-chats-${proj.id}`}>
                      <MessageCircle className="w-3 h-3 shrink-0" style={{ opacity: 0.6 }} />
                      Chats
                    </button>
                    <button style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '3px 10px', fontSize: 11.5, color: 'var(--bm-text-muted)', background: 'transparent', border: 'none', cursor: 'pointer', width: '100%', borderRadius: 4 }} onClick={() => { onProjectSelect(proj.id); }} data-testid={`project-link-files-${proj.id}`}>
                      <FileText className="w-3 h-3 shrink-0" style={{ opacity: 0.6 }} />
                      Files
                    </button>
                    <button style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '3px 10px', fontSize: 11.5, color: 'var(--bm-text-muted)', background: 'transparent', border: 'none', cursor: 'pointer', width: '100%', borderRadius: 4 }} data-testid={`project-link-workflows-${proj.id}`}>
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

        {/* Beta: Actions panel hidden — Starred Workflows, Recent Tools,
            Billing, Settings dialogs aren't wired up to backend yet.
            Re-enable once each action lands a real implementation.

        <div style={{ marginTop: 16, borderTop: '1px solid var(--bm-border)', paddingTop: 10 }}>
          <div style={{ fontSize: 10.5, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--bm-text-dim)', padding: '0 10px', marginBottom: 4, fontWeight: 600 }}>Actions</div>
          <button style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '5px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 12.5, cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }} onClick={() => setShowStarredDialog(true)} data-testid="button-starred-workflows">
            <Star className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0 }} /><span>Starred Workflows</span>
          </button>
          <button style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '5px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 12.5, cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }} onClick={() => setShowRecentToolsDialog(true)} data-testid="button-recent-tools">
            <Clock className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0 }} /><span>Recent Tools</span>
          </button>
          <button style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '5px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 12.5, cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }} onClick={() => setLocation('/billing')} data-testid="button-billing">
            <DollarSign className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0 }} /><span>Billing</span>
          </button>
          <button style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '5px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 12.5, cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }} onClick={() => { analytics.track('settings_opened'); setShowSettingsDialog(true); }} data-testid="button-settings">
            <Settings className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0 }} /><span>Settings</span>
          </button>
        </div>
        */}
      </div>

      {/* Billing summary — hidden until billing page is ready
      <BillingWidget />
      */}

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
      <WorkflowHistoryDialog open={showHistoryDialog} onOpenChange={setShowHistoryDialog} initialTab={historyInitialTab} onOpenRun={(row) => { if (row.chatSessionId) { window.location.assign(`/?session=${encodeURIComponent(row.chatSessionId)}`); } }} onRunAgain={(row) => { if (row.chatSessionId) { window.location.assign(`/?session=${encodeURIComponent(row.chatSessionId)}&runAgain=${encodeURIComponent(row.runId)}`); } }} />
      <ConnectorsDialog open={showConnectorsDialog} onOpenChange={setShowConnectorsDialog} />
<RecentToolsDialog open={showRecentToolsDialog} onOpenChange={setShowRecentToolsDialog}
        onToolSelect={(tool) => { if (onToolSelect) onToolSelect(tool as any); }}
      />
    </div>
  )
}

