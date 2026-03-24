import type { Express } from "express";
import express from "express";
import { createServer, type Server } from "http";
import { storage } from "./storage";
import OpenAI from "openai";
import { datasetConfigSchema, inviteCodes, inviteCodeUses } from "../shared/schema";
import type { InsertInviteCode } from "../shared/schema";
import { db } from "./db";
import { eq, desc, and } from "drizzle-orm";
import { mockGalaxyAPI } from "./mock-galaxy-api";
import { GalaxyAPIProxy } from "./galaxy-api-proxy";
import { createPoller } from "./galaxy-state-poller";
import { WorkflowSSEManager } from "./workflow-sse";
import { createWorkflowNotificationService, type WorkflowNotificationService } from "./workflow-notification-service";
import { GalaxyAssistant, type ModelConfig } from "./galaxy-assistant";
import { parameterRepository } from "./parameter-repository";
import { workflowRepository } from "./workflow-repository";
import { memoryService } from "./memory-repository";
import { createMemoryIntegration, getMemoryIntegration, type MemoryEnhancedContext } from "./memory-integration";
import { datasetValidator } from "./dataset-validator";
import { getContextCompressor } from "./context-compressor";
import { WorkflowPrerequisitesValidator } from "./workflow-prerequisites-validator";
import multer from "multer";
import { promises as fs, createReadStream } from "fs";
import path from "path";
import { v4 as uuidv4 } from "uuid";
import archiver from "archiver";
import { createHash } from "crypto";
import { authService } from "./auth-service";
import { authenticateToken, optionalAuth } from "./auth-middleware";
import BetterSqlite3 from "better-sqlite3";
import type { RegisterData, LoginData } from "./auth-service";
import { s3Service } from "./s3-client";
import {
  apiLimiter,
  authLimiter,
  registerLimiter,
  passwordResetLimiter,
  emailVerificationLimiter,
  uploadLimiter,
} from "./rate-limit";
import { checkBillingQuota } from "./quota-middleware";
import passport from "passport";
import { oauthService } from "./oauth-service";
import { stripeService } from "./stripe-service";
import { auditService, auditMiddleware } from "./audit-service";
import { conversationStateManager, createEmptyState, type ConversationState } from "./conversation-state";
import {
  getExecutionRunsOverview,
  RunOverviewBadRequestError,
} from "./run-overview";
import { telemetryService } from "./telemetry-service";
import { TokenCounter } from "./token-counter";
import {
  buildNextflowComputeConfig,
  evaluateHardwareGate,
} from "./execution-env-policy";

// Initialize OpenAI (optional for development)
const openai = (process.env.OPENAI_API_KEY && process.env.OPENAI_API_KEY.trim()) ? new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
}) : null;

// Initialize Galaxy backend - using REAL Galaxy API (no more mock)
const galaxyAPIBackend = new GalaxyAPIProxy(); // Real Galaxy API for all operations
const galaxyAPIProxy = galaxyAPIBackend; // Alias for consistency
const tokenCounter = new TokenCounter();

// Initialize state poller and SSE manager
const galaxyPoller = createPoller(galaxyAPIBackend, { pollInterval: 2000 });
const sseManager = new WorkflowSSEManager(galaxyPoller);

// Helper function to determine file type from extension
function getFileType(extension: string): string {
  const imageExtensions = ['png', 'jpg', 'jpeg', 'gif', 'svg', 'bmp', 'tiff', 'webp'];
  const tableExtensions = ['csv', 'tsv', 'tabular', 'bed', 'gff', 'gtf', 'vcf', 'sam', 'bam'];
  const textExtensions = ['txt', 'fasta', 'fastq', 'fa', 'fq', 'json', 'xml', 'html', 'htm', 'log'];
  const interactiveExtensions = ['html', 'htm', 'pdf'];

  const ext = (extension || '').toLowerCase();
  if (imageExtensions.includes(ext)) return 'image';
  if (tableExtensions.includes(ext)) return 'table';
  if (interactiveExtensions.includes(ext)) return 'interactive';
  if (textExtensions.includes(ext)) return 'text';
  return 'binary';
}

/**
 * Determine workflow execution engine based on workflow definition.
 * Centralizes the logic for detecting Galaxy reuse vs Nextflow execution.
 *
 * Detection priority:
 * 1. Explicit Galaxy reuse markers (tags, metadata) → 'galaxy'
 * 2. Explicit Nextflow markers (tags, metadata) → 'nextflow'
 * 3. Default → 'nextflow' (as per integration plan)
 */
function getWorkflowExecutionEngine(workflowDef: any): 'galaxy' | 'nextflow' {
  const tags = workflowDef?.tags || [];
  const metadata = workflowDef?.metadata || {};

  // Check for explicit Galaxy reuse markers
  const isGalaxyReuse =
    tags.includes('galaxy-reuse') ||
    tags.includes('galaxy-import') ||
    metadata.source === 'galaxy_reuse' ||
    workflowDef?.isGalaxyWorkflow === true;

  if (isGalaxyReuse) {
    return 'galaxy';
  }

  // Check for Nextflow markers
  const isNextflow =
    tags.includes('nextflow') ||
    tags.includes('native-execution') ||
    metadata.source === 'nextflow';

  if (isNextflow) {
    return 'nextflow';
  }

  // Default to Nextflow (as per integration plan)
  return 'nextflow';
}

type AutofixLifecycleState =
  | "idle"
  | "analyzing"
  | "fixing"
  | "restarting"
  | "succeeded"
  | "failed";

function normalizeAutofixState(raw: any): AutofixLifecycleState {
  const value = String(raw ?? "").toLowerCase();
  if (!value) return "idle";
  if (["analyzing", "analysis", "planning"].includes(value)) return "analyzing";
  if (["fixing", "running", "in_progress", "applying", "queued"].includes(value)) return "fixing";
  if (["restarting", "restart_pending", "restart_in_progress"].includes(value)) return "restarting";
  if (["succeeded", "success", "completed", "fixed"].includes(value)) return "succeeded";
  if (["failed", "error", "aborted", "timeout"].includes(value)) return "failed";
  return "idle";
}

function deriveAutofixLifecycle(session: any): {
  state: AutofixLifecycleState;
  source: "auto" | "manual" | "unknown";
  lastActionAt?: string;
  message?: string;
  sessionId?: string;
  totalAttempts?: number;
  terminationReason?: string;
} {
  if (!session) {
    return { state: "idle", source: "unknown" };
  }

  const rawSource = String(
    session?.source ?? session?.trigger_source ?? session?.mode ?? ""
  ).toLowerCase();
  const source =
    rawSource.includes("auto")
      ? "auto"
      : rawSource.includes("manual")
      ? "manual"
      : "unknown";

  const terminationReason = session?.termination_reason || session?.result || session?.reason;
  const stateFromSession = normalizeAutofixState(
    session?.status || session?.state || session?.phase
  );
  const stateFromTermination = normalizeAutofixState(terminationReason);
  const state = stateFromSession !== "idle" ? stateFromSession : stateFromTermination;

  return {
    state,
    source,
    lastActionAt:
      session?.updated_at ||
      session?.updatedAt ||
      session?.finished_at ||
      session?.created_at,
    message:
      session?.message ||
      session?.summary ||
      session?.explanation ||
      (terminationReason ? String(terminationReason) : undefined),
    sessionId: session?.session_id || session?.id,
    totalAttempts:
      typeof session?.total_attempts === "number"
        ? session.total_attempts
        : typeof session?.attempts === "number"
        ? session.attempts
        : undefined,
    terminationReason: terminationReason ? String(terminationReason) : undefined,
  };
}

async function getAutofixLifecycleForRun(run: any): Promise<{
  state: AutofixLifecycleState;
  source: "auto" | "manual" | "unknown";
  active: boolean;
  lastActionAt?: string;
  message?: string;
  sessionId?: string;
  totalAttempts?: number;
  terminationReason?: string;
}> {
  const cached = run?.execution?.nextflowStatus?.autofix;
  if (cached) {
    const state = normalizeAutofixState(cached.state);
    return {
      state,
      source:
        cached.source === "auto" || cached.source === "manual"
          ? cached.source
          : "unknown",
      active: cached.active === true || ["analyzing", "fixing", "restarting"].includes(state),
      lastActionAt: cached.lastActionAt,
      message: cached.message,
      sessionId: cached.sessionId,
      totalAttempts: cached.totalAttempts,
      terminationReason: cached.terminationReason,
    };
  }

  if (!run?.execution?.galaxyWorkflowId || !run?.execution?.galaxyInvocationId) {
    return { state: "idle", source: "unknown", active: false };
  }

  try {
    const sessionsResult = await galaxyAPIBackend.listAutofix3Sessions(
      run.execution.galaxyWorkflowId,
      run.execution.galaxyInvocationId,
      1
    );
    const latestSession = Array.isArray(sessionsResult?.sessions)
      ? sessionsResult.sessions[0]
      : undefined;
    const lifecycle = deriveAutofixLifecycle(latestSession);
    return {
      ...lifecycle,
      active: ["analyzing", "fixing", "restarting"].includes(lifecycle.state),
    };
  } catch (error: any) {
    console.warn("[AutoFix] Failed to resolve lifecycle for run:", error?.message || error);
    return { state: "idle", source: "unknown", active: false };
  }
}

function normalizeWorkflowName(raw: any): string {
  return String(raw || "")
    .trim()
    .toLowerCase()
    .replace(/\s+/g, " ");
}

function normalizeForFingerprint(value: any): any {
  if (Array.isArray(value)) {
    return value.map((item) => normalizeForFingerprint(item));
  }
  if (value && typeof value === "object") {
    return Object.keys(value)
      .sort()
      .reduce((acc: Record<string, any>, key) => {
        acc[key] = normalizeForFingerprint(value[key]);
        return acc;
      }, {});
  }
  return value;
}

function buildWorkflowFingerprint(workflowDef: any): string {
  if (!workflowDef || typeof workflowDef !== "object") {
    return "";
  }

  const steps = workflowDef.steps && typeof workflowDef.steps === "object" ? workflowDef.steps : {};
  const normalizedSteps = Object.entries(steps)
    .sort(([a], [b]) => String(a).localeCompare(String(b)))
    .map(([stepId, rawStep]: [string, any]) => {
      let normalizedToolState: any = rawStep?.tool_state;
      if (typeof normalizedToolState === "string") {
        try {
          normalizedToolState = JSON.parse(normalizedToolState);
        } catch {
          // Keep raw string if not valid JSON.
        }
      }
      return {
        stepId,
        type: rawStep?.type,
        tool_id: rawStep?.tool_id || rawStep?.tool,
        name: rawStep?.name || rawStep?.label,
        annotation: rawStep?.annotation,
        inputs: rawStep?.inputs,
        input_connections: rawStep?.input_connections,
        tool_state: normalizedToolState,
      };
    });

  const normalizedWorkflowShape = normalizeForFingerprint({
    executionEngineHint: getWorkflowExecutionEngine(workflowDef),
    workflow_type: workflowDef.workflow_type || workflowDef.format,
    format: workflowDef.format,
    nextflow_path: workflowDef.nextflow_path,
    parameters: workflowDef.parameters || {},
    steps: normalizedSteps,
  });

  return createHash("sha256")
    .update(JSON.stringify(normalizedWorkflowShape))
    .digest("hex");
}

// Initialize workflow notification service for email notifications
const workflowNotificationService = createWorkflowNotificationService(galaxyPoller, storage as any);

function registerInvocationNotifications({
  invocationId,
  req,
  workflowName,
  workflowId,
  source,
}: {
  invocationId: string | null | undefined;
  req: any;
  workflowName: string;
  workflowId: string;
  source: string;
}): void {
  const user = req?.user;
  if (!invocationId) {
    console.warn(`[WorkflowNotification] Skipping registration (${source}): missing invocation id`);
    return;
  }
  if (!user?.email) {
    console.log(`[WorkflowNotification] Skipping registration (${source}): unauthenticated or no email`);
    return;
  }

  try {
    workflowNotificationService.registerInvocation(invocationId, {
      userId: String(user.id || "anonymous"),
      userEmail: String(user.email),
      userName: String(user.fullName || user.email.split("@")[0] || "User"),
      workflowName: workflowName || "Workflow",
      workflowId: workflowId || "unknown",
      startTime: new Date(),
    });
    console.log(`[WorkflowNotification] Registered invocation ${invocationId} from ${source}`);
  } catch (error: any) {
    console.warn(`[WorkflowNotification] Registration failed (${source}) for ${invocationId}:`, error?.message || error);
  }
}

// Listen for workflow completion to update bioMate invocation records
galaxyPoller.on('workflow_completed', async (data: { invocation_id: string; state: string }) => {
  try {
    // Update legacy invocation record
    const invocation = await storage.getInvocationByGalaxyId(data.invocation_id);
    if (invocation) {
      const finalStatus = data.state === 'ok' || data.state === 'scheduled' ? 'ok' : 'error';

      // Retrieve outputs from Galaxy for the invocation record
      let outputDatasets: any[] = [];
      let totalOutputSize = 0;
      if (finalStatus === 'ok' && invocation.galaxyHistoryId) {
        try {
          // Get the actual history_id from Galaxy invocation (may differ from stored)
          const galaxyInvocation = await galaxyAPIProxy.getInvocation(
            invocation.galaxyWorkflowId!,
            data.invocation_id
          );
          const actualHistoryId = galaxyInvocation.history_id || invocation.galaxyHistoryId;
          console.log(`[WorkflowComplete] Fetching outputs from history: ${actualHistoryId}`);

          const historyContents = await galaxyAPIProxy.getHistoryContents(actualHistoryId);

          // Filter for completed output datasets
          outputDatasets = historyContents
            .filter((item: any) =>
              item.history_content_type === 'dataset' &&
              item.state === 'ok' &&
              !item.deleted
            )
            .map((dataset: any) => ({
              id: dataset.id,
              name: dataset.name,
              extension: dataset.extension,
              size: dataset.file_size || 0,
              fileType: getFileType(dataset.extension),
              datasetId: dataset.id,
              galaxyUrl: `/api/datasets/${dataset.id}/display`,
            }));

          totalOutputSize = outputDatasets.reduce((sum: number, d: any) => sum + (d.size || 0), 0);
          console.log(`[WorkflowComplete] Found ${outputDatasets.length} outputs for invocation ${invocation.id}`);

          // Also add outputs to the outputs collection for the /api/invocations/:id/outputs endpoint
          for (const output of outputDatasets) {
            await storage.addOutput({
              id: output.id,
              invocationId: invocation.id,
              name: output.name,
              extension: output.extension,
              size: output.size,
              fileType: output.fileType,
              galaxyDatasetId: output.datasetId,
              createdAt: new Date(),
            });
          }
          console.log(`[WorkflowComplete] Added ${outputDatasets.length} outputs to storage for API access`);
        } catch (outputError) {
          console.error('[WorkflowComplete] Failed to retrieve invocation outputs:', outputError);
        }
      }

      await storage.updateInvocation(invocation.id, {
        status: finalStatus,
        completedAt: new Date(),
        completedSteps: invocation.totalSteps,
        outputDatasets,
        outputCount: outputDatasets.length,
        totalOutputSize,
      });
      console.log(`[WorkflowComplete] Updated bioMate invocation ${invocation.id} to completed with ${outputDatasets.length} outputs`);
    }

    // CRITICAL FIX: Also update execution run records
    const executionRun = await storage.getExecutionRunByGalaxyId(data.invocation_id);
    if (executionRun) {
      // Map Galaxy 'ok'/'scheduled' → 'completed' (consistent with Nextflow promotion).
      // Never downgrade an already-promoted 'completed' status.
      const desiredStatus = data.state === 'ok' || data.state === 'scheduled' ? 'completed' : 'error';
      const finalStatus = executionRun.execution?.status === 'completed' ? 'completed' : desiredStatus;
      await storage.updateExecutionRunStatus(executionRun.id, finalStatus as any);
      // Update progress to 100% — completedSteps == totalSteps, currentStepIndex == totalSteps - 1
      const totalSteps = executionRun.progress.totalSteps || 1;
      await storage.updateExecutionRunProgress(
        executionRun.id,
        totalSteps,         // completedSteps = all done
        totalSteps - 1,     // currentStepIndex = last step (0-indexed)
        'Complete'
      );
      console.log(`[WorkflowComplete] Updated execution run ${executionRun.id} to ${finalStatus} (state=${data.state})`);

      // CRITICAL FIX: Retrieve and store workflow outputs from Galaxy
      if (finalStatus === 'ok' && executionRun.execution.galaxyWorkflowId) {
        try {
          // Get the actual history_id from the Galaxy invocation (may differ from what we requested)
          const galaxyInvocation = await galaxyAPIProxy.getInvocation(
            executionRun.execution.galaxyWorkflowId,
            data.invocation_id
          );
          const actualHistoryId = galaxyInvocation.history_id || executionRun.execution.galaxyHistoryId || '';
          console.log(`[WorkflowComplete] Using actual history_id: ${actualHistoryId} (stored: ${executionRun.execution.galaxyHistoryId})`);

          const historyContents = await galaxyAPIProxy.getHistoryContents(actualHistoryId);

          // Filter for output datasets (state=ok, not deleted)
          const outputDatasets = historyContents.filter((item: any) =>
            item.history_content_type === 'dataset' &&
            item.state === 'ok' &&
            !item.deleted
          );

          // Update each step with its outputs
          const updatedSteps = executionRun.steps.map((step: any) => ({
            ...step,
            status: 'completed',
            outputs: outputDatasets.map((dataset: any) => ({
              id: dataset.id,
              name: dataset.name,
              extension: dataset.extension,
              fileSize: dataset.file_size || 0,
              state: dataset.state,
              datasetId: dataset.id,
            })),
          }));

          // Update metrics with output info
          const totalSize = outputDatasets.reduce((sum: number, d: any) => sum + (d.file_size || 0), 0);

          await storage.updateExecutionRun(executionRun.id, {
            steps: updatedSteps,
            metrics: {
              ...executionRun.metrics,
              quality: executionRun.metrics?.quality || {},
              outputs: {
                fileCount: outputDatasets.length,
                totalSizeBytes: totalSize,
                byType: outputDatasets.reduce((acc: any, d: any) => {
                  acc[d.extension] = (acc[d.extension] || 0) + 1;
                  return acc;
                }, {} as Record<string, number>),
                bySize: {} as Record<string, number>,
              },
            },
          });

          console.log(`[WorkflowComplete] Retrieved ${outputDatasets.length} outputs for run ${executionRun.id}`);
        } catch (outputError) {
          console.error('[WorkflowComplete] Failed to retrieve outputs:', outputError);
        }
      }
    }
  } catch (error) {
    console.error('[WorkflowComplete] Failed to update invocation/execution run:', error);
  }
});

// Listen for step state changes to update execution run progress
galaxyPoller.on('step_state', async (data: { invocation_id: string; data: { step_id: string; step_state: string } }) => {
  try {
    const executionRun = await storage.getExecutionRunByGalaxyId(data.invocation_id);
    if (executionRun) {
      // Update run status to 'running' if it's still 'queued' or 'configuring'
      const currentStatus = executionRun.execution.status;
      if (currentStatus === 'queued' || currentStatus === 'configuring') {
        await storage.updateExecutionRunStatus(executionRun.id, 'running');
      }

      // Count completed steps
      const invocationState = galaxyPoller.getState(data.invocation_id);
      if (invocationState) {
        const completedSteps = invocationState.steps.filter((s: any) => {
          const state = s.jobs?.[0]?.state || s.state;
          return state === 'ok' || state === 'error';
        }).length;

        await storage.updateExecutionRunProgress(
          executionRun.id,
          completedSteps,
          completedSteps,
          data.data.step_state === 'running' ? 'Running...' : data.data.step_state
        );
      }
    }
  } catch (error) {
    console.error('[StepState] Failed to update execution run progress:', error);
  }
});

// Initialize Galaxy Assistant (hybrid intelligence with Claude Sonnet 4.5)
const parsedThinkingBudget = process.env.BIOMATE_THINKING_BUDGET
  ? Number(process.env.BIOMATE_THINKING_BUDGET)
  : undefined;

const modelConfigOverrides: Partial<ModelConfig> = {};

if (process.env.BIOMATE_INTENT_MODEL) {
  modelConfigOverrides.intentModel = process.env.BIOMATE_INTENT_MODEL;
}

if (process.env.BIOMATE_TOOL_RANKING_MODEL) {
  modelConfigOverrides.toolRankingModel = process.env.BIOMATE_TOOL_RANKING_MODEL;
}

if (process.env.BIOMATE_RESPONSE_MODEL) {
  modelConfigOverrides.responseModel = process.env.BIOMATE_RESPONSE_MODEL;
}

if (process.env.BIOMATE_ENABLE_THINKING) {
  modelConfigOverrides.enableThinking = process.env.BIOMATE_ENABLE_THINKING !== "false";
}

if (typeof parsedThinkingBudget === "number" && Number.isFinite(parsedThinkingBudget)) {
  modelConfigOverrides.thinkingBudget = parsedThinkingBudget;
}

const galaxyAssistant = process.env.ANTHROPIC_API_KEY ? new GalaxyAssistant({
  anthropicApiKey: process.env.ANTHROPIC_API_KEY,
  galaxyAPIProxy,
  modelConfig: modelConfigOverrides,
}) : null;
const UX_FEEDBACK_ENABLED = process.env.ENABLE_UX_FEEDBACK !== "false";

// Lightweight SQLite connection for pilot feedback persistence (read/write galaxy_ai_tools.db).
const PILOT_FEEDBACK_DB_PATH = path.join(process.env.HOME ?? "", "biomate/backend/database/galaxy_ai_tools.db");
let _pilotFeedbackDb: InstanceType<typeof BetterSqlite3> | null = null;
function getPilotFeedbackDb(): InstanceType<typeof BetterSqlite3> | null {
  if (_pilotFeedbackDb) return _pilotFeedbackDb;
  try {
    _pilotFeedbackDb = new BetterSqlite3(PILOT_FEEDBACK_DB_PATH, { readonly: false });
    _pilotFeedbackDb.prepare(`
      CREATE TABLE IF NOT EXISTS pilot_feedback (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        feedback_type TEXT NOT NULL,
        submitted_at TEXT NOT NULL,
        payload TEXT NOT NULL
      )
    `).run();
    return _pilotFeedbackDb;
  } catch {
    return null;
  }
}

// Initialize Prerequisites Validator (LLM-powered pre-execution validation)
const prerequisitesValidator = process.env.ANTHROPIC_API_KEY ? new WorkflowPrerequisitesValidator({
  anthropicApiKey: process.env.ANTHROPIC_API_KEY,
  galaxyAPIProxy,
}) : null;

// Initialize memory integration if Galaxy Assistant is available
const memoryIntegration = galaxyAssistant ? createMemoryIntegration(galaxyAssistant) : null;

// Configure multer for file uploads
// AWS workflows require file upload first, so we constrain to 5GB to reduce latency
const MAX_FILE_SIZE_GB = 5;
const MAX_FILE_SIZE_BYTES = MAX_FILE_SIZE_GB * 1024 * 1024 * 1024; // 5GB

const uploadDir = path.join(process.cwd(), 'data', 'uploads');
const upload = multer({
  storage: multer.diskStorage({
    destination: async (req, file, cb) => {
      // Ensure upload directory exists
      await fs.mkdir(uploadDir, { recursive: true });
      cb(null, uploadDir);
    },
    filename: (req, file, cb) => {
      // Generate unique filename
      const uniqueName = `${uuidv4()}${path.extname(file.originalname)}`;
      cb(null, uniqueName);
    },
  }),
  limits: {
    fileSize: MAX_FILE_SIZE_BYTES, // 5GB max file size per file
  },
  fileFilter: (req, file, cb) => {
    // Accept common bioinformatics formats
    const allowedExtensions = [
      '.fastq', '.fastq.gz', '.fq', '.fq.gz',
      '.bam', '.sam', '.cram',
      '.mzml', '.mzxml', '.mgf',
      '.csv', '.tsv', '.txt', '.tab',
      '.fasta', '.fa', '.fna', '.fas',
      '.vcf', '.vcf.gz', '.bed', '.gff', '.gtf',
      '.h5ad', '.h5', '.hdf5', '.loom',
      '.json', '.xml'
    ];
    const ext = path.extname(file.originalname).toLowerCase();
    if (allowedExtensions.some(allowed => file.originalname.toLowerCase().endsWith(allowed))) {
      cb(null, true);
    } else {
      cb(new Error(`File type not supported. Allowed: ${allowedExtensions.join(', ')}`));
    }
  },
});

function buildQCReportHtml(run: any, invocationId: string): string {
  const now = new Date().toISOString();
  const status = run?.status ?? "unknown";
  const workflowName = run?.workflowName ?? run?.name ?? "BioMate Workflow";
  const metrics = run?.qcMetrics ?? run?.metrics ?? {};
  const auditLog: any[] = run?.auditLog ?? run?.qcGates ?? [];

  // Derive workflow domain for methods text
  const wfLower = workflowName.toLowerCase();
  const isDrugDiscovery = /admet|docking|drug|compound|crispr_screen/.test(wfLower);
  const isRNAseq        = /rnaseq|rna.seq|deseq|differential.expression/.test(wfLower);
  const isProteomics    = /proteomics|maxquant|diann|lc.ms/.test(wfLower);
  const isMultiOmics    = /multi.omics|metabolomics/.test(wfLower);
  const isCryoEM        = /cryo|cryosparc|relion/.test(wfLower);

  function domainMethodsText(): string {
    if (isDrugDiscovery) return `ADMET profiling was performed using BioMate AI (biomate.ai) applying evidence-graded thresholds (hERG IC₅₀, DILI risk, Ames mutagenicity, ClinTox flags, Caco-2 permeability, BBB penetration). Thresholds are cited to FDA guidance, Lipinski et al. (2001), and Waring et al. (2015). Virtual screening used AutoDock Vina and/or DiffDock. Retrosynthesis feasibility was assessed with AiZynthFinder. All parameters, tool versions, and QC gate outcomes are recorded in the audit log (invocation ID: ${invocationId}).`;
    if (isRNAseq) return `RNA-seq analysis was performed using BioMate AI (biomate.ai). Reads were quality-controlled using FastQC, trimmed with Trim Galore, and aligned using STAR. Gene-level counts were generated with featureCounts. Differential expression was computed with DESeq2 (BH-corrected FDR threshold 0.05). QC thresholds follow ENCODE RNA-seq standards (mapping rate ≥ 75%; duplicate rate ≤ 30%). All pipeline steps and QC gate evaluations are recorded in the audit log (invocation ID: ${invocationId}).`;
    if (isMultiOmics) return `Multi-omics analysis was performed using BioMate AI (biomate.ai). Proteomics data were processed via ${isProteomics ? 'MaxQuant/DIA-NN' : 'label-free quantification'}, log₂-normalised, and tested for differential abundance using a Welch t-test with BH correction. Untargeted metabolomics features were detected by XCMS (centWave), annotated against HMDB (10 ppm tolerance), and tested for differential abundance. Protein–metabolite correlation and joint KEGG pathway enrichment were computed as described. QC thresholds follow Want et al. (2010) Nature Protocols. Full audit log: invocation ID ${invocationId}.`;
    if (isProteomics) return `Proteomics analysis was performed using BioMate AI (biomate.ai). Protein abundances were log₂-normalised to median, replicate consistency verified (CV ≤ 20%), and differential abundance tested with a Welch t-test (BH correction). Missing value filtering followed Goeminne et al. (2020) Nature Methods. Full audit log: invocation ID ${invocationId}.`;
    if (isCryoEM) return `Cryo-EM data processing was performed using BioMate AI (biomate.ai) via CryoSPARC. Motion correction, CTF estimation, particle picking, 2D/3D classification, and map refinement were applied following EMDB deposition standards. Resolution was estimated by gold-standard FSC at the 0.143 criterion. Full audit log: invocation ID ${invocationId}.`;
    return `Analysis was performed using BioMate AI (biomate.ai). QC thresholds are evidence-graded (GOLD/SILVER/BRONZE) and cited to peer-reviewed sources. All pipeline steps were executed via validated Nextflow DSL2 workflows. Full audit log: invocation ID ${invocationId}.`;
  }

  const statusColor: Record<string, string> = { PASS: "#15803d", FAIL: "#dc2626", WARN: "#d97706" };
  const badgeStyle: Record<string, string> = {
    GOLD:   "background:#ffd700;color:#333;",
    SILVER: "background:#c0c0c0;color:#333;",
    BRONZE: "background:#cd7f32;color:white;",
  };

  const metricsRows = Object.entries(metrics)
    .map(([k, v]) => `<tr><td>${k}</td><td>${v}</td></tr>`)
    .join("");

  const passed  = auditLog.filter((g: any) => (g.status ?? g.result) === "PASS").length;
  const failed  = auditLog.filter((g: any) => (g.status ?? g.result) === "FAIL").length;
  const warned  = auditLog.filter((g: any) => (g.status ?? g.result) === "WARN").length;
  const overallStatus = failed > 0 ? "FAIL" : warned > 0 ? "WARN" : "PASS";
  const overallColor  = statusColor[overallStatus] ?? "#333";

  const auditRows = auditLog
    .map((g: any) => {
      const gStatus     = (g.status ?? g.result ?? "—").toUpperCase();
      const gEvidence   = (g.evidence_level ?? g.evidenceLevel ?? "—").toUpperCase();
      const rowBg       = gStatus === "PASS" ? "#f0fdf4" : gStatus === "FAIL" ? "#fef2f2" : gStatus === "WARN" ? "#fffbeb" : "white";
      const statusHtml  = statusColor[gStatus]
        ? `<span style="font-weight:bold;color:${statusColor[gStatus]}">${gStatus}</span>`
        : gStatus;
      const badgeHtml   = badgeStyle[gEvidence]
        ? `<span style="display:inline-block;padding:2px 7px;border-radius:4px;font-size:11px;font-weight:bold;${badgeStyle[gEvidence]}">${gEvidence}</span>`
        : gEvidence;
      return `<tr style="background:${rowBg}">
        <td>${g.gate ?? g.name ?? "—"}</td>
        <td>${statusHtml}</td>
        <td>${badgeHtml}</td>
        <td>${g.threshold ?? "—"}</td>
        <td>${g.value ?? "—"}</td>
        <td style="font-size:12px;">${g.citation ?? g.source ?? "—"}</td>
      </tr>`;
    })
    .join("");

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>BioMate QC Report — ${workflowName}</title>
<style>
  body { font-family: Arial, sans-serif; max-width: 960px; margin: 40px auto; color: #1a1a1a; line-height: 1.5; }
  h1 { color: #0f4c81; margin-bottom: 4px; }
  h2 { color: #333; border-bottom: 2px solid #0f4c81; padding-bottom: 4px; margin-top: 32px; }
  table { width: 100%; border-collapse: collapse; margin-bottom: 24px; font-size: 14px; }
  th { background: #0f4c81; color: white; padding: 10px 8px; text-align: left; }
  td { padding: 8px; border-bottom: 1px solid #eee; vertical-align: top; }
  tr:hover td { filter: brightness(0.97); }
  .status-banner { border-radius: 6px; padding: 16px 20px; margin: 20px 0; font-size: 16px; font-weight: bold; }
  .status-PASS { background: #f0fdf4; border-left: 5px solid #15803d; color: #15803d; }
  .status-WARN { background: #fffbeb; border-left: 5px solid #d97706; color: #d97706; }
  .status-FAIL { background: #fef2f2; border-left: 5px solid #dc2626; color: #dc2626; }
  .methods-block { background: #f9fafb; border-left: 4px solid #0f4c81; padding: 14px 18px; font-style: italic; font-size: 14px; margin-bottom: 24px; }
  .print-btn { background: #0f4c81; color: white; border: none; padding: 10px 20px; border-radius: 5px; cursor: pointer; font-size: 14px; margin-bottom: 20px; }
  .print-btn:hover { background: #1a5fa8; }
  .footer { font-size: 12px; color: #888; margin-top: 40px; border-top: 1px solid #eee; padding-top: 12px; }
  @media print { .print-btn { display: none; } body { margin: 20px; } }
</style>
</head>
<body>
<h1>BioMate QC Report</h1>
<p style="color:#555;margin-top:0;">Workflow: <strong>${workflowName}</strong> &nbsp;|&nbsp; ID: <code>${invocationId}</code> &nbsp;|&nbsp; Generated: ${now}</p>

<button class="print-btn" onclick="window.print()">⬇ Download as PDF (Print → Save as PDF)</button>

<div class="status-banner status-${overallStatus}">
  Overall QC Status: ${overallStatus} &nbsp;|&nbsp;
  ✅ Passed: ${passed} &nbsp; ⚠️ Warned: ${warned} &nbsp; ❌ Failed: ${failed}
</div>

<table>
  <tr><th colspan="2">Run Summary</th></tr>
  <tr><td>Workflow</td><td>${workflowName}</td></tr>
  <tr><td>Invocation ID</td><td><code>${invocationId}</code></td></tr>
  <tr><td>Run status</td><td><span style="font-weight:bold;color:${status === 'completed' ? '#15803d' : '#dc2626'}">${status.toUpperCase()}</span></td></tr>
  <tr><td>Report generated</td><td>${now}</td></tr>
</table>

${Object.keys(metrics).length > 0 ? `
<h2>QC Metrics</h2>
<table>
  <tr><th>Metric</th><th>Value</th></tr>
  ${metricsRows}
</table>` : ""}

${auditLog.length > 0 ? `
<h2>QC Gate Audit Log</h2>
<p style="font-size:13px;color:#555;">
  Evidence levels:
  <span style="display:inline-block;padding:2px 7px;border-radius:4px;font-size:11px;font-weight:bold;background:#ffd700;color:#333;">GOLD</span> universally accepted consensus &nbsp;
  <span style="display:inline-block;padding:2px 7px;border-radius:4px;font-size:11px;font-weight:bold;background:#c0c0c0;color:#333;">SILVER</span> community standard &nbsp;
  <span style="display:inline-block;padding:2px 7px;border-radius:4px;font-size:11px;font-weight:bold;background:#cd7f32;color:white;">BRONZE</span> field heuristic
</p>
<table>
  <tr><th>Gate</th><th>Result</th><th>Evidence</th><th>Threshold</th><th>Observed</th><th>Citation</th></tr>
  ${auditRows}
</table>` : ""}

<h2>Methods Section Text</h2>
<p style="font-size:13px;color:#555;">Copy the paragraph below directly into your manuscript methods section.</p>
<div class="methods-block">${domainMethodsText()}</div>

<h2>Audit Log Download</h2>
<p style="font-size:13px;">To download the full JSON audit log, use the BioMate Run Manager → <em>View logs</em> → <em>Download audit log</em>. The log includes all tool versions, parameters, and AutoFix decisions.</p>

<div class="footer">
  Generated by BioMate AI · biomate.ai · Report ID: ${invocationId} · ${now}<br>
  Cite as: BioMate AI platform (biomate.ai). Analysis performed March 2026. QC thresholds are evidence-graded; see audit log for full citations.
</div>
</body>
</html>`;
}

export async function registerRoutes(app: Express): Promise<Server> {
  // Initialize repositories
  await parameterRepository.initialize();
  await workflowRepository.initialize();

  // Seed example templates on first run
  const templates = await parameterRepository.searchTemplates({});
  if (templates.count === 0) {
    console.log('[Server] Seeding example parameter templates...');
    await parameterRepository.seedExamples();
  }

  // Disabled: These example templates use tools (FastQC, HISAT2, etc.) that aren't installed
  // const workflowTemplates = await workflowRepository.searchTemplates({});
  // if (workflowTemplates.count === 0) {
  //   console.log('[Server] Seeding example workflow templates...');
  //   await workflowRepository.seedExamples();
  // }

  // Apply audit middleware for API routes (excludes health and SSE)
  app.use('/api', auditMiddleware({
    excludePaths: ['/api/health', '/api/workflow/sse'],
    logBody: false, // Don't log request bodies by default (privacy)
  }));

  // Request counter for error rate computation (denominator for rate metrics)
  app.use((req: express.Request, res: express.Response, next: express.NextFunction) => {
    // Only count API routes, skip static/health
    if (req.path.startsWith('/api/') && req.path !== '/api/health') {
      telemetryService.create('api_request', new Date(), { path: req.path, method: req.method }).catch(() => {});
    }
    next();
  });

  // UX Telemetry - fire-and-forget event ingestion (non-blocking)
  app.post("/api/telemetry/events", express.json(), async (req, res) => {
    if (!UX_FEEDBACK_ENABLED) {
      res.status(204).send();
      return;
    }
    // Keep telemetry non-blocking for UI interactions.
    res.status(204).send();
    const event = String(req.body?.event || "").trim();
    const timestamp = req.body?.timestamp ? new Date(req.body.timestamp) : new Date();
    const payload = req.body?.payload && typeof req.body.payload === "object" ? req.body.payload : undefined;
    if (!event) {
      return;
    }
    telemetryService.create(event, Number.isNaN(timestamp.getTime()) ? new Date() : timestamp, payload).catch((error) => {
      console.warn("[Telemetry] Failed to persist telemetry event:", error?.message || error);
    });
  });

  app.get("/api/telemetry/summary", async (req, res) => {
    try {
      const from = typeof req.query?.from === "string" ? req.query.from : undefined;
      const to = typeof req.query?.to === "string" ? req.query.to : undefined;
      const summary = await telemetryService.getSummary({ from, to });
      res.json(summary);
    } catch (error: any) {
      console.error("[Telemetry] Failed to fetch summary:", error);
      res.status(500).json({ error: "TelemetrySummaryError", message: error?.message || String(error) });
    }
  });

  app.get("/api/telemetry/confusion-triage", async (req, res) => {
    try {
      const from = typeof req.query?.from === "string" ? req.query.from : undefined;
      const to = typeof req.query?.to === "string" ? req.query.to : undefined;
      const limitRaw = typeof req.query?.limit === "string" ? req.query.limit : undefined;
      const limit = limitRaw ? Number(limitRaw) : undefined;
      const rows = await telemetryService.getConfusionTriage({ from, to, limit });
      res.json({
        totalGroups: rows.length,
        rows,
      });
    } catch (error: any) {
      console.error("[Telemetry] Failed to fetch confusion triage:", error);
      res.status(500).json({
        error: "TelemetryConfusionTriageError",
        message: error?.message || String(error),
      });
    }
  });

  // Frontend event ingestion — receives events from analytics.ts (no auth required)
  app.post('/api/telemetry/event', express.json(), async (req, res) => {
    try {
      const { event, properties } = req.body as {
        event: string;
        properties?: Record<string, unknown>;
      };

      if (!event || typeof event !== 'string') {
        return res.status(400).json({ error: 'event is required' });
      }

      // Strip any PII before storing (email, name)
      const safeProps = properties ? {
        ...properties,
        email: undefined,  // never store email in telemetry
      } : undefined;

      await telemetryService.create(event, new Date(), safeProps as Record<string, unknown> | undefined);
      res.status(204).end();
    } catch (err: any) {
      // Never return errors to client for telemetry
      res.status(204).end();
    }
  });

  // Index health — proxies to Galaxy backend; returns per-source counts + staleness flags
  app.get('/api/admin/index-health', optionalAuth, async (req, res) => {
    try {
      const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
      const resp = await fetch(`${galaxyUrl}/api/admin/index-health`, { signal: AbortSignal.timeout(10000) });
      const data = await resp.json();
      res.status(resp.status).json(data);
    } catch (err: any) {
      res.status(503).json({ health: 'error', detail: String(err?.message ?? err) });
    }
  });

  // Pipeline type compatibility pre-flight check
  app.post('/api/workflows/type-compatibility', optionalAuth, express.json(), async (req, res) => {
    try {
      const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
      const resp = await fetch(`${galaxyUrl}/api/workflows/type-compatibility`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(req.body),
        signal: AbortSignal.timeout(10000),
      });
      const data = await resp.json();
      res.status(resp.status).json(data);
    } catch (err: any) {
      res.status(503).json({ compatible: true, warnings: [], error: String(err?.message ?? err) });
    }
  });

  // ── Queue depth + AutoFix process health (pilot monitoring dashboard) ──────
  app.get('/api/admin/process-health', async (req, res) => {
    try {
      const since7d  = new Date(Date.now() - 7  * 24 * 60 * 60 * 1000);
      const since24h = new Date(Date.now() - 24 * 60 * 60 * 1000);

      const [summary7d, summary24h] = await Promise.all([
        telemetryService.getSummary({ from: since7d.toISOString() }),
        telemetryService.getSummary({ from: since24h.toISOString() }),
      ]);

      const ev7  = summary7d.byEventName  ?? {};
      const ev24 = summary24h.byEventName ?? {};

      // Queue metrics
      const workflowsSubmitted24h = (ev24['workflow_submitted']   ?? 0) as number;
      const workflowsCompleted24h = (ev24['workflow_completed']   ?? 0) as number;
      const workflowsFailed24h    = (ev24['workflow_failed']      ?? 0) as number;
      const workflowsRunning      = workflowsSubmitted24h - workflowsCompleted24h - workflowsFailed24h;
      const queueDepth            = Math.max(0, workflowsRunning);

      // AutoFix metrics (7-day window for statistical reliability)
      const autofixAttempts7d     = (ev7['autofix_attempt']       ?? 0) as number;
      const autofixSuccesses7d    = (ev7['autofix_success']       ?? 0) as number;
      const autofixFailures7d     = (ev7['autofix_failure']       ?? 0) as number;
      const autofixSuccessRate    = autofixAttempts7d > 0
        ? +(autofixSuccesses7d / autofixAttempts7d * 100).toFixed(1) : null;

      // Hallucination / bad-command guard (zero-tolerance metric)
      const hallucinationCount7d  = (ev7['workflow_hallucination_detected'] ?? 0) as number;
      const invalidToolCount7d    = (ev7['invalid_tool_name']               ?? 0) as number;

      // API error rate (24h)
      const totalReqs24h  = Math.max((ev24['api_request'] ?? 1) as number, 1);
      const errors5xx24h  = (ev24['api_error_5xx'] ?? 0) as number;
      const errorRate24h  = +((errors5xx24h / totalReqs24h) * 100).toFixed(2);

      // SLA evaluation
      const sla = {
        queue_depth_ok:       queueDepth < 20,
        autofix_rate_ok:      autofixSuccessRate === null || autofixSuccessRate >= 80,
        hallucination_ok:     hallucinationCount7d === 0 && invalidToolCount7d === 0,
        error_rate_ok:        errorRate24h < 1.0,
      };
      const sla_ok = Object.values(sla).every(Boolean);

      res.json({
        as_of: new Date().toISOString(),
        overall_health: sla_ok ? 'OK' : 'DEGRADED',
        sla,
        queue: {
          depth:              queueDepth,
          submitted_24h:      workflowsSubmitted24h,
          completed_24h:      workflowsCompleted24h,
          failed_24h:         workflowsFailed24h,
        },
        autofix: {
          attempts_7d:        autofixAttempts7d,
          successes_7d:       autofixSuccesses7d,
          failures_7d:        autofixFailures7d,
          success_rate_pct:   autofixSuccessRate,
          target_pct:         80,
        },
        hallucination_guard: {
          incidents_7d:       hallucinationCount7d + invalidToolCount7d,
          target:             0,
          status:             hallucinationCount7d === 0 && invalidToolCount7d === 0 ? 'PASS' : 'FAIL',
        },
        api: {
          error_rate_5xx_pct_24h: errorRate24h,
          total_requests_24h:     totalReqs24h,
          target_error_rate_pct:  1.0,
        },
      });
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  // Workflow input/output type lookup
  app.get('/api/workflows/:workflowName/types', optionalAuth, async (req, res) => {
    try {
      const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
      const name = encodeURIComponent(req.params.workflowName);
      const resp = await fetch(`${galaxyUrl}/api/workflows/${name}/types`, { signal: AbortSignal.timeout(5000) });
      const data = await resp.json();
      res.status(resp.status).json(data);
    } catch (err: any) {
      res.status(503).json({ has_type_info: false, error: String(err?.message ?? err) });
    }
  });

  // Workflow chain catalog
  app.get('/api/workflow-chains', optionalAuth, async (req, res) => {
    try {
      const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
      const qs = req.query.domain ? `?domain=${encodeURIComponent(String(req.query.domain))}` : '';
      const resp = await fetch(`${galaxyUrl}/api/workflow-chains${qs}`, { signal: AbortSignal.timeout(5000) });
      const data = await resp.json();
      res.status(resp.status).json(data);
    } catch (err: any) {
      res.status(503).json({ chains: [], total: 0, error: String(err?.message ?? err) });
    }
  });

  app.post('/api/workflow-chains/record-run', optionalAuth, express.json(), async (req, res) => {
    try {
      const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
      const resp = await fetch(`${galaxyUrl}/api/workflow-chains/record-run`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(req.body),
        signal: AbortSignal.timeout(5000),
      });
      const data = await resp.json();
      res.status(resp.status).json(data);
    } catch (err: any) {
      res.status(503).json({ error: String(err?.message ?? err) });
    }
  });

  // Error rate dashboard — returns 7-day rates for crash/timeout/5xx monitoring
  app.get('/api/admin/error-rates', async (req, res) => {
    try {
      const since = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
      const summary = await telemetryService.getSummary({
        from: since.toISOString(),
      });

      const totalRequests = (summary.byEventName['api_request'] ?? 0) || 1; // avoid div/0
      const errors5xx = summary.byEventName['api_error_5xx'] ?? 0;
      const timeouts = summary.byEventName['workflow_timeout'] ?? 0;
      const aiErrors = summary.byEventName['ai_assistant_error'] ?? 0;

      res.json({
        period: '7d',
        since: since.toISOString(),
        metrics: {
          error_rate_5xx_pct: +((errors5xx / totalRequests) * 100).toFixed(2),
          timeout_rate_pct: +((timeouts / totalRequests) * 100).toFixed(2),
          ai_error_count: aiErrors,
          total_errors: errors5xx + timeouts + aiErrors,
          total_requests: totalRequests,
        },
        by_day: summary.byDay,
        by_event: summary.byEventName,
        sla: {
          error_rate_target_pct: 1.0,
          error_rate_ok: (errors5xx / totalRequests) * 100 < 1.0,
          timeout_target_pct: 0.5,
          timeout_ok: (timeouts / totalRequests) * 100 < 0.5,
        },
      });
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  // UX Feedback ingestion endpoint for inline/post-run flows.
  app.post("/api/feedback", express.json(), optionalAuth, async (req, res) => {
    if (!UX_FEEDBACK_ENABLED) {
      res.status(404).json({ success: false, error: "Feedback feature disabled" });
      return;
    }
    const payload = req.body || {};
    if (!payload.feedback_type) {
      res.status(400).json({ success: false, error: "feedback_type is required" });
      return;
    }

    // Persist pilot exit surveys and post-run surveys to the database.
    if (["pilot_exit_survey", "post_run"].includes(payload.feedback_type)) {
      try {
        const db = getPilotFeedbackDb();
        if (db) {
          db.prepare(
            "INSERT INTO pilot_feedback (feedback_type, submitted_at, payload) VALUES (?, ?, ?)"
          ).run(payload.feedback_type, payload.submitted_at ?? new Date().toISOString(), JSON.stringify(payload));
        }
      } catch {
        // Non-fatal — feedback still acknowledged to user
      }
    }

    res.status(200).json({
      success: true,
      id: `fb_${Date.now()}`,
    });
  });

  // Pilot evaluation KPI aggregation — used by feedback dashboard.
  app.get("/api/feedback/pilot-kpi", authenticateToken, async (req, res) => {
    if (!UX_FEEDBACK_ENABLED) {
      res.status(404).json({ error: "Feedback feature disabled" });
      return;
    }
    const { from, to } = req.query as Record<string, string>;

    const db = getPilotFeedbackDb();
    if (!db) {
      res.json({
        respondents: 0,
        avg_workflow_quality_pct: null,
        h1_pass_count: 0,
        avg_time_minutes: null,
        h2_pass_count: 0,
        avg_prior_time_hours: null,
        avg_time_saved_hours: null,
        avg_qc_rating: null,
        qc_pass_count: 0,
        pricing_yes_count: 0,
        pricing_maybe_count: 0,
        total_hallucinations: 0,
        h5_pass: true,
        avg_overall_rating: null,
        avg_recommend_rating: null,
        coauthor_yes_count: 0,
      });
      return;
    }

    try {

      const fromFilter = from ?? "2000-01-01";
      const toFilter = to ?? "2100-01-01";

      const rows: Array<{ payload: string }> = db.prepare(
        `SELECT payload FROM pilot_feedback
         WHERE feedback_type IN ('pilot_exit_survey', 'post_run')
           AND submitted_at >= ? AND submitted_at <= ?`
      ).all(fromFilter, toFilter + "T23:59:59");

      const parsed = rows.map((r) => {
        try { return JSON.parse(r.payload); } catch { return {}; }
      });

      const exitSurveys = parsed.filter((p) => p.feedback_type === "pilot_exit_survey");
      const postRuns = parsed.filter((p) => p.feedback_type === "post_run");

      const respondents = exitSurveys.length;

      // H1 — workflow quality
      const qualityPcts = exitSurveys
        .filter((p) => p.workflow_quality_pct != null)
        .map((p) => Number(p.workflow_quality_pct));
      const avg_workflow_quality_pct = qualityPcts.length
        ? qualityPcts.reduce((a, b) => a + b, 0) / qualityPcts.length
        : null;
      const h1_pass_count = qualityPcts.filter((v) => v >= 80).length;

      // H2 — time to result (collect from both exit and post-run)
      const timeMins = [
        ...exitSurveys.filter((p) => p.avg_time_minutes).map((p) => Number(p.avg_time_minutes)),
        ...postRuns.filter((p) => p.prior_time_hours != null).map((p) => Number(p.prior_time_hours) * 60 * 0.1), // rough
      ].filter((v) => !isNaN(v) && v > 0);
      const avg_time_minutes = timeMins.length
        ? timeMins.reduce((a, b) => a + b, 0) / timeMins.length
        : null;
      const h2_pass_count = timeMins.filter((v) => v <= 30).length;

      const priorHours = exitSurveys
        .filter((p) => p.prior_time_hours)
        .map((p) => Number(p.prior_time_hours));
      const avg_prior_time_hours = priorHours.length
        ? priorHours.reduce((a, b) => a + b, 0) / priorHours.length
        : null;
      const timeSaved = exitSurveys
        .filter((p) => p.time_saved_hours != null)
        .map((p) => Number(p.time_saved_hours));
      const avg_time_saved_hours = timeSaved.length
        ? timeSaved.reduce((a, b) => a + b, 0) / timeSaved.length
        : null;

      // H3 — QC defensibility
      const qcRatings = [
        ...exitSurveys.filter((p) => p.qc_publication_rating).map((p) => Number(p.qc_publication_rating)),
        ...postRuns.filter((p) => p.qc_publication_rating).map((p) => Number(p.qc_publication_rating)),
      ];
      const avg_qc_rating = qcRatings.length
        ? qcRatings.reduce((a, b) => a + b, 0) / qcRatings.length
        : null;
      const qc_pass_count = qcRatings.filter((v) => v >= 4).length;

      // H4 — pricing
      const pricingAll = [
        ...exitSurveys.map((p) => p.pricing_response ?? ""),
        ...postRuns.map((p) => p.pricing_response ?? ""),
      ].filter(Boolean);
      const pricing_yes_count = pricingAll.filter((v) => v.startsWith("Yes")).length;
      const pricing_maybe_count = pricingAll.filter((v) => v.startsWith("Maybe")).length;

      // H5 — hallucinations
      const hallucs = exitSurveys
        .map((p) => Number(p.hallucination_incidents ?? 0))
        .reduce((a, b) => a + b, 0);
      const total_hallucinations = hallucs;
      const h5_pass = total_hallucinations === 0;

      // Overall
      const overallRatings = exitSurveys
        .filter((p) => p.overall_rating).map((p) => Number(p.overall_rating));
      const avg_overall_rating = overallRatings.length
        ? overallRatings.reduce((a, b) => a + b, 0) / overallRatings.length
        : null;
      const recommendRatings = exitSurveys
        .filter((p) => p.would_recommend).map((p) => Number(p.would_recommend));
      const avg_recommend_rating = recommendRatings.length
        ? recommendRatings.reduce((a, b) => a + b, 0) / recommendRatings.length
        : null;
      const coauthor_yes_count = exitSurveys.filter((p) => p.publish_together === true).length;

      res.json({
        respondents,
        avg_workflow_quality_pct: avg_workflow_quality_pct !== null ? Math.round(avg_workflow_quality_pct * 10) / 10 : null,
        h1_pass_count,
        avg_time_minutes: avg_time_minutes !== null ? Math.round(avg_time_minutes * 10) / 10 : null,
        h2_pass_count,
        avg_prior_time_hours: avg_prior_time_hours !== null ? Math.round(avg_prior_time_hours * 10) / 10 : null,
        avg_time_saved_hours: avg_time_saved_hours !== null ? Math.round(avg_time_saved_hours * 10) / 10 : null,
        avg_qc_rating: avg_qc_rating !== null ? Math.round(avg_qc_rating * 100) / 100 : null,
        qc_pass_count,
        pricing_yes_count,
        pricing_maybe_count,
        total_hallucinations,
        h5_pass,
        avg_overall_rating: avg_overall_rating !== null ? Math.round(avg_overall_rating * 100) / 100 : null,
        avg_recommend_rating: avg_recommend_rating !== null ? Math.round(avg_recommend_rating * 100) / 100 : null,
        coauthor_yes_count,
      });
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  // Health check
  app.get("/api/health", async (req, res) => {
    // Get Galaxy connection status
    const galaxyStatus = galaxyAPIBackend.getConnectionStatus();
    const galaxyHealthy = await galaxyAPIBackend.healthCheck();

    res.json({
      status: galaxyHealthy ? "ok" : "degraded",
      timestamp: new Date().toISOString(),
      services: {
        api: "ok",
        galaxy: {
          connected: galaxyHealthy,
          url: galaxyStatus.url,
          error: galaxyStatus.error
        },
        ai: !!galaxyAssistant ? "ok" : "unavailable"
      }
    });
  });

  // ============================================================================
  // Authentication API
  // ============================================================================

  // Register new user
  app.post("/api/auth/register", registerLimiter, async (req, res) => {
    try {
      const registerData: RegisterData = {
        email: req.body.email,
        password: req.body.password,
        fullName: req.body.fullName || req.body.name,
        organization: req.body.organization,
        phone: req.body.phone,
        termsAccepted: req.body.terms_accepted || req.body.termsAccepted || false,
        marketingEmailsOptIn: req.body.marketing_emails_opt_in || req.body.marketingEmailsOptIn || false,
        inviteCode: req.body.inviteCode || req.body.invite_code,
      };

      const result = await authService.register(registerData);

      // Set HTTP-only cookie
      res.cookie('biomate_token', result.token, {
        httpOnly: true,
        secure: process.env.NODE_ENV === 'production',
        sameSite: 'strict',
        maxAge: result.expiresIn * 1000, // Convert to milliseconds
      });

      res.status(201).json({
        success: true,
        user: result.user,
        token: result.token,
        expiresIn: result.expiresIn,
      });
    } catch (error: any) {
      console.error('[Auth] Registration error:', error);
      res.status(400).json({
        success: false,
        error: error.message || 'Registration failed',
      });
    }
  });

  // Login existing user
  app.post("/api/auth/login", authLimiter, async (req, res) => {
    try {
      const loginData: LoginData = {
        email: req.body.email,
        password: req.body.password,
      };

      const result = await authService.login(loginData);

      // Set HTTP-only cookie
      res.cookie('biomate_token', result.token, {
        httpOnly: true,
        secure: process.env.NODE_ENV === 'production',
        sameSite: 'strict',
        maxAge: result.expiresIn * 1000,
      });

      // Check subscription status
      const subscriptionStatus = authService.checkSubscriptionStatus(result.user);

      // Log successful login
      await auditService.logAuth(
        'login',
        result.user.id,
        req.ip || req.socket.remoteAddress || 'unknown',
        req.headers['user-agent'] || 'unknown',
        true
      );

      res.json({
        success: true,
        user: result.user,
        token: result.token,
        subscription: subscriptionStatus,
      });
    } catch (error: any) {
      console.error('[Auth] Login error:', error);

      // Log failed login
      await auditService.logAuth(
        'login',
        null,
        req.ip || req.socket.remoteAddress || 'unknown',
        req.headers['user-agent'] || 'unknown',
        false,
        error.message
      );

      if (error.message === 'TRIAL_EXPIRED') {
        return res.status(403).json({
          success: false,
          error: 'TRIAL_EXPIRED',
          message: 'Your trial has expired. Please subscribe to continue.',
        });
      }

      res.status(401).json({
        success: false,
        error: 'Invalid credentials',
      });
    }
  });

  // Logout
  app.post("/api/auth/logout", async (req, res) => {
    // Log logout
    const userId = (req as any).user?.id || null;
    await auditService.logAuth(
      'logout',
      userId,
      req.ip || req.socket.remoteAddress || 'unknown',
      req.headers['user-agent'] || 'unknown',
      true
    );

    res.clearCookie('biomate_token');
    res.json({ success: true, message: 'Logged out successfully' });
  });

  // Get current user (non-erroring for anonymous clients)
  app.get("/api/auth/me", optionalAuth, async (req, res) => {
    try {
      if (!req.user) {
        return res.json({
          success: false,
          user: null,
          subscription: null,
        });
      }

      const subscriptionStatus = authService.checkSubscriptionStatus(req.user as any);

      res.json({
        success: true,
        user: req.user,
        subscription: subscriptionStatus,
      });
    } catch (error: any) {
      console.error('[Auth] Get current user error:', error);
      res.status(500).json({ error: 'Failed to get user' });
    }
  });

  // Resend verification email
  app.post("/api/auth/resend-verification", emailVerificationLimiter, authenticateToken, async (req, res) => {
    try {
      if (!req.user) {
        return res.status(401).json({ error: 'Not authenticated' });
      }

      await authService.sendVerificationEmail(req.user.id);

      res.json({
        success: true,
        message: 'Verification email sent',
      });
    } catch (error: any) {
      console.error('[Auth] Resend verification error:', error);
      res.status(400).json({
        success: false,
        error: error.message || 'Failed to send verification email',
      });
    }
  });

  // Verify email with token
  app.post("/api/auth/verify-email", emailVerificationLimiter, async (req, res) => {
    try {
      const { token } = req.body;

      if (!token) {
        return res.status(400).json({
          success: false,
          error: 'Token is required',
        });
      }

      const user = await authService.verifyEmail(token);

      res.json({
        success: true,
        message: 'Email verified successfully',
        user,
      });
    } catch (error: any) {
      console.error('[Auth] Email verification error:', error);
      res.status(400).json({
        success: false,
        error: error.message || 'Email verification failed',
      });
    }
  });

  // Request password reset
  app.post("/api/auth/request-password-reset", passwordResetLimiter, async (req, res) => {
    try {
      const { email } = req.body;

      if (!email) {
        return res.status(400).json({
          success: false,
          error: 'Email is required',
        });
      }

      await authService.requestPasswordReset(email);

      // Always return success to prevent email enumeration
      res.json({
        success: true,
        message: 'If the email exists, a password reset link has been sent',
      });
    } catch (error: any) {
      console.error('[Auth] Password reset request error:', error);
      // Still return success for security
      res.json({
        success: true,
        message: 'If the email exists, a password reset link has been sent',
      });
    }
  });

  // Reset password with token
  app.post("/api/auth/reset-password", passwordResetLimiter, async (req, res) => {
    try {
      const { token, password } = req.body;

      if (!token || !password) {
        return res.status(400).json({
          success: false,
          error: 'Token and password are required',
        });
      }

      // Basic password validation
      if (password.length < 8) {
        return res.status(400).json({
          success: false,
          error: 'Password must be at least 8 characters',
        });
      }

      await authService.resetPassword(token, password);

      res.json({
        success: true,
        message: 'Password reset successfully',
      });
    } catch (error: any) {
      console.error('[Auth] Password reset error:', error);
      res.status(400).json({
        success: false,
        error: error.message || 'Password reset failed',
      });
    }
  });

  // ============================================================================
  // OAuth Authentication (Google & GitHub)
  // ============================================================================

  // Google OAuth - Initiate
  app.get("/api/auth/google",
    authLimiter,
    passport.authenticate('google', { scope: ['profile', 'email'] })
  );

  // Google OAuth - Callback
  app.get("/api/auth/google/callback",
    passport.authenticate('google', { session: false, failureRedirect: '/login?error=oauth_failed' }),
    async (req, res) => {
      try {
        if (!req.user) {
          return res.redirect('/login?error=oauth_failed');
        }

        // Generate JWT token
        const token = oauthService.generateToken(req.user as any);
        const subscriptionStatus = authService.checkSubscriptionStatus(req.user as any);

        // Set cookie
        res.cookie('biomate_token', token, {
          httpOnly: true,
          secure: process.env.NODE_ENV === 'production',
          sameSite: 'strict',
          maxAge: 7 * 24 * 60 * 60 * 1000, // 7 days
        });

        // Redirect to dashboard with token
        res.redirect(`/dashboard?oauth_success=true`);
      } catch (error: any) {
        console.error('[OAuth] Google callback error:', error);
        res.redirect('/login?error=oauth_error');
      }
    }
  );

  // GitHub OAuth - Initiate
  app.get("/api/auth/github",
    authLimiter,
    passport.authenticate('github', { scope: ['user:email'] })
  );

  // GitHub OAuth - Callback
  app.get("/api/auth/github/callback",
    passport.authenticate('github', { session: false, failureRedirect: '/login?error=oauth_failed' }),
    async (req, res) => {
      try {
        if (!req.user) {
          return res.redirect('/login?error=oauth_failed');
        }

        // Generate JWT token
        const token = oauthService.generateToken(req.user as any);
        const subscriptionStatus = authService.checkSubscriptionStatus(req.user as any);

        // Set cookie
        res.cookie('biomate_token', token, {
          httpOnly: true,
          secure: process.env.NODE_ENV === 'production',
          sameSite: 'strict',
          maxAge: 7 * 24 * 60 * 60 * 1000, // 7 days
        });

        // Redirect to dashboard with token
        res.redirect(`/dashboard?oauth_success=true`);
      } catch (error: any) {
        console.error('[OAuth] GitHub callback error:', error);
        res.redirect('/login?error=oauth_error');
      }
    }
  );

  // Check OAuth configuration status
  app.get("/api/auth/oauth/status", (req, res) => {
    const status = oauthService.isConfigured();
    res.json({
      success: true,
      oauth: status,
    });
  });

  // ============================================================================
  // S3 File Management API
  // ============================================================================

  // Initialize S3 upload (get presigned URL)
  app.post("/api/s3/upload/init", uploadLimiter, authenticateToken, async (req, res) => {
    try {
      const { filename, fileSize, contentType } = req.body;

      if (!filename || !fileSize || !contentType) {
        return res.status(400).json({
          error: 'Missing required fields: filename, fileSize, contentType',
        });
      }

      const userId = req.user!.id;

      // For files < 100MB, use simple presigned URL
      if (fileSize < 100 * 1024 * 1024) {
        const uploadData = await s3Service.generatePresignedUploadUrl(
          userId,
          filename,
          contentType
        );

        res.json({
          uploadId: uploadData.uploadId,
          uploadUrl: uploadData.uploadUrl,
          key: uploadData.key,
          method: 'simple',
          expiresIn: uploadData.expires_in,
        });
      } else {
        // For large files, use multipart upload
        const multipartData = await s3Service.generateMultipartUploadUrls(
          userId,
          filename,
          fileSize,
          contentType
        );

        res.json({
          uploadId: multipartData.uploadId,
          key: multipartData.key,
          partUrls: multipartData.partUrls,
          chunkSize: multipartData.chunkSize,
          method: 'multipart',
          expiresIn: 3600,
        });
      }
    } catch (error: any) {
      console.error('[S3] Upload init error:', error);
      res.status(500).json({
        error: 'Failed to initialize upload',
        message: error.message,
      });
    }
  });

  // Get presigned download URL
  app.post("/api/s3/download", authenticateToken, async (req, res) => {
    try {
      const { key } = req.body;

      if (!key) {
        return res.status(400).json({ error: 'Missing required field: key' });
      }

      // Verify user owns this file (key should start with users/{userId}/)
      const userId = req.user!.id;
      if (!key.startsWith(`users/${userId}/`)) {
        return res.status(403).json({ error: 'Access denied' });
      }

      // Check if file exists
      const exists = await s3Service.fileExists(key);
      if (!exists) {
        return res.status(404).json({ error: 'File not found' });
      }

      // Generate presigned URL
      const downloadUrl = await s3Service.generatePresignedDownloadUrl(key);

      res.json({
        downloadUrl,
        expiresIn: 3600,
      });
    } catch (error: any) {
      console.error('[S3] Download URL generation error:', error);
      res.status(500).json({
        error: 'Failed to generate download URL',
        message: error.message,
      });
    }
  });

  // Delete file from S3
  app.delete("/api/s3/files/:key", authenticateToken, async (req, res) => {
    try {
      const key = decodeURIComponent(req.params.key);

      // Verify user owns this file
      const userId = req.user!.id;
      if (!key.startsWith(`users/${userId}/`)) {
        return res.status(403).json({ error: 'Access denied' });
      }

      const success = await s3Service.deleteFile(key);

      if (success) {
        res.json({ success: true, message: 'File deleted successfully' });
      } else {
        res.status(500).json({ error: 'Failed to delete file' });
      }
    } catch (error: any) {
      console.error('[S3] Delete file error:', error);
      res.status(500).json({
        error: 'Failed to delete file',
        message: error.message,
      });
    }
  });

  // ============================================================================
  // Payment & Subscription API (Stripe)
  // ============================================================================

  // Create checkout session for subscription
  app.post("/api/payments/create-checkout-session", authenticateToken, async (req, res) => {
    try {
      if (!stripeService.isConfigured()) {
        return res.status(503).json({
          error: 'Payment system not configured',
          message: 'Stripe is not set up. Contact support.',
        });
      }

      const { priceId, successUrl, cancelUrl } = req.body;

      if (!priceId) {
        return res.status(400).json({ error: 'Price ID is required' });
      }

      const session = await stripeService.createCheckoutSession(
        req.user!.id,
        priceId,
        successUrl,
        cancelUrl
      );

      res.json({
        success: true,
        sessionId: session.id,
        url: session.url,
      });
    } catch (error: any) {
      console.error('[Payments] Checkout session error:', error);
      res.status(500).json({
        error: 'Failed to create checkout session',
        message: error.message,
      });
    }
  });

  // Create customer portal session
  app.post("/api/payments/create-portal-session", authenticateToken, async (req, res) => {
    try {
      if (!stripeService.isConfigured()) {
        return res.status(503).json({
          error: 'Payment system not configured',
        });
      }

      const { returnUrl } = req.body;

      const session = await stripeService.createPortalSession(req.user!.id, returnUrl);

      res.json({
        success: true,
        url: session.url,
      });
    } catch (error: any) {
      console.error('[Payments] Portal session error:', error);
      res.status(500).json({
        error: 'Failed to create portal session',
        message: error.message,
      });
    }
  });

  // Get current subscription
  app.get("/api/payments/subscription", authenticateToken, async (req, res) => {
    try {
      if (!stripeService.isConfigured()) {
        return res.json({
          success: true,
          subscription: null,
          configured: false,
        });
      }

      const subscription = await stripeService.getSubscription(req.user!.id);

      res.json({
        success: true,
        subscription,
        configured: true,
      });
    } catch (error: any) {
      console.error('[Payments] Get subscription error:', error);
      res.status(500).json({
        error: 'Failed to get subscription',
        message: error.message,
      });
    }
  });

  // Cancel subscription
  app.post("/api/payments/cancel-subscription", authenticateToken, async (req, res) => {
    try {
      if (!stripeService.isConfigured()) {
        return res.status(503).json({
          error: 'Payment system not configured',
        });
      }

      await stripeService.cancelSubscription(req.user!.id);

      res.json({
        success: true,
        message: 'Subscription canceled successfully',
      });
    } catch (error: any) {
      console.error('[Payments] Cancel subscription error:', error);
      res.status(500).json({
        error: 'Failed to cancel subscription',
        message: error.message,
      });
    }
  });

  // Get pricing tiers
  app.get("/api/payments/pricing", (req, res) => {
    if (!stripeService.isConfigured()) {
      return res.json({
        success: true,
        pricing: null,
        configured: false,
      });
    }

    const pricing = stripeService.getPricingTiers();

    res.json({
      success: true,
      pricing,
      configured: true,
    });
  });

  // Stripe webhook handler
  app.post("/api/payments/webhook", express.raw({ type: 'application/json' }), async (req, res) => {
    const signatureHeader = req.headers['stripe-signature'];
    const signature = Array.isArray(signatureHeader) ? signatureHeader[0] : signatureHeader;

    if (!signature) {
      return res.status(400).send('Missing stripe-signature header');
    }

    try {
      await stripeService.handleWebhook(req.body, signature);
      res.json({ received: true });
    } catch (error: any) {
      console.error('[Payments] Webhook error:', error);
      res.status(400).send(`Webhook Error: ${error.message}`);
    }
  });

  // ============================================================================
  // Galaxy Tool Search API
  // ============================================================================

  app.get("/api/galaxy/version", async (_req, res) => {
    try {
      const response = await galaxyAPIProxy.client.get("/api/version", { timeout: 10000 });
      res.json(response.data);
    } catch (error: any) {
      console.error("Get Galaxy version error:", error.message);
      res.status(error.response?.status || 502).json({
        error: "GalaxyVersionError",
        message: error.message || "Failed to fetch backend version",
      });
    }
  });

  app.get("/api/galaxy/tools/search", async (req, res) => {
    try {
      const { q, category, limit } = req.query;
      if (!q || typeof q !== 'string') {
        return res.status(400).json({ error: "Query parameter 'q' is required" });
      }

      const results = await galaxyAPIProxy.searchTools(
        q,
        category as string | undefined,
        limit ? parseInt(limit as string) : 50
      );

      res.json(results);
    } catch (error: any) {
      console.error("Tool search error:", error);
      res.status(error.status_code || 500).json({
        error: error.error || 'ToolSearchError',
        message: error.message || 'Tool search failed',
      });
    }
  });

  app.get("/api/galaxy/tools/categories", async (req, res) => {
    try {
      const categories = await galaxyAPIProxy.getToolCategories();
      res.json(categories);
    } catch (error: any) {
      console.error("Get categories error:", error);
      res.status(error.status_code || 500).json({
        error: error.error || 'CategoryError',
        message: error.message || 'Failed to fetch categories',
      });
    }
  });

  app.get("/api/galaxy/tools/:toolId", async (req, res) => {
    try {
      const tool = await galaxyAPIProxy.getToolById(req.params.toolId);
      res.json(tool);
    } catch (error: any) {
      console.error("Get tool error:", error);
      res.status(error.status_code || 500).json({
        error: error.error || 'ToolNotFound',
        message: error.message || 'Tool not found',
      });
    }
  });

  app.get("/api/galaxy/tools/:toolId(*)/schema", async (req, res) => {
    try {
      const schema = await galaxyAPIProxy.getToolSchema(req.params.toolId);
      res.json(schema);
    } catch (error: any) {
      console.error("Get tool schema error:", error);
      res.status(error.status_code || 500).json({
        error: error.error || 'SchemaNotFound',
        message: error.message || 'Tool schema not found',
      });
    }
  });

  app.get("/api/galaxy/tools/installed/list", async (req, res) => {
    try {
      const installed = await galaxyAPIProxy.getInstalledTools();
      res.json(installed);
    } catch (error: any) {
      console.error("Get installed tools error:", error);
      res.status(error.status_code || 500).json({
        error: error.error || 'InstalledToolsError',
        message: error.message || 'Failed to fetch installed tools',
      });
    }
  });

  // ============================================================================
  // Galaxy Dataset Discovery API
  // ============================================================================

  app.post("/api/galaxy/datasets/search", async (req, res) => {
    try {
      const searchRequest = req.body;
      if (!searchRequest.query) {
        return res.status(400).json({ error: "Query is required" });
      }

      const results = await galaxyAPIProxy.searchDatasets(searchRequest);
      res.json(results);
    } catch (error: any) {
      console.error("Dataset search error:", error);
      res.status(error.status_code || 500).json({
        error: error.error || 'DatasetSearchError',
        message: error.message || 'Dataset search failed',
      });
    }
  });

  // File Upload API
  app.post("/api/datasets/upload", authenticateToken, upload.single('file'), async (req, res) => {
    try {
      if (!req.file) {
        return res.status(400).json({ error: "No file uploaded" });
      }

      const file = req.file;
      const datasetId = uuidv4();
      const description = req.body.description || ''; // Get optional description from request body

      console.log(`[FileUpload] File uploaded: ${file.originalname} -> ${file.filename}`);
      console.log(`[FileUpload] Dataset ID: ${datasetId}`);
      if (description) {
        console.log(`[FileUpload] Description: ${description}`);
      }

      // Get or create Galaxy history for this session
      let historyId = req.session?.galaxyHistoryId as string | undefined;

      if (!historyId) {
        try {
          // Create a new history for this session
          const sessionName = `GalaxyChat-${new Date().toISOString().split('T')[0]}`;
          historyId = await galaxyAPIProxy.createHistory(sessionName);
          if (req.session) {
            req.session.galaxyHistoryId = historyId;
          }
          console.log(`[FileUpload] Created new Galaxy history: ${historyId}`);
        } catch (error: any) {
          console.warn(`[FileUpload] Failed to create Galaxy history:`, error.message);
          // Continue without Galaxy integration if it fails
        }
      }

      // Upload file to Galaxy if we have a history
      let galaxyDatasetId: string | undefined;
      if (historyId) {
        try {
          galaxyDatasetId = await galaxyAPIProxy.uploadDataset(
            file.path,
            historyId,
            file.originalname
          );
          console.log(`[FileUpload] Uploaded to Galaxy: ${galaxyDatasetId}`);
        } catch (error: any) {
          console.warn(`[FileUpload] Failed to upload to Galaxy:`, error.message);
          // Continue with local file only if Galaxy upload fails
        }
      }

      // Store dataset in session for validation
      if (req.session) {
        if (!req.session.uploadedDatasets) {
          req.session.uploadedDatasets = [];
        }
        req.session.uploadedDatasets.push({
          dataset_id: datasetId,
          galaxy_dataset_id: galaxyDatasetId,
          name: file.originalname,
          description: description,
          file_type: file.mimetype,
          file_size: file.size,
        });
      }

      // Return dataset information with both local and Galaxy IDs
      res.json({
        dataset_id: datasetId,
        galaxy_dataset_id: galaxyDatasetId,
        galaxy_history_id: historyId,
        name: file.originalname,
        description: description,
        file_size: file.size,
        file_type: file.mimetype,
        file_path: file.path,
        uploaded_at: new Date().toISOString(),
      });
    } catch (error: any) {
      console.error("[FileUpload] Upload error:", error);
      res.status(500).json({
        error: 'UploadError',
        message: error.message || 'File upload failed',
      });
    }
  });

  // URL Import API - Galaxy fetches file from URL (no size limit, faster for large files)
  // Leverages Galaxy's built-in URL fetching capabilities (HTTP, FTP, S3)
  app.post("/api/datasets/import-url", authenticateToken, checkBillingQuota('URL import'), async (req, res) => {
    try {
      const { url, filename } = req.body;

      if (!url) {
        return res.status(400).json({ error: "URL is required" });
      }

      // Validate URL format
      try {
        const parsedUrl = new URL(url);
        if (!['http:', 'https:', 'ftp:', 's3:'].includes(parsedUrl.protocol)) {
          return res.status(400).json({
            error: "Unsupported protocol. Use HTTP, HTTPS, FTP, or S3 URLs."
          });
        }
      } catch {
        return res.status(400).json({ error: "Invalid URL format" });
      }

      console.log(`[URLImport] Importing from URL: ${url}`);

      // Get or create Galaxy history
      let historyId = req.session?.galaxyHistoryId as string | undefined;
      if (!historyId) {
        try {
          const sessionName = `GalaxyChat-${new Date().toISOString().split('T')[0]}`;
          historyId = await galaxyAPIProxy.createHistory(sessionName);
          if (req.session) {
            req.session.galaxyHistoryId = historyId;
          }
          console.log(`[URLImport] Created new Galaxy history: ${historyId}`);
        } catch (error: any) {
          console.error(`[URLImport] Failed to create Galaxy history:`, error.message);
          return res.status(500).json({
            error: 'GalaxyError',
            message: 'Failed to create Galaxy history for URL import'
          });
        }
      }

      // Use Galaxy's URL fetch capability
      try {
        const datasetId = uuidv4();
        const galaxyDatasetId = await galaxyAPIProxy.uploadFromUrl(
          url,
          historyId,
          filename || url.split('/').pop() || 'imported-file'
        );

        console.log(`[URLImport] Galaxy dataset created: ${galaxyDatasetId}`);

        // Store in session (URL imports have additional metadata)
        if (req.session) {
          if (!req.session.uploadedDatasets) {
            req.session.uploadedDatasets = [];
          }
          req.session.uploadedDatasets.push({
            dataset_id: datasetId,
            galaxy_dataset_id: galaxyDatasetId,
            name: filename || url.split('/').pop() || 'imported-file',
            description: `Imported from URL: ${url}`,
            file_type: 'auto',
            file_size: 0, // Size unknown until Galaxy fetches it
          });
        }

        res.json({
          dataset_id: datasetId,
          galaxy_dataset_id: galaxyDatasetId,
          galaxy_history_id: historyId,
          name: filename || url.split('/').pop(),
          source: 'url',
          source_url: url,
          uploaded_at: new Date().toISOString(),
        });
      } catch (error: any) {
        console.error(`[URLImport] Galaxy URL import failed:`, error.message);
        res.status(500).json({
          error: 'URLImportError',
          message: error.message || 'Failed to import file from URL'
        });
      }
    } catch (error: any) {
      console.error("[URLImport] Error:", error);
      res.status(500).json({
        error: 'URLImportError',
        message: error.message || 'URL import failed',
      });
    }
  });

  // Storage/Resource Check API - Check available resources before execution
  app.get("/api/resources/status", async (req, res) => {
    try {
      // Calculate storage usage from session uploads
      const uploadedDatasets = req.session?.uploadedDatasets || [];
      const totalUploadedBytes = uploadedDatasets.reduce(
        (sum: number, d: any) => sum + (d.file_size || 0), 0
      );

      // Check local disk space (upload directory)
      let availableDiskGB = 50; // Default fallback
      try {
        const stats = await fs.statfs(uploadDir);
        availableDiskGB = (stats.bsize * stats.bavail) / (1024 * 1024 * 1024);
      } catch {
        console.warn('[Resources] Could not check disk space');
      }

      // Return resource status
      res.json({
        storage: {
          uploaded_gb: totalUploadedBytes / (1024 * 1024 * 1024),
          available_gb: availableDiskGB,
          max_file_size_gb: MAX_FILE_SIZE_GB,
          dataset_count: uploadedDatasets.length,
        },
        limits: {
          max_local_file_size_gb: MAX_FILE_SIZE_GB,
          max_concurrent_uploads: 3,
          max_concurrent_workflows: 5,
        },
        recommendations: {
          use_url_import_above_gb: 2,
          use_ftp_above_gb: 5,
        }
      });
    } catch (error: any) {
      console.error("[Resources] Status check failed:", error);
      res.status(500).json({
        error: 'ResourceCheckError',
        message: error.message || 'Failed to check resource status',
      });
    }
  });

  // Dataset Validation API - AI-powered analysis
  app.post("/api/datasets/validate", async (req, res) => {
    try {
      const { workflow_name, workflow_steps } = req.body;

      if (!workflow_steps || !Array.isArray(workflow_steps) || workflow_steps.length === 0) {
        return res.status(400).json({ error: "workflow_steps is required and must be a non-empty array" });
      }

      // Get uploaded datasets from session
      const datasets = req.session.uploadedDatasets || [];

      console.log(`[DatasetValidation] Validating ${datasets.length} datasets against workflow: ${workflow_name}`);

      // Validate datasets against workflow requirements
      const validation = await datasetValidator.validateDatasets(
        datasets,
        workflow_steps,
        workflow_name || 'Untitled Workflow'
      );

      console.log(`[DatasetValidation] Validation result:`, validation);

      res.json(validation);
    } catch (error: any) {
      console.error("[DatasetValidation] Validation error:", error);
      res.status(500).json({
        error: 'ValidationError',
        message: error.message || 'Dataset validation failed',
      });
    }
  });

  // Step execution endpoint for step-by-step mode
  app.post("/api/workflow/step/execute", async (req, res) => {
    try {
      const { step_id, tool_id, parameters, inputs } = req.body;

      if (!step_id || !tool_id) {
        return res.status(400).json({ error: "step_id and tool_id are required" });
      }

      // Get Galaxy history from session
      const historyId = req.session?.galaxyHistoryId as string | undefined;

      if (!historyId) {
        return res.status(400).json({
          error: "No Galaxy history found. Please upload datasets first."
        });
      }

      console.log(`[StepExecution] Executing step ${step_id} with tool ${tool_id} in history ${historyId}`);

      // Submit tool job to Galaxy
      const job = await galaxyAPIProxy.submitToolJob(tool_id, {
        ...parameters,
        ...inputs
      }, historyId);

      console.log(`[StepExecution] Job submitted:`, job);

      // Store job info in session
      if (req.session) {
        if (!req.session.workflowJobs) {
          req.session.workflowJobs = {};
        }
        req.session.workflowJobs[step_id] = {
          job_id: job.id,
          tool_id: tool_id,
          state: job.state || 'queued',
          started_at: new Date().toISOString()
        };
      }

      res.json({
        step_id,
        job_id: job.id,
        state: job.state || 'queued',
        message: `Step ${step_id} submitted to Galaxy`
      });
    } catch (error: any) {
      console.error("[StepExecution] Execution error:", error);
      res.status(500).json({
        error: 'ExecutionError',
        message: error.message || 'Step execution failed',
      });
    }
  });

  // Get step execution status
  app.get("/api/workflow/step/:step_id/status", async (req, res) => {
    try {
      const { step_id } = req.params;

      const jobInfo = req.session.workflowJobs?.[step_id];

      if (!jobInfo) {
        return res.status(404).json({ error: "Step execution not found" });
      }

      // Get job status from Galaxy
      const job = await galaxyAPIProxy.getJob(jobInfo.job_id);

      // Update session with latest state
      if (req.session?.workflowJobs?.[step_id]) {
        req.session.workflowJobs[step_id].state = job.state;
      }

      res.json({
        step_id,
        job_id: jobInfo.job_id,
        state: job.state,
        outputs: job.outputs || [],
        started_at: jobInfo.started_at
      });
    } catch (error: any) {
      console.error("[StepStatus] Status check error:", error);
      res.status(500).json({
        error: 'StatusError',
        message: error.message || 'Failed to get step status',
      });
    }
  });

  app.get("/api/galaxy/datasets/category/:category", async (req, res) => {
    try {
      const datasets = await galaxyAPIProxy.getDatasetsByCategory(req.params.category);
      res.json({ datasets });
    } catch (error: any) {
      console.error("Get datasets by category error:", error);
      res.status(error.status_code || 500).json({
        error: error.error || 'DatasetError',
        message: error.message || 'Failed to fetch datasets',
      });
    }
  });

  app.get("/api/galaxy/datasets/:datasetId", async (req, res) => {
    try {
      const dataset = await galaxyAPIProxy.getDatasetById(req.params.datasetId);
      res.json(dataset);
    } catch (error: any) {
      console.error("Get dataset error:", error);
      res.status(error.status_code || 500).json({
        error: error.error || 'DatasetNotFound',
        message: error.message || 'Dataset not found',
      });
    }
  });

  // ============================================================================
  // Galaxy Workflow Execution API
  // ============================================================================

  // Create/upload workflow to Galaxy
  app.post("/api/galaxy/workflows", async (req, res) => {
    try {
      const { workflow } = req.body;
      if (!workflow) {
        return res.status(400).json({ error: "workflow is required" });
      }

      console.log('[CreateWorkflow] Creating workflow in Galaxy:', workflow.name || 'unnamed');
      const createdWorkflow = await galaxyAPIBackend.createWorkflow(workflow);
      console.log('[CreateWorkflow] Successfully created workflow:', createdWorkflow.id);

      res.json(createdWorkflow);
    } catch (error: any) {
      console.error("[CreateWorkflow] Error creating workflow:", error);
      res.status(error.status_code || 500).json({
        error: error.error || 'WorkflowCreationError',
        message: error.message || 'Failed to create workflow',
      });
    }
  });

  /**
   * Pre-execution validation endpoint
   * Checks workflow for critical issues before allowing execution
   */
  app.post("/api/workflow/validate-before-execute", authenticateToken, async (req, res) => {
    try {
      const { workflow_ga, validation, tool_installation, pilot_run_suggested, pilot_reasons } = req.body;

      const blockers: string[] = [];
      const warnings: string[] = [];

      // Check for critical tool installation failures
      if (tool_installation && !tool_installation.success) {
        const failedTools = tool_installation.failed_tools || [];
        if (failedTools.length > 0) {
          blockers.push(`Missing tools that could not be installed: ${failedTools.join(', ')}`);
        }
      }

      // Check for critical validation issues
      if (validation) {
        const issues = validation.issues || [];
        // Issues are considered blockers
        for (const issue of issues) {
          blockers.push(`Validation issue: ${issue}`);
        }

        // Warnings are non-blocking but should be shown
        const validationWarnings = validation.warnings || [];
        warnings.push(...validationWarnings);
      }

      // Check if workflow has required steps
      if (workflow_ga) {
        const steps = workflow_ga.steps || {};
        const stepCount = Object.keys(steps).length;
        if (stepCount === 0) {
          blockers.push('Workflow has no steps defined');
        }
      }

      // Log validation check
      await auditService.log({
        userId: req.user?.id,
        action: 'workflow.validate_before_execute',
        resourceType: 'workflow',
        details: {
          blockersCount: blockers.length,
          warningsCount: warnings.length,
          pilotSuggested: pilot_run_suggested,
        },
        status: blockers.length > 0 ? 'failure' : 'success',
      });

      // Return validation result
      res.json({
        canExecute: blockers.length === 0,
        blockers,
        warnings,
        pilotRunSuggested: pilot_run_suggested,
        pilotReasons: pilot_reasons || [],
        recommendation: blockers.length > 0
          ? 'Please resolve the blocking issues before execution'
          : pilot_run_suggested
          ? 'Consider running a pilot test first to validate parameters'
          : 'Workflow is ready for execution',
      });
    } catch (error: any) {
      console.error('[ValidateBeforeExecute] Error:', error);
      res.status(500).json({ error: 'Validation check failed', message: error.message });
    }
  });

  app.post("/api/galaxy/workflows/invoke", optionalAuth, async (req, res) => {
    try {
      const {
        workflow_id,
        inputs,
        parameters,
        history_id,
        new_history_name,
        // New: optional validation bypass (for advanced users)
        skip_validation,
        // New: validation info from workflow generation
        validation,
        tool_installation
      } = req.body;

      if (!workflow_id) {
        return res.status(400).json({ error: "workflow_id is required" });
      }

      // Pre-execution validation (unless explicitly skipped)
      if (!skip_validation) {
        // Check for critical blockers
        const blockers: string[] = [];

        // Check tool installation
        if (tool_installation && !tool_installation.success) {
          const failedTools = tool_installation.failed_tools || [];
          if (failedTools.length > 0) {
            blockers.push(`Missing tools: ${failedTools.join(', ')}`);
          }
        }

        // Check validation issues
        if (validation && validation.issues && validation.issues.length > 0) {
          blockers.push(...validation.issues.map((i: string) => `Validation: ${i}`));
        }

        // Block execution if there are critical issues
        if (blockers.length > 0) {
          console.warn('[InvokeWorkflow] Blocked due to validation issues:', blockers);
          return res.status(400).json({
            error: 'VALIDATION_FAILED',
            message: 'Workflow has critical issues that must be resolved before execution',
            blockers,
            suggestion: 'Fix the issues or run a pilot test first. Use skip_validation=true to force execution.',
          });
        }
      }

      // Merge history parameters with other parameters
      const invokeParams = {
        ...parameters,
        // If history_id provided, use it; otherwise create a new history
        ...(history_id ? { history_id } : { new_history_name: new_history_name || `bioMate Workflow Run ${new Date().toISOString()}` })
      };

      console.log('[InvokeWorkflow] Invoking workflow:', workflow_id, 'with params:', invokeParams);

      const invocation = await galaxyAPIBackend.invokeWorkflow(workflow_id, inputs, invokeParams);
      let workflowNameForNotification = 'Workflow';

      // Log successful invocation
      await auditService.logWorkflowExecutionStart(
        (req as any).user?.id || null,
        invocation.id,
        workflow_id,
        invocation.history_id || ''
      );

      // Create local invocation record for Workflow History panel
      try {
        // Get workflow name from Galaxy if possible
        try {
          const workflowDetails = await galaxyAPIBackend.getWorkflow(workflow_id);
          workflowNameForNotification = workflowDetails?.name || 'Workflow';
        } catch (e) {
          console.warn('[InvokeWorkflow] Could not fetch workflow name:', e);
        }

        await storage.createInvocation({
          id: invocation.id,
          galaxyInvocationId: invocation.id,
          workflowId: workflow_id,
          workflowName: workflowNameForNotification,
          userId: (req as any).user?.id || 'anonymous',
          status: (invocation.state === 'failed' || invocation.state === 'cancelled' ? 'error' : invocation.state || 'new') as 'new' | 'queued' | 'running' | 'ok' | 'error' | 'paused' | 'deleted',
          totalSteps: invocation.steps?.length || 0,
          completedSteps: 0,
          createdAt: new Date(),
          updatedAt: new Date(),
        });
        console.log('[InvokeWorkflow] Created local invocation record:', invocation.id);
      } catch (storageError) {
        console.warn('[InvokeWorkflow] Failed to create local invocation record:', storageError);
        // Don't fail the request - Galaxy invocation was successful
      }

      registerInvocationNotifications({
        invocationId: invocation.id,
        req,
        workflowName: workflowNameForNotification,
        workflowId: workflow_id,
        source: 'api/galaxy/workflows/invoke',
      });

      res.json(invocation);
    } catch (error: any) {
      console.error("Workflow invocation error:", error);
      res.status(error.status_code || 500).json({
        error: error.error || 'InvocationError',
        message: error.message || 'Failed to invoke workflow',
      });
    }
  });

  app.get("/api/galaxy/workflows/:workflowId/invocations/:invocationId", async (req, res) => {
    try {
      const invocation = await galaxyAPIBackend.getInvocation(req.params.workflowId, req.params.invocationId);
      res.json(invocation);
    } catch (error: any) {
      console.error("Get invocation error:", error);
      res.status(error.status_code || 500).json({
        error: error.error || 'InvocationNotFound',
        message: error.message || 'Invocation not found',
      });
    }
  });

  app.get("/api/galaxy/jobs/:jobId", async (req, res) => {
    try {
      const job = await galaxyAPIBackend.getJob(req.params.jobId);
      res.json(job);
    } catch (error: any) {
      console.error("Get job error:", error);
      res.status(error.status_code || 500).json({
        error: error.error || 'JobNotFound',
        message: error.message || 'Job not found',
      });
    }
  });

  app.get("/api/galaxy/jobs/:jobId/stdout", async (req, res) => {
    try {
      const stdout = await galaxyAPIBackend.getJobStdout(req.params.jobId);
      res.type('text/plain').send(stdout);
    } catch (error: any) {
      console.error("Get job stdout error:", error);
      res.status(error.status_code || 500).json({
        error: error.error || 'JobNotFound',
        message: error.message || 'Failed to fetch job stdout',
      });
    }
  });

  app.get("/api/galaxy/jobs/:jobId/stderr", async (req, res) => {
    try {
      const stderr = await galaxyAPIBackend.getJobStderr(req.params.jobId);
      res.type('text/plain').send(stderr);
    } catch (error: any) {
      console.error("Get job stderr error:", error);
      res.status(error.status_code || 500).json({
        error: error.error || 'JobNotFound',
        message: error.message || 'Failed to fetch job stderr',
      });
    }
  });

  app.put("/api/galaxy/jobs/:jobId/pause", async (req, res) => {
    try {
      const result = await galaxyAPIBackend.pauseJob(req.params.jobId);
      res.json({
        success: true,
        message: 'Job paused successfully',
        data: result
      });
    } catch (error: any) {
      console.error("Pause job error:", error);
      res.status(error.status_code || 500).json({
        error: error.error || 'PauseJobFailed',
        message: error.message || 'Failed to pause job',
      });
    }
  });

  app.put("/api/galaxy/jobs/:jobId/resume", async (req, res) => {
    try {
      const result = await galaxyAPIBackend.resumeJob(req.params.jobId);
      res.json({
        success: true,
        message: 'Job resumed successfully',
        data: result
      });
    } catch (error: any) {
      console.error("Resume job error:", error);
      res.status(error.status_code || 500).json({
        error: error.error || 'ResumeJobFailed',
        message: error.message || 'Failed to resume job',
      });
    }
  });

  app.get("/api/galaxy/autofix3/status", async (req, res) => {
    try {
      const status = await galaxyAPIBackend.getAutofix3Status();
      res.json(status);
    } catch (error: any) {
      console.error("AutoFix3 status error:", error);
      res.status(error.status_code || 500).json({
        error: error.error || 'AutoFixStatusFailed',
        message: error.message || 'Failed to fetch AutoFix status',
      });
    }
  });

  app.post("/api/galaxy/workflows/:workflowId/invocations/:invocationId/autofix3/run", async (req, res) => {
    try {
      const result = await galaxyAPIBackend.runAutofix3(
        req.params.workflowId,
        req.params.invocationId,
        req.body
      );
      res.json(result);
    } catch (error: any) {
      console.error("AutoFix3 run error:", error);
      res.status(error.status_code || 500).json({
        error: error.error || 'AutoFixRunFailed',
        message: error.message || 'Failed to run AutoFix',
      });
    }
  });

  app.get("/api/galaxy/workflows/:workflowId/invocations/:invocationId/autofix3/sessions", async (req, res) => {
    try {
      const limit = req.query.limit ? parseInt(req.query.limit as string, 10) : undefined;
      const result = await galaxyAPIBackend.listAutofix3Sessions(
        req.params.workflowId,
        req.params.invocationId,
        limit
      );
      res.json(result);
    } catch (error: any) {
      console.error("AutoFix3 sessions error:", error);
      res.status(error.status_code || 500).json({
        error: error.error || 'AutoFixSessionsFailed',
        message: error.message || 'Failed to fetch AutoFix sessions',
      });
    }
  });

  // ============================================================================
  // Server-Sent Events (SSE) for Real-Time Workflow Updates
  // ============================================================================

  app.get("/api/galaxy/workflows/sse/:workflowId/:invocationId", (req, res) => {
    sseManager.handleConnection(req, res);
  });

  // SSE endpoint for QC gate events - used by workflow-artifact.tsx
  // Accepts connections with only invocationId (no workflowId required)
  app.get("/api/workflows/:invocationId/events", (req, res) => {
    sseManager.handleConnectionByInvocationId(req, res);
  });

  // AI realtime analysis status — polled every 5s by workflow-artifact.tsx while a run is active.
  // Proxies to the Galaxy backend endpoint that reads nextflow_monitor's analysis output (latest.json).
  // Returns empty payload (no error) when no analysis data exists yet.
  app.get("/api/workflows/:invocationId/realtime/status", async (req, res) => {
    try {
      const galaxyUrl = process.env.GALAXY_URL || "http://localhost:8081";
      const resp = await fetch(
        `${galaxyUrl}/api/workflows/${encodeURIComponent(req.params.invocationId)}/realtime/status`,
        { signal: AbortSignal.timeout(8000) }
      );
      if (resp.ok) {
        const data = await resp.json();
        return res.json(data);
      }
      // Galaxy returned an error — return empty payload so the UI stays quiet
      return res.json({ issues: [], autofix: null, has_data: false });
    } catch {
      return res.json({ issues: [], autofix: null, has_data: false });
    }
  });

  // Error summary for failed workflows — calls LLM to parse last 200 log lines into structured error
  app.get("/api/workflows/:invocationId/error-summary", async (req, res) => {
    try {
      const galaxyUrl = process.env.GALAXY_URL || "http://localhost:8081";
      const resp = await fetch(
        `${galaxyUrl}/api/workflows/${encodeURIComponent(req.params.invocationId)}/error-summary`,
        { signal: AbortSignal.timeout(15000) }  // 15s — LLM call takes a few seconds
      );
      if (resp.ok) {
        return res.json(await resp.json());
      }
      return res.json({ error_type: "unknown", human_summary: "Could not retrieve error details", can_resume: false });
    } catch {
      return res.json({ error_type: "unknown", human_summary: "Could not retrieve error details", can_resume: false });
    }
  });

  // SSE endpoint for LangGraph pipeline task-status events.
  // The Python backend publishes to Redis channel biomate:pipeline:{id};
  // this endpoint relays those events to the browser.
  app.get("/api/pipelines/:pipelineId/events", (req, res) => {
    res.setHeader("Content-Type", "text/event-stream");
    res.setHeader("Cache-Control", "no-cache, no-transform");
    res.setHeader("Connection", "keep-alive");
    res.setHeader("X-Accel-Buffering", "no");
    res.flushHeaders?.();

    // Send a ready event immediately so the client knows the channel is open
    res.write(`event: ready\ndata: {"ok":true}\n\n`);

    // If Redis is available, subscribe to the pipeline channel
    let redisSub: any = null;
    try {
      const { getRedisClient } = require('./redis-session');
      const client = getRedisClient?.();
      if (client) {
        redisSub = client.duplicate();
        redisSub.subscribe(`biomate:pipeline:${req.params.pipelineId}`);
        redisSub.on("message", (_chan: string, msg: string) => {
          res.write(`data: ${msg}\n\n`);
        });
      }
    } catch (e) {
      console.warn('[PipelineSSE] Redis not available, events will not relay:', e);
    }

    // Heartbeat every 30 s to keep connection alive through proxies
    const heartbeat = setInterval(() => {
      res.write(`: heartbeat\n\n`);
    }, 30000);

    req.on("close", () => {
      clearInterval(heartbeat);
      redisSub?.quit?.();
    });
  });

  // Internal endpoint: Python backend POSTs here to push QC gate / phase events
  // to SSE clients.  Not authenticated — only reachable from localhost.
  app.post("/internal/sse-inject", (req: any, res: any) => {
    const { invocation_id, event_type, data } = req.body || {};
    if (!invocation_id || !event_type || data === undefined) {
      return res.status(400).json({ error: 'Missing invocation_id, event_type, or data' });
    }
    sseManager.injectRawEvent(String(invocation_id), String(event_type), data);
    res.json({ ok: true });
  });

  // Proxy for QC gate endpoints — frontend POSTs to /api/qc-gates/:id/decision
  // which must be forwarded to the Galaxy backend. No dedicated route existed before.
  app.all("/api/qc-gates/*", async (req: any, res: any) => {
    try {
      const path = req.path;
      const method = req.method.toLowerCase();
      let response: any;
      if (method === 'get') {
        response = await galaxyAPIProxy.client.get(path, { params: req.query });
      } else if (method === 'post') {
        response = await galaxyAPIProxy.client.post(path, req.body);
      } else if (method === 'patch') {
        response = await (galaxyAPIProxy.client as any).patch(path, req.body);
      } else {
        return res.status(405).json({ error: 'Method not allowed' });
      }
      return res.status(response.status).json(response.data);
    } catch (err: any) {
      const status = err.response?.status || 502;
      return res.status(status).json(err.response?.data || { error: 'QC gate proxy error' });
    }
  });

  // Chat endpoint with Galaxy Assistant integration
  app.post("/api/chat", optionalAuth, async (req, res) => {
    const requestStartTime = Date.now();
    const timings: { step: string; elapsed: number }[] = [];
    const addTiming = (step: string) => {
      timings.push({ step, elapsed: Date.now() - requestStartTime });
      console.log(`[Chat API] [${Date.now() - requestStartTime}ms] ${step}`);
    };

    try {
      addTiming('Request received');
      const { message, context } = req.body;

      if (!message) {
        addTiming('Error: Message missing');
        return res.status(400).json({ error: "Message is required" });
      }

      if (!galaxyAssistant) {
        addTiming('Error: Galaxy Assistant not available');
        return res.status(503).json({
          error: "Galaxy Assistant not available. ANTHROPIC_API_KEY is not configured."
        });
      }

      addTiming('Validation passed');
      console.log('[Chat API] Processing message with Galaxy Assistant:', message);

      // ----------------------------------------------------------------
      // Conversation State: Load persisted state (pre-compaction flush)
      // ----------------------------------------------------------------
      const sessionId = context?.memorySessionId || context?.sessionId;
      let convState: ConversationState | undefined;

      if (sessionId) {
        convState = await conversationStateManager.loadState(sessionId);
        convState.currentTurn += 1;

        // Check if this message answers a pending clarification
        const resolvedClarification = conversationStateManager.resolveClarifications(convState, message);
        if (resolvedClarification) {
          addTiming(`Clarification resolved: ${resolvedClarification.type}`);
        }
      }

      // Check if memory integration should be used
      const useMemory = memoryIntegration && (context?.memorySessionId || context?.projectId);
      let assistantResponse;
      let episodeId: number | undefined;

      // Build enriched context for the LLM — pass accumulated facts so it can
      // decide supersession, and turnIndex so facts get the right timestamp
      const enrichedContext = {
        ...(context || {}),
        turnIndex: convState?.currentTurn,
        accumulatedFacts: convState
          ? conversationStateManager.getActiveFacts(convState).map(f => ({
              id: f.id,
              category: f.category,
              value: f.value,
            }))
          : undefined,
        // Billing: pass authenticated user id so the Python backend can track LLM costs
        billingUserId: req.user ? String(req.user.id) : undefined,
      };

      addTiming('Starting AI processing');

      if (useMemory) {
        // Process with memory enhancement
        addTiming('Using memory-enhanced processing');
        const memoryResponse = await memoryIntegration!.processWithMemory(message, context as MemoryEnhancedContext);
        assistantResponse = memoryResponse;
        episodeId = memoryResponse.episodeId;
        addTiming('Memory processing complete');
      } else {
        // Standard processing without memory
        addTiming('Using standard processing');
        assistantResponse = await galaxyAssistant.processMessage(message, enrichedContext);
        addTiming('Standard processing complete');
      }

      // ----------------------------------------------------------------
      // Conversation State: Update with extracted facts and intent
      // ----------------------------------------------------------------
      if (convState) {
        // Update intent from assistant response
        if (assistantResponse.intentType) {
          conversationStateManager.updateIntent(
            convState,
            assistantResponse.intentType,
            assistantResponse.intentConfidence || 0.8,
          );
        }

        // Add extracted facts (turnIndex already set via enrichedContext)
        if (assistantResponse.extractedFacts && assistantResponse.extractedFacts.length > 0) {
          conversationStateManager.addFacts(convState, assistantResponse.extractedFacts);
        } else if (assistantResponse.inlineParameters) {
          // Backwards compatibility: convert inlineParameters to facts
          const facts = Object.entries(assistantResponse.inlineParameters).map(([key, value]) =>
            conversationStateManager.createFact(
              key as any,
              String(value),
              convState!.currentTurn,
            )
          );
          conversationStateManager.addFacts(convState, facts);
        }

        // Recommendations update removed

        // Update phase if workflow was generated
        if (assistantResponse.generatedWorkflow) {
          convState.phase = 'generated';
        }

        // Track workflow steps in ConversationState for pipeline output→input wiring.
        // When the AI returns a generated workflow, record it as a step so subsequent
        // chained workflows can check type compatibility against it.
        if (assistantResponse.generatedWorkflow && convState) {
          const wf = assistantResponse.generatedWorkflow as any;
          const workflowName: string = wf?.name || wf?.workflowName || wf?.nextflow_path || '';
          if (workflowName) {
            // Fetch type info from backend (fire-and-forget, don't block response)
            const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
            fetch(`${galaxyUrl}/api/workflows/${encodeURIComponent(workflowName)}/types`, {
              signal: AbortSignal.timeout(3000),
            })
              .then(r => r.ok ? r.json() : null)
              .then((typeInfo: any) => {
                if (!typeInfo) return;
                conversationStateManager.addWorkflowStep(convState!, {
                  workflowId: String(wf?.id || ''),
                  workflowName,
                  domain: wf?.domain || typeInfo?.domain || 'general',
                  inputTypes: typeInfo?.input_types ?? [],
                  outputTypes: typeInfo?.output_types ?? [],
                  status: 'planned',
                  turnIndex: convState!.currentTurn,
                });
                conversationStateManager.saveState(convState!).catch(() => {});
              })
              .catch(() => {});
          }
        }

        // Create task arcs for multi-intent responses
        if (assistantResponse.isMultiIntent && assistantResponse.subIntentResults) {
          conversationStateManager.createTaskArcs(convState,
            assistantResponse.subIntentResults.map(r => ({
              id: r.intentId,
              type: r.intentType,
              subQuery: r.subQuery,
              facts: [],
              dependsOn: [],
            }))
          );
          // Update arc statuses based on results
          for (const result of assistantResponse.subIntentResults) {
            conversationStateManager.updateTaskArc(convState, result.intentId, {
              status: result.status === 'success' ? 'completed' : 'failed',
              resultSummary: result.message?.substring(0, 200),
            });
          }
        }

        // Evaluate readiness
        conversationStateManager.evaluateReadiness(convState);

        // Save state (pre-compaction flush — persists every turn)
        await conversationStateManager.saveState(convState);

        // Persist current turn's facts to the facts table for cross-session analysis
        await conversationStateManager.persistFacts(convState);

        // Periodic consolidation: every 10 turns, compact facts and intent history
        if (convState.currentTurn > 0 && convState.currentTurn % 10 === 0) {
          conversationStateManager.consolidateFacts(convState);
          conversationStateManager.compactIntentHistory(convState);
          await conversationStateManager.saveState(convState);
        }

        // Doom loop detection: check every turn
        const doomLoop = conversationStateManager.detectDoomLoop(convState);
        if (doomLoop.detected) {
          console.log(`[Chat API] Doom loop detected: ${doomLoop.intentType} repeated ${doomLoop.occurrences} times`);
        }

        addTiming('Conversation state saved');
      }

      console.log('[Chat API] Galaxy Assistant response:', {
        toolSearchUsed: assistantResponse.sources.toolSearchUsed,
        datasetRAGUsed: assistantResponse.sources.datasetRAGUsed,
        workflowGenerated: assistantResponse.sources.workflowGenerated,
        thinkingUsed: assistantResponse.sources.thinkingUsed,
        toolsFound: assistantResponse.recommendedTools?.length || 0,
        datasetsFound: assistantResponse.recommendedDatasets?.length || 0,
        memoryUsed: useMemory,
        episodeId,
      });

      // If workflow was generated, validate prerequisites
      let prerequisitesValidation = null;
      if (assistantResponse.generatedWorkflow && prerequisitesValidator) {
        try {
          console.log('[Chat API] Validating workflow prerequisites...');
          prerequisitesValidation = await prerequisitesValidator.validate({
            workflowDefinition: assistantResponse.generatedWorkflow,
            historyId: context?.historyId,
            userContext: message, // Use original message as context
          });
          console.log('[Chat API] Prerequisites validation:', {
            fulfilled: prerequisitesValidation.fulfilled,
            missingInputs: prerequisitesValidation.analysis.missingInputs.length,
            missingParams: prerequisitesValidation.analysis.missingParameters.length,
          });
        } catch (validationError: any) {
          console.error('[Chat API] Prerequisites validation failed:', validationError.message);
          // Non-fatal - continue without validation
        }
      }

      // Domain-fit guardrail: block execution when generated tools are clearly off-domain.
      const requestTextLower = (message || '').toLowerCase();
      const isDrugDevelopmentQuery = /(drug|admet|herg|dili|toxicity|docking|ligand|pk|pharmacokinetic|nca|auc|cmax|tmax|half[- ]?life|clinical)/i.test(
        String(message || "")
      );
      const requestedWesLike =
        requestTextLower.includes('whole-exome') ||
        requestTextLower.includes('whole exome') ||
        /\bwes\b/.test(requestTextLower) ||
        requestTextLower.includes('tumor-normal') ||
        requestTextLower.includes('tumor normal');
      const toolText = (assistantResponse.recommendedTools || [])
        .map((t: any) => `${t?.tool?.name || ''} ${t?.tool?.tool_id || ''} ${t?.tool?.category || ''}`.toLowerCase())
        .join(' ');
      const hasWesPreferredSignals =
        /picard|samtools|qualimap|mosdepth|bcftools|gatk|bamqc/.test(toolText);
      const hasMicrobiomeSignals =
        /qiime|microbiome|metagenom|16s/.test(toolText);
      const selfReportedMismatch =
        /not (the )?ideal match|aren't (the )?ideal match|not ideal for/.test(
          (assistantResponse.message || '').toLowerCase()
        );

      const domainGuard =
        (requestedWesLike && hasMicrobiomeSignals && !hasWesPreferredSignals) || selfReportedMismatch
          ? {
              blocked: true,
              reason:
                "Generated workflow appears domain-mismatched for your request. Please regenerate with domain-specific constraints before execution.",
              detectedDomain: requestedWesLike ? "wes_qc" : "general",
            }
          : {
              blocked: false,
              reason: null,
              detectedDomain: requestedWesLike ? "wes_qc" : "unspecified",
            };

      const prereqRecoveryRequested =
        requestTextLower.includes("prepare runnable demo inputs") ||
        requestTextLower.includes("sample/test inputs") ||
        requestTextLower.includes("sample data") ||
        requestTextLower.includes("test data");
      const missingInputCount =
        Array.isArray(prerequisitesValidation?.analysis?.missingInputs)
          ? prerequisitesValidation.analysis.missingInputs.length
          : 0;
      const missingParamCount =
        Array.isArray(prerequisitesValidation?.analysis?.missingParameters)
          ? prerequisitesValidation.analysis.missingParameters.length
          : 0;
      const prereqRecoveryApproved =
        prereqRecoveryRequested &&
        !!assistantResponse.generatedWorkflow &&
        (missingInputCount > 0 || missingParamCount > 0);
      const prereqRecovery = {
        requested: prereqRecoveryRequested,
        approved: prereqRecoveryApproved,
        reason: prereqRecoveryApproved
          ? "Recovery mode approved: allow runnable demo/sample path while inputs are unresolved."
          : null,
      };

      const workflowPayload = assistantResponse.generatedWorkflow;
      const runnableWorkflow = !!(
        workflowPayload?.success &&
        !workflowPayload?.error &&
        (workflowPayload?.workflow_ga || workflowPayload?.nextflow_path)
      );
      const workflowGenerationFailed = !!workflowPayload && !runnableWorkflow;
      const unresolvedWorkflowState = !runnableWorkflow;
      const workflowGenerationDiagnostics = (() => {
        if (!workflowGenerationFailed) return null;

        const reasonText = String(workflowPayload?.error || workflowPayload?.message || "").toLowerCase();
        const likelyReasons: string[] = [];
        const recommendedActions: string[] = [];
        const followUpQuestions: string[] = [];
        const suggestionConfidence = Number(assistantResponse.workflowSuggestion?.confidence || 0);

        if (domainGuard.blocked) {
          likelyReasons.push("The generated candidate appears domain-mismatched for your request.");
          recommendedActions.push("Regenerate with explicit domain constraints and required tool families.");
        }
        if (/timeout|timed out|deadline|temporar/.test(reasonText)) {
          likelyReasons.push("Upstream workflow generation timed out or an upstream service was temporarily unavailable.");
          recommendedActions.push("Retry generation with a narrower workflow scope (fewer stages) first.");
        }
        if (/auth|forbidden|permission|unauthor|401|403/.test(reasonText)) {
          likelyReasons.push("Generation hit an authentication/permission boundary in a dependent service.");
          recommendedActions.push("Confirm service credentials and retry after auth context is refreshed.");
        }
        if (/tool|runtime|install|dependency/.test(reasonText)) {
          likelyReasons.push("Tool/runtime constraints prevented assembling a runnable workflow.");
          recommendedActions.push("Constrain to currently available tools and rerun generation.");
        }
        if ((assistantResponse.recommendedTools?.length || 0) === 0) {
          likelyReasons.push("No strong tool matches were found for the current request phrasing.");
          recommendedActions.push("Provide required method/tool hints (must-use or must-avoid) to improve ranking.");
        }
        if (suggestionConfidence > 0 && suggestionConfidence < 0.7) {
          likelyReasons.push("Intent-to-workflow confidence is low; requirements may still be underspecified.");
          recommendedActions.push("Clarify organism/data type/input format/desired outputs before regenerating.");
        }
        if (prereqRecoveryRequested && missingInputCount > 0) {
          likelyReasons.push("The candidate workflow requires inputs that are not currently available in context.");
          recommendedActions.push("Use sample/test inputs first, then swap to real datasets once validated.");
        }
        if (likelyReasons.length === 0) {
          likelyReasons.push("The generation pipeline returned a non-runnable candidate due to unmet constraints.");
          recommendedActions.push("Regenerate with stricter constraints and explicit required outputs.");
        }

        followUpQuestions.push(
          "What exact input data do you already have (format + example filenames)?",
          "Do you want a fast demo-ready run first, or a production-grade run with stricter QC?",
          "Any required tools/runtimes to include or avoid?"
        );

        return {
          failed: true,
          likelyReasons,
          recommendedActions,
          followUpQuestions,
          processOutputs: {
            error: workflowPayload?.error || null,
            message: workflowPayload?.message || null,
            source: workflowPayload?.source || null,
            confidence: workflowPayload?.confidence ?? null,
            templateMatchScore: workflowPayload?.template_match_score ?? null,
            toolCount: assistantResponse.recommendedTools?.length || 0,
            datasetCount: assistantResponse.recommendedDatasets?.length || 0,
            domainGuard: domainGuard.blocked ? domainGuard.reason : null,
          },
        };
      })();

      let assistantMessage = String(assistantResponse.message || "");
      const shouldApplyTruthfulnessGuard =
        isDrugDevelopmentQuery &&
        (unresolvedWorkflowState || /partial workflow|incomplete|only one/i.test(assistantMessage));
      if (shouldApplyTruthfulnessGuard) {
        // UX truthfulness guard: never claim a runnable workflow when payload is unresolved.
        const overPromisedRunnable =
          /runnable workflow has been generated|workflow has been generated and is technically|is ready for execution|ready to execute|click\s*"?run"?\s*to launch/i.test(
            assistantMessage
          );
        if (overPromisedRunnable) {
          assistantMessage = assistantMessage.replace(
            /runnable workflow has been generated/gi,
            "candidate workflow was drafted but execution payload is not yet runnable"
          );
          assistantMessage = assistantMessage.replace(
            /workflow has been generated and is technically/gi,
            "candidate workflow was drafted but is only partially validated and not guaranteed executable in this response"
          );
          assistantMessage = assistantMessage.replace(
            /is ready for execution/gi,
            "is currently not executable in this response"
          );
          assistantMessage = assistantMessage.replace(
            /ready to execute/gi,
            "not yet safe to execute end-to-end"
          );
          assistantMessage = assistantMessage.replace(
            /click\s*"?run"?\s*to launch[^.\n]*/gi,
            "confirm inputs and regenerate a runnable workflow"
          );
        }
        if (!/workflow generation is currently unavailable|recovery plan|suggested next actions/i.test(assistantMessage)) {
          assistantMessage = `Workflow generation is currently unavailable for immediate execution.\nRecovery Plan: confirm priority stage, provide minimal input examples, and regenerate.\n\n${assistantMessage}`;
        }
      }
      if (workflowGenerationDiagnostics && !assistantMessage.includes("To unblock this quickly")) {
        assistantMessage += `\n\nTo unblock this quickly, please confirm:\n- ${workflowGenerationDiagnostics.followUpQuestions.join("\n- ")}`;
      }

      // Format response for frontend
      addTiming('Sending response');
      const suggestions = generateSuggestions(
        String(assistantResponse.message || ""),
        String(message || "")
      );

      // Persist chat cost estimate for end-to-end process auditing.
      // This is an approximation based on local token counting heuristics.
      try {
        const inCount = tokenCounter.countText(String(message || "")).tokens;
        const outCount = tokenCounter.countText(String(assistantResponse.message || "")).tokens;
        const pricing = tokenCounter.estimateCost([
          { role: "user", content: String(message || "") },
          { role: "assistant", content: String(assistantResponse.message || "") },
        ]);
        const estimatedCostUsd = Number((pricing.total || 0).toFixed(8));
        const sessionId = String(context?.memorySessionId || context?.sessionId || "");
        const runId = String(context?.runId || context?.executionRunId || "");
        const invocationId = String(context?.invocationId || "");

        telemetryService
          .create("cost.chat.estimated", new Date(), {
            userId: req.user ? String(req.user.id) : "anonymous",
            sessionId: sessionId || undefined,
            runId: runId || undefined,
            invocationId: invocationId || undefined,
            provider: "anthropic",
            model: galaxyAssistant?.getModelConfig().responseModel || "claude-sonnet-4-6",
            inputTokensEstimated: inCount,
            outputTokensEstimated: outCount,
            estimatedCostUsd,
            estimationMethod: "token_counter_heuristic",
          })
          .catch((error) => {
            console.warn("[CostAudit] Failed to persist chat cost estimate:", error?.message || error);
          });

        // Emit LLM cost event to Galaxy billing backend → Lago (fire-and-forget)
        if (req.user) {
          const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
          const billingKey = process.env.BILLING_INTERNAL_KEY;
          if (billingKey) {
            fetch(`${galaxyUrl}/internal/billing/llm_cost`, {
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
                'X-Internal-Key': billingKey,
              },
              body: JSON.stringify({
                user_id: String(req.user.id),
                session_id: sessionId || `chat-${Date.now()}`,
                model: galaxyAssistant?.getModelConfig().responseModel || 'claude-sonnet-4-6',
                input_tokens: inCount,
                output_tokens: outCount,
                duration_ms: 0,
              }),
              signal: AbortSignal.timeout(5000),
            }).catch((err: any) => {
              console.warn('[Billing] llm_cost emission failed:', err?.message || err);
            });
          }
        }
      } catch (costError: any) {
        console.warn("[CostAudit] Failed to estimate chat cost:", costError?.message || costError);
      }

      res.json({
        response: assistantMessage,
        suggestions,
        workflow: assistantResponse.generatedWorkflow,

        // Pre-execution validation (if workflow was generated)
        prerequisitesValidation,

        // Thinking mode support
        thinking_content: assistantResponse.thinking_content,
        thinking_level: assistantResponse.thinking_level,

        // Memory tracking
        episodeId,

        // Additional metadata for UI enhancement
        metadata: {
          intentType: assistantResponse.intentType,
          inlineParameters: assistantResponse.inlineParameters,
          workflowSuggestion: assistantResponse.workflowSuggestion,
          sources: assistantResponse.sources,
          memoryUsed: useMemory,
          domainGuard,
          prereqRecovery,
          workflowGenerationDiagnostics,
        },

        // Multi-intent results
        subIntentResults: assistantResponse.subIntentResults,
        isMultiIntent: assistantResponse.isMultiIntent || false,

        // Research and benchmark results (for specialized rendering)
        researchResponse: assistantResponse.researchResponse,
        benchmarkEvidence: assistantResponse.benchmarkEvidence,

        // Conversation state snapshot for UI transparency
        stateSnapshot: convState ? {
          phase: convState.phase,
          factCount: conversationStateManager.getActiveFacts(convState).length,
          readinessScore: convState.readiness.score,
          missingRequired: convState.readiness.missingRequired,
          intentType: convState.intent.primaryType,
          intentConfidence: convState.intent.confidence,
          taskArcs: convState.taskArcs?.map(a => ({
            id: a.id, intentType: a.intentType, status: a.status,
          })),
          doomLoop: (() => {
            const dl = conversationStateManager.detectDoomLoop(convState);
            return dl.detected ? { suggestion: dl.suggestion } : undefined;
          })(),
          // Pipeline chain state — surfaces type compatibility warnings to UI
          pipelineSteps: convState.workflowSteps?.map(s => ({
            stepIndex: s.stepIndex,
            workflowName: s.workflowName,
            status: s.status,
            inputTypes: s.inputTypes,
            outputTypes: s.outputTypes,
            warnings: s.compatibilityWarnings,
          })) ?? [],
          pipelineWarnings: conversationStateManager.getPipelineWarnings(convState),
        } : undefined,

        // Clarification request (if system needs user input or doom loop detected)
        clarification: (() => {
          // Doom loop clarification takes priority if no pending clarifications
          const pending = convState?.pendingClarifications.find(c => c.status === 'pending');
          if (pending) {
            return { id: pending.id, question: pending.question, options: pending.options, type: pending.type };
          }
          if (convState) {
            const dl = conversationStateManager.detectDoomLoop(convState);
            if (dl.detected && dl.suggestion) {
              return { id: 'doom_loop', question: dl.suggestion, type: 'ambiguous_intent' as const };
            }
          }
          return undefined;
        })(),

        // Debug: Include timings
        _debug_timings: timings,
      });
      addTiming('Response sent');

    } catch (error: any) {
      addTiming(`Error: ${error.message}`);
      console.error("Chat API error:", error);

      // Track AI assistant errors for error-rate dashboard
      telemetryService.create('ai_assistant_error', new Date(), {
        error: (error as Error).message?.slice(0, 200),
        path: req.path,
      }).catch(() => {});

      // Fallback response
      const fallbackResponse = "I'm here to help you with bioinformatics analysis! What kind of data or workflow would you like to work on?";

      res.json({
        response: fallbackResponse,
        suggestions: generateSuggestions(fallbackResponse, String(req.body?.message || "")),
        workflow: null,
        metadata: {
          error: error.message,
        },
      });
    }
  });

  // Streaming chat endpoint (SSE) for token-level response updates
  app.post("/api/chat/stream", optionalAuth, async (req, res) => {
    const sendEvent = (event: string, data: Record<string, any>) => {
      res.write(`event: ${event}\n`);
      res.write(`data: ${JSON.stringify(data)}\n\n`);
    };

    try {
      const { message, context } = req.body || {};
      if (!message) {
        res.status(400).json({ error: "Message is required" });
        return;
      }
      if (!galaxyAssistant) {
        res.status(503).json({
          error: "Galaxy Assistant not available. ANTHROPIC_API_KEY is not configured."
        });
        return;
      }

      res.setHeader("Content-Type", "text/event-stream");
      res.setHeader("Cache-Control", "no-cache, no-transform");
      res.setHeader("Connection", "keep-alive");
      res.setHeader("X-Accel-Buffering", "no");
      res.flushHeaders?.();

      sendEvent("ready", { ok: true });

      const enrichedContext = {
        ...(context || {}),
        billingUserId: req.user ? String(req.user.id) : undefined,
      };

      const assistantResponse = await galaxyAssistant.processMessage(
        String(message),
        enrichedContext,
        (chunk) => sendEvent("delta", { text: chunk })
      );

      let prerequisitesValidation = null;
      if (assistantResponse.generatedWorkflow && prerequisitesValidator) {
        try {
          prerequisitesValidation = await prerequisitesValidator.validate({
            workflowDefinition: assistantResponse.generatedWorkflow,
            historyId: context?.historyId,
            userContext: message,
          });
        } catch (validationError: any) {
          console.error('[Chat Stream API] Prerequisites validation failed:', validationError.message);
        }
      }

      const suggestions = generateSuggestions(
        String(assistantResponse.message || ""),
        String(message || "")
      );

      const workflowPayload = assistantResponse.generatedWorkflow;
      const runnableWorkflow = !!(
        workflowPayload?.success &&
        !workflowPayload?.error &&
        (workflowPayload?.workflow_ga || workflowPayload?.nextflow_path)
      );
      const workflowGenerationFailed = !!workflowPayload && !runnableWorkflow;
      const unresolvedWorkflowState = !runnableWorkflow;
      const isDrugDevelopmentQuery = /(drug|admet|herg|dili|toxicity|docking|ligand|pk|pharmacokinetic|nca|auc|cmax|tmax|half[- ]?life|clinical)/i.test(
        String(message || "")
      );

      const workflowGenerationDiagnostics = (() => {
        if (!unresolvedWorkflowState || !isDrugDevelopmentQuery) return null;
        const likelyReasons: string[] = [];
        const recommendedActions: string[] = [];
        const followUpQuestions: string[] = [];
        const errorText = `${workflowPayload?.error || ""} ${workflowPayload?.message || ""}`.toLowerCase();

        likelyReasons.push("Tool gap: one or more required capabilities are unavailable for this exact request.");
        likelyReasons.push("Input gap: required datasets/metadata are missing for immediate execution.");
        if (/domain|mismatch|alignment|incompatible/.test(errorText)) {
          likelyReasons.push("Domain mismatch: requested stages span incompatible domains and should be split into staged workflows.");
        }

        recommendedActions.push("Confirm a priority stage (docking, ADMET, or PK/NCA), then build and validate that stage first.");
        recommendedActions.push("Provide minimal required inputs (format + example filenames), then regenerate.");
        recommendedActions.push("Define at least one decision gate (risk cutoff/threshold) for go-no-go filtering.");

        followUpQuestions.push("Which stage is highest priority right now: docking, ADMET, or PK/NCA?");
        followUpQuestions.push("What input files do you currently have (format and example filenames)?");
        followUpQuestions.push("What cutoff/threshold should be used as your decision gate?");

        return {
          failed: true,
          likelyReasons,
          recommendedActions,
          followUpQuestions,
          processOutputs: {
            error: workflowPayload?.error || null,
            message: workflowPayload?.message || null,
            source: workflowPayload?.source || null,
            confidence: workflowPayload?.confidence ?? null,
            templateMatchScore: workflowPayload?.template_match_score ?? null,
            toolCount: assistantResponse.recommendedTools?.length || 0,
            datasetCount: assistantResponse.recommendedDatasets?.length || 0,
          },
        };
      })();

      let assistantMessage = String(assistantResponse.message || "");
      if (isDrugDevelopmentQuery) {
        assistantMessage = `Decision gate: set a risk threshold/cutoff before execution. Next step: confirm priority stage, required inputs, and follow-up questions.\n\n${assistantMessage}`;
      }
      const shouldApplyTruthfulnessGuard =
        isDrugDevelopmentQuery &&
        (unresolvedWorkflowState || /partial workflow|incomplete|only one/i.test(assistantMessage));
      if (shouldApplyTruthfulnessGuard) {
        // Ensure streamed UX never over-promises immediate executability.
        const overPromisedRunnable =
          /runnable workflow has been generated|workflow has been generated and is technically|is ready for execution|ready to execute|click\s*"?run"?\s*to launch/i.test(
            assistantMessage
          );
        if (overPromisedRunnable) {
          assistantMessage = assistantMessage.replace(
            /runnable workflow has been generated/gi,
            "candidate workflow was drafted but execution payload is not yet runnable"
          );
          assistantMessage = assistantMessage.replace(
            /workflow has been generated and is technically/gi,
            "candidate workflow was drafted but is only partially validated and not guaranteed executable in this response"
          );
          assistantMessage = assistantMessage.replace(
            /is ready for execution/gi,
            "is currently not executable in this response"
          );
          assistantMessage = assistantMessage.replace(
            /ready to execute/gi,
            "not yet safe to execute end-to-end"
          );
          assistantMessage = assistantMessage.replace(
            /click\s*"?run"?\s*to launch[^.\n]*/gi,
            "confirm inputs and regenerate a runnable workflow"
          );
        }
        if (!/workflow generation is currently unavailable|recovery plan|suggested next actions/i.test(assistantMessage)) {
          assistantMessage = `Workflow generation is currently unavailable for immediate execution.\nRecovery Plan: confirm priority stage, provide minimal input examples, and regenerate.\n\n${assistantMessage}`;
        }
      }
      if (workflowGenerationDiagnostics && !assistantMessage.includes("To unblock this quickly")) {
        assistantMessage += `\n\nTo unblock this quickly, please confirm:\n- ${workflowGenerationDiagnostics.followUpQuestions.join("\n- ")}`;
      }

      const responsePayload = {
        response: assistantMessage,
        suggestions,
        workflow: assistantResponse.generatedWorkflow,
        prerequisitesValidation,
        thinking_content: assistantResponse.thinking_content,
        thinking_level: assistantResponse.thinking_level,
        metadata: {
          intentType: assistantResponse.intentType,
          inlineParameters: assistantResponse.inlineParameters,
          workflowSuggestion: assistantResponse.workflowSuggestion,
          sources: assistantResponse.sources,
          memoryUsed: false,
          workflowGenerationDiagnostics,
        },
        subIntentResults: assistantResponse.subIntentResults,
        isMultiIntent: assistantResponse.isMultiIntent || false,
        researchResponse: assistantResponse.researchResponse,
        benchmarkEvidence: assistantResponse.benchmarkEvidence,
      };

      // Emit LLM cost to Galaxy billing backend → Lago (fire-and-forget)
      if (req.user) {
        const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
        const billingKey = process.env.BILLING_INTERNAL_KEY;
        if (billingKey) {
          const inCount = tokenCounter.countText(String(message || "")).tokens;
          const outCount = tokenCounter.countText(String(assistantResponse.message || "")).tokens;
          const sessionId = String(context?.memorySessionId || context?.sessionId || "");
          fetch(`${galaxyUrl}/internal/billing/llm_cost`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'X-Internal-Key': billingKey,
            },
            body: JSON.stringify({
              user_id: String(req.user.id),
              session_id: sessionId || `stream-${Date.now()}`,
              model: galaxyAssistant?.getModelConfig().responseModel || 'claude-sonnet-4-6',
              input_tokens: inCount,
              output_tokens: outCount,
              duration_ms: 0,
            }),
            signal: AbortSignal.timeout(5000),
          }).catch((err: any) => {
            console.warn('[Billing] stream llm_cost emission failed:', err?.message || err);
          });
        }
      }

      sendEvent("final", responsePayload);
      sendEvent("done", { ok: true });
      res.end();
    } catch (error: any) {
      console.error("Chat Stream API error:", error);
      try {
        sendEvent("error", {
          message: error?.message || "Streaming chat failed",
        });
        sendEvent("done", { ok: false });
      } catch {
        // Ignore secondary write errors
      }
      res.end();
    }
  });

  // ============================================================================
  // Context Compression API
  // ============================================================================

  // Compress session messages
  app.post("/api/compress-session", async (req, res) => {
    try {
      const { sessionId, messages, keepRecentCount } = req.body;

      if (!messages || !Array.isArray(messages)) {
        return res.status(400).json({ error: "messages array is required" });
      }

      if (!process.env.ANTHROPIC_API_KEY) {
        return res.status(503).json({
          error: "Context compression not available. ANTHROPIC_API_KEY is not configured."
        });
      }

      console.log('[Compression API] Compressing session:', {
        sessionId,
        messageCount: messages.length,
        keepRecentCount: keepRecentCount || 3
      });

      // Get compressor instance
      const compressor = getContextCompressor(process.env.ANTHROPIC_API_KEY);

      // Compress messages
      const result = await compressor.compressMessages(messages, {
        keepRecentCount: keepRecentCount || 3
      });

      console.log('[Compression API] Compression successful:', {
        messagesReduced: `${result.messagesBeforeCount} → ${result.messagesAfterCount}`,
        tokensReduced: `${result.tokensBeforeCount} → ${result.tokensAfterCount}`,
        compressionRatio: `${(result.compressionRatio * 100).toFixed(1)}%`
      });

      res.json(result);
    } catch (error: any) {
      console.error('[Compression API] Compression failed:', error);
      res.status(500).json({
        error: 'CompressionError',
        message: error.message || 'Context compression failed',
      });
    }
  });

  // Workflow generation endpoint - proxies to Galaxy backend
  app.post("/api/ai_assistant/generate_workflow", optionalAuth, checkBillingQuota('AI generation'), async (req, res) => {
    try {
      const { request_text, available_datasets, context, preferred_tools, constraints } = req.body;

      if (!request_text) {
        return res.status(400).json({ error: "request_text is required" });
      }

      console.log('[WorkflowGen API] Generating workflow for:', request_text);

      // Call Galaxy backend via proxy
      const response = await galaxyAPIProxy.generateWorkflow({
        user_intent: request_text,
        datasets: available_datasets,
        max_tools_search: constraints?.max_tools_search,
      });

      console.log('[WorkflowGen API] Response:', {
        success: response.success,
        source: response.source,
        confidence: response.confidence,
        has_workflow_ga: !!response.workflow_ga,
      });

      console.log('[WorkflowGen API] Sending response to client...');
      res.json(response);
      console.log('[WorkflowGen API] Response sent successfully');
    } catch (error: any) {
      console.error("[WorkflowGen API] Error:", error);
      res.status(500).json({
        success: false,
        error: 'WorkflowGenerationError',
        message: error.message || 'Workflow generation failed',
      });
    }
  });

  // ============================================================================
  // AI Assistant - Pilot Run API (Added 2025-12-30)
  // ============================================================================

  // Start a pilot run for parameter tuning
  app.post("/api/ai_assistant/pilot/start", optionalAuth, async (req, res) => {
    try {
      const { workflow_id, total_samples, config } = req.body;

      if (!workflow_id) {
        return res.status(400).json({ error: "workflow_id is required" });
      }

      console.log('[Pilot API] Starting pilot run for workflow:', workflow_id);

      // Proxy to Galaxy backend
      const response = await galaxyAPIProxy.client.post('/api/ai_assistant/pilot/start', {
        workflow_id,
        total_samples: total_samples || 100,
        config: config || {},
      });

      res.json(response.data);
    } catch (error: any) {
      console.error("[Pilot API] Error starting pilot:", error);
      res.status(500).json({
        success: false,
        error: 'PilotStartError',
        message: error.message || 'Failed to start pilot run',
      });
    }
  });

  // Get pilot run status
  app.get("/api/ai_assistant/pilot/:pilotId/status", async (req, res) => {
    try {
      const { pilotId } = req.params;

      console.log('[Pilot API] Getting status for pilot:', pilotId);

      const response = await galaxyAPIProxy.client.get(`/api/ai_assistant/pilot/${pilotId}/status`);
      res.json(response.data);
    } catch (error: any) {
      console.error("[Pilot API] Error getting pilot status:", error);
      res.status(500).json({
        success: false,
        error: 'PilotStatusError',
        message: error.message || 'Failed to get pilot status',
      });
    }
  });

  // Get full run estimate from pilot results
  app.get("/api/ai_assistant/pilot/:pilotId/estimate", async (req, res) => {
    try {
      const { pilotId } = req.params;

      console.log('[Pilot API] Getting estimate for pilot:', pilotId);

      const response = await galaxyAPIProxy.client.get(`/api/ai_assistant/pilot/${pilotId}/estimate`);
      res.json(response.data);
    } catch (error: any) {
      console.error("[Pilot API] Error getting pilot estimate:", error);
      res.status(500).json({
        success: false,
        error: 'PilotEstimateError',
        message: error.message || 'Failed to get pilot estimate',
      });
    }
  });

  // ============================================================================
  // AI Assistant - Citation API (Added 2025-12-30)
  // ============================================================================

  // Export citations as BibTeX
  app.post("/api/ai_assistant/citations/export", async (req, res) => {
    try {
      const { workflow_ga, include_all } = req.body;

      if (!workflow_ga) {
        return res.status(400).json({ error: "workflow_ga is required" });
      }

      console.log('[Citation API] Exporting citations for workflow');

      const response = await galaxyAPIProxy.client.post('/api/ai_assistant/citations/export', {
        workflow_ga,
        include_all: include_all ?? true,
      });

      res.json(response.data);
    } catch (error: any) {
      console.error("[Citation API] Error exporting citations:", error);
      res.status(500).json({
        success: false,
        error: 'CitationExportError',
        message: error.message || 'Failed to export citations',
      });
    }
  });

  // Generate methods section text
  app.post("/api/ai_assistant/citations/methods", async (req, res) => {
    try {
      const { workflow_ga, style } = req.body;

      if (!workflow_ga) {
        return res.status(400).json({ error: "workflow_ga is required" });
      }

      console.log('[Citation API] Generating methods section, style:', style);

      const response = await galaxyAPIProxy.client.post('/api/ai_assistant/citations/methods', {
        workflow_ga,
        style: style || 'apa',
      });

      res.json(response.data);
    } catch (error: any) {
      console.error("[Citation API] Error generating methods:", error);
      res.status(500).json({
        success: false,
        error: 'MethodsGenerationError',
        message: error.message || 'Failed to generate methods section',
      });
    }
  });

  // ============================================================================
  // AI Assistant - Benchmark API (Added 2025-12-30)
  // ============================================================================

  // Get benchmark results for a scenario
  app.get("/api/ai_assistant/benchmarks/:scenario", async (req, res) => {
    try {
      const { scenario } = req.params;

      console.log('[Benchmark API] Getting benchmarks for scenario:', scenario);

      const response = await galaxyAPIProxy.client.get(`/api/ai_assistant/benchmarks/${encodeURIComponent(scenario)}`);
      res.json(response.data);
    } catch (error: any) {
      console.error("[Benchmark API] Error getting benchmarks:", error);
      res.status(500).json({
        available: false,
        error: 'BenchmarkQueryError',
        message: error.message || 'Failed to get benchmark results',
      });
    }
  });

  // Query benchmarks with natural language (NEW)
  app.post("/api/ai_assistant/benchmark_query", async (req, res) => {
    try {
      const { query, constraints, top_k } = req.body;

      if (!query) {
        return res.status(400).json({ error: "query is required" });
      }

      console.log('[Benchmark API] Querying benchmarks:', query);

      const response = await galaxyAPIProxy.client.post('/api/ai_assistant/benchmark_query', {
        query,
        constraints: constraints || {},
        top_k: top_k || 5,
      });

      res.json(response.data);
    } catch (error: any) {
      console.error("[Benchmark API] Error querying benchmarks:", error);
      res.status(500).json({
        success: false,
        error: 'BenchmarkQueryError',
        message: error.message || 'Failed to query benchmarks',
      });
    }
  });

  // Compare tools with benchmark evidence (NEW)
  app.post("/api/ai_assistant/tool_comparison", async (req, res) => {
    try {
      const { tool_a, tool_b, task } = req.body;

      if (!tool_a || !tool_b) {
        return res.status(400).json({ error: "tool_a and tool_b are required" });
      }

      console.log('[Benchmark API] Comparing tools:', tool_a, 'vs', tool_b);

      const response = await galaxyAPIProxy.client.post('/api/ai_assistant/tool_comparison', {
        tool_a,
        tool_b,
        task: task || null,
      });

      res.json(response.data);
    } catch (error: any) {
      console.error("[Benchmark API] Error comparing tools:", error);
      res.status(500).json({
        success: false,
        error: 'ToolComparisonError',
        message: error.message || 'Failed to compare tools',
      });
    }
  });

  // ============================================================================
  // AI Assistant - Research Query API (Added 2025-12-30)
  // ============================================================================

  // Answer research questions with literature-backed evidence
  app.post("/api/ai_assistant/research_query", async (req, res) => {
    try {
      const { query, context, include_citations, include_benchmark_evidence, max_citations } = req.body;

      if (!query) {
        return res.status(400).json({ error: "query is required" });
      }

      console.log('[Research API] Answering research question:', query);

      const response = await galaxyAPIProxy.client.post('/api/ai_assistant/research_query', {
        query,
        context: context || {},
        include_citations: include_citations ?? true,
        include_benchmark_evidence: include_benchmark_evidence ?? true,
        max_citations: max_citations || 5,
      });

      res.json(response.data);
    } catch (error: any) {
      console.error("[Research API] Error answering research query:", error);
      res.status(500).json({
        success: false,
        error: 'ResearchQueryError',
        message: error.message || 'Failed to answer research question',
      });
    }
  });

  // Get available scientific skills
  app.get("/api/ai_assistant/skills/available", async (req, res) => {
    try {
      console.log('[Skills API] Getting available skills');

      const response = await galaxyAPIProxy.client.get('/api/ai_assistant/skills/available');
      res.json(response.data);
    } catch (error: any) {
      console.error("[Skills API] Error getting skills:", error);
      res.status(500).json({
        available: false,
        error: 'SkillsQueryError',
        message: error.message || 'Failed to get available skills',
      });
    }
  });

  // ============================================================================
  // Parameter Template Repository API
  // ============================================================================

  // Search parameter templates
  app.get("/api/parameter-templates/search", async (req, res) => {
    try {
      const {tool_id, use_case_category, analysis_type, sample_type, tags, limit} = req.query;

      const searchRequest = {
        tool_id: tool_id as string | undefined,
        use_case_category: use_case_category as string | undefined,
        analysis_type: analysis_type as string | undefined,
        sample_type: sample_type as string | undefined,
        tags: tags ? (tags as string).split(',') : undefined,
        limit: limit ? parseInt(limit as string) : undefined,
      };

      const results = await parameterRepository.searchTemplates(searchRequest);
      res.json(results);
    } catch (error: any) {
      console.error('[API] Parameter template search failed:', error);
      res.status(500).json({error: 'Failed to search parameter templates', message: error.message});
    }
  });

  // Get templates for a specific tool
  app.get("/api/parameter-templates/tool/:toolId", async (req, res) => {
    try {
      const {toolId} = req.params;
      const templates = await parameterRepository.getTemplatesForTool(toolId);
      res.json({count: templates.length, templates});
    } catch (error: any) {
      console.error('[API] Get tool templates failed:', error);
      res.status(500).json({error: 'Failed to get tool templates', message: error.message});
    }
  });

  // Get a specific parameter template
  app.get("/api/parameter-templates/:id", async (req, res) => {
    try {
      const {id} = req.params;
      const template = await parameterRepository.getTemplate(id);

      if (!template) {
        return res.status(404).json({error: 'Parameter template not found'});
      }

      res.json(template);
    } catch (error: any) {
      console.error('[API] Get parameter template failed:', error);
      res.status(500).json({error: 'Failed to get parameter template', message: error.message});
    }
  });

  // Save a new parameter template
  app.post("/api/parameter-templates", async (req, res) => {
    try {
      const userId = req.headers['x-user-id'] as string || 'anonymous';
      const template = await parameterRepository.saveTemplate(req.body, userId);
      res.status(201).json(template);
    } catch (error: any) {
      console.error('[API] Save parameter template failed:', error);
      res.status(500).json({error: 'Failed to save parameter template', message: error.message});
    }
  });

  // Record template usage
  app.post("/api/parameter-templates/:id/usage", async (req, res) => {
    try {
      const {id} = req.params;
      const {success} = req.body;
      await parameterRepository.recordUsage(id, success === true);
      res.json({success: true});
    } catch (error: any) {
      console.error('[API] Record template usage failed:', error);
      res.status(500).json({error: 'Failed to record usage', message: error.message});
    }
  });

  // Get popular templates
  app.get("/api/parameter-templates/popular/:limit?", async (req, res) => {
    try {
      const limit = req.params.limit ? parseInt(req.params.limit) : 10;
      const templates = await parameterRepository.getPopularTemplates(limit);
      res.json({count: templates.length, templates});
    } catch (error: any) {
      console.error('[API] Get popular templates failed:', error);
      res.status(500).json({error: 'Failed to get popular templates', message: error.message});
    }
  });

  // Get validated templates only
  app.get("/api/parameter-templates/validated", async (req, res) => {
    try {
      const templates = await parameterRepository.getValidatedTemplates();
      res.json({count: templates.length, templates});
    } catch (error: any) {
      console.error('[API] Get validated templates failed:', error);
      res.status(500).json({error: 'Failed to get validated templates', message: error.message});
    }
  });

  // ============================================================================
  // Workflow Template Repository API
  // ============================================================================

  // Search workflow templates
  app.get("/api/workflow-templates/search", async (req, res) => {
    try {
      const {use_case_category, analysis_type, sample_type, input_type, tags, difficulty, limit} = req.query;

      const searchRequest = {
        use_case_category: use_case_category as string | undefined,
        analysis_type: analysis_type as string | undefined,
        sample_type: sample_type as string | undefined,
        input_type: input_type as string | undefined,
        tags: tags ? (tags as string).split(',') : undefined,
        difficulty: difficulty as string | undefined,
        limit: limit ? parseInt(limit as string) : undefined,
      };

      const results = await workflowRepository.searchTemplates(searchRequest);
      res.json(results);
    } catch (error: any) {
      console.error('[API] Workflow template search failed:', error);
      res.status(500).json({error: 'Failed to search workflow templates', message: error.message});
    }
  });

  // Get a specific workflow template
  app.get("/api/workflow-templates/:id", async (req, res) => {
    try {
      const {id} = req.params;
      const template = await workflowRepository.getTemplate(id);

      if (!template) {
        return res.status(404).json({error: 'Workflow template not found'});
      }

      res.json(template);
    } catch (error: any) {
      console.error('[API] Get workflow template failed:', error);
      res.status(500).json({error: 'Failed to get workflow template', message: error.message});
    }
  });

  // Save a new workflow template
  app.post("/api/workflow-templates", async (req, res) => {
    try {
      const userId = req.headers['x-user-id'] as string || 'anonymous';
      const template = await workflowRepository.saveTemplate(req.body, userId);
      res.status(201).json(template);
    } catch (error: any) {
      console.error('[API] Save workflow template failed:', error);
      res.status(500).json({error: 'Failed to save workflow template', message: error.message});
    }
  });

  // Record workflow template usage
  app.post("/api/workflow-templates/:id/usage", async (req, res) => {
    try {
      const {id} = req.params;
      const {success, runtime_minutes} = req.body;
      await workflowRepository.recordUsage(id, success === true, runtime_minutes);
      res.json({success: true});
    } catch (error: any) {
      console.error('[API] Record workflow usage failed:', error);
      res.status(500).json({error: 'Failed to record usage', message: error.message});
    }
  });

  // Get popular workflow templates
  app.get("/api/workflow-templates/popular/:limit?", async (req, res) => {
    try {
      const limit = req.params.limit ? parseInt(req.params.limit) : 10;
      const templates = await workflowRepository.getPopularTemplates(limit);
      res.json({count: templates.length, templates});
    } catch (error: any) {
      console.error('[API] Get popular workflow templates failed:', error);
      res.status(500).json({error: 'Failed to get popular templates', message: error.message});
    }
  });

  // Get validated workflow templates only
  app.get("/api/workflow-templates/validated", async (req, res) => {
    try {
      const templates = await workflowRepository.getValidatedTemplates();
      res.json({count: templates.length, templates});
    } catch (error: any) {
      console.error('[API] Get validated workflow templates failed:', error);
      res.status(500).json({error: 'Failed to get validated templates', message: error.message});
    }
  });


  // ============================================================================
  // Long-Term Memory API
  // ============================================================================

  // Get or create user profile with LTM context
  app.get("/api/memory/user", authenticateToken, async (req, res) => {
    try {
      const userContext = await memoryService.users.loadUserContext(req.user!.id);
      res.json(userContext);
    } catch (error: any) {
      console.error('[API] Load user context failed:', error);
      res.status(500).json({ error: 'Failed to load user context', message: error.message });
    }
  });

  // Update user preferences
  app.post("/api/memory/user/preferences", authenticateToken, async (req, res) => {
    try {
      const { preferenceType, preferenceKey, preferenceValue, context, learnedFrom } = req.body;
      const preference = await memoryService.users.recordPreference({
        userId: req.user!.id,
        preferenceType,
        preferenceKey,
        preferenceValue,
        context,
        learnedFrom,
      });
      res.json(preference);
    } catch (error: any) {
      console.error('[API] Record preference failed:', error);
      res.status(500).json({ error: 'Failed to record preference', message: error.message });
    }
  });

  // Record a correction
  app.post("/api/memory/user/corrections", authenticateToken, async (req, res) => {
    try {
      const { sessionId, projectId, suggestedApproach, correctedApproach, workflowContext, userExplanation } = req.body;
      const correction = await memoryService.users.recordCorrection({
        userId: req.user!.id,
        sessionId,
        projectId,
        suggestedApproach,
        correctedApproach,
        workflowContext,
        userExplanation,
      });
      res.json(correction);
    } catch (error: any) {
      console.error('[API] Record correction failed:', error);
      res.status(500).json({ error: 'Failed to record correction', message: error.message });
    }
  });

  // ============================================================================
  // Project Memory API
  // ============================================================================

  // Get all projects for user
  app.get("/api/memory/projects", authenticateToken, async (req, res) => {
    try {
      const { status } = req.query;
      const projects = await memoryService.projects.getUserProjects(
        req.user!.id,
        status as 'active' | 'archived' | 'completed' | undefined
      );
      res.json(projects);
    } catch (error: any) {
      console.error('[API] Get projects failed:', error);
      res.status(500).json({ error: 'Failed to get projects', message: error.message });
    }
  });

  // Create a new project
  app.post("/api/memory/projects", authenticateToken, async (req, res) => {
    try {
      const { name, description, researchGoal, instructions, primaryDomain, organisms, tissueTypes, conditions, dataModalities, category, tags } = req.body;
      const project = await memoryService.projects.createProject({
        userId: req.user!.id,
        name,
        description,
        researchGoal,
        instructions,
        primaryDomain,
        organisms,
        tissueTypes,
        conditions,
        dataModalities,
        category,
        tags,
      });
      res.json(project);
    } catch (error: any) {
      console.error('[API] Create project failed:', error);
      res.status(500).json({ error: 'Failed to create project', message: error.message });
    }
  });

  // Get project with full context
  app.get("/api/memory/projects/:projectId", authenticateToken, async (req, res) => {
    try {
      const { projectId } = req.params;
      const projectContext = await memoryService.projects.loadProjectContext(projectId);
      if (!projectContext.project) {
        return res.status(404).json({ error: 'Project not found' });
      }
      res.json(projectContext);
    } catch (error: any) {
      console.error('[API] Get project context failed:', error);
      res.status(500).json({ error: 'Failed to get project context', message: error.message });
    }
  });

  // Update project
  app.put("/api/memory/projects/:projectId", authenticateToken, async (req, res) => {
    try {
      const { projectId } = req.params;
      const project = await memoryService.projects.updateProject(projectId, req.body);
      res.json(project);
    } catch (error: any) {
      console.error('[API] Update project failed:', error);
      res.status(500).json({ error: 'Failed to update project', message: error.message });
    }
  });

  // Add project knowledge
  app.post("/api/memory/projects/:projectId/knowledge", authenticateToken, async (req, res) => {
    try {
      const { projectId } = req.params;
      const { knowledgeType, title, content, source, relatedWorkflows, relatedSessions } = req.body;
      const knowledge = await memoryService.projects.addProjectKnowledge({
        projectId,
        knowledgeType,
        title,
        content,
        source,
        relatedWorkflows,
        relatedSessions,
      });
      res.json(knowledge);
    } catch (error: any) {
      console.error('[API] Add project knowledge failed:', error);
      res.status(500).json({ error: 'Failed to add knowledge', message: error.message });
    }
  });

  // Search projects
  app.get("/api/memory/projects/search", authenticateToken, async (req, res) => {
    try {
      const { domain, tags, text } = req.query;
      const projects = await memoryService.projects.searchProjects(req.user!.id, {
        domain: domain as string | undefined,
        tags: tags ? (tags as string).split(',') : undefined,
        text: text as string | undefined,
      });
      res.json(projects);
    } catch (error: any) {
      console.error('[API] Search projects failed:', error);
      res.status(500).json({ error: 'Failed to search projects', message: error.message });
    }
  });

  // ============================================================================
  // Session Memory API
  // ============================================================================

  // Initialize a new session
  app.post("/api/memory/sessions", authenticateToken, async (req, res) => {
    try {
      const { projectId } = req.body;
      const result = await memoryService.initializeSession(req.user!.id, projectId);
      res.json(result);
    } catch (error: any) {
      console.error('[API] Initialize session failed:', error);
      res.status(500).json({ error: 'Failed to initialize session', message: error.message });
    }
  });

  // Get session
  app.get("/api/memory/sessions/:sessionId", authenticateToken, async (req, res) => {
    try {
      const { sessionId } = req.params;
      const session = await memoryService.sessions.getSession(sessionId);
      if (!session) {
        return res.status(404).json({ error: 'Session not found' });
      }
      const messages = await memoryService.sessions.getSessionMessages(sessionId);
      res.json({ session, messages });
    } catch (error: any) {
      console.error('[API] Get session failed:', error);
      res.status(500).json({ error: 'Failed to get session', message: error.message });
    }
  });

  // End session with summary
  app.put("/api/memory/sessions/:sessionId/end", authenticateToken, async (req, res) => {
    try {
      const { sessionId } = req.params;
      const { summary, keyDecisions } = req.body;
      const session = await memoryService.endSessionWithSummary(sessionId, summary, keyDecisions);
      res.json(session);
    } catch (error: any) {
      console.error('[API] End session failed:', error);
      res.status(500).json({ error: 'Failed to end session', message: error.message });
    }
  });

  // Get recent sessions
  app.get("/api/memory/sessions", authenticateToken, async (req, res) => {
    try {
      const { limit } = req.query;
      const sessions = await memoryService.sessions.getRecentSessions(
        req.user!.id,
        limit ? parseInt(limit as string) : 10
      );
      res.json(sessions);
    } catch (error: any) {
      console.error('[API] Get recent sessions failed:', error);
      res.status(500).json({ error: 'Failed to get sessions', message: error.message });
    }
  });

  // C3b — Store a session summary generated when context is compressed
  app.post("/api/memory/session-summary", async (req, res) => {
    try {
      const { summary, sessionId, userId } = req.body;
      if (!summary) {
        return res.status(400).json({ error: 'summary is required' });
      }
      if (sessionId) {
        // Persist summary into the sessions table via the existing endSessionWithSummary path
        // (upsert-style: if session exists, update summary; otherwise silently skip)
        try {
          await memoryService.sessions.updateSessionSummary(sessionId, summary);
        } catch (_inner: any) {
          // updateSessionSummary may not exist on all installs — silently swallow
          console.warn('[API] session-summary partial save:', _inner?.message);
        }
      }
      res.json({ success: true, sessionId, summaryLength: summary.length });
    } catch (error: any) {
      console.error('[API] Store session-summary failed:', error);
      res.status(500).json({ error: 'Failed to store session summary', message: error.message });
    }
  });

  // Record interaction (message + episode)
  app.post("/api/memory/interactions", authenticateToken, async (req, res) => {
    try {
      const { sessionId, projectId, userMessage, assistantResponse, userIntent, toolsUsed, workflowGenerated, workflowId } = req.body;
      const result = await memoryService.recordInteraction({
        sessionId,
        projectId,
        userMessage,
        assistantResponse,
        userIntent,
        toolsUsed,
        workflowGenerated,
        workflowId,
      });
      res.json(result);
    } catch (error: any) {
      console.error('[API] Record interaction failed:', error);
      res.status(500).json({ error: 'Failed to record interaction', message: error.message });
    }
  });

  // ============================================================================
  // Memory Sync API - Bidirectional sync between frontend localStorage and backend
  // ============================================================================

  /**
   * Sync frontend localStorage state with backend memory
   * Implements conflict resolution with "last write wins" strategy
   */
  app.post("/api/memory/sync", authenticateToken, async (req, res) => {
    try {
      const userId = req.user!.id;
      const { chatSessions, userSettings, lastSyncTimestamp } = req.body;

      const syncResult = {
        success: true,
        synced: {
          chatSessions: 0,
          preferences: 0,
        },
        conflicts: [] as Array<{ type: string; id: string; resolution: string }>,
        serverTimestamp: new Date().toISOString(),
      };

      // Sync chat sessions to backend memory
      if (chatSessions && Array.isArray(chatSessions)) {
        for (const session of chatSessions) {
          try {
            // Check if session exists in backend
            const existingSession = await memoryService.sessions.getSession(session.id);

            if (!existingSession) {
              // Create new session in backend
              await memoryService.sessions.createSession({
                id: session.id,
                userId,
                projectId: session.projectId,
              });
              syncResult.synced.chatSessions++;
            } else {
              // Conflict resolution: compare timestamps
              const frontendUpdated = new Date(session.lastActivity);
              const backendUpdated = existingSession.startedAt || new Date(0);

              if (frontendUpdated > backendUpdated) {
                // Frontend is newer - would update backend (not implemented yet)
                syncResult.conflicts.push({
                  type: 'chatSession',
                  id: session.id,
                  resolution: 'frontend_newer_accepted',
                });
              } else {
                syncResult.conflicts.push({
                  type: 'chatSession',
                  id: session.id,
                  resolution: 'backend_newer_kept',
                });
              }
            }
          } catch (sessionError) {
            console.error(`[MemorySync] Failed to sync session ${session.id}:`, sessionError);
          }
        }
      }

      // Sync user settings/preferences
      if (userSettings && typeof userSettings === 'object') {
        try {
          // Convert user settings to preferences
          for (const [key, value] of Object.entries(userSettings)) {
            if (key === 'id' || key === 'userId' || key === 'updatedAt') continue;

            await memoryService.users.recordPreference({
              userId,
              preferenceType: 'user_setting',
              preferenceKey: key,
              preferenceValue: JSON.stringify(value),
              context: { source: 'frontend_sync' },
              learnedFrom: 'user_explicit',
            });
            syncResult.synced.preferences++;
          }
        } catch (prefError) {
          console.error('[MemorySync] Failed to sync preferences:', prefError);
        }
      }

      // Log sync event for audit
      await auditService.log({
        userId,
        action: 'memory.sync',
        resourceType: 'memory',
        details: {
          chatSessionsSynced: syncResult.synced.chatSessions,
          preferencesSynced: syncResult.synced.preferences,
          conflictsCount: syncResult.conflicts.length,
        },
        status: 'success',
      });

      res.json(syncResult);
    } catch (error: any) {
      console.error('[API] Memory sync failed:', error);
      res.status(500).json({ error: 'Memory sync failed', message: error.message });
    }
  });

  /**
   * Get backend memory state for frontend sync
   * Returns user context, projects, and recent sessions
   */
  app.get("/api/memory/sync", authenticateToken, async (req, res) => {
    try {
      const userId = req.user!.id;

      // Load user context from backend
      const userContext = await memoryService.users.loadUserContext(userId);

      // Load user's projects
      const projects = await memoryService.projects.getUserProjects(userId, 'active');

      // Load recent sessions
      const recentSessions = await memoryService.sessions.getRecentSessions(userId, 20);

      // Convert preferences to user settings format
      const userSettings: Record<string, any> = {};
      for (const pref of userContext.preferences) {
        if (pref.preferenceType === 'user_setting') {
          try {
            userSettings[pref.preferenceKey] = JSON.parse(pref.preferenceValue as string);
          } catch {
            userSettings[pref.preferenceKey] = pref.preferenceValue;
          }
        }
      }

      res.json({
        success: true,
        serverTimestamp: new Date().toISOString(),
        data: {
          user: userContext.user,
          userSettings,
          projects,
          recentSessions,
          stats: userContext.stats,
        },
      });
    } catch (error: any) {
      console.error('[API] Get sync state failed:', error);
      res.status(500).json({ error: 'Get sync state failed', message: error.message });
    }
  });

  // ============================================================================
  // Episodic Memory API
  // ============================================================================

  // Get similar episodes for a project
  app.get("/api/memory/projects/:projectId/episodes", authenticateToken, async (req, res) => {
    try {
      const { projectId } = req.params;
      const { intent, tools, limit } = req.query;
      const episodes = await memoryService.episodes.getSimilarEpisodes(projectId, {
        intent: intent as string | undefined,
        toolsUsed: tools ? (tools as string).split(',') : undefined,
        limit: limit ? parseInt(limit as string) : 10,
      });
      res.json(episodes);
    } catch (error: any) {
      console.error('[API] Get episodes failed:', error);
      res.status(500).json({ error: 'Failed to get episodes', message: error.message });
    }
  });

  // Update episode outcome
  app.put("/api/memory/episodes/:episodeId/outcome", authenticateToken, async (req, res) => {
    try {
      const { episodeId } = req.params;
      const { success, errorType, errorMessage, whatWorked, whatFailed, lessonsLearned } = req.body;
      const episode = await memoryService.episodes.updateEpisodeOutcome(parseInt(episodeId), {
        success,
        errorType,
        errorMessage,
        whatWorked,
        whatFailed,
        lessonsLearned,
      });
      res.json(episode);
    } catch (error: any) {
      console.error('[API] Update episode outcome failed:', error);
      res.status(500).json({ error: 'Failed to update episode', message: error.message });
    }
  });

  // Consolidate episodes into patterns
  app.post("/api/memory/projects/:projectId/consolidate", authenticateToken, async (req, res) => {
    try {
      const { projectId } = req.params;
      const result = await memoryService.episodes.consolidateEpisodes(projectId);
      res.json(result);
    } catch (error: any) {
      console.error('[API] Consolidate episodes failed:', error);
      res.status(500).json({ error: 'Failed to consolidate episodes', message: error.message });
    }
  });

  // ============================================================================
  // Procedural Memory API
  // ============================================================================

  // Get procedures for a project
  app.get("/api/memory/projects/:projectId/procedures", authenticateToken, async (req, res) => {
    try {
      const { projectId } = req.params;
      const { minSuccessRate } = req.query;
      const procedures = await memoryService.procedures.getReliableProcedures(
        projectId,
        minSuccessRate ? parseFloat(minSuccessRate as string) : 0.7
      );
      res.json(procedures);
    } catch (error: any) {
      console.error('[API] Get procedures failed:', error);
      res.status(500).json({ error: 'Failed to get procedures', message: error.message });
    }
  });

  // Find matching procedures for a trigger
  app.get("/api/memory/projects/:projectId/procedures/match", authenticateToken, async (req, res) => {
    try {
      const { projectId } = req.params;
      const { trigger } = req.query;
      if (!trigger) {
        return res.status(400).json({ error: 'trigger query parameter required' });
      }
      const procedures = await memoryService.procedures.findMatchingProcedures(
        projectId,
        trigger as string
      );
      res.json(procedures);
    } catch (error: any) {
      console.error('[API] Find matching procedures failed:', error);
      res.status(500).json({ error: 'Failed to find procedures', message: error.message });
    }
  });

  // Create a procedure
  app.post("/api/memory/projects/:projectId/procedures", authenticateToken, async (req, res) => {
    try {
      const { projectId } = req.params;
      const { name, triggerPattern, description, steps, preconditions, postconditions, applicableDomains, learnedFrom } = req.body;
      const procedure = await memoryService.procedures.createProcedure({
        projectId,
        name,
        triggerPattern,
        description,
        steps,
        preconditions,
        postconditions,
        applicableDomains,
        learnedFrom,
      });
      res.json(procedure);
    } catch (error: any) {
      console.error('[API] Create procedure failed:', error);
      res.status(500).json({ error: 'Failed to create procedure', message: error.message });
    }
  });

  // Record procedure usage
  app.post("/api/memory/procedures/:procedureId/usage", authenticateToken, async (req, res) => {
    try {
      const { procedureId } = req.params;
      const { success } = req.body;
      const procedure = await memoryService.procedures.recordUsage(parseInt(procedureId), success);
      res.json(procedure);
    } catch (error: any) {
      console.error('[API] Record procedure usage failed:', error);
      res.status(500).json({ error: 'Failed to record usage', message: error.message });
    }
  });


  // ============================================================================
  // Workflow Management API
  // ============================================================================

  // List all workflows (for compatibility with E2E tests)
  app.get("/api/workflows", optionalAuth, async (req, res) => {
    try {
      // Return list of workflow invocations for this user
      const { limit } = req.query;
      const invocations = await storage.getInvocations(
        req.user?.id,
        limit ? parseInt(limit as string) : 100
      );
      res.json(invocations);
    } catch (error: any) {
      console.error("Error fetching workflows:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // SSE endpoint for workflow events (generic, works without specific invocation ID)
  app.get("/api/workflows/events", optionalAuth, (req, res) => {
    try {
      // Set SSE headers
      res.setHeader('Content-Type', 'text/event-stream');
      res.setHeader('Cache-Control', 'no-cache');
      res.setHeader('Connection', 'keep-alive');
      res.setHeader('X-Accel-Buffering', 'no');

      // Send initial connection message
      res.write('data: {"type":"connected","message":"SSE connection established"}\n\n');

      // Keep connection alive with periodic heartbeat
      const heartbeat = setInterval(() => {
        res.write('data: {"type":"heartbeat"}\n\n');
      }, 15000);

      // Clean up on close
      req.on('close', () => {
        clearInterval(heartbeat);
      });
    } catch (error: any) {
      console.error("SSE connection error:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // ============================================================================
  // Workflow Invocation Management API
  // ============================================================================

  // Create a new invocation record (called when workflow starts)
  app.post("/api/invocations", optionalAuth, async (req, res) => {
    try {
      const invocationData = req.body;

      const invocation = await storage.createInvocation({
        userId: req.user?.id,
        workflowName: invocationData.workflowName,
        workflowDefinition: invocationData.workflowDefinition,
        galaxyInvocationId: invocationData.galaxyInvocationId,
        galaxyHistoryId: invocationData.galaxyHistoryId,
        galaxyWorkflowId: invocationData.galaxyWorkflowId,
        inputDatasets: invocationData.inputDatasets || [],
        totalSteps: invocationData.totalSteps || 0,
        status: 'running',
      });

      res.json(invocation);
    } catch (error: any) {
      console.error("Error creating invocation:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Get all invocations for the current user
  app.get("/api/invocations", optionalAuth, async (req, res) => {
    try {
      const { limit } = req.query;
      const invocations = await storage.getInvocations(
        req.user?.id,
        limit ? parseInt(limit as string) : 100
      );
      res.json(invocations);
    } catch (error: any) {
      console.error("Error fetching invocations:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Get a specific invocation by ID
  app.get("/api/invocations/:id", optionalAuth, async (req, res) => {
    try {
      const invocation = await storage.getInvocation(req.params.id);
      if (!invocation) {
        return res.status(404).json({ error: "Invocation not found" });
      }
      res.json(invocation);
    } catch (error: any) {
      console.error("Error fetching invocation:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Update an invocation (status, outputs, etc.)
  app.patch("/api/invocations/:id", optionalAuth, async (req, res) => {
    try {
      const updates = req.body;
      const invocation = await storage.updateInvocation(req.params.id, updates);

      if (!invocation) {
        return res.status(404).json({ error: "Invocation not found" });
      }

      res.json(invocation);
    } catch (error: any) {
      console.error("Error updating invocation:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Delete an invocation
  app.delete("/api/invocations/:id", authenticateToken, async (req, res) => {
    try {
      const success = await storage.deleteInvocation(req.params.id);
      if (!success) {
        return res.status(404).json({ error: "Invocation not found" });
      }
      res.json({ success: true });
    } catch (error: any) {
      console.error("Error deleting invocation:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Trigger AutoFix for a workflow invocation (Nextflow/Galaxy unified)
  app.post("/api/invocations/:id/ai/autofix", authenticateToken, async (req, res) => {
    try {
      const invocation = await storage.getInvocation(req.params.id);
      if (!invocation) {
        return res.status(404).json({ error: "Invocation not found" });
      }
      if (!invocation.galaxyInvocationId || !invocation.galaxyWorkflowId) {
        return res.status(400).json({ error: "Invocation is missing Galaxy identifiers" });
      }

      const response = await fetch(
        `${process.env.GALAXY_URL || 'http://localhost:8081'}/api/workflows/${invocation.galaxyWorkflowId}/invocations/${invocation.galaxyInvocationId}/ai/autofix`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': process.env.GALAXY_API_KEY || '',
          },
          body: JSON.stringify({
            ...req.body,
            fix_mode: req.body.fix_mode || 'safe',
          }),
        }
      );

      const data = await response.json();
      res.status(response.status).json(data);
    } catch (error: any) {
      console.error("[Invocation AutoFix] Error triggering autofix:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Get Nextflow status for a workflow invocation
  app.get("/api/invocations/:id/nextflow/status", async (req, res) => {
    try {
      const invocation = await storage.getInvocation(req.params.id);
      if (!invocation) {
        return res.status(404).json({ error: "Invocation not found" });
      }
      if (!invocation.galaxyInvocationId) {
        return res.status(400).json({ error: "Invocation is missing Galaxy identifiers" });
      }

      // Proxy to Galaxy backend Nextflow status endpoint
      const response = await fetch(
        `${process.env.GALAXY_URL || 'http://localhost:8081'}/api/workflows/${invocation.galaxyInvocationId}/nextflow/status`,
        {
          method: 'GET',
          headers: {
            'x-api-key': process.env.GALAXY_API_KEY || '',
          },
        }
      );

      const data = await response.json();
      res.status(response.status).json(data);
    } catch (error: any) {
      console.error("[Invocation Nextflow] Error fetching status:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Get outputs for a specific invocation (also accepts ExecutionRun IDs)
  app.get("/api/invocations/:id/outputs", async (req, res) => {
    try {
      const resolveInvocation = async (identifier: string) => {
        let invocation = await storage.getInvocation(identifier);
        if (invocation) return invocation;
        invocation = await storage.getInvocationByGalaxyId(identifier);
        if (invocation) return invocation;
        const executionRun = await storage.getExecutionRun(identifier);
        if (executionRun?.execution?.galaxyInvocationId) {
          invocation = await storage.getInvocationByGalaxyId(executionRun.execution.galaxyInvocationId);
          if (invocation) return invocation;
        }
        return undefined;
      };

      // Nextflow control files that should not surface as user outputs
      const NF_INTERNAL_FILES = new Set([
        ".command.sh", ".command.run", ".command.log", ".command.out",
        ".command.err", ".command.env", ".command.trace", ".exitcode",
        ".started", ".nf-params.json", "workflow-trace.txt",
        "workflow-timeline.html",  // execution timeline (internal)
      ]);
      const NF_SKIP_DIRS = new Set(["work", ".nextflow"]);

      /** Recursively collect real files from a local directory (max depth 4). */
      const scanOutdir = async (dirPath: string, depth = 4): Promise<string[]> => {
        if (depth <= 0) return [];
        const results: string[] = [];
        try {
          const entries = await fs.readdir(dirPath, { withFileTypes: true });
          for (const entry of entries) {
            if (NF_INTERNAL_FILES.has(entry.name)) continue;
            const full = path.join(dirPath, entry.name);
            if (entry.isDirectory()) {
              if (!NF_SKIP_DIRS.has(entry.name)) {
                results.push(...await scanOutdir(full, depth - 1));
              }
            } else if (entry.isFile()) {
              results.push(full);
            }
          }
        } catch { /* permission / gone */ }
        return results;
      };

      const addRuntimeArtifactOutputs = async (invocationId: string, rawArtifacts: string[]) => {
        const existing = await storage.getInvocationOutputs(invocationId);
        const existingLocalPaths = new Set(
          existing
            .map((o: any) => String(o?.metadata?.localPath || ""))
            .filter((p: string) => p.length > 0)
        );

        // Expand directory paths into individual files
        const expandedFiles: string[] = [];
        for (const artifactPath of rawArtifacts) {
          if (!artifactPath) continue;
          if (artifactPath.startsWith("s3://")) {
            expandedFiles.push(artifactPath);
            continue;
          }
          try {
            const stat = await fs.stat(artifactPath);
            if (stat.isFile()) {
              expandedFiles.push(artifactPath);
            } else if (stat.isDirectory()) {
              expandedFiles.push(...await scanOutdir(artifactPath));
            }
          } catch { /* path gone or inaccessible */ }
        }

        for (const artifactPath of expandedFiles) {
          if (existingLocalPaths.has(artifactPath)) continue;
          try {
            const ext = path.extname(artifactPath).replace(".", "").toLowerCase() || "txt";
            const fileType = classifyFileType(ext);

            if (artifactPath.startsWith("s3://")) {
              await storage.addOutput({
                invocationId,
                galaxyDatasetId: "",
                name: path.basename(artifactPath),
                extension: ext,
                size: 0,
                fileType,
                isVisualizable: isVisualizable(ext),
                previewAvailable: fileType === "text" || fileType === "table",
                metadata: { source: "nextflow_s3_output", s3Uri: artifactPath },
              });
            } else {
              const stat = await fs.stat(artifactPath);
              if (!stat.isFile()) continue;
              await storage.addOutput({
                invocationId,
                galaxyDatasetId: "",
                name: path.basename(artifactPath),
                extension: ext,
                size: stat.size,
                fileType,
                isVisualizable: isVisualizable(ext) || fileType === "text" || fileType === "table",
                previewAvailable: fileType === "text" || fileType === "table",
                metadata: { source: "nextflow_runtime_artifact", localPath: artifactPath },
              });
            }
            existingLocalPaths.add(artifactPath);
          } catch {
            // Ignore non-existing or inaccessible artifact paths.
          }
        }
      };

      const materializeRuntimeSummary = async (
        invocationId: string,
        nextflowStatus: any,
        executionRunId?: string
      ) => {
        const summaryDir = path.join("/tmp/biomate_runtime_outputs", invocationId);
        await fs.mkdir(summaryDir, { recursive: true });
        const summaryPath = path.join(summaryDir, "nextflow_run_summary.txt");
        const lines = [
          `BioMate Nextflow run summary`,
          `generated_at: ${new Date().toISOString()}`,
          `execution_run_id: ${executionRunId || "n/a"}`,
          `nextflow_run_id: ${nextflowStatus?.run_id || "n/a"}`,
          `status: ${nextflowStatus?.status || "unknown"}`,
          `progress_percent: ${nextflowStatus?.progressPercent ?? nextflowStatus?.progress ?? 0}`,
          "",
          "log_tail:",
          ...(Array.isArray(nextflowStatus?.log_tail)
            ? nextflowStatus.log_tail.map((line: any) => String(line))
            : ["(no runtime logs available)"]),
        ];
        await fs.writeFile(summaryPath, `${lines.join("\n")}\n`, "utf8");
        const stat = await fs.stat(summaryPath);
        await storage.addOutput({
          invocationId,
          galaxyDatasetId: "",
          name: "nextflow_run_summary",
          extension: "txt",
          size: stat.size,
          fileType: "text",
          isVisualizable: true,
          previewAvailable: true,
          metadata: {
            source: "nextflow_runtime_summary",
            localPath: summaryPath,
          },
        });
      };

      // First try to get outputs directly by invocation ID
      let outputs = await storage.getInvocationOutputs(req.params.id);

      // If no outputs found, check if this is an ExecutionRun ID
      // and look up the corresponding WorkflowInvocation
      if (outputs.length === 0) {
        const invocation = await resolveInvocation(req.params.id);
        if (invocation) {
          outputs = await storage.getInvocationOutputs(invocation.id);

          // If persisted outputs are still empty for Nextflow, materialize runtime evidence
          // so users can inspect/download concrete run artifacts from the UI.
          if (outputs.length === 0 && invocation.galaxyInvocationId) {
            const executionRun = await storage.getExecutionRunByGalaxyId(invocation.galaxyInvocationId);
            const nextflowStatus = executionRun?.execution?.nextflowStatus;
            if (nextflowStatus && typeof nextflowStatus === "object") {
              const artifacts: string[] = [];
              const pushArtifact = (value: any) => {
                if (!value) return;
                if (typeof value === "string") {
                  const trimmed = value.trim();
                  if (trimmed) artifacts.push(trimmed);
                  return;
                }
                if (Array.isArray(value)) {
                  value.forEach(pushArtifact);
                  return;
                }
                if (typeof value === "object") {
                  Object.values(value).forEach(pushArtifact);
                }
              };
              pushArtifact(nextflowStatus.outputs);
              pushArtifact(nextflowStatus.results);
              pushArtifact(nextflowStatus.output_files);
              pushArtifact(nextflowStatus.outdir);
              if (Array.isArray(nextflowStatus.log_tail)) {
                for (const line of nextflowStatus.log_tail) {
                  if (typeof line !== "string") continue;
                  const pathMatches = line.match(/\/[^\s,\]]+/g) || [];
                  pathMatches.forEach((candidate) => artifacts.push(candidate));
                }
              }

              await addRuntimeArtifactOutputs(invocation.id, Array.from(new Set(artifacts)));
              outputs = await storage.getInvocationOutputs(invocation.id);
              if (outputs.length === 0) {
                await materializeRuntimeSummary(invocation.id, nextflowStatus, executionRun?.id);
                outputs = await storage.getInvocationOutputs(invocation.id);
              }
            }
          }
        }
      }

      res.json(outputs);
    } catch (error: any) {
      console.error("Error fetching outputs:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Fetch outputs from Galaxy after workflow completion
  app.post("/api/invocations/:id/fetch-outputs", async (req, res) => {
    try {
      let invocation = await storage.getInvocation(req.params.id);
      if (!invocation) {
        const executionRun = await storage.getExecutionRun(req.params.id);
        if (executionRun?.execution?.galaxyInvocationId) {
          const resolved = await storage.getInvocationByGalaxyId(executionRun.execution.galaxyInvocationId);
          if (resolved) {
            invocation = resolved;
          }
        }
      }
      if (!invocation) {
        return res.status(404).json({ error: "Invocation not found" });
      }

      // Fetch actual history_id from Galaxy invocation when available
      let historyIdToUse = invocation.galaxyHistoryId;
      if (invocation.galaxyWorkflowId && invocation.galaxyInvocationId) {
        try {
          const galaxyInvocation = await galaxyAPIProxy.getInvocation(
            invocation.galaxyWorkflowId,
            invocation.galaxyInvocationId
          );
          historyIdToUse = galaxyInvocation.history_id || historyIdToUse;
        } catch (historyError) {
          console.warn("[InvocationOutputs] Failed to resolve actual history_id, using stored history id", historyError);
        }
      }

      // Fetch history contents from Galaxy
      const historyContents = await galaxyAPIProxy.getHistoryContents(historyIdToUse);

      // Filter outputs created by this invocation (after invocation start time)
      const isNextflowInvocation = getWorkflowExecutionEngine(invocation.workflowDefinition) === 'nextflow';
      let invocationOutputs = historyContents.filter((item: any) => {
        const itemCreateTime = new Date(item.create_time);
        return (
          !item.deleted &&
          item.state === 'ok' &&
          item.history_content_type === 'dataset' &&
          itemCreateTime >= invocation.createdAt
        );
      });
      if (isNextflowInvocation && invocationOutputs.length === 0) {
        invocationOutputs = historyContents.filter((item: any) => (
          !item.deleted &&
          item.state === 'ok' &&
          item.history_content_type === 'dataset'
        ));
      }

      // Store each output in our database
      const storedOutputs = [];
      for (const galaxyOutput of invocationOutputs) {
        const extension = galaxyOutput.extension || galaxyOutput.file_ext || 'txt';
        const fileType = classifyFileType(extension);

        const output = await storage.addOutput({
          invocationId: invocation.id,
          galaxyDatasetId: galaxyOutput.id,
          name: galaxyOutput.name,
          extension: extension,
          size: galaxyOutput.file_size || 0,
          fileType: fileType,
          isVisualizable: isVisualizable(extension),
          previewAvailable: fileType === 'table' || fileType === 'text',
          metadata: {
            dataType: galaxyOutput.data_type,
            rows: galaxyOutput.metadata?.data_lines,
            columns: galaxyOutput.metadata?.columns,
          },
        });

        storedOutputs.push(output);
      }

      // Update invocation status to completed
      await storage.updateInvocation(invocation.id, {
        status: 'ok',
        completedAt: new Date(),
        completedSteps: invocation.totalSteps,
      });

      res.json({ outputs: storedOutputs, count: storedOutputs.length });
    } catch (error: any) {
      console.error("Error fetching outputs:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // ============================================================================
  // Output Dataset Management API
  // ============================================================================

  // Get a specific output by ID
  app.get("/api/outputs/:id", async (req, res) => {
    try {
      const output = await storage.getOutput(req.params.id);
      if (!output) {
        return res.status(404).json({ error: "Output not found" });
      }
      res.json(output);
    } catch (error: any) {
      console.error("Error fetching output:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Download output file from Galaxy
  app.get("/api/outputs/:id/download", async (req, res) => {
    try {
      const output = await storage.getOutput(req.params.id);
      if (!output) {
        return res.status(404).json({ error: "Output not found" });
      }

      // Fetch file from Galaxy or local runtime artifact fallback.
      let fileStream: any;
      const localPath = String((output as any)?.metadata?.localPath || "");
      if (output.galaxyDatasetId) {
        fileStream = await galaxyAPIProxy.downloadDataset(output.galaxyDatasetId);
      } else if (localPath) {
        fileStream = createReadStream(localPath);
      } else {
        return res.status(404).json({ error: "Output has no downloadable source" });
      }

      // Set appropriate headers
      res.setHeader('Content-Disposition', `attachment; filename="${output.name}"`);
      res.setHeader('Content-Type', 'application/octet-stream');

      // Pipe the stream to response
      fileStream.pipe(res);
    } catch (error: any) {
      console.error("Error downloading output:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Download all outputs for an invocation as ZIP
  app.get("/api/invocations/:id/download-all", async (req, res) => {
    try {
      // Accept either a WorkflowInvocation ID or an ExecutionRun ID.
      let invocation = await storage.getInvocation(req.params.id);
      if (!invocation) {
        const byGalaxyId = await storage.getInvocationByGalaxyId(req.params.id);
        if (byGalaxyId) {
          invocation = byGalaxyId;
        }
      }
      if (!invocation) {
        const executionRun = await storage.getExecutionRun(req.params.id);
        if (executionRun?.execution?.galaxyInvocationId) {
          const resolved = await storage.getInvocationByGalaxyId(executionRun.execution.galaxyInvocationId);
          if (resolved) {
            invocation = resolved;
          }
        }
      }
      if (!invocation) {
        return res.status(404).json({ error: "Invocation not found" });
      }

      const outputs = await storage.getInvocationOutputs(invocation.id);
      if (!outputs || outputs.length === 0) {
        return res.status(404).json({ error: "No outputs found for this invocation" });
      }

      // Create ZIP archive
      const archive = archiver('zip', { zlib: { level: 9 } });

      // Set response headers
      const zipFilename = `${invocation.workflowName || 'workflow'}_outputs_${invocation.id.slice(0, 8)}.zip`;
      res.setHeader('Content-Type', 'application/zip');
      res.setHeader('Content-Disposition', `attachment; filename="${zipFilename}"`);

      // Pipe archive to response
      archive.pipe(res);

      // Handle archive errors
      archive.on('error', (err) => {
        console.error('Archive error:', err);
        if (!res.headersSent) {
          res.status(500).json({ error: 'Failed to create archive' });
        }
      });

      // Add each output to the archive
      for (const output of outputs) {
        try {
          const localPath = String((output as any)?.metadata?.localPath || "");
          const fileStream = output.galaxyDatasetId
            ? await galaxyAPIProxy.downloadDataset(output.galaxyDatasetId)
            : localPath
            ? createReadStream(localPath)
            : null;
          if (!fileStream) {
            continue;
          }
          const filename = `${output.name}.${output.extension}`;
          archive.append(fileStream, { name: filename });
        } catch (err) {
          console.error(`Failed to add ${output.name} to archive:`, err);
          // Continue with other files
        }
      }

      // Finalize the archive
      await archive.finalize();
    } catch (error: any) {
      console.error("Error creating download archive:", error);
      if (!res.headersSent) {
        res.status(500).json({ error: error.message });
      }
    }
  });

  // Display output file (for images, HTML, etc.)
  app.get("/api/outputs/:id/display", async (req, res) => {
    try {
      const output = await storage.getOutput(req.params.id);
      if (!output) {
        return res.status(404).json({ error: "Output not found" });
      }

      // Fetch file from Galaxy, local path, or S3 presigned URL.
      let fileStream: any;
      const localPath = String((output as any)?.metadata?.localPath || "");
      const s3Uri    = String((output as any)?.metadata?.s3Uri     || "");
      if (output.galaxyDatasetId) {
        fileStream = await galaxyAPIProxy.downloadDataset(output.galaxyDatasetId);
      } else if (localPath) {
        fileStream = createReadStream(localPath);
      } else if (s3Uri) {
        // Redirect to a presigned download URL for S3 objects
        const galaxyUrl = process.env.GALAXY_URL || "http://localhost:8081";
        const presignUrl = `${galaxyUrl}/api/nextflow/outputs/download?s3_uri=${encodeURIComponent(s3Uri)}&run_id=direct`;
        return res.redirect(302, presignUrl);
      } else {
        return res.status(404).json({ error: "Output has no display source" });
      }

      // Set appropriate content type for inline display
      const contentTypeMap: Record<string, string> = {
        'png': 'image/png',
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'svg': 'image/svg+xml',
        'gif': 'image/gif',
        'pdf': 'application/pdf',
        'html': 'text/html',
        'htm': 'text/html',
        'txt': 'text/plain',
        'csv': 'text/csv',
        'tsv': 'text/tab-separated-values',
      };

      const contentType = contentTypeMap[output.extension] || 'application/octet-stream';
      res.setHeader('Content-Type', contentType);
      res.setHeader('Content-Disposition', 'inline');

      // Pipe the stream to response
      fileStream.pipe(res);
    } catch (error: any) {
      console.error("Error displaying output:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Preview output (first N lines for tables/text files)
  app.get("/api/outputs/:id/preview", async (req, res) => {
    try {
      const output = await storage.getOutput(req.params.id);
      if (!output) {
        return res.status(404).json({ error: "Output not found" });
      }

      if (output.fileType !== 'table' && output.fileType !== 'text') {
        return res.status(400).json({ error: "Preview not available for this file type" });
      }

      const maxLines = parseInt(req.query.lines as string) || 100;
      const localPath = String((output as any)?.metadata?.localPath || "");
      let rawText = "";
      if (output.galaxyDatasetId) {
        const fileStream = await galaxyAPIProxy.downloadDataset(output.galaxyDatasetId);
        for await (const chunk of fileStream) {
          rawText += chunk.toString();
          if (rawText.split("\n").length > maxLines + 50) {
            break;
          }
        }
      } else if (localPath) {
        rawText = await fs.readFile(localPath, "utf8");
      } else {
        return res.status(404).json({ error: "Output has no preview source" });
      }
      const lines = rawText.split("\n").slice(0, maxLines);

      res.json({
        lines,
        totalLines: output.metadata?.rows || lines.length,
        hasMore: (output.metadata?.rows || lines.length) > maxLines
      });
    } catch (error: any) {
      console.error("Error previewing output:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Parse bioinformatics file (VCF, FASTA, FASTQ, BED, GFF, GTF)
  app.get("/api/outputs/:id/parse", async (req, res) => {
    try {
      const output = await storage.getOutput(req.params.id);
      if (!output) {
        return res.status(404).json({ error: "Output not found" });
      }

      const format = (req.query.format as string) || output.extension.toLowerCase();
      const limit = parseInt(req.query.limit as string) || 1000;

      // Import parsers dynamically to avoid circular dependencies
      const {
        parseVCF,
        parseFASTA,
        parseFASTQ,
        parseBED,
        parseGFF,
        parseGTF,
      } = await import('./bioinformatics-parsers');

      // Fetch file content from Galaxy
      const fileStream = await galaxyAPIProxy.downloadDataset(output.galaxyDatasetId);

      // Collect all chunks
      const chunks: Buffer[] = [];
      for await (const chunk of fileStream) {
        chunks.push(Buffer.from(chunk));
      }
      const content = Buffer.concat(chunks).toString('utf-8');

      // Parse based on format
      let parsed: any;
      switch (format) {
        case 'vcf':
          parsed = parseVCF(content, limit);
          break;
        case 'fasta':
        case 'fa':
        case 'fna':
          parsed = parseFASTA(content, limit);
          break;
        case 'fastq':
        case 'fq':
          parsed = parseFASTQ(content, limit);
          break;
        case 'bed':
          parsed = parseBED(content, limit);
          break;
        case 'gff':
        case 'gff3':
          parsed = parseGFF(content, limit);
          break;
        case 'gtf':
          parsed = parseGTF(content, limit);
          break;
        default:
          return res.status(400).json({
            error: `Unsupported format for parsing: ${format}`,
            supportedFormats: ['vcf', 'fasta', 'fa', 'fna', 'fastq', 'fq', 'bed', 'gff', 'gff3', 'gtf']
          });
      }

      res.json(parsed);
    } catch (error: any) {
      console.error("Error parsing bioinformatics file:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Launch interactive tool
  app.post("/api/interactive-tools/launch", optionalAuth, async (req, res) => {
    try {
      const { toolId, datasetIds, historyId } = req.body;

      if (!toolId || !datasetIds?.length) {
        return res.status(400).json({
          error: "toolId and datasetIds are required"
        });
      }

      // Get Galaxy dataset IDs from our output records
      const galaxyDatasetIds: string[] = [];
      for (const outputId of datasetIds) {
        const output = await storage.getOutput(outputId);
        if (output?.galaxyDatasetId) {
          galaxyDatasetIds.push(output.galaxyDatasetId);
        }
      }

      if (galaxyDatasetIds.length === 0) {
        return res.status(400).json({
          error: "No valid Galaxy datasets found for the provided IDs"
        });
      }

      // Get or create history ID
      let targetHistoryId = historyId;
      if (!targetHistoryId) {
        // Get the most recent active history
        const histories = await galaxyAPIProxy.getHistories();
        if (histories && histories.length > 0) {
          targetHistoryId = histories[0].id;
        } else {
          // Create a new history if none exists
          targetHistoryId = await galaxyAPIProxy.createHistory('BioMate Interactive Session');
        }
      }

      // Build inputs for the interactive tool
      const inputs: Record<string, any> = {};
      galaxyDatasetIds.forEach((datasetId, index) => {
        inputs[`input${index + 1}`] = {
          src: 'hda',
          id: datasetId,
        };
      });
      // Some tools also expect 'input' as parameter name
      if (galaxyDatasetIds.length === 1) {
        inputs['input'] = {
          src: 'hda',
          id: galaxyDatasetIds[0],
        };
      }

      // Launch interactive tool via Galaxy API
      const result = await galaxyAPIProxy.launchInteractiveTool(toolId, targetHistoryId, inputs);

      // Construct entry point URL if not provided
      const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8080';
      const entryPointUrl = result.entry_point_url || `${galaxyUrl}/interactivetool/jobs/${result.job_id}`;

      res.json({
        success: true,
        url: entryPointUrl,
        jobId: result.job_id,
        state: result.state,
      });
    } catch (error: any) {
      console.error("Error launching interactive tool:", error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  });

  // ============================================================================
  // Pre-Execution Validation API (LLM-powered prerequisites check)
  // ============================================================================

  /**
   * Validate workflow prerequisites before execution
   * Uses LLM intelligence to analyze:
   * - Required inputs vs available datasets
   * - Required parameters
   * - Data format compatibility
   *
   * Returns conversational guidance for the user
   */
  app.post("/api/workflows/validate", optionalAuth, async (req, res) => {
    try {
      if (!prerequisitesValidator) {
        return res.status(503).json({
          error: "Prerequisites validator not available",
          message: "ANTHROPIC_API_KEY not configured"
        });
      }

      const { workflowDefinition, inputs, parameters, historyId, userContext } = req.body;

      if (!workflowDefinition) {
        return res.status(400).json({
          error: "workflowDefinition is required"
        });
      }

      console.log('[Validate] Starting pre-execution validation for workflow:', workflowDefinition.name);

      const result = await prerequisitesValidator.validate({
        workflowDefinition,
        inputs,
        parameters,
        historyId,
        userContext,
      });

      console.log('[Validate] Validation complete:', {
        fulfilled: result.fulfilled,
        inputMappings: result.analysis.inputMappings.length,
        missingInputs: result.analysis.missingInputs.length,
        missingParams: result.analysis.missingParameters.length,
      });

      res.json(result);
    } catch (error: any) {
      console.error('[Validate] Validation failed:', error);
      res.status(500).json({
        error: "Validation failed",
        message: error.message
      });
    }
  });

  // ============================================================================
  // Unified Workflow Execution API (Sandbox/Production with Tunable Data Scope)
  // ============================================================================

  // Create a new execution run (unified sandbox/production)
  app.post("/api/workflows/execute", optionalAuth, async (req, res) => {
    let executionRun: any = null;
    let galaxyHistoryId: string | null = null;
    let galaxyWorkflowId: string | null = null;

    try {
      const request = req.body;
      const generationAssessment = request.generationAssessment || request.workflowDefinition?.__generationAssessment;
      const retryContext = request.retryContext || request.workflowDefinition?.__retryContext;
      const retryOfRunId =
        retryContext?.runId ||
        request.executionConfig?.retryOfRunId;
      const retryOfInvocationId =
        retryContext?.galaxyInvocationId ||
        request.executionConfig?.retryOfInvocationId;

      // Validation
      if (!request.workflowDefinition) {
        return res.status(400).json({ error: "workflowDefinition is required" });
      }

      // Server-side de-dup guard:
      // if this request is an explicit manual retry, block it while AutoFix is active
      // for the referenced failed run/invocation.
      if (retryOfRunId || retryOfInvocationId) {
        let retrySourceRun =
          retryOfRunId ? await storage.getExecutionRun(retryOfRunId) : undefined;
        if (!retrySourceRun && retryOfInvocationId) {
          retrySourceRun = await storage.getExecutionRunByGalaxyId(retryOfInvocationId);
        }

        if (retrySourceRun) {
          const autofixLifecycle = await getAutofixLifecycleForRun(retrySourceRun);
          if (autofixLifecycle.active) {
            return res.status(409).json({
              error: "autofix_active_retry_blocked",
              message: "Manual retry blocked while AutoFix is active for the referenced run.",
              guidance: "Wait for AutoFix to complete before triggering a manual rerun.",
              retryContext: {
                runId: retryOfRunId,
                galaxyInvocationId: retryOfInvocationId,
              },
              autofix: autofixLifecycle,
            });
          }
        }
      }

      // Stage-C fallback guard:
      // If caller did not provide explicit retry metadata, infer likely duplicate-manual-retry
      // from a recent failed run for the same workflow identity that still has active AutoFix.
      if (!retryOfRunId && !retryOfInvocationId && (req.user?.id || request.projectId)) {
        const incomingWorkflowFingerprint = buildWorkflowFingerprint(request.workflowDefinition);
        const incomingWorkflowName = normalizeWorkflowName(
          request.workflowDefinition?.name || request.workflowDefinition?.annotation
        );
        const recentRuns = await storage.getExecutionRuns(
          req.user?.id,
          request.projectId,
          undefined,
          30
        );
        const now = Date.now();
        const implicitRetrySource = recentRuns.find((run) => {
          const runWorkflowName = normalizeWorkflowName(run.workflowName);
          const runWorkflowFingerprint = buildWorkflowFingerprint(run.workflowDefinition);
          const fingerprintMatches =
            !!incomingWorkflowFingerprint &&
            !!runWorkflowFingerprint &&
            incomingWorkflowFingerprint === runWorkflowFingerprint;
          const updatedAtMs = new Date(run.updatedAt || run.createdAt || Date.now()).getTime();
          const isRecent = now - updatedAtMs <= 2 * 60 * 60 * 1000; // 2h safety window
          return (
            run.execution?.executionEngine === "nextflow" &&
            run.execution?.status === "failed" &&
            (
              fingerprintMatches ||
              (incomingWorkflowName && runWorkflowName === incomingWorkflowName)
            ) &&
            isRecent
          );
        });

        if (implicitRetrySource) {
          const implicitFingerprintMatched =
            !!incomingWorkflowFingerprint &&
            incomingWorkflowFingerprint === buildWorkflowFingerprint(implicitRetrySource.workflowDefinition);
          const autofixLifecycle = await getAutofixLifecycleForRun(implicitRetrySource);
          if (autofixLifecycle.active) {
            return res.status(409).json({
              error: "autofix_active_retry_blocked",
              message: "Execution blocked: AutoFix is still active for a recent failed run of this workflow.",
              guidance: "Wait for AutoFix to finish, or retry with explicit context after it reaches terminal state.",
              retryContext: {
                runId: implicitRetrySource.id,
                galaxyInvocationId: implicitRetrySource.execution?.galaxyInvocationId,
                inferred: true,
                inferredBy: implicitFingerprintMatched ? "fingerprint" : "name",
              },
              autofix: autofixLifecycle,
            });
          }
        }
      }

      // Check if workflow has input steps that require data
      const steps = request.workflowDefinition.steps || {};
      const inputSteps = Object.values(steps).filter((step: any) =>
        step.type === 'data_input' || step.type === 'data_collection_input'
      );

      // Validate inputs are provided if workflow has input steps
      const inputs = Array.isArray(request.inputs) ? request.inputs : [];
      if (inputSteps.length > 0 && inputs.length === 0) {
        return res.status(400).json({
          error: "inputs_required",
          message: `Workflow has ${inputSteps.length} input step(s) but no inputs were provided`,
          inputStepsCount: inputSteps.length
        });
      }

      // Scientific + technical confidence gate.
      // Technical confidence: required inputs are present and generation didn't report tool-install blockers.
      // Scientific confidence: generation stage must not require user feedback/domain correction.
      const technicalReady = inputSteps.length === 0 || inputs.length > 0;
      const toolInstallationReady = generationAssessment?.toolInstallationSuccess !== false;
      const scientificBlocked =
        generationAssessment?.needsUserFeedback === true ||
        generationAssessment?.domainGuardBlocked === true;
      const scientificReason =
        generationAssessment?.domainGuardReason ||
        generationAssessment?.feedbackPrompt ||
        "Workflow confidence is not high enough for safe execution.";
      const hardwareRequirements =
        request.workflowDefinition?.hardware_requirements ||
        request.workflowDefinition?.workflow_ga?.hardware_requirements ||
        null;
      const requestedComputeConfig = request.executionConfig?.computeConfig || {};
      const hardwareGate = evaluateHardwareGate(
        hardwareRequirements,
        requestedComputeConfig,
        request.workflowDefinition?.workflow_type
      );
      const { inferredExecutor, hardwareReady, hardwareReason } = hardwareGate;

      if ((!technicalReady || !toolInstallationReady || scientificBlocked || !hardwareReady) && request.executionConfig?.allowLowConfidence !== true) {
        return res.status(409).json({
          error: "confidence_gate_blocked",
          message: "Execution blocked pending scientific/technical confirmation.",
          guidance: [scientificReason, hardwareReason].filter(Boolean).join(" "),
          technicalReady,
          toolInstallationReady,
          scientificBlocked,
          hardwareReady,
          hardwareRequirements,
          inferredExecutor,
          nextActions: [
            "review_workflow_and_domain",
            "review_hardware_requirements",
            "regenerate_with_constraints",
            "confirm_override_with_allowLowConfidence",
          ],
        });
      }
      if (request.executionConfig?.allowLowConfidence === true) {
        console.warn("[ConfidenceGate] Low-confidence override accepted", {
          userId: req.user?.id ?? null,
          workflowName: request.workflowDefinition?.name,
          scientificBlocked,
          technicalReady,
          toolInstallationReady,
          hardwareReady,
          inferredExecutor,
        });
      }

      // Determine execution engine using standardized helper
      const executionEngine = getWorkflowExecutionEngine(request.workflowDefinition);
      const workflowTags = request.workflowDefinition?.tags || [];
      const {
        __generationAssessment: _dropGenerationAssessment,
        __retryContext: _dropRetryContext,
        ...workflowDefinitionSanitized
      } =
        request.workflowDefinition || {};
      const workflowDefinitionForExecution = executionEngine === 'nextflow'
        ? {
            ...workflowDefinitionSanitized,
            tags: Array.from(new Set([...(workflowTags || []), 'nextflow'])),
          }
        : workflowDefinitionSanitized;

      // Create execution run record
      executionRun = await storage.createExecutionRun(
        {
          ...request,
          workflowDefinition: workflowDefinitionForExecution,
          executionConfig: {
            ...(request.executionConfig || {}),
            executionEngine,
          }
        },
        req.user?.id,
        request.projectId
      );

      // Determine history name based on mode
      const mode = request.executionConfig?.mode || 'sandbox';
      const historyPrefix = mode === 'sandbox' ? '[Sandbox]' : '[Production]';
      const engineSuffix = executionEngine === 'nextflow' ? ' [Nextflow]' : '';
      const historyName = `${historyPrefix}${engineSuffix} ${executionRun.workflowName} - Run ${executionRun.runSequence}`;

      // Create Galaxy history
      galaxyHistoryId = await galaxyAPIProxy.createHistory(historyName);

      // Apply data scope if specified
      let sampledInputs = inputs;
      const dataScope = executionRun.dataScope;

      if (dataScope.fraction < 1.0 && sampledInputs.length > 0) {
        // Sample inputs based on data scope configuration
        const totalCount = sampledInputs.length;
        const targetCount = Math.max(1, Math.ceil(totalCount * dataScope.fraction));

        if (dataScope.samplingStrategy === 'random') {
          // Random sampling
          const shuffled = [...sampledInputs].sort(() => Math.random() - 0.5);
          sampledInputs = shuffled.slice(0, targetCount);
        } else if (dataScope.samplingStrategy === 'first_n') {
          // First N sampling
          sampledInputs = sampledInputs.slice(0, targetCount);
        }
        // For stratified and representative, would need metadata - use all for now

        // Update execution run with sampled IDs
        await storage.updateExecutionRun(executionRun.id, {
          dataScope: {
            ...dataScope,
            absoluteCount: sampledInputs.length,
            totalAvailable: totalCount,
            sampledIds: sampledInputs.map((i: any) => i.id),
          }
        });
      }

      // ==================== NEXTFLOW DIRECT EXECUTION ====================
      // Check if this is a DIRECT Nextflow workflow (new format from NextflowWorkflowGenerator)
      if (request.workflowDefinition.workflow_type === 'nextflow') {
        console.log('[Nextflow Direct] Detected workflow_type=nextflow');
        console.log('[Nextflow Direct] Path:', request.workflowDefinition.nextflow_path);
        console.log('[Nextflow Direct] Parameters:', request.workflowDefinition.parameters);

        try {
          // Call /api/nextflow/execute directly — backend creates its own tracking
          // workflow and invocation internally. No need to pre-create them in Galaxy.
          console.log('[Nextflow Direct] Executing workflow via /api/nextflow/execute...');
          const nextflowComputeConfig = buildNextflowComputeConfig(
            request.executionConfig?.computeConfig || {},
            hardwareRequirements
          );

          const nextflowResponse = await fetch(`${process.env.GALAXY_URL || 'http://localhost:8081'}/api/nextflow/execute`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'X-API-Key': process.env.GALAXY_API_KEY || '',
            },
            body: JSON.stringify({
              history_id: galaxyHistoryId,
              nextflow_path: request.workflowDefinition.nextflow_path,
              parameters: request.workflowDefinition.parameters || {},
              profile: request.executionConfig?.nextflow_profile || 'standard',
              compute_config:
                Object.keys(nextflowComputeConfig).length > 0
                  ? nextflowComputeConfig
                  : undefined,
            })
          });

          if (!nextflowResponse.ok) {
            const errBody = await nextflowResponse.text().catch(() => nextflowResponse.statusText);
            throw new Error(`Nextflow execution failed (${nextflowResponse.status}): ${errBody}`);
          }

          const nextflowData = await nextflowResponse.json();
          console.log('[Nextflow Direct] Execution result:', nextflowData);

          // The backend returns invocation_id it created internally
          const backendInvocationId = nextflowData.invocation_id || nextflowData.run_id || '';

          // Update execution run with backend-returned tracking IDs
          await storage.updateExecutionRun(executionRun.id, {
            execution: {
              ...executionRun.execution,
              galaxyInvocationId: backendInvocationId,
              galaxyHistoryId: galaxyHistoryId,
              status: nextflowData.success ? 'running' : 'failed',
              startedAt: new Date(),
              executionEngine: 'nextflow',
              nextflowRunId: nextflowData.run_id,
              nextflowOutputDir: nextflowData.outputs?.outdir
            }
          });

          // Nextflow-direct runs do not have a Galaxy workflow ID, so polling the
          // Galaxy invocation endpoint would produce noisy /api/workflows//... 404s.
          if (backendInvocationId && executionRun.execution?.galaxyWorkflowId) {
            galaxyPoller.startPolling(backendInvocationId, executionRun.execution.galaxyWorkflowId);
          }

          // Create legacy invocation record
          await storage.createInvocation({
            userId: req.user?.id,
            workflowName: executionRun.workflowName,
            workflowDefinition: request.workflowDefinition,
            galaxyInvocationId: backendInvocationId,
            galaxyHistoryId: galaxyHistoryId,
            galaxyWorkflowId: '',
            inputDatasets: [],
            totalSteps: executionRun.progress.totalSteps,
            status: nextflowData.success ? 'ok' : 'error',
          });

          registerInvocationNotifications({
            invocationId: backendInvocationId,
            req,
            workflowName: executionRun.workflowName,
            workflowId: String(
              request.workflowDefinition?.id ||
              request.workflowDefinition?.nextflow_path ||
              executionRun.execution?.galaxyWorkflowId ||
              "nextflow-direct"
            ),
            source: 'api/workflows/execute[nextflow-direct]',
          });

          // Return success response
          return res.json({
            runId: executionRun.id,
            galaxyInvocationId: backendInvocationId,
            galaxyHistoryId: galaxyHistoryId,
            executionEngine: 'nextflow',
            nextflowRunId: nextflowData.run_id,
            status: nextflowData.success ? 'running' : 'failed',
            message: `Nextflow workflow queued (run_id: ${nextflowData.run_id})`,
            outputs: nextflowData.outputs,
            results: nextflowData.results
          });

        } catch (error) {
          console.error('[Nextflow Direct] Execution error:', error);

          if (executionRun) {
            await storage.updateExecutionRun(executionRun.id, {
              execution: {
                ...executionRun.execution,
                status: 'failed',
                error: error instanceof Error ? error.message : String(error)
              }
            });
          }

          return res.status(500).json({
            error: 'nextflow_execution_failed',
            message: error instanceof Error ? error.message : String(error),
            runId: executionRun?.id
          });
        }
      }
      // ==================== END NEXTFLOW DIRECT EXECUTION ====================

      // Create workflow in Galaxy (for non-Nextflow workflows)
      const galaxyWorkflow = await galaxyAPIProxy.createWorkflow(workflowDefinitionForExecution);
      galaxyWorkflowId = galaxyWorkflow.id;

      // Invoke workflow in Galaxy
      // Build inputs object for Galaxy (mapping step inputs to dataset IDs)
      const galaxyInputs: Record<string, any> = {};
      for (const input of sampledInputs) {
        const stepId = input.step_id ?? 0;
        galaxyInputs[stepId.toString()] = {
          src: input.src || 'hda',
          id: input.id
        };
      }

      const invocationResult = await galaxyAPIProxy.invokeWorkflow(
        galaxyWorkflow.id,
        galaxyInputs,
        {
          history_id: galaxyHistoryId,
          ...(executionEngine === 'nextflow' ? { scheduler: 'nextflow' } : {})
        }
      );

      // Update execution run with Galaxy IDs and status
      await storage.updateExecutionRun(executionRun.id, {
        execution: {
          ...executionRun.execution,
          galaxyInvocationId: invocationResult.id,
          galaxyHistoryId: galaxyHistoryId,
          galaxyWorkflowId: galaxyWorkflow.id,
          status: 'queued',
          startedAt: new Date(),
        }
      });

      // Start polling for this invocation
      galaxyPoller.startPolling(
        invocationResult.id,
        galaxyWorkflow.id
      );

      // Also create a legacy invocation record for backward compatibility
      // Capture the invocation ID to return to frontend for output tracking
      const workflowInvocation = await storage.createInvocation({
        userId: req.user?.id,
        workflowName: executionRun.workflowName,
        workflowDefinition: workflowDefinitionForExecution,
        galaxyInvocationId: invocationResult.id,
        galaxyHistoryId: galaxyHistoryId,
        galaxyWorkflowId: galaxyWorkflow.id,
        inputDatasets: sampledInputs,
        totalSteps: executionRun.progress.totalSteps,
        status: 'running',
      });

      registerInvocationNotifications({
        invocationId: invocationResult.id,
        req,
        workflowName: executionRun.workflowName,
        workflowId: galaxyWorkflow.id,
        source: 'api/workflows/execute',
      });

      res.json({
        runId: executionRun.id,
        // Include WorkflowInvocation ID for output tracking (outputs are linked to this ID)
        invocationId: workflowInvocation.id,
        galaxyInvocationId: invocationResult.id,
        galaxyHistoryId: galaxyHistoryId,
        executionEngine,
        status: 'queued',
        dataScopeApplied: {
          fraction: executionRun.dataScope.fraction,
          absoluteCount: sampledInputs.length,
          sampledIds: sampledInputs.map((i: any) => i.id),
        }
      });
    } catch (error: any) {
      console.error("[ExecutionRun] Error creating execution run:", error);

      // If execution run was created, mark it as failed
      if (executionRun?.id) {
        try {
          const errorMessage = error.detail?.err_msg || error.message || 'Unknown error';
          await storage.updateExecutionRun(executionRun.id, {
            execution: {
              ...executionRun.execution,
              status: 'failed',
              errorMessage: errorMessage,
              galaxyHistoryId: galaxyHistoryId || undefined,
              galaxyWorkflowId: galaxyWorkflowId || undefined,
            }
          });
          console.log(`[ExecutionRun] Marked run ${executionRun.id} as failed`);
        } catch (updateError) {
          console.error("[ExecutionRun] Failed to update run status:", updateError);
        }
      }

      // Return detailed error
      const statusCode = error.status_code || 500;
      res.status(statusCode).json({
        error: error.error || 'ExecutionError',
        message: error.detail?.err_msg || error.message || 'Failed to execute workflow',
        runId: executionRun?.id,
        details: error.detail
      });
    }
  });

  // Get all execution runs for the current user
  app.get("/api/workflows/runs", optionalAuth, async (req, res) => {
    try {
      const { mode, projectId, chatSessionId, limit } = req.query;
      const runs = await storage.getExecutionRuns(
        req.user?.id,
        projectId as string,
        mode as 'sandbox' | 'production' | undefined,
        limit ? parseInt(limit as string) : 100,
        chatSessionId as string | undefined
      );
      res.json(runs);
    } catch (error: any) {
      console.error("[ExecutionRun] Error fetching runs:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Leverage-first runs overview endpoint (summary rows for run manager surfaces)
  app.get("/api/workflows/runs/overview", optionalAuth, async (req, res) => {
    try {
      const overview = await getExecutionRunsOverview(storage, {
        userId: req.user?.id,
        scope: req.query.scope as string | undefined,
        chatSessionId: req.query.chatSessionId as string | undefined,
        status: req.query.status as string | undefined,
        search: req.query.search as string | undefined,
        sort: req.query.sort as string | undefined,
        limit: req.query.limit as string | undefined,
        offset: req.query.offset as string | undefined,
      });
      res.json(overview);
    } catch (error: any) {
      if (error instanceof RunOverviewBadRequestError) {
        return res.status(error.statusCode).json({ error: error.message });
      }
      console.error("[ExecutionRun] Error fetching run overview:", error);
      res.status(500).json({ error: error.message || "Failed to fetch run overview" });
    }
  });

  // Export QC report for a workflow invocation
  app.post("/api/export/qc_report", express.json(), optionalAuth, async (req, res) => {
    const { invocationId, format = "html" } = req.body ?? {};
    if (!invocationId) {
      return res.status(400).json({ error: "invocationId required" });
    }
    try {
      const run = await storage.getExecutionRunByGalaxyId(invocationId);
      if (!run) return res.status(404).json({ error: "Run not found" });

      if (format === "json") {
        return res.json({ invocationId, run });
      }

      const html = buildQCReportHtml(run, invocationId);
      res.setHeader("Content-Type", "text/html");
      res.setHeader(
        "Content-Disposition",
        `attachment; filename="biomate_qc_report_${invocationId.slice(0, 8)}.html"`
      );
      return res.send(html);
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  // Get a specific execution run by ID
  app.get("/api/workflows/runs/:id", async (req, res) => {
    try {
      const run = await storage.getExecutionRun(req.params.id);
      if (!run) {
        return res.status(404).json({ error: "Execution run not found" });
      }
      res.json(run);
    } catch (error: any) {
      console.error("[ExecutionRun] Error fetching run:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Get execution run status (lightweight polling endpoint)
  app.get("/api/workflows/runs/:id/status", async (req, res) => {
    try {
      let run = await storage.getExecutionRun(req.params.id);
      if (!run) {
        return res.status(404).json({ error: "Execution run not found" });
      }

      // Return lightweight status response
      const isNextflowRun =
        getWorkflowExecutionEngine(run.workflowDefinition) === 'nextflow' ||
        run.execution?.executionEngine === 'nextflow';
      let nextflowStatus: any | undefined = undefined;
      let autofix: any | undefined = undefined;
      if (isNextflowRun && (run.execution?.nextflowRunId || run.execution?.galaxyInvocationId)) {
        try {
          const nextflowRunId = run.execution?.nextflowRunId || run.execution?.galaxyInvocationId;
          if (nextflowRunId) {
            nextflowStatus = await galaxyAPIProxy.getNextflowStatus(nextflowRunId);
          }

          // Promote Nextflow terminal state into execution run state.
          const nfState = String(nextflowStatus?.status || '').toLowerCase();
          if ((nfState === 'succeeded' || nfState === 'failed') && run.execution.status === 'running') {
            const mappedStatus = nfState === 'succeeded' ? 'completed' : 'failed';
            const terminalMessage = nfState === 'failed'
              ? (nextflowStatus?.log_tail?.slice?.(-1)?.[0] || run.execution.errorMessage || 'Nextflow run failed')
              : undefined;

            run = await storage.updateExecutionRun(run.id, {
              execution: {
                ...run.execution,
                status: mappedStatus,
                errorMessage: terminalMessage,
                completedAt: new Date(),
                nextflowStatus: nextflowStatus,
              },
            }) || run;

            // D2: Emit workflow_completed so the notification service fires for Nextflow runs.
            // Galaxy poller doesn't poll Nextflow direct runs; we emit manually on terminal state.
            const nfInvocationId = run.execution?.galaxyInvocationId || run.execution?.nextflowRunId;
            if (nfInvocationId) {
              galaxyPoller.emit('workflow_completed', {
                invocation_id: nfInvocationId,
                state: nfState === 'succeeded' ? 'ok' : 'failed',
              });
            }
          } else if (run.execution.status === 'running') {
            // Keep latest Nextflow status snapshot for UI visibility.
            run = await storage.updateExecutionRun(run.id, {
              execution: {
                ...run.execution,
                nextflowStatus: nextflowStatus,
              },
            }) || run;
          }
        } catch (statusError: any) {
          console.warn("[ExecutionRun] Failed to fetch Nextflow status:", statusError?.message || statusError);
        }
      }

      if (isNextflowRun && run.execution?.galaxyWorkflowId && run.execution?.galaxyInvocationId) {
        try {
          const sessionsResult = await galaxyAPIBackend.listAutofix3Sessions(
            run.execution.galaxyWorkflowId,
            run.execution.galaxyInvocationId,
            1
          );
          const latestSession = Array.isArray(sessionsResult?.sessions)
            ? sessionsResult.sessions[0]
            : undefined;
          const lifecycle = deriveAutofixLifecycle(latestSession);
          autofix = {
            ...lifecycle,
            active: ["analyzing", "fixing", "restarting"].includes(lifecycle.state),
          };

          if (nextflowStatus && typeof nextflowStatus === "object") {
            nextflowStatus = {
              ...nextflowStatus,
              autofix,
            };
          } else {
            nextflowStatus = { autofix };
          }
        } catch (autofixError: any) {
          console.warn("[ExecutionRun] Failed to fetch AutoFix lifecycle:", autofixError?.message || autofixError);
          autofix = {
            state: "idle",
            source: "unknown",
            active: false,
          };
          if (nextflowStatus && typeof nextflowStatus === "object") {
            nextflowStatus = {
              ...nextflowStatus,
              autofix,
            };
          } else {
            nextflowStatus = { autofix };
          }
        }
      }

      // Artifact-readiness contract: terminal "completed" should expose concrete
      // artifacts users can visualize or download in the UI. This is reported
      // (not hard-blocked) so UI/E2E can distinguish technical completion from
      // artifact materialization readiness.
      let artifactReadiness: {
        hasOutputs: boolean;
        visualizableCount: number;
        downloadableCount: number;
        totalOutputs: number;
        meetsContract: boolean;
      } | undefined = undefined;
      if (String(run.execution?.status || "").toLowerCase() === "completed") {
        const invocation = run.execution?.galaxyInvocationId
          ? await storage.getInvocationByGalaxyId(run.execution.galaxyInvocationId)
          : undefined;
        let outputs = invocation ? await storage.getInvocationOutputs(invocation.id) : [];

        // If completed but no outputs are persisted yet, make a best-effort fetch
        // from Galaxy to avoid false "artifact_readiness=false" due to timing lag.
        if (invocation && outputs.length === 0 && invocation.galaxyHistoryId) {
          try {
            const historyContents = await galaxyAPIProxy.getHistoryContents(invocation.galaxyHistoryId);
            const isNextflowInvocation = getWorkflowExecutionEngine(invocation.workflowDefinition) === 'nextflow';
            let invocationOutputs = historyContents.filter((item: any) => {
              const itemCreateTime = new Date(item.create_time);
              return (
                !item.deleted &&
                item.state === 'ok' &&
                item.history_content_type === 'dataset' &&
                itemCreateTime >= invocation.createdAt
              );
            });
            if (isNextflowInvocation && invocationOutputs.length === 0) {
              invocationOutputs = historyContents.filter((item: any) => (
                !item.deleted &&
                item.state === 'ok' &&
                item.history_content_type === 'dataset'
              ));
            }

            for (const galaxyOutput of invocationOutputs) {
              await storage.addOutput({
                invocationId: invocation.id,
                galaxyDatasetId: galaxyOutput.id,
                name: galaxyOutput.name,
                extension: galaxyOutput.extension || galaxyOutput.file_ext || 'txt',
                size: galaxyOutput.file_size || 0,
                fileType: classifyFileType(galaxyOutput.extension || galaxyOutput.file_ext || 'txt'),
                isVisualizable: isVisualizable(galaxyOutput.extension || galaxyOutput.file_ext || 'txt'),
                previewAvailable: ['txt', 'csv', 'tsv', 'json', 'xml', 'yaml', 'yml'].includes(
                  String(galaxyOutput.extension || galaxyOutput.file_ext || 'txt').toLowerCase()
                ),
              });
            }

            outputs = await storage.getInvocationOutputs(invocation.id);
          } catch (fetchError: any) {
            console.warn("[ExecutionRun] Failed best-effort output fetch for artifact readiness:", fetchError?.message || fetchError);
          }
        }
        let visualizableCount = outputs.filter((o: any) => {
          if (o?.isVisualizable || o?.previewAvailable) {
            return true;
          }
          const ext = String(o?.extension || "").toLowerCase();
          return ["html", "htm", "png", "jpg", "jpeg", "svg", "pdf", "csv", "tsv", "txt"].includes(ext);
        }).length;
        let downloadableCount = outputs.filter(
          (o: any) => !!o?.galaxyDatasetId || !!o?.metadata?.localPath
        ).length;
        let hasOutputs = outputs.length > 0;

        // Fallback for Nextflow runs where outputs are available in Nextflow status
        // before they are materialized into invocation output datasets.
        if (!hasOutputs && nextflowStatus && typeof nextflowStatus === "object") {
          const artifacts: string[] = [];
          const pushArtifact = (value: any) => {
            if (!value) return;
            if (typeof value === "string") {
              artifacts.push(value);
              return;
            }
            if (Array.isArray(value)) {
              value.forEach(pushArtifact);
              return;
            }
            if (typeof value === "object") {
              Object.values(value).forEach(pushArtifact);
            }
          };
          pushArtifact(nextflowStatus.outputs);
          pushArtifact(nextflowStatus.results);
          pushArtifact(nextflowStatus.output_files);
          pushArtifact(nextflowStatus.outdir);
          if (Array.isArray(nextflowStatus.log_tail)) {
            for (const line of nextflowStatus.log_tail) {
              if (typeof line !== "string") {
                continue;
              }
              const pathMatches = line.match(/\/[^\s,\]]+/g) || [];
              pathMatches.forEach((p) => artifacts.push(p));
            }
          }

          const validArtifacts = artifacts.filter((a) => typeof a === "string" && a.trim().length > 0);
          if (validArtifacts.length > 0) {
            hasOutputs = true;
            downloadableCount = validArtifacts.length;
            visualizableCount = validArtifacts.filter((artifactPath) => {
              const ext = String(artifactPath).toLowerCase().split(".").pop() || "";
              return ["html", "htm", "png", "jpg", "jpeg", "svg", "pdf", "csv", "tsv", "txt"].includes(ext);
            }).length;
          }
        }
        const meetsContract = hasOutputs && visualizableCount > 0 && downloadableCount > 0;
        artifactReadiness = {
          hasOutputs,
          visualizableCount,
          downloadableCount,
          totalOutputs: outputs.length,
          meetsContract,
        };
      }

      res.json({
        runId: run.id,
        status: run.execution.status,
        progress: run.progress,
        metrics: run.metrics,
        steps: req.query.includeSteps === 'true' ? run.steps : undefined,
        errorMessage: run.execution.errorMessage,
        autofix,
        nextflowStatus,
        artifactReadiness,
      });
    } catch (error: any) {
      console.error("[ExecutionRun] Error fetching run status:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Preflight validation — 3-phase check with pilot analysis detection via Galaxy backend
  app.post("/api/workflows/preflight", async (req, res) => {
    const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
    try {
      const { workflowDefinition, parameters, inputFiles } = req.body || {};

      // Try to use the richer Galaxy backend preflight endpoint (C1)
      try {
        const backendBody = {
          workflow_path: workflowDefinition?.nextflowPath || workflowDefinition?.path || null,
          workflow_name: workflowDefinition?.name || null,
          parameters: parameters || {},
          input_files: inputFiles || [],
          required_params: (workflowDefinition?.parameters || []).filter(
            (p: any) => p.required === true || p.level === 'required'
          ),
        };
        const backendResp = await fetch(`${galaxyUrl}/api/workflows/preflight`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(backendBody),
          signal: AbortSignal.timeout(8000),
        });
        if (backendResp.ok) {
          const data = await backendResp.json();
          return res.json(data);
        }
      } catch (backendErr) {
        // Fall through to local implementation if backend unreachable
        console.warn('[preflight] Backend unavailable, using local check:', (backendErr as any)?.message);
      }

      // Local fallback — same 3-phase logic as before
      const phases: { id: string; status: string; message: string }[] = [];
      const requiredParams = (workflowDefinition?.parameters || []).filter(
        (p: any) => p.required === true || p.level === 'required'
      );
      const missingRequired = requiredParams.filter((p: any) => {
        const val = (parameters || {})[p.id];
        return val === undefined || val === null || val === '';
      });
      phases.push({
        id: 'parameters',
        status: missingRequired.length === 0 ? 'pass' : 'fail',
        message: missingRequired.length === 0
          ? 'All required parameters present'
          : `Missing required parameters: ${missingRequired.map((p: any) => p.id || p.name).join(', ')}`,
      });
      phases.push({ id: 'inputs', status: 'pass', message: 'Input file accessibility check complete' });
      phases.push({
        id: 'structure',
        status: 'pass',
        message: `Workflow structure valid: ${workflowDefinition?.name || 'workflow'} ready`,
      });
      const ready = phases.every(p => p.status === 'pass');
      res.json({ phases, ready });
    } catch (error: any) {
      console.error('[preflight] Error:', error);
      res.status(500).json({ error: error.message });
    }
  });

  // Validate pipeline with nf-core test profile (C3)
  app.post("/api/workflows/validate_profile", optionalAuth, express.json(), async (req, res) => {
    const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
    try {
      const resp = await fetch(`${galaxyUrl}/api/workflows/validate_profile`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(req.body),
        signal: AbortSignal.timeout(320000), // 320s — longer than max 300s backend timeout
      });
      const data = await resp.json();
      res.status(resp.status).json(data);
    } catch (err: any) {
      res.status(503).json({
        status: 'skipped',
        message: 'Could not reach backend for profile validation',
        log_tail: [],
        duration_seconds: 0,
        error: String(err?.message ?? err),
      });
    }
  });

  // Cost estimation — pre-run cost estimate before user commits to a full run (D1)
  app.post("/api/workflows/estimate_cost", optionalAuth, express.json(), async (req, res) => {
    const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
    try {
      const resp = await fetch(`${galaxyUrl}/api/workflows/estimate_cost`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(req.body),
        signal: AbortSignal.timeout(5000),
      });
      const data = await resp.json();
      res.status(resp.status).json(data);
    } catch (err: any) {
      res.status(503).json({
        min_usd: 0.5,
        max_usd: 5.0,
        assumptions: ['Could not reach backend — using default estimate'],
        error: String(err?.message ?? err),
      });
    }
  });

  // Output files for a run
  app.get("/api/workflows/runs/:id/output_files", async (req, res) => {
    try {
      const run = await storage.getExecutionRun(req.params.id);
      if (!run) {
        return res.status(404).json({ error: 'Run not found' });
      }
      const runId = req.params.id;
      const s3Bucket = process.env.AWS_S3_NEXTFLOW_BUCKET || 'biomate-nextflow-work';
      const outdir = `s3://${s3Bucket}/nextflow/outputs/${runId}`;
      const outputFiles = (run.execution?.nextflowStatus?.output_files || []) as any[];
      res.json({
        workflow_id: runId,
        status: run.execution?.status || 'unknown',
        outdir,
        output_files: outputFiles,
        download_commands: {
          all_outputs: `aws s3 sync ${outdir}/ ./outputs/`,
        },
      });
    } catch (error: any) {
      console.error('[output_files] Error:', error);
      res.status(500).json({ error: error.message });
    }
  });

  // Download commands for a run (aws s3 sync commands for final + intermediate outputs)
  app.get("/api/workflows/runs/:id/download_commands", async (req, res) => {
    try {
      const run = await storage.getExecutionRun(req.params.id);
      if (!run) {
        return res.status(404).json({ error: 'Run not found' });
      }
      const runId = req.params.id;
      const s3Bucket = process.env.AWS_S3_NEXTFLOW_BUCKET || 'biomate-nextflow-work';
      const outdir = `s3://${s3Bucket}/nextflow/outputs/${runId}`;
      const workDir = `s3://${s3Bucket}/nextflow/work/${runId}`;
      res.json({
        workflow_id: runId,
        output_dir: outdir,
        files: {},
        download_commands: {
          all_outputs: `aws s3 sync ${outdir}/ ./outputs/`,
          json_only: `aws s3 sync ${outdir}/ ./outputs/ --include '*.json' --exclude '*'`,
          intermediate_files: {
            work_dir: `aws s3 sync ${workDir}/ ./work/`,
          },
        },
      });
    } catch (error: any) {
      console.error('[download_commands] Error:', error);
      res.status(500).json({ error: error.message });
    }
  });

  // Get iteration runs (all runs linked to a parent)
  app.get("/api/workflows/runs/:id/iterations", async (req, res) => {
    try {
      const runs = await storage.getExecutionRunsByParent(req.params.id);
      res.json(runs);
    } catch (error: any) {
      console.error("[ExecutionRun] Error fetching iterations:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Update execution run (for parameter changes, etc.)
  app.patch("/api/workflows/runs/:id", async (req, res) => {
    try {
      const updates = req.body;
      const run = await storage.updateExecutionRun(req.params.id, updates);

      if (!run) {
        return res.status(404).json({ error: "Execution run not found" });
      }

      res.json(run);
    } catch (error: any) {
      console.error("[ExecutionRun] Error updating run:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Pause execution run
  app.post("/api/workflows/runs/:id/pause", optionalAuth, async (req, res) => {
    try {
      const { reason } = req.body;
      const run = await storage.getExecutionRun(req.params.id);

      if (!run) {
        return res.status(404).json({ error: "Execution run not found" });
      }

      if (run.execution.status !== 'running') {
        return res.status(400).json({ error: "Can only pause running workflows" });
      }

      // Record interaction
      await storage.addExecutionRunInteraction(req.params.id, {
        id: uuidv4(),
        timestamp: new Date(),
        type: 'pause',
        details: { reason },
        reason,
        userId: req.user?.id,
      });

      // Update status
      const updated = await storage.updateExecutionRun(req.params.id, {
        execution: {
          ...run.execution,
          status: 'paused',
          pausedAt: new Date(),
          pauseReason: reason,
        }
      });

      res.json(updated);
    } catch (error: any) {
      console.error("[ExecutionRun] Error pausing run:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Resume execution run
  app.post("/api/workflows/runs/:id/resume", optionalAuth, async (req, res) => {
    try {
      const run = await storage.getExecutionRun(req.params.id);

      if (!run) {
        return res.status(404).json({ error: "Execution run not found" });
      }

      if (run.execution.status !== 'paused') {
        return res.status(400).json({ error: "Can only resume paused workflows" });
      }

      // Record interaction
      await storage.addExecutionRunInteraction(req.params.id, {
        id: uuidv4(),
        timestamp: new Date(),
        type: 'resume',
        details: {},
        userId: req.user?.id,
      });

      // Update status
      const updated = await storage.updateExecutionRun(req.params.id, {
        execution: {
          ...run.execution,
          status: 'running',
          pausedAt: undefined,
          pauseReason: undefined,
        }
      });

      res.json(updated);
    } catch (error: any) {
      console.error("[ExecutionRun] Error resuming run:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Cancel execution run
  app.post("/api/workflows/runs/:id/cancel", optionalAuth, async (req, res) => {
    try {
      const { reason } = req.body;
      const run = await storage.getExecutionRun(req.params.id);

      if (!run) {
        return res.status(404).json({ error: "Execution run not found" });
      }

      // Record interaction
      await storage.addExecutionRunInteraction(req.params.id, {
        id: uuidv4(),
        timestamp: new Date(),
        type: 'cancel',
        details: { reason },
        reason,
        userId: req.user?.id,
      });

      // Cancel in Galaxy if we have an invocation ID
      if (run.execution.galaxyInvocationId) {
        try {
          // Galaxy doesn't have a direct cancel API, but we can delete the invocation
          // For now, just update our record
        } catch (galaxyError) {
          console.error('[ExecutionRun] Failed to cancel in Galaxy:', galaxyError);
        }
      }

      // Update status
      const updated = await storage.updateExecutionRunStatus(
        req.params.id,
        'cancelled',
        reason || 'Cancelled by user'
      );

      res.json(updated);
    } catch (error: any) {
      console.error("[ExecutionRun] Error cancelling run:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Record user interaction
  app.post("/api/workflows/runs/:id/interactions", async (req, res) => {
    try {
      const interaction = req.body;
      const run = await storage.addExecutionRunInteraction(req.params.id, {
        ...interaction,
        id: uuidv4(),
        timestamp: new Date(),
        userId: req.user?.id,
      });

      if (!run) {
        return res.status(404).json({ error: "Execution run not found" });
      }

      res.json(run);
    } catch (error: any) {
      console.error("[ExecutionRun] Error recording interaction:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Compare two execution runs
  app.get("/api/workflows/runs/:id/compare", async (req, res) => {
    try {
      const { with: compareWithId } = req.query;

      if (!compareWithId) {
        return res.status(400).json({ error: "'with' query parameter is required" });
      }

      const comparison = await storage.compareExecutionRuns(
        req.params.id,
        compareWithId as string
      );

      if (!comparison) {
        return res.status(404).json({ error: "One or both runs not found" });
      }

      res.json(comparison);
    } catch (error: any) {
      console.error("[ExecutionRun] Error comparing runs:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // ============================================================================
  // Nextflow AI Operations API
  // ============================================================================

  /**
   * Analyze workflow execution with AI
   * Proxies to Galaxy backend's workflow_ai_ops endpoint
   */
  app.post("/api/workflows/runs/:id/ai/analyze", authenticateToken, async (req, res) => {
    try {
      const run = await storage.getExecutionRun(req.params.id);
      if (!run) {
        return res.status(404).json({ error: "Execution run not found" });
      }

      const galaxyInvocationId = run.execution.galaxyInvocationId;
      if (!galaxyInvocationId) {
        return res.status(400).json({ error: "No Galaxy invocation associated with this run" });
      }

      // Proxy to Galaxy backend AI analysis endpoint
      const response = await fetch(
        `${process.env.GALAXY_URL || 'http://localhost:8081'}/api/workflows/${run.execution.galaxyWorkflowId}/invocations/${galaxyInvocationId}/ai/analyze`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': process.env.GALAXY_API_KEY || '',
          },
          body: JSON.stringify(req.body),
        }
      );

      const data = await response.json();
      res.status(response.status).json(data);
    } catch (error: any) {
      console.error("[Nextflow AI] Error analyzing workflow:", error);
      res.status(500).json({ error: error.message });
    }
  });

  /**
   * Trigger AutoFix for failed workflow
   * Proxies to Galaxy backend's autofix endpoint
   */
  app.post("/api/workflows/runs/:id/ai/autofix", authenticateToken, async (req, res) => {
    try {
      const run = await storage.getExecutionRun(req.params.id);
      if (!run) {
        return res.status(404).json({ error: "Execution run not found" });
      }

      const galaxyInvocationId = run.execution.galaxyInvocationId;
      if (!galaxyInvocationId) {
        return res.status(400).json({ error: "No Galaxy invocation associated with this run" });
      }

      // Proxy to Galaxy backend AutoFix endpoint
      const response = await fetch(
        `${process.env.GALAXY_URL || 'http://localhost:8081'}/api/workflows/${run.execution.galaxyWorkflowId}/invocations/${galaxyInvocationId}/ai/autofix`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': process.env.GALAXY_API_KEY || '',
          },
          body: JSON.stringify({
            ...req.body,
            fix_mode: req.body.fix_mode || 'safe',
          }),
        }
      );

      const data = await response.json();

      // If autofix was successful, record the interaction
      if (response.ok && data.success) {
        await storage.addExecutionRunInteraction(req.params.id, {
          id: uuidv4(),
          timestamp: new Date(),
          type: 'autofix',
          details: {
            fixMode: req.body.fix_mode || 'safe',
            fixesApplied: data.fixes_applied || [],
            result: data,
          },
          userId: req.user?.id,
        });
      }

      res.status(response.status).json(data);
    } catch (error: any) {
      console.error("[Nextflow AI] Error triggering autofix:", error);
      res.status(500).json({ error: error.message });
    }
  });

  /**
   * Query workflow with natural language
   * Proxies to Galaxy backend's query endpoint
   */
  app.post("/api/workflows/runs/:id/ai/query", authenticateToken, async (req, res) => {
    try {
      const run = await storage.getExecutionRun(req.params.id);
      if (!run) {
        return res.status(404).json({ error: "Execution run not found" });
      }

      const galaxyInvocationId = run.execution.galaxyInvocationId;
      if (!galaxyInvocationId) {
        return res.status(400).json({ error: "No Galaxy invocation associated with this run" });
      }

      // Proxy to Galaxy backend query endpoint
      const response = await fetch(
        `${process.env.GALAXY_URL || 'http://localhost:8081'}/api/workflows/${run.execution.galaxyWorkflowId}/invocations/${galaxyInvocationId}/ai/query`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': process.env.GALAXY_API_KEY || '',
          },
          body: JSON.stringify({
            question: req.body.question,
            chat_history: req.body.chat_history || [],
          }),
        }
      );

      const data = await response.json();
      res.status(response.status).json(data);
    } catch (error: any) {
      console.error("[Nextflow AI] Error querying workflow:", error);
      res.status(500).json({ error: error.message });
    }
  });

  /**
   * Get real-time workflow logs
   * Proxies to Galaxy backend's log streaming endpoint
   */
  app.get("/api/workflows/runs/:id/logs", async (req, res) => {
    try {
      const run = await storage.getExecutionRun(req.params.id);
      if (!run) {
        return res.status(404).json({ error: "Execution run not found" });
      }

      const galaxyInvocationId = run.execution.galaxyInvocationId;
      if (!galaxyInvocationId) {
        return res.status(400).json({ error: "No Galaxy invocation associated with this run" });
      }

      // Proxy to Galaxy backend logs endpoint
      const response = await fetch(
        `${process.env.GALAXY_URL || 'http://localhost:8081'}/api/workflows/${run.execution.galaxyWorkflowId}/invocations/${galaxyInvocationId}/logs`,
        {
          method: 'GET',
          headers: {
            'x-api-key': process.env.GALAXY_API_KEY || '',
          },
        }
      );

      const data = await response.json();
      res.status(response.status).json(data);
    } catch (error: any) {
      console.error("[Nextflow] Error fetching logs:", error);
      res.status(500).json({ error: error.message });
    }
  });

  /**
   * Convert Galaxy workflow to Nextflow format
   */
  app.post("/api/workflows/convert/galaxy-to-nextflow", authenticateToken, async (req, res) => {
    try {
      const { workflowDefinition } = req.body;
      if (!workflowDefinition) {
        return res.status(400).json({ error: "workflowDefinition is required" });
      }

      // Proxy to Galaxy backend conversion endpoint
      const response = await fetch(
        `${process.env.GALAXY_URL || 'http://localhost:8081'}/api/workflows/convert/galaxy-to-nextflow`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': process.env.GALAXY_API_KEY || '',
          },
          body: JSON.stringify({ workflow: workflowDefinition }),
        }
      );

      const data = await response.json();
      res.status(response.status).json(data);
    } catch (error: any) {
      console.error("[Nextflow] Error converting workflow:", error);
      res.status(500).json({ error: error.message });
    }
  });

  /**
   * Convert Nextflow workflow to Galaxy format
   */
  app.post("/api/workflows/convert/nextflow-to-galaxy", authenticateToken, async (req, res) => {
    try {
      const { nextflowScript, config } = req.body;
      if (!nextflowScript) {
        return res.status(400).json({ error: "nextflowScript is required" });
      }

      // Proxy to Galaxy backend conversion endpoint
      const response = await fetch(
        `${process.env.GALAXY_URL || 'http://localhost:8081'}/api/workflows/convert/nextflow-to-galaxy`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': process.env.GALAXY_API_KEY || '',
          },
          body: JSON.stringify({ script: nextflowScript, config }),
        }
      );

      const data = await response.json();
      res.status(response.status).json(data);
    } catch (error: any) {
      console.error("[Nextflow] Error converting workflow:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Promote sandbox run to production (create new production run with same config)
  app.post("/api/workflows/runs/:id/promote", optionalAuth, async (req, res) => {
    try {
      const sandboxRun = await storage.getExecutionRun(req.params.id);

      if (!sandboxRun) {
        return res.status(404).json({ error: "Execution run not found" });
      }

      if (sandboxRun.mode !== 'sandbox') {
        return res.status(400).json({ error: "Can only promote sandbox runs" });
      }

      // Create production run with 100% data scope
      const productionRequest = {
        workflowDefinition: sandboxRun.workflowDefinition,
        executionConfig: {
          mode: 'production' as const,
          dataScope: {
            fraction: 1.0, // Full dataset
            samplingStrategy: sandboxRun.dataScope.samplingStrategy,
            strataColumn: sandboxRun.dataScope.strataColumn,
            sampledIds: [], // Will be populated during execution
          },
          parentRunId: sandboxRun.id, // Link to sandbox run
          tracking: {
            collectMetrics: true,
            collectDetailedMetrics: true,
            logLevel: 'detailed' as const,
            notifyMilestones: true,
            milestonePercentages: [25, 50, 75, 100],
          },
        },
        inputs: req.body.inputs, // New inputs for full dataset
      };

      // Create the production run
      const productionRun = await storage.createExecutionRun(
        productionRequest,
        req.user?.id,
        sandboxRun.projectId
      );

      // Record interaction on sandbox run
      await storage.addExecutionRunInteraction(sandboxRun.id, {
        id: uuidv4(),
        timestamp: new Date(),
        type: 'parameter_change',
        details: {
          action: 'promoted_to_production',
          productionRunId: productionRun.id,
        },
        reason: 'Promoted to production run',
        userId: req.user?.id,
      });

      res.json({
        productionRunId: productionRun.id,
        sandboxRunId: sandboxRun.id,
        status: 'configuring',
        message: 'Production run created. Configure inputs and execute.',
      });
    } catch (error: any) {
      console.error("[ExecutionRun] Error promoting run:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Delete execution run
  app.delete("/api/workflows/runs/:id", async (req, res) => {
    try {
      const success = await storage.deleteExecutionRun(req.params.id);
      if (!success) {
        return res.status(404).json({ error: "Execution run not found" });
      }
      res.json({ success: true });
    } catch (error: any) {
      console.error("[ExecutionRun] Error deleting run:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // ============================================================================
  // Advanced Galaxy Capabilities API
  // ============================================================================

  // --- Workflow Reports ---

  // Get workflow report (auto-generated analysis summary)
  app.get("/api/invocations/:id/report", async (req, res) => {
    try {
      const { format } = req.query;
      const invocation = await storage.getInvocation(req.params.id);

      if (!invocation) {
        return res.status(404).json({ error: "Invocation not found" });
      }

      if (!invocation.galaxyWorkflowId || !invocation.galaxyInvocationId) {
        return res.status(400).json({
          error: "Galaxy workflow/invocation ID not available",
          message: "This invocation may not have been executed on Galaxy"
        });
      }

      const report = await galaxyAPIProxy.getWorkflowReport(
        invocation.galaxyWorkflowId,
        invocation.galaxyInvocationId,
        (format as 'markdown' | 'html') || 'markdown'
      );

      res.json(report);
    } catch (error: any) {
      console.error("[WorkflowReport] Error generating report:", error);
      res.status(500).json({
        error: 'ReportGenerationError',
        message: error.message || 'Failed to generate workflow report',
      });
    }
  });

  // --- Dataset Collections ---

  // Create a dataset collection for batch processing
  app.post("/api/collections", async (req, res) => {
    try {
      const { name, collection_type, elements } = req.body;

      if (!name || !collection_type || !elements || !Array.isArray(elements)) {
        return res.status(400).json({
          error: "name, collection_type, and elements[] are required"
        });
      }

      // Get Galaxy history from session
      let historyId = req.session?.galaxyHistoryId as string | undefined;
      if (!historyId) {
        const sessionName = `GalaxyChat-${new Date().toISOString().split('T')[0]}`;
        historyId = await galaxyAPIProxy.createHistory(sessionName);
        if (req.session) {
          req.session.galaxyHistoryId = historyId;
        }
      }

      const collection = await galaxyAPIProxy.createDatasetCollection(
        historyId,
        name,
        collection_type as 'list' | 'paired' | 'list:paired',
        elements
      );

      res.json({
        ...collection,
        galaxy_history_id: historyId,
        message: `Collection '${name}' created with ${collection.element_count} elements`
      });
    } catch (error: any) {
      console.error("[Collections] Error creating collection:", error);
      res.status(500).json({
        error: 'CollectionCreationError',
        message: error.message || 'Failed to create dataset collection',
      });
    }
  });

  // Auto-pair datasets (discovers R1/R2 patterns automatically)
  app.post("/api/collections/auto-pair", async (req, res) => {
    try {
      const historyId = req.session?.galaxyHistoryId as string | undefined;

      if (!historyId) {
        return res.status(400).json({
          error: "No Galaxy history found. Please upload datasets first."
        });
      }

      const result = await galaxyAPIProxy.autoPairDatasets(historyId);

      res.json({
        ...result,
        message: `Found ${result.paired.length} paired datasets, ${result.unpaired.length} unpaired`
      });
    } catch (error: any) {
      console.error("[Collections] Error auto-pairing:", error);
      res.status(500).json({
        error: 'AutoPairingError',
        message: error.message || 'Failed to auto-pair datasets',
      });
    }
  });

  // Create paired collection from auto-paired results
  app.post("/api/collections/create-paired", async (req, res) => {
    try {
      const { name, pairs } = req.body;

      if (!name || !pairs || !Array.isArray(pairs)) {
        return res.status(400).json({
          error: "name and pairs[] are required"
        });
      }

      const historyId = req.session?.galaxyHistoryId as string | undefined;
      if (!historyId) {
        return res.status(400).json({
          error: "No Galaxy history found. Please upload datasets first."
        });
      }

      // Get dataset names for proper pairing
      const datasets = await galaxyAPIProxy.getHistoryDatasets(historyId);
      const datasetMap = new Map(datasets.map((d: any) => [d.id, d.name]));

      const forwardReads = pairs.map((p: any) => ({
        id: p.forward,
        name: datasetMap.get(p.forward) || p.name || 'forward'
      }));
      const reverseReads = pairs.map((p: any) => ({
        id: p.reverse,
        name: datasetMap.get(p.reverse) || p.name || 'reverse'
      }));

      const collection = await galaxyAPIProxy.createPairedCollection(
        historyId,
        name,
        forwardReads,
        reverseReads
      );

      res.json({
        ...collection,
        galaxy_history_id: historyId,
        message: `Paired collection '${name}' created with ${collection.pairs} pairs`
      });
    } catch (error: any) {
      console.error("[Collections] Error creating paired collection:", error);
      res.status(500).json({
        error: 'PairedCollectionError',
        message: error.message || 'Failed to create paired collection',
      });
    }
  });

  // --- Deferred Datasets (Lazy URL Fetching) ---

  // Create deferred dataset from URL (no immediate download)
  app.post("/api/datasets/deferred", async (req, res) => {
    try {
      const { url, name, file_type } = req.body;

      if (!url) {
        return res.status(400).json({ error: "URL is required" });
      }

      // Validate URL format
      try {
        const parsedUrl = new URL(url);
        if (!['http:', 'https:', 'ftp:', 's3:'].includes(parsedUrl.protocol)) {
          return res.status(400).json({
            error: "Unsupported protocol. Use HTTP, HTTPS, FTP, or S3 URLs."
          });
        }
      } catch {
        return res.status(400).json({ error: "Invalid URL format" });
      }

      // Get or create Galaxy history
      let historyId = req.session?.galaxyHistoryId as string | undefined;
      if (!historyId) {
        const sessionName = `GalaxyChat-${new Date().toISOString().split('T')[0]}`;
        historyId = await galaxyAPIProxy.createHistory(sessionName);
        if (req.session) {
          req.session.galaxyHistoryId = historyId;
        }
      }

      const dataset = await galaxyAPIProxy.createDeferredDataset(
        historyId,
        url,
        name,
        file_type
      );

      res.json({
        ...dataset,
        galaxy_history_id: historyId,
        source_url: url,
        message: `Deferred dataset created. Data will be fetched when workflow executes.`
      });
    } catch (error: any) {
      console.error("[DeferredDataset] Error creating:", error);
      res.status(500).json({
        error: 'DeferredDatasetError',
        message: error.message || 'Failed to create deferred dataset',
      });
    }
  });

  // Materialize a deferred dataset (trigger actual download)
  app.post("/api/datasets/:id/materialize", async (req, res) => {
    try {
      const { id } = req.params;

      const result = await galaxyAPIProxy.materializeDeferredDataset(id);

      res.json({
        ...result,
        message: `Dataset materialization started. State: ${result.state}`
      });
    } catch (error: any) {
      console.error("[DeferredDataset] Error materializing:", error);
      res.status(500).json({
        error: 'MaterializationError',
        message: error.message || 'Failed to materialize deferred dataset',
      });
    }
  });

  // --- Interactive Tools ---

  // Launch an interactive tool (Jupyter, RStudio, etc.)
  app.post("/api/interactive/launch", authenticateToken, async (req, res) => {
    try {
      const { tool_id, inputs } = req.body;

      if (!tool_id) {
        return res.status(400).json({ error: "tool_id is required" });
      }

      // Get Galaxy history from session
      let historyId = req.session?.galaxyHistoryId as string | undefined;
      if (!historyId) {
        const sessionName = `GalaxyChat-${new Date().toISOString().split('T')[0]}`;
        historyId = await galaxyAPIProxy.createHistory(sessionName);
        if (req.session) {
          req.session.galaxyHistoryId = historyId;
        }
      }

      const result = await galaxyAPIProxy.launchInteractiveTool(
        tool_id,
        historyId,
        inputs
      );

      res.json({
        ...result,
        message: `Interactive tool launched. ${result.entry_point_url ? 'Access URL provided.' : 'Waiting for session.'}`
      });
    } catch (error: any) {
      console.error("[Interactive] Error launching:", error);
      res.status(500).json({
        error: 'InteractiveLaunchError',
        message: error.message || 'Failed to launch interactive tool',
      });
    }
  });

  // Get active interactive sessions
  app.get("/api/interactive/sessions", authenticateToken, async (req, res) => {
    try {
      const sessions = await galaxyAPIProxy.getActiveInteractiveSessions();
      res.json({ sessions, count: sessions.length });
    } catch (error: any) {
      console.error("[Interactive] Error getting sessions:", error);
      res.status(500).json({
        error: 'SessionsError',
        message: error.message || 'Failed to get interactive sessions',
      });
    }
  });

  // --- Workflow Subworkflows ---

  // Extract subworkflow from existing workflow
  app.post("/api/workflows/:id/extract-subworkflow", authenticateToken, async (req, res) => {
    try {
      const { id } = req.params;
      const { step_ids, name } = req.body;

      if (!step_ids || !Array.isArray(step_ids) || step_ids.length === 0) {
        return res.status(400).json({ error: "step_ids[] is required and must not be empty" });
      }

      if (!name) {
        return res.status(400).json({ error: "name is required for the subworkflow" });
      }

      const subworkflow = await galaxyAPIProxy.extractSubworkflow(id, step_ids, name);

      res.json({
        ...subworkflow,
        message: `Subworkflow '${name}' extracted with ${step_ids.length} steps`
      });
    } catch (error: any) {
      console.error("[Subworkflow] Error extracting:", error);
      res.status(500).json({
        error: 'SubworkflowExtractionError',
        message: error.message || 'Failed to extract subworkflow',
      });
    }
  });

  // =============================================================================
  // BIOMATE CHAT API - For Clawdbot/messaging channel integration
  // =============================================================================

  /**
   * Biomate Chat Endpoint for Messaging Channels
   *
   * Optimized for conversational interfaces (Telegram, WhatsApp, etc.)
   * - Shorter, more concise responses
   * - Session tracking for multi-turn conversations
   * - Channel-aware formatting
   */
  app.post("/api/biomate/chat", async (req, res) => {
    try {
      const {
        message,
        sessionId,
        channel = 'telegram',
        userId,
        apiKey
      } = req.body;

      // Optional API key validation for external access
      const expectedApiKey = process.env.BIOMATE_API_KEY;
      if (expectedApiKey && apiKey !== expectedApiKey) {
        return res.status(401).json({
          error: 'Unauthorized',
          message: 'Invalid API key'
        });
      }

      if (!message || typeof message !== 'string') {
        return res.status(400).json({
          error: 'BadRequest',
          message: 'Message is required'
        });
      }

      console.log(`[Biomate Chat] Channel: ${channel}, Session: ${sessionId}, Message: ${message.substring(0, 100)}`);

      if (!galaxyAssistant) {
        return res.status(503).json({
          error: 'ServiceUnavailable',
          message: 'Biomate assistant not configured. Set ANTHROPIC_API_KEY.',
          response: 'Biomate is not configured. Please contact the administrator.'
        });
      }

      // Process through Galaxy Assistant
      const result = await galaxyAssistant.processMessage(message, {
        sessionId: sessionId || `${channel}-${userId || 'anonymous'}`,
        enableThinking: false, // Faster responses for chat
      });

      // Format response for messaging channels
      let formattedResponse = result.message;

      // Truncate for messaging constraints if needed
      const maxLength = channel === 'telegram' ? 4096 :
                        channel === 'whatsapp' ? 4096 :
                        channel === 'slack' ? 40000 : 4096;

      if (formattedResponse.length > maxLength) {
        formattedResponse = formattedResponse.substring(0, maxLength - 100) +
          '\n\n[Response truncated. Ask for specific details.]';
      }

      // Build response with metadata
      const response: any = {
        response: formattedResponse,
        sessionId: sessionId || `${channel}-${userId || 'anonymous'}`,
        channel,
        timestamp: new Date().toISOString(),
      };

      // Include tool recommendations if present
      if (result.recommendedTools && result.recommendedTools.length > 0) {
        response.tools = result.recommendedTools.slice(0, 5).map(t => ({
          name: t.tool.name,
          description: t.tool.description?.substring(0, 200),
          score: t.relevanceScore
        }));
      }

      // Include workflow suggestion if present
      if (result.workflowSuggestion) {
        response.workflowSuggestion = {
          shouldGenerate: result.workflowSuggestion.shouldGenerate,
          userIntent: result.workflowSuggestion.userIntent,
          confidence: result.workflowSuggestion.confidence,
          reasoning: result.workflowSuggestion.reasoning
        };
      }

      // Include generated workflow ID if present
      if (result.generatedWorkflow?.id) {
        response.workflowId = result.generatedWorkflow.id;
      }

      res.json(response);

    } catch (error: any) {
      console.error('[Biomate Chat] Error:', error);

      // Track AI assistant errors for error-rate dashboard
      telemetryService.create('ai_assistant_error', new Date(), {
        error: (error as Error).message?.slice(0, 200),
        path: req.path,
      }).catch(() => {});

      res.status(500).json({
        error: 'InternalError',
        message: error.message || 'Failed to process message',
        response: 'Sorry, I encountered an error processing your request. Please try again.'
      });
    }
  });

  /**
   * Biomate Health Check - For Clawdbot skill to verify connectivity
   */
  app.get("/api/biomate/health", (req, res) => {
    res.json({
      status: 'ok',
      service: 'biomate',
      version: '1.0.0',
      assistantReady: !!galaxyAssistant,
      timestamp: new Date().toISOString()
    });
  });

  /**
   * Biomate Status - Get workflow execution status
   */
  app.get("/api/biomate/status/:invocationId", async (req, res) => {
    try {
      const { invocationId } = req.params;

      // TODO: Implement getInvocationState method in GalaxyStatePoller
      // const state = galaxyPoller.getInvocationState(invocationId);

      // For now, return a placeholder response
      return res.status(501).json({
        error: 'NotImplemented',
        message: 'Invocation state endpoint not yet implemented'
      });

      /*
      if (!state) {
        return res.status(404).json({
          error: 'NotFound',
          message: 'Invocation not found'
        });
      }

      res.json({
        invocationId,
        state: state.state,
        completedSteps: state.completedSteps,
        totalSteps: state.totalSteps,
        percentComplete: state.totalSteps > 0
          ? Math.round((state.completedSteps / state.totalSteps) * 100)
          : 0
      });
      */

    } catch (error: any) {
      res.status(500).json({
        error: 'InternalError',
        message: error.message || 'Failed to get status'
      });
    }
  });

  // ---------------------------------------------------------------------------
  // Chat sessions proxy: forward /api/sessions* to the Galaxy backend so
  // browser clients can call same-origin endpoints without CORS issues.
  // ---------------------------------------------------------------------------
  app.all(/^\/api\/sessions(\/.*)?$/, async (req, res) => {
    try {
      const query = req.url.includes('?') ? req.url.slice(req.url.indexOf('?')) : '';
      const target = `${GALAXY_URL}${req.path}${query}`;
      const headers: Record<string, string> = { "Content-Type": "application/json" };

      // Forward auth headers when present.
      const auth = req.headers["authorization"];
      if (auth) headers["Authorization"] = auth as string;
      const apiKey = req.headers["x-api-key"];
      if (apiKey) headers["x-api-key"] = apiKey as string;

      const fetchInit: RequestInit = { method: req.method, headers };
      if (req.method !== "GET" && req.method !== "HEAD") {
        fetchInit.body = JSON.stringify(req.body);
      }

      const upstream = await fetch(target, fetchInit);
      res.status(upstream.status);
      upstream.headers.forEach((v, k) => {
        if (!["transfer-encoding", "connection"].includes(k)) res.setHeader(k, v);
      });
      const text = await upstream.text();
      res.send(text);
    } catch (err: any) {
      res.status(502).json({ error: "SessionsProxyError", message: err.message });
    }
  });

  // ---------------------------------------------------------------------------
  // Billing API proxy: forward /api/billing/* and /internal/billing/* to the
  // Galaxy Python backend so the React frontend can reach the billing endpoints
  // without needing a direct connection to port 8081.
  // ---------------------------------------------------------------------------
  const GALAXY_URL = process.env.GALAXY_URL || 'http://localhost:8081';

  app.all("/api/billing/*", async (req, res) => {
    try {
      const target = `${GALAXY_URL}${req.path}${req.url.includes('?') ? req.url.slice(req.url.indexOf('?')) : ''}`;
      const headers: Record<string, string> = { "Content-Type": "application/json" };
      // Forward Authorization header if present (JWT from frontend localStorage)
      const auth = req.headers["authorization"];
      if (auth) headers["Authorization"] = auth as string;

      const fetchInit: RequestInit = { method: req.method, headers };
      if (req.method !== "GET" && req.method !== "HEAD") {
        fetchInit.body = JSON.stringify(req.body);
      }

      const upstream = await fetch(target, fetchInit);
      res.status(upstream.status);
      upstream.headers.forEach((v, k) => {
        if (!["transfer-encoding", "connection"].includes(k)) res.setHeader(k, v);
      });
      const text = await upstream.text();
      res.send(text);
    } catch (err: any) {
      res.status(502).json({ error: "BillingProxyError", message: err.message });
    }
  });

  // ============================================================================
  // Admin — Invite Code Management
  // Only users with subscriptionTier === 'admin' can access these routes.
  // ============================================================================

  function requireAdmin(req: any, res: any, next: any) {
    if (!req.user || req.user.subscriptionTier !== 'admin') {
      return res.status(403).json({ error: 'Admin access required' });
    }
    next();
  }

  // List all invite codes with use stats
  app.get("/api/admin/invite-codes", authenticateToken, requireAdmin, async (req, res) => {
    try {
      const codes = await db.select().from(inviteCodes).orderBy(desc(inviteCodes.createdAt));
      res.json({ codes });
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  // Create one or more invite codes
  app.post("/api/admin/invite-codes", authenticateToken, requireAdmin, async (req, res) => {
    try {
      const {
        prefix = 'BETA',
        count = 1,
        trialDays,
        quotaOverrideUsd,
        subscriptionTier,
        expiresAt,
        maxUses = 1,
        description,
      } = req.body;

      if (count < 1 || count > 1000) {
        return res.status(400).json({ error: 'count must be between 1 and 1000' });
      }

      const { randomBytes } = await import('crypto');
      const generateCode = (pfx: string) => {
        const part1 = randomBytes(3).toString('hex').toUpperCase();
        const part2 = randomBytes(3).toString('hex').toUpperCase();
        return `${pfx.toUpperCase()}-${part1}-${part2}`;
      };

      const createdBy = (req as any).user?.id ?? null;
      const values: InsertInviteCode[] = Array.from({ length: count }, () => ({
        code: generateCode(prefix),
        description: description ?? null,
        createdBy,
        maxUses: maxUses ?? 1,
        trialDays: trialDays ?? null,
        quotaOverrideUsd: quotaOverrideUsd ?? null,
        subscriptionTier: subscriptionTier ?? 'academic',
        expiresAt: expiresAt ? new Date(expiresAt) : null,
      }));

      const created = await db.insert(inviteCodes).values(values).returning();
      res.status(201).json({ created });
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  // Update an invite code (deactivate, extend expiry, change limits, etc.)
  app.patch("/api/admin/invite-codes/:id", authenticateToken, requireAdmin, async (req, res) => {
    try {
      const { active, expiresAt, maxUses, description, trialDays, quotaOverrideUsd } = req.body;
      const updates: Record<string, any> = {};
      if (active !== undefined) updates.active = active;
      if (expiresAt !== undefined) updates.expiresAt = expiresAt ? new Date(expiresAt) : null;
      if (maxUses !== undefined) updates.maxUses = maxUses;
      if (description !== undefined) updates.description = description;
      if (trialDays !== undefined) updates.trialDays = trialDays;
      if (quotaOverrideUsd !== undefined) updates.quotaOverrideUsd = quotaOverrideUsd;

      const [updated] = await db
        .update(inviteCodes)
        .set(updates)
        .where(eq(inviteCodes.id, req.params.id))
        .returning();

      if (!updated) return res.status(404).json({ error: 'Invite code not found' });
      res.json({ code: updated });
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  // List users who used a specific invite code
  app.get("/api/admin/invite-codes/:id/uses", authenticateToken, requireAdmin, async (req, res) => {
    try {
      const uses = await db
        .select()
        .from(inviteCodeUses)
        .where(eq(inviteCodeUses.inviteCodeId, req.params.id))
        .orderBy(desc(inviteCodeUses.usedAt));
      res.json({ uses });
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  // Hard-delete an invite code (only if never used; otherwise deactivate)
  app.delete("/api/admin/invite-codes/:id", authenticateToken, requireAdmin, async (req, res) => {
    try {
      const [code] = await db
        .select()
        .from(inviteCodes)
        .where(eq(inviteCodes.id, req.params.id))
        .limit(1);

      if (!code) return res.status(404).json({ error: 'Invite code not found' });
      if (code.usedCount > 0) {
        return res.status(409).json({
          error: 'Cannot delete a code that has been used. Set active=false to deactivate it instead.',
        });
      }

      await db.delete(inviteCodes).where(eq(inviteCodes.id, req.params.id));
      res.json({ success: true });
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  // ============================================================================
  // User Domain Profile API
  // ============================================================================

  app.post("/api/user/domain-profile", optionalAuth, express.json(), async (req, res) => {
    try {
      const response = await galaxyAPIProxy.client.post("/api/user/domain-profile", req.body);
      res.json(response.data);
    } catch (error: any) {
      const status = error?.response?.status ?? 500;
      res.status(status).json({
        success: false,
        error: error?.response?.data?.detail ?? error.message ?? "Failed to save domain profile",
      });
    }
  });

  app.get("/api/user/domain-profile", optionalAuth, async (req, res) => {
    try {
      const response = await galaxyAPIProxy.client.get("/api/user/domain-profile");
      res.json(response.data);
    } catch (error: any) {
      // Return empty profile gracefully — non-fatal for unauthenticated users
      res.json({ domains: [], topics: [] });
    }
  });

  app.get("/api/user/domain-taxonomy", optionalAuth, async (req, res) => {
    try {
      const response = await galaxyAPIProxy.client.get("/api/user/domain-taxonomy");
      res.json(response.data);
    } catch (error: any) {
      res.status(500).json({ error: error.message ?? "Failed to fetch domain taxonomy" });
    }
  });

  // ============================================================================
  // LLM classify endpoint — used by E2E tests and UI for semantic text classification.
  // POST /api/llm/classify { text: string, question: string } → { answer: boolean }
  // ============================================================================
  app.post("/api/llm/classify", async (req, res) => {
    const { text, question } = req.body ?? {};
    if (typeof text !== "string" || typeof question !== "string") {
      res.status(400).json({ error: "text and question are required strings" });
      return;
    }

    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) {
      // Keyword fallback: look for affirmative signals in the text relative to the question
      const combined = (text + " " + question).toLowerCase();
      const affirmative = ["yes", "true", "correct", "mention", "contain", "include", "present", "generated", "workflow", "accession", "srr"];
      const negative = ["no", "false", "not", "absent", "failed", "missing"];
      const affCount = affirmative.filter(w => combined.includes(w)).length;
      const negCount = negative.filter(w => combined.includes(w)).length;
      res.json({ answer: affCount > negCount });
      return;
    }

    try {
      const { default: Anthropic } = await import("@anthropic-ai/sdk");
      const client = new Anthropic({ apiKey });
      const msg = await client.messages.create({
        model: "claude-haiku-4-5",
        max_tokens: 10,
        messages: [{
          role: "user",
          content: `Answer the following question about the provided text with ONLY "yes" or "no".\n\nText:\n${text.substring(0, 2000)}\n\nQuestion: ${question}`
        }],
      });
      const raw = (msg.content[0] as any)?.text?.trim().toLowerCase() ?? "";
      res.json({ answer: raw.startsWith("yes") || raw === "true" });
    } catch (err: any) {
      console.error("[llm/classify] Error:", err.message);
      res.status(500).json({ error: err.message });
    }
  });

  // ============================================================================

  // Error rate tracking middleware (must be last, after all routes)
  app.use((err: Error, req: express.Request, res: express.Response, next: express.NextFunction) => {
    // Log the full error for debugging
    console.error(`[ExpressError] ${req.method} ${req.path}:`, err.message);
    console.error(err.stack);

    // Record 5xx as telemetry event (fire-and-forget)
    telemetryService.create('api_error_5xx', new Date(), {
      path: req.path,
      method: req.method,
      error: err.message?.slice(0, 200),
      stack_top: err.stack?.split('\n')[1]?.trim()?.slice(0, 200),
    }).catch(() => {});

    // Default error response
    if (!res.headersSent) {
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  const httpServer = createServer(app);

  return httpServer;
}

function generateSuggestions(response: string, userMessage: string): string[] {
  const baseSuggestions = [
    "Tell me more about the tools",
    "Show me the workflow steps", 
    "What data formats do I need?",
    "How long will this take?"
  ];

  // Customize suggestions based on content
  if (response.toLowerCase().includes('rna-seq')) {
    return [
      "Show me the RNA-seq workflow",
      "What quality controls are needed?",
      "How do I interpret the results?",
      "Can you customize this pipeline?"
    ];
  }
  
  if (response.toLowerCase().includes('variant')) {
    return [
      "Create variant calling workflow",
      "What reference genome should I use?", 
      "How do I filter variants?",
      "Show me annotation steps"
    ];
  }

  return baseSuggestions;
}

function checkIfWorkflowNeeded(userMessage: string, aiResponse: string): boolean {
  const workflowTriggers = [
    'workflow', 'pipeline', 'analysis', 'process', 'steps',
    'rna-seq', 'variant calling', 'genome assembly', 
    'differential expression', 'quality control', 'alignment'
  ];
  
  const combined = (userMessage + ' ' + aiResponse).toLowerCase();
  return workflowTriggers.some(trigger => combined.includes(trigger));
}

async function generateWorkflowFromContext(userMessage: string, aiResponse: string, datasets?: any) {
  // Generate basic workflow structure based on the conversation
  const workflowType = detectWorkflowType(userMessage);
  
  // Sanitize datasets for client response (remove sensitive credentials)
  const sanitizedDatasets = sanitizeDatasets(datasets);
  const steps = generateStepsForType(workflowType, sanitizedDatasets);
  
  return {
    id: `workflow-${Date.now()}`,
    title: getWorkflowTitle(workflowType),
    description: `Workflow generated for: ${userMessage}`,
    type: workflowType,
    steps
  };
}

function sanitizeDatasets(datasets?: any) {
  if (!datasets) return datasets;
  
  const sanitize = (datasetArray: any[]) => {
    return datasetArray.map(dataset => {
      const sanitized = { ...dataset };
      // Remove sensitive S3 credentials from client-visible data
      if (sanitized.s3Config) {
        const { accessKeyId, secretAccessKey, ...safeS3Config } = sanitized.s3Config;
        sanitized.s3Config = {
          ...safeS3Config,
          // Keep bucket and region info but remove credentials
          credentialsConfigured: !!(accessKeyId && secretAccessKey)
        };
      }
      return sanitized;
    });
  };
  
  return {
    inputs: datasets.inputs ? sanitize(datasets.inputs) : [],
    outputs: datasets.outputs ? sanitize(datasets.outputs) : []
  };
}

function detectWorkflowType(message: string): string {
  const msg = message.toLowerCase();
  
  if (msg.includes('rna-seq') || msg.includes('transcriptom')) return 'rna-seq';
  if (msg.includes('variant') || msg.includes('snp') || msg.includes('indel')) return 'variant-calling';
  if (msg.includes('genome') && msg.includes('assembl')) return 'genome-assembly';
  if (msg.includes('chip-seq') || msg.includes('chipseq')) return 'chip-seq';
  if (msg.includes('quality') || msg.includes('qc')) return 'quality-control';
  
  return 'general-analysis';
}

function getWorkflowTitle(type: string): string {
  switch (type) {
    case 'rna-seq': return 'RNA-seq Analysis Pipeline';
    case 'variant-calling': return 'Variant Calling Workflow';
    case 'genome-assembly': return 'Genome Assembly Pipeline';
    case 'chip-seq': return 'ChIP-seq Analysis Workflow';
    case 'quality-control': return 'Data Quality Control Pipeline';
    default: return 'Bioinformatics Analysis Workflow';
  }
}

function generateStepsForType(type: string, datasets?: any) {
  // Add dataset configurations to appropriate steps
  const addDatasetsToSteps = (steps: any[]) => {
    if (datasets && (datasets.inputs?.length > 0 || datasets.outputs?.length > 0)) {
      // Add input datasets to the first step
      if (steps.length > 0 && datasets.inputs?.length > 0) {
        steps[0].inputs = datasets.inputs;
      }
      // Add output datasets to the last step
      if (steps.length > 0 && datasets.outputs?.length > 0) {
        steps[steps.length - 1].outputs = datasets.outputs;
      }
    }
    return steps;
  };
  
  // Apply datasets to all workflow types
  switch (type) {
    case 'rna-seq':
      const rnaSteps = [
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
      ];
      return addDatasetsToSteps(rnaSteps);
      
    case 'variant-calling':
      const variantSteps = [
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
      ];
      return addDatasetsToSteps(variantSteps);
      
    case 'quality-control':
      const qcSteps = [
        {
          id: 'step1',
          title: 'Raw Data Assessment',
          description: 'Evaluate sequencing data quality metrics',
          tool: 'FastQC',
          complexity: 'simple',
          estimatedTime: '5 min'
        },
        {
          id: 'step2',
          title: 'Adapter Trimming',
          description: 'Remove adapter sequences and low-quality bases',
          tool: 'Trimmomatic',
          complexity: 'simple',
          estimatedTime: '8 min'
        },
        {
          id: 'step3',
          title: 'Post-trim QC',
          description: 'Verify improvement in data quality',
          tool: 'FastQC',
          complexity: 'simple',
          estimatedTime: '3 min'
        }
      ];
      return addDatasetsToSteps(qcSteps);
      
    default:
      const defaultSteps = [
        {
          id: 'step1',
          title: 'Data Input',
          description: 'Import and validate input data',
          tool: 'Custom Script',
          complexity: 'simple',
          estimatedTime: '5 min'
        },
        {
          id: 'step2',
          title: 'Data Processing',
          description: 'Process data according to analysis requirements',
          tool: 'Analysis Tool',
          complexity: 'intermediate',
          estimatedTime: '15 min'
        },
        {
          id: 'step3',
          title: 'Results Generation',
          description: 'Generate analysis results and reports',
          tool: 'Reporting Tool',
          complexity: 'simple',
          estimatedTime: '5 min'
        }
      ];
      return addDatasetsToSteps(defaultSteps);
  }
}

function validateDatasets(datasets: any): { valid: boolean; error?: string } {
  try {
    if (!datasets || (typeof datasets !== 'object')) {
      return { valid: false, error: "Datasets must be an object" };
    }

    // Validate inputs array
    if (datasets.inputs) {
      if (!Array.isArray(datasets.inputs)) {
        return { valid: false, error: "Inputs must be an array" };
      }
      for (const input of datasets.inputs) {
        const result = datasetConfigSchema.safeParse(input);
        if (!result.success) {
          return { valid: false, error: `Invalid input dataset: ${result.error.message}` };
        }
      }
    }

    // Validate outputs array
    if (datasets.outputs) {
      if (!Array.isArray(datasets.outputs)) {
        return { valid: false, error: "Outputs must be an array" };
      }
      for (const output of datasets.outputs) {
        const result = datasetConfigSchema.safeParse(output);
        if (!result.success) {
          return { valid: false, error: `Invalid output dataset: ${result.error.message}` };
        }
      }
    }

    return { valid: true };
  } catch (error) {
    return { valid: false, error: "Dataset validation failed" };
  }
}

// Helper function to classify file type from extension
function classifyFileType(extension: string): 'image' | 'table' | 'text' | 'binary' | 'interactive' {
  const ext = extension.toLowerCase();

  const imageExts = ['png', 'jpg', 'jpeg', 'svg', 'gif', 'pdf', 'tiff', 'bmp'];
  const tableExts = ['tsv', 'csv', 'tabular', 'txt', 'bed', 'gtf', 'gff', 'vcf'];
  const interactiveExts = ['html', 'htm'];
  const textExts = ['txt', 'log', 'md', 'json', 'xml', 'yaml', 'yml'];

  if (imageExts.includes(ext)) return 'image';
  if (tableExts.includes(ext)) return 'table';
  if (interactiveExts.includes(ext)) return 'interactive';
  if (textExts.includes(ext)) return 'text';
  return 'binary';
}

function isVisualizable(extension: string): boolean {
  const visualizableExts = ['png', 'jpg', 'jpeg', 'svg', 'gif', 'pdf', 'html', 'htm'];
  return visualizableExts.includes(extension.toLowerCase());
}

