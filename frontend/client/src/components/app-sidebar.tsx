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
  Loader2
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
        className="flex items-center gap-2 mb-2 w-full hover:opacity-80 transition-opacity"
        onClick={() => setLocation("/billing")}
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
  const recentChats = chatSessions.length > 0 ? chatSessions.slice(0, 4).map(session => ({
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
    <div className="h-full bg-sidebar border-r border-border flex flex-col">
      {/* Header */}
      <div className="p-4 border-b border-border">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-primary/10 rounded-lg">
              <FileText className="w-5 h-5 text-primary" />
            </div>
            <div>
              <h1 className="text-sm font-semibold text-sidebar-foreground">bioMate AI</h1>
              <p className="text-xs text-sidebar-foreground/70">Bioinformatics Assistant</p>
            </div>
          </div>
          <Button
            variant="ghost"
            size="icon"
            onClick={onToggleSidebar}
            className="h-7 w-7 flex-shrink-0"
            data-testid="button-sidebar-toggle"
          >
            <PanelLeft className="h-4 w-4" />
            <span className="sr-only">Toggle Sidebar</span>
          </Button>
        </div>
        <Button 
          size="sm"
          className="w-fit mx-auto px-3" 
          onClick={onNewChat}
          data-testid="button-new-chat"
        >
          <Plus className="w-4 h-4 mr-1" />
          New Chat
        </Button>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-hidden">
        {/* Projects */}
        <div className="p-4">
          <Collapsible open={projectsExpanded} onOpenChange={setProjectsExpanded}>
            <CollapsibleTrigger asChild>
              <Button
                variant="ghost"
                className="w-full justify-start p-0 h-auto mb-3"
                data-testid="button-toggle-projects"
              >
                <div className="flex items-center gap-2">
                  <h3 className="text-xs font-semibold text-sidebar-foreground uppercase tracking-wider">Projects</h3>
                  {projectsExpanded ? (
                    <ChevronDown className="w-3 h-3" />
                  ) : (
                    <ChevronRight className="w-3 h-3" />
                  )}
                </div>
              </Button>
            </CollapsibleTrigger>
            <CollapsibleContent>
              <ScrollArea className="h-[120px]">
                <div className="space-y-1">
                  {recentProjects.length > 0 ? recentProjects.map((project) => (
                    <Button
                      key={project.id}
                      variant="ghost"
                      className={cn(
                        "w-full justify-start text-left h-auto p-2",
                        activeProjectId === project.id && "bg-sidebar-accent text-sidebar-accent-foreground"
                      )}
                      onClick={() => onProjectSelect(project.id)}
                      data-testid={`button-project-${project.id}`}
                    >
                      <FolderOpen className="w-4 h-4 mr-2 flex-shrink-0" />
                      <div className="flex-1 min-w-0">
                        <div className="truncate text-sm font-medium">{project.name}</div>
                      </div>
                    </Button>
                  )) : (
                    <div className="text-xs text-sidebar-foreground/50 text-center py-2">
                      No projects yet
                    </div>
                  )}
                </div>
              </ScrollArea>
            </CollapsibleContent>
          </Collapsible>
        </div>

        {/* Recent Chats */}
        <div className="p-4 border-t border-border">
          <Collapsible open={chatsExpanded} onOpenChange={setChatsExpanded}>
            <CollapsibleTrigger asChild>
              <Button
                variant="ghost"
                className="w-full justify-start p-0 h-auto mb-3"
                data-testid="button-toggle-chats"
              >
                <div className="flex items-center gap-2">
                  <h3 className="text-xs font-semibold text-sidebar-foreground uppercase tracking-wider">Recent Chats</h3>
                  {chatsExpanded ? (
                    <ChevronDown className="w-3 h-3" />
                  ) : (
                    <ChevronRight className="w-3 h-3" />
                  )}
                </div>
              </Button>
            </CollapsibleTrigger>
            <CollapsibleContent>
              <ScrollArea className="h-[200px]">
                <div className="space-y-1">
                  {recentChats.map((chat) => {
                    const dotStatus = sessionStatusMap.get(chat.id)
                    return (
                      <Button
                        key={chat.id}
                        variant="ghost"
                        className={cn(
                          "w-full justify-start text-left h-auto p-2",
                          activeChatId === chat.id && "bg-sidebar-accent text-sidebar-accent-foreground"
                        )}
                        onClick={() => onChatSelect(chat.id)}
                        data-testid={`button-chat-${chat.id}`}
                      >
                        <MessageCircle className="w-4 h-4 mr-2 flex-shrink-0" />
                        <div className="flex-1 min-w-0">
                          <div className="truncate text-sm">{chat.title}</div>
                        </div>
                        {dotStatus === 'running' && (
                          <span
                            className="ml-1.5 h-2 w-2 flex-shrink-0 rounded-full bg-blue-500 animate-pulse"
                            title="Workflow running"
                          />
                        )}
                        {dotStatus === 'failed' && (
                          <span
                            className="ml-1.5 h-2 w-2 flex-shrink-0 rounded-full bg-red-500"
                            title="Workflow failed — needs attention"
                          />
                        )}
                        {dotStatus === 'completed' && activeChatId !== chat.id && (
                          <span
                            className="ml-1.5 h-2 w-2 flex-shrink-0 rounded-full bg-green-500"
                            title="Workflow completed"
                          />
                        )}
                      </Button>
                    )
                  })}
                </div>
              </ScrollArea>
            </CollapsibleContent>
          </Collapsible>
        </div>

        {/* Tool Categories */}
        <div className="p-4 border-t border-border">
          <Collapsible open={toolCategoriesExpanded} onOpenChange={setToolCategoriesExpanded}>
            <CollapsibleTrigger asChild>
              <Button
                variant="ghost"
                className="w-full justify-start p-0 h-auto mb-3"
                data-testid="button-toggle-tool-categories"
              >
                <div className="flex items-center gap-2">
                  <h3 className="text-xs font-semibold text-sidebar-foreground uppercase tracking-wider">Tool Categories</h3>
                  {toolCategoriesExpanded ? (
                    <ChevronDown className="w-3 h-3" />
                  ) : (
                    <ChevronRight className="w-3 h-3" />
                  )}
                </div>
              </Button>
            </CollapsibleTrigger>
            <CollapsibleContent>
              <div className="space-y-1">
                {toolCategories.map((category) => {
                  const isExpanded = expandedCategories.includes(category.name);
                  return (
                    <Collapsible key={category.name} open={isExpanded} onOpenChange={() => toggleCategory(category.name)}>
                      <CollapsibleTrigger asChild>
                        <Button
                          variant="ghost"
                          className={cn(
                            "w-full justify-start",
                            activeCategory === category.name && "bg-sidebar-accent text-sidebar-accent-foreground"
                          )}
                          data-testid={`button-category-${category.name.toLowerCase()}`}
                        >
                          <category.icon className="w-4 h-4 mr-2" />
                          <span className="flex-1 text-left">{category.name}</span>
                          <span className="text-xs text-sidebar-foreground/50 mr-2">
                            {category.count}
                          </span>
                          {isExpanded ? (
                            <ChevronDown className="w-3 h-3" />
                          ) : (
                            <ChevronRight className="w-3 h-3" />
                          )}
                        </Button>
                      </CollapsibleTrigger>
                      <CollapsibleContent>
                        <div className="ml-6 mt-1 space-y-1">
                          {category.tools.map((tool) => (
                            <Button
                              key={tool.id}
                              variant="ghost"
                              size="sm"
                              className={cn(
                                "w-full justify-start text-left h-auto p-2",
                                activeTool === tool.id && "bg-sidebar-accent text-sidebar-accent-foreground"
                              )}
                              onClick={() => onToolSelect(tool)}
                              data-testid={`button-tool-${tool.id}`}
                            >
                              <tool.icon className="w-3 h-3 mr-2 flex-shrink-0" />
                              <div className="flex-1 min-w-0">
                                <div className="truncate">
                                  <span className="text-sm">{tool.name}</span>
                                  <span className="text-xs text-sidebar-foreground/60 ml-2">
                                    - {tool.description}
                                  </span>
                                </div>
                              </div>
                            </Button>
                          ))}
                        </div>
                      </CollapsibleContent>
                    </Collapsible>
                  );
                })}
              </div>
            </CollapsibleContent>
          </Collapsible>
        </div>

        {/* Quick Actions */}
        <div className="p-4 border-t border-border">
          <h3 className="text-xs font-semibold text-sidebar-foreground mb-3 uppercase tracking-wider">Quick Actions</h3>
          <div className="space-y-1">
            <Button
              variant="ghost"
              className="w-full justify-start"
              data-testid="button-starred-workflows"
              onClick={() => setShowStarredDialog(true)}
            >
              <Star className="w-4 h-4 mr-2" />
              <span>Starred Workflows</span>
            </Button>
            <Button
              variant="ghost"
              className="w-full justify-start"
              data-testid="button-recent-tools"
              onClick={() => setShowRecentToolsDialog(true)}
            >
              <Clock className="w-4 h-4 mr-2" />
              <span>Recent Tools</span>
            </Button>
            <Button
              variant="ghost"
              className="w-full justify-start"
              data-testid="button-billing"
              onClick={() => setLocation("/billing")}
            >
              <DollarSign className="w-4 h-4 mr-2" />
              <span>Billing &amp; Invoices</span>
            </Button>
            <Button
              variant="ghost"
              className="w-full justify-start"
              data-testid="button-settings"
              onClick={() => setShowSettingsDialog(true)}
            >
              <Settings className="w-4 h-4 mr-2" />
              <span>Settings</span>
            </Button>
          </div>
        </div>
      </div>

      {/* Billing summary */}
      <BillingWidget />

      {/* Footer */}
      <div className="p-4 border-t border-border">
        <Card className="p-3">
          <div className="flex items-center gap-3">
            <Avatar className="h-8 w-8">
              <AvatarImage src={userAvatar} alt="User" />
              <AvatarFallback>{user?.name ? user.name.split(' ').map(w => w[0]).join('').slice(0, 2).toUpperCase() : 'U'}</AvatarFallback>
            </Avatar>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-card-foreground truncate">{user?.name || user?.email?.split('@')[0] || 'Researcher'}</p>
              <p className="text-xs text-muted-foreground truncate">{user?.email || 'researcher@biomate.ai'}</p>
            </div>
          </div>
        </Card>
      </div>

      {/* Dialogs */}
      <SettingsDialog 
        open={showSettingsDialog} 
        onOpenChange={setShowSettingsDialog}
      />
      
      <StarredWorkflowsDialog 
        open={showStarredDialog} 
        onOpenChange={setShowStarredDialog}
        onWorkflowSelect={(workflow) => {
          console.log('Selected starred workflow:', workflow);
          // Handle workflow selection - could trigger workflow builder or chat
        }}
      />
      
      <RecentToolsDialog 
        open={showRecentToolsDialog} 
        onOpenChange={setShowRecentToolsDialog}
        onToolSelect={(tool) => {
          console.log('Selected recent tool:', tool);
          if (onToolSelect) {
            onToolSelect(tool as any); // Type assertion since interfaces are compatible
          }
        }}
      />
    </div>
  )
}