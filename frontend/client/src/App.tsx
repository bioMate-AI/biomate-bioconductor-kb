import { Switch, Route } from "wouter";
import { queryClient } from "./lib/queryClient";
import { QueryClientProvider } from "@tanstack/react-query";
import { Toaster } from "@/components/ui/toaster";
import { TooltipProvider } from "@/components/ui/tooltip";
import { ThemeProvider } from "@/components/theme-provider";
import { ChatWithArtifacts } from "@/components/chat-with-artifacts";
import ProjectsPage from "@/pages/projects";
import ProjectDetailPage from "@/pages/project-detail";
import NotFound from "@/pages/not-found";
import { AppSidebar } from "@/components/app-sidebar";
import { ThemeToggle } from "@/components/theme-toggle";
import { CreateProjectDialog } from "@/components/create-project-dialog";
import { ToolIntroductionDialog } from "@/components/tool-introduction-dialog";
import { ResizablePanelGroup, ResizablePanel, ResizableHandle } from "@/components/ui/resizable";
import { Button } from "@/components/ui/button";
import { chatHistoryService } from "@/lib/chat-history";
import { useState, useEffect } from "react";
import { useSearch, useLocation } from "wouter";
import { PanelLeft } from "lucide-react";
import type { ChatSession } from "@shared/schema";

function ProjectsRouter() {
  const [, setLocation] = useLocation();
  const search = useSearch();
  const searchParams = new URLSearchParams(search);
  const projectId = searchParams.get('project');
  
  const handleProjectSelect = (id: string) => {
    setLocation(`/projects?project=${id}`);
  };
  
  const handleBackToProjects = () => {
    setLocation('/projects');
  };
  
  if (projectId) {
    return (
      <ProjectDetailPage 
        projectId={projectId} 
        onBack={handleBackToProjects}
      />
    );
  } else {
    return (
      <ProjectsPage 
        onProjectSelect={handleProjectSelect}
      />
    );
  }
}

function Router({ currentChatSession, onChatUpdated }: { currentChatSession: ChatSession | null, onChatUpdated: (session: ChatSession) => void }) {
  return (
    <Switch>
      <Route path="/">
        <ChatWithArtifacts 
          currentChatSession={currentChatSession}
          onChatUpdated={onChatUpdated}
        />
      </Route>
      <Route path="/projects" component={ProjectsRouter} />
      <Route component={NotFound} />
    </Switch>
  );
}

interface ToolItem {
  id: string
  name: string
  description: string
  complexity: 'simple' | 'intermediate' | 'complex'
  category: string
  icon: any
}

function App() {
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false)
  const [showCreateProjectDialog, setShowCreateProjectDialog] = useState(false)
  const [showToolDialog, setShowToolDialog] = useState(false)
  const [selectedTool, setSelectedTool] = useState<ToolItem | null>(null)
  const [currentChatSession, setCurrentChatSession] = useState<ChatSession | null>(null)
  const [chatSessions, setChatSessions] = useState<ChatSession[]>([])
  const [, setLocation] = useLocation()

  // Initialize chat history on mount
  useEffect(() => {
    const sessions = chatHistoryService.getAllSessions()
    setChatSessions(sessions)
    if (sessions.length > 0) {
      setCurrentChatSession(sessions[0]) // Load most recent chat
    }
  }, [])

  const handleNewChat = () => {
    console.log('Creating new chat session')
    const newSession = chatHistoryService.createNewSession()
    setCurrentChatSession(newSession)
    
    // Update sessions list
    const updatedSessions = chatHistoryService.getAllSessions()
    setChatSessions(updatedSessions)
    
    // Navigate to home page for new chat
    setLocation('/')
  }

  const handleChatSelect = (chatId: string) => {
    console.log('Loading chat session:', chatId)
    const session = chatHistoryService.getSession(chatId)
    if (session) {
      setCurrentChatSession(session)
      // Navigate to home page for chat
      setLocation('/')
    }
  }

  const handleChatUpdated = (session: ChatSession) => {
    console.log('App: Updating chat session:', session.id, 'workflows:', session.workflows)
    // Save the updated session to chat history service
    chatHistoryService.updateSession(session.id, session)
    setCurrentChatSession(session)
    setChatSessions(chatHistoryService.getAllSessions())
  }

  const handleCategorySelect = (category: string) => {
    console.log('Selected category:', category)
  }

  const handleToolSelect = (tool: ToolItem) => {
    console.log('Tool selected:', tool.name)
    setSelectedTool(tool)
    setShowToolDialog(true)
  }

  const handleAddToWorkflow = (tool: ToolItem) => {
    console.log('Adding tool to workflow:', tool.name)
    setShowToolDialog(false)
  }

  const handleStartChat = (tool: ToolItem) => {
    console.log('Starting chat about tool:', tool.name)
    setShowToolDialog(false)
  }

  const toggleSidebar = () => {
    setSidebarCollapsed(!sidebarCollapsed)
  }

  const handleProjectSelect = (projectId: string) => {
    setLocation(`/projects?project=${projectId}`)
  }

  const handleNewProject = () => {
    setShowCreateProjectDialog(true)
  }

  const handleProjectCreated = (projectId: string) => {
    setShowCreateProjectDialog(false)
    setLocation(`/projects?project=${projectId}`)
  }

  return (
    <QueryClientProvider client={queryClient}>
      <ThemeProvider defaultTheme="light" storageKey="biomate-ui-theme">
        <TooltipProvider>
          <div className="h-screen w-full bg-background">
            <ResizablePanelGroup direction="horizontal" className="h-full">
              {/* Resizable Left Sidebar */}
              {!sidebarCollapsed && (
                <>
                  <ResizablePanel 
                    defaultSize={20}
                    minSize={15}
                    maxSize={35}
                    className="flex"
                  >
                    <AppSidebar 
                      onNewChat={handleNewChat}
                      onChatSelect={handleChatSelect}
                      onCategorySelect={handleCategorySelect}
                      onToolSelect={handleToolSelect}
                      onProjectSelect={handleProjectSelect}
                      onNewProject={handleNewProject}
                      onToggleSidebar={toggleSidebar}
                      activeChatId={currentChatSession?.id}
                      chatSessions={chatSessions}
                    />
                  </ResizablePanel>
                  
                  <ResizableHandle withHandle />
                </>
              )}
              
              {/* Main Content Area */}
              <ResizablePanel defaultSize={sidebarCollapsed ? 100 : 80} minSize={65} className="flex flex-col">
                {/* Header */}
                <header className="flex items-center justify-between p-4 border-b bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60">
                  {sidebarCollapsed && (
                    <Button
                      variant="ghost"
                      size="icon"
                      onClick={toggleSidebar}
                      className="h-7 w-7"
                      data-testid="button-sidebar-toggle-main"
                    >
                      <PanelLeft className="h-4 w-4" />
                      <span className="sr-only">Show Sidebar</span>
                    </Button>
                  )}
                  <div className="flex-1" />
                  <ThemeToggle />
                </header>

                {/* Content */}
                <div className="flex-1 overflow-hidden">
                  <Router currentChatSession={currentChatSession} onChatUpdated={handleChatUpdated} />
                </div>
              </ResizablePanel>
            </ResizablePanelGroup>
            
            <ToolIntroductionDialog
              open={showToolDialog}
              onOpenChange={setShowToolDialog}
              tool={selectedTool}
              onAddToWorkflow={handleAddToWorkflow}
              onStartChat={handleStartChat}
            />
            
            <CreateProjectDialog
              open={showCreateProjectDialog}
              onOpenChange={setShowCreateProjectDialog}
              onProjectCreated={handleProjectCreated}
            />
          </div>
          <Toaster />
        </TooltipProvider>
      </ThemeProvider>
    </QueryClientProvider>
  );
}

export default App;
