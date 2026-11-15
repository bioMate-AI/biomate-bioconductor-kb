import { t } from "@/lib/i18n";
import { HintTip, HintScope } from "@/components/ui/hint-tip";
import { Switch, Route, useLocation } from "wouter";
import { queryClient } from "./lib/queryClient";
import { QueryClientProvider } from "@tanstack/react-query";
import { Toaster } from "@/components/ui/toaster";
import { TooltipProvider } from "@/components/ui/tooltip";
import { ThemeProvider } from "@/components/theme-provider";
import { AuthProvider } from "@/contexts/auth-context";
import { ActiveProjectProvider } from "@/contexts/active-project-context";
import { OnPremLicenseGate } from "@/components/onprem-license-gate";
import { useAuth } from "@/contexts/auth-context";
import { ChatWithArtifacts } from "@/components/chat-with-artifacts";
import ProjectsPage from "@/pages/projects";
import WorkspacesPage from "@/pages/workspaces";
import ProjectDetailPage from "@/pages/project-detail";
import ProjectNotesPage from "@/pages/project-notes";
import NotFound from "@/pages/not-found";
import { useOneShotUrlParam } from "@/lib/one-shot-url-param";
import { AppSidebar } from "@/components/app-sidebar";
// Theme toggle hidden — light only for now (dark mode not reviewed).
// import { ThemeToggle } from "@/components/theme-toggle";
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
import { useChatProjectLink } from "@/hooks/use-chat-project-link";
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
import BillingPage from "@/pages/billing";
import AdminFeedbackDashboardPage from "@/pages/admin/feedback-dashboard";
import SystemDashboardPage from "@/pages/admin/system-dashboard";
import PilotExitSurveyPage from "@/pages/pilot-exit-survey";
import DrugDiscoveryCroDemoPage from "@/pages/drug-discovery-cro-demo";
import IndReportPage from "@/pages/ind-report";
import DebugOutputs from "@/pages/DebugOutputs";
import DebugViewerChain from "@/pages/DebugViewerChain";
import DebugAfterRun from "@/pages/DebugAfterRun";
import WorkflowDeepLink from "@/pages/WorkflowDeepLink";
import RunLanding from "@/pages/RunLanding";
import CapabilitiesPage from "@/pages/capabilities";
import { ModelsPanel } from "@/components/models";
import { ConnectorsDialog } from "@/components/connectors-dialog";
import DataHubPage from "@/pages/data-hub";
import { DesignGenerate } from "@/components/design-generate/DesignGenerate";
import { SiteHeader } from "@/components/site-header";
import { SiteFooter } from "@/components/site-footer";
import { TutorialTipOverlay } from "@/components/tutorial-tip-overlay";
// v2 design-token/layout CSS retained for AfterRunReport (active UI, ?afterrun=v2).
// The old ?ui=v2 ResearchApp test surface was removed to avoid confusion.
import "@/v2/tokens.css";
import "@/v2/research-tokens.css";
import "@/v2/layout.css";
import "@/v2/research-layout.css";
import "@/v2/tour.css";
import { IND_REPORT_ENABLED } from "@/lib/feature-flags";

interface ToolItem {
  id: string
  name: string
  description: string
  complexity: 'simple' | 'intermediate' | 'complex'
  category: string
  icon: any
}

export function ProjectsRouter() {
  const { setActiveProjectId } = useActiveProject();
  const [, setLocation] = useLocation();
  const search = useSearch();
  const searchParams = new URLSearchParams(search);
  const projectId = searchParams.get('project');
  const initialTab = searchParams.get('tab') ?? 'chat';
  useEffect(() => {
    if (!projectId) return;
    setActiveProjectId(projectId);
    if (initialTab === "workflows") {
      // Retired duplicate project Runs view: keep project context and open Files.
      // Do not create a chat or reconstruct a workflow as a new run.
      setLocation(`/files?project=${encodeURIComponent(projectId)}`, { replace: true });
    } else if (initialTab === "files") setLocation("/files");
    // Opening project Chats only reads saved sessions. New Chat remains an explicit action.
  }, [projectId, initialTab]);

  const handleProjectSelect = (id: string) => {
    setLocation(`/projects?project=${id}`);
  };

  const handleBackToProjects = () => {
    setLocation('/projects');
  };

  if (projectId) {
    return (
      <ProjectDetailPage
        key={`${projectId}:${initialTab ?? "files"}`}
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
  const { setActiveProjectId } = useActiveProject()
  useChatProjectLink(search, !isLoading && isAuthenticated, setActiveProjectId)
  // All hooks must run before any conditional return (rules of hooks).
  const handledSessionParam = useRef(false)

  // Consume pending use-case query passed via ?q= from the marketing hero input.
  // Cross-domain localStorage doesn't work (biomate.ai vs dev-public.biomate.ai),
  // so register.tsx passes the query through as a URL param → /?q=<encoded>.
  const [initialMessage, setInitialMessage] = useState<string | undefined>(() => {
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

  // Demo files tag — e.g. 'mg_demo' — passed alongside ?q= from the landing page chip.
  const [initialDemoFiles] = useState<string | undefined>(() => {
    const urlD = new URLSearchParams(window.location.search).get('demoFiles')
    if (urlD) return urlD
    const stored = sessionStorage.getItem('pendingDemoFiles')
    if (stored) { sessionStorage.removeItem('pendingDemoFiles'); return stored }
    return undefined
  })

  // Pre-filled draft (?draft=) from the project "Analyze with BioMate" flow. Unlike ?q=,
  // this populates the chat input for review/edit and is NOT auto-submitted. Only the
  // draft param is stripped (?project= / ?attachFile= stay for the composer), and the
  // value is consumed once applied — see lib/one-shot-url-param.ts.
  const [initialDraft, consumeInitialDraft] = useOneShotUrlParam('draft')
  // `?send=1` with a draft: the user already chose to run it (data panel "Run full QC") — the
  // composer submits the draft once its attached files are linked. Read once, like the draft.
  const [initialDraftSend] = useOneShotUrlParam('send')

  useEffect(() => {
    if (!isLoading && !isAuthenticated) {
      // Preserve both the query and demo-files tag through the login flow
      const params = new URLSearchParams()
      if (initialMessage) params.set('q', initialMessage)
      if (initialDemoFiles) params.set('demoFiles', initialDemoFiles)
      const qs = params.toString()
      setLocation('/login' + (qs ? '?' + qs : ''))
    }
  }, [isAuthenticated, isLoading, setLocation, initialMessage, initialDemoFiles])

  // Handle ?session=<chatSessionId> — the open chat's address (written by App
  // whenever a chat is open, and by the Runs dialog / project "Open" links).
  // Once auth is ready, load it. The param is KEPT so a page refresh reopens
  // the same chat instead of landing on a new one.
  useEffect(() => {
    if (isLoading || !isAuthenticated || handledSessionParam.current) return
    const sessionId = new URLSearchParams(search).get('session')
    if (sessionId) {
      handledSessionParam.current = true
      onChatSelect(sessionId)
    }
  }, [isLoading, isAuthenticated]) // eslint-disable-line react-hooks/exhaustive-deps
  if (isLoading || !isAuthenticated) return null

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
        key={currentChatSession?.id ?? 'new'}
        currentChatSession={currentChatSession}
        onChatUpdated={onChatUpdated}
        onWorkflowPanelOpenChange={(open) => setSidebarCollapsed(open)}
        initialMessage={initialMessage}
        initialDemoFiles={initialDemoFiles}
        initialDraft={initialDraft}
        initialDraftSend={initialDraftSend === '1'}
        // One-shot URL payloads (?q= auto-send, ?draft= prefill) are consumed
        // HERE, at their source. ChatWithArtifacts is keyed by session id, so the
        // first send (new chat → real session) remounts it; if these props were
        // still set, the fresh instance re-applied the draft into the composer
        // the user had just sent from (and would re-send ?q=).
        onInitialMessageConsumed={() => setInitialMessage(undefined)}
        onInitialDraftConsumed={consumeInitialDraft}
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
        fontSize: 'var(--fs-base)', flexShrink: 0,
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
/** Routes that render the chat surface. Its own header already carries the
 *  project chip, so the project banner would be a second, redundant line. */
export function isChatRoute(path: string): boolean {
  return path === '/' || path === ''
}

function ActiveProjectBanner() {
  const { activeProject, setActiveProjectId } = useActiveProject()
  const [location, navigate] = useLocation()
  if (!activeProject || isChatRoute(location)) return null
  return (
    <div
      style={{
        display: 'flex', alignItems: 'center', gap: 8,
        padding: '4px 14px',
        background: 'var(--bm-surface-2, hsl(var(--accent)))',
        borderBottom: '1px solid var(--bm-border, hsl(var(--border)))',
        fontSize: 'var(--fs-base)', flexShrink: 0,
      }}
      data-testid="active-project-banner"
    >
      <FolderOpen style={{ width: 13, height: 13, opacity: 0.7, flexShrink: 0 }} />
      <span style={{ color: 'var(--bm-text-muted)', userSelect: 'none' }}>{t('active_project.label')}</span>
      <button
        style={{ fontWeight: 600, color: 'var(--bm-text)', background: 'none', border: 'none', cursor: 'pointer', padding: 0, fontSize: 'inherit', maxWidth: 260, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}
        onClick={() => navigate(`/projects?project=${activeProject.id}`)}
        data-testid="active-project-banner-name"
      >
        {activeProject.name}
      </button>
      <span style={{ flex: 1 }} />
      <button
        style={{ display: 'flex', alignItems: 'center', gap: 4, fontSize: 'var(--fs-sm)', color: 'var(--bm-text-muted)', background: 'none', border: 'none', cursor: 'pointer', padding: '2px 6px', borderRadius: 4 }}
        onClick={() => navigate(`/projects?project=${activeProject.id}`)}
        data-testid="active-project-banner-goto"
      >
        {t('panel.go_to_project')}
      </button>
      <button
        style={{ display: 'flex', alignItems: 'center', color: 'var(--bm-text-muted)', background: 'none', border: 'none', cursor: 'pointer', padding: '2px 4px', borderRadius: 4, opacity: 0.7 }}
        onClick={() => setActiveProjectId(null)}
        aria-label={t('active_project.clear')}
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
            >
              {/* Brand mark */}
              <HintTip hint={t('hint.rail.expand')}>
              <button
                onClick={toggleSidebar}
                className="w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0 overflow-hidden"
                style={{ padding: 0, background: 'transparent', border: 'none' }}
                data-testid="button-sidebar-expand"
                aria-label={t('nav.expand_sidebar')}
              >
                {/* Brand mark = the site's browser icon (favicon), not a plain "B"
                    (founder: "use the browser icon of biomate website"). */}
                <img src="/favicon.png" alt="BioMate" className="w-full h-full object-cover rounded-lg" />
              </button>
              </HintTip>
              {/* Icon buttons */}
              <HintTip hint={t('hint.rail.new_chat')}>
              <button onClick={onNewChat} data-testid="button-new-chat" className="w-8 h-8 rounded flex items-center justify-center hover:bg-muted transition-colors" aria-label={t('nav.new_chat')}>
                <Plus className="h-4 w-4" style={{ color: 'var(--bm-text-muted)' }} />
              </button>
              </HintTip>
              {/* Import workflow is available under Settings in the expanded sidebar. */}
              <HintTip hint={t('hint.rail.history')}>
              <button onClick={toggleSidebar} data-testid="button-rail-chat-history" className="w-8 h-8 rounded flex items-center justify-center hover:bg-muted transition-colors" aria-label={t('nav.chat_history')}>
                <MessageCircle className="h-4 w-4" style={{ color: 'var(--bm-text-muted)' }} />
              </button>
              </HintTip>
              <div className="flex-1" />
              {/* <ThemeToggle /> — light only for now */}
            </div>
          ) : (
            /* Full sidebar */
            <div className="flex-shrink-0 flex overflow-hidden" data-testid="platform-sidebar" style={{ width: 224, minWidth: 224, maxWidth: 224 }}>
              <AppSidebar
                onNewChat={onNewChat}
                onChatSelect={onChatSelect}
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
  const [route, navigate] = useLocation();
  const connectorReturnTo = useRef('/');
  useEffect(() => {
    // Preserve project/session query context, but never return to auth or loop
    // back into Connectors. Direct links get a safe workspace fallback.
    if (route !== '/settings/connections' && !/^\/(login|register|mfa-challenge|reset-password)/.test(route)) {
      connectorReturnTo.current = `${route}${window.location.search}${window.location.hash}`;
    }
  }, [route]);
  return (
    <Switch>
      {/* Auth pages */}
      <Route path="/login" component={LoginPage} />
      <Route path="/register" component={RegisterPage} />
      <Route path="/join/:token" component={JoinProjectPage} />

      {/* Debug-only harness — see frontend/client/src/pages/DebugOutputs.tsx */}
      <Route path="/debug/outputs/:runId" component={DebugOutputs} />
      <Route path="/debug/viewer/:runId" component={DebugViewerChain} />
      <Route path="/debug/afterrun/:runId" component={DebugAfterRun} />
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
      {/* Billing stays HIDDEN — deliberate owner decision; do NOT re-enable without
          the owner's explicit OK. (The crash was separately hardened 2026-09-30 —
          compute.total_hours / storage.size_gb are now null-safe — so it is ready to
          restore WHENEVER the owner chooses, but it stays commented out until then.) */}
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

      <Route path="/admin">
        <AuthenticatedPageLayout>
          <SystemDashboardPage />
        </AuthenticatedPageLayout>
      </Route>

      <Route path="/pilot-exit-survey">
        <AuthenticatedPageLayout>
          <PilotExitSurveyPage />
        </AuthenticatedPageLayout>
      </Route>

      {/* CRO Library hidden for now (per request 2026-09-22) — no sidebar entry
          existed; commenting the route so the direct /drug-discovery-cro URL is
          disabled too. Restore when CRO is ready to surface. */}
      {/* <Route path="/drug-discovery-cro">
        <AuthenticatedPageLayout>
          <DrugDiscoveryCroDemoPage />
        </AuthenticatedPageLayout>
      </Route> */}

      {/* IND Report is paused — see IND_REPORT_ENABLED (feature-flags.ts). */}
      {IND_REPORT_ENABLED && (
        <Route path="/ind-report">
          <AuthenticatedPageLayout>
            <IndReportPage />
          </AuthenticatedPageLayout>
        </Route>
      )}

      <Route path="/capabilities">
        <PublicPageLayout>
          <CapabilitiesPage />
        </PublicPageLayout>
      </Route>

      {/* DL upgrade wave-1/wave-2 — Models + Design&Generate surfaces.
          Components: components/models (ModelsPanel) and
          components/design-generate (DesignGenerate). Node proxy routes for
          /api/models·/api/inference·/api/generate live in server/routes.ts. */}
      <Route path="/models">
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
          <div className="flex-1 min-h-0 overflow-y-auto" data-testid="models-scroll-region">
            <div className="max-w-5xl mx-auto p-4"><ModelsPanel /></div>
          </div>
        </PlatformLayout>
      </Route>

      <Route path="/design">
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
          <div className="max-w-5xl mx-auto p-4">
            <DesignGenerate />
          </div>
        </PlatformLayout>
      </Route>

      {/* Tier-1 data surface — the data hub. Datasets as first-class objects
          (DatasetObject) with perception-at-ingest quality. Node proxy for
          /api/perception lives in server/routes.ts. */}
      <Route path="/settings/connections">
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
          <ConnectorsDialog embedded open onOpenChange={open => { if (!open) navigate(connectorReturnTo.current); }} />
        </PlatformLayout>
      </Route>

      <Route path="/files">
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
          <DataHubPage />
        </PlatformLayout>
      </Route>

{/* Deep link from chat connectors — loads a generated workflow by id and
          opens the workflow panel focused on it. See pages/WorkflowDeepLink.tsx. */}
      <Route path="/workflow/:id" component={WorkflowDeepLink} />

      {/* Wave 4 — shareable pre-filled run landing (claim → panel Confirm & Run).
          Distinct from /workflow/:id owner drafts. See pages/RunLanding.tsx. */}
      <Route path="/run/:token" component={RunLanding} />

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

  // Tracks the latest session ID the user has intentionally selected/created,
  // used to guard against stale async callbacks overwriting the active session.
  const activeSessionIdRef = useRef<string | null>(null)

  const handleNewChat = () => {
    console.log('Creating new chat session')
    const newSession = chatHistoryService.createNewSession()
    activeSessionIdRef.current = newSession.id
    setCurrentChatSession(newSession)

    // Update sessions list
    const updatedSessions = chatHistoryService.getAllSessions()
    setChatSessions(updatedSessions)

    // Navigate to home page for new chat
    setLocation('/')
  }

  const handleChatSelect = async (chatId: string) => {
    console.log('Loading chat session:', chatId)
    activeSessionIdRef.current = chatId
    const local = chatHistoryService.getSession(chatId)
    // If session has no messages (e.g. synced from backend on another machine), fetch full detail
    const session = (!local || local.messages.length === 0)
      ? await chatHistoryService.fetchSessionDetail(chatId)
      : local
    // Guard: user may have clicked "New Chat" or a different session while the fetch was in flight
    if (session && activeSessionIdRef.current === chatId) {
      setCurrentChatSession(session)
      // Navigate to the chat page; the URL-sync effect below adds ?session=.
      setLocation('/')
    } else {
      // Unknown/deleted id — drop it so a refresh doesn't keep retrying it.
      const params = new URLSearchParams(window.location.search)
      if (params.get('session') === chatId) {
        params.delete('session')
        const qs = params.toString()
        window.history.replaceState(null, '', window.location.pathname + (qs ? '?' + qs : ''))
      }
    }
  }

  // Keep the open chat in the URL (/?session=<id>) so refresh, back/forward
  // and copied links reopen it. Only chats with messages are addressable — a
  // fresh empty chat stays at "/" (refreshing it correctly gives a new chat).
  // replaceState, not navigation: the chat is already rendered.
  useEffect(() => {
    if (location !== '/') return
    const id = currentChatSession && currentChatSession.messages.length > 0 ? currentChatSession.id : null
    if (!id) return
    const params = new URLSearchParams(window.location.search)
    if (params.get('session') === id) return
    params.set('session', id)
    window.history.replaceState(null, '', '/?' + params.toString())
  }, [location, currentChatSession?.id, currentChatSession?.messages.length])

  const handleChatUpdated = (session: ChatSession) => {
    // Save the updated session to chat history service regardless of which session is active
    chatHistoryService.updateSession(session.id, session)
    // Only promote to currentChatSession if this is still the active session.
    // Streaming callbacks from a previous session fire onChatUpdated after the
    // user has already switched — without this guard they would revert the UI
    // back to the old session.
    // Accept if: no active session (initial state / first message auto-creates one)
    // OR the incoming session matches the currently active session.
    // Reject if a different session ID arrives (stale streaming from a previous chat).
    setCurrentChatSession(prev => (!prev || prev.id === session.id) ? session : prev)
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

  // Both CTAs route through BioMate's real chat entry point via ?draft=, which
  // pre-fills the chat input for the user to review/edit before sending (the
  // same mechanism as the project "Analyze with BioMate" flow). They are NOT
  // console.log no-ops.
  const handleAddToWorkflow = (tool: ToolItem) => {
    setShowToolDialog(false)
    const msg = `Add the ${tool.name} tool to my workflow.`
    window.location.assign(`/?draft=${encodeURIComponent(msg)}`)
  }

  const handleStartChat = (tool: ToolItem) => {
    setShowToolDialog(false)
    const msg = `Tell me about the ${tool.name} tool and how to use it.`
    window.location.assign(`/?draft=${encodeURIComponent(msg)}`)
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
      <HintScope>
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
      </HintScope>
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
  // VITE_ONPREM=true activates the license gate for on-premises deployments.
  // SaaS (default) never shows the gate.
  const isOnPrem = import.meta.env.VITE_ONPREM === 'true';
  return (
    <QueryClientProvider client={queryClient}>
      <ThemeProvider defaultTheme="light" storageKey="biomate-ui-theme">
        <AuthProvider>
          <ActiveProjectProvider>
            {isOnPrem ? (
              <OnPremLicenseGate>
                <AppWithAuthSync />
              </OnPremLicenseGate>
            ) : (
              <AppWithAuthSync />
            )}
          </ActiveProjectProvider>
        </AuthProvider>
      </ThemeProvider>
      <TutorialTipOverlay />
    </QueryClientProvider>
  )
}
