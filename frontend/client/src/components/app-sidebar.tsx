import { useState, useEffect, useCallback } from "react"
import { useLocation } from "wouter"
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { SettingsDialog } from "./settings-dialog"
import { StarredWorkflowsDialog } from "./starred-workflows-dialog"
import { RecentToolsDialog } from "./recent-tools-dialog"
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
  AlertCircle,
  Loader2,
  FlaskConical,
  BookOpen,
} from "lucide-react"
import { cn } from "@/lib/utils"
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
// Billing widget
// ---------------------------------------------------------------------------

interface BillingData {
  total_usd: number
  llm_usd: number
  compute_usd: number
  storage_usd: number
  running_estimate_usd: number
  quota_usd: number | null
  quota_pct: number | null
  running_jobs: any[]
}

const BILLING_POLL_MS = 30_000

function useBillingData(): BillingData | null {
  const [data, setData] = useState<BillingData | null>(null)

  const fetchBilling = useCallback(async () => {
    const token = localStorage.getItem("auth_token")
    if (!token) return
    try {
      const res = await fetch("/api/billing/usage", {
        headers: { Authorization: `Bearer ${token}` },
      })
      if (res.ok) {
        setData(await res.json())
      }
    } catch {
      // Silently ignore — billing is non-critical
    }
  }, [])

  useEffect(() => {
    fetchBilling()
    const id = setInterval(fetchBilling, BILLING_POLL_MS)
    return () => clearInterval(id)
  }, [fetchBilling])

  return data
}

function BillingWidget() {
  const billing = useBillingData()
  const [, setLocation] = useLocation()

  if (!billing) return null

  const total = billing.total_usd ?? 0
  const quota = billing.quota_usd
  const pct   = billing.quota_pct ?? (quota ? Math.min((total / quota) * 100, 100) : null)
  const over  = pct !== null && pct >= 100
  const running = billing.running_estimate_usd ?? 0

  const fmt = (v: number) =>
    v < 0.01 ? "<$0.01" : `$${v.toFixed(2)}`

  return (
    <div className="p-4 border-t border-border">
      <button
        className="flex items-center gap-2 mb-2 w-full"
        /* onClick={() => setLocation("/billing")} — billing page not ready */
      >
        <DollarSign className="w-3 h-3 text-sidebar-foreground/60" />
        <h3 className="text-xs font-semibold text-sidebar-foreground uppercase tracking-wider">
          Usage this month
        </h3>
      </button>

      {/* Quota progress bar */}
      {pct !== null && (
        <div className="mb-2">
          <div className="flex justify-between text-xs text-sidebar-foreground/60 mb-1">
            <span>{fmt(total)}</span>
            <span>{quota ? fmt(quota) : "∞"}</span>
          </div>
          <div className="h-1.5 bg-sidebar-accent rounded-full overflow-hidden">
            <div
              className={`h-full rounded-full transition-all ${over ? "bg-destructive" : pct > 80 ? "bg-yellow-500" : "bg-primary"}`}
              style={{ width: `${Math.min(pct, 100)}%` }}
            />
          </div>
          {over && (
            <div className="flex items-center gap-1 mt-1">
              <AlertCircle className="w-3 h-3 text-destructive" />
              <span className="text-xs text-destructive">Quota exceeded</span>
            </div>
          )}
        </div>
      )}

      {/* Cost breakdown */}
      <div className="space-y-0.5 text-xs text-sidebar-foreground/70">
        {billing.llm_usd > 0 && (
          <div className="flex justify-between">
            <span>AI / LLM</span><span>{fmt(billing.llm_usd)}</span>
          </div>
        )}
        {billing.compute_usd > 0 && (
          <div className="flex justify-between">
            <span>Compute</span><span>{fmt(billing.compute_usd)}</span>
          </div>
        )}
        {billing.storage_usd > 0 && (
          <div className="flex justify-between">
            <span>Storage</span><span>{fmt(billing.storage_usd)}</span>
          </div>
        )}
        {running > 0 && (
          <div className="flex justify-between text-yellow-600 dark:text-yellow-400">
            <span className="flex items-center gap-1">
              <Loader2 className="w-2.5 h-2.5 animate-spin" />
              Running
            </span>
            <span>~{fmt(running)}</span>
          </div>
        )}
        {total === 0 && running === 0 && (
          <div className="text-center text-sidebar-foreground/40 py-1">No usage yet</div>
        )}
      </div>
    </div>
  )
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
  const [projectsExpanded, setProjectsExpanded] = useState(false);
  const [chatsExpanded, setChatsExpanded] = useState(true);
  const [toolCategoriesExpanded, setToolCategoriesExpanded] = useState(false);
  const [showSettingsDialog, setShowSettingsDialog] = useState(false);
  const [showStarredDialog, setShowStarredDialog] = useState(false);
  const [showRecentToolsDialog, setShowRecentToolsDialog] = useState(false);
  const [, setLocation] = useLocation();
  const { user } = useAuth();

  // Get recent projects
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

  // Use chat sessions from props or fallback to default
  const recentChats = chatSessions.length > 0 ? [...chatSessions]
    .sort((a, b) => new Date(b.lastActivity ?? 0).getTime() - new Date(a.lastActivity ?? 0).getTime())
    .slice(0, 20).map(session => ({
    id: session.id,
    title: session.title,
    timestamp: getRelativeTime(session.lastActivity)
  })) : [
    { id: "1", title: "RNA-seq Analysis Pipeline", timestamp: "2 hours ago" },
    { id: "2", title: "Variant Calling Workflow", timestamp: "Yesterday" },
    { id: "3", title: "ChIP-seq Data Processing", timestamp: "3 days ago" },
    { id: "4", title: "Genome Assembly Help", timestamp: "1 week ago" },
  ];
  return (
    <div className="h-full flex flex-col" style={{
      background: 'var(--bm-surface, hsl(var(--sidebar)))',
      borderRight: '1px solid var(--bm-border, hsl(var(--border)))',
      padding: '14px 10px',
      gap: 0,
    }}>
      {/* Brand */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '4px 8px 10px', justifyContent: 'space-between' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 9 }}>
          <div style={{
            width: 26, height: 26, borderRadius: 7,
            background: 'var(--bm-text, hsl(var(--foreground)))',
            color: 'var(--bm-bg-elev, white)',
            display: 'grid', placeItems: 'center',
            fontFamily: 'var(--bm-font-mono, monospace)',
            fontSize: 13, fontWeight: 700, letterSpacing: '-0.03em', flexShrink: 0,
          }}>B</div>
          <div>
            <div style={{ fontWeight: 600, fontSize: 14.5, letterSpacing: '-0.01em', lineHeight: 1.2, color: 'var(--bm-text)', display: 'flex', alignItems: 'center', gap: 6 }}>
              biomate
              <span
                title="Early-access beta — features may change"
                style={{
                  fontSize: 9.5,
                  fontWeight: 700,
                  letterSpacing: '0.06em',
                  textTransform: 'uppercase',
                  padding: '1px 5px',
                  borderRadius: 3,
                  background: 'oklch(0.78 0.15 65)',
                  color: '#fff',
                  lineHeight: 1.3,
                }}
              >
                BETA
              </span>
            </div>
            <div style={{ fontSize: 11, color: 'var(--bm-text-dim, oklch(0.62 0.010 260))', marginTop: 1 }}>workflow console</div>
          </div>
        </div>
        <button
          onClick={onToggleSidebar}
          data-testid="button-sidebar-toggle"
          style={{ background: 'transparent', border: 'none', padding: 4, borderRadius: 4, cursor: 'pointer', color: 'var(--bm-text-dim)' }}
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
        <button className="side-link" data-testid="button-workflows-nav" style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '6px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 13, cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }} onClick={() => setShowStarredDialog(true)}>
          <FlaskConical className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0 }} /><span>Workflows</span>
        </button>
        <button className="side-link" data-testid="button-runs-nav" style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '6px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 13, cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }} onClick={() => setLocation('/dashboard')}>
          <Activity className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0 }} /><span>Runs</span>
        </button>
        <button className="side-link" data-testid="button-cro-compliance" style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '6px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 13, cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }} onClick={() => setLocation('/drug-discovery-cro')}>
          <Database className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0 }} /><span>CRO Library</span>
        </button>
        <button className="side-link" data-testid="button-ind-report" style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '6px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 13, cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }} onClick={() => setLocation('/ind-report')}>
          <FileText className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0 }} /><span>IND Report</span>
        </button>
        <button className="side-link" data-testid="button-capabilities" style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '6px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 13, cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }} onClick={() => setLocation('/capabilities')}>
          <BookOpen className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0 }} /><span>Capabilities</span>
        </button>
        <button className="side-link" data-testid="button-blog" style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '6px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 13, cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }} onClick={() => setLocation('/blog')}>
          <BookOpen className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0 }} /><span>Research notes</span>
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
                  }} title={dotStatus || 'idle'} />
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

        {/* Quick actions (compact) */}
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
          <button style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '5px 10px', borderRadius: 6, color: 'var(--bm-text-muted)', fontSize: 12.5, cursor: 'pointer', border: 'none', background: 'transparent', width: '100%', textAlign: 'left' }} onClick={() => setShowSettingsDialog(true)} data-testid="button-settings">
            <Settings className="w-3.5 h-3.5" style={{ opacity: 0.7, flexShrink: 0 }} /><span>Settings</span>
          </button>
        </div>
      </div>

      {/* Billing summary */}
      <BillingWidget />

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
      </div>

      {/* Dialogs */}
      <SettingsDialog open={showSettingsDialog} onOpenChange={setShowSettingsDialog} />
      <StarredWorkflowsDialog open={showStarredDialog} onOpenChange={setShowStarredDialog}
        onWorkflowSelect={(workflow) => console.log('Selected starred workflow:', workflow)}
      />
      <RecentToolsDialog open={showRecentToolsDialog} onOpenChange={setShowRecentToolsDialog}
        onToolSelect={(tool) => { if (onToolSelect) onToolSelect(tool as any); }}
      />
    </div>
  )
}

