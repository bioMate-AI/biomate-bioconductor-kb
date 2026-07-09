import { useState, useEffect } from "react"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Textarea } from "@/components/ui/textarea"
import { Input } from "@/components/ui/input"
import {
  ArrowLeft,
  MessageCircle,
  FileText,
  Settings,
  Plus,
  Edit3,
  Save,
  X,
  Upload,
  Download,
  Trash2,
  Clock,
  Tag,
  FlaskConical,
  CheckCircle2,
  XCircle,
  Loader2,
  Circle,
} from "lucide-react"
import { projectService } from "@/lib/projects"
import { ChatInterface } from "@/components/chat-interface"
import { ProjectFileTree } from "@/components/project-file-tree"
import type { Project, ChatSession, ProjectDocument } from "@shared/schema"
import { cn } from "@/lib/utils"

interface ProjectDetailPageProps {
  projectId: string
  onBack: () => void
  onChatSelect?: (chatId: string) => void
  initialTab?: string
}

export default function ProjectDetailPage({
  projectId,
  onBack,
  onChatSelect,
  initialTab,
}: ProjectDetailPageProps) {
  const [project, setProject] = useState<Project | null>(null)
  const [projectChats, setProjectChats] = useState<ChatSession[]>([])
  const [currentChatSession, setCurrentChatSession] = useState<ChatSession | null>(null)
  const [isEditingInstructions, setIsEditingInstructions] = useState(false)
  const [instructionsValue, setInstructionsValue] = useState("")
  const validTabs = ["chat", "files", "workflows"]
  const [activeTab, setActiveTab] = useState(validTabs.includes(initialTab || "") ? initialTab! : "chat")
  const [projectRuns, setProjectRuns] = useState<any[]>([])
  const [runsLoading, setRunsLoading] = useState(false)

  // Load project data — try API first, fall back to localStorage
  useEffect(() => {
    const loadProject = async () => {
      try {
        const res = await fetch(`/api/projects/${projectId}`, { credentials: "include" })
        if (res.ok) {
          const data = await res.json()
          const p = data.project
          if (p) {
            // Adapt API shape to local Project type (API returns camelCase)
            setProject({
              ...p,
              tags: p.tags ?? [],
              documents: p.documents ?? [],
              progress: p.progress ?? 0,
              category: p.primaryDomain ?? p.category ?? null,
              instructions: p.researchGoal ?? p.instructions ?? "",
              lastActivity: new Date(p.updatedAt ?? p.createdAt),
              createdAt: new Date(p.createdAt),
              updatedAt: new Date(p.updatedAt ?? p.createdAt),
            } as any)
            setInstructionsValue(p.research_goal ?? p.instructions ?? "")
            return
          }
        }
      } catch { /* fall through to localStorage */ }
      // localStorage fallback
      const projectData = projectService.getProject(projectId)
      if (projectData) {
        setProject(projectData)
        setInstructionsValue(projectData.instructions || "")
        const chats = projectService.getProjectChatSessions(projectId)
        setProjectChats(chats)
        if (chats.length > 0) setCurrentChatSession(chats[0])
      }
    }
    loadProject()
  }, [projectId])

  // Load workflow runs for this project when the Workflows tab is active
  useEffect(() => {
    if (activeTab !== "workflows") return
    setRunsLoading(true)
    fetch(`/api/workflows/runs?projectId=${projectId}&limit=50`, { credentials: "include" })
      .then(r => r.ok ? r.json() : [])
      .then(data => setProjectRuns(Array.isArray(data) ? data : []))
      .catch(() => setProjectRuns([]))
      .finally(() => setRunsLoading(false))
  }, [activeTab, projectId])

  const handleCreateNewChat = () => {
    if (!project) return
    
    const newChat = projectService.createProjectChatSession(project.id)
    if (newChat) {
      setCurrentChatSession(newChat)
      setProjectChats([newChat, ...projectChats])
    }
  }

  const handleChatUpdated = (updatedSession: ChatSession) => {
    setCurrentChatSession(updatedSession)
    setProjectChats(prev => 
      prev.map(chat => chat.id === updatedSession.id ? updatedSession : chat)
    )
  }

  const handleSaveInstructions = async () => {
    if (!project) return
    try {
      const res = await fetch(`/api/projects/${project.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({ researchGoal: instructionsValue.trim() || null }),
      })
      if (res.ok) {
        setProject(prev => prev ? { ...prev, instructions: instructionsValue.trim() } : prev)
        setIsEditingInstructions(false)
      }
    } catch {
      // silently keep editing state open on network error
    }
  }

  const handleCancelEditInstructions = () => {
    setInstructionsValue(project?.instructions || "")
    setIsEditingInstructions(false)
  }

  const getRelativeTime = (date: Date | string | null | undefined): string => {
    if (!date) return 'Unknown'
    const d = new Date(date as any)
    if (isNaN(d.getTime())) return 'Unknown'
    const now = new Date()
    const diffMs = now.getTime() - d.getTime()
    const diffHours = Math.floor(diffMs / (1000 * 60 * 60))
    const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24))
    if (diffHours < 1) return 'Just now'
    if (diffHours < 24) return `${diffHours} hour${diffHours > 1 ? 's' : ''} ago`
    if (diffDays < 7) return `${diffDays} day${diffDays > 1 ? 's' : ''} ago`
    return `${Math.floor(diffDays / 7)} week${Math.floor(diffDays / 7) > 1 ? 's' : ''} ago`
  }

  const formatDate = (date: Date | string | null | undefined): string => {
    if (!date) return '—'
    const d = new Date(date as any)
    if (isNaN(d.getTime())) return '—'
    return d.toLocaleDateString()
  }

  if (!project) {
    return (
      <div className="h-full flex items-center justify-center">
        <div className="text-center">
          <h2 className="text-xl font-semibold mb-2">Project not found</h2>
          <p className="text-muted-foreground mb-4">The project you're looking for doesn't exist.</p>
          <Button onClick={onBack}>
            <ArrowLeft className="w-4 h-4 mr-2" />
            Back to Projects
          </Button>
        </div>
      </div>
    )
  }

  return (
    <div className="h-full flex flex-col">
      {/* Header */}
      <div className="border-b border-border p-4">
        <div className="flex items-center gap-4 mb-4">
          <Button variant="ghost" size="sm" onClick={onBack} data-testid="button-back-to-projects">
            <ArrowLeft className="w-4 h-4 mr-2" />
            All projects
          </Button>
        </div>
        
        <div className="flex items-start justify-between">
          <div>
            <h1 className="text-2xl font-bold mb-2">{project.name}</h1>
            {project.description && (
              <p className="text-muted-foreground mb-3">{project.description}</p>
            )}
            
            <div className="flex items-center gap-2">
              {project.category && (
                <Badge variant="outline">{project.category}</Badge>
              )}
              <Badge 
                variant="secondary"
                className={cn(
                  project.status === 'completed' && "bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-300",
                  project.status === 'archived' && "bg-gray-100 text-gray-700 dark:bg-gray-900 dark:text-gray-300",
                  project.status === 'active' && "bg-blue-100 text-blue-700 dark:bg-blue-900 dark:text-blue-300"
                )}
              >
                {project.status}
              </Badge>
              {project.tags.map((tag) => (
                <Badge key={tag} variant="secondary" className="text-xs">
                  <Tag className="w-3 h-3 mr-1" />
                  {tag}
                </Badge>
              ))}
            </div>
          </div>
          
          <div className="text-right text-sm text-muted-foreground">
            <div className="flex items-center gap-1 mb-1">
              <Clock className="w-3 h-3" />
              Updated {getRelativeTime((project as any).updatedAt ?? project.lastActivity)}
            </div>
            <div>{projectChats.length} chat session{projectChats.length !== 1 ? 's' : ''}</div>
          </div>
        </div>
      </div>

      {/* Content */}
      <div className="flex-1 flex">
        {/* Main Content */}
        <div className="flex-1 flex flex-col">
          <Tabs value={activeTab} onValueChange={setActiveTab} className="flex-1 flex flex-col">
            <TabsList className="w-fit m-4 mb-0">
              <TabsTrigger value="chat" className="flex items-center gap-2">
                <MessageCircle className="w-4 h-4" />
                Chat
              </TabsTrigger>
              <TabsTrigger value="files" className="flex items-center gap-2">
                <FileText className="w-4 h-4" />
                Files
              </TabsTrigger>
              <TabsTrigger value="workflows" className="flex items-center gap-2" data-testid="tab-project-workflows">
                <FlaskConical className="w-4 h-4" />
                Workflows
              </TabsTrigger>
            </TabsList>

            <TabsContent value="chat" className="flex-1 m-0">
              <div className="h-full flex flex-col">
                {/* Chat Sessions */}
                {projectChats.length > 1 && (
                  <div className="border-b border-border p-4">
                    <div className="flex items-center justify-between mb-3">
                      <h3 className="font-medium">Chat Sessions</h3>
                      <Button size="sm" onClick={handleCreateNewChat} data-testid="button-new-project-chat">
                        <Plus className="w-4 h-4 mr-2" />
                        New Chat
                      </Button>
                    </div>
                    <ScrollArea className="h-20">
                      <div className="flex gap-2">
                        {projectChats.map((chat) => (
                          <Button
                            key={chat.id}
                            variant={currentChatSession?.id === chat.id ? "default" : "outline"}
                            size="sm"
                            onClick={() => setCurrentChatSession(chat)}
                            className="whitespace-nowrap"
                            data-testid={`button-project-chat-${chat.id}`}
                          >
                            {chat.title}
                          </Button>
                        ))}
                      </div>
                    </ScrollArea>
                  </div>
                )}

                {/* Chat Interface */}
                <div className="flex-1">
                  {currentChatSession ? (
                    <ChatInterface 
                      chatSession={currentChatSession}
                      onChatUpdated={handleChatUpdated}
                      onWorkflowGenerated={() => {}}
                    />
                  ) : (
                    <div className="h-full flex items-center justify-center">
                      <div className="text-center">
                        <MessageCircle className="w-12 h-12 text-muted-foreground mx-auto mb-4" />
                        <h3 className="text-lg font-medium mb-2">No chat sessions yet</h3>
                        <p className="text-muted-foreground mb-4">
                          Start a conversation about your project
                        </p>
                        <Button onClick={handleCreateNewChat}>
                          <Plus className="w-4 h-4 mr-2" />
                          Start first chat
                        </Button>
                      </div>
                    </div>
                  )}
                </div>
              </div>
            </TabsContent>

            <TabsContent value="files" className="flex-1 m-0 min-h-0" style={{ display: "flex", flexDirection: "column" }}>
              <div className="flex-1 p-4 min-h-0 flex flex-col">
                <ProjectFileTree projectId={projectId} />
              </div>
              {/* Analyze CTA — fixed footer inside Files tab */}
              <div className="border-t border-border px-4 py-3 bg-muted/20 shrink-0 flex items-center justify-between gap-4">
                <p className="text-xs text-muted-foreground">Upload genomics, proteomics, or any research data files above.</p>
                <Button
                  size="sm"
                  onClick={() => openChatWithProject()}
                  className="gap-1.5 shrink-0"
                  data-testid="button-analyze-files"
                >
                  <MessageCircle className="w-3.5 h-3.5" />
                  Analyze with BioMate
                </Button>
              </div>
            </TabsContent>

            <TabsContent value="workflows" className="flex-1 m-0 min-h-0 overflow-hidden" data-testid="tab-content-workflows">
              <div className="h-full flex flex-col gap-4">
                <div className="flex items-center justify-between">
                  <h3 className="font-medium text-sm">Workflow runs in this project</h3>
                </div>
                {runsLoading ? (
                  <div className="flex items-center gap-2 text-muted-foreground text-sm py-8 justify-center">
                    <Loader2 className="w-4 h-4 animate-spin" />
                    Loading runs…
                  </div>
                ) : projectRuns.length === 0 ? (
                  <div className="flex flex-col items-center justify-center py-12 text-center text-muted-foreground">
                    <FlaskConical className="w-10 h-10 mb-3 opacity-40" />
                    <p className="text-sm font-medium mb-1">No workflow runs yet</p>
                    <p className="text-xs">Start a chat and ask BioMate to run a workflow.</p>
                  </div>
                ) : (
                  <ScrollArea className="flex-1">
                    <div className="space-y-2">
                      {projectRuns.map((run: any) => {
                        const status = run.execution?.status ?? run.status ?? "unknown"
                        const name = run.workflowName ?? run.execution?.workflowName ?? run.id
                        const ts = run.createdAt ?? run.execution?.createdAt
                        const relTime = ts ? new Date(ts).toLocaleString() : ""
                        const statusIcon =
                          status === "completed" ? <CheckCircle2 className="w-4 h-4 text-green-500 flex-shrink-0" /> :
                          status === "failed" || status === "errored" ? <XCircle className="w-4 h-4 text-red-500 flex-shrink-0" /> :
                          status === "running" ? <Loader2 className="w-4 h-4 text-blue-500 animate-spin flex-shrink-0" /> :
                          <Circle className="w-4 h-4 text-muted-foreground flex-shrink-0" />
                        return (
                          <div key={run.id} className="flex items-center gap-3 p-3 rounded-lg border border-border bg-background hover:bg-muted/40 transition-colors">
                            {statusIcon}
                            <div className="flex-1 min-w-0">
                              <p className="text-sm font-medium truncate">{name}</p>
                              <p className="text-xs text-muted-foreground">{status} · {relTime}</p>
                            </div>
                            {run.chatSessionId && (
                              <Button size="sm" variant="outline" className="text-xs h-7 px-2 flex-shrink-0"
                                onClick={() => window.location.assign(`/?session=${encodeURIComponent(run.chatSessionId)}`)}>
                                Open
                              </Button>
                            )}
                          </div>
                        )
                      })}
                    </div>
                  </ScrollArea>
                )}
              </div>
            </TabsContent>
          </Tabs>
        </div>

        {/* Right Sidebar - Instructions */}
        <div className="w-80 border-l border-border bg-muted/30">
          <div className="p-4">
            <div className="flex items-center justify-between mb-4">
              <h3 className="font-medium">Instructions</h3>
              {!isEditingInstructions && (
                <Button 
                  variant="ghost" 
                  size="sm"
                  onClick={() => setIsEditingInstructions(true)}
                  data-testid="button-edit-instructions"
                >
                  <Edit3 className="w-4 h-4" />
                </Button>
              )}
            </div>

            {isEditingInstructions ? (
              <div className="space-y-3">
                <Textarea
                  value={instructionsValue}
                  onChange={(e) => setInstructionsValue(e.target.value)}
                  placeholder="Add background context, guidelines, or instructions for this project..."
                  className="min-h-[200px] resize-none"
                  data-testid="textarea-edit-instructions"
                />
                <div className="flex gap-2">
                  <Button 
                    size="sm" 
                    onClick={handleSaveInstructions}
                    data-testid="button-save-instructions"
                  >
                    <Save className="w-4 h-4 mr-2" />
                    Save
                  </Button>
                  <Button 
                    variant="outline" 
                    size="sm" 
                    onClick={handleCancelEditInstructions}
                    data-testid="button-cancel-instructions"
                  >
                    <X className="w-4 h-4 mr-2" />
                    Cancel
                  </Button>
                </div>
              </div>
            ) : (
              <div className="text-sm">
                {project.instructions ? (
                  <div className="whitespace-pre-wrap text-muted-foreground">
                    {project.instructions}
                  </div>
                ) : (
                  <div className="text-center py-8 text-muted-foreground">
                    <FileText className="w-8 h-8 mx-auto mb-2 opacity-50" />
                    <p className="text-sm">No instructions yet</p>
                    <p className="text-xs">Add context to help the AI understand your project</p>
                  </div>
                )}
              </div>
            )}
          </div>

          {/* Project Metadata */}
          <div className="border-t border-border p-4">
            <h4 className="font-medium mb-3">Project Details</h4>
            <div className="space-y-2 text-sm">
              <div className="flex justify-between">
                <span className="text-muted-foreground">Created:</span>
                <span>{formatDate(project.createdAt)}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">Progress:</span>
                <span>{project.progress}%</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">Files:</span>
                <span>{project.documents.length}</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}