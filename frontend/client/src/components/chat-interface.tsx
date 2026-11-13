import { type WorkflowProgressEvent, workflowProgressMessageId, hasWorkflowProgressEvent } from "@/lib/workflow-progress-event"
import { buildAssistantMessageFromFinal } from "@/lib/assistant-message-from-final"
import { computeTurnIndicators, signalsPendingWorkflow } from "@/lib/chat-turn-state"
import { LiveVoicePanel } from "./live-voice-panel"
import { prepareColdStartSelection, preparedInputsBlock } from "./cold-start-examples"
import { toast } from "@/hooks/use-toast"
import { useActiveProjectIdSafe, useActiveProjectSafe } from "@/contexts/active-project-context"
import { useState, useEffect, useRef, useCallback, useMemo } from "react"
import { t, locale } from "@/lib/i18n"
import { modelLabel, type ResolvedModel } from "@/lib/llm-region"
import { uploadFile as uploadFileShared } from "@/lib/upload"
import { tOr } from "@/lib/i18n"
import { CodeExecutionBlock, type ToolBlock, type AgentToolEvent } from "./code-execution-block"
import { abortTurn, endTurn, isTurnActive, setTurnAbort, startTurn, useTurnActive } from "@/lib/active-turns"
import { ChatMessage, type Message } from "./chat-message"
import { peekWorkflowSelection, takeWorkflowSelection } from "@/lib/workflow-selection"
import { groupWorkflowResponses, ProgressStreamBox } from "./chat-progress-fold"
import { DataAnalysisCard, type FileAnalysisResult } from "./data-analysis-card"
import { FindingsCard } from "./findings-card"
import { ChatInput, type ComposerProject } from "./chat-input"
import { ColdStartDashboard } from "./cold-start-dashboard"
import { TaskList, type TaskItem, type TaskStatus } from "./task-list"
import { TypingIndicator } from "./typing-indicator"
// FileUpload moved into ChatInput component as a popover
import { CompressionDialog, CompressionStatusBadge } from "./compression-dialog"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Separator } from "@/components/ui/separator"
import { Card } from "@/components/ui/card"
import { useMutation } from "@tanstack/react-query"
import { apiRequest } from "@/lib/queryClient"
import { chatHistoryService } from "@/lib/chat-history"
import { emitUxEvent } from "@/lib/ux-telemetry"
import { chatRetryDelaysMs, getChatAsyncGuidance, isTransientChatError } from "@/lib/async-guidance"
import { useNetworkStatus } from "@/lib/network-status"
import type { ChatSession, ExecutionRun } from "@shared/schema"
import { analytics } from "@/lib/analytics"
import {
  ChevronRight,
  ChevronDown,
  Loader2,
  CheckCircle,
  Check,
  Clock,
  AlertTriangle,
  Settings,
  Dna,
  FlaskConical,
  Microscope,
  BarChart3,
  Brain,
  Layers
} from "lucide-react"
import { cn } from "@/lib/utils"
import type { DraftOptions } from "@/lib/one-shot-url-param"

interface WorkflowProgress {
  id: string
  title: string
  description: string
  status: 'running' | 'completed' | 'pending' | 'error'
  progress: number
  steps: Array<{
    id: string
    name: string
    status: 'running' | 'completed' | 'pending' | 'error'
    duration?: string
  }>
}

interface ChatInterfaceProps {
  chatSession?: ChatSession | null
  onSendMessage?: (message: string) => void
  isTyping?: boolean
  className?: string
  onWorkflowGenerated?: (workflow: any) => void
  onChatUpdated?: (session: ChatSession) => void
  activeWorkflow?: WorkflowProgress | null
  showProgress?: boolean
  onToggleProgress?: () => void
  // Workflow execution props for inline artifacts
  onRunWorkflow?: (workflow: any, steps: any[], sourceMessageId?: string) => void
  onRunChain?: (workflow: any) => void
  onRunPipeline?: (workflow: any) => void
  onApprovePipelineStep?: (workflow: any, completedStepId: string, nextStepId: string) => void
  onStopWorkflow?: () => void
  onPauseWorkflow?: () => void
  onResumeWorkflow?: () => void
  onParameterChange?: (stepId: string, params: Record<string, any>) => void
  isWorkflowRunning?: boolean
  workflowProgress?: number
  workflowError?: string | null
  currentExecutionRun?: ExecutionRun | null
  externalPromptRequest?: { id: number; prompt: string } | null
  onExternalPromptConsumed?: (id: number) => void
  focusedRunId?: string | null
  runAnchorRequestId?: number
  // Right panel
  onOpenWorkflowInPanel?: (messageId: string, workflow: any, tab?: 'summary' | 'outputs' | 'report') => void
  panelWorkflowMessageId?: string | null
  /** Whether the workflow panel is currently open. When true, all inline
   *  workflow cards (viewer, pipeline, chain) are suppressed in chat messages
   *  so workflow UI lives exclusively in the panel. */
  isPanelOpen?: boolean
  onRegisterSetDraft?: (setter: (draft: string, opts?: DraftOptions) => void) => void
  /**
   * Registers a parent-triggered send. Useful for the
   * IntentClarificationCard re-submit flow: when the user picks a
   * candidate, chat-with-artifacts re-submits the original message with
   * `context.intentOverride` set so the backend skips ambiguity detection.
   */
  onRegisterSendMessage?: (
    sender: (
      message: string,
      files?: File[],
      contextOverride?: Record<string, unknown>,
    ) => void,
  ) => void
  /** Called when the streaming (thinking/generating) state changes. */
  onStreamingChange?: (isStreaming: boolean) => void
  /** Called just before a message with file attachments is submitted. */
  onSubmitWithFiles?: () => void
  /** The workflow currently open in the right panel (if any). Sent to the
   *  backend so follow-up messages can auto-fill parameters. */
  currentPanelWorkflow?: any | null
}

// ── Onboarding welcome ────────────────────────────────────────────────────────
// Step 1: pick domains (all 14 + free-text "Other")
// Step 2: pick topics per selected domain (+ free-text "Other" per domain)
// "Next" saves profile then closes welcome — user enters the platform.
// Suggested queries are deferred until verified (see backend/experiments/verified_queries/).

import { DOMAIN_TAXONOMY, DOMAIN_LABELS } from "@/components/domain-profile-selector"

const ONBOARDING_DONE_KEY = 'biomate_onboarding_done'

// Example queries shown as clickable chips on the empty-state chat screen.
function OnboardingWelcome({
  onComplete,
  visible,
}: {
  onComplete: () => void
  visible: boolean
}) {
  const [step, setStep] = useState<"domains" | "topics">("domains")
  const [selectedDomains, setSelectedDomains] = useState<Set<string>>(new Set())
  const [otherDomain, setOtherDomain] = useState("")
  const [selectedTopics, setSelectedTopics] = useState<Set<string>>(new Set())
  const [otherTopics, setOtherTopics] = useState<Record<string, string>>({}) // domainKey → free text
  const [saving, setSaving] = useState(false)

  if (!visible) return null

  const domainKeys = Object.keys(DOMAIN_TAXONOMY)
  const domainsArray = Array.from(selectedDomains)

  const toggleDomain = (key: string) => {
    setSelectedDomains(prev => {
      const next = new Set(prev)
      if (next.has(key)) {
        next.delete(key)
        const removed = DOMAIN_TAXONOMY[key] ?? []
        const stillValid = new Set(Array.from(next).flatMap(d => DOMAIN_TAXONOMY[d] ?? []))
        setSelectedTopics(prev2 => {
          const next2 = new Set(prev2)
          for (const t of removed) { if (!stillValid.has(t)) next2.delete(t) }
          return next2
        })
      } else {
        next.add(key)
      }
      return next
    })
  }

  const toggleTopic = (topic: string) => {
    setSelectedTopics(prev => {
      const next = new Set(prev)
      next.has(topic) ? next.delete(topic) : next.add(topic)
      return next
    })
  }

  const handleNext = async () => {
    setSaving(true)
    // Collect final domains + topics including free-text "Others"
    const customDomains = otherDomain.trim()
      ? otherDomain.split(',').map(s => s.trim()).filter(Boolean)
      : []
    const allDomains = [...domainsArray, ...customDomains]

    const customTopics = Object.values(otherTopics)
      .flatMap(v => v.split(',').map(s => s.trim()).filter(Boolean))
    const allTopics = [...Array.from(selectedTopics), ...customTopics]

    // Best-effort save — never block the user
    try {
      await fetch('/api/user/domain-profile', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({ domains: allDomains, topics: allTopics }),
      })
    } catch { /* non-fatal */ }

    localStorage.setItem(ONBOARDING_DONE_KEY, '1')
    setSaving(false)
    onComplete()
  }

  // ── Step 1: domain selection ────────────────────────────────────────────────
  if (step === "domains") {
    return (
      <div data-testid="onboarding-welcome" className="flex flex-col items-center justify-center min-h-[60vh] px-4 py-8">
        <div className="w-full max-w-2xl">
          <div className="mb-6 text-center">
            <h2 className="text-2xl font-semibold mb-1">{t('What would you like to analyze?')}</h2>
            <p className="text-sm text-muted-foreground">
              {t('Select your research areas — BioMate will prioritise relevant workflows.')}
            </p>
          </div>

          <div className="grid grid-cols-2 gap-2 mb-4">
            {domainKeys.map(key => {
              const isSelected = selectedDomains.has(key)
              return (
                <button
                  key={key}
                  type="button"
                  data-testid={`onboarding-domain-btn-${key}`}
                  onClick={() => toggleDomain(key)}
                  className={cn(
                    "flex items-center gap-3 rounded-lg border px-4 py-2.5 text-left transition-colors text-sm",
                    "hover:border-primary/60 hover:bg-primary/5",
                    isSelected
                      ? "border-primary bg-primary/10 text-primary font-medium"
                      : "border-border bg-background"
                  )}
                >
                  <div className={cn(
                    "flex h-4 w-4 shrink-0 items-center justify-center rounded border",
                    isSelected ? "border-primary bg-primary text-primary-foreground" : "border-muted-foreground"
                  )}>
                    {isSelected && <Check className="h-3 w-3" />}
                  </div>
                  {DOMAIN_LABELS[key]}
                </button>
              )
            })}
          </div>

          {/* Other domain free-text */}
          <div className="mb-6">
            <input
              type="text"
              placeholder="Other domain (e.g. spatial genomics, immunology) — separate with commas"
              value={otherDomain}
              onChange={e => setOtherDomain(e.target.value)}
              className="w-full rounded-lg border border-border bg-background px-4 py-2 text-sm placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/40"
            />
          </div>

          <div className="flex items-center justify-between">
            <span className="text-xs text-muted-foreground">
              {selectedDomains.size + (otherDomain.trim() ? 1 : 0)} selected
            </span>
            <div className="flex gap-2">
              <Button variant="ghost" size="sm" onClick={() => { localStorage.setItem(ONBOARDING_DONE_KEY, '1'); onComplete() }}>
                Skip
              </Button>
              <Button
                onClick={() => setStep("topics")}
                disabled={selectedDomains.size === 0 && !otherDomain.trim()}
                className="gap-2"
              >
                Continue <ChevronRight className="h-4 w-4" />
              </Button>
            </div>
          </div>
        </div>
      </div>
    )
  }

  // ── Step 2: topic selection ─────────────────────────────────────────────────
  return (
    <div data-testid="onboarding-welcome" className="flex flex-col items-center justify-center min-h-[60vh] px-4 py-8">
      <div className="w-full max-w-2xl">
        <div className="mb-6 text-center">
          <h2 className="text-2xl font-semibold mb-1">Which topics interest you?</h2>
          <p className="text-sm text-muted-foreground">
            Optional — helps BioMate surface the most relevant workflows for your work.
          </p>
        </div>

        <div className="space-y-5 mb-6 max-h-[50vh] overflow-y-auto pr-1">
          {domainsArray.map(domainKey => (
            <div key={domainKey}>
              <h4 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-2">
                {DOMAIN_LABELS[domainKey]}
              </h4>
              <div className="flex flex-wrap gap-2 mb-2">
                {(DOMAIN_TAXONOMY[domainKey] ?? []).map(topic => {
                  const isSel = selectedTopics.has(topic)
                  return (
                    <button
                      key={topic}
                      type="button"
                      onClick={() => toggleTopic(topic)}
                      className={cn(
                        "inline-flex items-center gap-1.5 rounded-full border px-3 py-1 text-xs transition-colors",
                        "hover:border-primary/60 hover:bg-primary/5",
                        isSel
                          ? "border-primary bg-primary/10 text-primary font-medium"
                          : "border-border text-muted-foreground"
                      )}
                    >
                      {isSel && <Check className="h-3 w-3 shrink-0" />}
                      {topic}
                    </button>
                  )
                })}
              </div>
              {/* Per-domain "Other" free-text */}
              <input
                type="text"
                placeholder={`Other ${DOMAIN_LABELS[domainKey]} topics — separate with commas`}
                value={otherTopics[domainKey] ?? ""}
                onChange={e => setOtherTopics(prev => ({ ...prev, [domainKey]: e.target.value }))}
                className="w-full rounded-lg border border-border bg-background px-3 py-1.5 text-xs placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/40"
              />
            </div>
          ))}

          {/* Other domain section (if user typed a custom domain) */}
          {otherDomain.trim() && (
            <div>
              <h4 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-2">
                Other: {otherDomain}
              </h4>
              <input
                type="text"
                placeholder="Specific topics within this area — separate with commas"
                value={otherTopics['__other__'] ?? ""}
                onChange={e => setOtherTopics(prev => ({ ...prev, '__other__': e.target.value }))}
                className="w-full rounded-lg border border-border bg-background px-3 py-1.5 text-xs placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/40"
              />
            </div>
          )}
        </div>

        <div className="flex items-center justify-between">
          <Button variant="ghost" size="sm" onClick={() => setStep("domains")}>Back</Button>
          <Button onClick={handleNext} disabled={saving} className="gap-2">
            {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : null}
            Next — Enter BioMate <ChevronRight className="h-4 w-4" />
          </Button>
        </div>
      </div>
    </div>
  )
}

// ── Returning-user welcome (domain picker + starter prompts) ─────────────────

type WelcomeDomain = 'genomics' | 'drug_discovery' | 'cryo_em' | 'proteomics' | 'single_cell' | 'transcriptomics' | 'structural_biology' | 'epigenomics'

const WELCOME_DOMAINS: { key: WelcomeDomain; label: string; icon: React.ElementType; color: string }[] = [
  { key: 'genomics',          label: 'Genomics',           icon: Dna,         color: 'text-emerald-600' },
  { key: 'drug_discovery',    label: 'Drug Discovery',     icon: FlaskConical, color: 'text-violet-600' },
  { key: 'cryo_em',           label: 'Cryo-EM',            icon: Microscope,  color: 'text-sky-600' },
  { key: 'transcriptomics',   label: 'Transcriptomics',    icon: BarChart3,   color: 'text-orange-600' },
  { key: 'single_cell',       label: 'Single Cell',        icon: Brain,       color: 'text-pink-600' },
  { key: 'proteomics',        label: 'Proteomics',         icon: Layers,      color: 'text-teal-600' },
  { key: 'structural_biology',label: 'Structural Biology', icon: Microscope,  color: 'text-indigo-600' },
  { key: 'epigenomics',       label: 'Epigenomics',        icon: Dna,         color: 'text-amber-600' },
]

const WELCOME_PROMPTS: Record<WelcomeDomain, string[]> = {
  genomics: [
    'Run whole genome sequencing analysis on SRR1518169',
    'Call germline variants with GATK HaplotypeCaller',
    'Perform RNA-seq differential expression analysis',
    'Align FASTQ reads with BWA-MEM2 against hg38',
  ],
  drug_discovery: [
    'Run ADMET property prediction for aspirin (CC(=O)Oc1ccccc1C(=O)O)',
    'Predict binding affinity between imatinib and BCR-ABL kinase',
    'Screen compound library for drug-likeness and toxicity',
    'Run PBPK/PK-PD modeling for semaglutide',
  ],
  cryo_em: [
    'Process cryo-EM micrographs with standard SPA pipeline',
    'Run CryoSPARC on EMPIAR-10025 apoferritin dataset',
    'Perform helical reconstruction for filament data',
    'Run RELION multi-body refinement for flexible regions',
  ],
  transcriptomics: [
    'Run nf-core/rnaseq differential expression analysis',
    'Perform spatial transcriptomics analysis with Visium data',
    'Run single-cell RNA-seq with Seurat clustering',
    'Long-read RNA-seq with Oxford Nanopore data',
  ],
  single_cell: [
    'Run scRNA-seq clustering and cell-type annotation',
    'Perform trajectory analysis on my scRNA-seq data',
    'Integrate multi-modal single-cell ATAC + RNA data',
    'Identify rare cell populations with high-resolution clustering',
  ],
  proteomics: [
    'Run label-free quantification on DIA-MS data with DIA-NN',
    'Identify phosphorylation sites in my MS/MS spectra',
    'Run CyTOF mass cytometry analysis',
    'Perform protein-protein interaction network analysis',
  ],
  structural_biology: [
    'Run AlphaFold2 structure prediction for my protein sequence',
    'Perform molecular docking of ligand against EGFR',
    'Run GROMACS MD simulation for protein-ligand complex',
    'Predict binding affinity with MM-GBSA free energy',
  ],
  epigenomics: [
    'Run ChIP-seq peak calling with MACS2',
    'Perform ATAC-seq chromatin accessibility analysis',
    'Run bisulfite sequencing DNA methylation analysis',
    'Integrate CUT&RUN with RNA-seq for regulatory analysis',
  ],
}

function ReturningUserWelcome(_props: { onSend: (msg: string) => void }) {
  // Greeting + 8-domain × 4-query grid removed per todo (item #11):
  // the hardcoded suggested queries haven't been E2E-validated against every
  // workflow. Restore once each query is verified to drive a complete run.
  // GATE: scripts/coldstart_executability_guard.py must go green (every WELCOME_PROMPT backed by a workflow in passed_workflows.txt) before re-enabling — currently 9/32.
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────

export function ChatInterface({
  chatSession,
  onSendMessage = (msg) => console.log('Send message:', msg),
  isTyping = false,
  className,
  onWorkflowGenerated = (workflow) => console.log('Workflow generated:', workflow),
  onChatUpdated,
  activeWorkflow,
  showProgress,
  onToggleProgress,
  onRunWorkflow,
  onRunChain,
  onRunPipeline,
  onApprovePipelineStep,
  onStopWorkflow,
  onPauseWorkflow,
  onResumeWorkflow,
  onParameterChange,
  isWorkflowRunning = false,
  workflowProgress = 0,
  workflowError,
  currentExecutionRun,
  externalPromptRequest = null,
  onExternalPromptConsumed,
  focusedRunId = null,
  runAnchorRequestId = 0,
  onOpenWorkflowInPanel,
  panelWorkflowMessageId,
  isPanelOpen = false,
  onRegisterSetDraft,
  onRegisterSendMessage,
  onStreamingChange,
  onSubmitWithFiles,
  currentPanelWorkflow,
}: ChatInterfaceProps) {
  const [isTypingLocal, setIsTypingLocal] = useState(false)
  // Notify parent when streaming state changes so it can show a panel skeleton.
  useEffect(() => { onStreamingChange?.(isTypingLocal) }, [isTypingLocal, onStreamingChange])
  const [workflowGeneratingPhase, setWorkflowGeneratingPhase] = useState<'thinking' | 'workflow'>('thinking')
  // Independent flag: shows "BioMate is generating workflow…" cue for 1.5 s after
  // onSuccess when a workflow was produced. workflow_ready + final arrive in the same
  // TCP flush so React batches them — the indicator never renders from workflowGeneratingPhase
  // alone. This flag fires AFTER onSuccess and is self-clearing.
  const [showWorkflowCue, setShowWorkflowCue] = useState(false)
  const workflowCueTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  // File analysis results: messageId → FileAnalysisResult[] shown below user messages
  const [fileAnalysisMap, setFileAnalysisMap] = useState<Record<string, FileAnalysisResult[]>>({})
  // Soft query queue: messages submitted while AI is responding are held here
  // and auto-submitted one-at-a-time once each response completes.
  const [pendingMessages, setPendingMessages] = useState<string[]>([])
  const pendingMessagesRef = useRef<string[]>([])
  pendingMessagesRef.current = pendingMessages

  const abortControllerRef = useRef<AbortController | null>(null)
  // A workflow picked in the library waits in the composer: remind the user to give it THEIR data
  // (founder 2026-11-12: "Run" from the library sent the bare workflow name and ran on examples).
  const [libraryPick, setLibraryPick] = useState(() => peekWorkflowSelection()?.label || peekWorkflowSelection()?.name || null)
  // Latest session id for callbacks with stable identity (stopStreaming) — never a stale closure.
  const chatSessionIdRef = useRef<string | undefined>(chatSession?.id)
  chatSessionIdRef.current = chatSession?.id
  const scrollRef = useRef<HTMLDivElement>(null)
  const messagesEndRef = useRef<HTMLDivElement>(null)
  const followChatTailRef = useRef(true)
  // Captured setter from ChatInput — lets empty-state chips pre-fill the textarea
  const localSetDraftRef = useRef<((draft: string, opts?: DraftOptions) => void) | null>(null)
  const [preparingExample, setPreparingExample] = useState(false)
  const preparingExampleRef = useRef(false)
  const localAddFilesRef = useRef<((files: File[]) => void) | null>(null)
  const localExampleFilesRef = useRef<((files: File[]) => void) | null>(null)
  // Model-facing notes for the seeded example's files (never shown to the user).
  // Sent as a hidden [Prepared inputs: …] block only while those files are still
  // attached — if the user swaps in their own data the notes no longer apply.
  const exampleContextRef = useRef<{ context: string; fileNames: string[] } | null>(null)
  // Track whether we've pre-loaded the GSE227835 de_genes.txt for Turn 2
  const deGenesPreloadedRef = useRef(false)
  const [focusedAnchorMessageId, setFocusedAnchorMessageId] = useState<string | null>(null)
  const [highlightedAnchorMessageId, setHighlightedAnchorMessageId] = useState<string | null>(null)

  // Real projects for the composer's "project suggested" row (spec 06 §6.6)
  // and instructions seeding (§6.5). Fetched from the SAME source the sidebar
  // uses (GET /api/projects) so the composer proposes only projects the user
  // actually has — never a fabricated one. Refreshed on the shared
  // 'biomate:projects-updated' event so a newly-created project can be
  // proposed without a reload.
  const contextProjectId = useActiveProjectIdSafe();
  const activeProjectContext = useActiveProjectSafe();
  const [composerProjects, setComposerProjects] = useState<ComposerProject[]>([])
  const [activeProjectId, setActiveProjectId] = useState<string | null>(() => {
    try { return typeof window !== 'undefined' ? localStorage.getItem('biomate-active-project-id') : null }
    catch { return null }
  })
  useEffect(() => { setActiveProjectId(contextProjectId) }, [contextProjectId])
  useEffect(() => {
    let cancelled = false
    const loadProjects = () => {
      fetch('/api/projects', { credentials: 'include' })
        .then((r) => (r.ok ? r.json() : { projects: [] }))
        .then((d) => { if (!cancelled) setComposerProjects((d.projects ?? []).map((p: any) => ({ ...p, instructions: p.researchGoal ?? p.instructions ?? "" })) as ComposerProject[]) })
        .catch(() => { /* honest-empty: no projects → no suggestion */ })
    }
    loadProjects()
    const onUpdate = () => loadProjects()
    if (typeof window !== 'undefined') window.addEventListener('biomate:projects-updated', onUpdate)
    return () => { cancelled = true; if (typeof window !== 'undefined') window.removeEventListener('biomate:projects-updated', onUpdate) }
  }, [])
  // File the current chat into a project (spec 06 §6.6 "File it there"): set the
  // active project the existing chat-stream context already threads
  // (`biomate-active-project-id` → context.projectId, see chatMutation) and
  // broadcast so the sidebar reflects the new home.
  const handleFileToProject = useCallback((projectId: string) => {
    try { localStorage.setItem('biomate-active-project-id', projectId) } catch { /* noop */ }
    setActiveProjectId(projectId)
    if (typeof window !== 'undefined') window.dispatchEvent(new Event('biomate:projects-updated'))
  }, [])

  // Stop dialog state
  const [showStopDialog, setShowStopDialog] = useState(false)
  // Snapshot of queue length at the moment stop was clicked (avoids stale reactive read)
  const [stopDialogQueueCount, setStopDialogQueueCount] = useState(0)

  // LangGraph task tracking
  const [langgraphTasks, setLanggraphTasks] = useState<TaskItem[]>([])
  const langgraphTasksRef = useRef<TaskItem[]>([])
  langgraphTasksRef.current = langgraphTasks

  // Compression state
  const [showCompressionDialog, setShowCompressionDialog] = useState(false)
  const [isCompressing, setIsCompressing] = useState(false)
  const [currentTokenCount, setCurrentTokenCount] = useState(0)
  const [compressionDismissed, setCompressionDismissed] = useState(false)

  // Model label: the model the server ACTUALLY used for the last reply (its `model` stream event,
  // resolved under the region policy) — never the stored Settings pick, which the policy may override.
  const [activeLLMModel, setActiveLLMModel] = useState<ResolvedModel | null>(null)
  const [hasOwnOpenrouterKey, setHasOwnOpenrouterKey] = useState(false)
  useEffect(() => {
    fetch('/api/user/llm-api-keys', { credentials: 'include' })
      .then(r => r.ok ? r.json() : null)
      .then(d => setHasOwnOpenrouterKey(!!d?.openrouter))
      .catch(() => {})
  }, [])
  const [onboardingDone, setOnboardingDone] = useState(() =>
    typeof window !== 'undefined' && localStorage.getItem(ONBOARDING_DONE_KEY) === '1'
  )
  const { isOnline } = useNetworkStatus()
  
  // Use messages from chat session or empty array if no session
  const displayMessages = chatSession?.messages || []
  // Turn state follows the stream lifecycle, not the reply text: a workflow
  // turn streams its summary long before the card (see lib/chat-turn-state.ts).
  const lastMsg = displayMessages[displayMessages.length - 1]
  // A turn survives the remount that the first message of a new chat causes (lib/active-turns).
  const sessionTurnActive = useTurnActive(chatSession?.id)
  const { displayTyping, turnBusy } = computeTurnIndicators({
    streamOpen: isTyping || isTypingLocal || sessionTurnActive,
    showWorkflowCue,
    phase: workflowGeneratingPhase,
    lastMessage: lastMsg,
  })
  const latestAssistantMessageId = [...displayMessages]
    .reverse()
    .find((msg) => msg.role !== "user")?.id

  // Debug: Log message count
  useEffect(() => {
    console.log('[ChatInterface] displayMessages count:', displayMessages.length)
    console.log('[ChatInterface] displayMessages IDs:', displayMessages.map(m => m.id))
  }, [displayMessages])

  useEffect(() => { followChatTailRef.current = true }, [chatSession?.id])

  // Follow new messages only while the reader is at the end of both chat and its streams.
  useEffect(() => {
    const readingEarlierUpdate = Array.from(scrollRef.current?.querySelectorAll<HTMLElement>('[role="log"]') ?? [])
      .some(log => log.scrollHeight - log.scrollTop - log.clientHeight > 24)
    if (followChatTailRef.current && !readingEarlierUpdate && messagesEndRef.current) {
      messagesEndRef.current.scrollIntoView({ behavior: 'smooth' })
    }
  }, [displayMessages, displayTyping])

  // After the first AI response in a GSE227835 DESeq2 conversation, pre-attach
  // de_genes.txt so the user has the sample gene list ready for Turn 2 (enrichGO).
  useEffect(() => {
    if (deGenesPreloadedRef.current) return
    if (!localAddFilesRef.current) return
    const hasGSE = displayMessages.some(
      m => typeof m.content === 'string' && m.content.includes('GSE227835')
    )
    if (!hasGSE) return
    // Wait until there is at least one AI response after the user's first message
    const aiResponded = displayMessages.some(m => m.role === 'assistant')
    if (!aiResponded) return
    // Only attach if user hasn't already sent a second message (Turn 2 pending)
    const userMessages = displayMessages.filter(m => m.role === 'user')
    if (userMessages.length > 1) return
    deGenesPreloadedRef.current = true
    const addFiles = localAddFilesRef.current
    fetch('/demo/mg_demo/de_genes.txt')
      .then(r => r.blob())
      .then(blob => {
        const file = new File([blob], 'de_genes.txt', { type: 'text/plain' })
        addFiles([file])
      })
      .catch(() => { /* silently skip if not available */ })
  }, [displayMessages])

  // Anchor chat view to the workflow artifact associated with the focused run.
  useEffect(() => {
    if (!focusedRunId) {
      setFocusedAnchorMessageId(null)
      setHighlightedAnchorMessageId(null)
      return
    }
    if (displayMessages.length === 0) return

    const candidateInvocationIds = new Set<string>([focusedRunId])
    if (currentExecutionRun?.id) {
      candidateInvocationIds.add(currentExecutionRun.id)
    }
    if (currentExecutionRun?.execution?.galaxyInvocationId) {
      candidateInvocationIds.add(currentExecutionRun.execution.galaxyInvocationId)
    }

    const reversedMessages = [...displayMessages].reverse()
    const targetMessage =
      reversedMessages.find((message) => {
        if (message.role !== "assistant") return false
        if (message.invocationId && candidateInvocationIds.has(message.invocationId)) return true
        return false
      }) ||
      reversedMessages.find((message) => {
        if (message.role !== "assistant") return false
        if (message.metadata?.type !== "workflow" || !message.metadata?.workflow) return false
        if (!currentExecutionRun?.workflowName) return false
        return (
          message.metadata.workflow.name === currentExecutionRun.workflowName ||
          message.metadata.workflow.workflow_name === currentExecutionRun.workflowName
        )
      })

    if (!targetMessage) {
      setFocusedAnchorMessageId(null)
      return
    }

    setFocusedAnchorMessageId(targetMessage.id)
    setHighlightedAnchorMessageId(targetMessage.id)

    const scrollToTarget = () => {
      const artifactElement = document.getElementById(`workflow-artifact-anchor-${targetMessage.id}`)
      const messageElement = document.getElementById(`chat-message-anchor-${targetMessage.id}`)
      const targetElement = artifactElement || messageElement
      targetElement?.scrollIntoView({ behavior: "smooth", block: "center" })
    }

    if (typeof window !== "undefined" && typeof window.requestAnimationFrame === "function") {
      window.requestAnimationFrame(scrollToTarget)
    } else {
      scrollToTarget()
    }

    const highlightTimer = setTimeout(() => {
      setHighlightedAnchorMessageId((prev) => (prev === targetMessage.id ? null : prev))
    }, 2200)

    return () => {
      clearTimeout(highlightTimer)
    }
  }, [
    focusedRunId,
    runAnchorRequestId,
    currentExecutionRun?.id,
    currentExecutionRun?.execution?.galaxyInvocationId,
    currentExecutionRun?.workflowName,
    displayMessages,
  ])

  // Monitor token count and trigger compression dialog
  useEffect(() => {
    if (!chatSession || !displayMessages.length) {
      setCurrentTokenCount(0)
      return
    }

    // Calculate current token count using chat history service
    const session = chatHistoryService.getSession(chatSession.id)
    if (!session) return

    const tokenCount = session.totalTokens || 0
    setCurrentTokenCount(tokenCount)

    console.log('[ChatInterface] Token monitoring:', {
      sessionId: chatSession.id,
      tokenCount,
      percentage: ((tokenCount / 200000) * 100).toFixed(1) + '%',
      messageCount: displayMessages.length
    })

    // Check if compression dialog should be shown
    const percentage = (tokenCount / 200000) * 100

    if (percentage >= 80 && !showCompressionDialog && !compressionDismissed) {
      // Critical: Show dialog immediately at 80%
      console.log('[ChatInterface] Token count critical (80%+), showing compression dialog')
      setShowCompressionDialog(true)
    } else if (percentage >= 70 && !showCompressionDialog && !compressionDismissed) {
      // Warning: Show dialog at 70%
      console.log('[ChatInterface] Token count warning (70%+), showing compression dialog')
      setShowCompressionDialog(true)
    }
  }, [displayMessages, chatSession, showCompressionDialog, compressionDismissed])

  interface ChatRequestPayload {
    content: string
    sessionId: string
    placeholderId: string
    /** Caller-supplied override merged into the chat context (e.g. intentOverride). */
    contextOverride?: Record<string, unknown>
  }

  const updateMessageInSession = (sessionId: string, messageId: string, updates: Partial<Message>) => {
    const session = chatHistoryService.getSession(sessionId)
    if (!session) {
      console.warn('[updateMsg] session NOT FOUND for', sessionId, 'update keys:', Object.keys(updates))
      return
    }
    const updatedMessages = session.messages.map((msg) =>
      msg.id === messageId ? { ...msg, ...updates } : msg
    )
    const updatedSession = chatHistoryService.updateSession(sessionId, { messages: updatedMessages })
    if (updatedSession && onChatUpdated) {
      onChatUpdated(updatedSession)
    }
  }

  // Workflow-progress chat lines from the backend narrator. Bubbled up from
  // NextflowWorkflowViewer's SSE listener; we append each one as a short
  // italic message (chat-message.tsx renders metadata.type='workflow_progress'
  // with a 🔹 icon, smaller font, no full card). De-dupe by (invocationId, kind, ts).
  const handleWorkflowProgress = useCallback((event: WorkflowProgressEvent) => {
    if (!chatSession?.id) return
    const session = chatHistoryService.getSession(chatSession.id)
    if (!session) return
    // Exact IDs also reject replayed events that arrive after a newer update.
    const eventId = workflowProgressMessageId(event)
    if (hasWorkflowProgressEvent(session.messages, event, eventId)) return
    const progressMsg: Message = {
      id: eventId,
      role: 'assistant',
      content: event.friendly_message,
      timestamp: new Date(),
      invocationId: event.invocationId,
      metadata: {
        type: 'workflow_progress',
        ...(event.invocationId && [currentExecutionRun?.id, currentExecutionRun?.execution?.galaxyInvocationId].includes(event.invocationId)
          ? { runId: currentExecutionRun?.id } : {}),
        kind: event.kind,
        eventId: event.eventId,
        ts: event.ts,
        technical: event.technical,
      } as any,
    }
    const updatedMessages = [...session.messages, progressMsg]
    const updatedSession = chatHistoryService.updateSession(session.id, { messages: updatedMessages })
    if (updatedSession && onChatUpdated) {
      onChatUpdated(updatedSession)
    }
  }, [chatSession?.id, onChatUpdated, currentExecutionRun?.id, currentExecutionRun?.execution?.galaxyInvocationId])

  // Galaxy Chat API integration with full hybrid intelligence
  // Uses /api/chat which provides: intent analysis, tool search, dataset RAG, workflow generation
  const chatMutation = useMutation({
    mutationFn: async ({ content, sessionId, placeholderId, contextOverride }: ChatRequestPayload) => {
      const session = chatHistoryService.getSession(sessionId)
      // Thread the active project id (if any) into chat-stream context.
      // Server policy: null/missing → chat stays project-less; non-null
      // → chat becomes project-scoped and cross-session recovery
      // (within the same project) is in scope. See
      // docs/20260612_DATASET_STORAGE_AND_SESSION_BOUNDARIES.md.
      const _activeProjectId = (() => {
        try { return typeof window !== 'undefined' ? localStorage.getItem('biomate-active-project-id') : null }
        catch { return null }
      })()
      const _activeSkillIds = (() => {
        try {
          const raw = typeof window !== 'undefined' ? localStorage.getItem('biomate-active-skills') : null
          if (!raw) return undefined
          const ids = JSON.parse(raw)
          return Array.isArray(ids) && ids.length > 0 ? ids : undefined
        } catch { return undefined }
      })()
      // Build the history payload. See:
      //   docs/20260610_REAL_USER_FULL_CHAT_LOGS.md  (wjunlin@HKU)
      //   docs/20260610_CHAT_CONTEXT_AUDIT_4_QUESTIONS.md
      // Previously `.slice(-4)` — dropped early `[Galaxy dataset: ...]`
      // attachment lines after 2 turns, so the LLM kept asking for files
      // the user had already attached. Now: include the last 8 turns plus
      // any earlier message carrying a dataset/attachment block. The
      // server then runs selectChatHistoryUnderBudget over this payload
      // (≤16 KB cap, dataset blocks verbatim, long assistant replies
      // head/tail-clipped) — that's the authoritative budget. Keep the
      // client payload modest so we don't pay for redundant network
      // transfer of content the server will discard anyway.
      const _DATASET_BLOCK_RE = /\[(?:Galaxy dataset|Uploaded datasets?|Attached files?)\s*:/i
      const _allMsgs = (session?.messages || [])
        .filter((m) => (m.role === "user" || m.role === "assistant") && !!m.content?.trim())
      const _recent = _allMsgs.slice(-8)
      const _earlierAttachments = _allMsgs
        .slice(0, Math.max(0, _allMsgs.length - 8))
        .filter((m) => _DATASET_BLOCK_RE.test(m.content || ""))
      const previousMessages = [..._earlierAttachments, ..._recent]
        .map((m) => ({ role: m.role, content: m.content }))
      // A fresh AbortController drives each attempt. It is aborted for two
      // distinct reasons that we must tell apart:
      //   - user pressed Stop  → timedOutRef stays false; treat as a clean
      //     stop (return partial), no retry.
      //   - per-attempt timeout → timedOutRef is set just before we abort;
      //     treat as a TRANSIENT failure eligible for retry.
      // LLM workflow generation can legitimately take 30–90s (see CLAUDE.md
      // E2E timeout guidance), so the client timeout is generous (120s) — a
      // too-short timeout firing at 15–45s was a likely cause of the "under
      // maintenance" dead-end on the first attempt.
      const ATTEMPT_TIMEOUT_MS = 120_000
      // Retries per failure kind: chatRetryDelaysMs (gateway errors span a server restart).
      const timedOutRef = { current: false }

      // Single stream attempt. Throws on failure; the caller decides whether
      // the failure is transient (retry) or deterministic (surface now).
      const attemptStream = async (): Promise<any> => {
      timedOutRef.current = false
      abortControllerRef.current = new AbortController()
      setTurnAbort(sessionId, abortControllerRef.current)
      const _timeoutId = setTimeout(() => {
        timedOutRef.current = true
        try { abortControllerRef.current?.abort() } catch { /* noop */ }
      }, ATTEMPT_TIMEOUT_MS)
      try {
      const response = await fetch('/api/chat/stream', {
        method: 'POST',
        credentials: 'include', // ensure auth cookie is sent on mobile browsers
        signal: abortControllerRef.current.signal,
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: content,
          stream: true,
          context: {
            previousMessages,
            uiLanguage: locale,
            // The user's IANA time zone — names the chat's output folder by local time.
            timeZone: (() => { try { return Intl.DateTimeFormat().resolvedOptions().timeZone } catch { return undefined } })(),
            // Include session ID for memory integration AND server-side
            // assistant-message persistence (see docs/20260529_CHAT_STREAM_PERSISTENCE_GAP.md).
            // The server UPSERTs by assistantMessageId so client + server writes
            // are idempotent (no duplicate messages).
            ...(sessionId && { memorySessionId: sessionId, sessionId }),
            ...(_activeProjectId && { projectId: _activeProjectId }),
            ...(_activeSkillIds && { activeSkillIds: _activeSkillIds }),
            assistantMessageId: placeholderId,
            // Pass the currently open panel workflow so the backend can
            // extract parameter values from follow-up user messages and
            // return workflowEdits ops to auto-fill the panel.
            ...(currentPanelWorkflow && { currentWorkflow: currentPanelWorkflow }),
            // Caller-supplied override (e.g. intentOverride from
            // IntentClarificationCard re-submit). Spread LAST so it can
            // augment but not be clobbered by defaults above.
            ...(contextOverride || {}),
          }
        })
      })
      if (!response.ok) {
        const httpErr: any = response.status === 429
          ? new Error('Chat API error: The service is temporarily busy. Please wait a moment and try again.')
          : new Error(`Chat API error: ${response.statusText || response.status}`)
        httpErr.httpStatus = response.status
        throw httpErr
      }
      if (!response.body) {
        throw new Error('Streaming response body unavailable')
      }

      const reader = response.body.getReader()
      const decoder = new TextDecoder()
      let buffer = ''
      let accumulatedText = ''
      let finalPayload: any = null
      // Agent tool blocks accumulate during streaming
      const toolBlocksMap = new Map<string, ToolBlock>()

      try {
        while (true) {
          const { done, value } = await reader.read()
          if (done) break
          buffer += decoder.decode(value, { stream: true })

          while (true) {
            const eventBoundary = buffer.indexOf('\n\n')
            if (eventBoundary === -1) break

            const rawEvent = buffer.slice(0, eventBoundary)
            buffer = buffer.slice(eventBoundary + 2)

            const lines = rawEvent.split('\n')
            let eventName = 'message'
            const dataLines: string[] = []
            for (const line of lines) {
              if (line.startsWith('event:')) eventName = line.slice(6).trim()
              if (line.startsWith('data:')) dataLines.push(line.slice(5).trim())
            }

            const payloadText = dataLines.join('\n')
            if (!payloadText) continue
            let payload: any
            try {
              payload = JSON.parse(payloadText)
            } catch (parseErr: any) {
              console.error('[ChatInterface] SSE JSON parse error for event:', eventName, parseErr?.message, payloadText.slice(0, 100))
              continue
            }

            if (eventName === 'model' && typeof payload.model === 'string') {
              setActiveLLMModel(payload as ResolvedModel)
            } else if (eventName === 'delta' && typeof payload.text === 'string') {
              accumulatedText += payload.text
              if (accumulatedText.length <= payload.text.length) {
                console.log('[ChatInterface] First delta received, sessionId:', sessionId, 'placeholderId:', placeholderId, 'text len:', accumulatedText.length)
              }
              updateMessageInSession(sessionId, placeholderId, { content: accumulatedText })
            } else if (eventName === 'tool_event') {
              const event = payload as AgentToolEvent
              // 'status' events are observability-only (e.g. schema-grounded
              // extraction stage progress) — they share the SSE 'tool_event'
              // channel but should NOT render as tool calls in the chat UI.
              // Skip without registering a tool block.
              if (event.type === 'status') {
                // Surface status events as a transient progress indicator in the placeholder.
                if (event.message && !accumulatedText) {
                  const curSess = chatHistoryService.getSession(sessionId)
                  const curMsg = curSess?.messages.find(m => m.id === placeholderId)
                  updateMessageInSession(sessionId, placeholderId, {
                    metadata: { ...(curMsg?.metadata ?? {}), progressStatus: event.message }
                  })
                }
                continue
              }
              const id = event.tool_use_id
              if (!toolBlocksMap.has(id)) {
                toolBlocksMap.set(id, { tool_use_id: id, name: event.name })
              }
              const block = toolBlocksMap.get(id)!
              if (event.type === 'tool_call') block.call = event
              else if (event.type === 'tool_result') block.result = event
              // Persist tool blocks into the placeholder message metadata (merge-safe)
              const currentSession = chatHistoryService.getSession(sessionId)
              const currentMsg = currentSession?.messages.find(m => m.id === placeholderId)
              updateMessageInSession(sessionId, placeholderId, {
                metadata: { ...(currentMsg?.metadata ?? {}), toolBlocks: Array.from(toolBlocksMap.values()) }
              })
            } else if (eventName === 'final') {
              console.log('[ChatInterface] SSE final event received, workflow:', !!payload.workflow, 'keys:', Object.keys(payload))
              // Merge accumulated tool blocks into final payload
              if (toolBlocksMap.size > 0) {
                finalPayload = { ...payload, toolBlocks: Array.from(toolBlocksMap.values()) }
              } else {
                finalPayload = payload
              }
            } else if (eventName === 'progress') {
              // Routing-stage progress (intent → search → matched → plan) so the
              // user sees responsive status during the ~30s LLM chain instead of a
              // frozen spinner. Only before the text response starts streaming.
              const stage = (payload as any).stage as string | undefined
              const detail = (payload as any).detail as string | undefined
              // The server matched a workflow: the card follows the text, so
              // the turn stays visibly in progress until `final` (§4.1).
              if (signalsPendingWorkflow(eventName, payload)) setWorkflowGeneratingPhase('workflow')
              if (stage && !accumulatedText) {
                const label =
                  stage === 'intent' ? tOr('chat.progress.intent', 'Understanding your goal…') :
                  stage === 'search' ? tOr('chat.progress.search', 'Searching…') :
                  stage === 'matched' ? tOr('chat.progress.matched', 'Matched a workflow') :
                  stage === 'plan' ? tOr('chat.progress.plan', 'Preparing the plan…') :
                  stage
                const text = detail ? `${label} · ${detail}` : label
                const curSess = chatHistoryService.getSession(sessionId)
                const curMsg = curSess?.messages.find(m => m.id === placeholderId)
                updateMessageInSession(sessionId, placeholderId, {
                  metadata: { ...(curMsg?.metadata ?? {}), progressStatus: text }
                })
              }
            } else if (eventName === 'workflow_ready') {
              setWorkflowGeneratingPhase('workflow')
            } else if (eventName === 'error') {
              // Preserve the server's real error message so the retry
              // classifier (isTransientChatError) can decide whether this is a
              // transient hiccup worth retrying vs a deterministic failure to
              // surface immediately. The old opaque '__maintenance__' sentinel
              // discarded that signal and always dead-ended. Servers report the
              // text under message, error or detail; accept any of them.
              const pick = (v: unknown) => (typeof v === 'string' && v ? v : undefined)
              const serverMsg =
                pick(payload?.message) || pick(payload?.error) || pick(payload?.detail) ||
                'Streaming chat failed'
              throw new Error(serverMsg)
            }
          }
        }
        console.log('[ChatInterface] SSE stream complete, finalPayload set:', !!finalPayload)
      } catch (err: any) {
        console.error('[ChatInterface] SSE read error:', err?.name, err?.message)
        if (err?.name === 'AbortError') {
          if (timedOutRef.current) {
            // Per-attempt timeout — transient, eligible for retry.
            const toErr: any = new Error(
              `Workflow generation timed out after ${Math.round(ATTEMPT_TIMEOUT_MS / 1000)}s`,
            )
            toErr.timedOut = true
            throw toErr
          }
          // Stream was stopped by the user — clean stop, not an error.
          const abortErr: any = new Error('aborted')
          abortErr.userAborted = true
          abortErr.partial = finalPayload ?? { message: accumulatedText, aborted: true }
          throw abortErr
        }
        throw err
      }

      if (!finalPayload) {
        console.error('[ChatInterface] No final payload received from stream')
        throw new Error('No final payload received from stream')
      }
      return finalPayload
      } finally {
        clearTimeout(_timeoutId)
      }
      } // end attemptStream

      // Bounded retry: retry ONLY genuinely transient failures (network blip,
      // 5xx, timeout, empty/incomplete stream, rate-limit). Deterministic
      // failures (4xx, validation, clarification) are thrown immediately so
      // the user sees the real message instead of retrying into a hang.
      let lastError: any = null
      for (let attempt = 1; ; attempt++) {
        try {
          return await attemptStream()
        } catch (err: any) {
          // User pressed Stop — return the partial payload, do not retry.
          if (err?.userAborted) {
            return err.partial ?? { message: '', aborted: true }
          }
          lastError = err
          const transient = isTransientChatError(err?.message, {
            httpStatus: err?.httpStatus ?? null,
            aborted: false,
          }) || err?.timedOut === true
          const delays = chatRetryDelaysMs(err?.message, err?.httpStatus ?? null)
          const backoffMs = delays[attempt - 1]
          if (!transient || backoffMs === undefined) {
            throw err
          }
          // Keep the placeholder visible with a calm "retrying" cue so the
          // user isn't staring at a frozen bubble.
          console.warn(
            `[ChatInterface] Transient generation failure (attempt ${attempt}/${delays.length + 1}), retrying in ${backoffMs}ms:`,
            err?.message,
          )
          try {
            updateMessageInSession(sessionId, placeholderId, {
              metadata: { progressStatus: 'Reconnecting to the workflow service…' },
            })
          } catch { /* placeholder may not exist yet */ }
          await new Promise((r) => setTimeout(r, backoffMs))
          // If the user pressed Stop during the backoff window,
          // stopStreaming() nulled the controller — honor it, don't re-fire.
          if (abortControllerRef.current === null || !isTurnActive(sessionId)) {
            return { message: '', aborted: true }
          }
        }
      }
      throw lastError ?? new Error('Workflow generation failed')
    },
    onSuccess: async (data, variables) => {
      console.log('[ChatInterface] API Response:', data)
      endTurn(variables.sessionId)

      const { message: aiMessage, workflowSuccess, workflowData, stepsArray } =
        buildAssistantMessageFromFinal(data, variables.placeholderId)

      console.log('[ChatInterface] Created AI message:', {
        id: aiMessage.id,
        invocationId: aiMessage.invocationId,
        metadata: aiMessage.metadata,
        hasWorkflow: !!aiMessage.metadata?.workflow,
        metadataType: aiMessage.metadata?.type
      })

      // Add message to chat session (create one if it doesn't exist)
      if (variables.sessionId) {
        console.log('[ChatInterface] Updating streaming placeholder:', variables.placeholderId)
        updateMessageInSession(variables.sessionId, variables.placeholderId, aiMessage)

        // Also add workflow to session.workflows if workflow was generated
        if (workflowSuccess && workflowData && stepsArray.length > 0) {
          console.log('[ChatInterface] Extracting workflow to session.workflows')
          const workflowSteps = stepsArray.map((step: any, index: number) => ({
            id: `step_${index}`,
            title: step.name || step.tool_id || `Step ${index + 1}`,
            tool: step.tool_id || step.name || 'Unknown Tool',
            description: step.annotation || '',
            status: 'pending' as const,
            complexity: 'intermediate' as const,
            estimatedTime: '5 min',
            parameters: {},
            inputs: [],
            outputs: [],
          }))
          chatHistoryService.addWorkflow(variables.sessionId, workflowSteps)
        }
      } else {
        console.log('[ChatInterface] No session, creating new one')
        // Auto-create session if it doesn't exist (e.g., in test environment)
        const newSession = chatHistoryService.createNewSession()
        chatHistoryService.addMessage(newSession.id, aiMessage)

        // Also add workflow to session.workflows if workflow was generated
        if (workflowSuccess && workflowData && stepsArray.length > 0) {
          console.log('[ChatInterface] Extracting workflow to new session.workflows')
          const workflowSteps = stepsArray.map((step: any, index: number) => ({
            id: `step_${index}`,
            title: step.name || step.tool_id || `Step ${index + 1}`,
            tool: step.tool_id || step.name || 'Unknown Tool',
            description: step.annotation || '',
            status: 'pending' as const,
            complexity: 'intermediate' as const,
            estimatedTime: '5 min',
            parameters: {},
            inputs: [],
            outputs: [],
          }))
          chatHistoryService.addWorkflow(newSession.id, workflowSteps)
        }

        const updatedSession = chatHistoryService.getSession(newSession.id)
        console.log('[ChatInterface] New session created with', updatedSession?.messages.length, 'messages')
        if (updatedSession && onChatUpdated) {
          onChatUpdated(updatedSession)
        }
      }
      setIsTypingLocal(false)
      setWorkflowGeneratingPhase('thinking')

      // Show "BioMate is generating the workflow…" cue for 1.5 s when a workflow
      // was produced. We can't rely on workflowGeneratingPhase for this because
      // workflow_ready + final arrive in the same TCP flush and React batches them.
      if (workflowSuccess && workflowData) {
        if (workflowCueTimerRef.current) clearTimeout(workflowCueTimerRef.current)
        setShowWorkflowCue(true)
        workflowCueTimerRef.current = setTimeout(() => setShowWorkflowCue(false), 1500)
      }

      // Trigger workflow builder display
      if (workflowSuccess && workflowData) {
        emitUxEvent('workflow.generated', {
          sessionId: chatSession?.id,
          invocationId: data.invocationId,
        })
        onWorkflowGenerated(workflowData)
      }
    },
    onError: (error, variables) => {
      console.error('[ChatInterface] API Error:', error.message)
      endTurn(variables?.sessionId)

      const errorMessage = error.message || 'Unknown error occurred';
      const guidance = getChatAsyncGuidance(errorMessage, { isOnline });
      // By the time onError fires, the mutationFn has already exhausted its
      // bounded auto-retry for transient failures. So this is either a
      // persistent transient outage or a deterministic failure. Surface a
      // calm, honest message — a temporary hiccup the user can retry — WITHOUT
      // implying planned downtime (the old hardcoded "under maintenance"
      // string was misleading for a transient blip) and WITHOUT leaking raw
      // stack traces (guidance.reason is already sanitized).
      const transient = isTransientChatError(errorMessage, { httpStatus: null, aborted: false });
      const content = transient
        ? `${guidance.reason} ${guidance.retry}`.trim()
        : `${guidance.title}. ${guidance.reason} ${guidance.retry}`.trim();
      const aiMessage: Message = {
        id: (Date.now() + 1).toString(),
        content,
        role: "assistant",
        timestamp: new Date(),
        suggestions: ["Try again"],
        metadata: {
          type: 'error',
          errorType: guidance.isNetworkRelated ? 'network' : 'api',
          errorMessage: errorMessage,
        }
      }

      emitUxEvent('workflow.error_shown', {
        sessionId: chatSession?.id,
        errorType: guidance.isNetworkRelated ? 'network' : 'api',
        errorMessage: errorMessage,
      })

      // Add error message to chat session
      if (variables?.sessionId && variables?.placeholderId) {
        updateMessageInSession(variables.sessionId, variables.placeholderId, aiMessage)
      }
      setIsTypingLocal(false)
      setWorkflowGeneratingPhase('thinking')

      // Do not emit demo workflows on error; keep real-only behavior.
    }
  })

  const shouldGenerateWorkflow = (response: string): boolean => {
    const workflowKeywords = [
      'workflow', 'pipeline', 'analysis', 'steps', 'process',
      'RNA-seq', 'variant calling', 'genome assembly', 'alignment',
      'quality control', 'differential expression'
    ]
    return workflowKeywords.some(keyword => 
      response.toLowerCase().includes(keyword.toLowerCase())
    )
  }

  const generateWorkflowFromResponse = (response: string) => {
    // Generate workflow based on response content with concrete steps
    const detectedType = detectWorkflowTypeFromResponse(response)
    return {
      id: `workflow-${Date.now()}`,
      title: getWorkflowTitleFromType(detectedType),
      description: "Workflow generated from conversation",
      type: detectedType,
      steps: getStepsForType(detectedType)
    }
  }

  const detectWorkflowTypeFromResponse = (response: string): string => {
    const msg = response.toLowerCase()

    // Biomni tools - database queries
    if (msg.includes('uniprot') || msg.includes('protein') && msg.includes('query')) return 'database-query'
    if (msg.includes('ncbi') || msg.includes('genbank') || msg.includes('entrez')) return 'database-query'

    // Biomni tools - genomics/bioinformatics
    if (msg.includes('gene set enrichment') || msg.includes('gsea') || msg.includes('pathway')) return 'enrichment-analysis'
    if (msg.includes('primer') || msg.includes('pcr')) return 'primer-design'
    if (msg.includes('cell type annotation') || msg.includes('scrna') || msg.includes('single-cell')) return 'scrna-analysis'

    // Biomni tools - bioimaging
    if (msg.includes('segment') && (msg.includes('cell') || msg.includes('nuclei') || msg.includes('image'))) return 'cell-segmentation'
    if (msg.includes('image registration') || msg.includes('align') && msg.includes('image')) return 'image-registration'
    if (msg.includes('microscopy') || msg.includes('fluorescence')) return 'bioimaging'

    // Biomni tools - pharmacology
    if (msg.includes('drug') && (msg.includes('target') || msg.includes('interaction'))) return 'drug-target'
    if (msg.includes('smiles') || msg.includes('compound')) return 'drug-target'

    // Standard bioinformatics workflows
    if (msg.includes('rna-seq') || msg.includes('transcriptom')) return 'rna-seq'
    if (msg.includes('variant') || msg.includes('snp') || msg.includes('indel')) return 'variant-calling'
    if (msg.includes('genome') && msg.includes('assembl')) return 'genome-assembly'
    if (msg.includes('chip-seq') || msg.includes('chipseq')) return 'chip-seq'
    if (msg.includes('quality') || msg.includes('qc')) return 'quality-control'

    return 'custom' // Default to custom workflow instead of hardcoded RNA-seq
  }

  const getWorkflowTitleFromType = (type: string): string => {
    switch (type) {
      // Biomni workflow types
      case 'database-query': return 'Database Query Workflow'
      case 'enrichment-analysis': return 'Gene Set Enrichment Analysis'
      case 'primer-design': return 'PCR Primer Design Workflow'
      case 'scrna-analysis': return 'scRNA-seq Cell Type Annotation'
      case 'cell-segmentation': return 'Cell Segmentation Workflow'
      case 'image-registration': return 'Image Registration Pipeline'
      case 'bioimaging': return 'Bioimaging Analysis Workflow'
      case 'drug-target': return 'Drug-Target Interaction Prediction'
      case 'custom': return 'Custom Analysis Workflow'
      // Standard bioinformatics workflow types
      case 'rna-seq': return 'RNA-seq Analysis Pipeline'
      case 'variant-calling': return 'Variant Calling Workflow'
      case 'genome-assembly': return 'Genome Assembly Pipeline'
      case 'chip-seq': return 'ChIP-seq Analysis Workflow'
      case 'quality-control': return 'Data Quality Control Pipeline'
      default: return 'Bioinformatics Analysis Workflow'
    }
  }

  const getStepsForType = (type: string) => {
    switch (type) {
      // Biomni workflow types
      case 'database-query':
        return [
          {
            id: 'step1',
            title: 'Database Query',
            description: 'Query protein/gene database for information',
            tool: 'UniProt Query',
            complexity: 'simple',
            estimatedTime: '1 min'
          }
        ]

      case 'enrichment-analysis':
        return [
          {
            id: 'step1',
            title: 'Gene Set Enrichment',
            description: 'Analyze gene set enrichment across pathways',
            tool: 'GSEA',
            complexity: 'intermediate',
            estimatedTime: '5 min'
          }
        ]

      case 'primer-design':
        return [
          {
            id: 'step1',
            title: 'Primer Design',
            description: 'Design PCR primers for target sequence',
            tool: 'Primer3',
            complexity: 'simple',
            estimatedTime: '2 min'
          }
        ]

      case 'scrna-analysis':
        return [
          {
            id: 'step1',
            title: 'Cell Type Annotation',
            description: 'Annotate cell types in scRNA-seq data',
            tool: 'scRNA Annotator',
            complexity: 'complex',
            estimatedTime: '10 min'
          }
        ]

      case 'cell-segmentation':
        return [
          {
            id: 'step1',
            title: 'Cell Segmentation',
            description: 'Segment cells/nuclei in microscopy images',
            tool: 'CellProfiler',
            complexity: 'intermediate',
            estimatedTime: '5 min'
          }
        ]

      case 'image-registration':
        return [
          {
            id: 'step1',
            title: 'Image Registration',
            description: 'Align images to reference',
            tool: 'Image Aligner',
            complexity: 'intermediate',
            estimatedTime: '3 min'
          }
        ]

      case 'drug-target':
        return [
          {
            id: 'step1',
            title: 'Drug-Target Prediction',
            description: 'Predict drug-target interactions',
            tool: 'DTI Predictor',
            complexity: 'complex',
            estimatedTime: '5 min'
          }
        ]

      case 'custom':
        return [
          {
            id: 'step1',
            title: 'Analysis Step',
            description: 'Custom analysis step based on request',
            tool: 'Custom Tool',
            complexity: 'intermediate',
            estimatedTime: '5 min'
          }
        ]

      // Standard bioinformatics workflow types
      case 'rna-seq':
        return [
          {
            id: 'step1',
            title: 'Quality Control',
            description: 'Assess raw sequencing reads quality using FastQC',
            tool: 'FastQC',
            complexity: 'simple',
            estimatedTime: '5 min'
          },
          {
            id: 'step2',
            title: 'Read Alignment',
            description: 'Align reads to reference genome using HISAT2',
            tool: 'HISAT2',
            complexity: 'intermediate',
            estimatedTime: '15 min'
          },
          {
            id: 'step3',
            title: 'Gene Expression Quantification',
            description: 'Count reads mapping to genes using featureCounts',
            tool: 'featureCounts',
            complexity: 'complex',
            estimatedTime: '8 min'
          },
          {
            id: 'step4',
            title: 'Differential Expression Analysis',
            description: 'Identify significant expression changes using DESeq2',
            tool: 'DESeq2',
            complexity: 'complex',
            estimatedTime: '12 min'
          }
        ]

      case 'variant-calling':
        return [
          {
            id: 'step1',
            title: 'Quality Control',
            description: 'Check raw sequencing data quality',
            tool: 'FastQC',
            complexity: 'simple',
            estimatedTime: '5 min'
          },
          {
            id: 'step2',
            title: 'Read Alignment',
            description: 'Align reads to reference genome',
            tool: 'BWA-MEM',
            complexity: 'intermediate', 
            estimatedTime: '20 min'
          },
          {
            id: 'step3',
            title: 'Variant Calling',
            description: 'Call variants using GATK HaplotypeCaller',
            tool: 'GATK',
            complexity: 'complex',
            estimatedTime: '25 min'
          },
          {
            id: 'step4',
            title: 'Variant Filtering',
            description: 'Filter variants by quality metrics',
            tool: 'GATK VariantFiltration',
            complexity: 'intermediate',
            estimatedTime: '10 min'
          }
        ]
        
      default:
        return [
          {
            id: 'step1',
            title: 'Quality Control',
            description: 'Assess raw sequencing reads quality using FastQC',
            tool: 'FastQC',
            complexity: 'simple',
            estimatedTime: '5 min'
          },
          {
            id: 'step2', 
            title: 'Read Alignment',
            description: 'Align reads to reference genome using HISAT2',
            tool: 'HISAT2',
            complexity: 'intermediate',
            estimatedTime: '15 min'
          },
          {
            id: 'step3',
            title: 'Gene Expression Quantification',
            description: 'Count reads mapping to genes using featureCounts',
            tool: 'featureCounts', 
            complexity: 'complex',
            estimatedTime: '8 min'
          },
          {
            id: 'step4',
            title: 'Differential Expression Analysis',
            description: 'Identify significant expression changes using DESeq2',
            tool: 'DESeq2',
            complexity: 'complex',
            estimatedTime: '12 min'
          }
        ]
    }
  }

  const generateDemoWorkflow = () => {
    return {
      id: `workflow-${Date.now()}`,
      title: "RNA-seq Analysis Pipeline", 
      description: "Complete RNA-seq data analysis workflow",
      type: "rna-seq",
      steps: [
        {
          id: 'step1',
          title: 'Quality Control',
          description: 'Assess raw sequencing reads quality using FastQC',
          tool: 'FastQC',
          complexity: 'simple',
          estimatedTime: '5 min'
        },
        {
          id: 'step2', 
          title: 'Read Alignment',
          description: 'Align reads to reference genome using HISAT2',
          tool: 'HISAT2',
          complexity: 'intermediate',
          estimatedTime: '15 min'
        },
        {
          id: 'step3',
          title: 'Gene Expression Quantification',
          description: 'Count reads mapping to genes using featureCounts',
          tool: 'featureCounts', 
          complexity: 'complex',
          estimatedTime: '8 min'
        },
        {
          id: 'step4',
          title: 'Differential Expression Analysis',
          description: 'Identify significant expression changes using DESeq2',
          tool: 'DESeq2',
          complexity: 'complex',
          estimatedTime: '12 min'
        }
      ]
    }
  }

  const getStatusIcon = (status: WorkflowProgress['status']) => {
    switch (status) {
      case 'running': return Clock
      case 'completed': return CheckCircle
      case 'error': return AlertTriangle
      default: return Clock
    }
  }

  const getStatusColor = (status: WorkflowProgress['status']) => {
    switch (status) {
      case 'running': return 'text-blue-500'
      case 'completed': return 'text-green-500'
      case 'error': return 'text-red-500'
      default: return 'text-muted-foreground'
    }
  }

  const handleSendMessage = async (
    content: string,
    files?: File[],
    contextOverride?: Record<string, unknown>,
  ) => {
    // A workflow picked in the Workflows library rides with the message that runs it, as
    // structured context.selectedWorkflow (the server builds exactly that workflow, no search).
    if (!contextOverride?.selectedWorkflow) {
      const _picked = takeWorkflowSelection(content)
      setLibraryPick(null)
      if (_picked) contextOverride = { ...(contextOverride || {}), selectedWorkflow: _picked }
    }
    // Handle attached files: upload to backend and include dataset IDs in prompt context.
    if (files && files.length > 0) {
      console.log('[ChatInterface] Files attached:', files.map((f) => f.name))
      const uploaded: Array<{ name: string; datasetId?: string; galaxyDatasetId?: string; s3Uri?: string }> = []
      const failedUploads: string[] = []

      for (const file of files) {
        try {
          // Branches by size: ≤100 MiB → single POST to /api/datasets/upload;
          // larger → real S3 multipart (chunked PUT direct to S3 with per-part
          // retry). Closes the 5 GB ceiling for chat-composer attachments.
          const result = await uploadFileShared(file, {
            description: 'Uploaded from BioMate chat composer',
          })
          uploaded.push({
            name: file.name,
            datasetId: result.datasetId,
            galaxyDatasetId: result.galaxyDatasetId,
            s3Uri: result.s3Uri,
          })
        } catch (err) {
          const msg = err instanceof Error ? err.message : String(err)
          failedUploads.push(`${file.name} (${msg})`)
        }
      }

      const fileNames = files.map((f) => f.name).join(', ')
      const uploadedContext =
        uploaded.length > 0
          ? uploaded
              .map(
                (f) =>
                  `${f.name}: dataset_id=${f.datasetId || 'n/a'}${
                    f.galaxyDatasetId ? `, galaxy_dataset_id=${f.galaxyDatasetId}` : ''
                  }${f.s3Uri ? `, s3_uri=${f.s3Uri}` : ''}`
              )
              .join('; ')
          : ''
      const failedContext = failedUploads.length > 0 ? failedUploads.join(', ') : ''

      const prepared = exampleContextRef.current
      const preparedBlock = prepared && prepared.fileNames.every((n) => files.some((f) => f.name === n))
        ? `\n${preparedInputsBlock(prepared.context)}`
        : ''
      exampleContextRef.current = null
      content =
        content +
        (content ? '\n\n' : '') +
        `[Attached files: ${fileNames}]` +
        (uploadedContext ? `\n[Uploaded datasets: ${uploadedContext}]` : '') +
        (failedContext ? `\n[Upload warnings: ${failedContext}]` : '') +
        preparedBlock
    }

    // Create user message
    const msgId = Date.now().toString()
    const userMessage: Message = {
      id: msgId,
      content,
      role: "user",
      timestamp: new Date()
    }

    // Async file analysis — non-blocking, results appear as cards below the user message
    if (files && files.length > 0) {
      const filesToAnalyze = files.map(f => ({ name: f.name }))
      ;(async () => {
        try {
          const results = await Promise.all(
            filesToAnalyze.map(async (f) => {
              const r = await fetch(`/api/datasets/analyze?name=${encodeURIComponent(f.name)}`, { credentials: 'include' })
              if (!r.ok) return null
              return (await r.json()) as FileAnalysisResult
            })
          )
          const valid = results.filter((r): r is FileAnalysisResult => !!r?.analyzed)
          if (valid.length > 0) {
            setFileAnalysisMap(prev => ({ ...prev, [msgId]: valid }))
          }
        } catch { /* non-fatal */ }
      })()
    }

    // Add user message to chat session (create one if it doesn't exist)
    // The chat is created in (or, still empty, filed into) the active project from its first
    // message — the same project the stream context carries — so it never sits under "Other chats".
    const sendProjectId = (() => {
      if (activeProjectId) return activeProjectId
      try { return typeof window !== 'undefined' ? localStorage.getItem('biomate-active-project-id') : null } catch { return null }
    })()
    const sessionId = chatSession?.id
      ? (chatHistoryService.fileEmptySessionInProject(chatSession.id, sendProjectId), chatSession.id)
      : chatHistoryService.createNewSession(sendProjectId).id
    const updatedSession = chatHistoryService.addMessage(sessionId, userMessage)
    if (updatedSession && onChatUpdated) {
      onChatUpdated(updatedSession)
    }

    // Add placeholder assistant message for streaming UX
    const placeholderId = `assistant-stream-${Date.now()}`
    const placeholderMessage: Message = {
      id: placeholderId,
      content: "",
      role: "assistant",
      timestamp: new Date(),
      suggestions: [],
      metadata: {
        type: "text",
      },
    }
    const withPlaceholder = chatHistoryService.addMessage(sessionId, placeholderMessage)
    if (withPlaceholder && onChatUpdated) {
      onChatUpdated(withPlaceholder)
    }

    if (files && files.length > 0) onSubmitWithFiles?.()
    setIsTypingLocal(true)
    startTurn(sessionId)
    setWorkflowGeneratingPhase('thinking')

    analytics.track('query_sent', { query_length: content.length })

    // Call Galaxy API (always, regardless of session)
    chatMutation.mutate({ content, sessionId, placeholderId, contextOverride })

    onSendMessage(content)
  }

  // Stable bridge between handleSendMessage (recreated each render) and the
  // parent-registered sender (registered once on mount). The ref points at
  // the latest handleSendMessage; the registered closure reads through it.
  const handleSendMessageRef = useRef(handleSendMessage)
  handleSendMessageRef.current = handleSendMessage
  useEffect(() => {
    if (!onRegisterSendMessage) return
    onRegisterSendMessage((message, files, contextOverride) => {
      void handleSendMessageRef.current(message, files, contextOverride)
    })
  }, [onRegisterSendMessage])

  /**
   * Soft-queue wrapper around handleSendMessage.
   * Text-only messages submitted while the AI is responding are held in
   * pendingMessages and auto-submitted as soon as each response completes.
   * Messages with file attachments bypass the queue and go immediately.
   */
  const handleSendOrQueue = useCallback((content: string, files?: File[], contextOverride?: Record<string, unknown>) => {
    // Only text-only messages with NO lane override are soft-queued; a message
    // carrying a lane override (from the composer's lane preview) must reach the
    // send path with its override intact, so it bypasses the queue.
    if (turnBusy && !files?.length && !contextOverride && content.trim()) {
      setPendingMessages(prev => [...prev, content.trim()])
      return
    }
    // Use ref so we always call the latest handleSendMessage even when
    // turnBusy hasn't changed (e.g. user just clicked "New Chat").
    handleSendMessageRef.current(content, files, contextOverride)
  }, [turnBusy]) // eslint-disable-line react-hooks/exhaustive-deps

  const stopStreaming = useCallback(() => {
    abortControllerRef.current?.abort()
    abortControllerRef.current = null
    abortTurn(chatSessionIdRef.current) // the stream may belong to the pre-remount instance
    setIsTypingLocal(false)
    setWorkflowGeneratingPhase('thinking')
    const queuedCount = pendingMessagesRef.current.length
    if (queuedCount > 0) {
      setStopDialogQueueCount(queuedCount)
      setShowStopDialog(true)
    }
  }, [])

  // Auto-submit the next queued message once the AI finishes responding.
  useEffect(() => {
    if (!turnBusy && pendingMessagesRef.current.length > 0) {
      const [next, ...rest] = pendingMessagesRef.current
      setPendingMessages(rest)
      handleSendMessageRef.current(next)
    }
  }, [turnBusy]) // eslint-disable-line react-hooks/exhaustive-deps

  const handleToolClick = (tool: any) => {
    console.log('Tool clicked:', tool)
    // Future: Navigate to tool details or add to workflow
  }

  const handleSuggestionClick = (suggestion: string, message: Message) => {
    const normalized = suggestion.toLowerCase().trim()
    console.log("[ChatInterface] Suggestion clicked:", suggestion)

    // "Continue" — request continuation of a truncated response
    if (normalized === 'continue') {
      handleSendMessage('Please continue from where you left off.')
      return
    }

    if (normalized.includes("try again")) {
      const lastUserMessage = [...displayMessages].reverse().find((m) => m.role === "user" && m.content?.trim())
      if (lastUserMessage?.content) {
        emitUxEvent("async.retry_clicked", {
          sessionId: chatSession?.id,
          source: "chat_error_surface",
          suggestion,
        })
        handleSendMessage(lastUserMessage.content)
      }
      return
    }

    if (normalized.includes("report issue")) {
      emitUxEvent("async.report_issue_clicked", {
        sessionId: chatSession?.id,
        source: "chat_error_surface",
        suggestion,
        errorType: message.metadata?.errorType,
      })
      return
    }

    emitUxEvent("chat.suggestion_clicked", {
      sessionId: chatSession?.id,
      suggestion,
      messageRole: message.role,
    })
  }

  const handleDatasetClick = (dataset: any) => {
    console.log('Dataset clicked:', dataset)
    // Future: Preview dataset or add to workflow inputs
  }

  const handleCompress = async () => {
    if (!chatSession) {
      console.error('[ChatInterface] Cannot compress: no active session')
      return
    }

    try {
      setIsCompressing(true)
      console.log('[ChatInterface] Starting compression for session:', chatSession.id)

      // Call backend compression service
      const response = await fetch('/api/compress-session', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          sessionId: chatSession.id,
          messages: displayMessages,
          keepRecentCount: 3
        })
      })

      if (!response.ok) {
        throw new Error(`Compression failed: ${response.statusText}`)
      }

      const result = await response.json()

      console.log('[ChatInterface] Compression successful:', {
        messagesReduced: `${result.messagesBeforeCount} → ${result.messagesAfterCount}`,
        tokensReduced: `${result.tokensBeforeCount} → ${result.tokensAfterCount}`,
        compressionRatio: `${(result.compressionRatio * 100).toFixed(1)}%`
      })

      // Update session with compressed messages
      chatHistoryService.updateSession(chatSession.id, {
        messages: result.compressedMessages
      })

      // Update local state
      const updatedSession = chatHistoryService.getSession(chatSession.id)
      if (updatedSession && onChatUpdated) {
        onChatUpdated(updatedSession)
      }

      // Record compression in backend (optional - don't fail if this fails)
      try {
        await fetch(`/api/memory/sessions/${chatSession.id}/compress`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({
            summary: result.summary,
            messages_before: result.messagesBeforeCount,
            messages_after: result.messagesAfterCount,
            tokens_before: result.tokensBeforeCount,
            tokens_after: result.tokensAfterCount
          })
        })
      } catch (recordError) {
        console.warn('[ChatInterface] Failed to record compression in backend:', recordError)
        // Don't fail the compression - the local compression already succeeded
      }

      // Close dialog
      setShowCompressionDialog(false)
      setCompressionDismissed(false) // Allow showing again if needed

    } catch (error) {
      console.error('[ChatInterface] Compression failed:', error)
      alert('Compression failed. Please try again.')
    } finally {
      setIsCompressing(false)
    }
  }

  const handleCancelCompression = () => {
    console.log('[ChatInterface] Compression dismissed by user')
    setShowCompressionDialog(false)
    setCompressionDismissed(true)

    // Allow showing again after 10 minutes
    setTimeout(() => {
      setCompressionDismissed(false)
    }, 10 * 60 * 1000)
  }

  // Listen for LangGraph task updates dispatched via custom DOM events from SSE handlers
  useEffect(() => {
    const handler = (e: CustomEvent<{ task_id: string; status: TaskStatus; description?: string; elapsed_ms?: number }>) => {
      const { task_id, status, description, elapsed_ms } = e.detail
      setLanggraphTasks(prev => {
        const existing = prev.find(t => t.id === task_id)
        if (existing) {
          return prev.map(t =>
            t.id === task_id ? { ...t, status, elapsedMs: elapsed_ms } : t
          )
        }
        return [...prev, { id: task_id, description: description || task_id, status, elapsedMs: elapsed_ms }]
      })
    }
    window.addEventListener('langgraphTaskUpdate', handler as EventListener)
    return () => window.removeEventListener('langgraphTaskUpdate', handler as EventListener)
  }, [])

  const handleStopTask = useCallback((taskId: string) => {
    setLanggraphTasks(prev =>
      prev.map(t => t.id === taskId ? { ...t, status: 'stopped' as TaskStatus } : t)
    )
  }, [])

  const handleRetryTask = useCallback((taskId: string) => {
    setLanggraphTasks(prev =>
      prev.map(t => t.id === taskId ? { ...t, status: 'pending' as TaskStatus } : t)
    )
  }, [])

  const handleRemoveTask = useCallback((taskId: string) => {
    setLanggraphTasks(prev => prev.filter(t => t.id !== taskId))
  }, [])

  // Re-send the last user message to regenerate the assistant response.
  const handleRegenerate = useCallback(() => {
    const msgs = chatSession?.messages ?? []
    const lastUser = [...msgs].reverse().find(m => m.role === 'user')
    if (!lastUser?.content?.trim()) return
    handleSendOrQueue(lastUser.content)
  }, [chatSession?.messages, handleSendOrQueue])

  // "Redo as a validated run" (spec 02 §2.2). Given an instant/compute-style
  // assistant answer, find the user turn that produced it and re-send that
  // intent forced to the Cloud/validated-workflow lane via the existing
  // intentOverride path (backend maps 'workflow_generation' ->
  // needsWorkflowGeneration and skips ambiguity detection).
  const handleRedoAsValidatedRun = useCallback((message: Message) => {
    const msgs = chatSession?.messages ?? []
    const idx = msgs.findIndex(m => m.id === message.id)
    // Nearest preceding user turn (fall back to the last user message).
    const priorUser = idx >= 0
      ? [...msgs.slice(0, idx)].reverse().find(m => m.role === 'user' && m.content?.trim())
      : undefined
    const source = priorUser ?? [...msgs].reverse().find(m => m.role === 'user' && m.content?.trim())
    if (!source?.content?.trim()) return
    analytics.track('redo_as_validated_run', { sessionId: chatSession?.id })
    handleSendMessage(source.content, undefined, { intentOverride: 'workflow_generation' })
  }, [chatSession?.messages, chatSession?.id]) // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!externalPromptRequest) return
    if (turnBusy) return
    const prompt = externalPromptRequest.prompt?.trim()
    if (!prompt) {
      onExternalPromptConsumed?.(externalPromptRequest.id)
      return
    }
    handleSendMessage(prompt)
    onExternalPromptConsumed?.(externalPromptRequest.id)
  }, [externalPromptRequest, turnBusy])

  return (
    <div className={`flex flex-col h-full min-w-0 min-h-0 ${className}`}>
      <div
        className="sr-only"
        data-testid="chat-run-anchor-state"
        data-focused-run-id={focusedRunId || ""}
        data-focused-message-id={focusedAnchorMessageId || ""}
        data-highlighted-message-id={highlightedAnchorMessageId || ""}
        data-generating={isTypingLocal ? "true" : "false"}
      />
      {/* Compression status badge + active LLM model badge */}
      {(currentTokenCount > 0 || activeLLMModel) && (
        <div className="flex items-center justify-between p-2 border-b bg-background/95">
          {activeLLMModel ? (
            <span
              className="inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-fs-xs text-muted-foreground"
              data-testid="chat-model-label"
              data-model={activeLLMModel.model}
              data-chinese={activeLLMModel.isChinese ? 'true' : 'false'}
              title={activeLLMModel.model}
            >
              {modelLabel(activeLLMModel, locale)}
              {hasOwnOpenrouterKey && (
                <button
                  onClick={() => { setHasOwnOpenrouterKey(false); fetch('/api/user/llm-api-keys', { method: 'PATCH', credentials: 'include', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ provider: 'openrouter', key: '' }) }).catch(() => {}); }}
                  className="ml-0.5 hover:text-destructive"
                  title="Clear OpenRouter key — revert to BioMate default"
                  aria-label="Clear OpenRouter model"
                >×</button>
              )}
            </span>
          ) : <span />}
          {currentTokenCount > 0 && (
            <CompressionStatusBadge currentTokens={currentTokenCount} tokenLimit={200000} />
          )}
        </div>
      )}

      <ScrollArea className="chat-thread flex-1 min-h-0 min-w-0" ref={scrollRef}
        onScrollCapture={(event) => {
          const viewport = event.target as HTMLElement
          if (viewport.hasAttribute('data-radix-scroll-area-viewport')) {
            followChatTailRef.current = viewport.scrollHeight - viewport.scrollTop - viewport.clientHeight <= 48
          }
        }} data-testid="chat-messages" style={{
        padding: '24px clamp(16px, 4%, 56px) 20px',
      }}>
        {displayMessages.length === 0 && !isTyping && !isTypingLocal && (
          <>
            {/* ReturningUserWelcome still returns null (the old hardcoded
                WELCOME_PROMPTS grid is intentionally not restored). The
                cold-start module dashboard replaces it: it seeds the composer
                (does not send) via the captured draft setter, so the user
                still reviews and sends. Spec 00 §0.4/§0.5. */}
            <ReturningUserWelcome onSend={(q) => handleSendOrQueue(q)} />
            <ColdStartDashboard
              onSeed={async (text) => {
                if (preparingExampleRef.current) return;
                preparingExampleRef.current = true;
                setPreparingExample(true);
                try {
                  const example = await prepareColdStartSelection(text);
                  if (example.projectId) {
                    activeProjectContext?.setActiveProjectId(example.projectId);
                    handleFileToProject(example.projectId);
                  }
                  if (!localSetDraftRef.current || (example.files.length && !localExampleFilesRef.current)) {
                    throw new Error("The composer is still loading. Please try again.");
                  }
                  exampleContextRef.current = example.hiddenContext
                    ? { context: example.hiddenContext, fileNames: example.files.map((f) => f.name) }
                    : null;
                  localExampleFilesRef.current?.(example.files);
                  localSetDraftRef.current(example.prompt);
                } catch (error) {
                  toast({ title: "Could not prepare example", description: error instanceof Error ? error.message : "Please try again.", variant: "destructive" });
                } finally {
                  preparingExampleRef.current = false;
                  setPreparingExample(false);
                }
              }}
            />
          </>
        )}
        <div style={{ display: 'flex', flexDirection: 'column', gap: '22px' }}>
          {(() => {
            const visible = displayMessages.filter(
              // Hide empty assistant placeholder during typing UNLESS it already has a
              // progressStatus to show (research-phase progress indicator).
              msg => !(msg.role === 'assistant' && !msg.content?.trim() && !(msg.metadata as any)?.progressStatus && (isTyping || isTypingLocal))
            )
            // One assistant identity owns the run's progress and completion answer.
            const renderOne = (message: Message, progress: Message[] = [], continuation = false, hideActions = false) => {
              // Scope the global currentExecutionRun to THIS card: show run status/findings
              // only when the run's id/galaxyInvocationId matches the card's own invocationId.
              // Previously the guard short-circuited when a card had no invocationId
              // (generated-but-never-executed) and handed it the GLOBAL run → the new card
              // showed another workflow's status + findings. (audit sweep S4#1, data-integrity)
              const scopedRun = (!!message.invocationId &&
                [currentExecutionRun?.id, currentExecutionRun?.execution?.galaxyInvocationId].includes(message.invocationId))
                ? currentExecutionRun : null;
              return (
              <div key={message.id}>
                <ChatMessage
                  message={message}
                  progressMessages={progress}
                  continuation={continuation}
                  hideActions={hideActions}
                  sessionId={chatSession?.id}
                  onToolClick={handleToolClick}
                  onDatasetClick={handleDatasetClick}
                  onCreateWorkflow={() => {
                    if (message.metadata?.workflow) {
                      onWorkflowGenerated(message.metadata.workflow);
                    }
                  }}
                  // Workflow execution props for inline artifacts
                  onRunWorkflow={onRunWorkflow ? (workflow, steps) => onRunWorkflow(workflow, steps, message.id) : undefined}
                  onRunChain={onRunChain}
                  onRunPipeline={onRunPipeline}
                  onApprovePipelineStep={onApprovePipelineStep}
                  onStopWorkflow={onStopWorkflow}
                  onPauseWorkflow={onPauseWorkflow}
                  onResumeWorkflow={onResumeWorkflow}
                  onParameterChange={onParameterChange}
                  onRegenerate={handleRegenerate}
                  onSuggestionClick={handleSuggestionClick}
                  onRedoAsValidatedRun={handleRedoAsValidatedRun}
                  onFollowUpQuestion={(question) => localSetDraftRef.current?.(question)}
                  onWorkflowProgress={handleWorkflowProgress}
                  isWorkflowRunning={isWorkflowRunning}
                  workflowProgress={workflowProgress}
                  currentExecutionRun={scopedRun}
                  isStreaming={(isTyping || isTypingLocal || sessionTurnActive) && message.id === lastMsg?.id && message.role === "assistant"}
                  isLatestAssistantMessage={message.id === latestAssistantMessageId}
                  isRunAnchorFocused={focusedAnchorMessageId === message.id}
                  isRunAnchorHighlighted={highlightedAnchorMessageId === message.id}
                  isInPanel={!!panelWorkflowMessageId && message.id === panelWorkflowMessageId}
                  onOpenInPanel={
                    message.metadata?.type === 'workflow' && message.metadata?.workflow
                      ? (opts) => onOpenWorkflowInPanel?.(message.id, message.metadata!.workflow, opts?.tab)
                      : undefined
                  }
                />
                {/* Inline file analysis cards — shown below user messages after async analysis */}
                {message.role === 'user' && fileAnalysisMap[message.id] && (
                  <div className="ml-10 mt-1 space-y-1">
                    {fileAnalysisMap[message.id].map((result, i) => (
                      <DataAnalysisCard key={i} result={result} />
                    ))}
                  </div>
                )}
                {/* FindingsCard — shown below completed workflow messages */}
                {message.role === 'assistant' &&
                  message.metadata?.type === 'workflow' &&
                  scopedRun?.id &&
                  (scopedRun?.execution?.status === 'completed' || (scopedRun?.execution?.status as string) === 'ok' || (scopedRun?.execution?.status as string) === 'succeeded') &&
                  message.id === latestAssistantMessageId && (
                  <div className="ml-10 mt-1">
                    <FindingsCard
                      runId={scopedRun.id}
                      onContinueAnalysis={(suggestion) => handleSendOrQueue(suggestion)}
                      preview
                    />
                  </div>
                )}
              </div>
              );
            }
            // Use persisted run identities; unrelated and legacy entries keep their chronology.
            const groups = groupWorkflowResponses(visible, currentExecutionRun ? {
              id: currentExecutionRun.id,
              invocationId: currentExecutionRun.execution?.galaxyInvocationId,
            } : undefined)
            return groups.map((g) => {
              if (g.kind === 'response') return (
                <section key={g.key} aria-label="Workflow response" className="min-w-0 space-y-3">
                  {renderOne(g.message, g.progress, false, g.findings.length > 0)}
                  {g.findings.map(message => renderOne(message, [], true))}
                </section>
              )
              if (g.kind === 'single') return renderOne(g.message)
              return <ProgressStreamBox key={g.key} messages={g.messages} />
            })
          })()}
          {displayTyping && <TypingIndicator phase={showWorkflowCue ? 'workflow' : workflowGeneratingPhase} />}
          {/* Auto-scroll anchor */}
          <div ref={messagesEndRef} />
        </div>
      </ScrollArea>
      
      {/* Compact Progress Indicator - Shows ONLY if workflow running but NO inline artifact visible
          The inline WorkflowArtifact in chat messages is the primary progress display.
          This compact bar only shows for workflows started outside chat or legacy mode.
          UI Simplification: Removed detailed step list - see inline artifact for details. */}
      {activeWorkflow && !displayMessages.some(m => m.metadata?.type === 'workflow' && m.metadata?.workflow) && (
        <div className="border-t bg-background">
          <div
            className="w-full p-3 cursor-pointer hover:bg-muted/50 transition-colors"
            onClick={onToggleProgress}
            data-testid="button-toggle-progress"
          >
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                {(() => {
                  const StatusIcon = getStatusIcon(activeWorkflow.status)
                  return <StatusIcon className={cn("w-4 h-4", getStatusColor(activeWorkflow.status))} />
                })()}
                <span className="text-sm font-medium">{activeWorkflow.title}</span>
                <Badge variant="secondary" className="text-xs">
                  {activeWorkflow.progress}%
                </Badge>
              </div>
              <div className="flex items-center gap-2 text-xs text-muted-foreground">
                {activeWorkflow.steps.filter(s => s.status === 'completed').length}/{activeWorkflow.steps.length} steps
                {showProgress ? <ChevronDown className="w-3 h-3" /> : <ChevronRight className="w-3 h-3" />}
              </div>
            </div>
          </div>

          {showProgress && (
            <div className="p-4 pt-0">
              <Separator className="mb-4" />
              
              {/* Progress Bar */}
              <div className="mb-4">
                <div className="flex justify-between text-sm mb-2">
                  <span className="text-muted-foreground">Overall Progress</span>
                  <span className="font-medium">{activeWorkflow.progress}%</span>
                </div>
                <div className="w-full bg-muted rounded-full h-2">
                  <div 
                    className="bg-primary h-2 rounded-full transition-all duration-500"
                    style={{ width: `${activeWorkflow.progress}%` }}
                  />
                </div>
              </div>

              {/* Steps Detail */}
              <div className="space-y-2">
                <h4 className="font-medium text-sm">Pipeline Steps</h4>
                <div className="space-y-1">
                  {activeWorkflow.steps.map((step, index) => {
                    const StepIcon = getStatusIcon(step.status)
                    return (
                      <div key={step.id} className="flex items-center gap-2 text-sm p-2 rounded-md hover:bg-muted/50">
                        <div className="w-6 h-6 rounded-full border-2 flex items-center justify-center text-xs font-medium bg-background">
                          {index + 1}
                        </div>
                        <StepIcon className={cn("w-3 h-3", getStatusColor(step.status))} />
                        <span className="flex-1">{step.name}</span>
                        {step.duration && (
                          <span className="text-xs text-muted-foreground">{step.duration}</span>
                        )}
                        {step.status === 'running' && (
                          <div className="w-2 h-2 bg-blue-500 rounded-full animate-pulse" />
                        )}
                      </div>
                    )
                  })}
                </div>
              </div>

              {/* Quick Actions */}
              <div className="flex gap-2 mt-4">
                <Button size="sm" variant="outline" data-testid="button-view-logs">
                  View Logs
                </Button>
                <Button size="sm" variant="outline" data-testid="button-workflow-settings">
                  <Settings className="w-3 h-3 mr-1" />
                  Settings
                </Button>
              </div>
            </div>
          )}
        </div>
      )}

      {(langgraphTasks.length > 0 || pendingMessages.length > 0) && (
        <div className="px-4 pb-2">
          <TaskList
            tasks={langgraphTasks}
            queuedMessages={pendingMessages}
            onStopTask={handleStopTask}
            onRemoveTask={handleRemoveTask}
            onRetryTask={handleRetryTask}
            onRemoveMessage={(i) => setPendingMessages(prev => prev.filter((_, idx) => idx !== i))}
          />
        </div>
      )}
      {showStopDialog && (
        <div
          className="mx-4 mb-2 rounded-lg border bg-background shadow-md p-3 text-sm"
          data-testid="stop-dialog"
        >
          <p className="font-medium mb-2 text-foreground">
            Reply stopped. What should happen to your {stopDialogQueueCount} queued message{stopDialogQueueCount !== 1 ? 's' : ''}?
          </p>
          <div className="flex gap-2">
            <button
              className="rounded border border-border px-3 py-1.5 text-xs hover:bg-muted"
              data-testid="stop-reply-only"
              onClick={() => setShowStopDialog(false)}
            >
              Keep queued ({stopDialogQueueCount})
            </button>
            <button
              className="rounded bg-destructive text-destructive-foreground px-3 py-1.5 text-xs hover:bg-destructive/90"
              data-testid="stop-and-clear-queue"
              onClick={() => {
                setPendingMessages([])
                setShowStopDialog(false)
              }}
            >
              Clear all queued
            </button>
          </div>
        </div>
      )}
      {/* Reference design chat input wrap — padding clamp like layout.css */}
      {/* Composer sits on the chat canvas (no separate footer bar) — the
          input card itself carries the border/elevation. */}
      <div style={{ padding: '14px 24px 18px' }}>
        {preparingExample && <p role="status" className="text-sm text-muted-foreground px-4">Preparing sample data…</p>}
        <LiveVoicePanel key={chatSession?.id || "new-chat"} busy={turnBusy || preparingExample}
          reply={[...displayMessages].reverse().find(m => m.role === "assistant" && m.metadata?.type !== "error" && m.content?.trim())}
          onSend={text => handleSendOrQueue(text)} />
        {libraryPick && (
          <div className="mx-auto mb-1 w-full max-w-3xl rounded-md border border-amber-300/60 bg-amber-50 px-3 py-1.5 text-xs text-amber-900 dark:bg-amber-950/30 dark:text-amber-200" role="note" data-testid="library-input-reminder">
            {t('chat.library_input_reminder', { name: libraryPick })}
          </div>
        )}
        <ChatInput
          voiceContextKey={chatSession?.id || "new-chat"}
          disabled={preparingExample}
          onSend={handleSendOrQueue}
          pendingCount={pendingMessages.length}
          isStreaming={turnBusy}
          onStop={stopStreaming}
          onRegisterSetDraft={(setter) => {
            localSetDraftRef.current = setter
            onRegisterSetDraft?.(setter)
          }}
          onRegisterAddFiles={(adder) => { localAddFilesRef.current = adder }}
          onRegisterExampleFiles={(setter) => { localExampleFilesRef.current = setter }}
          /* Surface session-wide attached-dataset count so the
             X / MAX_DATASET_REFS indicator in the input strip reflects
             the server-side cap (frontend/server/dataset-cap.ts). */
          sessionDatasetCount={chatSession?.datasets?.length ?? 0}
          /* Real projects feed the "project suggested" row (§6.6) + seed the
             instructions field (§6.5). No projects → row stays hidden. */
          projects={composerProjects}
          activeProjectId={activeProjectId}
          onFileToProject={handleFileToProject}
        />
      </div>
      {/* chat-analysis-status kept for E2E selectors but visually hidden — TypingIndicator in message list handles the visual */}
      <div
        className="sr-only"
        role="status"
        aria-live="polite"
        data-testid="chat-analysis-status"
        data-active={turnBusy ? "true" : "false"}
      />

      {/* Compression dialog */}
      <CompressionDialog
        open={showCompressionDialog}
        currentTokens={currentTokenCount}
        tokenLimit={200000}
        messageCount={displayMessages.length}
        isCompressing={isCompressing}
        onCompress={handleCompress}
        onCancel={handleCancelCompression}
        onStartNewChat={() => {
          setShowCompressionDialog(false)
          const newSession = chatHistoryService.createNewSession()
          if (newSession && onChatUpdated) onChatUpdated(newSession)
        }}
      />
    </div>
  )
}
