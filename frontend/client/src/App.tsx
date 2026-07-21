import { Switch, Route, useLocation } from "wouter";
import { queryClient } from "./lib/queryClient";
import { QueryClientProvider } from "@tanstack/react-query";
import { Toaster } from "@/components/ui/toaster";
import { TooltipProvider } from "@/components/ui/tooltip";
import { ThemeProvider } from "@/components/theme-provider";
import { AuthProvider } from "@/contexts/auth-context";
import { ActiveProjectProvider } from "@/contexts/active-project-context";
import { useAuth } from "@/contexts/auth-context";
import { ChatWithArtifacts } from "@/components/chat-with-artifacts";
import ProjectsPage from "@/pages/projects";
import WorkspacesPage from "@/pages/workspaces";
import ProjectDetailPage from "@/pages/project-detail";
import ProjectNotesPage from "@/pages/project-notes";
import NotFound from "@/pages/not-found";
import { AppSidebar } from "@/components/app-sidebar";
import { ThemeToggle } from "@/components/theme-toggle";
import { CreateProjectDialog } from "@/components/create-project-dialog";
import { ToolIntroductionDialog } from "@/components/tool-introduction-dialog";
import { ResizablePanelGroup, ResizablePanel, ResizableHandle } from "@/components/ui/resizable";
import { Button } from "@/components/ui/button";
import { Sheet, SheetContent } from "@/components/ui/sheet";
import { chatHistoryService } from "@/lib/chat-history";
import React, { useState, useEffect, useRef } from "react";
import { useSearch } from "wouter";
import { PanelLeft, Plus, FlaskConical, MessageCircle, Menu, FolderOpen, X } from "lucide-react";
import { useActiveProject } from "@/contexts/active-project-context";
import type { ChatSession } from "@shared/schema";
import { analytics } from "@/lib/analytics"
import { isDesktop, desktopGetPendingDeepLink, desktopOnDeepLink } from "@/lib/desktop";

// Import new pages
import LoginPage from "@/pages/auth/login";
import RegisterPage from "@/pages/auth/register";
import JoinProjectPage from "@/pages/join-project";
import ForgotPasswordPage from "@/pages/auth/forgot-password";
import ResetPasswordPage from "@/pages/auth/reset-password";
import VerifyEmailPage from "@/pages/auth/verify-email";
import MfaChallengePage from "@/pages/auth/mfa-challenge";
import PricingPage from "@/pages/pricing";
import CheckoutPage from "@/pages/checkout";
import BlogPage from "@/pages/blog";
import BlogPostPage from "@/pages/blog-post";
import AboutPage from "@/pages/about";
import TutorialsPage from "@/pages/tutorials";
import PrivacyPage from "@/pages/privacy";
import TermsPage from "@/pages/terms";
import DashboardPage from "@/pages/dashboard";
import BillingPage from "@/pages/billing";
import AdminFeedbackDashboardPage from "@/pages/admin/feedback-dashboard";
import PilotExitSurveyPage from "@/pages/pilot-exit-survey";
import DrugDiscoveryCroDemoPage from "@/pages/drug-discovery-cro-demo";
import IndReportPage from "@/pages/ind-report";
import DebugOutputs from "@/pages/DebugOutputs";
import DebugViewerChain from "@/pages/DebugViewerChain";
import WorkflowDeepLink from "@/pages/WorkflowDeepLink";
import CapabilitiesPage from "@/pages/capabilities";
import { SiteHeader } from "@/components/site-header";
import { SiteFooter } from "@/components/site-footer";
import { TutorialTipOverlay } from "@/components/tutorial-tip-overlay";
import { useUiFlavor } from "@/hooks/use-ui-flavor";
// v2 surface — loaded behind ?ui=v2 / localStorage.biomate_ui flag.
// ResearchApp has @ts-nocheck and a default export now; no @ts-expect-error needed.
import ResearchApp from "@/v2/ResearchApp";
import "@/v2/tokens.css";
import "@/v2/research-tokens.css";
import "@/v2/layout.css";
import "@/v2/research-layout.css";
import "@/v2/tour.css";

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
  const initialTab = searchParams.get('tab') ?? undefined;

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
        initialTab={initialTab}
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

// Root route: redirect guests to /login, show platform for authenticated users
function RootRoute({
  sidebarCollapsed, setSidebarCollapsed, onNewChat, onChatSelect, onCategorySelect,
  onToolSelect, onProjectSelect, onNewProject, currentChatSession, onChatUpdated, chatSessions
}: any) {
  const { isAuthenticated, isLoading } = useAuth()
  const [, setLocation] = useLocation()
  const search = useSearch()
  // All hooks must run before any conditional return (rules of hooks).
  // useUiFlavor must be called every render — moving it after the early
  // return below caused "Rendered more hooks than during the previous render"
  // when isLoading flipped true→false.
  const uiFlavor = useUiFlavor()
  const handledSessionParam = useRef(false)

  // Consume pending use-case query passed via ?q= from the marketing hero input.
  // Cross-domain localStorage doesn't work (biomate.ai vs dev-public.biomate.ai),
  // so register.tsx passes the query through as a URL param → /?q=<encoded>.
  const [initialMessage] = useState<string | undefined>(() => {
    const urlQ = new URLSearchParams(window.location.search).get('q')
    if (urlQ) {
      window.history.replaceState(null, '', window.location.pathname)
      return decodeURIComponent(urlQ)
    }
    // Fallback: hero query parked in sessionStorage during login (auth-context's
    // setLocation('/') mounts this component before login.tsx can append ?q=,
    // so the URL param path above would miss it).
    const stored = sessionStorage.getItem('pendingHeroQuery')
    if (stored) {
      sessionStorage.removeItem('pendingHeroQuery')
      return stored
    }
    return undefined
  })

  useEffect(() => {
    if (!isLoading && !isAuthenticated) {
      // Preserve the pending hero query so it survives the login/register flow
      const dest = initialMessage
        ? '/login?q=' + encodeURIComponent(initialMessage)
        : '/login'
      setLocation(dest)
    }
  }, [isAuthenticated, isLoading, setLocation, initialMessage])

  // Handle ?session=<chatSessionId> — emitted by the "Open" button in the
  // Workflow Runs dialog. Once auth is ready, load the session and strip the param.
  useEffect(() => {
    if (isLoading || !isAuthenticated || handledSessionParam.current) return
    const sessionId = new URLSearchParams(search).get('session')
    if (sessionId) {
      handledSessionParam.current = true
      onChatSelect(sessionId)
      window.history.replaceState(null, '', '/')
    }
  }, [isLoading, isAuthenticated]) // eslint-disable-line react-hooks/exhaustive-deps
  if (isLoading || !isAuthenticated) return null

  // v2 chrome — gated behind ?ui=v2 / localStorage.biomate_ui = 'v2'.
  // The data-v2-ui attribute scopes the v2 design-token :root rules so
  // they don't bleed into the v1 surface.
  if (uiFlavor === 'v2') {
    return (
      <div data-v2-ui style={{ height: '100vh', overflow: 'auto' }}>
        <ResearchApp />
      </div>
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
        initialMessage={initialMessage}
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

/** One-time dismissible banner nudging mobile users to switch to desktop. */
function MobileBanner() {
  const [dismissed, setDismissed] = useState(() => {
    try { return localStorage.getItem('biomate_mobile_banner_dismissed') === '1' } catch { return false }
  })

  if (dismissed) return null

  const dismiss = () => {
    setDismissed(true)
    try { localStorage.setItem('biomate_mobile_banner_dismissed', '1') } catch {}
  }

  return (
    <div
      style={{
        display: 'flex', alignItems: 'center', gap: 8,
        padding: '7px 14px',
        background: 'hsl(214 100% 97%)',
        borderBottom: '1px solid hsl(214 60% 88%)',
        fontSize: 13, flexShrink: 0,
        color: 'hsl(214 60% 30%)',
      }}
      data-testid="mobile-banner"
    >
      <span style={{ flex: 1, lineHeight: 1.4 }}>
        BioMate works best on a computer — some features may be limited on mobile.
      </span>
      <button
        onClick={dismiss}
        aria-label="Dismiss"
        style={{
          border: 'none', background: 'none', cursor: 'pointer',
          padding: '2px 4px', borderRadius: 4, flexShrink: 0,
          color: 'hsl(214 60% 40%)', display: 'flex', alignItems: 'center',
          opacity: 0.8,
        }}
      >
        <X style={{ width: 15, height: 15 }} />
      </button>
    </div>
  )
}

/** Thin bar shown at the top of the main content area when a project is active. */
function ActiveProjectBanner() {
  const { activeProject, setActiveProjectId } = useActiveProject()
  const [, navigate] = useLocation()
  if (!activeProject) return null
  return (
    <div
      style={{
        display: 'flex', alignItems: 'center', gap: 8,
        padding: '4px 14px',
        background: 'var(--bm-surface-2, hsl(var(--accent)))',
        borderBottom: '1px solid var(--bm-border, hsl(var(--border)))',
        fontSize: 12.5, flexShrink: 0,
      }}
      data-testid="active-project-banner"
    >
      <FolderOpen style={{ width: 13, height: 13, opacity: 0.7, flexShrink: 0 }} />
      <span style={{ color: 'var(--bm-text-muted)', userSelect: 'none' }}>Project:</span>
      <button
        style={{ fontWeight: 600, color: 'var(--bm-text)', background: 'none', border: 'none', cursor: 'pointer', padding: 0, fontSize: 'inherit', maxWidth: 260, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}
        onClick={() => navigate(`/projects?project=${activeProject.id}`)}
        data-testid="active-project-banner-name"
      >
        {activeProject.name}
      </button>
      <span style={{ flex: 1 }} />
      <button
        style={{ display: 'flex', alignItems: 'center', gap: 4, fontSize: 11.5, color: 'var(--bm-text-muted)', background: 'none', border: 'none', cursor: 'pointer', padding: '2px 6px', borderRadius: 4 }}
        onClick={() => navigate(`/projects?project=${activeProject.id}`)}
        data-testid="active-project-banner-goto"
      >
        Go to project
      </button>
      <button
        style={{ display: 'flex', alignItems: 'center', color: 'var(--bm-text-muted)', background: 'none', border: 'none', cursor: 'pointer', padding: '2px 4px', borderRadius: 4, opacity: 0.7 }}
        onClick={() => setActiveProjectId(null)}
        aria-label="Clear active project"
        data-testid="active-project-banner-clear"
      >
        <X style={{ width: 13, height: 13 }} />
      </button>
    </div>
  )
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
  const [isMobile, setIsMobile] = useState(() => typeof window !== 'undefined' && window.innerWidth < 768)
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false)

  useEffect(() => {
    if (!isLoading && !isAuthenticated) navigate('/login')
  }, [isAuthenticated, isLoading, navigate])

  useEffect(() => {
    const check = () => setIsMobile(window.innerWidth < 768)
    window.addEventListener('resize', check)
    return () => window.removeEventListener('resize', check)
  }, [])

  if (!isAuthenticated) return null

  const toggleSidebar = () => {
    if (isMobile) {
      setMobileMenuOpen(true)
    } else {
      setSidebarCollapsed(!sidebarCollapsed)
    }
  }

  return (
    <div className="h-dvh w-full flex flex-col" style={{ background: 'var(--bm-bg, hsl(var(--background)))' }}>
      {isMobile && <MobileBanner />}
      {/* Mobile header bar — only on small screens */}
      {isMobile && (
        <div
          className="flex-shrink-0 flex items-center justify-between border-b px-3"
          style={{
            height: 52,
            background: 'var(--bm-surface, hsl(var(--sidebar)))',
            borderColor: 'var(--bm-border, hsl(var(--border)))',
          }}
        >
          <img src="/biomate-logo.png" alt="BioMate" style={{ height: 34, width: 'auto', objectFit: 'contain' }} />
          <button
            onClick={() => setMobileMenuOpen(true)}
            data-testid="button-mobile-menu"
            style={{
              border: 'none', background: 'transparent', cursor: 'pointer',
              padding: '6px', borderRadius: 6, display: 'flex', alignItems: 'center',
              color: 'var(--bm-text-muted)',
            }}
            aria-label="Open menu"
          >
            <Menu className="h-5 w-5" />
          </button>
        </div>
      )}

      {/* Mobile sidebar Sheet */}
      {isMobile && (
        <Sheet open={mobileMenuOpen} onOpenChange={setMobileMenuOpen}>
          <SheetContent side="left" className="p-0 w-72 max-w-[85vw]">
            <AppSidebar
              onNewChat={() => { onNewChat(); setMobileMenuOpen(false); }}
              onChatSelect={(id) => { onChatSelect(id); setMobileMenuOpen(false); }}
              onCategorySelect={onCategorySelect}
              onToolSelect={onToolSelect}
              onProjectSelect={(id) => { onProjectSelect(id); setMobileMenuOpen(false); }}
              onNewProject={() => { onNewProject(); setMobileMenuOpen(false); }}
              onToggleSidebar={() => setMobileMenuOpen(false)}
              activeChatId={activeChatId}
              chatSessions={chatSessions}
            />
          </SheetContent>
        </Sheet>
      )}

      {/* Desktop + mobile content row */}
      <div className="flex flex-1 min-h-0 overflow-hidden">
        {/* Desktop sidebar only */}
        {!isMobile && (
          sidebarCollapsed ? (
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
              <button onClick={onNewChat} data-testid="button-new-chat" className="w-8 h-8 rounded flex items-center justify-center hover:bg-muted transition-colors" title="New chat">
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
            <div className="flex-shrink-0 flex overflow-hidden" style={{ width: 260, minWidth: 260, maxWidth: 260 }}>
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
          )
        )}

        {/* Main content — no separate header; chat-with-artifacts owns its own top bar */}
        <div className="flex-1 min-w-0 flex flex-col overflow-hidden">
          <ActiveProjectBanner />
          {children}
        </div>
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
      <Route path="/join/:token" component={JoinProjectPage} />

      {/* Debug-only harness — see frontend/client/src/pages/DebugOutputs.tsx */}
      <Route path="/debug/outputs/:runId" component={DebugOutputs} />
      <Route path="/debug/viewer/:runId" component={DebugViewerChain} />
      <Route path="/forgot-password" component={ForgotPasswordPage} />
      <Route path="/reset-password" component={ResetPasswordPage} />
      <Route path="/verify-email" component={VerifyEmailPage} />
      <Route path="/mfa-challenge" component={MfaChallengePage} />

      {/* Public pages */}
      {/* Pricing page — temporarily disabled until payment flow is fully tested
      <Route path="/pricing">
        <PublicPageLayout>
          <PricingPage />
        </PublicPageLayout>
      </Route>
      */}
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
      <Route path="/tutorials">
        <PublicPageLayout>
          <TutorialsPage />
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

      {/* Checkout page — temporarily disabled until payment flow is fully tested
      <Route path="/checkout/:plan">
        <PublicPageLayout>
          <CheckoutPage />
        </PublicPageLayout>
      </Route>
      */}

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

      <Route path="/ind-report">
        <AuthenticatedPageLayout>
          <IndReportPage />
        </AuthenticatedPageLayout>
      </Route>

      <Route path="/capabilities">
        <PublicPageLayout>
          <CapabilitiesPage />
        </PublicPageLayout>
      </Route>

{/* Deep link from chat connectors — loads a generated workflow by id and
          opens the workflow panel focused on it. See pages/WorkflowDeepLink.tsx. */}
      <Route path="/workflow/:id" component={WorkflowDeepLink} />

{/* Root: platform for authenticated users, redirect to /login for guests */}
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

      {/* /workspaces — LTM project framework UI (project memory, episodes,
          procedures, cross-session dataset isolation). See
          docs/20260612_DATASET_STORAGE_AND_SESSION_BOUNDARIES.md. */}
      <Route path="/workspaces" component={WorkspacesPage} />

      {/* /projects/:projectId/notes — Stream-A LLM synthesis page.
          Backend: frontend/server/notes-routes.ts (commit e3955d0da). */}
      <Route path="/projects/:projectId/notes">
        <AuthenticatedPageLayout>
          <ProjectNotesPage />
        </AuthenticatedPageLayout>
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

  // Desktop deep link handling: biomate://project/<id> and biomate://session/<id>
  useEffect(() => {
    if (!isDesktop()) return
    const handleDeepLink = (url: string) => {
      const match = url.match(/^biomate:\/\/(project|session)\/([^?#]+)/)
      if (!match) return
      const [, type, id] = match
      if (type === 'project') setLocation(`/projects?project=${encodeURIComponent(id)}`)
      if (type === 'session') setLocation(`/?session=${encodeURIComponent(id)}`)
    }
    desktopGetPendingDeepLink().then(url => { if (url) handleDeepLink(url) })
    const unlisten = desktopOnDeepLink(handleDeepLink)
    return unlisten
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  const { user } = useAuth()

  // Reload sidebar session list whenever the authenticated user changes.
  // Do NOT reset currentChatSession here — the auto-submit may have just created one.
  useEffect(() => {
    if (user?.id) chatHistoryService.setUserId(String(user.id))
    const sessions = chatHistoryService.getAllSessions()
    setChatSessions(sessions)
  }, [user?.id])

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
  const { isAuthenticated, user } = useAuth()

  useEffect(() => {
    chatHistoryService.setBackendSyncActive(isAuthenticated)
  }, [isAuthenticated])

  // Scope chat history to the authenticated user so new users don't see others' chats
  useEffect(() => {
    if (user?.id) chatHistoryService.setUserId(String(user.id))
  }, [user?.id])

  return <App />
}

export default function RootApp() {
  return (
    <QueryClientProvider client={queryClient}>
      <ThemeProvider defaultTheme="light" storageKey="biomate-ui-theme">
        <AuthProvider>
          <ActiveProjectProvider>
            <AppWithAuthSync />
          </ActiveProjectProvider>
        </AuthProvider>
      </ThemeProvider>
      <TutorialTipOverlay />
    </QueryClientProvider>
  )
}
