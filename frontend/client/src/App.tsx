import { Switch, Route, useLocation } from "wouter";
import { queryClient } from "./lib/queryClient";
import { QueryClientProvider } from "@tanstack/react-query";
import { Toaster } from "@/components/ui/toaster";
import { TooltipProvider } from "@/components/ui/tooltip";
import { ThemeProvider } from "@/components/theme-provider";
import { AuthProvider } from "@/contexts/auth-context";
import { useAuth } from "@/contexts/auth-context";
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
import { useSearch } from "wouter";
import { PanelLeft, Plus, FlaskConical, MessageCircle } from "lucide-react";
import type { ChatSession } from "@shared/schema";
import { analytics } from "@/lib/analytics";

// Import new pages
import LandingPage from "@/pages/landing";
import LoginPage from "@/pages/auth/login";
import RegisterPage from "@/pages/auth/register";
import ForgotPasswordPage from "@/pages/auth/forgot-password";
import ResetPasswordPage from "@/pages/auth/reset-password";
import VerifyEmailPage from "@/pages/auth/verify-email";
import PricingPage from "@/pages/pricing";
import CheckoutPage from "@/pages/checkout";
import BlogPage from "@/pages/blog";
import BlogPostPage from "@/pages/blog-post";
import AboutPage from "@/pages/about";
import PrivacyPage from "@/pages/privacy";
import TermsPage from "@/pages/terms";
import DashboardPage from "@/pages/dashboard";
import BillingPage from "@/pages/billing";
import AdminFeedbackDashboardPage from "@/pages/admin/feedback-dashboard";
import PilotExitSurveyPage from "@/pages/pilot-exit-survey";
import DrugDiscoveryCroDemoPage from "@/pages/drug-discovery-cro-demo";
import { SiteHeader } from "@/components/site-header";
import { SiteFooter } from "@/components/site-footer";
import { TutorialTipOverlay } from "@/components/tutorial-tip-overlay";

interface ToolItem {
  id: string
  name: string
  description: string
  complexity: 'simple' | 'intermediate' | 'complex'
  category: string
  icon: any
}

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

// Smart root route: shows marketing landing for guests, platform for authenticated users
function RootRoute({
  sidebarCollapsed, setSidebarCollapsed, onNewChat, onChatSelect, onCategorySelect,
  onToolSelect, onProjectSelect, onNewProject, currentChatSession, onChatUpdated, chatSessions
}: any) {
  const { isAuthenticated, isLoading } = useAuth()
  if (isLoading) return null
  if (!isAuthenticated) {
    return (
      <PublicPageLayout>
        <LandingPage />
      </PublicPageLayout>
    )
  }
  return (
    <PlatformLayout
      sidebarCollapsed={sidebarCollapsed}
      setSidebarCollapsed={setSidebarCollapsed}
      onNewChat={onNewChat}
      onChatSelect={onChatSelect}
      onCategorySelect={onCategorySelect}
      onToolSelect={onToolSelect}
      onProjectSelect={onProjectSelect}
      onNewProject={onNewProject}
      activeChatId={currentChatSession?.id}
      chatSessions={chatSessions}
    >
      <ChatWithArtifacts
        currentChatSession={currentChatSession}
        onChatUpdated={onChatUpdated}
        onWorkflowPanelOpenChange={(open) => setSidebarCollapsed(open)}
      />
    </PlatformLayout>
  )
}

// Public pages wrapper with header and footer
function PublicPageLayout({ children }: { children: React.ReactNode }) {
  return (
    <>
      <SiteHeader />
      <main>{children}</main>
      <SiteFooter />
    </>
  );
}

// NextflowDemoPage removed

// Authenticated pages wrapper with header — redirects to /login if not authenticated
function AuthenticatedPageLayout({ children }: { children: React.ReactNode }) {
  const { isAuthenticated, isLoading } = useAuth()
  const [, navigate] = useLocation()
  useEffect(() => {
    if (!isLoading && !isAuthenticated) navigate('/login')
  }, [isAuthenticated, isLoading, navigate])
  if (!isAuthenticated) return null
  return (
    <>
      <SiteHeader isAuthenticated />
      <main>{children}</main>
    </>
  );
}

// Platform layout with sidebar for chat interface
function PlatformLayout({
  children,
  sidebarCollapsed,
  setSidebarCollapsed,
  onNewChat,
  onChatSelect,
  onCategorySelect,
  onToolSelect,
  onProjectSelect,
  onNewProject,
  activeChatId,
  chatSessions
}: {
  children: React.ReactNode
  sidebarCollapsed: boolean
  setSidebarCollapsed: (value: boolean) => void
  onNewChat: () => void
  onChatSelect: (id: string) => void
  onCategorySelect: (category: string) => void
  onToolSelect: (tool: ToolItem) => void
  onProjectSelect: (id: string) => void
  onNewProject: () => void
  activeChatId?: string
  chatSessions: ChatSession[]
}) {
  const { isAuthenticated, isLoading } = useAuth()
  const [, navigate] = useLocation()

  useEffect(() => {
    if (!isLoading && !isAuthenticated) navigate('/login')
  }, [isAuthenticated, isLoading, navigate])

  if (!isAuthenticated) return null

  const toggleSidebar = () => {
    setSidebarCollapsed(!sidebarCollapsed)
  }

  return (
    <div className="h-screen w-full flex" style={{ background: 'var(--bm-bg, hsl(var(--background)))' }}>
      {/* Sidebar: full when not collapsed, slim icon rail when collapsed */}
      {sidebarCollapsed ? (
        /* Slim icon rail — 52px, always visible when panel is open */
        <div
          className="flex-shrink-0 flex flex-col items-center border-r py-3 gap-3"
          style={{
            width: 52,
            background: 'var(--bm-surface, hsl(var(--sidebar)))',
            borderColor: 'var(--bm-border, hsl(var(--border)))',
          }}
          title="Sidebar collapsed — panel is open"
        >
          {/* Brand mark */}
          <button
            onClick={toggleSidebar}
            className="w-8 h-8 rounded-lg flex items-center justify-center font-mono font-bold text-sm flex-shrink-0"
            style={{
              background: 'var(--bm-text, hsl(var(--foreground)))',
              color: 'var(--bm-bg-elev, white)',
              fontSize: 13,
              letterSpacing: '-0.03em',
            }}
            data-testid="button-sidebar-expand"
            title="Expand sidebar"
          >
            B
          </button>
          {/* Icon buttons */}
          <button onClick={onNewChat} className="w-8 h-8 rounded flex items-center justify-center hover:bg-muted transition-colors" title="New chat">
            <Plus className="h-4 w-4" style={{ color: 'var(--bm-text-muted)' }} />
          </button>
          <button className="w-8 h-8 rounded flex items-center justify-center hover:bg-muted transition-colors" title="Workflows">
            <FlaskConical className="h-4 w-4" style={{ color: 'var(--bm-text-muted)' }} />
          </button>
          <button className="w-8 h-8 rounded flex items-center justify-center hover:bg-muted transition-colors" title="Chat history">
            <MessageCircle className="h-4 w-4" style={{ color: 'var(--bm-text-muted)' }} />
          </button>
          <div className="flex-1" />
          <ThemeToggle />
        </div>
      ) : (
        /* Full sidebar */
        <div className="flex-shrink-0 flex" style={{ width: 260 }}>
          <AppSidebar
            onNewChat={onNewChat}
            onChatSelect={onChatSelect}
            onCategorySelect={onCategorySelect}
            onToolSelect={onToolSelect}
            onProjectSelect={onProjectSelect}
            onNewProject={onNewProject}
            onToggleSidebar={toggleSidebar}
            activeChatId={activeChatId}
            chatSessions={chatSessions}
          />
        </div>
      )}

      {/* Main content — no separate header; chat-with-artifacts owns its own top bar */}
      <div className="flex-1 min-w-0 flex flex-col overflow-hidden">
        {children}
      </div>
    </div>
  );
}

interface RouterProps {
  currentChatSession: ChatSession | null
  onChatUpdated: (session: ChatSession) => void
  sidebarCollapsed: boolean
  setSidebarCollapsed: (value: boolean) => void
  onNewChat: () => void
  onChatSelect: (id: string) => void
  onCategorySelect: (category: string) => void
  onToolSelect: (tool: ToolItem) => void
  onProjectSelect: (id: string) => void
  onNewProject: () => void
  chatSessions: ChatSession[]
}

function Router({
  currentChatSession,
  onChatUpdated,
  sidebarCollapsed,
  setSidebarCollapsed,
  onNewChat,
  onChatSelect,
  onCategorySelect,
  onToolSelect,
  onProjectSelect,
  onNewProject,
  chatSessions
}: RouterProps) {
  return (
    <Switch>
      {/* Auth pages */}
      <Route path="/login" component={LoginPage} />
      <Route path="/register" component={RegisterPage} />
      <Route path="/forgot-password" component={ForgotPasswordPage} />
      <Route path="/reset-password" component={ResetPasswordPage} />
      <Route path="/verify-email" component={VerifyEmailPage} />

      {/* Public pages */}
      <Route path="/pricing">
        <PublicPageLayout>
          <PricingPage />
        </PublicPageLayout>
      </Route>
      <Route path="/blog">
        <PublicPageLayout>
          <BlogPage />
        </PublicPageLayout>
      </Route>
      <Route path="/blog/:slug">
        <PublicPageLayout>
          <BlogPostPage />
        </PublicPageLayout>
      </Route>
      <Route path="/about">
        <PublicPageLayout>
          <AboutPage />
        </PublicPageLayout>
      </Route>
      <Route path="/privacy">
        <PublicPageLayout>
          <PrivacyPage />
        </PublicPageLayout>
      </Route>
      <Route path="/terms">
        <PublicPageLayout>
          <TermsPage />
        </PublicPageLayout>
      </Route>

      {/* Checkout page */}
      <Route path="/checkout/:plan">
        <PublicPageLayout>
          <CheckoutPage />
        </PublicPageLayout>
      </Route>

{/* NextflowDemoPage removed */}

      {/* Authenticated pages */}
      {/* <Route path="/dashboard">
        <AuthenticatedPageLayout>
          <DashboardPage />
        </AuthenticatedPageLayout>
      </Route> */}

      {/* <Route path="/billing">
        <AuthenticatedPageLayout>
          <BillingPage />
        </AuthenticatedPageLayout>
      </Route> */}

      <Route path="/admin/feedback-dashboard">
        <AuthenticatedPageLayout>
          <AdminFeedbackDashboardPage />
        </AuthenticatedPageLayout>
      </Route>

      <Route path="/pilot-exit-survey">
        <AuthenticatedPageLayout>
          <PilotExitSurveyPage />
        </AuthenticatedPageLayout>
      </Route>

      <Route path="/drug-discovery-cro">
        <AuthenticatedPageLayout>
          <DrugDiscoveryCroDemoPage />
        </AuthenticatedPageLayout>
      </Route>

      {/* Root: landing page for guests, platform for authenticated users */}
      <Route path="/">
        <RootRoute
          sidebarCollapsed={sidebarCollapsed}
          setSidebarCollapsed={setSidebarCollapsed}
          onNewChat={onNewChat}
          onChatSelect={onChatSelect}
          onCategorySelect={onCategorySelect}
          onToolSelect={onToolSelect}
          onProjectSelect={onProjectSelect}
          onNewProject={onNewProject}
          currentChatSession={currentChatSession}
          onChatUpdated={onChatUpdated}
          chatSessions={chatSessions}
        />
      </Route>

      <Route path="/projects">
        <PlatformLayout
          sidebarCollapsed={sidebarCollapsed}
          setSidebarCollapsed={setSidebarCollapsed}
          onNewChat={onNewChat}
          onChatSelect={onChatSelect}
          onCategorySelect={onCategorySelect}
          onToolSelect={onToolSelect}
          onProjectSelect={onProjectSelect}
          onNewProject={onNewProject}
          activeChatId={currentChatSession?.id}
          chatSessions={chatSessions}
        >
          <ProjectsRouter />
        </PlatformLayout>
      </Route>

      {/* 404 */}
      <Route component={NotFound} />
    </Switch>
  );
}

function App() {
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false)
  const [showCreateProjectDialog, setShowCreateProjectDialog] = useState(false)
  const [showToolDialog, setShowToolDialog] = useState(false)
  const [selectedTool, setSelectedTool] = useState<ToolItem | null>(null)
  const [currentChatSession, setCurrentChatSession] = useState<ChatSession | null>(null)
  const [chatSessions, setChatSessions] = useState<ChatSession[]>([])
  const [location, setLocation] = useLocation()

  // Track page views on route change
  useEffect(() => {
    analytics.track('page_viewed', { page: location })
  }, [location])

  // Load chat history list on mount, but start with a fresh empty session
  // so users always land on a clean chat (previous sessions accessible in sidebar)
  useEffect(() => {
    const sessions = chatHistoryService.getAllSessions()
    setChatSessions(sessions)
    // Do not auto-load the last session — the user sees an empty welcome state
    // and can pick a previous conversation from the sidebar if needed
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

  const handleChatSelect = async (chatId: string) => {
    console.log('Loading chat session:', chatId)
    const local = chatHistoryService.getSession(chatId)
    // If session has no messages (e.g. synced from backend on another machine), fetch full detail
    const session = (!local || local.messages.length === 0)
      ? await chatHistoryService.fetchSessionDetail(chatId)
      : local
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
    <TooltipProvider>
      <Router
        currentChatSession={currentChatSession}
        onChatUpdated={handleChatUpdated}
        sidebarCollapsed={sidebarCollapsed}
        setSidebarCollapsed={setSidebarCollapsed}
        onNewChat={handleNewChat}
        onChatSelect={handleChatSelect}
        onCategorySelect={handleCategorySelect}
        onToolSelect={handleToolSelect}
        onProjectSelect={handleProjectSelect}
        onNewProject={handleNewProject}
        chatSessions={chatSessions}
      />

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
      <Toaster />
    </TooltipProvider>
  );
}


function AppWithAuthSync() {
  const { isAuthenticated } = useAuth()

  useEffect(() => {
    chatHistoryService.setBackendSyncActive(isAuthenticated)
  }, [isAuthenticated])

  return <App />
}

export default function RootApp() {
  return (
    <QueryClientProvider client={queryClient}>
      <ThemeProvider defaultTheme="light" storageKey="biomate-ui-theme">
        <AuthProvider>
          <AppWithAuthSync />
        </AuthProvider>
      </ThemeProvider>
      <TutorialTipOverlay />
    </QueryClientProvider>
  )
}
