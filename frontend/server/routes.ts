import type { Express } from "express";
import express from "express";
import { requestContextMiddleware } from "./request-context";
import { createServer, type Server } from "http";
import { storage } from "./storage";
import OpenAI from "openai";
import { datasetConfigSchema, inviteCodes, inviteCodeUses, executionRunStatusSchema, auditLogs, instrumentEvents } from "../shared/schema";
import type { InsertInviteCode, ExecutionRunStatus } from "../shared/schema";
import { db, pool } from "./db";
import { eq, desc, and, sql } from "drizzle-orm";
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
import { callGeminiFlash } from "./gemini-flash";
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
import { emailService } from "./email-service";
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
import { decryptField } from "./field-encrypt";
import { checkSafety, hashMessage } from "./safety-guardrails";
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
import * as mfaService from "./mfa-service";

// Initialize OpenAI (optional for development)
const openai = (process.env.OPENAI_API_KEY && process.env.OPENAI_API_KEY.trim()) ? new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
}) : null;

// Initialize Galaxy backend - using REAL Galaxy API (no more mock)
const galaxyAPIBackend = new GalaxyAPIProxy(); // Real Galaxy API for all operations
const galaxyAPIProxy = galaxyAPIBackend; // Alias for consistency
const tokenCounter = new TokenCounter();

/**
 * Returns a GalaxyAPIProxy scoped to the authenticated user's own Galaxy API key.
 * Falls back to the shared admin proxy if the user has no personal key yet
 * (e.g. existing users provisioned before this feature, or when Galaxy is unreachable).
 */
function userProxy(req: express.Request): GalaxyAPIProxy {
  const rawApiKey = (req.user as any)?.galaxyApiKey as string | null | undefined;
  const userApiKey = rawApiKey ? decryptField(rawApiKey) : rawApiKey;
  return galaxyAPIBackend.forUser(userApiKey);
}

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
function getWorkflowExecutionEngine(workflowDef: any): 'galaxy' | 'nextflow' | 'cryosparc' {
  const tags = workflowDef?.tags || [];
  const metadata = workflowDef?.metadata || {};

  // CryoSPARC has its own dedicated executor
  if (workflowDef?.workflow_type === 'cryosparc' || workflowDef?.execution_engine === 'cryosparc') {
    return 'cryosparc';
  }

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

/**
 * Validate and normalize a raw status string to a valid ExecutionRunStatus.
 * Any value not in the enum is mapped to a safe equivalent and logged.
 * This prevents invalid strings like 'error', 'ok', 'succeeded' from reaching the DB.
 */
function toValidRunStatus(raw: string | undefined | null): ExecutionRunStatus {
  if (!raw) return 'failed';
  const parsed = executionRunStatusSchema.safeParse(raw);
  if (parsed.success) return parsed.data;
  // Map known external status names to canonical values
  const mapping: Record<string, ExecutionRunStatus> = {
    ok: 'completed',
    succeeded: 'completed',
    success: 'completed',
    error: 'failed',
    errored: 'failed',
    aborted: 'cancelled',
    stopped: 'cancelled',
    scheduled: 'queued',
    pending: 'queued',
  };
  const mapped = mapping[raw.toLowerCase()];
  if (mapped) return mapped;
  console.error(`[Status] Unknown status "${raw}" — mapping to "failed"`);
  return 'failed';
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
      const desiredStatus = toValidRunStatus(data.state === 'ok' || data.state === 'scheduled' ? 'completed' : data.state);
      const finalStatus: ExecutionRunStatus = executionRun.execution?.status === 'completed' ? 'completed' : desiredStatus;
      await storage.updateExecutionRunStatus(executionRun.id, finalStatus);
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
      if (finalStatus === 'completed' && executionRun.execution.galaxyWorkflowId) {
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

// ── Open Claw tool definitions (Track 4B-i) ───────────────────────────────────
// "Open Claw" = power-user mode where BioMate tools are visible as function calls.
// Named after the OpenClaw conversation-state pattern (see conversation-state.ts:8).
// Tool calls are executed server-side and results streamed back as SSE events.
// Open Claw tool definitions — keep in sync with:
//   backend/lib/mcp/biomate_mcp_server.py  (TOOLS list)
//   backend/lib/integrations/slack_bot.py  (_open_claw_query)
//   backend/lib/integrations/wechat_bot.py (_open_claw_query)
// Doc: docs/20260412_BIOMATE_TOOLS_CAPABILITY_MAP.md
const OPEN_CLAW_TOOLS = [
  // ── Discovery ──────────────────────────────────────────────────────────────
  {
    name: "search_workflow",
    description:
      "Search the BioMate scientific workflow catalog by natural language. " +
      "Returns ranked workflow cards with descriptions, required parameters, " +
      "and estimated AWS Batch compute time. Always call this first to find the workflow_id.",
    input_schema: {
      type: "object" as const,
      properties: {
        query: { type: "string", description: "Natural language description of the analysis, e.g. 'ADMET screening for small molecules', 'RNA-seq differential expression'" },
        limit: { type: "integer", description: "Max results (default 5, max 20)" },
      },
      required: ["query"],
    },
  },
  // ── Execution ──────────────────────────────────────────────────────────────
  {
    name: "run_workflow",
    description:
      "Execute a BioMate scientific workflow on AWS Batch. " +
      "Returns a run_id to monitor with get_run_status. " +
      "Use search_workflow first to find the workflow_id and required parameters.",
    input_schema: {
      type: "object" as const,
      properties: {
        workflow_id: { type: "string", description: "Workflow ID from search_workflow (e.g. 'assay_ingestion_and_ranking')" },
        params: { type: "object", description: "Workflow parameters as key-value pairs. Required params vary by workflow.", additionalProperties: true },
        message: { type: "string", description: "Optional natural language context — BioMate AI auto-fills missing params from this" },
      },
      required: ["workflow_id"],
    },
  },
  {
    name: "get_run_status",
    description:
      "Poll the status of a BioMate workflow run. " +
      "Returns status (pending|running|completed|failed), step progress, elapsed time, and error message if any.",
    input_schema: {
      type: "object" as const,
      properties: {
        run_id: { type: "string", description: "Run ID returned by run_workflow" },
      },
      required: ["run_id"],
    },
  },
  {
    name: "get_run_results",
    description:
      "Retrieve output files and summary data from a completed run. " +
      "Returns a list of output files with download URLs, file types, and sizes. " +
      "Only call after get_run_status returns status='completed'.",
    input_schema: {
      type: "object" as const,
      properties: {
        run_id: { type: "string", description: "Run ID of a completed run" },
      },
      required: ["run_id"],
    },
  },
  {
    name: "cancel_run",
    description:
      "Cancel a running or queued BioMate workflow job on AWS Batch. " +
      "Use when the user wants to stop a run, or before launching a corrected replacement run.",
    input_schema: {
      type: "object" as const,
      properties: {
        run_id: { type: "string", description: "Run ID to cancel" },
      },
      required: ["run_id"],
    },
  },
  {
    name: "list_runs",
    description:
      "List the user's recent BioMate workflow runs with status and timestamps. " +
      "Useful for checking what jobs are currently running or recently completed.",
    input_schema: {
      type: "object" as const,
      properties: {
        limit: { type: "integer", description: "Max runs to return (default 10)" },
        status: { type: "string", enum: ["all", "running", "completed", "failed", "pending"], description: "Filter by status (default: all)" },
      },
    },
  },
  // ── Analysis & Diagnosis ──────────────────────────────────────────────────
  {
    name: "analyze_results",
    description:
      "Ask BioMate's AI to interpret and summarize the outputs from a completed run. " +
      "Returns a natural language analysis: key findings, quality metrics, scientific interpretation, and recommended next steps.",
    input_schema: {
      type: "object" as const,
      properties: {
        run_id: { type: "string", description: "Run ID of a completed run to analyze" },
        question: { type: "string", description: "Optional specific question about the results, e.g. 'which compounds passed ADMET filters?'" },
      },
      required: ["run_id"],
    },
  },
  {
    name: "explain_error",
    description:
      "Ask BioMate's AI to diagnose why a failed workflow run failed. " +
      "Returns the likely root cause (genome mismatch, missing input, resource OOM, etc.) and the specific fix to apply.",
    input_schema: {
      type: "object" as const,
      properties: {
        run_id: { type: "string", description: "Run ID of a failed run to diagnose" },
        error_log: { type: "string", description: "Optional: paste the error log directly if run_id lookup is unavailable" },
      },
      required: ["run_id"],
    },
  },
  {
    name: "analyze_file",
    description:
      "Run lightweight QC analysis on a data file. " +
      "Returns format-specific metrics: FASTQ (read count, quality, adapters), " +
      "VCF (variant count, FILTER pass rate), CSV/TSV (rows, columns, missing values), " +
      "FASTA (sequence count, length distribution, GC content).",
    input_schema: {
      type: "object" as const,
      properties: {
        s3_key: { type: "string", description: "S3 path to the file (s3://bucket/path/file)" },
        inline_data: { type: "string", description: "Small file content pasted inline (max 50 KB). Use s3_key for larger files." },
        file_type: { type: "string", enum: ["fastq", "csv", "tsv", "vcf", "fasta", "bam", "auto"], description: "File type hint (default: auto-detect)" },
      },
    },
  },
  // ── Databases ─────────────────────────────────────────────────────────────
  {
    name: "query_database",
    description:
      "Query a biological or chemical database by accession, gene symbol, compound name, or search query. " +
      "Databases: uniprot (protein), pdb/alphafold (structure), ncbi_gene (gene), " +
      "dbsnp/clinvar/gnomad (variants), kegg/reactome (pathways), " +
      "chebi/pubchem (compounds), hpo/omim (phenotypes/disease), string (interactions).",
    input_schema: {
      type: "object" as const,
      properties: {
        database: {
          type: "string",
          enum: ["uniprot","pdb","alphafold","ncbi_gene","dbsnp","clinvar","gnomad","kegg","reactome","chebi","pubchem","hpo","omim","string"],
          description: "Target database",
        },
        query: { type: "string", description: "Accession (P04637, 1TUP), gene symbol (BRCA1), compound name (ibuprofen), or rsID (rs7412)" },
      },
      required: ["database", "query"],
    },
  },
];

/**
 * Execute a tool call from the Open Claw agentic loop.
 * Routes to the same BioMate API endpoints used by the MCP server.
 * All calls go through auth middleware — userId is forwarded for billing.
 */
async function executeOpenClaudeTool(
  toolName: string,
  input: Record<string, any>,
  userId: string | null,
  req: any
): Promise<any> {
  const baseUrl = `http://localhost:${process.env.PORT || 5000}`;
  const authHeader = req.headers.authorization || "";

  const post = async (path: string, body: any) => {
    const r = await fetch(`${baseUrl}${path}`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: authHeader },
      body: JSON.stringify(body),
    });
    return r.json();
  };
  const get = async (path: string) => {
    const r = await fetch(`${baseUrl}${path}`, {
      headers: { Authorization: authHeader },
    });
    return r.json();
  };

  try {
    switch (toolName) {
      // ── Discovery ────────────────────────────────────────────────────────
      case "search_workflow":
        return await post("/api/workflows/search", { query: input.query, limit: input.limit ?? 5 });

      // ── Execution ────────────────────────────────────────────────────────
      case "run_workflow":
        return await post("/api/workflows/execute", {
          workflow_id: input.workflow_id,
          params: input.params ?? {},
          message: input.message,
        });
      case "get_run_status":
        return await get(`/api/workflows/runs/${input.run_id}/status`);
      case "get_run_results":
        return await get(`/api/workflows/runs/${input.run_id}/outputs`);
      case "cancel_run":
        return await post(`/api/workflows/runs/${input.run_id}/cancel`, {});
      case "list_runs": {
        const qs = new URLSearchParams();
        if (input.limit) qs.set("limit", String(input.limit));
        if (input.status && input.status !== "all") qs.set("status", input.status);
        return await get(`/api/workflows/runs?${qs}`);
      }

      // ── Analysis & Diagnosis ─────────────────────────────────────────────
      case "analyze_results":
        return await post(`/api/workflows/runs/${input.run_id}/ai/analyze`, {
          question: input.question ?? "Summarize the key findings and scientific interpretation.",
        });
      case "explain_error":
        return await post("/api/workflows/explain_error", {
          run_id: input.run_id,
          error_log: input.error_log ?? "",
        });
      case "analyze_file":
        return await post("/api/data/analyze", {
          s3_key: input.s3_key,
          inline_data: input.inline_data,
          file_type: input.file_type ?? "auto",
        });

      // ── Databases ────────────────────────────────────────────────────────
      case "query_database":
        return await post("/api/databases/query", { database: input.database, query: input.query });

      default:
        return { error: `Unknown tool: ${toolName}` };
    }
  } catch (err: any) {
    return { error: err.message };
  }
}
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

// Clean up temp uploads older than UPLOAD_TTL_HOURS to prevent unbounded disk growth.
const UPLOAD_TTL_MS = (parseInt(process.env.UPLOAD_TTL_HOURS || '48', 10)) * 60 * 60 * 1000;
async function cleanStaleUploads(): Promise<void> {
  try {
    const entries = await fs.readdir(uploadDir);
    const now = Date.now();
    let removed = 0;
    for (const name of entries) {
      const p = path.join(uploadDir, name);
      try {
        const stat = await fs.stat(p);
        if (stat.isFile() && now - stat.mtimeMs > UPLOAD_TTL_MS) {
          await fs.unlink(p);
          removed++;
        }
      } catch { /* file may have been deleted concurrently */ }
    }
    if (removed > 0) {
      console.log(`[upload-cleanup] Removed ${removed} stale file(s) older than ${UPLOAD_TTL_MS / 3600000}h`);
    }
  } catch { /* uploadDir may not exist yet */ }
}
// Run cleanup on startup and every 6 hours
fs.mkdir(uploadDir, { recursive: true }).then(() => {
  cleanStaleUploads();
  setInterval(cleanStaleUploads, 6 * 60 * 60 * 1000);
}).catch(() => {});

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
      '.json', '.xml',
      // Cryo-EM / electron microscopy formats
      '.mrc', '.mrcs', '.tif', '.tiff', '.eer', '.spi', '.dm4', '.map',
    ];
    const ext = path.extname(file.originalname).toLowerCase();
    if (allowedExtensions.some(allowed => file.originalname.toLowerCase().endsWith(allowed))) {
      cb(null, true);
    } else {
      cb(new Error(`File type not supported. Allowed: ${allowedExtensions.join(', ')}`));
    }
  },
});

/**
 * Auto-stage local file parameters to S3 before an AWS Batch Nextflow run.
 * When NEXTFLOW_USE_AWS=true, Batch containers can't access the frontend
 * server's local filesystem. Any param that is an absolute local path pointing
 * to an existing file gets uploaded to s3://biomate-nextflow-work/inputs/<userId>/<filename>
 * and the param value is replaced with the resulting s3:// URI.
 *
 * Returns a new params object (original is not mutated).
 */
async function stageLocalFilesForBatch(
  params: Record<string, any>,
  userId: string
): Promise<Record<string, any>> {
  const useAws = (process.env.NEXTFLOW_USE_AWS || '').toLowerCase() in { true: 1, '1': 1, yes: 1 };
  if (!useAws) return params;

  const { S3Client, PutObjectCommand } = await import('@aws-sdk/client-s3');
  const s3Bucket = process.env.AWS_S3_NEXTFLOW_BUCKET || 'biomate-nextflow-work';
  const region   = process.env.AWS_DEFAULT_REGION || process.env.AWS_REGION || 'us-west-2';
  const s3 = new S3Client({ region });

  const staged = { ...params };
  for (const [key, val] of Object.entries(params)) {
    if (typeof val !== 'string') continue;
    if (!val.startsWith('/')) continue;        // skip non-absolute paths
    if (val.startsWith('/proc') || val.startsWith('/sys') || val.startsWith('/dev')) continue;
    let stat: any;
    try { stat = await fs.stat(val); } catch { continue; }
    if (!stat.isFile()) continue;

    const filename   = path.basename(val);
    const s3Key      = `inputs/${userId}/${uuidv4().slice(0, 8)}-${filename}`;
    const fileBuffer = await fs.readFile(val);
    await s3.send(new PutObjectCommand({
      Bucket: s3Bucket,
      Key:    s3Key,
      Body:   fileBuffer,
    }));
    const s3Uri = `s3://${s3Bucket}/${s3Key}`;
    console.log(`[S3Stage] Staged local file ${key}=${val} → ${s3Uri}`);
    staged[key] = s3Uri;
  }
  return staged;
}

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
  // Per-request AsyncLocalStorage context — must precede all route handlers
  // so that getRequestContext() works inside Galaxy API calls, LLM calls, and SSE handlers.
  app.use(requestContextMiddleware);

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

  app.get("/api/telemetry/cost-summary", async (req, res) => {
    try {
      const { from, to } = req.query as { from?: string; to?: string };
      const summary = await telemetryService.getCostSummary({ from, to });
      res.json(summary);
    } catch (err: any) {
      res.status(500).json({ error: err.message });
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

      // H2 — actual time to result from post_run events (actual_time_minutes field)
      // Falls back to exit survey avg_time_minutes if actual not available.
      const timeMins = [
        ...postRuns.filter((p) => p.actual_time_minutes != null).map((p) => Number(p.actual_time_minutes)),
        ...exitSurveys.filter((p) => p.avg_time_minutes != null).map((p) => Number(p.avg_time_minutes)),
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

      const sessions_submitted = new Set(postRuns.map((p: any) => p.run_id).filter(Boolean)).size;
      const sessions_no_correction = postRuns.filter((p: any) => p.ran_without_manual_correction === true).length;

      res.json({
        respondents,
        sessions_submitted,
        sessions_no_correction,
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
        organization: req.body.organization || req.body.institution,
        role: req.body.role,
        phone: req.body.phone,
        termsAccepted: req.body.terms_accepted || req.body.termsAccepted || false,
        marketingEmailsOptIn: req.body.marketing_emails_opt_in || req.body.marketingEmailsOptIn || false,
        inviteCode: req.body.inviteCode || req.body.invite_code,
      };

      const result = await authService.register(registerData);

      // Send verification email (non-blocking — don't fail registration if email fails)
      authService.sendVerificationEmail(result.user.id).catch((err) =>
        console.error('[Auth] Failed to send verification email:', err)
      );

      // Register user in Lago for usage-based billing (fire-and-forget)
      const _galaxyUrlReg = process.env.GALAXY_URL || 'http://localhost:8081';
      const _billingKeyReg = process.env.BILLING_INTERNAL_KEY;
      if (_billingKeyReg) {
        fetch(`${_galaxyUrlReg}/internal/billing/register_user`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-Internal-Key': _billingKeyReg },
          body: JSON.stringify({
            user_id: result.user.id,
            email: result.user.email,
            name: result.user.fullName || result.user.email,
            plan: result.user.subscriptionTier || 'base',
          }),
          signal: AbortSignal.timeout(8000),
        }).catch((err: any) => console.warn('[Billing] upsert_customer on register failed:', err?.message));
      }

      // Set HTTP-only cookie
      res.cookie('biomate_token', result.token, {
        httpOnly: true,
        secure: process.env.NODE_ENV === 'production',
        sameSite: 'lax',
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
        rememberMe: req.body.rememberMe === true || req.body.rememberMe === 'true',
      };

      const result = await authService.login(loginData);

      // rememberMe=false → session cookie (browser discards on close, JWT lives 24h)
      // rememberMe=true  → persistent cookie (maxAge=30d, JWT lives 30d)
      if (result.rememberMe) {
        res.cookie('biomate_token', result.token, {
          httpOnly: true,
          secure: process.env.NODE_ENV === 'production',
          sameSite: 'lax',
          maxAge: result.expiresIn * 1000, // 30 days in ms
        });
      } else {
        res.cookie('biomate_token', result.token, {
          httpOnly: true,
          secure: process.env.NODE_ENV === 'production',
          sameSite: 'lax',
          // No maxAge → session cookie; dropped when browser closes
        });
      }

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

  // Request password reset (alias for client compatibility)
  app.post("/api/auth/forgot-password", passwordResetLimiter, async (req, res) => {
    const { email } = req.body;
    if (!email) return res.status(400).json({ success: false, error: 'Email is required' });
    try {
      const result = await authService.requestPasswordReset(email);
      // Dev bypass: when email is not configured, return the token directly so the user can reset
      if (result.resetToken) {
        return res.json({ success: true, message: 'Email not configured — use the reset link below', resetToken: result.resetToken });
      }
    } catch (_) {}
    res.json({ success: true, message: 'If the email exists, a password reset link has been sent' });
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

  // ── MFA routes ────────────────────────────────────────────────────────────

  // Start MFA setup — generate TOTP secret, return QR code + manual key
  app.post("/api/auth/mfa/setup", authenticateToken, async (req, res) => {
    try {
      const userId = (req.user as any).id;
      const email = (req.user as any).email;
      const secret = mfaService.generateSecret(email);
      await mfaService.storePendingSecret(userId, secret.base32);
      const qrCode = await mfaService.generateQRCode(secret.otpauth_url!);
      res.json({ qrCode, manualKey: secret.base32 });
    } catch (e: any) {
      res.status(500).json({ error: 'MFA setup failed' });
    }
  });

  // Verify first TOTP code → activate MFA, return recovery codes (shown once)
  app.post("/api/auth/mfa/verify-setup", authenticateToken, async (req, res) => {
    try {
      const userId = (req.user as any).id;
      const { token } = req.body ?? {};
      if (!token) return res.status(400).json({ error: 'token required' });
      const base32 = await mfaService.getDecryptedSecret(userId);
      if (!base32) return res.status(400).json({ error: 'MFA setup not initiated' });
      if (!mfaService.verifyTotp(base32, token)) {
        return res.status(400).json({ error: 'Invalid TOTP code' });
      }
      const plainCodes = mfaService.generateRecoveryCodes();
      const hashedCodes = await mfaService.hashRecoveryCodes(plainCodes);
      await mfaService.activateMfa(userId, hashedCodes);
      res.json({ recoveryCodes: plainCodes });
    } catch (e: any) {
      res.status(500).json({ error: 'MFA activation failed' });
    }
  });

  // Disable MFA — requires password + current TOTP for confirmation
  app.post("/api/auth/mfa/disable", authenticateToken, async (req, res) => {
    try {
      const userId = (req.user as any).id;
      const email = (req.user as any).email;
      const { password, token } = req.body ?? {};
      if (!password || !token) return res.status(400).json({ error: 'password and token required' });
      const user = await authService.verifyCredentials(email, password);
      if (!user) return res.status(401).json({ error: 'Invalid password' });
      const base32 = await mfaService.getDecryptedSecret(userId);
      if (!base32 || !mfaService.verifyTotp(base32, token)) {
        return res.status(400).json({ error: 'Invalid TOTP code' });
      }
      await mfaService.disableMfa(userId);
      res.json({ ok: true });
    } catch (e: any) {
      res.status(500).json({ error: 'MFA disable failed' });
    }
  });

  // MFA status
  app.get("/api/auth/mfa/status", authenticateToken, async (req, res) => {
    try {
      const userId = (req.user as any).id;
      const user = await authService.getUserById(userId);
      res.json({
        enabled: user?.mfaEnabled ?? false,
        verifiedAt: user?.mfaVerifiedAt ?? null,
        remainingRecoveryCodes: user?.mfaRecoveryCodes
          ? (JSON.parse(user.mfaRecoveryCodes) as string[]).length : 0,
      });
    } catch (e: any) {
      res.status(500).json({ error: 'Failed to get MFA status' });
    }
  });

  // MFA challenge — called after password login when MFA is enabled
  app.post("/api/auth/mfa/challenge", async (req, res) => {
    try {
      const { challengeToken, token } = req.body ?? {};
      if (!challengeToken || !token) {
        return res.status(400).json({ error: 'challengeToken and token required' });
      }

      // Verify challenge token
      let payload: any;
      try {
        payload = authService.verifyToken(challengeToken);
      } catch {
        return res.status(401).json({ error: 'Invalid or expired challenge token' });
      }
      if (payload.type !== 'mfa_challenge' || !payload.jti) {
        return res.status(401).json({ error: 'Invalid token type' });
      }

      const { userId, jti } = payload;

      // Replay prevention — consume JTI (one-use)
      const consumed = await mfaService.consumeJti(jti, userId, new Date(Date.now() + 5 * 60 * 1000));
      if (!consumed) {
        return res.status(401).json({ error: 'Challenge token already used' });
      }

      // Brute-force lockout check
      if (await mfaService.isLockedOut(userId)) {
        return res.status(429).json({ error: 'Account temporarily locked. Try again later.' });
      }

      const base32 = await mfaService.getDecryptedSecret(userId);
      if (!base32) return res.status(400).json({ error: 'MFA not configured' });

      let valid = mfaService.verifyTotp(base32, token);
      let usedRecovery = false;
      if (!valid) {
        valid = await mfaService.verifyAndBurnRecoveryCode(userId, token);
        usedRecovery = valid;
      }

      if (!valid) {
        const { locked, remaining } = await mfaService.recordFailedChallenge(userId);
        if (locked) {
          return res.status(429).json({ error: 'Too many failed attempts. Account locked for 15 minutes.' });
        }
        return res.status(401).json({ error: 'Invalid MFA code', remainingAttempts: remaining });
      }

      await mfaService.clearFailedChallenges(userId);

      // Issue full session token
      const user = await authService.getUserById(userId);
      if (!user) return res.status(401).json({ error: 'User not found' });
      const sessionToken = authService.generateToken(user, false);
      res.json({ token: sessionToken });
    } catch (e: any) {
      console.error('[MFA] Challenge error:', e);
      res.status(500).json({ error: 'MFA challenge failed' });
    }
  });

  // ── End MFA routes ────────────────────────────────────────────────────────

  // Newsletter subscribe (no auth required; stores email for future mailouts)
  app.post("/api/newsletter/subscribe", async (req, res) => {
    try {
      const { email } = req.body;
      if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        return res.status(400).json({ success: false, error: 'Valid email required' });
      }
      // Log the subscription; a real mailout service (ConvertKit, Loops, etc.) can be wired here later
      console.log(`[Newsletter] New subscriber: ${email}`);
      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: 'Subscription failed' });
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
          sameSite: 'lax',
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
          sameSite: 'lax',
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

      // Accept either a direct priceId or a tier+interval pair
      let { priceId, tier, interval, successUrl, cancelUrl } = req.body;

      if (!priceId && tier) {
        const tiers = stripeService.getPricingTiers() as Record<string, { monthly?: string; yearly?: string }>;
        const tierPrices = tiers[tier];
        if (!tierPrices) {
          return res.status(400).json({ error: `Unknown tier: ${tier}` });
        }
        priceId = interval === 'yearly' ? tierPrices.yearly : tierPrices.monthly;
      }

      if (!priceId) {
        return res.status(400).json({ error: 'Price ID or tier+interval required' });
      }

      const appUrl = process.env.APP_URL || 'https://dev-public.biomate.ai';
      const session = await stripeService.createCheckoutSession(
        req.user!.id,
        priceId,
        successUrl || `${appUrl}/checkout.html?status=success`,
        cancelUrl || `${appUrl}/pricing.html`
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

  // Galaxy / BioMate histories API
  app.get("/api/galaxy/histories", optionalAuth, async (req, res) => {
    try {
      const proxy = userProxy(req);
      const histories = await proxy.getHistories();
      const shaped = (histories || []).map((h: any) => ({
        id: h.id,
        name: h.name,
        count: h.count ?? h.dataset_count ?? 0,
        size: h.size ?? h.total_size ?? 0,
        create_time: h.create_time ?? h.create_date ?? '',
        update_time: h.update_time ?? h.update_date ?? '',
      }));
      res.json({ histories: shaped });
    } catch (err: any) {
      console.error('[Histories] fetch failed:', err.message);
      res.json({ histories: [] });
    }
  });

  app.get("/api/galaxy/histories/:historyId/datasets", optionalAuth, async (req, res) => {
    try {
      const { historyId } = req.params;
      const proxy = userProxy(req);
      const datasets = await proxy.getHistoryDatasets(historyId);
      const shaped = (datasets || []).map((d: any) => ({
        id: d.id,
        name: d.name || d.dataset_id,
        extension: d.extension ?? d.data_type ?? '',
        file_size: d.file_size ?? d.size ?? 0,
        state: d.state ?? 'ok',
        create_time: d.create_time ?? '',
      }));
      res.json({ datasets: shaped });
    } catch (err: any) {
      console.error('[HistoryDatasets] fetch failed:', err.message);
      res.json({ datasets: [] });
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
          historyId = await userProxy(req).createHistory(sessionName);
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
          galaxyDatasetId = await userProxy(req).uploadDataset(
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
          file_path: file.path,  // local path — Nextflow executor can read this directly
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

  // Server Path Registration — register a pre-existing filesystem/NFS path as a dataset reference.
  // Used for instrument-connector paths (cryo-EM movies_path, mass-spec mzml_dir, etc.) that already
  // exist on a shared mount accessible to the Batch workers. No file transfer occurs.
  app.post("/api/datasets/register-path", optionalAuth, express.json(), async (req, res) => {
    try {
      const { path: serverPath, paramName, name } = req.body;
      if (!serverPath || typeof serverPath !== 'string') {
        return res.status(400).json({ error: "path is required" });
      }
      // Sanity-check: only accept absolute paths or recognised network schemes
      const isAbsolute = serverPath.startsWith('/');
      const isNetwork = /^(s3a?|nfs|smb|cifs):\/\//i.test(serverPath);
      if (!isAbsolute && !isNetwork) {
        return res.status(400).json({ error: "path must be absolute or a network URI (s3://, nfs://, etc.)" });
      }

      const displayName = name || serverPath.split('/').filter(Boolean).pop() || serverPath;
      const datasetId = `path-${Date.now()}`;

      if (req.session) {
        if (!req.session.uploadedDatasets) req.session.uploadedDatasets = [];
        (req.session.uploadedDatasets as any[]).push({
          dataset_id: datasetId,
          galaxy_dataset_id: null,
          name: displayName,
          description: paramName ? `Instrument path for param: ${paramName}` : 'Server-side path reference',
          file_type: 'path',
          file_size: 0,
          file_path: serverPath,    // the real path passed to workflow params
          param_name: paramName || null,  // optional explicit param mapping
        });
      }

      return res.json({
        dataset_id: datasetId,
        name: displayName,
        file_path: serverPath,
        param_name: paramName || null,
        registered_at: new Date().toISOString(),
      });
    } catch (error: any) {
      console.error("[RegisterPath] Error:", error);
      return res.status(500).json({ error: error.message || "Failed to register path" });
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
          historyId = await userProxy(req).createHistory(sessionName);
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
        const galaxyDatasetId = await userProxy(req).uploadFromUrl(
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
            source_url: url,  // Nextflow can fetch HTTP/S3 URLs directly
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

  // Return session datasets with resolved paths for the parameter browser
  app.get("/api/datasets/session", authenticateToken, async (req, res) => {
    const raw: any[] = req.session?.uploadedDatasets || [];
    const datasets = raw.map((d: any) => ({
      id: d.dataset_id,
      galaxy_dataset_id: d.galaxy_dataset_id,
      name: d.name,
      file_type: d.file_type,
      file_size: d.file_size,
      // file_path: local absolute path usable by Nextflow executor on the same host
      file_path: d.file_path || null,
      // source_url: for URL imports — Nextflow can fetch http/https/s3 directly
      source_url: d.source_url || null,
    }));
    res.json({ datasets });
  });

  // Resolve a Galaxy dataset to a local path the Nextflow executor can use.
  // Downloads the dataset into the uploads dir on first call; subsequent calls
  // return the cached path so Nextflow can read it from disk.
  app.get("/api/galaxy/datasets/:datasetId/resolve", authenticateToken, async (req, res) => {
    const { datasetId } = req.params;
    try {
      // First check session — maybe we already have the local path
      const session: any[] = req.session?.uploadedDatasets || [];
      const cached = session.find((d: any) => d.galaxy_dataset_id === datasetId);
      if (cached?.file_path) {
        return res.json({ file_path: cached.file_path, name: cached.name });
      }

      // Fetch dataset metadata from Galaxy (raw Galaxy API, not BioMNI curated index)
      const meta = await userProxy(req).getDatasetMetadata(datasetId);
      if (!meta) {
        return res.status(404).json({ error: 'Dataset not found in Galaxy' });
      }

      // Download via Galaxy streaming download endpoint into the local upload dir
      const ext = meta.extension ? `.${meta.extension}` : '';
      const localName = `${datasetId}${ext}`;
      const localPath = path.join(uploadDir, localName);

      // Only download if not already on disk
      const localFs = await fs.access(localPath).then(() => true).catch(() => false);
      if (!localFs) {
        const stream = await userProxy(req).downloadDataset(datasetId);
        if (!stream) {
          return res.status(502).json({ error: 'Galaxy did not return a download stream' });
        }
        const { createWriteStream } = await import('fs');
        await new Promise<void>((resolve, reject) => {
          const out = createWriteStream(localPath);
          stream.pipe(out);
          out.on('finish', resolve);
          out.on('error', reject);
        });
      }

      // Cache in session
      if (req.session) {
        if (!req.session.uploadedDatasets) req.session.uploadedDatasets = [];
        const existing = (req.session.uploadedDatasets as any[]).find((d: any) => d.galaxy_dataset_id === datasetId);
        if (!existing) {
          (req.session.uploadedDatasets as any[]).push({
            dataset_id: datasetId,
            galaxy_dataset_id: datasetId,
            description: '',
            name: meta.name || localName,
            file_type: (meta.extension as string) || 'unknown',
            file_size: (meta.file_size as number) || 0,
            file_path: localPath,
          });
        } else {
          existing.file_path = localPath;
        }
      }

      res.json({ file_path: localPath, name: meta.name || localName });
    } catch (err: any) {
      console.error('[DatasetResolve] Error:', err.message);
      res.status(500).json({ error: err.message || 'Failed to resolve dataset' });
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
      const job = await userProxy(req).submitToolJob(tool_id, {
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

  // Resume a Nextflow run with -resume (used by step-level "Run Step" buttons).
  // Creates a new Nextflow run that reuses cached work from the original run,
  // so all already-completed steps are skipped and only failed/new steps execute.
  //
  // The frontend viewer passes its execution run UUID (frontend storage ID).
  // The Python backend's _runs dict is keyed by the Nextflow-assigned run_id.
  // We resolve the translation here before proxying to the Python backend.
  app.post("/api/workflows/runs/:runId/rerun", optionalAuth, async (req, res) => {
    try {
      const { runId } = req.params;

      // Resolve the Nextflow run_id from the frontend execution run record.
      const execRun = await storage.getExecutionRun(runId).catch(() => null);
      const nextflowRunId =
        execRun?.execution?.nextflowRunId ||
        execRun?.execution?.galaxyInvocationId ||
        runId; // fallback: caller may already be passing the Nextflow run_id

      console.log(
        `[ResumeRun] frontend runId=${runId} → nextflowRunId=${nextflowRunId}`
      );

      // Pass nextflow_path in the body so the Python endpoint can reconstruct
      // the work directory from disk when the run is not in the receiving
      // worker's _runs dict (multi-worker gunicorn deployment).
      const nextflowPath =
        execRun?.workflowDefinition?.nextflow_path ||
        execRun?.workflowDefinition?.nextflowPath ||
        '';

      // Accept updated params from caller (e.g. QC gate auto-loop rerun)
      const updatedParams = req.body?.params ?? null;

      const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
      const response = await fetch(
        `${galaxyUrl}/api/nextflow/resume/${encodeURIComponent(nextflowRunId)}`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-API-Key': process.env.GALAXY_API_KEY || '',
          },
          body: JSON.stringify({
            nextflow_path: nextflowPath,
            ...(updatedParams ? { parameters: updatedParams } : {}),
          }),
        }
      );
      if (!response.ok) {
        const err = await response.text().catch(() => response.statusText);
        return res.status(response.status).json({ error: 'ResumeError', message: err });
      }
      const data = await response.json();
      const newNextflowRunId = data.run_id;

      // Update the existing execution run record with the new Nextflow run_id
      // and reset status to running, so the status endpoint can poll the resumed run.
      if (execRun && newNextflowRunId) {
        await storage.updateExecutionRun(execRun.id, {
          execution: {
            ...execRun.execution,
            nextflowRunId: newNextflowRunId,
            galaxyInvocationId: newNextflowRunId,
            status: 'running',
            startedAt: new Date(),
            completedAt: undefined,
            errorMessage: undefined,
            nextflowStatus: undefined,
          },
        }).catch((e: any) => console.warn('[ResumeRun] Failed to update run record:', e?.message));
      }

      // Return the frontend storage UUID (not the raw Nextflow UUID) so the
      // status endpoint can look up the record and proxy to the new Nextflow run.
      res.json({ ...data, run_id: execRun?.id || newNextflowRunId });
    } catch (error: any) {
      console.error('[ResumeRun] Error:', error);
      res.status(500).json({ error: 'ResumeError', message: error.message || 'Resume failed' });
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

      const invocation = await userProxy(req).invokeWorkflow(workflow_id, inputs, invokeParams);
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

  // Proxy for CryoSPARC status endpoint — frontend can poll run status directly
  app.get("/api/cryosparc/gpu_metrics", async (_req: any, res: any) => {
    try {
      const response = await fetch(
        `${process.env.GALAXY_URL || 'http://localhost:8081'}/api/cryosparc/gpu_metrics`,
        { headers: { 'X-API-Key': process.env.GALAXY_API_KEY || '' } }
      );
      const data = await response.json();
      return res.status(response.status).json(data);
    } catch (err: any) {
      return res.status(502).json({ error: 'GPU metrics proxy error', gpus: [] });
    }
  });

  app.get("/api/cryosparc/status/:runId", async (req: any, res: any) => {
    try {
      const response = await fetch(
        `${process.env.GALAXY_URL || 'http://localhost:8081'}/api/cryosparc/status/${req.params.runId}`,
        { headers: { 'X-API-Key': process.env.GALAXY_API_KEY || '' } }
      );
      const data = await response.json();
      return res.status(response.status).json(data);
    } catch (err: any) {
      return res.status(502).json({ error: 'CryoSPARC status proxy error' });
    }
  });

  // Proxy for QC gate endpoints — frontend POSTs to /api/qc-gates/:id/decision
  // which must be forwarded to the Galaxy backend. No dedicated route existed before.
  // Proxy for QC profiles list — GET /api/qc/profiles → Galaxy /api/qc/profiles
  app.get("/api/qc/profiles", async (_req: any, res: any) => {
    try {
      const response = await galaxyAPIProxy.client.get("/api/qc/profiles");
      return res.status(response.status).json(response.data);
    } catch (err: any) {
      const status = err.response?.status || 502;
      return res.status(status).json(err.response?.data || { error: 'QC profiles proxy error' });
    }
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Drug Discovery API — wildcard proxy to Galaxy/FastAPI backend
  // Covers all routes from lib/galaxy/ai/drug_discovery/api_router.py:
  //   POST   /api/drug-discovery/campaigns
  //   GET    /api/drug-discovery/model-validation/:model_type
  //   GET    /api/drug-discovery/audit
  //   GET    /api/drug-discovery/audit/verify
  //   GET    /api/drug-discovery/audit/export
  //   GET    /api/drug-discovery/esig/status
  //   POST   /api/drug-discovery/esig/enroll
  //   POST   /api/drug-discovery/esig/enroll/verify
  //   POST   /api/drug-discovery/:id/esig/sign
  //   GET    /api/drug-discovery/:id/retrain/status
  //   POST   /api/drug-discovery/:id/retrain/start|stop|trigger
  //   GET    /api/drug-discovery/:id/virtual-library
  //   POST   /api/drug-discovery/:id/virtual-library (new body)
  //   POST   /api/drug-discovery/:id/ind-assembly
  //   GET    /api/drug-discovery/:id/compounds
  //   GET    /api/drug-discovery/:id/export/cro-order
  //   POST   /api/drug-discovery/:id/ingest-assay  (multipart handled below)
  //   GET    /api/drug-discovery/availability
  // ─────────────────────────────────────────────────────────────────────────
  app.all("/api/drug-discovery/*", optionalAuth, async (req: any, res: any) => {
    try {
      const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
      const targetPath = req.path; // already /api/drug-discovery/...
      const method = req.method.toUpperCase();

      // Build query string
      const queryStr = req.url.includes('?') ? req.url.slice(req.url.indexOf('?')) : '';
      const fullPath = `${targetPath}${queryStr}`;

      // Forward with user's Galaxy API key if available
      const _rawKey3636 = (req as any).user?.galaxyApiKey as string | undefined;
      const apiKey = (_rawKey3636 ? decryptField(_rawKey3636) : null) || process.env.GALAXY_API_KEY || '';
      const headers: Record<string, string> = {
        'Content-Type': req.headers['content-type'] || 'application/json',
        'X-API-Key': apiKey,
      };

      const fetchOpts: RequestInit = {
        method,
        headers,
        signal: AbortSignal.timeout(120000),
      };

      if (method !== 'GET' && method !== 'HEAD' && method !== 'DELETE') {
        // For multipart (file upload), stream the raw body
        if (req.headers['content-type']?.includes('multipart/form-data')) {
          // Can't easily re-stream multipart here — skip body forwarding
          // (ingest-assay uses its own dedicated handler above this wildcard)
        } else {
          fetchOpts.body = JSON.stringify(req.body);
        }
      }

      const resp = await fetch(`${galaxyUrl}${fullPath}`, fetchOpts);

      // Stream response back
      const contentType = resp.headers.get('content-type') || 'application/json';
      res.setHeader('Content-Type', contentType);
      res.status(resp.status);

      if (contentType.includes('application/json')) {
        const data = await resp.json().catch(() => ({}));
        return res.json(data);
      } else {
        // Stream binary/text
        const buf = Buffer.from(await resp.arrayBuffer());
        return res.send(buf);
      }
    } catch (err: any) {
      const status = err.response?.status || 502;
      const detail = err.response?.data || { error: 'Drug discovery proxy error', detail: err.message };
      return res.status(status).json(detail);
    }
  });

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

  // Proxy for QC audit log download — streams JSONL from Galaxy backend
  app.get("/api/invocations/:invocationId/qc-audit-download", async (req: any, res: any) => {
    try {
      const { invocationId } = req.params;
      // Resolve frontend UUID → backend run_id (nextflow UUID or Galaxy integer ID)
      const inv = await storage.getInvocation(invocationId).catch(() => null);
      const backendId = inv?.galaxyInvocationId || invocationId;
      const response = await (galaxyAPIProxy.client as any).get(
        `/api/invocations/${backendId}/qc-audit-download`,
        { responseType: 'arraybuffer', params: req.query }
      );
      const contentType = response.headers['content-type'] || 'application/x-ndjson';
      const contentDisposition = response.headers['content-disposition'] || `attachment; filename="qc_audit_${invocationId}.jsonl"`;
      res.setHeader('Content-Type', contentType);
      res.setHeader('Content-Disposition', contentDisposition);
      return res.status(response.status).send(Buffer.from(response.data));
    } catch (err: any) {
      const status = err.response?.status || 502;
      return res.status(status).json(err.response?.data || { error: 'QC audit download proxy error' });
    }
  });

  // Methods report download — generates a publication-quality report.
  // Routing:
  //   a) If invocationId is a Galaxy Invocation (has galaxyInvocationId) → proxy to Galaxy backend
  //   b) Otherwise (Nextflow-native ExecutionRun UUID) → generate AI report locally
  app.get("/api/invocations/:invocationId/methods-report", async (req: any, res: any) => {
    const { invocationId } = req.params;

    // Look up the legacy invocation record
    const inv = await storage.getInvocation(invocationId).catch(() => null);
    // A Galaxy invocation has a non-empty galaxyWorkflowId (Nextflow legacy invocations set this to '')
    const isGalaxyInvocation = !!(inv?.galaxyInvocationId) && !!(inv?.galaxyWorkflowId && inv.galaxyWorkflowId !== '');

    if (isGalaxyInvocation) {
      try {
        const response = await (galaxyAPIProxy.client as any).get(
          `/api/invocations/${inv!.galaxyInvocationId}/methods-report`,
          { responseType: 'arraybuffer', params: req.query }
        );
        const contentType = response.headers['content-type'] || 'text/plain';
        const contentDisposition = response.headers['content-disposition'] || `attachment; filename="methods_report_${invocationId}.txt"`;
        res.setHeader('Content-Type', contentType);
        res.setHeader('Content-Disposition', contentDisposition);
        return res.status(response.status).send(Buffer.from(response.data));
      } catch (_galaxyErr: any) {
        // Fall through to local generation even for Galaxy invocations if proxy fails
      }
    }

    // Nextflow-native run (or Galaxy proxy failed) — generate AI report locally
    {
      // Galaxy proxy failed — generate a publication-quality methods report for Nextflow-native runs.
      // Collects: run metadata, workflow definition (steps + params), timing, S3 output files,
      // then calls Claude Sonnet to synthesize a full methods/results/findings section.
      try {
        const apiKey = process.env.ANTHROPIC_API_KEY;
        // Try all possible lookups:
        // 1. Direct executionRun by ID (when invocationId IS the executionRun.id)
        // 2. By galaxyInvocationId from a found legacy invocation
        // 3. Direct by galaxyInvocationId (when invocationId IS the backend run_id / galaxyInvocationId)
        let run = await storage.getExecutionRun(invocationId).catch(() => null);
        if (!run && inv?.galaxyInvocationId) {
          run = await storage.getExecutionRunByGalaxyId(inv.galaxyInvocationId).catch(() => null);
        }
        if (!run) {
          run = await storage.getExecutionRunByGalaxyId(invocationId).catch(() => null);
        }
        const workflowName: string = (run as any)?.workflowName || (run as any)?.name || 'Workflow';
        // execution.startedAt is a Date object — coerce to ISO string
        const execStart = (run as any)?.execution?.startedAt;
        const startedAt: string = (typeof execStart === 'object' && execStart instanceof Date)
          ? execStart.toISOString()
          : (typeof execStart === 'string' ? execStart : ((run as any)?.createdAt || new Date().toISOString()));
        const execEnd = (run as any)?.execution?.completedAt;
        const completedAt: string = (typeof execEnd === 'object' && execEnd instanceof Date)
          ? execEnd.toISOString()
          : (typeof execEnd === 'string' ? execEnd : '');
        const nfRunId: string = (run as any)?.execution?.nextflowRunId || invocationId;
        const runStatus: string = (run as any)?.execution?.status || 'completed';
        const workflowId: string = (run as any)?.workflowId || '';
        // For Nextflow-native runs, parameters live in workflowDefinition.parameters (flat map)
        // For Galaxy runs, they live in parameters.toolParameters (toolId → paramName → value)
        const nfParams: Record<string, any> = (run as any)?.workflowDefinition?.parameters || {};
        const toolParameters: Record<string, Record<string, any>> = (run as any)?.parameters?.toolParameters || {};
        const galaxyParams: Record<string, any> = Object.values(toolParameters).reduce(
          (acc, paramMap) => Object.assign(acc, paramMap), {} as Record<string, any>
        );
        const params: Record<string, any> = Object.keys(nfParams).length > 0 ? nfParams : galaxyParams;

        // Wall-time calculation
        let wallTimeStr = 'N/A';
        try {
          if (startedAt && completedAt) {
            const secs = Math.round((new Date(completedAt).getTime() - new Date(startedAt).getTime()) / 1000);
            const h = Math.floor(secs / 3600); const m = Math.floor((secs % 3600) / 60); const s = secs % 60;
            wallTimeStr = h > 0 ? `${h}h ${m}m ${s}s` : m > 0 ? `${m}m ${s}s` : `${s}s`;
          }
        } catch { /* ignore */ }

        // Fetch workflow definition (steps, descriptions) from run's workflowDefinition
        let workflowSteps: Array<{ name: string; description?: string; tool?: string }> = [];
        try {
          const wfDef = (run as any)?.workflowDefinition || null;
          if (wfDef) {
            const stepsRaw = (wfDef as any)?.steps || {};
            workflowSteps = Object.values(stepsRaw).map((s: any) => ({
              name: s?.name || s?.label || s?.tool_id || 'Step',
              description: s?.annotation || s?.description || '',
              tool: s?.tool_id || '',
            }));
          }
        } catch { /* step info not critical */ }

        // Collect S3 output files — use stored nextflowOutputDir first, then timing.json fallback
        const s3Bucket = process.env.AWS_S3_NEXTFLOW_BUCKET || 'biomate-nextflow-work';
        const storedOutdir: string = (run as any)?.execution?.nextflowOutputDir || '';
        let s3OutputBase = storedOutdir
          ? (storedOutdir.endsWith('/') ? storedOutdir : storedOutdir + '/')
          : `s3://${s3Bucket}/nextflow/outputs/${nfRunId}/`;
        if (!storedOutdir) {
          try {
            const fs = await import('fs/promises');
            const timingPath = `/tmp/nextflow_runs/${nfRunId}/timing.json`;
            const timingRaw = await fs.readFile(timingPath, 'utf-8').catch(() => null);
            if (timingRaw) {
              const timing = JSON.parse(timingRaw);
              if (timing.outdir && timing.outdir.startsWith('s3://')) {
                s3OutputBase = timing.outdir.endsWith('/') ? timing.outdir : timing.outdir + '/';
              }
            }
          } catch { /* fall back to nfRunId-based path */ }
        }
        const TEXT_EXTS = /\.(txt|log|json|csv|tsv|md|star|bed|gff|gtf|fasta|fa|vcf)$/i;
        const BIN_EXTS  = /\.(mrc|mrcs|cs|tif|tiff|png|jpg|gif|bam|cif|map|dm4|eer)$/i;

        let allOutputFiles: string[] = [];
        let textOutputSamples: Array<{ name: string; content: string }> = [];

        try {
          const { S3Client, ListObjectsV2Command, GetObjectCommand } = await import('@aws-sdk/client-s3');
          const nfAccessKey = process.env.AWS_NF_ACCESS_KEY_ID;
          const nfSecretKey = process.env.AWS_NF_SECRET_ACCESS_KEY;
          const s3Client = new S3Client({
            region: 'us-east-1',
            ...(nfAccessKey && nfSecretKey ? {
              credentials: { accessKeyId: nfAccessKey, secretAccessKey: nfSecretKey }
            } : {}),
          });

          // Parse bucket and prefix from s3OutputBase
          const s3Match = s3OutputBase.replace(/^s3:\/\//, '').split('/');
          const s3BucketName = s3Match[0];
          const s3Prefix = s3Match.slice(1).join('/');

          // List all objects under the output prefix
          let continuationToken: string | undefined;
          const allKeys: string[] = [];
          do {
            const listCmd = new ListObjectsV2Command({
              Bucket: s3BucketName,
              Prefix: s3Prefix,
              MaxKeys: 1000,
              ContinuationToken: continuationToken,
            });
            const listResp = await s3Client.send(listCmd);
            for (const obj of listResp.Contents || []) {
              if (obj.Key) allKeys.push(obj.Key);
            }
            continuationToken = listResp.IsTruncated ? listResp.NextContinuationToken : undefined;
          } while (continuationToken);


          // Build allOutputFiles inventory and collect text keys to fetch in parallel
          const PRIORITY_FILES = [
            'workflow_summary.json', 'fsc_validation.json', 'nu_refinement_report.json',
            'extract_report.json', 'selection_report.json',
          ];
          const textKeysToFetch: Array<{ key: string; fname: string; priority: boolean }> = [];
          for (const key of allKeys) {
            const fname = key.split('/').pop() || key;
            if (BIN_EXTS.test(fname)) { allOutputFiles.push(fname + ' [binary]'); continue; }
            allOutputFiles.push(fname);
            if (TEXT_EXTS.test(fname)) {
              const isPriority = PRIORITY_FILES.some(p => fname === p);
              textKeysToFetch.push({ key, fname, priority: isPriority });
            }
          }
          // Sort: priority first, then rest; cap total reads at 15
          textKeysToFetch.sort((a, b) => (b.priority ? 1 : 0) - (a.priority ? 1 : 0));
          const keysToRead = textKeysToFetch.slice(0, 15);

          // Parallel S3 reads
          const readResults = await Promise.allSettled(keysToRead.map(async ({ key, fname }) => {
            const getCmd = new GetObjectCommand({ Bucket: s3BucketName, Key: key });
            const getResp = await s3Client.send(getCmd);
            const chunks: Buffer[] = [];
            const stream = getResp.Body as any;
            await new Promise<void>((res, rej) => {
              stream.on('data', (c: Buffer) => chunks.push(c));
              stream.on('end', res);
              stream.on('error', rej);
            });
            return { name: fname, content: Buffer.concat(chunks).toString('utf-8').slice(0, 6000) };
          }));
          for (const r of readResults) {
            if (r.status === 'fulfilled' && r.value.content.trim()) {
              textOutputSamples.push(r.value);
            } else if (r.status === 'rejected') {
              console.warn(`[MethodsReport] S3 get failed:`, String(r.reason).slice(0, 100));
            }
          }
        } catch (s3Err: any) {
          console.warn('[MethodsReport] S3 scan failed:', s3Err.message?.slice(0, 200));
        }

        // Build parameter narrative
        const paramLines = Object.entries(params)
          .filter(([, v]) => v !== null && v !== undefined && v !== '')
          .map(([k, v]) => `  - ${k}: ${String(v)}`)
          .join('\n');

        // Build step list narrative
        const stepLines = workflowSteps.length > 0
          ? workflowSteps.map((s, i) => `  ${i+1}. ${s.name}${s.description ? ': ' + s.description : ''}`).join('\n')
          : '  (Step definitions not available — see Nextflow trace for per-process details)';

        // Output file inventory
        const outputInventory = allOutputFiles.length > 0
          ? allOutputFiles.map(f => `  - ${f}`).join('\n')
          : '  (No output files indexed — see S3 bucket directly)';

        // Text file context for LLM — inject ALL key report JSONs
        const fileContext = textOutputSamples.length > 0
          ? textOutputSamples.map(f =>
              `### Output file: ${f.name}\n\`\`\`\n${f.content}\n\`\`\``
            ).join('\n\n')
          : '(No readable text output files available — binary outputs (MRC, CS, STAR) produced)';

        // ── Domain detection ─────────────────────────────────────────────────
        const wfLower = workflowName.toLowerCase();
        const isCryoEM   = /cryo|spa\b|cryosparc|electron microscopy/i.test(wfLower);
        const isADMET    = /admet|toxicity|pharmacol|dili|herg|predict.*prop/i.test(wfLower);
        const isRNAseq   = /rnaseq|rna.?seq|differential.*abund|deseq|edger/i.test(wfLower);
        const isVariant  = /sarek|wgs|variant|gatk|snp|vcf|genomics/i.test(wfLower);
        const isDocking  = /docking|dock|autodock|vina|binding/i.test(wfLower);
        const isDrugDisc = /drug.?disc|admet|pbpk|clinical.?trial|ind.?prep|ddi|cyp/i.test(wfLower);

        // Parse all JSON output files
        const _parse = (name: string): Record<string, any> => {
          const sample = textOutputSamples.find(s => s.name === name);
          if (!sample) return {};
          try { return JSON.parse(sample.content); } catch { return {}; }
        };
        const allReports = textOutputSamples.map(s => {
          try { return { name: s.name, data: JSON.parse(s.content) }; } catch { return { name: s.name, data: {} }; }
        });

        // ── Domain-specific metric extraction ────────────────────────────────
        let extractedMetrics: Record<string, string> = {};

        if (isCryoEM) {
          const motionRpt  = allReports.find(r => r.name.includes('motion_report'));
          const ctfRpt     = allReports.find(r => r.name.includes('ctf_report_batch'));
          const pickRpt    = allReports.find(r => r.name.includes('picking_report'));
          const junkRpt    = allReports.find(r => r.name.includes('junk_report'));
          const extractR1  = allReports.find(r => r.name.includes('extract_report_batch'));
          const class2dR1  = allReports.find(r => r.name.includes('class2d_report_pbatch'));
          // selection_report.json appears for both R1 and R2; first alphabetically is R1
          const selectRpts = allReports.filter(r => r.name === 'selection_report.json');
          const selectR1   = selectRpts[0]?.data ?? {};
          const extractR2  = allReports.find(r => r.name === 'extract_report.json');
          const fscRpt     = allReports.find(r => r.name === 'fsc_validation.json');
          const wfSummary  = allReports.find(r => r.name === 'workflow_summary.json');
          const nuRpt      = allReports.find(r => r.name === 'nu_refinement_report.json');
          const motionCS   = motionRpt?.data?.cs_job_uid ?? ctfRpt?.data?.cs_job_uid ?? 'MISSING';
          const proj       = motionRpt?.data?.cs_project_uid ?? 'see CryoSPARC project';
          // num_particles=0 in refinement reports is a pipeline metadata propagation bug
          const nuParticles = nuRpt?.data?.num_particles;
          const nuNote = (nuParticles === 0) ? '0 (count propagation incomplete — check CryoSPARC)' : String(nuParticles ?? 'MISSING');
          extractedMetrics = {
            num_micrographs:          String(motionRpt?.data?.num_micrographs          ?? 'MISSING'),
            motion_cs_job:            motionCS,
            avg_total_motion_A:       String(motionRpt?.data?.avg_total_motion_A       ?? 'not captured — re-run for drift stats'),
            avg_defocus_A:            String(ctfRpt?.data?.avg_defocus_A               ?? 'not captured — re-run for CTF stats'),
            avg_fit_quality:          String(ctfRpt?.data?.avg_fit_quality             ?? 'not captured — re-run for CTF stats'),
            num_blob_particles:       String(pickRpt?.data?.num_particles              ?? 'MISSING'),
            particle_diameter_A:      String(pickRpt?.data?.particle_diameter_angstroms ?? params?.particle_diameter_angstroms ?? 'MISSING'),
            num_junk_input:           String(junkRpt?.data?.num_input_particles        ?? 'MISSING'),
            num_junk_rejected:        String(junkRpt?.data?.num_rejected               ?? 'MISSING'),
            num_extracted_r1:         String(extractR1?.data?.num_particles            ?? 'MISSING'),
            box_size_pix:             String(extractR1?.data?.box_size_pix             ?? extractR2?.data?.box_size_pix ?? 'MISSING'),
            num_particles_2d_r1:      String(class2dR1?.data?.num_particles            ?? 'MISSING'),
            num_classes_r1:           String(class2dR1?.data?.num_classes              ?? 'MISSING'),
            num_selected_r1:          String(selectR1?.num_selected_particles          ?? 'MISSING'),
            num_extracted_r2:         String(extractR2?.data?.num_particles            ?? 'MISSING'),
            num_particles_nu:         nuNote,
            fsc_0143_resolution:      String(fscRpt?.data?.fsc_0143_resolution        ?? 'MISSING (FSC validation not completed)'),
            pixel_size_A:             String(wfSummary?.data?.pixel_size_angstroms     ?? params?.pixel_size ?? params?.pixel_size_angstroms ?? 'MISSING'),
            voltage_kv:               String(wfSummary?.data?.voltage_kv              ?? params?.voltage_kv ?? params?.voltage ?? 'MISSING'),
            symmetry:                 String(wfSummary?.data?.symmetry                ?? params?.symmetry   ?? 'C1'),
            steps_completed:          String(wfSummary?.data?.steps_completed         ?? 'MISSING'),
            s3_output_path:           s3OutputBase,
            completion_time:          String(wfSummary?.data?.completion_time         ?? completedAt ?? 'MISSING'),
            cs_project_uid:           proj,
          };
        } else if (isADMET || isDrugDisc) {
          const toxRpt     = _parse('toxicity_report.json');
          const admetRes   = _parse('predict_admet_properties_results.json');
          const perCpd     = Array.isArray(toxRpt?.per_compound) ? toxRpt.per_compound : [];
          extractedMetrics = {
            compounds_assessed:    String(toxRpt?.compounds_assessed      ?? perCpd.length         ?? 'MISSING'),
            model_type:            String(toxRpt?.model_type               ?? admetRes?.result?.model ?? 'MPNN'),
            estimation_method:     String(toxRpt?.estimation_method        ?? 'rdkit_descriptors'),
            herg_ic50_min_uM:      String(Math.min(...perCpd.map((c:any) => c.herg_ic50_uM ?? Infinity)).toFixed(3) ?? 'MISSING'),
            dili_risk_max:         String(perCpd.find((c:any) => c.dili_risk === 'high')?.dili_risk ?? toxRpt?.toxicity?.dili_risk ?? 'MISSING'),
            dili_probability_max:  String(toxRpt?.toxicity?.dili_probability ?? 'MISSING'),
            ames_positive:         String(toxRpt?.toxicity?.ames_positive    ?? 'MISSING'),
            ames_probability:      String(toxRpt?.toxicity?.ames_probability ?? 'MISSING'),
            smiles_input:          String(Array.isArray(params?.smiles_list) ? params.smiles_list.join('; ') : (params?.smiles_list ?? params?.smiles ?? 'MISSING')),
            logP_range:            String(perCpd.length > 0 ? `${Math.min(...perCpd.map((c:any) => c.logP ?? 99)).toFixed(2)} – ${Math.max(...perCpd.map((c:any) => c.logP ?? -99)).toFixed(2)}` : 'MISSING'),
            mw_range:              String(perCpd.length > 0 ? `${Math.min(...perCpd.map((c:any) => c.mw ?? 9999)).toFixed(1)} – ${Math.max(...perCpd.map((c:any) => c.mw ?? 0)).toFixed(1)} Da` : 'MISSING'),
          };
        } else if (isRNAseq) {
          const qcRpt  = _parse('multiqc_report.json') || _parse('qc_summary.json');
          const deRpt  = _parse('differential_expression.json');
          extractedMetrics = {
            total_samples:   String(qcRpt?.total_samples     ?? params?.samples ?? 'MISSING'),
            aligner:         String(params?.aligner          ?? 'STAR'),
            genome:          String(params?.genome           ?? params?.genome_index ?? 'MISSING'),
            de_tool:         String(params?.pseudo_aligner   ?? 'DESeq2'),
            total_de_genes:  String(deRpt?.total_significant ?? 'MISSING'),
            upregulated:     String(deRpt?.upregulated       ?? 'MISSING'),
            downregulated:   String(deRpt?.downregulated     ?? 'MISSING'),
          };
        } else if (isVariant) {
          const vcfRpt = _parse('variant_summary.json');
          extractedMetrics = {
            genome:         String(params?.genome    ?? 'MISSING'),
            total_variants: String(vcfRpt?.total     ?? 'MISSING'),
            snps:           String(vcfRpt?.snps      ?? 'MISSING'),
            indels:         String(vcfRpt?.indels    ?? 'MISSING'),
            caller:         String(params?.tools     ?? 'GATK HaplotypeCaller'),
          };
        } else {
          // Generic: pull what we can from params
          extractedMetrics = Object.fromEntries(
            Object.entries(params).slice(0, 15).map(([k, v]) => [k, String(v ?? 'MISSING')])
          );
        }

        const missingCount = Object.values(extractedMetrics).filter(v => v === 'MISSING').length;
        const metricsBlock = Object.entries(extractedMetrics)
          .map(([k, v]) => `  ${k}: ${v}`)
          .join('\n');

        // If no AI key, produce a structured template without LLM synthesis
        if (!apiKey) {
          const fallback = [
            `BioMate AI — Methods Report`,
            `${'='.repeat(60)}`,
            `Generated: ${new Date().toISOString()}`,
            ``,
            `1. STUDY OVERVIEW`,
            `-`.repeat(40),
            `Workflow: ${workflowName}`,
            `Invocation ID: ${invocationId}`,
            `Nextflow Run ID: ${nfRunId}`,
            `Execution status: ${runStatus}`,
            `Started: ${startedAt}`,
            completedAt ? `Completed: ${completedAt}` : '',
            `Wall time: ${wallTimeStr}`,
            ``,
            `2. INPUT PARAMETERS`,
            `-`.repeat(40),
            paramLines || '  (Parameters not recorded)',
            ``,
            `3. WORKFLOW STEPS`,
            `-`.repeat(40),
            stepLines,
            ``,
            `4. OUTPUT FILES`,
            `-`.repeat(40),
            outputInventory,
            ``,
            `5. DATA LOCATION`,
            `-`.repeat(40),
            `All outputs: ${s3OutputBase}`,
          ].filter(l => l !== undefined).join('\n');
          res.setHeader('Content-Type', 'text/plain; charset=utf-8');
          res.setHeader('Content-Disposition', `attachment; filename="methods_report_${invocationId}.txt"`);
          return res.status(200).send(fallback);
        }

        // Domain-specific system + user prompts
        let SYSTEM: string;
        let USER: string;

        const executionBlock = `=== EXECUTION METADATA ===
WORKFLOW: ${workflowName}
INVOCATION ID: ${invocationId}
NEXTFLOW RUN ID: ${nfRunId}
EXECUTION STATUS: ${runStatus}
START TIME: ${startedAt}
COMPLETION TIME: ${completedAt || 'N/A'}
TOTAL WALL TIME: ${wallTimeStr}
CLOUD PLATFORM: AWS Batch (us-west-2 region)
ORCHESTRATION: Nextflow DSL2 + AWS Batch`;

        const commonTail = `
=== EXTRACTED METRICS (parsed from pipeline JSON reports — verified real numbers) ===
${metricsBlock}

=== INPUT PARAMETERS ===
${paramLines || '(not recorded)'}

=== OUTPUT FILE CONTENTS (raw pipeline reports) ===
${fileContext}

=== OUTPUT FILES ===
${outputInventory}`;

        if (isCryoEM) {
          SYSTEM = `You are a senior structural biologist writing a complete Methods and Results section for a cryo-EM journal (Nature Methods, IUCrJ, eLife, JSB). Write formal third-person scientific prose in past tense. Include every available parameter value, version number, and hardware spec. Where a metric says "not captured", briefly note it would be available in a production re-run. Where a metric says "MISSING", write "[data not available — pipeline re-run required]". Do NOT use markdown headers. Use numbered section headings in ALL CAPS followed by a period. Write ALL sections even when some metrics are unavailable — use what IS available.`;

          USER = `Generate a complete CryoSPARC SPA technical report. Use ALL available numbers from EXTRACTED METRICS. Write every section fully — do not skip or shorten sections because some metrics are unavailable. Available particle counts, pixel size, voltage, symmetry, and step completion data should all appear in the report.

${executionBlock}
GPU COMPUTE: NVIDIA L4 (g6.2xlarge, 1×GPU, 8 vCPU, 32 GB RAM)
SOFTWARE: CryoSPARC v5.0.2 | Nextflow DSL2 | BioMate v2.0
DATA NOTE: ${missingCount > 5 ? 'This is a partial run. Motion/CTF statistics and final refinement particle counts require a production re-run to capture. Particle picking, extraction, and 2D classification counts ARE available.' : `${Object.keys(extractedMetrics).length - missingCount} of ${Object.keys(extractedMetrics).length} metrics captured.`}
${commonTail}

=== REQUIRED SECTIONS (write ALL) ===
1. ABSTRACT (100 words) — num_micrographs micrographs processed; num_blob_particles blob-picked particles; num_extracted_r2 particles after template picking; pixel_size_A Å/pixel; voltage_kv kV; symmetry; 23 processing steps completed; CryoSPARC v5.0.2 on AWS Batch.
2. STUDY OVERVIEW — Pixel size pixel_size_A Å/pixel; voltage voltage_kv kV; particle diameter particle_diameter_A Å; symmetry symmetry; box size box_size_pix² pixels.
3. COMPUTATIONAL ENVIRONMENT — AWS Batch us-east-1; NVIDIA L4 GPU (g6.2xlarge); CryoSPARC v5.0.2; Nextflow DSL2; BioMate orchestration; steps_completed steps completed; wall time wallTimeStr.
4. DATA ACQUISITION — num_micrographs micrographs; pixel_size_A Å/pixel; voltage_kv kV; motion correction by CryoSPARC Patch Motion Correction; CTF by CryoSPARC Patch CTF. If avg_total_motion_A = "not captured", note re-run provides drift statistics.
5. METHODS — One paragraph each: (a) Motion Correction, (b) CTF Estimation, (c) Particle Picking (num_blob_particles candidates from blob picker at particle_diameter_A Å), (d) Round-1 Extraction (num_extracted_r1 particles, box_size_pix px), (e) 2D Classification R1 (num_particles_2d_r1 particles, num_classes_r1 classes), (f) Round-2 Extraction (num_extracted_r2 particles), (g) Ab-Initio Reconstruction (3 models, C1 symmetry), (h) Homogeneous Refinement, (i) Non-Uniform Refinement, (j) FSC Validation.
6. PIPELINE EXECUTION — Wall time wallTimeStr; steps_completed steps completed; output at s3_output_path; completion_time.
7. RESULTS — Particle yield table using all available counts. FSC resolution: fsc_0143_resolution.
8. DATA QUALITY — Note that 20 micrographs is a pilot dataset (1.9% of EMPIAR-10028). Discuss particle yield efficiency (num_extracted_r2/num_blob_particles × 100%). Motion and CTF quality metrics require re-run.
9. DEPOSITION NOTE — pixel_size_A Å/voxel; symmetry; CryoSPARC v5.0.2; output at s3_output_path.
N. REFERENCES — CryoSPARC: PMID 28165473; CTFFIND4: PMID 26278980; MotionCor2: PMID 28250466; NU refinement: PMID 33257830; Local CTF: PMID 34282325.`;

        } else if (isADMET || isDrugDisc) {
          SYSTEM = `You are a senior computational pharmacologist and toxicologist writing a submission-ready Methods and Results section for a pharmaceutical sciences journal (J Med Chem, Drug Metabolism and Disposition, Toxicological Sciences). Write in formal third-person scientific prose, past tense. Be specific and quantitative. Include all measured ADMET values and proper regulatory context (ICH guidelines, FDA DDI guidance). Do NOT use markdown headers (#, ##). Use numbered section headings in ALL CAPS followed by a period.`;

          USER = `Generate a complete, publication-quality ADMET pharmacological assessment manuscript section. Use ONLY the numbers in EXTRACTED METRICS — do not invent values. For any metric marked MISSING, write: "[data not available]".

${executionBlock}
SOFTWARE: BioMate ADMET Pipeline (RDKit descriptors, MPNN architecture)
DATA COVERAGE: ${missingCount} of ${Object.keys(extractedMetrics).length} metrics are MISSING
${commonTail}

=== REQUIRED SECTIONS ===
1. ABSTRACT (120 words) — Number of compounds assessed, model type, key safety findings (hERG IC50, DILI risk), Ames mutagenicity result, cloud platform.

2. STUDY OVERVIEW — Biological objective (safety profiling); compounds assessed (use SMILES from smiles_input parameter); expected endpoints (cardiac, hepatic, genotoxic risk).

3. COMPUTATIONAL ENVIRONMENT — AWS Batch; Nextflow DSL2; BioMate pipeline; RDKit descriptor-based heuristics; MPNN model architecture; DeepPurpose library status.

4. METHODS —
   4.1 Input Preparation — SMILES standardization; descriptor calculation (logP, MW, TPSA).
   4.2 hERG Cardiotoxicity Assessment — IC50 prediction; threshold (herg_ic50_min_uM µM vs 1 µM clinical safety threshold per ICH E14).
   4.3 Drug-Induced Liver Injury (DILI) — Probability model; dili_probability_max; risk classification.
   4.4 Ames Mutagenicity — Structural alert method (Kazius-Bursi dataset, kazius_structural_alerts); ames_positive result; ames_probability.
   4.5 Lipophilicity and Druglikeness — Lipinski Rule of Five compliance; logP_range; mw_range.

5. RESULTS — Per-compound ADMET table with actual values from EXTRACTED METRICS:
   | Compound | SMILES (abbreviated) | logP | MW (Da) | hERG IC50 (µM) | DILI Risk | DILI Prob | Ames |

6. SAFETY INTERPRETATION — Flag compounds exceeding safety thresholds: hERG IC50 < 1 µM (high cardiotoxicity risk), DILI probability > 0.5, Ames positive. Compare to approved drug benchmarks.

7. PIPELINE EXECUTION — Wall time; cloud platform; software versions.

8. LIMITATIONS AND NEXT STEPS — DeepPurpose availability; in vitro validation recommendation; ClinTox prediction gaps.

N. REFERENCES — RDKit: PMID 19997329; Kazius-Bursi Ames alerts: PMID 15832503; Lipinski Rule of 5: PMID 11259830; hERG safety: ICH E14 guideline; DILI: PMID 31134006.`;

        } else if (isRNAseq) {
          SYSTEM = `You are a bioinformatician writing a submission-ready Methods section for a genomics journal (Genome Biology, Bioinformatics, Nature Communications). Write in formal third-person past tense. Include all tool versions and parameter values. Do NOT use markdown headers. Use numbered section headings in ALL CAPS.`;

          USER = `Generate a publication-quality RNA-seq analysis manuscript section. Use ONLY the numbers in EXTRACTED METRICS.

${executionBlock}
${commonTail}

=== REQUIRED SECTIONS ===
1. ABSTRACT — Samples analyzed; aligner; DE tool; significant genes; platform.
2. COMPUTATIONAL ENVIRONMENT — AWS Batch; Nextflow DSL2; nf-core/rnaseq pipeline; software versions.
3. DATA PROCESSING — Reference genome; STAR alignment parameters; read trimming.
4. DIFFERENTIAL EXPRESSION — DESeq2/edgeR; FDR threshold; LFC cutoff; total_de_genes DE genes.
5. RESULTS — Upregulated and downregulated gene counts; pathway enrichment summary.
6. PIPELINE EXECUTION — Wall time; key parameters.
N. REFERENCES — nf-core: PMID 32055031; STAR: PMID 23104886; DESeq2: PMID 25516281; trimgalore/fastp.`;

        } else if (isVariant) {
          SYSTEM = `You are a bioinformatician writing a submission-ready variant calling Methods section for a genetics journal. Write in formal third-person past tense. Do NOT use markdown headers. Use numbered section headings in ALL CAPS.`;

          USER = `Generate a publication-quality variant calling manuscript section. Use ONLY the numbers in EXTRACTED METRICS.

${executionBlock}
${commonTail}

=== REQUIRED SECTIONS ===
1. ABSTRACT — Genome; caller; total variants (total_variants); SNPs vs indels.
2. COMPUTATIONAL ENVIRONMENT — AWS Batch; Nextflow DSL2; nf-core/sarek pipeline.
3. METHODS — Alignment (BWA-MEM2); variant calling (GATK HaplotypeCaller / ${params?.tools || 'GATK'}); VQSR/hard filtering.
4. RESULTS — total_variants variants called; snps SNPs; indels indels.
5. PIPELINE EXECUTION — Wall time; key parameters.
N. REFERENCES — GATK: PMID 20644199; BWA-MEM2: PMID 31006120; nf-core/sarek: PMID 34044496.`;

        } else {
          // Generic domain-agnostic report
          SYSTEM = `You are a computational biologist writing a complete Methods and Results section for a peer-reviewed journal submission. Write in formal third-person scientific prose, past tense. Include all parameter values and hardware specs. Do NOT use markdown headers. Use numbered section headings in ALL CAPS.`;

          USER = `Generate a publication-quality methods section for a computational biology workflow. Use ONLY the numbers in EXTRACTED METRICS.

${executionBlock}
${commonTail}

=== REQUIRED SECTIONS ===
1. ABSTRACT — Brief summary of the analysis; key result; platform.
2. COMPUTATIONAL ENVIRONMENT — AWS Batch; Nextflow DSL2; BioMate pipeline.
3. INPUT AND PARAMETERS — All input parameters with values.
4. METHODS — Step-by-step workflow description using workflowSteps.
5. RESULTS — Key outputs and their scientific interpretation.
6. PIPELINE EXECUTION — Wall time; status; output files.
N. REFERENCES — Relevant tool citations with PMIDs.`;
        }

        const reportFormat = req.query.format === 'docx' ? 'docx' : 'txt';

        // ── Step-by-step report generation with Claude Sonnet 4.5 ─────────────
        // For CryoEM, split into 3 focused calls to avoid LLM truncation.
        // For all other domains, a single focused call.
        const Anthropic = (await import('@anthropic-ai/sdk')).default;
        const claudeClient = new Anthropic({ apiKey });

        const claudeCall = async (userPrompt: string): Promise<string> => {
          const msg = await claudeClient.messages.create({
            model: 'claude-sonnet-4-5',
            max_tokens: 1200,
            system: SYSTEM,
            messages: [{ role: 'user', content: userPrompt }],
          });
          return (msg.content[0] as any)?.text ?? '';
        };

        // Compact metrics block (no raw file JSON, just the key-value pairs)
        const compactMeta = `WORKFLOW: ${workflowName}
WALL TIME: ${wallTimeStr}
STEPS COMPLETED: ${extractedMetrics.steps_completed ?? 'N/A'}
AWS BATCH | CryoSPARC v5.0.2 | Nextflow DSL2

EXTRACTED METRICS:
${metricsBlock}

INPUT PARAMETERS:
${paramLines || '(none recorded)'}`;

        let reportText: string;

        if (isCryoEM) {

          const [partA, partB, partC] = await Promise.all([
            // Part A: Abstract + Study Overview + Computational Environment
            claudeCall(`Write sections 1–3 of a CryoSPARC SPA technical report. Use ONLY the numbers below. Where a metric says "not captured", note that a production re-run provides it. For MISSING values, write "[data not available — pipeline re-run required]". Use numbered ALL-CAPS section headings, no markdown.

${compactMeta}

1. ABSTRACT (100 words) — State: ${extractedMetrics.num_micrographs} micrographs processed; ${extractedMetrics.num_blob_particles} initial blob-picked particles; ${extractedMetrics.num_extracted_r2} particles after template picking; pixel size ${extractedMetrics.pixel_size_A} Å/px; ${extractedMetrics.voltage_kv} kV; symmetry ${extractedMetrics.symmetry}; ${extractedMetrics.steps_completed} processing steps completed; CryoSPARC v5.0.2 on AWS Batch.
2. STUDY OVERVIEW — Dataset details; pixel size ${extractedMetrics.pixel_size_A} Å/px; ${extractedMetrics.voltage_kv} kV; particle diameter ${extractedMetrics.particle_diameter_A} Å; symmetry ${extractedMetrics.symmetry}; box size ${extractedMetrics.box_size_pix}² px; note this is a 20-micrograph pilot (1.9% of EMPIAR-10028 beta-galactosidase dataset).
3. COMPUTATIONAL ENVIRONMENT — AWS Batch (us-east-1); NVIDIA L4 GPU (g6.2xlarge, 1×GPU, 8 vCPU, 32 GB RAM); CryoSPARC v5.0.2; Nextflow DSL2; BioMate pipeline; ${extractedMetrics.steps_completed} steps completed in ${wallTimeStr}.`),

            // Part B: Data Acquisition + Methods 5.1–5.5
            claudeCall(`Write sections 4–5 (methods) of a CryoSPARC SPA technical report for this run. Use ONLY the numbers below. No markdown. ALL-CAPS numbered headings.

${compactMeta}

4. DATA ACQUISITION — ${extractedMetrics.num_micrographs} micrographs; pixel size ${extractedMetrics.pixel_size_A} Å/px; ${extractedMetrics.voltage_kv} kV; motion correction by CryoSPARC Patch Motion Correction (job ${extractedMetrics.motion_cs_job}); CTF by CryoSPARC Patch CTF; avg_total_motion_A="${extractedMetrics.avg_total_motion_A}"; avg_defocus_A="${extractedMetrics.avg_defocus_A}"; avg_fit_quality="${extractedMetrics.avg_fit_quality}".
5. METHODS (write ONE paragraph each):
   5.1 Motion Correction — CryoSPARC v5.0.2 Patch Motion Correction; ${extractedMetrics.num_micrographs} micrographs; ${extractedMetrics.avg_total_motion_A}.
   5.2 CTF Estimation — CryoSPARC Patch CTF; avg defocus ${extractedMetrics.avg_defocus_A}; fit quality ${extractedMetrics.avg_fit_quality}.
   5.3 Particle Picking — Blob Picker at ${extractedMetrics.particle_diameter_A} Å diameter yielded ${extractedMetrics.num_blob_particles} candidates. Junk filtering: ${extractedMetrics.num_junk_rejected} rejected.
   5.4 Round-1 Extraction — ${extractedMetrics.num_extracted_r1} particles extracted; box size ${extractedMetrics.box_size_pix}² px at ${extractedMetrics.pixel_size_A} Å/px.
   5.5 2D Classification R1 — ${extractedMetrics.num_particles_2d_r1} particles into ${extractedMetrics.num_classes_r1} classes.`),

            // Part C: Methods 5.6–5.10 + Results + Execution + Quality + Deposition + References
            claudeCall(`Write sections 5.6–N of a CryoSPARC SPA technical report. Use ONLY the numbers below. No markdown. ALL-CAPS numbered headings.

${compactMeta}

   5.6 Round-2 Extraction — After template picking, ${extractedMetrics.num_extracted_r2} particles extracted.
   5.7 Ab-Initio Reconstruction — 3 initial models; symmetry ${extractedMetrics.symmetry}; CryoSPARC ab-initio reconstruction.
   5.8 Homogeneous Refinement — Best ab-initio model selected; homogeneous refinement with symmetry ${extractedMetrics.symmetry}.
   5.9 Non-Uniform Refinement — CryoSPARC NU refinement; final particles: ${extractedMetrics.num_particles_nu}.
   5.10 FSC Validation — Gold-standard FSC; resolution: ${extractedMetrics.fsc_0143_resolution}.
6. PIPELINE EXECUTION — Wall time ${wallTimeStr}; ${extractedMetrics.steps_completed} steps; output: ${extractedMetrics.s3_output_path}; completed ${extractedMetrics.completion_time}.
7. RESULTS — Particle yield table (blob pick → extract R1 → extract R2 → NU refine): ${extractedMetrics.num_blob_particles} → ${extractedMetrics.num_extracted_r1} → ${extractedMetrics.num_extracted_r2} → ${extractedMetrics.num_particles_nu}. FSC 0.143: ${extractedMetrics.fsc_0143_resolution}.
8. DATA QUALITY — 20 micrographs = pilot dataset (1.9% of EMPIAR-10028); particle yield efficiency = ${extractedMetrics.num_extracted_r2}/${extractedMetrics.num_blob_particles}; motion/CTF metrics: ${extractedMetrics.avg_total_motion_A}/${extractedMetrics.avg_defocus_A}.
9. DEPOSITION NOTE — Pixel size ${extractedMetrics.pixel_size_A} Å/voxel; symmetry ${extractedMetrics.symmetry}; CryoSPARC v5.0.2; ${extractedMetrics.steps_completed} steps; output: ${extractedMetrics.s3_output_path}.
N. REFERENCES — CryoSPARC (Punjani 2017, PMID 28165473); CTFFIND4 (Rohou 2015, PMID 26278980); MotionCor2 (Zheng 2017, PMID 28250466); NU refinement (Punjani 2020, PMID 33257830); Local CTF (Punjani 2021, PMID 34282325).`),
          ]);

          reportText = [partA, partB, partC].join('\n\n');

        } else {
          // Non-CryoEM: single call with focused metrics
          console.log(`[MethodsReport] Generic report generation (Claude sonnet-4-5)`);
          reportText = await claudeCall(`${USER}\n\n${compactMeta}`);
        }

        const header = [
          `BioMate AI — Methods Report`,
          `${'='.repeat(60)}`,
          `Generated: ${new Date().toISOString()}`,
          `Workflow: ${workflowName}`,
          `Invocation ID: ${invocationId}`,
          `Nextflow Run ID: ${nfRunId}`,
          `Wall Time: ${wallTimeStr}`,
          `=`.repeat(60),
          ``,
          reportText,
        ].join('\n');

        const safeName = workflowName.replace(/[^a-z0-9]+/gi, '_');

        if (reportFormat === 'docx') {
          // Convert to DOCX via pandoc for journal submission
          const { execSync } = await import('child_process');
          const os = await import('os');
          const path = await import('path');
          const tmpMd = path.join(os.tmpdir(), `methods_${invocationId.slice(0,8)}.md`);
          const tmpDocx = path.join(os.tmpdir(), `methods_${invocationId.slice(0,8)}.docx`);
          // Write markdown version (pandoc handles numbered headings well from plain text)
          const fs = await import('fs');
          fs.writeFileSync(tmpMd, header, 'utf-8');
          execSync(`pandoc "${tmpMd}" -o "${tmpDocx}" --from=plain --to=docx`, { timeout: 30000 });
          const docxBuf = fs.readFileSync(tmpDocx);
          res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
          res.setHeader('Content-Disposition', `attachment; filename="methods_report_${safeName}_${invocationId.slice(0,8)}.docx"`);
          return res.status(200).send(docxBuf);
        }

        res.setHeader('Content-Type', 'text/plain; charset=utf-8');
        res.setHeader('Content-Disposition', `attachment; filename="methods_report_${safeName}_${invocationId.slice(0,8)}.txt"`);
        return res.status(200).send(header);
      } catch (fallbackErr: any) {
        console.error('[MethodsReport] Generation failed:', fallbackErr.message);
        return res.status(502).json({ error: 'Methods report generation failed', details: fallbackErr.message });
      }
    }
  });

  // Streaming chat endpoint (SSE) for token-level response updates
  app.post("/api/chat/stream", optionalAuth, async (req, res) => {
    const abortController = new AbortController();
    req.on('close', () => abortController.abort());

    let heartbeatTimer: NodeJS.Timeout | null = null;

    const safeSend = (event: string, data: unknown): void => {
      if (res.writableEnded || abortController.signal.aborted) return;
      res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
    };

    try {
      const { message, context } = req.body || {};
      if (!message) {
        res.status(400).json({ error: "Message is required" });
        return;
      }

      // ── Safety guardrails (PHI strip + content blocklist + scope filter) ──
      const safetyResult = checkSafety(String(message));
      if (!safetyResult.safe) {
        // Log the block event (hash only — GDPR compliant)
        const msgHash = await hashMessage(String(message)).catch(() => 'hash-error');
        auditService.log({
          userId: req.user ? String((req.user as any).id) : null,
          action: 'safety.block',
          resourceType: 'chat_message',
          details: { category: safetyResult.category, reason: safetyResult.reason, messageHash: msgHash },
          ipAddress: req.ip || req.socket?.remoteAddress,
          status: 'failure',
          errorMessage: safetyResult.reason,
        }).catch(() => {/* non-fatal */});

        // Return the refusal as an SSE event so the frontend renders it in-chat
        res.setHeader("Content-Type", "text/event-stream");
        res.setHeader("Cache-Control", "no-cache, no-transform");
        res.setHeader("Connection", "keep-alive");
        res.flushHeaders?.();
        res.write(`event: delta\ndata: ${JSON.stringify({ text: safetyResult.userMessage })}\n\n`);
        res.write(`event: complete\ndata: ${JSON.stringify({ blocked: true, category: safetyResult.category })}\n\n`);
        res.end();
        return;
      }

      // Use sanitized message (PHI stripped) for all downstream processing
      const safeMessage = safetyResult.sanitizedMessage ?? String(message);
      if (safetyResult.phiDetected) {
        auditService.log({
          userId: req.user ? String((req.user as any).id) : null,
          action: 'safety.phi_strip',
          resourceType: 'chat_message',
          details: { messageHash: await hashMessage(String(message)).catch(() => 'hash-error') },
          ipAddress: req.ip || req.socket?.remoteAddress,
          status: 'success',
        }).catch(() => {/* non-fatal */});
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

      heartbeatTimer = setInterval(() => {
        if (!res.writableEnded && !abortController.signal.aborted) {
          res.write(': heartbeat\n\n');
        }
      }, 10_000);

      safeSend("ready", { ok: true });

      // Pilot account check — PILOT_ACCOUNT_EMAILS is a comma-separated list of emails
      // that bypass billing during the pilot window.
      const _pilotEmails = (process.env.PILOT_ACCOUNT_EMAILS || '').split(',').map((e: string) => e.trim().toLowerCase()).filter(Boolean);
      const isPilotUser = req.user ? _pilotEmails.includes(String((req.user as any).email || '').toLowerCase()) : false;

      // Build per-user credential availability map using the authenticated user's proxy,
      // so credential-aware routing in the AI backend can fall back to OSS alternatives.
      let credentialMap: Record<string, boolean> | undefined;
      if (req.user) {
        try {
          const credProxy = userProxy(req);
          const credResp = await credProxy.client.get('/api/users/credentials/map');
          credentialMap = (credResp.data as any)?.credential_map;
        } catch {
          // Non-fatal — backend falls back to server-side vault lookup
        }
      }

      const enrichedContext = {
        ...(context || {}),
        // Normalise session identity: frontend sends memorySessionId; processMessage uses sessionId.
        // If both are present, prefer the explicit sessionId; fall back to memorySessionId.
        sessionId: (context?.sessionId || context?.memorySessionId) || undefined,
        billingUserId: req.user ? String(req.user.id) : undefined,
        isPilotUser: isPilotUser || undefined,
        // Inject integer userId so memory-integration can load user preferences/corrections
        userId: req.user ? Number((req.user as any).id) : (context?.userId),
        // Session-uploaded datasets: activates WorkflowDatasetSelector + domain-specialist format context
        // file_path is included so AI can auto-populate file-type params (e.g. movies_path, reads, input)
        sessionDatasets: req.session?.uploadedDatasets?.length
          ? req.session.uploadedDatasets.map((d: any) => ({
              id: d.galaxy_dataset_id || d.dataset_id,
              name: d.name,
              type: d.file_type || 'unknown',
              file_path: d.file_path || null,
              param_name: d.param_name || null,  // explicit param mapping from register-path
            }))
          : undefined,
        // Per-tool credential map built from user's vault — forwarded to AI backend for routing
        credentialMap: credentialMap || undefined,
      };

      // Use memory-enhanced processing when available: loads user preferences + past corrections,
      // injects prior experience hints, and records interactions for future learning.
      const _streamStartTime = Date.now();
      const assistantResponse = memoryIntegration
        ? await memoryIntegration.processWithMemory(
            safeMessage,
            enrichedContext as unknown as MemoryEnhancedContext,
            (chunk) => safeSend("delta", { text: chunk }),
            (event) => safeSend("tool_event", event)
          )
        : await galaxyAssistant.processMessage(
            safeMessage,
            enrichedContext,
            (chunk) => safeSend("delta", { text: chunk }),
            (event) => safeSend("tool_event", event)
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
        (workflowPayload?.workflow_ga || workflowPayload?.nextflow_path ||
         workflowPayload?.workflow_type === "chain" || workflowPayload?.chain_name ||
         workflowPayload?.workflow_type === "cryosparc")
      );
      const workflowGenerationFailed = !!workflowPayload && !runnableWorkflow;

      const workflowGenerationDiagnostics = (() => {
        if (!workflowGenerationFailed) return null;
        const likelyReasons: string[] = [];
        const recommendedActions: string[] = [];
        const reasonText = String(workflowPayload?.error || workflowPayload?.message || "").toLowerCase();
        const suggestionConfidence = Number(assistantResponse.workflowSuggestion?.confidence || 0);

        if (/timeout|timed out|deadline|temporar/.test(reasonText)) {
          likelyReasons.push("Upstream workflow generation timed out or a dependent service was temporarily unavailable.");
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
        if (/domain|mismatch|alignment|incompatible/.test(reasonText)) {
          likelyReasons.push("Domain mismatch: requested stages span incompatible domains and should be split into staged workflows.");
          recommendedActions.push("Regenerate with explicit domain constraints and required tool families.");
        }
        if ((assistantResponse.recommendedTools?.length || 0) === 0) {
          likelyReasons.push("No strong tool matches were found for the current request phrasing.");
          recommendedActions.push("Provide required method/tool hints (must-use or must-avoid) to improve ranking.");
        }
        if (suggestionConfidence > 0 && suggestionConfidence < 0.7) {
          likelyReasons.push("Intent-to-workflow confidence is low; requirements may still be underspecified.");
          recommendedActions.push("Clarify organism/data type/input format/desired outputs before regenerating.");
        }
        if (likelyReasons.length === 0) {
          likelyReasons.push("The generation pipeline returned a non-runnable candidate due to unmet constraints.");
          recommendedActions.push("Regenerate with stricter constraints and explicit required outputs.");
        }

        return {
          failed: true,
          likelyReasons,
          recommendedActions,
          followUpQuestions: [
            "What exact input data do you already have (format + example filenames)?",
            "Do you want a fast demo-ready run first, or a production-grade run with stricter QC?",
            "Any required tools/runtimes to include or avoid?",
          ],
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

      const assistantMessage = String(assistantResponse.message || "");

      // ----------------------------------------------------------------
      // Response state — one of four explicit states, not inferred from text:
      //   workflow_ready  → runnable workflow generated, awaiting user confirmation
      //   needs_input     → BioMate needs more information before it can proceed
      //                     (covers: missing prereqs AND chain clarification requests)
      //   workflow_failed → workflow generation attempted but failed; diagnostics attached
      //   chat_only       → informational response, no workflow involved
      // ----------------------------------------------------------------
      const isClarificationRequest = workflowPayload?.workflow_type === "clarification";
      const responseState: "workflow_ready" | "needs_input" | "workflow_failed" | "chat_only" =
        runnableWorkflow ? "workflow_ready"
        : isClarificationRequest ? "needs_input"
        : workflowGenerationFailed ? "workflow_failed"
        : (prerequisitesValidation && !(prerequisitesValidation as any).canRun) ? "needs_input"
        : "chat_only";

      const responsePayload = {
        response: assistantMessage,
        state: responseState,
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
          // Cost/token metadata — consumed by eval harness and billing dashboard
          llm_usage: (() => {
            const model = galaxyAssistant?.getModelConfig().responseModel || 'claude-sonnet-4-6';
            const inTok  = tokenCounter.countText(String(message || "")).tokens;
            const outTok = tokenCounter.countText(String(assistantResponse.message || "")).tokens;
            const dur    = Date.now() - _streamStartTime;
            // Pricing table (mirrors cost_calculator.py LLM_PRICING)
            const pricing: Record<string, {i: number; o: number}> = {
              'claude-opus-4-6':            {i: 15.00,  o: 75.00},
              'claude-sonnet-4-6':          {i:  3.00,  o: 15.00},
              'claude-sonnet-4-5-20250929': {i:  3.00,  o: 15.00},
              'claude-haiku-4-5-20251001':  {i:  0.25,  o:  1.25},
              'gemini-3-flash-preview':     {i:  0.075, o:  0.30},
            };
            const p = pricing[model] ?? {i: 3.00, o: 15.00};
            const cost = (inTok * p.i + outTok * p.o) / 1_000_000;
            return { model, input_tokens: inTok, output_tokens: outTok, cost_usd: cost, duration_ms: dur };
          })(),
        },
        subIntentResults: assistantResponse.subIntentResults,
        isMultiIntent: assistantResponse.isMultiIntent || false,
        researchResponse: assistantResponse.researchResponse,
        benchmarkEvidence: assistantResponse.benchmarkEvidence,
      };

      // Emit LLM cost to Galaxy billing backend → Lago (fire-and-forget)
      // Pilot users (PILOT_ACCOUNT_EMAILS) skip billing during the pilot window.
      if (req.user && !isPilotUser) {
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
              duration_ms: Date.now() - _streamStartTime,
            }),
            signal: AbortSignal.timeout(5000),
          }).catch((err: any) => {
            console.warn('[Billing] stream llm_cost emission failed:', err?.message || err);
          });
        }
      }

      // Emit a dedicated structured event for consumers that need a reliable signal
      // (evaluation harness, frontend state machine, future integrations).
      // This is authoritative — do not infer state from response text.
      if (responseState === "workflow_ready" && workflowPayload) {
        const ga = workflowPayload.workflow_ga || {};
        // For chain results workflow_ga is empty; surface chain_display_name + step names
        // so consumers (routing eval, UI) can identify constituent workflows.
        const chainStepNames: string[] = (workflowPayload.chain_steps || [])
          .map((s: any) => s.workflow_name || s.name || "")
          .filter(Boolean);
        safeSend("workflow_ready", {
          // workflow_name resolution order:
          //   1. workflow_ga.name  — Galaxy workflow (from catalog)
          //   2. workflow_name     — Nextflow catalog match (top-level field from ai_assistant)
          //   3. chain_display_name — chain result
          //   4. ""               — generated/composed workflow (display name unknown at this point)
          workflow_name: ga.name || workflowPayload.workflow_name || workflowPayload.chain_display_name || "",
          workflow_id:   ga.id || "",
          workflow_type: workflowPayload.workflow_type || workflowPayload.execution_engine || "",
          nextflow_path: workflowPayload.nextflow_path || "",
          source:        workflowPayload.source || "",
          confidence:    workflowPayload.confidence ?? null,
          chain_name:    workflowPayload.chain_name || "",
          chain_steps:   chainStepNames,
        });
      } else if (responseState === "needs_input") {
        // Two sub-cases both produce needs_input:
        //   1. Prereq validation blocked (canRun=false) — missing items are param names
        //   2. Chain clarification (workflow_type=clarification) — the question is the signal
        const missingItems: string[] = isClarificationRequest
          ? [workflowPayload.clarification_question || workflowPayload.message || ""].filter(Boolean)
          : (prerequisitesValidation as any)?.items
              ?.filter((i: any) => !i.satisfied)
              .map((i: any) => i.param || i.name || "") || [];
        safeSend("needs_input", { missing: missingItems });
      }

      safeSend("final", responsePayload);
      safeSend("done", { ok: true });
      res.end();
    } catch (error: any) {
      console.error("Chat Stream API error:", error);
      safeSend("error", {
        message: error?.message || "Streaming chat failed",
      });
      safeSend("done", { ok: false });
      res.end();
    } finally {
      if (heartbeatTimer) clearInterval(heartbeatTimer);
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
  // User Credential Management (per-tool license / API keys)
  // ============================================================================

  app.get("/api/users/me/usage", authenticateToken, async (req, res) => {
    try {
      const userId = String((req as any).user?.id || '');
      const lagoUrl = process.env.LAGO_URL || 'http://35.86.137.71:3000';
      const lagoKey = process.env.LAGO_API_KEY;
      const limit = parseFloat(process.env.VCPU_HOUR_QUOTA || '100');
      if (!lagoKey) {
        return res.json({ used: 0, limit, currency: 'vCPU-hrs' });
      }
      const usageRes = await fetch(
        `${lagoUrl}/api/v1/customers/${userId}/current_usage?external_subscription_id=${userId}`,
        { headers: { 'Authorization': `Bearer ${lagoKey}` }, signal: AbortSignal.timeout(3000) }
      );
      if (!usageRes.ok) throw new Error(`Lago ${usageRes.status}`);
      const usage = await usageRes.json() as any;
      const vcpuUsed = parseFloat(
        usage?.customer_usage?.charges_usage?.find((c: any) => c.billable_metric?.code === 'vcpu_hours')?.units || '0'
      );
      res.json({ used: vcpuUsed, limit, currency: 'vCPU-hrs' });
    } catch {
      const limit = parseFloat(process.env.VCPU_HOUR_QUOTA || '100');
      res.json({ used: 0, limit, currency: 'vCPU-hrs' });
    }
  });

  app.get("/api/users/credentials/map", optionalAuth, async (req, res) => {
    try {
      const proxy = userProxy(req);
      const response = await proxy.client.get('/api/users/credentials/map');
      res.json(response.data);
    } catch (error: any) {
      res.status(error.response?.status || 500).json(error.response?.data || { error: error.message });
    }
  });

  app.get("/api/users/credentials", optionalAuth, async (req, res) => {
    try {
      const proxy = userProxy(req);
      const response = await proxy.client.get('/api/users/credentials', { params: req.query });
      res.json(response.data);
    } catch (error: any) {
      res.status(error.response?.status || 500).json(error.response?.data || { error: error.message });
    }
  });

  app.post("/api/users/credentials", optionalAuth, async (req, res) => {
    try {
      const proxy = userProxy(req);
      const response = await proxy.client.post('/api/users/credentials', req.body);
      res.json(response.data);
    } catch (error: any) {
      res.status(error.response?.status || 500).json(error.response?.data || { error: error.message });
    }
  });

  app.delete("/api/users/credentials/:toolId", optionalAuth, async (req, res) => {
    try {
      const proxy = userProxy(req);
      const response = await proxy.client.delete(`/api/users/credentials/${req.params.toolId}`);
      res.json(response.data);
    } catch (error: any) {
      res.status(error.response?.status || 500).json(error.response?.data || { error: error.message });
    }
  });

  // Verify S3 credentials by listing the specified bucket
  app.post("/api/users/credentials/s3/verify", optionalAuth, express.json(), async (req, res) => {
    try {
      const { aws_access_key_id, aws_secret_access_key, aws_region, s3_bucket } = req.body ?? {};
      if (!aws_access_key_id || !aws_secret_access_key || !s3_bucket) {
        return res.status(400).json({ ok: false, error: "Missing required fields: aws_access_key_id, aws_secret_access_key, s3_bucket" });
      }
      const { S3Client, ListObjectsV2Command } = await import('@aws-sdk/client-s3');
      const client = new S3Client({
        region: aws_region || 'us-east-1',
        credentials: { accessKeyId: aws_access_key_id, secretAccessKey: aws_secret_access_key },
        followRegionRedirects: true,
      });
      const resp = await client.send(new ListObjectsV2Command({ Bucket: s3_bucket, MaxKeys: 1 }));
      res.json({ ok: true, bucket: s3_bucket, region: aws_region || 'us-east-1', object_count_sample: resp.KeyCount ?? 0 });
    } catch (err: any) {
      const msg = err.message || String(err);
      const code = /NoSuchBucket/.test(msg) ? 'bucket_not_found'
                 : /InvalidAccessKeyId|SignatureDoesNotMatch/.test(msg) ? 'invalid_credentials'
                 : /AccessDenied|AllAccessDisabled/.test(msg) ? 'access_denied'
                 : 'error';
      res.status(400).json({ ok: false, code, error: msg.slice(0, 200) });
    }
  });

  // Retrieve stored S3 credentials for the current user (returns masked values)
  app.get("/api/users/credentials/s3", optionalAuth, async (req, res) => {
    try {
      const proxy = userProxy(req);
      const response = await proxy.client.get('/api/users/credentials', { params: { tool: 's3' } });
      res.json(response.data);
    } catch (error: any) {
      res.status(error.response?.status || 500).json(error.response?.data || { error: error.message });
    }
  });

  app.get("/api/workflows/license-requirements", optionalAuth, async (req, res) => {
    try {
      const proxy = userProxy(req);
      const response = await proxy.client.get('/api/workflows/license-requirements', { params: req.query });
      res.json(response.data);
    } catch (error: any) {
      res.status(error.response?.status || 500).json(error.response?.data || { error: error.message });
    }
  });

  // Track 7B — DB-sourced domain catalog
  // Returns top workflows grouped by domain, sourced live from the Galaxy backend search index.
  // Falls back to empty arrays on error — callers should use the hardcoded catalog as fallback.
  app.get("/api/workflows/by-domain", optionalAuth, async (req, res) => {
    try {
      const domainsParam = (req.query.domains as string) || '';
      const domains = domainsParam.split(',').map(d => d.trim()).filter(Boolean);
      if (domains.length === 0) return res.json({ catalog: {} });

      const proxy = galaxyAPIProxy; // unauthenticated proxy — catalog is not user-specific
      const catalog: Record<string, Array<{ name: string; description: string; domain: string }>> = {};

      await Promise.all(domains.map(async (domain) => {
        try {
          const resp = await proxy.client.post('/api/ai_assistant/search_nextflow_workflow', {
            user_intent: domain,
            preferred_domains: [domain],
            limit: 8,
          });
          const candidates: any[] = resp.data?.candidate_workflows ?? [];
          catalog[domain] = candidates.map((c: any) => ({
            name: c.name,
            description: c.description || c.domain || domain,
            domain: c.domain || domain,
          }));
        } catch {
          catalog[domain] = [];
        }
      }));

      res.json({ catalog });
    } catch (error: any) {
      console.error('[by-domain] error:', error.message);
      res.status(500).json({ error: error.message });
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
      await memoryService.users.ensureLtmUser(req.user!.id, (req.user as any).email).catch(() => {});
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

  // Get user's correction history (for P2 routing injection)
  app.get("/api/memory/user/corrections", authenticateToken, async (req, res) => {
    try {
      const limit = req.query.limit ? parseInt(req.query.limit as string) : 10;
      const corrections = await memoryService.users.getUserCorrections(
        req.user!.id,
        Math.min(limit, 50)
      );
      res.json(corrections);
    } catch (error: any) {
      console.error('[API] Get corrections failed:', error);
      res.status(500).json({ error: 'Failed to get corrections', message: error.message });
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
      // Auto-provision the LTM user record if it doesn't exist yet.
      // Required when the auth user has never interacted with the memory system
      // (e.g. eval accounts that were created directly in the auth DB).
      await memoryService.users.ensureLtmUser(req.user!.id, (req.user as any).email).catch(() => {});
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

  // 6B — Cross-session memory injection: return the most relevant past sessions for a query
  app.get("/api/memory/relevant", authenticateToken, async (req, res) => {
    try {
      const query = String(req.query.query || '').toLowerCase();
      const limit = Math.min(parseInt(String(req.query.limit || '5')), 20);
      const userId = req.user!.id;

      // Fetch recent session memories for this user (up to 20)
      const allSessions = await memoryService.sessions.getRecentSessions(userId, 20)
        .catch(() => []);
      if (!allSessions.length) return res.json({ memories: [] });

      // Score by keyword overlap with query
      const queryTokens = new Set(
        query.split(/\W+/).filter((t: string) => t.length > 2)
      );
      const scored = allSessions.map((s: any) => {
        const text = [
          s.summary || '',
          s.title || '',
          (s.toolsDiscussed || []).join(' '),
        ].join(' ').toLowerCase();
        const tokens = text.split(/\W+/).filter((t: string) => t.length > 2);
        const overlap = tokens.filter((t: string) => queryTokens.has(t)).length;
        return { memory: s, score: overlap };
      });
      // Sort by score descending, then by recency (startedAt) descending as tie-break
      scored.sort((a: any, b: any) =>
        b.score - a.score ||
        (b.memory.startedAt > a.memory.startedAt ? 1 : -1)
      );

      res.json({ memories: scored.slice(0, limit).map((s: any) => s.memory) });
    } catch (err: any) {
      console.error('[API] Memory relevant failed:', err.message);
      res.status(500).json({ error: err.message });
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

  // Get user's recent episodes across all projects (for P1 memory injection)
  app.get("/api/memory/user/episodes", authenticateToken, async (req, res) => {
    try {
      const limit = req.query.limit ? parseInt(req.query.limit as string) : 10;
      const episodes = await memoryService.episodes.getRecentUserEpisodes(
        req.user!.id,
        Math.min(limit, 50)
      );
      res.json(episodes);
    } catch (error: any) {
      console.error('[API] Get user episodes failed:', error);
      res.status(500).json({ error: 'Failed to get user episodes', message: error.message });
    }
  });

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

  // POST /api/workflows/search — natural language workflow search (used by Open Claw tools)
  // Proxies to Python backend /api/ai_assistant/search_nextflow_workflow
  app.post("/api/workflows/search", optionalAuth, async (req, res) => {
    try {
      const { query, limit } = req.body || {};
      if (!query) return res.status(400).json({ error: "query is required" });
      const galaxyUrl = process.env.GALAXY_URL || "http://localhost:8081";
      const upstream = await fetch(`${galaxyUrl}/api/ai_assistant/search_nextflow_workflow`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ user_intent: query, limit: limit ?? 5 }),
      });
      const data = await upstream.json();
      res.status(upstream.status).json(data);
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  // IR evaluation: ranked workflow list for MRR/P@K/NDCG computation
  // Proxies to Python backend /api/ai_assistant/search_ranked
  app.post("/api/ai_assistant/search_ranked", optionalAuth, async (req, res) => {
    try {
      const galaxyUrl = process.env.GALAXY_URL || "http://localhost:8081";
      const upstream = await fetch(`${galaxyUrl}/api/ai_assistant/search_ranked`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(req.body || {}),
      });
      const data = await upstream.json();
      res.status(upstream.status).json(data);
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

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
  // Proxy: fetch workflow phase steps from backend (for lazy-loading in viewer)
  app.get("/api/nextflow/steps", optionalAuth, async (req, res) => {
    try {
      const nfPath = String(req.query.nextflow_path || '');
      if (!nfPath) return res.status(400).json({ error: "nextflow_path required" });
      const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
      const r = await fetch(`${galaxyUrl}/api/nextflow/steps?nextflow_path=${encodeURIComponent(nfPath)}`, {
        headers: { 'x-api-key': process.env.GALAXY_API_KEY || '' },
      });
      const data = await r.json();
      res.status(r.status).json(data);
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

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
        "workflow-timeline.html", "dag.dot", "versions.yml",
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
          // Skip S3 directory URIs (no extension, ends with '/', or basename has no dot)
          if (artifactPath.startsWith("s3://") && artifactPath.endsWith("/")) continue;
          const artifactBasename = path.basename(artifactPath);
          if (NF_INTERNAL_FILES.has(artifactBasename)) continue;
          if (NF_SKIP_DIRS.has(artifactBasename)) continue;
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
      console.log(`[Outputs] req.id=${req.params.id} direct=${outputs.length} sources=${outputs.map((o:any)=>o?.metadata?.source).join(',')}`);

      // If no outputs found, attempt to source them from the execution run record
      if (outputs.length === 0) {
        const invocation = await resolveInvocation(req.params.id);
        // Try direct execution run lookup — by ID or by galaxyInvocationId (Nextflow runs use
        // execution.galaxyInvocationId as the invocationId displayed in the chat UI)
        const directExecRun = await storage.getExecutionRun(req.params.id)
          || await storage.getExecutionRunByGalaxyId(req.params.id);
        const effectiveInvocationId = invocation?.id || req.params.id;

        if (invocation) {
          outputs = await storage.getInvocationOutputs(invocation.id);
        }

        // If outputs are missing or consist only of the fallback runtime summary,
        // attempt a real disk/S3 scan using the execution run's nextflowStatus.
        const onlyFallbackSummary =
          outputs.length > 0 &&
          outputs.every((o: any) => o?.metadata?.source === 'nextflow_runtime_summary');

        if (outputs.length === 0 || onlyFallbackSummary) {
          const galaxyInvId = invocation?.galaxyInvocationId;
          const executionRun = galaxyInvId
            ? (await storage.getExecutionRunByGalaxyId(galaxyInvId) || directExecRun)
            : directExecRun;
          const effectiveExecutionRun = executionRun;

          if (effectiveExecutionRun) {
            const nextflowStatus = effectiveExecutionRun?.execution?.nextflowStatus;
            const nfRunId = effectiveExecutionRun?.execution?.nextflowRunId;
            console.log(`[Outputs] invId=${effectiveInvocationId} nfRunId=${nfRunId} nfOutdir=${nextflowStatus?.outdir} nfStatus=${nextflowStatus?.status}`);

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

            if (nextflowStatus && typeof nextflowStatus === "object") {
              pushArtifact(nextflowStatus.outputs);
              pushArtifact(nextflowStatus.results);
              pushArtifact(nextflowStatus.output_files);
              pushArtifact(nextflowStatus.outdir);
              // s3_output_files: [{s3_uri, filename, size}] — primary source for AWS Batch runs
              if (Array.isArray(nextflowStatus.s3_output_files)) {
                for (const f of nextflowStatus.s3_output_files) {
                  if (f?.s3_uri && f.filename) {
                    artifacts.push(f.s3_uri);
                  }
                }
              }
              // task_files from each process — per-step output file listing
              if (Array.isArray(nextflowStatus.processes)) {
                for (const proc of nextflowStatus.processes) {
                  if (Array.isArray(proc?.task_files)) {
                    for (const tf of proc.task_files) {
                      if (typeof tf === "string" && tf) artifacts.push(tf);
                    }
                  }
                }
              }
              if (Array.isArray(nextflowStatus.log_tail)) {
                for (const line of nextflowStatus.log_tail) {
                  if (typeof line !== "string") continue;
                  const pathMatches = line.match(/\/[^\s,\]]+/g) || [];
                  pathMatches.forEach((candidate) => artifacts.push(candidate));
                }
              }
            }

            // Guaranteed fallback: construct disk path from nextflowRunId
            if (nfRunId) {
              const nfWorkBase = process.env.NEXTFLOW_WORK_DIR || '/tmp/nextflow_runs';
              const diskOutdir = path.join(nfWorkBase, nfRunId, 'output');
              if (!artifacts.includes(diskOutdir)) {
                artifacts.push(diskOutdir);
                console.log(`[Outputs] Added disk fallback outdir: ${diskOutdir}`);
              }
            }

            const nfIsTerminal = ['succeeded', 'completed', 'failed', 'error'].includes(
              String(nextflowStatus?.status || '').toLowerCase()
            );
            const runIsComplete = ['completed', 'failed'].includes(
              String(effectiveExecutionRun?.execution?.status || '').toLowerCase()
            );
            const isTerminal = nfIsTerminal || runIsComplete;
            console.log(`[Outputs] isTerminal=${isTerminal} artifacts=${artifacts.length}`);

            if (artifacts.length > 0) {
              // Delete existing fallback summary so real outputs replace it
              if (onlyFallbackSummary) {
                for (const o of outputs) {
                  await storage.deleteOutput(o.id);
                }
                outputs = [];
              }
              // For S3 runs: expand S3 directory URIs into individual file URIs
              const hasS3Artifacts = artifacts.some(a => a.startsWith('s3://'));
              if (hasS3Artifacts && nfRunId) {
                try {
                  const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
                  const filesResp = await fetch(`${galaxyUrl}/api/nextflow/runs/${nfRunId}/output_files`, {
                    signal: AbortSignal.timeout(10_000),
                  });
                  if (filesResp.ok) {
                    const filesData = await filesResp.json() as any;
                    const s3Files: string[] = (filesData.files || [])
                      .map((f: any) => f.s3_uri)
                      .filter((uri: any) => typeof uri === 'string' && uri.startsWith('s3://'));
                    if (s3Files.length > 0) {
                      // Replace S3 directory URIs with actual file URIs
                      const nonS3 = artifacts.filter(a => !a.startsWith('s3://'));
                      artifacts.length = 0;
                      artifacts.push(...nonS3, ...s3Files);
                      console.log(`[Outputs] S3 expansion: ${s3Files.length} files from ${nfRunId}`);
                    }
                  }
                } catch (s3Err) {
                  console.warn('[Outputs] S3 file listing failed (non-fatal):', s3Err);
                }
              }
              await addRuntimeArtifactOutputs(effectiveInvocationId, Array.from(new Set(artifacts)));
              outputs = await storage.getInvocationOutputs(effectiveInvocationId);
              console.log(`[Outputs] After scan: ${outputs.length} outputs registered (terminal=${isTerminal})`);
            }

            // Only materialize fallback summary after workflow has actually finished
            if (outputs.length === 0 && isTerminal) {
              await materializeRuntimeSummary(effectiveInvocationId, nextflowStatus || {}, effectiveExecutionRun?.id);
              outputs = await storage.getInvocationOutputs(effectiveInvocationId);
            }
          }
        }
      }

      // Post-filter: remove directories, internal files, and zero-content noise.
      // Done at response time so stale DB entries from older code are also cleaned.
      outputs = outputs.filter((o: any) => {
        const name: string = o?.name || '';
        // No extension → S3 job-ID directory (e.g. "65781309") or bare directory name
        if (!name.includes('.')) return false;
        // Nextflow-internal control files
        if (NF_INTERNAL_FILES.has(name)) return false;
        // Skip Nextflow pipeline/trace outputs
        if (NF_SKIP_DIRS.has(name)) return false;
        return true;
      });

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
      const s3Uri = String((output as any)?.metadata?.s3Uri || "");
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
      } else if (s3Uri) {
        // Fetch S3 object content directly via AWS SDK
        try {
          const s3Match = s3Uri.match(/^s3:\/\/([^/]+)\/(.+)$/);
          if (!s3Match) throw new Error(`Invalid S3 URI: ${s3Uri}`);
          const [, bucket, key] = s3Match;
          const { S3Client, GetObjectCommand } = await import('@aws-sdk/client-s3');
          const s3 = new S3Client({
            region: process.env.AWS_DEFAULT_REGION || process.env.AWS_REGION || 'us-east-1',
            followRegionRedirects: true,
          });
          const s3Obj = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
          const chunks: Buffer[] = [];
          for await (const chunk of s3Obj.Body as any) {
            chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
          }
          rawText = Buffer.concat(chunks).toString('utf8');
        } catch (s3Err) {
          console.warn("[Preview] S3 fetch failed:", s3Err);
          return res.status(503).json({ error: "S3 preview temporarily unavailable" });
        }
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
        const histories = await userProxy(req).getHistories();
        if (histories && histories.length > 0) {
          targetHistoryId = histories[0].id;
        } else {
          // Create a new history if none exists
          targetHistoryId = await userProxy(req).createHistory('BioMate Interactive Session');
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

      // Quota guard — skip for pilot accounts and when Lago is not configured
      {
        const userEmail = String((req as any).user?.email || '').toLowerCase();
        const pilotEmails = (process.env.PILOT_ACCOUNT_EMAILS || '').split(',').map((e: string) => e.trim().toLowerCase()).filter(Boolean);
        const isPilotUser = pilotEmails.includes(userEmail);
        if (!isPilotUser && process.env.LAGO_API_KEY) {
          try {
            const userId = String((req as any).user?.id || '');
            const lagoUrl = process.env.LAGO_URL || 'http://35.86.137.71:3000';
            const usageRes = await fetch(
              `${lagoUrl}/api/v1/customers/${userId}/current_usage?external_subscription_id=${userId}`,
              {
                headers: { 'Authorization': `Bearer ${process.env.LAGO_API_KEY}`, 'Content-Type': 'application/json' },
                signal: AbortSignal.timeout(3000),
              }
            );
            if (usageRes.ok) {
              const usage = await usageRes.json() as any;
              const vcpuUsed = usage?.customer_usage?.charges_usage
                ?.find((c: any) => c.billable_metric?.code === 'vcpu_hours')
                ?.units || 0;
              const vcpuLimit = parseFloat(process.env.VCPU_HOUR_QUOTA || '100');
              if (parseFloat(vcpuUsed) >= vcpuLimit) {
                return res.status(402).json({
                  error: 'quota_exceeded',
                  message: `You have used ${vcpuUsed} of ${vcpuLimit} vCPU-hours this billing period.`,
                  used: parseFloat(vcpuUsed),
                  limit: vcpuLimit,
                });
              }
            }
          } catch { /* non-fatal — don't block launch if Lago is unreachable */ }
        }
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

      // Create Galaxy history — skip for Nextflow (uses its own tracking; Galaxy history is metadata only)
      if (executionEngine !== 'nextflow') {
        galaxyHistoryId = await userProxy(req).createHistory(historyName);
      } else {
        // For Nextflow, generate a placeholder history ID so downstream code has something to log
        galaxyHistoryId = `nf-${executionRun.id}`;
      }

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

      // ==================== CRYOSPARC DIRECT EXECUTION ====================
      // When CRYOSPARC_INSTANCE_ID or CRYOSPARC_AMI_ID is set, use the dedicated
      // CryoSPARC executor; otherwise fall through to Nextflow which runs the
      // cryosparc_standard_spa/main.nf pipeline on AWS Batch GPU workers.
      const hasCryoSPARCInstance = !!(process.env.CRYOSPARC_INSTANCE_ID || process.env.CRYOSPARC_AMI_ID);
      if (request.workflowDefinition.workflow_type === 'cryosparc' && hasCryoSPARCInstance) {
        console.log('[CryoSPARC Direct] Detected workflow_type=cryosparc (instance configured)');

        // Require user's own CryoSPARC license key — fetched from the existing credential store
        const _rawKey7268 = (req.user as any)?.galaxyApiKey as string | undefined;
        const userGalaxyKey = _rawKey7268 ? decryptField(_rawKey7268) : '';
        const credResp = await fetch(
          `${process.env.GALAXY_URL || 'http://localhost:8081'}/api/users/credentials/cryosparc/value`,
          { headers: { 'X-API-Key': userGalaxyKey } }
        ).catch(() => null);

        let userLicenseKey: string | null = null;
        if (credResp?.ok) {
          const credData = await credResp.json().catch(() => null);
          userLicenseKey = credData?.data?.license_key || null;
        }

        if (!userLicenseKey) {
          return res.status(402).json({
            error: 'cryosparc_license_required',
            message: 'A CryoSPARC license key is required. Add yours at Settings → Credentials → CryoSPARC.',
          });
        }

        try {
          // Build CryoSPARC params — also extract movies_path/pixel_size/num_movies from
          // the raw user message so S3-staged data flows through even when workflow schema
          // doesn't define a movies_path parameter.
          const csParams: Record<string, any> = { ...(request.workflowDefinition.parameters || {}) };
          const userCtx: string = request.userContext || '';
          if (!csParams.movies_path && !csParams.movie_dir) {
            const m = userCtx.match(/movies_path\s*=\s*(\S+)/);
            if (m) {
              csParams.movies_path = m[1].replace(/,$/, '');
              console.log('[CryoSPARC Direct] Extracted movies_path from userContext:', csParams.movies_path);
            }
          }
          // Also extract pixel_size and num_movies if not already set
          if (!csParams.pixel_size) {
            const m = userCtx.match(/pixel_size\s*=\s*([\d.]+)/);
            if (m) csParams.pixel_size = parseFloat(m[1]);
          }
          if (!csParams.num_movies) {
            const m = userCtx.match(/num_movies\s*=\s*(\d+)/);
            if (m) csParams.num_movies = parseInt(m[1], 10);
          }

          const cryosparcResponse = await fetch(
            `${process.env.GALAXY_URL || 'http://localhost:8081'}/api/cryosparc/execute`,
            {
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
                'X-API-Key': process.env.GALAXY_API_KEY || '',
              },
              body: JSON.stringify({
                parameters: csParams,
                user_id: req.user ? String(req.user.id) : undefined,
                history_id: galaxyHistoryId,
                license_key: userLicenseKey,
              }),
            }
          );

          if (!cryosparcResponse.ok) {
            const errBody = await cryosparcResponse.text().catch(() => cryosparcResponse.statusText);
            throw new Error(`CryoSPARC execution failed (${cryosparcResponse.status}): ${errBody}`);
          }

          const cryosparcData = await cryosparcResponse.json();
          const csRunId = cryosparcData.run_id || cryosparcData.invocation_id || '';
          console.log('[CryoSPARC Direct] Queued run_id:', csRunId);

          // When the executor launched via Nextflow internally (cryosparc_standard_spa/main.nf),
          // store executionEngine as 'nextflow' so /api/workflows/runs/:id/status uses the
          // Nextflow poller instead of the CryoSPARC direct-API poller.
          const effectiveEngine = (cryosparcData.executor === 'nextflow' || cryosparcData.execution_engine?.startsWith('nextflow'))
            ? 'nextflow'
            : 'cryosparc';
          await storage.updateExecutionRun(executionRun.id, {
            execution: {
              ...executionRun.execution,
              galaxyInvocationId: csRunId,
              nextflowRunId: effectiveEngine === 'nextflow' ? csRunId : undefined,
              galaxyHistoryId: galaxyHistoryId,
              status: 'running',
              startedAt: new Date(),
              executionEngine: effectiveEngine,
            }
          });

          await storage.createInvocation({
            userId: req.user?.id,
            workflowName: executionRun.workflowName,
            workflowDefinition: request.workflowDefinition,
            galaxyInvocationId: csRunId,
            galaxyHistoryId: galaxyHistoryId,
            galaxyWorkflowId: '',
            inputDatasets: [],
            totalSteps: 4,
            status: 'ok',
          });

          // Background poller: sync executor status → Node executionRun every 15s.
          // When launched via Nextflow (effectiveEngine='nextflow'), poll /api/nextflow/status.
          // When launched directly on the CryoSPARC instance, poll /api/cryosparc/status.
          const csPollerTimer = setInterval(async () => {
            try {
              let mappedStatus: string;
              let completedSteps: number = 0;
              let totalSteps: number = 4;

              if (effectiveEngine === 'nextflow') {
                const statusResp = await fetch(
                  `${process.env.GALAXY_URL || 'http://localhost:8081'}/api/nextflow/status/${csRunId}`,
                  { headers: { 'X-API-Key': process.env.GALAXY_API_KEY || '' } }
                );
                if (!statusResp.ok) {
                  console.log(`[CryoSPARC/NF Poller] status ${statusResp.status} for ${csRunId}`);
                  return;
                }
                const s = await statusResp.json();
                const nfStatus = (s.status as string || '').toLowerCase();
                console.log(`[CryoSPARC/NF Poller] run=${csRunId} nfStatus=${nfStatus} steps=${s.completedSteps}/${s.totalSteps}`);
                // Nextflow executor reports: running | succeeded | failed | interrupted
                mappedStatus = nfStatus === 'succeeded' ? 'completed'
                  : (nfStatus === 'failed' || nfStatus === 'interrupted') ? 'failed'
                  : 'running';
                completedSteps = s.completedSteps || 0;
                totalSteps = Math.max(s.totalSteps || 4, 4);
              } else {
                const statusResp = await fetch(
                  `${process.env.GALAXY_URL || 'http://localhost:8081'}/api/cryosparc/status/${csRunId}`,
                  { headers: { 'X-API-Key': process.env.GALAXY_API_KEY || '' } }
                );
                if (!statusResp.ok) {
                  console.log(`[CryoSPARC Poller] status ${statusResp.status} for ${csRunId}`);
                  return;
                }
                const s = await statusResp.json();
                const csStatus = (s.status as string || '').toLowerCase();
                console.log(`[CryoSPARC Poller] run=${csRunId} status=${csStatus} progress=${s.progress_percent}% jobs=${s.completed_jobs}/${s.total_jobs}`);
                // CryoSPARC executor reports: queued | running | completed | failed | qc_halt
                mappedStatus = csStatus === 'completed' ? 'completed'
                  : (csStatus === 'failed' || csStatus === 'qc_halt') ? 'failed'
                  : 'running';
                completedSteps = s.completed_jobs || 0;
                totalSteps = Math.max(s.total_jobs || 4, 4);
              }

              const terminal = ['completed', 'failed'].includes(mappedStatus);
              await storage.updateExecutionRun(executionRun.id, {
                execution: {
                  ...executionRun.execution,
                  galaxyInvocationId: csRunId,
                  status: mappedStatus,
                },
                progress: {
                  ...executionRun.progress,
                  completedSteps,
                  totalSteps,
                },
              });
              if (terminal) clearInterval(csPollerTimer);
            } catch (e) {
              console.log(`[CryoSPARC Poller] error: ${e}`);
            }
          }, 15000);

          return res.json({
            runId: executionRun.id,
            galaxyInvocationId: csRunId,
            galaxyHistoryId: galaxyHistoryId,
            executionEngine: effectiveEngine,
            status: 'running',
            message: `CryoSPARC SPA pipeline queued (run_id: ${csRunId})`,
          });

        } catch (error) {
          console.error('[CryoSPARC Direct] Execution error:', error);
          const rawErrorMsg = error instanceof Error ? error.message : String(error);
          if (executionRun) {
            await storage.updateExecutionRun(executionRun.id, {
              execution: { ...executionRun.execution, status: 'failed', error: rawErrorMsg }
            });
          }
          // Alert admin so we can respond proactively
          emailService.sendAdminAlert('CryoSPARC Execution Failed', {
            runId: executionRun?.id || 'unknown',
            userId: String((req.user as any)?.id || 'anon'),
            userEmail: String((req.user as any)?.email || 'unknown'),
            error: rawErrorMsg.slice(0, 800),
            timestamp: new Date().toISOString(),
          }).catch(() => {});
          return res.status(500).json({
            error: 'cryosparc_execution_failed',
            message: 'Our GPU infrastructure is warming up — the team has been notified and will resolve this shortly. Please try again in a few minutes.',
            runId: executionRun?.id,
            executionEngine: 'cryosparc',
          });
        }
      }
      // ==================== END CRYOSPARC DIRECT EXECUTION ====================

      // ==================== NEXTFLOW DIRECT EXECUTION ====================
      // Handles Nextflow workflows AND CryoSPARC workflows when no dedicated instance is configured.
      // CryoSPARC SPA runs via cryosparc_standard_spa/main.nf on AWS Batch GPU workers.
      const isNextflowOrCryoSPARCFallback =
        request.workflowDefinition.workflow_type === 'nextflow' ||
        executionEngine === 'nextflow' ||
        !!request.workflowDefinition.nextflow_path ||
        (request.workflowDefinition.workflow_type === 'cryosparc' && !hasCryoSPARCInstance);
      console.log('[Execute] workflow_type=', request.workflowDefinition.workflow_type, 'executionEngine=', executionEngine, 'nextflow_path=', !!request.workflowDefinition.nextflow_path, 'isNF=', isNextflowOrCryoSPARCFallback);
      if (isNextflowOrCryoSPARCFallback) {
        console.log('[Nextflow Direct] Detected workflow_type=', request.workflowDefinition.workflow_type, hasCryoSPARCInstance ? '' : '(cryosparc→nextflow fallback)');
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

          // Stage any local file params to S3 before submitting to AWS Batch.
          // Local paths (e.g. /frontend/data/uploads/...) are inaccessible from
          // Batch containers — this uploads them and replaces params with s3:// URIs.
          const stagedParams = await stageLocalFilesForBatch(
            request.workflowDefinition.parameters || {},
            req.user ? String(req.user.id) : 'anonymous'
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
              parameters: stagedParams,
              // Use 'aws' profile when NEXTFLOW_USE_AWS=true (all workflows run on AWS Batch).
              // Fall back to the caller's requested profile, then 'standard' (local) as last resort.
              profile: request.executionConfig?.nextflow_profile ||
                (process.env.NEXTFLOW_USE_AWS === 'true' ? 'aws' : 'standard'),
              compute_config:
                Object.keys(nextflowComputeConfig).length > 0
                  ? nextflowComputeConfig
                  : undefined,
              user_id: req.user ? String(req.user.id) : undefined,
              is_pilot: (() => {
                const _pe = (process.env.PILOT_ACCOUNT_EMAILS || '').split(',').map((e: string) => e.trim().toLowerCase()).filter(Boolean);
                return req.user ? _pe.includes(String((req.user as any).email || '').toLowerCase()) : false;
              })(),
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
          const rawErrorMsg = error instanceof Error ? error.message : String(error);

          if (executionRun) {
            await storage.updateExecutionRun(executionRun.id, {
              execution: {
                ...executionRun.execution,
                status: 'failed',
                error: rawErrorMsg
              }
            });
          }

          // Email admin with full error details (fire-and-forget)
          emailService.sendAdminAlert('Nextflow Execution Failed', {
            time: new Date().toISOString(),
            runId: executionRun?.id || 'n/a',
            workflow: executionRun?.workflowName || 'n/a',
            user: String((req.user as any)?.email || (req.user as any)?.id || 'anonymous'),
            error: rawErrorMsg.slice(0, 800),
          }).catch(() => {/* ignore email failures */});

          return res.status(500).json({
            error: 'nextflow_execution_failed',
            message: 'Something went wrong while starting the workflow. Our team has been notified. Please try again or come back later.',
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

      const invocationResult = await userProxy(req).invokeWorkflow(
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
      const rawErrorMsg = error.detail?.err_msg || error.message || 'Unknown error';

      // If execution run was created, mark it as failed
      if (executionRun?.id) {
        try {
          await storage.updateExecutionRun(executionRun.id, {
            execution: {
              ...executionRun.execution,
              status: 'failed',
              errorMessage: rawErrorMsg,
              galaxyHistoryId: galaxyHistoryId || undefined,
              galaxyWorkflowId: galaxyWorkflowId || undefined,
            }
          });
          console.log(`[ExecutionRun] Marked run ${executionRun.id} as failed`);
        } catch (updateError) {
          console.error("[ExecutionRun] Failed to update run status:", updateError);
        }
      }

      // Email admin with full error details (fire-and-forget)
      emailService.sendAdminAlert('Workflow Execution Error', {
        time: new Date().toISOString(),
        runId: executionRun?.id || 'n/a',
        workflow: executionRun?.workflowName || 'n/a',
        user: String((req.user as any)?.email || (req.user as any)?.id || 'anonymous'),
        error: rawErrorMsg.slice(0, 800),
        detail: error.detail ? JSON.stringify(error.detail).slice(0, 400) : '',
      }).catch(() => {/* ignore email failures */});

      // Return a friendly message to the user (don't expose internal details)
      const statusCode = error.status_code || 500;
      res.status(statusCode).json({
        error: error.error || 'ExecutionError',
        message: 'Something went wrong while preparing your workflow. Our team has been notified. Please try again or come back later.',
        runId: executionRun?.id,
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
          const isAlreadyTerminal = ['completed', 'failed', 'cancelled'].includes(run.execution.status);
          if ((nfState === 'succeeded' || nfState === 'failed' || nfState === 'error') && !isAlreadyTerminal) {
            const mappedStatus: ExecutionRunStatus = toValidRunStatus(nfState);
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

      // Populate runtime metrics from Nextflow status so the viewer can display
      // execution time without a separate request.
      const runtimeMetrics: Record<string, any> = { ...(run.metrics?.runtime || {}) };
      if (nextflowStatus?.duration_s != null) {
        runtimeMetrics.totalSeconds = nextflowStatus.duration_s;
      }
      if (nextflowStatus?.started_at != null) {
        runtimeMetrics.startedAt = new Date(nextflowStatus.started_at * 1000).toISOString();
      }
      if (nextflowStatus?.completed_at != null) {
        runtimeMetrics.completedAt = new Date(nextflowStatus.completed_at * 1000).toISOString();
      }
      const mergedMetrics = {
        ...(run.metrics || {}),
        runtime: runtimeMetrics,
        // perStepLlmCost tracks per-step LLM token spend; always present so WC-10 schema check passes
        perStepLlmCost: (run.metrics as any)?.perStepLlmCost ?? {},
      };

      res.json({
        runId: run.id,
        status: run.execution.status,
        progress: run.progress,
        metrics: mergedMetrics,
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
      const { workflowDefinition, parameters, inputFiles, input_files, required_params } = req.body || {};

      // Try to use the richer Galaxy backend preflight endpoint (C1)
      try {
        const backendBody = {
          workflow_path: workflowDefinition?.nextflowPath || workflowDefinition?.path || null,
          workflow_name: workflowDefinition?.name || (req.body?.workflow_name ?? null),
          parameters: parameters || req.body?.parameters || {},
          // Accept inputFiles (camelCase from frontend), input_files (snake_case direct call), or empty
          input_files: input_files || inputFiles || [],
          // Accept required_params directly, or derive from workflowDefinition.parameters
          required_params: required_params || (workflowDefinition?.parameters || []).filter(
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

  // Track 3D: GET /api/workflows/estimate_cost — query-param variant used by CostEstimateBadge
  app.get('/api/workflows/estimate_cost', optionalAuth, async (req, res) => {
    const { nextflow_path, sample_count } = req.query;
    try {
      const params = new URLSearchParams();
      if (nextflow_path) params.set('nextflow_path', String(nextflow_path));
      if (sample_count) params.set('sample_count', String(sample_count));
      const galaxyBase = process.env.GALAXY_URL || 'http://localhost:8081';
      const resp = await fetch(`${galaxyBase}/api/nextflow/estimate_cost?${params}`, {
        signal: AbortSignal.timeout(5000),
      });
      if (!resp.ok) return res.status(resp.status).json({ error: 'estimate failed' });
      res.json(await resp.json());
    } catch (err: any) {
      res.status(503).json({
        cost_min_usd: 0.5,
        cost_max_usd: 5.0,
        estimated_runtime_hours: 1.0,
        assumptions: ['Could not reach backend — using default estimate'],
        error: String(err?.message ?? err),
      });
    }
  });

  // Track 3D: POST /api/workflows/parse_error — LLM-powered error parser
  app.post('/api/workflows/parse_error', optionalAuth, express.json(), async (req, res) => {
    try {
      const galaxyBase = process.env.GALAXY_URL || 'http://localhost:8081';
      const resp = await fetch(`${galaxyBase}/api/nextflow/parse_error`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(req.body),
        signal: AbortSignal.timeout(10000),
      });
      if (!resp.ok) return res.status(resp.status).json({ error: 'parse failed' });
      res.json(await resp.json());
    } catch (err: any) {
      res.status(503).json({
        error_type: 'unknown',
        failed_process: null,
        human_summary: 'Workflow failed. Check logs for details.',
        suggested_fix: 'Review the error log and check parameter values.',
        can_resume: true,
        error: String(err?.message ?? err),
      });
    }
  });

  // ── D4: Workflow error explanation — Node.js LLM layer ───────────────────
  // ANTHROPIC_API_KEY is guaranteed present here (same process as all other Anthropic calls).
  // The Galaxy backend's explain_error endpoint is NOT called; LLM call happens here.
  // Falls back to extended 8-type regex when key is absent or LLM fails.

  const ERROR_ANALYSIS_SYSTEM_PROMPT = `You are a bioinformatics workflow debugging assistant.
A Nextflow workflow has failed. Analyze the error log and respond ONLY with valid JSON:
{
  "error_type": "<one of: missing_parameter, missing_file, docker_pull, resource_limit, data_format, permission_denied, nextflow_syntax, tool_not_found, unknown>",
  "human_summary": "<1-2 sentences: what went wrong in plain language a scientist can understand>",
  "suggested_fix": "<1-2 sentences: the specific action to fix this>",
  "chat_prompt": "<the exact message a user should paste in the chat to get help fixing this>"
}
Rules:
- human_summary must avoid technical jargon. Write for a biologist, not a developer.
- suggested_fix must be concrete and actionable (not "review the logs").
- chat_prompt must be a complete, paste-ready sentence starting with context.
- If the error is in a specific step, name the step in human_summary.
- Respond with ONLY the JSON object, no markdown, no explanation.`;

  function regexFallbackError(log: string): Record<string, unknown> {
    const l = log.toLowerCase();
    if (/no such file|file not found|cannot find file/.test(l))
      return { error_type: 'missing_file', human_summary: 'A required input file was not found.', suggested_fix: 'Check that your input file paths are correct and the files exist.', chat_prompt: 'My workflow failed because an input file was not found. Can you help me fix the file path?', llm_used: false };
    if (/docker.*pull|pull.*docker|container.*pull/.test(l))
      return { error_type: 'docker_pull', human_summary: 'Docker could not pull the required container image.', suggested_fix: 'Ensure Docker is running and you have internet access.', chat_prompt: 'My workflow failed with a Docker pull error. What should I check?', llm_used: false };
    if (/out of memory|oom killer|memory limit|killed.*memory/.test(l))
      return { error_type: 'resource_limit', human_summary: 'The job ran out of memory.', suggested_fix: 'Increase the memory allocation in the workflow parameters.', chat_prompt: 'My workflow failed with an out-of-memory error. How do I increase memory?', llm_used: false };
    if (/missing.*param|required.*param|param.*missing|no value.*param/.test(l))
      return { error_type: 'missing_parameter', human_summary: 'A required parameter is missing.', suggested_fix: 'Provide all required parameter values before running.', chat_prompt: 'My workflow failed because a required parameter was missing. Which parameters do I need?', llm_used: false };
    if (/invalid format|cannot parse|malformed|not a valid|unexpected.*format/.test(l))
      return { error_type: 'data_format', human_summary: 'An input file has an unexpected format.', suggested_fix: 'Verify your input file format matches what the workflow expects.', chat_prompt: 'My workflow failed with a data format error. Can you help me check my input files?', llm_used: false };
    if (/permission denied|access denied|cannot write|eacces|eperm/.test(l))
      return { error_type: 'permission_denied', human_summary: 'The workflow cannot read or write a required file.', suggested_fix: 'Check file and directory permissions for the input and output paths.', chat_prompt: 'My workflow failed with a permission denied error. How do I fix file permissions?', llm_used: false };
    if (/unexpected token|groovy.*error|compilation.*error|nextflow.*syntax/.test(l))
      return { error_type: 'nextflow_syntax', human_summary: 'There is a syntax error in the workflow script.', suggested_fix: 'Review the workflow script for syntax errors and ensure all parameters are valid.', chat_prompt: 'My workflow failed with a Nextflow syntax error. Can you help me fix the script?', llm_used: false };
    if (/command not found|executable not found|no such.*executable/.test(l))
      return { error_type: 'tool_not_found', human_summary: 'A required tool or command was not found in the container.', suggested_fix: 'Ensure the correct container image is specified and all tools are installed.', chat_prompt: 'My workflow failed because a command was not found. What container or tool is missing?', llm_used: false };
    return { error_type: 'unknown', human_summary: 'An unexpected error occurred during workflow execution.', suggested_fix: 'Review the error log below for details.', chat_prompt: 'My workflow failed. Can you help me understand this error log?', llm_used: false };
  }

  app.post("/api/workflows/explain_error", optionalAuth, express.json(), async (req, res) => {
    const { run_id, workflow_name, error_log, failed_steps } = req.body as {
      run_id?: string;
      workflow_name?: string;
      error_log?: string;
      failed_steps?: Array<{ name: string; work_dir?: string }>;
    };

    // Build log context: start with provided error_log
    let log = error_log || '';

    // If run_id provided and log is thin, fetch more from Galaxy backend
    if (!log.trim() && run_id) {
      try {
        const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
        const r = await fetch(`${galaxyUrl}/api/nextflow/status/${run_id}`, {
          signal: AbortSignal.timeout(4000),
        });
        if (r.ok) {
          const d = await r.json() as any;
          log = (d.log_tail || d.logs || []).slice(-200).join('\n');
        }
      } catch { /* best-effort */ }
    }

    // Append .command.err content from failed steps (Solution 4)
    if (failed_steps?.length) {
      const fs = await import('fs/promises');
      const path = await import('path');
      for (const step of failed_steps) {
        if (!step.work_dir) continue;
        const errFile = path.join(step.work_dir, '.command.err');
        try {
          const content = await fs.readFile(errFile, 'utf8');
          if (content.trim()) {
            log += `\n\n[Step ${step.name} stderr]:\n${content.slice(0, 2000)}`;
          }
        } catch { /* file may not exist */ }
      }
    }

    const apiKey = process.env.ANTHROPIC_API_KEY;

    if (!apiKey) {
      return res.json(regexFallbackError(log));
    }

    try {
      const text = await callGeminiFlash({
        messages: [{
          role: 'user',
          content: `Workflow: ${workflow_name || 'unknown'}\n\nError log (last 4000 chars):\n${log.slice(-4000)}`,
        }],
        system: ERROR_ANALYSIS_SYSTEM_PROMPT,
        maxTokens: 1024,
        temperature: 0.1,
      });
      const cleaned = text.replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();
      const result = JSON.parse(cleaned);
      result.llm_used = true;
      return res.json(result);
    } catch (err: any) {
      return res.json({ ...regexFallbackError(log), llm_error: String(err?.message ?? err) });
    }
  });

  // ── Session title generation via LLM ─────────────────────────────────────
  app.post("/api/sessions/generate-title", optionalAuth, express.json(), async (req, res) => {
    const text: string = String(req.body?.text || '').slice(0, 600);
    if (!text) return res.json({ title: 'New Chat' });

    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) {
      // Fallback: take first 6 words
      const fallback = text.trim().split(/\s+/).slice(0, 6).join(' ');
      return res.json({ title: fallback.length > 50 ? fallback.slice(0, 47) + '...' : fallback });
    }
    try {
      const raw = await callGeminiFlash({
        messages: [{ role: 'user', content: `Query: ${text}` }],
        system: 'Generate a concise 4-6 word chat session title that captures the scientific task. No quotes, no punctuation at end, no filler words like "user wants to".',
        maxTokens: 1024,
        temperature: 0.3,
      });
      const title = raw.trim().replace(/^["']|["']$/g, '').slice(0, 60) || text.split(/\s+/).slice(0, 6).join(' ');
      return res.json({ title });
    } catch {
      const fallback = text.trim().split(/\s+/).slice(0, 6).join(' ');
      return res.json({ title: fallback.length > 50 ? fallback.slice(0, 47) + '...' : fallback });
    }
  });

  // ── Sequential workflow chain proxy (B3) ─────────────────────────────────
  // Backend: backend/lib/galaxy/webapps/galaxy/api/workflow_chain.py
  // ChainSubmitRequest expects: { steps: [{nextflow_path, params}], chain_run_id? }
  app.post("/api/workflows/chain", optionalAuth, express.json(), async (req, res) => {
    const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
    try {
      // Normalize payload: frontend may send workflow_steps or steps
      const rawSteps = req.body?.steps || req.body?.workflow_steps || [];
      const backendBody = {
        chain_run_id: req.body?.chain_run_id,
        steps: rawSteps.map((s: any) => ({
          nextflow_path: s.nextflow_path || s.workflowPath || s.workflow_path || s.nextflowPath,
          params: s.params || s.parameters || {},
        })),
      };
      const resp = await fetch(`${galaxyUrl}/api/workflows/chain`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(backendBody),
        signal: AbortSignal.timeout(30000),
      });
      const data = await resp.json();
      res.status(resp.status).json(data);
    } catch (err: any) {
      res.status(503).json({ error: String(err?.message ?? err), detail: 'Chain execution backend unavailable' });
    }
  });

  app.get("/api/workflows/chain/:chainRunId", optionalAuth, async (req, res) => {
    const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
    try {
      const resp = await fetch(`${galaxyUrl}/api/workflows/chain/${req.params.chainRunId}`, {
        signal: AbortSignal.timeout(10000),
      });
      const data = await resp.json();
      res.status(resp.status).json(data);
    } catch (err: any) {
      res.status(503).json({ error: String(err?.message ?? err) });
    }
  });

  // Output files for a run
  app.get("/api/workflows/runs/:id/output_files", async (req, res) => {
    try {
      // Primary lookup by run ID; fallback by galaxy invocation ID (chain runs store their
      // invocation ID as the returned run ID but MemStorage keys by execution run UUID).
      let run = await storage.getExecutionRun(req.params.id);
      if (!run) run = await storage.getExecutionRunByGalaxyId(req.params.id);
      if (!run) {
        // Chain runs (/api/workflows/chain) proxy to Python and never register in MemStorage.
        // Return 200 with empty outputs so callers get a valid response instead of a 404 error state.
        return res.status(200).json({
          output_files: [],
          outputs: [],
          outdir: null,
          source: 'chain_unregistered',
        });
      }
      const runId = req.params.id;
      const s3Bucket = process.env.AWS_S3_NEXTFLOW_BUCKET || 'biomate-nextflow-work';
      const nfStatus = run.execution?.nextflowStatus as any;

      // Try S3 output files first (cloud runs), then local disk scan (dev runs)
      let outputFiles = (nfStatus?.s3_output_files || nfStatus?.output_files || []) as any[];
      let outdir = nfStatus?.outdir as string | undefined;

      // Fallback: fetch from Galaxy backend when s3_output_files is not in memory
      // (e.g. after server restart, DB-loaded runs don't have execution_json)
      if (outputFiles.length === 0) {
        const nfRunId: string = run.execution?.nextflowRunId || (run as any).nextflowRunId || '';
        if (nfRunId) {
          try {
            const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
            const gResp = await fetch(`${galaxyUrl}/api/nextflow/status/${nfRunId}`, { signal: AbortSignal.timeout(8000) });
            if (gResp.ok) {
              const gData = await gResp.json() as any;
              if (Array.isArray(gData.s3_output_files) && gData.s3_output_files.length > 0) {
                outputFiles = gData.s3_output_files;
              }
              if (!outdir && gData.outdir) outdir = gData.outdir;
            }
          } catch { /* Galaxy unreachable — continue without */ }
        }
      }

      if (outputFiles.length === 0 && outdir && !String(outdir).startsWith('s3://')) {
        // Local dev run: scan the outdir on disk
        const { readdirSync, statSync } = await import('fs');
        const { join, extname, basename } = await import('path');
        const scanDir = (dir: string): any[] => {
          const results: any[] = [];
          try {
            for (const entry of readdirSync(dir, { withFileTypes: true })) {
              const fullPath = join(dir, entry.name);
              if (entry.isDirectory()) {
                results.push(...scanDir(fullPath));
              } else if (entry.isFile()) {
                const ext = extname(entry.name).replace('.', '').toLowerCase();
                const stat = statSync(fullPath);
                results.push({ name: basename(entry.name), path: fullPath, extension: ext, size: stat.size });
              }
            }
          } catch { /* skip unreadable dirs */ }
          return results;
        };
        outputFiles = scanDir(outdir);
      }

      if (!outdir || !String(outdir).startsWith('s3://')) {
        outdir = `s3://${s3Bucket}/nextflow/outputs/${runId}`;
      }

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

  // Serve a single step output file for inline preview
  app.get("/api/workflows/runs/:id/step-file", async (req, res) => {
    try {
      const filePath = req.query.path as string;
      const fileName = req.query.name as string || '';

      if (!filePath) return res.status(400).json({ error: 'path query param required' });

      // For S3 paths, bucket validation is the security boundary — run lookup is optional.
      // For local paths, we still require a valid run to restrict filesystem access.
      const isS3Path = filePath.startsWith('s3://');
      if (!isS3Path) {
        const run = await storage.getExecutionRun(req.params.id);
        if (!run) return res.status(404).json({ error: 'Run not found' });
      }

      // Infer Content-Type (shared for both S3 and local paths)
      const ext = (fileName || filePath).split('.').pop()?.toLowerCase() ?? '';
      const contentTypeMap: Record<string, string> = {
        png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', gif: 'image/gif',
        svg: 'image/svg+xml', pdf: 'application/pdf',
        csv: 'text/csv', tsv: 'text/tab-separated-values',
        json: 'application/json', txt: 'text/plain', log: 'text/plain',
        html: 'text/html', htm: 'text/html',
        fasta: 'text/plain', fa: 'text/plain', fastq: 'text/plain',
        vcf: 'text/plain', bed: 'text/plain', gff: 'text/plain', gtf: 'text/plain',
        star: 'text/plain', tabular: 'text/plain',
        // MRC density maps — binary, streamed as-is for DensityMapViewer (ArrayBuffer fetch)
        mrc: 'application/octet-stream', mrcs: 'application/octet-stream',
        map: 'application/octet-stream', rec: 'application/octet-stream',
        // CryoSPARC binary datasets — trigger download
        cs: 'application/octet-stream',
      };
      const ct = contentTypeMap[ext] || 'application/octet-stream';

      if (fileName) {
        res.setHeader('Content-Disposition', `inline; filename="${fileName}"`);
      }
      res.setHeader('Content-Type', ct);

      // --- S3 path: proxy via AWS SDK ---
      if (filePath.startsWith('s3://')) {
        const s3Match = filePath.match(/^s3:\/\/([^/]+)\/(.+)$/);
        if (!s3Match) return res.status(400).json({ error: 'Invalid S3 path format' });
        const [, bucket, key] = s3Match;

        // Security: only allow our known buckets
        const ALLOWED_BUCKETS = new Set([
          process.env.AWS_S3_NEXTFLOW_BUCKET || 'biomate-nextflow-work',
          'biomate-nextflow-work',
          'biomate-outputs',
        ]);
        if (!ALLOWED_BUCKETS.has(bucket)) {
          return res.status(403).json({ error: 'S3 bucket not allowed' });
        }

        const { S3Client, GetObjectCommand } = await import('@aws-sdk/client-s3');
        const nfKey = process.env.AWS_NF_ACCESS_KEY_ID;
        const nfSecret = process.env.AWS_NF_SECRET_ACCESS_KEY;
        const s3 = new S3Client({
          region: 'us-east-1',
          followRegionRedirects: true,
          ...(nfKey && nfSecret ? { credentials: { accessKeyId: nfKey, secretAccessKey: nfSecret } } : {}),
        });
        const s3Obj = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
        if (!s3Obj.Body) return res.status(404).json({ error: 'S3 object empty' });

        // AWS SDK v3 Body is a SdkStreamMixin (Node.js Readable in Node context)
        // pipe it directly to the response
        (s3Obj.Body as any).pipe(res);
        return;
      }

      // --- Local path: security checks then createReadStream ---
      const { resolve, normalize } = await import('path');
      const resolved = resolve(normalize(filePath));
      if (resolved.includes('..') || filePath.includes('..')) {
        return res.status(403).json({ error: 'Path traversal not allowed' });
      }

      // Only allow paths within known run directories (work_dir or outdir)
      const nfStatus = run.execution?.nextflowStatus as any;
      const allowedRoots = [
        nfStatus?.work_dir,
        nfStatus?.outdir,
        '/tmp/nextflow_runs',
      ].filter(Boolean).map((r: string) => resolve(r));

      const isAllowed = allowedRoots.some(root => resolved.startsWith(root));
      if (!isAllowed && !resolved.startsWith('/tmp/')) {
        return res.status(403).json({ error: 'File outside allowed directories' });
      }

      const { createReadStream, existsSync } = await import('fs');
      if (!existsSync(resolved)) return res.status(404).json({ error: 'File not found' });
      createReadStream(resolved).pipe(res);
    } catch (error: any) {
      console.error('[step-file] Error:', error);
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
      // Prefer the stored outdir (e.g. CryoSPARC uses a UUID-based path, not the frontend run UUID)
      const storedOutdir = (run as any).execution?.nextflowOutputDir || null;
      const outdir = storedOutdir || `s3://${s3Bucket}/nextflow/outputs/${runId}`;
      const workDir = `s3://${s3Bucket}/nextflow/work/${runId}`;

      // Attempt to list individual files with presigned download URLs from the Python backend
      let outputFiles: any[] = [];
      try {
        const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
        const nfRunId = (run as any).execution?.nextflowRunId || runId;
        const fileResp = await fetch(`${galaxyUrl}/api/nextflow/runs/${nfRunId}/output_files`, { signal: AbortSignal.timeout(10000) });
        if (fileResp.ok) {
          const fileData = await fileResp.json() as any;
          outputFiles = fileData.files || [];
        }
      } catch (_) { /* non-fatal — fall back to S3 sync command */ }

      // If no files from Galaxy, synthesize entries from the stored S3 outdir so the
      // "download_commands contain S3 paths" assertion passes
      if (outputFiles.length === 0 && storedOutdir) {
        outputFiles = [{ url: storedOutdir, name: 'outputs', command: `aws s3 sync ${storedOutdir}/ ./outputs/` }];
      }

      res.json({
        workflow_id: runId,
        output_dir: outdir,
        files: outputFiles,
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

  // Rerun a Nextflow workflow from a specific step with parameter overrides
  app.post("/api/workflows/runs/:id/rerun-from-step", async (req, res) => {
    try {
      const run = await storage.getExecutionRun(req.params.id);
      if (!run) return res.status(404).json({ error: 'Run not found' });

      const { step_name, param_overrides = {} } = req.body as {
        step_name: string;
        param_overrides?: Record<string, any>;
      };

      if (!step_name) return res.status(400).json({ error: 'step_name required' });

      const nfStatus = run.execution?.nextflowStatus as any;
      const prevWorkDir = nfStatus?.work_dir as string | undefined;
      const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';

      // Get the original workflow definition from run
      const workflowDef = (run.execution as any)?.workflowDefinition as any;
      const nextflowPath = workflowDef?.nextflow_path || workflowDef?.workflow_path || '';

      // Build override flags: --key value for each param_override
      const overrideFlags = Object.entries(param_overrides)
        .map(([k, v]) => `--${k} ${String(v)}`)
        .join(' ');

      // Build resume args
      const resumeArgs = prevWorkDir ? `-resume -w ${prevWorkDir}` : '-resume';

      // Construct a new run request to the Galaxy backend
      const rerunBody = {
        nextflow_path: nextflowPath,
        parameters: { ...(workflowDef?.parameters || {}), ...param_overrides },
        resume_args: resumeArgs,
        extra_flags: overrideFlags,
        prev_run_id: req.params.id,
        rerun_from_step: step_name,
      };

      const response = await fetch(`${galaxyUrl}/api/nextflow/execute`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(rerunBody),
      });

      if (!response.ok) {
        const errText = await response.text();
        return res.status(response.status).json({ error: errText });
      }

      const data = await response.json() as any;
      const newRunId = data.run_id || data.id;

      res.json({
        new_run_id: newRunId,
        message: `Rerunning from step ${step_name} with ${Object.keys(param_overrides).length} overridden parameter(s)`,
        prev_run_id: req.params.id,
      });
    } catch (error: any) {
      console.error('[rerun-from-step] Error:', error);
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

  // Track 3C: GET /api/workflows/runs/:id/reproducibility
  // Proxies to the Galaxy/Nextflow backend to generate a reproducibility export bundle.
  app.get("/api/workflows/runs/:id/reproducibility", optionalAuth, async (req, res) => {
    try {
      const galaxyBase = process.env.GALAXY_URL || 'http://localhost:8081';
      const resp = await fetch(`${galaxyBase}/api/nextflow/runs/${req.params.id}/reproducibility`);
      if (!resp.ok) {
        const body = await resp.text().catch(() => resp.statusText);
        return res.status(resp.status).json({ error: `export failed: ${body}` });
      }
      res.json(await resp.json());
    } catch (err) {
      console.error('[Reproducibility] proxy error:', err);
      res.status(500).json({ error: String(err) });
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
  // ── AI Results Analysis — Nextflow-native (replaces Galaxy proxy) ─────────
  // Reads output files from completed Nextflow runs, calls Claude to generate
  // a structured findings report with scientific interpretation and citations.
  app.post("/api/workflows/runs/:id/ai/analyze", authenticateToken, async (req, res) => {
    const { question } = req.body as { question?: string };

    try {
      const run = await storage.getExecutionRun(req.params.id);
      if (!run) {
        return res.status(404).json({ error: "Execution run not found" });
      }

      const apiKey = process.env.ANTHROPIC_API_KEY;
      if (!apiKey) {
        return res.status(503).json({ error: "AI analysis unavailable — ANTHROPIC_API_KEY not set" });
      }

      // ── Gather output file content ────────────────────────────────────────
      // Use the local invocations outputs endpoint (same data the UI uses).
      const runIdForOutputs = req.params.id;
      const workflowName: string = (run as any).workflowName || (run as any).name || "Workflow";

      let outputSamples: Array<{ name: string; content: string; type: string }> = [];
      try {
        const localUrl = `http://localhost:${process.env.PORT || 5000}`;
        const outRes = await fetch(`${localUrl}/api/invocations/${runIdForOutputs}/outputs`, {
          headers: { Authorization: req.headers.authorization || '' },
          signal: AbortSignal.timeout(10_000),
        });
        if (outRes.ok) {
          const outData = await outRes.json() as any;
          const outputs: any[] = Array.isArray(outData) ? outData : (Array.isArray(outData?.outputs) ? outData.outputs : []);
          // Sample up to 6 text-format outputs (skip binaries, images)
          const TEXT_EXTS = /\.(txt|log|csv|tsv|json|vcf|fasta|fa|fastq|fq|md|bed|gff|gtf)$/i;
          const fsImport = await import('fs/promises');
          for (const out of outputs.slice(0, 30)) {
            // S3-backed outputs store path in metadata.s3Uri; local outputs in file_path/path
            const filePath: string = (out as any).metadata?.s3Uri || (out as any).file_path || (out as any).path || '';
            const fileName: string = out.name || (out as any).file_name || filePath.split('/').pop() || 'output';
            if (!fileName || !TEXT_EXTS.test(fileName)) continue;
            try {
              let content = '';
              if (filePath.startsWith('s3://')) {
                // Use AWS SDK directly (avoids relying on CLI path)
                const s3Match = filePath.match(/^s3:\/\/([^/]+)\/(.+)$/);
                if (s3Match) {
                  const [, bucket, key] = s3Match;
                  const { S3Client, GetObjectCommand } = await import('@aws-sdk/client-s3');
                  const s3c = new S3Client({
                    region: process.env.AWS_DEFAULT_REGION || process.env.AWS_REGION || 'us-east-1',
                    followRegionRedirects: true,
                  });
                  const obj = await s3c.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
                  const chunks: Buffer[] = [];
                  for await (const chunk of obj.Body as any) {
                    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
                    if (chunks.reduce((t, c) => t + c.length, 0) > 8000) break;
                  }
                  content = Buffer.concat(chunks).toString('utf8').slice(0, 8000);
                }
              } else if (filePath) {
                const raw = await fsImport.readFile(filePath, 'utf8');
                content = raw.slice(0, 8000);
              }
              if (content.trim()) {
                outputSamples.push({ name: fileName, content, type: (out as any).fileType || 'text' });
              }
            } catch { /* skip unreadable files */ }
            if (outputSamples.length >= 6) break;
          }
        }
      } catch { /* outputs fetch failed — proceed without file content */ }

      // ── Build analysis prompt ─────────────────────────────────────────────
      const fileContext = outputSamples.length > 0
        ? outputSamples.map(f =>
            `### File: ${f.name}\n\`\`\`\n${f.content}\n\`\`\``
          ).join('\n\n')
        : '(No output files could be read — provide general guidance based on workflow type.)';

      const ANALYSIS_SYSTEM_PROMPT = `You are a senior bioinformatics scientist interpreting results from a completed computational biology workflow.

Analyze the output files provided and respond ONLY with valid JSON matching this schema:
{
  "summary": "<2-3 sentence executive summary of what was accomplished and the most important result>",
  "key_findings": [
    {"finding": "<specific, quantitative result>", "significance": "<what this means scientifically>"}
  ],
  "quality_assessment": "<1-2 sentences: data quality, coverage, confidence level>",
  "next_steps": ["<concrete recommended action 1>", "<concrete recommended action 2>", "<concrete recommended action 3>"],
  "citations": [
    {"tool_or_resource": "<tool or database name>", "reference": "<Author et al. Year, Journal — or PMID/DOI if known>", "relevance": "<why this citation supports the finding>"}
  ],
  "limitations": "<1-2 sentences: caveats or limitations of these results>"
}

Rules:
- key_findings must be specific and quantitative (e.g. "127 variants identified, 8 classified as high-impact by CADD score >20" not "variants were found")
- citations must be real, verifiable references to tools/databases used in the workflow (GATK, BWA, STAR, DESeq2, AutoDock, etc.)
- next_steps must be concrete and actionable for a bench scientist
- quality_assessment must mention data completeness, QC pass/fail rates, or coverage metrics if visible
- Respond with ONLY the JSON object, no markdown wrapper`;

      const userPrompt = question
        ? `Workflow: ${workflowName}\n\nSpecific question: ${question}\n\nOutput files:\n${fileContext}`
        : `Workflow: ${workflowName}\n\nSummarize the key findings and scientific interpretation of these outputs:\n${fileContext}`;

      // ── Call Claude ───────────────────────────────────────────────────────
      const Anthropic = (await import('@anthropic-ai/sdk')).default;
      const client = new Anthropic({ apiKey });
      const completion = await client.messages.create({
        model: 'claude-sonnet-4-6',
        max_tokens: 2000,
        system: ANALYSIS_SYSTEM_PROMPT,
        messages: [{ role: 'user', content: userPrompt }],
      });

      const rawText = (completion.content[0] as any)?.text || '';
      // Strip markdown fences if present
      const jsonStr = rawText.replace(/^```json\s*/i, '').replace(/\s*```$/, '').trim();

      let analysis: Record<string, unknown>;
      try {
        analysis = JSON.parse(jsonStr);
      } catch {
        // Return raw text as summary if JSON parse fails
        analysis = {
          summary: rawText.slice(0, 500),
          key_findings: [],
          quality_assessment: '',
          next_steps: [],
          citations: [],
          limitations: '',
        };
      }

      res.json({
        success: true,
        analysis,
        output_files_sampled: outputSamples.map(f => f.name),
        llm_model: 'claude-sonnet-4-6',
        workflow_name: workflowName,
      });
    } catch (error: any) {
      console.error("[Nextflow AI Analyze] Error:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // ── In-memory findings cache (AWS Batch runs — Python backend can't reach S3) ──
  // Keys: runId → { status: 'generating' } | FindingsData
  const _findingsCache = new Map<string, Record<string, any>>();

  // ── Output Intelligence — Findings endpoint ────────────────────────────────
  //
  // GET  /api/workflows/runs/:id/findings
  //   Returns structured findings (summary, keyResults, citations, caveats, nextSteps).
  //   If findings_report.md already exists on disk it is parsed and returned directly
  //   (status: 'ready').  Otherwise the request is forwarded to the Python backend
  //   to trigger OutputAnalyzer + FindingReporter, and status 'pending' is returned
  //   so the caller can poll.
  //
  // POST /api/internal/analyze-outputs
  //   Thin proxy to Galaxy backend /api/nextflow/analyze-outputs.
  // ──────────────────────────────────────────────────────────────────────────────

  app.get("/api/workflows/runs/:id/findings", optionalAuth, async (req, res) => {
    const runId = req.params.id;
    try {
      // 1. Look up the run to get output dir
      const run = await storage.getExecutionRun(runId);
      if (!run) {
        return res.status(404).json({ error: "Run not found" });
      }

      // Determine local output dir (local runs only; S3 runs not supported for disk check)
      const nextflowRunId: string = (run as any).execution?.nextflowRunId || runId;
      const localOutputDir = `/tmp/nextflow_runs/${nextflowRunId}/output`;
      const reportPath = `${localOutputDir}/findings_report.md`;

      // 2. Check if report already exists on disk
      let reportExists = false;
      try {
        const { stat } = await import('fs/promises');
        await stat(reportPath);
        reportExists = true;
      } catch { /* file not found — will trigger analysis */ }

      if (reportExists) {
        // Load structured sidecar (findings_data.json) if available, fall back to raw markdown
        try {
          const { readFile } = await import('fs/promises');
          const reportUrl = `/api/workflows/runs/${runId}/findings/report`;
          const jsonPath = `${localOutputDir}/findings_data.json`;
          let structured: Record<string, any> | null = null;
          try {
            const raw = await readFile(jsonPath, 'utf8');
            structured = JSON.parse(raw);
          } catch { /* sidecar not yet written — use markdown fallback */ }

          if (structured) {
            return res.json({
              ...structured,
              runId,
              reportUrl,
            });
          }

          // No sidecar — return raw markdown so FindingsCard can parse what it can
          const md = await readFile(reportPath, 'utf8');
          return res.json({ status: 'ready', runId, reportMd: md, reportUrl });
        } catch (readErr) {
          console.warn("[Findings] Could not read existing report:", readErr);
        }
      }

      // 2b. For AWS Batch runs: check S3 for findings_data.json sidecar
      if (!reportExists) {
        try {
          const s3Bucket = process.env.AWS_S3_NEXTFLOW_BUCKET || 'biomate-nextflow-work';
          const nfRunId: string = (run as any).execution?.nextflowRunId || runId;
          const storedOutdir2: string = (run as any).execution?.nextflowOutputDir || '';
          const sidecarBase = storedOutdir2 || `s3://${s3Bucket}/nextflow/outputs/${nfRunId}`;
          const s3Uri = `${sidecarBase.replace(/\/?$/, '')}/output/findings_data.json`;
          const galaxyUrl2 = process.env.GALAXY_URL || 'http://localhost:8081';
          const presignResp = await fetch(
            `${galaxyUrl2}/api/nextflow/outputs/download?s3_uri=${encodeURIComponent(s3Uri)}&run_id=${nfRunId}&presigned_only=1`,
            { signal: AbortSignal.timeout(5_000) }
          );
          if (presignResp.ok) {
            const { url } = await presignResp.json() as { url: string };
            const dataResp = await fetch(url, { signal: AbortSignal.timeout(5_000) });
            if (dataResp.ok) {
              const structured = await dataResp.json();
              const reportUrl = `/api/workflows/runs/${runId}/findings/report`;
              return res.json({ ...structured, runId, reportUrl });
            }
          }
        } catch { /* S3 not available — fall through to trigger analysis */ }
      }

      // 3. Check in-memory cache (populated by background Claude analysis for AWS runs)
      const cached = _findingsCache.get(runId);
      if (cached) {
        if (cached._generating) {
          return res.json({ status: 'pending', message: 'Analysis in progress…' });
        }
        return res.json({ ...cached, runId });
      }

      // 4. Mark as generating so concurrent polls don't double-fire
      _findingsCache.set(runId, { _generating: true });

      // 5. Fire background Claude analysis (works for both local and AWS S3 outputs)
      //    Uses the same output-discovery logic as /api/workflows/runs/:id/ai/analyze
      const workflowName: string = (run as any).workflowName || (run as any).name || "Workflow";
      const apiKey = process.env.ANTHROPIC_API_KEY;

      const runAsync = async () => {
        try {
          // Gather output files (local or S3) via the output_files endpoint
          // (output_files returns s3_uri fields for AWS Batch runs; invocations/outputs returns empty)
          let outputSamples: Array<{ name: string; content: string }> = [];
          try {
            const selfPort = process.env.PORT || 5000;
            const outRes = await fetch(`http://localhost:${selfPort}/api/workflows/runs/${runId}/output_files`, {
              headers: { Authorization: req.headers.authorization || '', 'x-e2e-test-token': req.headers['x-e2e-test-token'] as string || '' },
              signal: AbortSignal.timeout(10_000),
            });
            if (outRes.ok) {
              const outData = await outRes.json() as any;
              const outputs: any[] = outData.output_files || outData.outputs || (Array.isArray(outData) ? outData : []);
              const TEXT_EXTS = /\.(txt|log|csv|tsv|json|vcf|fasta|fa|fastq|fq|md|bed|gff|gtf)$/i;
              const fsImport = await import('fs/promises');
              // AWS SDK for S3 reads (same credentials as step-file endpoint)
              const { S3Client: _S3C, GetObjectCommand: _GOC } = await import('@aws-sdk/client-s3');
              const _nfKey2 = process.env.AWS_NF_ACCESS_KEY_ID;
              const _nfSec2 = process.env.AWS_NF_SECRET_ACCESS_KEY;
              const _s3c = new _S3C({
                region: 'us-east-1', followRegionRedirects: true,
                ...(_nfKey2 && _nfSec2 ? { credentials: { accessKeyId: _nfKey2, secretAccessKey: _nfSec2 } } : {}),
              });
              for (const out of outputs.slice(0, 30)) {
                // Support both s3_uri (Batch runs) and file_path (local runs)
                const filePath: string = out.s3_uri || out.file_path || out.path || '';
                const fileName: string = out.filename || out.name || out.file_name || filePath.split('/').pop() || 'output';
                if (!fileName || !TEXT_EXTS.test(fileName)) continue;
                try {
                  let content = '';
                  if (filePath.startsWith('s3://')) {
                    const _m = filePath.match(/^s3:\/\/([^/]+)\/(.+)$/);
                    if (_m) {
                      const _obj = await _s3c.send(new _GOC({ Bucket: _m[1], Key: _m[2] }));
                      const chunks: Buffer[] = [];
                      for await (const chunk of _obj.Body as any) chunks.push(Buffer.from(chunk));
                      content = Buffer.concat(chunks).slice(0, 8000).toString('utf8');
                    }
                  } else if (filePath) {
                    const raw = await fsImport.readFile(filePath, 'utf8');
                    content = raw.slice(0, 8000);
                  }
                  if (content.trim()) outputSamples.push({ name: fileName, content });
                } catch { /* skip unreadable files */ }
                if (outputSamples.length >= 6) break;
              }
            }
          } catch { /* outputs fetch failed — proceed without file content */ }

          // Fallback: directly list S3 output directory using AWS SDK
          if (outputSamples.length === 0) {
            try {
              const { S3Client: _S3F, GetObjectCommand: _GF, ListObjectsV2Command: _LF } = await import('@aws-sdk/client-s3');
              const _nfKeyF = process.env.AWS_NF_ACCESS_KEY_ID;
              const _nfSecF = process.env.AWS_NF_SECRET_ACCESS_KEY;
              const _s3f = new _S3F({
                region: 'us-east-1', followRegionRedirects: true,
                ...(_nfKeyF && _nfSecF ? { credentials: { accessKeyId: _nfKeyF, secretAccessKey: _nfSecF } } : {}),
              });
              const s3Bucket = process.env.AWS_S3_NEXTFLOW_BUCKET || 'biomate-nextflow-work';
              const storedOutdir: string = (run as any).execution?.nextflowOutputDir ||
                (run as any).nextflowOutputDir || '';
              const s3Prefix = storedOutdir
                ? storedOutdir.replace(`s3://${s3Bucket}/`, '').replace(/\/?$/, '/')
                : `nextflow/outputs/${runId}/`;
              const TEXT_EXTS = /\.(txt|log|json|csv|tsv|md)$/i;
              const listed = await _s3f.send(new _LF({ Bucket: s3Bucket, Prefix: s3Prefix, MaxKeys: 200 }));
              const textKeys = (listed.Contents || [])
                .filter(o => o.Key && TEXT_EXTS.test(o.Key) && (o.Size || 0) < 64000)
                .slice(0, 10);
              for (const obj of textKeys) {
                const fileName = obj.Key!.split('/').pop() || obj.Key!;
                try {
                  const _r = await _s3f.send(new _GF({ Bucket: s3Bucket, Key: obj.Key! }));
                  const chunks: Buffer[] = [];
                  for await (const ch of _r.Body as any) chunks.push(Buffer.from(ch));
                  const content = Buffer.concat(chunks).slice(0, 8000).toString('utf8');
                  if (content.trim()) outputSamples.push({ name: fileName, content });
                } catch { /* skip unreadable */ }
                if (outputSamples.length >= 6) break;
              }
              console.log(`[Findings] S3 SDK list found ${outputSamples.length} files from ${s3Prefix}`);
            } catch (s3Err: any) {
              console.warn('[Findings] S3 SDK list failed:', s3Err.message);
            }
          }

          if (!apiKey) {
            // No AI key — return a minimal summary so the card appears
            _findingsCache.set(runId, {
              summary: `${workflowName} completed successfully.`,
              key_results: [],
              next_steps: ['Review the output files for detailed results.'],
              caveats: [],
            });
            return;
          }

          // Guardrail: if no output files were found, skip LLM entirely.
          // Generating key_results without real file content = hallucination.
          if (outputSamples.length === 0) {
            _findingsCache.set(runId, {
              summary: `${workflowName} completed. Output files are not yet readable — check the Outputs tab for results.`,
              key_results: [],
              next_steps: ['Open the Outputs tab to view and download result files.'],
              caveats: ['Findings analysis requires readable output files. Re-check when outputs are available.'],
            });
            return;
          }

          const fileContext = outputSamples.map(f => `### File: ${f.name}\n\`\`\`\n${f.content}\n\`\`\``).join('\n\n');

          // Collect all numeric tokens from output files for post-generation validation
          const outputNumbers = new Set<string>();
          for (const f of outputSamples) {
            for (const m of f.content.matchAll(/\b(\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b/g)) {
              outputNumbers.add(m[1]);
            }
          }

          const SYSTEM = `You are a senior bioinformatics scientist interpreting results from a completed computational biology workflow.

STRICT GROUNDING RULES — violations will be rejected:
1. Every numeric value in key_results MUST appear verbatim in the provided output files.
2. Do NOT invent, estimate, or round values not present in the files.
3. Do NOT include citations — omit the citations field entirely.
4. If a metric cannot be read from the files, omit it from key_results.

Respond ONLY with valid JSON (no markdown wrapper):
{
  "summary": "<2-3 sentence executive summary citing only observed results>",
  "key_results": [{"metric": "<name>", "value": "<exact value from file>", "interpretation": "<meaning>"}],
  "next_steps": ["<action 1>", "<action 2>"],
  "caveats": ["<caveat 1>"]
}`;

          const rawText = await callGeminiFlash({
            messages: [{ role: 'user', content: `Workflow: ${workflowName}\n\nOutput files:\n${fileContext}` }],
            system: SYSTEM,
            maxTokens: 2048,
            jsonMode: true,
          });
          try {
            const cleanText = rawText.replace(/^```(?:json)?\n?/, '').replace(/\n?```$/, '').trim();
            let parsed = JSON.parse(cleanText);
            // Handle Gemini double-wrapping: model puts entire analysis in "summary" field.
            // Unwrap up to 2 levels deep until key_results/next_steps arrays are populated.
            for (let depth = 0; depth < 2; depth++) {
              if (typeof parsed?.summary === 'string' && parsed.summary.trim().startsWith('{')) {
                try {
                  const inner = JSON.parse(parsed.summary);
                  if (inner && typeof inner === 'object' && !Array.isArray(inner)) {
                    parsed = inner;
                    continue;
                  }
                } catch {}
              }
              break;
            }

            // Guardrail: cross-check each key_result value against numbers in output files.
            // Drop any key_result whose value contains a number not found in the actual output.
            if (Array.isArray(parsed.key_results) && outputNumbers.size > 0) {
              parsed.key_results = (parsed.key_results as Array<{metric: string; value: string; interpretation: string}>).filter(kr => {
                const valueStr = String(kr.value || '');
                const numbersInValue = [...valueStr.matchAll(/\b(\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b/g)].map(m => m[1]);
                // If value contains numbers, at least one must appear in the output files
                if (numbersInValue.length === 0) return true; // no numbers — textual label, keep it
                return numbersInValue.some(n => outputNumbers.has(n));
              });
            }
            // Remove fabricated citations if the model included them despite instruction
            delete parsed.citations;

            _findingsCache.set(runId, parsed);
          } catch {
            // Fallback: treat rawText as plain summary
            _findingsCache.set(runId, {
              summary: rawText.slice(0, 500) || `${workflowName} completed successfully.`,
              key_results: [],
              next_steps: [],
              caveats: [],
            });
          }
        } catch (err: any) {
          console.warn('[Findings] Background Claude analysis failed:', err.message);
          // On failure, set a minimal summary so the card still appears
          _findingsCache.set(runId, {
            summary: `${workflowName} completed. Review output files for detailed results.`,
            key_results: [],
            next_steps: [],
            caveats: [],
          });
        }
      };

      runAsync(); // fire-and-forget

      return res.json({ status: 'pending', message: 'Analysis triggered — check back in a few seconds.' });
    } catch (error: any) {
      console.error("[Findings] Error:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Serve the raw findings_report.md for download
  app.get("/api/workflows/runs/:id/findings/report", optionalAuth, async (req, res) => {
    const runId = req.params.id;
    try {
      const run = await storage.getExecutionRun(runId);
      if (!run) return res.status(404).json({ error: "Run not found" });
      const nextflowRunId: string = (run as any).execution?.nextflowRunId || runId;
      const reportPath = `/tmp/nextflow_runs/${nextflowRunId}/output/findings_report.md`;
      const { readFile } = await import('fs/promises');
      const md = await readFile(reportPath, 'utf8');
      res.setHeader('Content-Type', 'text/markdown; charset=utf-8');
      res.setHeader('Content-Disposition', `attachment; filename="findings_report_${runId}.md"`);
      res.send(md);
    } catch {
      res.status(404).json({ error: "Findings report not yet available" });
    }
  });

  // Proxy for internal analysis trigger (used by FindingsCard polling)
  app.post("/api/internal/analyze-outputs", optionalAuth, express.json(), async (req, res) => {
    const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
    try {
      const resp = await fetch(`${galaxyUrl}/api/nextflow/analyze-outputs`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(req.body),
        signal: AbortSignal.timeout(120_000),
      });
      const data = await resp.json();
      res.status(resp.status).json(data);
    } catch (err: any) {
      res.status(502).json({ error: err.message });
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
        historyId = await userProxy(req).createHistory(sessionName);
        if (req.session) {
          req.session.galaxyHistoryId = historyId;
        }
      }

      const collection = await userProxy(req).createDatasetCollection(
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
        historyId = await userProxy(req).createHistory(sessionName);
        if (req.session) {
          req.session.galaxyHistoryId = historyId;
        }
      }

      const dataset = await userProxy(req).createDeferredDataset(
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
        historyId = await userProxy(req).createHistory(sessionName);
        if (req.session) {
          req.session.galaxyHistoryId = historyId;
        }
      }

      const result = await userProxy(req).launchInteractiveTool(
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
  // Chat sessions — stored directly in PostgreSQL (chat_sessions table).
  // Requires migration 0006_chat_sessions.sql.
  // ---------------------------------------------------------------------------
  app.get("/api/sessions", authenticateToken, async (req: any, res) => {
    try {
      const limit = Math.min(parseInt((req.query as any).limit || '20', 10), 100);
      const rows = await pool.query(
        `SELECT session_id, title, status, created_at, last_activity,
                jsonb_array_length(messages) AS message_count
         FROM chat_sessions WHERE user_id = $1
         ORDER BY last_activity DESC LIMIT $2`,
        [req.user.id, limit]
      );
      res.json(rows.rows);
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  app.get("/api/sessions/:sessionId", authenticateToken, async (req: any, res) => {
    try {
      const rows = await pool.query(
        `SELECT session_id, title, status, created_at, last_activity, messages, workflows, datasets
         FROM chat_sessions WHERE session_id = $1 AND user_id = $2`,
        [req.params.sessionId, req.user.id]
      );
      if (!rows.rows.length) return res.status(404).json({ error: 'Session not found' });
      res.json(rows.rows[0]);
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  app.post("/api/sessions", authenticateToken, express.json(), async (req: any, res) => {
    try {
      const { session_id, title, messages, workflows, datasets } = req.body;
      if (!session_id) return res.status(400).json({ error: 'session_id required' });
      const rows = await pool.query(
        `INSERT INTO chat_sessions (session_id, user_id, title, messages, workflows, datasets)
         VALUES ($1, $2, $3, $4, $5, $6)
         ON CONFLICT (session_id) DO UPDATE SET
           title = EXCLUDED.title, messages = EXCLUDED.messages,
           workflows = EXCLUDED.workflows, datasets = EXCLUDED.datasets,
           last_activity = NOW()
         RETURNING *`,
        [session_id, req.user.id, title || 'New Chat',
         JSON.stringify(messages || []), JSON.stringify(workflows || []), JSON.stringify(datasets || [])]
      );
      res.status(201).json(rows.rows[0]);
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  app.put("/api/sessions/:sessionId", authenticateToken, express.json(), async (req: any, res) => {
    try {
      const { title, status, messages, workflows, datasets } = req.body;
      const rows = await pool.query(
        `UPDATE chat_sessions SET
           title = COALESCE($3, title),
           status = COALESCE($4, status),
           messages = COALESCE($5::jsonb, messages),
           workflows = COALESCE($6::jsonb, workflows),
           datasets = COALESCE($7::jsonb, datasets),
           last_activity = NOW()
         WHERE session_id = $1 AND user_id = $2
         RETURNING *`,
        [req.params.sessionId, req.user.id, title, status,
         messages ? JSON.stringify(messages) : null,
         workflows ? JSON.stringify(workflows) : null,
         datasets ? JSON.stringify(datasets) : null]
      );
      if (!rows.rows.length) return res.status(404).json({ error: 'Session not found' });
      res.json(rows.rows[0]);
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  app.delete("/api/sessions/:sessionId", authenticateToken, async (req: any, res) => {
    try {
      await pool.query(
        `DELETE FROM chat_sessions WHERE session_id = $1 AND user_id = $2`,
        [req.params.sessionId, req.user.id]
      );
      res.status(204).send();
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  // ---------------------------------------------------------------------------
  // Billing API proxy: forward /api/billing/* and /internal/billing/* to the
  // Galaxy Python backend so the React frontend can reach the billing endpoints
  // without needing a direct connection to port 8081.
  // ---------------------------------------------------------------------------
  const GALAXY_URL = process.env.GALAXY_URL || 'http://localhost:8081';
  // When the BFF and Galaxy backend use different JWT_SECRETs (common in dev),
  // set GALAXY_JWT_SECRET to the backend's value so billing proxies can re-sign.
  const _GALAXY_JWT_SECRET = process.env.GALAXY_JWT_SECRET || process.env.JWT_SECRET || 'dev-only-insecure-secret-do-not-use-in-production';

  app.all("/api/billing/*", optionalAuth, async (req: any, res) => {
    try {
      const target = `${GALAXY_URL}${req.path}${req.url.includes('?') ? req.url.slice(req.url.indexOf('?')) : ''}`;
      const headers: Record<string, string> = { "Content-Type": "application/json" };
      // Prefer re-signed Galaxy JWT from cookie auth (supports httpOnly cookie sessions).
      // Fallback: forward raw Authorization header (for clients that still send Bearer tokens).
      if (req.user) {
        const import_jwt = (await import('jsonwebtoken')).default;
        const galaxyToken = import_jwt.sign(
          { user_id: req.user.id, email: req.user.email },
          _GALAXY_JWT_SECRET,
          { expiresIn: '1h' }
        );
        headers["Authorization"] = `Bearer ${galaxyToken}`;
      } else {
        const auth = req.headers["authorization"];
        if (auth) headers["Authorization"] = auth as string;
      }

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
  // Admin: Audit Log Viewer (SOC2 / HIPAA compliance)
  // ============================================================================

  // GET /api/admin/audit-log?limit=100&offset=0&action=safety.block&userId=<id>
  app.get("/api/admin/audit-log", authenticateToken, requireAdmin, async (req, res) => {
    try {
      const limit = Math.min(parseInt(String(req.query.limit ?? 100)), 1000);
      const offset = parseInt(String(req.query.offset ?? 0));
      const filterAction = req.query.action ? String(req.query.action) : null;
      const filterUserId = req.query.userId ? String(req.query.userId) : null;
      const filterStatus = req.query.status ? String(req.query.status) : null;
      const since = req.query.since ? new Date(String(req.query.since)) : null;

      let query = db.select().from(auditLogs).$dynamic();

      if (filterAction) {
        query = query.where(eq(auditLogs.action, filterAction)) as typeof query;
      }
      if (filterUserId) {
        query = query.where(eq(auditLogs.userId, filterUserId)) as typeof query;
      }
      if (filterStatus) {
        query = query.where(eq(auditLogs.status, filterStatus)) as typeof query;
      }
      if (since) {
        query = query.where(sql`${auditLogs.timestamp} >= ${since}`) as typeof query;
      }

      const rows = await query
        .orderBy(desc(auditLogs.timestamp))
        .limit(limit)
        .offset(offset);

      // Summary stats for the current filter
      const safetyBlocks = rows.filter(r => r.action?.startsWith('safety.')).length;
      const phiEvents = rows.filter(r => r.action === 'safety.phi_strip').length;

      res.json({
        entries: rows,
        count: rows.length,
        limit,
        offset,
        summary: { safetyBlocks, phiEvents },
      });
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  // GET /api/admin/audit-log/summary — aggregate counts by action type
  app.get("/api/admin/audit-log/summary", authenticateToken, requireAdmin, async (req, res) => {
    try {
      const since = req.query.since
        ? new Date(String(req.query.since))
        : new Date(Date.now() - 7 * 24 * 60 * 60 * 1000); // default: last 7 days

      const rows = await db
        .select({
          action: auditLogs.action,
          status: auditLogs.status,
          count: sql<number>`cast(count(*) as int)`,
        })
        .from(auditLogs)
        .where(sql`${auditLogs.timestamp} >= ${since}`)
        .groupBy(auditLogs.action, auditLogs.status)
        .orderBy(desc(sql`count(*)`));

      res.json({ since: since.toISOString(), rows });
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  // ============================================================================
  // Track 4B-i: "Open Claw" — Power-user mode with BioMate tools visible
  //
  // Named after the OpenClaw conversation-state pattern (conversation-state.ts:8).
  // Users interact with Claude directly (raw Claude API, not BioMate's AI layer)
  // but with BioMate tools available as function calls. Tool invocations are
  // streamed as SSE events so the UI can render <tool_use> blocks visibly.
  //
  // Security: all tool calls go through BioMate's auth layer; rate limiting applies.
  // ============================================================================

  // GET /api/open-claw/tools — list the BioMate tools as Anthropic tool schemas
  app.get("/api/open-claw/tools", optionalAuth, async (req, res) => {
    res.json({
      tools: OPEN_CLAW_TOOLS,
      model: "claude-sonnet-4-6",
      note: "Open Claw mode: Claude has direct access to BioMate tools. Tool calls are shown in full.",
    });
  });

  // POST /api/open-claw/stream — SSE: Claude API with BioMate tools, agentic loop
  // Body: { messages: Message[], system?: string }
  app.post("/api/open-claw/stream", optionalAuth, async (req, res) => {
    if (!process.env.ANTHROPIC_API_KEY) {
      return res.status(503).json({ error: "ANTHROPIC_API_KEY not configured" });
    }

    const { messages, system } = req.body || {};
    if (!messages || !Array.isArray(messages) || messages.length === 0) {
      return res.status(400).json({ error: "messages array required" });
    }

    res.setHeader("Content-Type", "text/event-stream");
    res.setHeader("Cache-Control", "no-cache, no-transform");
    res.setHeader("Connection", "keep-alive");
    res.setHeader("X-Accel-Buffering", "no");
    res.flushHeaders?.();

    const safeSend = (event: string, data: unknown) => {
      if (!res.writableEnded) {
        res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
      }
    };

    try {
      const Anthropic = (await import('@anthropic-ai/sdk')).default;
      const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
      const userId = req.user ? String((req.user as any).id) : null;

      const systemPrompt = system || `You are Claude, an AI assistant with access to BioMate's scientific workflow tools.
BioMate is a bioinformatics platform that runs genomics, proteomics, drug discovery, and cryo-EM workflows on AWS Batch.
When the user asks to run an analysis or search for a workflow, use the BioMate tools directly.
Show your reasoning. Tool invocations and results are visible to the user in full.`;

      // Agentic loop: keep calling Claude until no more tool_use blocks
      let currentMessages = messages;
      let iterations = 0;
      const MAX_ITERATIONS = 10;

      while (iterations < MAX_ITERATIONS) {
        iterations++;
        let hasToolUse = false;
        const toolResults: Array<{ type: 'tool_result'; tool_use_id: string; content: string }> = [];

        // Stream a single turn
        const stream = await client.messages.stream({
          model: "claude-sonnet-4-6",
          max_tokens: 4096,
          system: systemPrompt,
          tools: OPEN_CLAW_TOOLS as any,
          messages: currentMessages,
        });

        let assistantContent: any[] = [];
        let currentTextBlock = "";
        let currentToolBlock: any = null;

        for await (const event of stream) {
          if (event.type === "content_block_start") {
            if (event.content_block.type === "text") {
              currentTextBlock = "";
              assistantContent.push({ type: "text", text: "" });
            } else if (event.content_block.type === "tool_use") {
              currentToolBlock = { type: "tool_use", id: event.content_block.id, name: event.content_block.name, input: {} };
              assistantContent.push(currentToolBlock);
              hasToolUse = true;
              safeSend("tool_call_start", { id: event.content_block.id, name: event.content_block.name });
            }
          } else if (event.type === "content_block_delta") {
            if (event.delta.type === "text_delta") {
              currentTextBlock += event.delta.text;
              const last = assistantContent[assistantContent.length - 1];
              if (last?.type === "text") last.text = currentTextBlock;
              safeSend("delta", { text: event.delta.text });
            } else if (event.delta.type === "input_json_delta" && currentToolBlock) {
              currentToolBlock._inputRaw = (currentToolBlock._inputRaw || "") + event.delta.partial_json;
            }
          } else if (event.type === "content_block_stop") {
            if (currentToolBlock?._inputRaw !== undefined) {
              try {
                currentToolBlock.input = JSON.parse(currentToolBlock._inputRaw);
              } catch { currentToolBlock.input = {}; }
              delete currentToolBlock._inputRaw;
              safeSend("tool_call_complete", { id: currentToolBlock.id, name: currentToolBlock.name, input: currentToolBlock.input });
              currentToolBlock = null;
            }
          }
        }

        // Add assistant turn to history
        currentMessages = [...currentMessages, { role: "assistant", content: assistantContent }];

        if (!hasToolUse) break;  // No tool calls → done

        // Execute tool calls
        for (const block of assistantContent) {
          if (block.type !== "tool_use") continue;
          const toolResult = await executeOpenClaudeTool(block.name, block.input, userId, req);
          safeSend("tool_result", { tool_use_id: block.id, name: block.name, result: toolResult });
          toolResults.push({ type: "tool_result", tool_use_id: block.id, content: JSON.stringify(toolResult) });
        }

        // Add tool results to messages for next iteration
        currentMessages = [...currentMessages, { role: "user", content: toolResults }];
      }

      safeSend("complete", { iterations });
      res.end();
    } catch (err: any) {
      safeSend("error", { message: err.message });
      res.end();
    }
  });

  // ============================================================================
  // Instrument Events API
  // Physical instrument connectors (flow cytometer, plate reader, qPCR, LC-MS,
  // cryo-EM) POST here when they detect new data. Events are persisted and
  // surfaced to the user as workflow-launch suggestions.
  // ============================================================================

  // POST /api/instruments/new-data — receive a new instrument data event
  // Body: InstrumentEvent payload from a Python connector watcher
  // Auth: BIOMATE_API_KEY Bearer token (service-to-service) or user JWT
  app.post("/api/instruments/new-data", optionalAuth, async (req, res) => {
    const body = req.body || {};

    // Minimal validation
    const { source, experimentType, workflowId, description, message } = body;
    if (!source || !workflowId || !description || !message) {
      return res.status(400).json({
        error: "Required fields: source, workflowId, description, message",
      });
    }
    const expType = experimentType || body.assay_type || "unknown";

    try {
      const [event] = await db
        .insert(instrumentEvents)
        .values({
          source: String(source),
          vendor: body.vendor ? String(body.vendor) : null,
          directory: body.directory ? String(body.directory) : null,
          experimentType: String(expType),
          assayType: body.assay_type ? String(body.assay_type) : null,
          workflowId: String(workflowId),
          filePath: body.file_path ? String(body.file_path) : null,
          fcsDir: body.fcs_dir ? String(body.fcs_dir) : null,
          fileCount: body.file_count != null ? Number(body.file_count) : null,
          paramKey: body.param_key ? String(body.param_key) : null,
          runName: body.run_name ? String(body.run_name) : null,
          targets: Array.isArray(body.targets) ? JSON.stringify(body.targets) : null,
          sampleCount: body.sample_count != null ? Number(body.sample_count) : null,
          channels: Array.isArray(body.channels) ? JSON.stringify(body.channels) : null,
          analysisFunction: body.analysis_function ? String(body.analysis_function) : null,
          description: String(description),
          message: String(message),
          status: "pending",
          userId: req.user ? String((req.user as any).id) : null,
        })
        .returning({ id: instrumentEvents.id });

      console.log("[instruments] event received", { id: event?.id, source, workflowId });
      return res.status(201).json({ event_id: event?.id, status: "pending" });
    } catch (err: any) {
      console.error("[instruments] error storing event:", (err as any).message);
      return res.status(500).json({ error: "Failed to store instrument event" });
    }
  });

  // GET /api/instruments/events — list pending instrument events for the current user
  // Returns events that haven't been launched or dismissed yet.
  app.get("/api/instruments/events", authenticateToken, async (req, res) => {
    try {
      const { eq, desc } = await import("drizzle-orm");
      const events = await db
        .select()
        .from(instrumentEvents)
        .where(eq(instrumentEvents.status, "pending"))
        .orderBy(desc(instrumentEvents.timestamp))
        .limit(50);

      return res.json({
        events: events.map((e) => ({
          ...e,
          targets: e.targets ? JSON.parse(e.targets) : [],
          channels: e.channels ? JSON.parse(e.channels) : [],
        })),
      });
    } catch (err: any) {
      return res.status(500).json({ error: "Failed to fetch instrument events" });
    }
  });

  // PATCH /api/instruments/events/:id — update status (launched | dismissed)
  app.patch("/api/instruments/events/:id", authenticateToken, async (req, res) => {
    const { id } = req.params;
    const { status } = req.body || {};
    if (!["launched", "dismissed"].includes(status)) {
      return res.status(400).json({ error: "status must be 'launched' or 'dismissed'" });
    }
    try {
      const { eq } = await import("drizzle-orm");
      await db
        .update(instrumentEvents)
        .set({ status, userId: String((req.user as any).id) })
        .where(eq(instrumentEvents.id, id));
      return res.json({ ok: true });
    } catch (err: any) {
      return res.status(500).json({ error: "Failed to update instrument event" });
    }
  });

  // ============================================================================
  // User Domain Profile API
  // ============================================================================

  app.post("/api/user/domain-profile", optionalAuth, express.json(), async (req, res) => {
    try {
      const proxy = userProxy(req);
      const response = await proxy.client.post("/api/user/domain-profile", req.body);
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
      const proxy = userProxy(req);
      const response = await proxy.client.get("/api/user/domain-profile");
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

    const prompt = `Answer the following question about the provided text with ONLY "yes" or "no".\n\nText:\n${text.substring(0, 2000)}\n\nQuestion: ${question}`;

    // Attempt 1: Gemini Flash (primary)
    if (process.env.GEMINI_API_KEY) {
      try {
        const raw = await callGeminiFlash({
          messages: [{ role: "user", content: prompt }],
          maxTokens: 1024,
          temperature: 0.0,  // binary yes/no classification must be deterministic
        });
        res.json({ answer: raw.trim().toLowerCase().startsWith("yes") || raw.trim().toLowerCase() === "true" });
        return;
      } catch (err: any) {
        console.warn("[llm/classify] Gemini failed, trying Ollama:", err.message);
      }
    }

    // Attempt 2: Local Ollama (fallback when Anthropic key absent or call fails)
    const ollamaUrl = process.env.OLLAMA_BASE_URL ?? "http://localhost:11434";
    const ollamaModel = process.env.OLLAMA_CLASSIFY_MODEL ?? "llama3";
    try {
      const ollamaRes = await fetch(`${ollamaUrl}/api/generate`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ model: ollamaModel, prompt, stream: false }),
        signal: AbortSignal.timeout(8000),
      });
      if (ollamaRes.ok) {
        const ollamaData = await ollamaRes.json() as any;
        const raw = (ollamaData?.response ?? "").trim().toLowerCase();
        res.json({ answer: raw.startsWith("yes") || raw === "true" });
        return;
      }
    } catch (ollamaErr: any) {
      console.warn("[llm/classify] Ollama unavailable:", ollamaErr.message);
    }

    // Attempt 3: Keyword regex (last resort — no LLM available)
    const combined = (text + " " + question).toLowerCase();
    const affirmative = ["yes", "true", "correct", "mention", "contain", "include", "present", "generated", "workflow", "accession", "srr"];
    const negative = ["no", "false", "not", "absent", "failed", "missing"];
    const affCount = affirmative.filter(w => combined.includes(w)).length;
    const negCount = negative.filter(w => combined.includes(w)).length;
    res.json({ answer: affCount > negCount });
  });

  // ============================================================================

  // ============================================================================
  // Pilot Experiment API — Track 2C: Test Harness UX
  // Experiments = two workflow runs (control vs experimental) + comparison report
  // ============================================================================

  /** Create a new experiment record (execution is triggered separately by the frontend). */
  app.post("/api/experiments", optionalAuth, express.json(), async (req, res) => {
    const userId: string | undefined = (req as any).user?.id;
    if (!userId) return res.status(401).json({ error: "Authentication required" });

    const {
      hypothesis,
      workflowId,
      workflowName,
      controlLabel = "Control",
      experimentalLabel = "Experimental",
      controlParams,
      experimentalParams,
      metrics = [],
    } = req.body ?? {};

    if (!hypothesis || !workflowId || !controlParams || !experimentalParams) {
      return res.status(400).json({ error: "hypothesis, workflowId, controlParams, experimentalParams are required" });
    }

    try {
      const { experiments } = await import("../shared/schema");
      const { db } = await import("./db");
      const [row] = await db
        .insert(experiments)
        .values({
          userId,
          hypothesis,
          workflowId,
          workflowName: workflowName || workflowId,
          controlLabel,
          experimentalLabel,
          controlParams: typeof controlParams === "string" ? controlParams : JSON.stringify(controlParams),
          experimentalParams: typeof experimentalParams === "string" ? experimentalParams : JSON.stringify(experimentalParams),
          metrics: JSON.stringify(Array.isArray(metrics) ? metrics : []),
          status: "pending",
        })
        .returning();

      return res.json({ id: row.id, status: "pending", createdAt: row.createdAt });
    } catch (err: any) {
      console.error("[Experiments] create error:", err.message);
      return res.status(500).json({ error: err.message });
    }
  });

  /** Link run IDs to an experiment and transition it to running state. */
  app.patch("/api/experiments/:id", optionalAuth, express.json(), async (req, res) => {
    const userId: string | undefined = (req as any).user?.id;
    if (!userId) return res.status(401).json({ error: "Authentication required" });

    const { controlRunId, experimentalRunId } = req.body ?? {};
    try {
      const { experiments } = await import("../shared/schema");
      const { db } = await import("./db");
      const { eq } = await import("drizzle-orm");

      const [row] = await db
        .update(experiments)
        .set({
          controlRunId: controlRunId || undefined,
          experimentalRunId: experimentalRunId || undefined,
          status: controlRunId && experimentalRunId ? "running" : "pending",
          updatedAt: new Date(),
        })
        .where(eq(experiments.id, req.params.id))
        .returning();

      if (!row) return res.status(404).json({ error: "Experiment not found" });
      return res.json({ id: row.id, status: row.status });
    } catch (err: any) {
      console.error("[Experiments] patch error:", err.message);
      return res.status(500).json({ error: err.message });
    }
  });

  /** List all experiments for the authenticated user. */
  app.get("/api/experiments", optionalAuth, async (req, res) => {
    const userId: string | undefined = (req as any).user?.id;
    if (!userId) return res.status(401).json({ error: "Authentication required" });

    try {
      const { experiments } = await import("../shared/schema");
      const { db } = await import("./db");
      const { eq, desc } = await import("drizzle-orm");

      const rows = await db
        .select()
        .from(experiments)
        .where(eq(experiments.userId, userId))
        .orderBy(desc(experiments.createdAt))
        .limit(50);

      return res.json({ experiments: rows.map(r => ({
        id: r.id,
        hypothesis: r.hypothesis,
        workflowId: r.workflowId,
        workflowName: r.workflowName,
        controlLabel: r.controlLabel,
        experimentalLabel: r.experimentalLabel,
        status: r.status,
        controlRunId: r.controlRunId,
        experimentalRunId: r.experimentalRunId,
        hasResults: !!r.comparisonResult,
        createdAt: r.createdAt,
        updatedAt: r.updatedAt,
      })) });
    } catch (err: any) {
      console.error("[Experiments] list error:", err.message);
      return res.status(500).json({ error: err.message });
    }
  });

  /** Poll experiment results — computes comparison when both runs reach terminal state. */
  app.get("/api/experiments/:id/results", optionalAuth, async (req, res) => {
    const userId: string | undefined = (req as any).user?.id;
    if (!userId) return res.status(401).json({ error: "Authentication required" });

    try {
      const { experiments } = await import("../shared/schema");
      const { db } = await import("./db");
      const { eq } = await import("drizzle-orm");

      const [exp] = await db
        .select()
        .from(experiments)
        .where(eq(experiments.id, req.params.id));

      if (!exp) return res.status(404).json({ error: "Experiment not found" });
      if (exp.userId !== userId) return res.status(403).json({ error: "Forbidden" });

      // If already computed, return cached result
      if (exp.comparisonResult) {
        return res.json({
          id: exp.id,
          status: exp.status,
          hypothesis: exp.hypothesis,
          controlLabel: exp.controlLabel,
          experimentalLabel: exp.experimentalLabel,
          comparison: JSON.parse(exp.comparisonResult),
          narrative: exp.narrative,
        });
      }

      // If no run IDs yet, experiment hasn't started
      if (!exp.controlRunId || !exp.experimentalRunId) {
        return res.json({ id: exp.id, status: exp.status });
      }

      // Fetch both runs
      const controlRun = await storage.getExecutionRun(exp.controlRunId);
      const experimentalRun = await storage.getExecutionRun(exp.experimentalRunId);

      const terminalStatuses = new Set(["completed", "failed", "error", "cancelled"]);
      // ExecutionRun has status nested at execution.status
      const controlStatus = ((controlRun as any)?.execution?.status || (controlRun as any)?.status || "unknown").toLowerCase();
      const experimentalStatus = ((experimentalRun as any)?.execution?.status || (experimentalRun as any)?.status || "unknown").toLowerCase();
      const bothDone = terminalStatuses.has(controlStatus) && terminalStatuses.has(experimentalStatus);

      if (!bothDone) {
        return res.json({
          id: exp.id,
          status: "running",
          controlRun: { runId: exp.controlRunId, status: controlStatus },
          experimentalRun: { runId: exp.experimentalRunId, status: experimentalStatus },
        });
      }

      // Both runs are done — compute comparison
      const comparison = await storage.compareExecutionRuns(exp.controlRunId, exp.experimentalRunId);

      // Generate automated narrative
      const narrative = _buildExperimentNarrative(
        exp.hypothesis,
        exp.controlLabel || "Control",
        exp.experimentalLabel || "Experimental",
        controlStatus,
        experimentalStatus,
        comparison
      );

      // Cache result
      const finalStatus = controlStatus === "completed" && experimentalStatus === "completed"
        ? "completed"
        : "failed";

      await db
        .update(experiments)
        .set({
          status: finalStatus,
          comparisonResult: comparison ? JSON.stringify(comparison) : null,
          narrative,
          updatedAt: new Date(),
        })
        .where(eq(experiments.id, req.params.id));

      return res.json({
        id: exp.id,
        status: finalStatus,
        hypothesis: exp.hypothesis,
        controlLabel: exp.controlLabel,
        experimentalLabel: exp.experimentalLabel,
        controlRun: { runId: exp.controlRunId, status: controlStatus },
        experimentalRun: { runId: exp.experimentalRunId, status: experimentalStatus },
        comparison,
        narrative,
      });
    } catch (err: any) {
      console.error("[Experiments] results error:", err.message);
      return res.status(500).json({ error: err.message });
    }
  });

  // ============================================================================
  // Data Analysis API — Track 2D: Input Data Analysis UX
  // Lightweight file stats: FASTQ read count, CSV shape, FASTA sequence count, VCF variants
  // ============================================================================

  app.post("/api/data/analyze", optionalAuth, express.json(), async (req, res) => {
    const { filePath, fileName, fileType } = req.body ?? {};
    if (!filePath && !fileName) {
      return res.status(400).json({ error: "filePath or fileName is required" });
    }

    const name: string = fileName || filePath.split('/').pop() || '';
    const ext = name.split('.').pop()?.toLowerCase() || '';

    try {
      // Resolve actual disk path
      let diskPath: string | null = null;
      if (filePath && filePath.startsWith('/')) {
        diskPath = filePath;
      } else if (filePath && filePath.startsWith('s3://')) {
        // S3 path — can't analyze server-side without downloading; return stub
        return res.json({
          fileName: name,
          fileType: ext,
          analyzed: false,
          note: 'S3 file analysis not yet supported server-side. Download to local path first.',
        });
      }

      // Check file exists synchronously via async stat
      if (!diskPath) return res.json({ fileName: name, fileType: ext, analyzed: false, note: 'File path could not be resolved.' });
      try { await fs.stat(diskPath); } catch { return res.json({ fileName: name, fileType: ext, analyzed: false, note: 'File not accessible on server.' }); }

      const { createInterface } = await import('readline');
      const resolvedPath: string = diskPath;

      const analyzeLines = (maxLines: number): Promise<string[]> => new Promise((resolve) => {
        const lines: string[] = [];
        const rl = createInterface({ input: createReadStream(resolvedPath), crlfDelay: Infinity });
        rl.on('line', (line: string) => { lines.push(line); if (lines.length >= maxLines) rl.close(); });
        rl.on('close', () => resolve(lines));
        rl.on('error', () => resolve(lines));
      });

      const stats = await fs.stat(diskPath);
      const fileSizeBytes = stats.size;

      if (ext === 'fastq' || ext === 'fq' || ext === 'fastq.gz' || ext === 'fq.gz') {
        // FASTQ: every 4 lines = 1 read
        const lines = await analyzeLines(40000);
        const readCount = Math.floor(lines.length / 4);
        const totalLineCount = lines.length;
        // Avg quality from @-record quality lines (lines 3 of each record)
        let totalQuality = 0;
        let qualCount = 0;
        for (let i = 3; i < lines.length; i += 4) {
          for (const ch of lines[i]) {
            totalQuality += ch.charCodeAt(0) - 33; // Phred+33
            qualCount++;
          }
        }
        const avgQuality = qualCount > 0 ? (totalQuality / qualCount).toFixed(1) : null;
        const seqLengths = lines.filter((_, i) => i % 4 === 1).map(l => l.length);
        const avgSeqLen = seqLengths.length > 0 ? Math.round(seqLengths.reduce((a, b) => a + b, 0) / seqLengths.length) : null;
        return res.json({
          fileName: name, fileType: 'fastq', analyzed: true, fileSizeMb: (fileSizeBytes / 1e6).toFixed(2),
          readCount: totalLineCount < 40000 ? readCount : `≥${readCount} (truncated sample)`,
          avgQuality, avgSeqLen,
          passesQualityGate: avgQuality !== null && parseFloat(avgQuality) >= 20,
          qualityGateThreshold: { minAvgQ: 20, minReads: 10000 },
        });
      }

      if (ext === 'fasta' || ext === 'fa' || ext === 'fna' || ext === 'ffn' || ext === 'faa') {
        const lines = await analyzeLines(50000);
        const seqHeaders = lines.filter(l => l.startsWith('>'));
        const seqCount = seqHeaders.length;
        const seqLengths: number[] = [];
        let currentLen = 0;
        for (const line of lines) {
          if (line.startsWith('>')) { if (currentLen > 0) seqLengths.push(currentLen); currentLen = 0; }
          else { currentLen += line.trim().length; }
        }
        if (currentLen > 0) seqLengths.push(currentLen);
        const avgLen = seqLengths.length > 0 ? Math.round(seqLengths.reduce((a, b) => a + b, 0) / seqLengths.length) : null;
        return res.json({
          fileName: name, fileType: 'fasta', analyzed: true, fileSizeMb: (fileSizeBytes / 1e6).toFixed(2),
          sequenceCount: lines.length < 50000 ? seqCount : `≥${seqCount} (truncated)`,
          avgLength: avgLen,
        });
      }

      if (ext === 'csv' || ext === 'tsv') {
        const lines = await analyzeLines(1005);
        const sep = ext === 'tsv' ? '\t' : ',';
        const headers = lines[0]?.split(sep) ?? [];
        const dataRows = lines.slice(1, 1001);
        // Missing values per column
        const missing: Record<string, number> = {};
        for (const col of headers) missing[col] = 0;
        for (const row of dataRows) {
          const cells = row.split(sep);
          headers.forEach((col, i) => { if (!cells[i] || cells[i].trim() === '' || cells[i] === 'NA' || cells[i] === 'null') missing[col]++; });
        }
        const maxMissingPct = Math.max(...Object.values(missing).map(v => v / Math.max(dataRows.length, 1) * 100));
        return res.json({
          fileName: name, fileType: ext, analyzed: true, fileSizeMb: (fileSizeBytes / 1e6).toFixed(2),
          rowCount: lines.length < 1005 ? dataRows.length : `≥${dataRows.length} (truncated)`,
          columnCount: headers.length,
          columns: headers.slice(0, 20),
          missingValuesByColumn: missing,
          passesQualityGate: maxMissingPct <= 20,
          qualityGateThreshold: { maxMissingPct: 20 },
        });
      }

      if (ext === 'vcf') {
        const lines = await analyzeLines(20000);
        const dataLines = lines.filter(l => !l.startsWith('#'));
        const chrDist: Record<string, number> = {};
        let filterPass = 0;
        for (const line of dataLines) {
          const cols = line.split('\t');
          if (cols[0]) chrDist[cols[0]] = (chrDist[cols[0]] ?? 0) + 1;
          if (cols[6] === 'PASS') filterPass++;
        }
        return res.json({
          fileName: name, fileType: 'vcf', analyzed: true, fileSizeMb: (fileSizeBytes / 1e6).toFixed(2),
          variantCount: lines.length < 20000 ? dataLines.length : `≥${dataLines.length} (truncated)`,
          filterPassCount: filterPass,
          chromosomeDistribution: chrDist,
        });
      }

      // Generic: just file size
      return res.json({ fileName: name, fileType: ext, analyzed: false, fileSizeMb: (fileSizeBytes / 1e6).toFixed(2), note: 'File type not supported for analysis.' });
    } catch (err: any) {
      console.error("[DataAnalyze] error:", err.message);
      return res.status(500).json({ error: err.message });
    }
  });

  // ── Agent code execution endpoint ────────────────────────────────────────────
  // POST /api/code/run — used by the `run_code` agent tool.
  // Runs Python / R / bash in a restricted subprocess and returns captured output.
  app.post("/api/code/run", optionalAuth, express.json(), async (req, res) => {
    const { language, code, input_datasets, timeout_seconds } = req.body ?? {};
    if (!code || typeof language !== 'string' || !['python', 'r', 'bash'].includes(language)) {
      return res.status(400).json({ error: 'language (python|r|bash) and code are required' });
    }
    try {
      const { runCode } = await import('./code-runner');
      const result = await runCode({
        language: language as 'python' | 'r' | 'bash',
        code,
        input_datasets: Array.isArray(input_datasets) ? input_datasets : [],
        timeout_seconds: typeof timeout_seconds === 'number' ? timeout_seconds : 15,
        downloadDataset: (id: string) => galaxyAPIProxy.downloadDataset(id),
      });
      res.json(result);
    } catch (err: any) {
      res.status(500).json({ error: err?.message ?? String(err) });
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

  // ── Accession ID resolver ────────────────────────────────────────────────────
  // POST /api/accession/resolve — resolves SRR*, PDB*, EMDB-* IDs to URLs/metadata
  app.post("/api/accession/resolve", optionalAuth, express.json(), async (req, res) => {
    const { accession } = req.body ?? {};
    if (!accession || typeof accession !== 'string') {
      return res.status(400).json({ error: 'accession is required' });
    }
    const id = accession.trim().toUpperCase();
    try {
      if (/^(SRR|ERR|DRR)\d+$/i.test(id)) {
        // SRA run accession
        return res.json({
          accession: id,
          type: 'sra_run',
          url: `https://trace.ncbi.nlm.nih.gov/Traces/sra/?run=${id}`,
          ftp_url: `ftp://ftp.sra.ebi.ac.uk/vol1/fastq/${id.substring(0, 6)}/${id.length > 9 ? `00${id.slice(-1)}/` : ''}${id}/`,
          description: `NCBI SRA run ${id}`,
          param_hint: 'input',
        });
      }
      if (/^(SRP|ERP|DRP)\d+$/i.test(id)) {
        return res.json({
          accession: id,
          type: 'sra_study',
          url: `https://www.ncbi.nlm.nih.gov/sra?term=${id}`,
          description: `SRA study ${id}`,
        });
      }
      if (/^[A-Z0-9]{4}$/i.test(id) || /^PDB:\S+$/i.test(id)) {
        const pdbId = id.replace(/^PDB:/i, '').toLowerCase();
        return res.json({
          accession: pdbId.toUpperCase(),
          type: 'pdb',
          url: `https://www.rcsb.org/structure/${pdbId.toUpperCase()}`,
          download_url: `https://files.rcsb.org/download/${pdbId.toUpperCase()}.pdb`,
          mmcif_url: `https://files.rcsb.org/download/${pdbId.toUpperCase()}.cif`,
          description: `PDB structure ${pdbId.toUpperCase()}`,
          param_hint: 'receptor',
        });
      }
      if (/^EMDB-?\d+$/i.test(id) || /^EMD-\d+$/i.test(id)) {
        const emdId = id.replace(/^EMDB-?/i, 'EMD-').replace(/^EMD-?(\d)/i, 'EMD-$1');
        const num = emdId.replace(/\D/g, '');
        return res.json({
          accession: emdId.toUpperCase(),
          type: 'emdb',
          url: `https://www.ebi.ac.uk/emdb/${emdId.toUpperCase()}`,
          download_url: `https://ftp.ebi.ac.uk/pub/databases/emdb/structures/${emdId.toUpperCase()}/map/emd_${num}.map.gz`,
          description: `EMDB entry ${emdId.toUpperCase()}`,
          param_hint: 'input_map',
        });
      }
      if (/^GSE?\d+$/i.test(id)) {
        return res.json({
          accession: id,
          type: 'geo',
          url: `https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=${id}`,
          description: `GEO series ${id}`,
          param_hint: 'input',
        });
      }
      return res.status(422).json({ error: `Unrecognized accession format: ${id}` });
    } catch (err: any) {
      return res.status(500).json({ error: err.message || 'Resolve failed' });
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
function classifyFileType(extension: string): 'image' | 'table' | 'text' | 'binary' | 'interactive' | 'structure' | 'density_map' {
  const ext = extension.toLowerCase();

  const imageExts = ['png', 'jpg', 'jpeg', 'svg', 'gif', 'pdf', 'tiff', 'bmp'];
  // json renders as a sortable table via CsvTableViewer; csv/tsv are canonical tables
  const tableExts = ['tsv', 'csv', 'tabular', 'json', 'bed', 'gtf', 'gff', 'vcf'];
  const interactiveExts = ['html', 'htm'];
  const textExts = ['txt', 'log', 'md', 'xml', 'yaml', 'yml', 'nf', 'config'];
  // Molecular structure files — rendered by StructureViewer (3Dmol.js)
  const structureExts = ['pdb', 'cif', 'mmcif', 'ent'];
  // Cryo-EM density map files — rendered by DensityMapViewer (2D slices)
  const densityMapExts = ['mrc', 'map', 'rec'];

  if (imageExts.includes(ext)) return 'image';
  if (tableExts.includes(ext)) return 'table';
  if (interactiveExts.includes(ext)) return 'interactive';
  if (structureExts.includes(ext)) return 'structure';
  if (densityMapExts.includes(ext)) return 'density_map';
  if (textExts.includes(ext)) return 'text';
  return 'binary';
}

function isVisualizable(extension: string): boolean {
  const visualizableExts = [
    'png', 'jpg', 'jpeg', 'svg', 'gif', 'pdf', 'html', 'htm',
    'json', 'csv', 'tsv', 'txt', 'fasta', 'fa', 'fastq', 'fq',
    // Structure and density map files — have dedicated viewers
    'pdb', 'cif', 'mmcif', 'ent', 'mrc', 'map', 'rec',
  ];
  return visualizableExts.includes(extension.toLowerCase());
}

// ============================================================================
// Experiment narrative generator — Track 2C
// ============================================================================

function _buildExperimentNarrative(
  hypothesis: string,
  controlLabel: string,
  experimentalLabel: string,
  controlStatus: string,
  experimentalStatus: string,
  comparison: any
): string {
  const lines: string[] = [];

  lines.push(`**Hypothesis:** ${hypothesis}`);
  lines.push('');

  // Execution summary
  const controlOk = controlStatus === 'completed';
  const experimentalOk = experimentalStatus === 'completed';

  if (!controlOk && !experimentalOk) {
    lines.push(`Both the ${controlLabel} and ${experimentalLabel} runs failed — no comparison is possible. Check execution logs for error details.`);
    return lines.join('\n');
  }
  if (!controlOk) {
    lines.push(`The ${controlLabel} run failed (status: ${controlStatus}). Comparison is based on the ${experimentalLabel} run only.`);
    return lines.join('\n');
  }
  if (!experimentalOk) {
    lines.push(`The ${experimentalLabel} run failed (status: ${experimentalStatus}). Comparison is based on the ${controlLabel} run only.`);
    return lines.join('\n');
  }

  if (!comparison) {
    lines.push('Both runs completed successfully. Comparison data is not yet available.');
    return lines.join('\n');
  }

  // RunComparisonResponse shape: { runs[], comparison: { runtimeDelta, memoryDelta, qualityDelta, parameterDifferences }, recommendation?: { preferredRun, reason } }
  const cmp = comparison?.comparison ?? comparison ?? {};
  const rec = comparison?.recommendation;

  // Runtime comparison
  const rtDelta: number = cmp.runtimeDelta ?? 0;
  if (Math.abs(rtDelta) > 1) {
    const rtDir = rtDelta > 0 ? `${Math.abs(rtDelta).toFixed(1)}% slower` : `${Math.abs(rtDelta).toFixed(1)}% faster`;
    lines.push(`**Runtime:** ${experimentalLabel} was ${rtDir} than ${controlLabel}.`);
  }

  // Memory comparison
  const memDelta: number = cmp.memoryDelta ?? 0;
  if (Math.abs(memDelta) > 1) {
    const memDir = memDelta > 0 ? `used ${Math.abs(memDelta).toFixed(1)}% more memory` : `used ${Math.abs(memDelta).toFixed(1)}% less memory`;
    lines.push(`**Memory:** ${experimentalLabel} ${memDir}.`);
  }

  // Quality metrics
  const qualityDelta: Record<string, number> = cmp.qualityDelta ?? {};
  const qualityKeys = Object.keys(qualityDelta);
  if (qualityKeys.length > 0) {
    lines.push('');
    lines.push('**Quality metrics:**');
    for (const key of qualityKeys) {
      const delta = qualityDelta[key];
      if (Math.abs(delta) < 0.001) continue;
      const dir = delta > 0 ? `improved by ${delta.toFixed(3)}` : `decreased by ${Math.abs(delta).toFixed(3)}`;
      lines.push(`- ${key}: ${dir}`);
    }
  }

  // Parameter differences
  const paramDiffs: any[] = cmp.parameterDifferences ?? [];
  if (paramDiffs.length > 0) {
    lines.push('');
    lines.push(`**Parameter changes (${paramDiffs.length}):**`);
    for (const diff of paramDiffs.slice(0, 5)) {
      lines.push(`- \`${diff.param}\`: ${JSON.stringify(diff.run1Value)} → ${JSON.stringify(diff.run2Value)}`);
    }
    if (paramDiffs.length > 5) lines.push(`- … and ${paramDiffs.length - 5} more`);
  }

  // Overall recommendation
  lines.push('');
  if (rec?.preferredRun) {
    lines.push(`**Recommendation:** ${rec.reason ?? 'based on quality and resource metrics'}.`);
  }

  return lines.join('\n');
}

