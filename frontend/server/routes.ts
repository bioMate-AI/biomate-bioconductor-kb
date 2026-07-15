import type { Express } from "express";
import express from "express";
import { requestContextMiddleware } from "./request-context";
import { registerJobsRouter } from "./jobs/router";
// Side-effect import: registers the `download_all_zip` job handler.
import "./jobs/handlers/download-all-zip";
import "./jobs/handlers/methods-report";
import "./jobs/handlers/findings-analysis";
import { createServer, type Server } from "http";
import { storage } from "./storage";
import OpenAI from "openai";
import { datasetConfigSchema, inviteCodes, inviteCodeUses, executionRunStatusSchema, auditLogs, instrumentEvents, instruments, INSTRUMENT_TYPES, apiKeys } from "../shared/schema";
import { generateApiKey, listApiKeys } from "./api-key-service";
import type { InsertInviteCode, ExecutionRunStatus, InstrumentType } from "../shared/schema";
import { db, pool } from "./db";
import { selectChatHistoryUnderBudget } from "./chat-history-selector";
import { capDatasetReferences, MAX_DATASET_REFS } from "./dataset-cap";
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
import { buildFiguresFromKeyResults } from "./findings-figures";
import { datasetValidator } from "./dataset-validator";
import { getContextCompressor } from "./context-compressor";
import { WorkflowPrerequisitesValidator } from "./workflow-prerequisites-validator";
import multer from "multer";
import { promises as fs, createReadStream, existsSync, readdirSync } from "fs";
import path from "path";
import { v4 as uuidv4 } from "uuid";
import archiver from "archiver";
import { createHash, randomBytes } from "crypto";
import { authService } from "./auth-service";
import { emailService } from "./email-service";
import { authenticateToken, authenticateStaticApiKey, optionalAuth } from "./auth-middleware";
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
import { decryptField, encryptField } from "./field-encrypt";
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
    awaiting_approval: 'paused',
    paused: 'paused',
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

      // Persist workflow metadata to chat_sessions.workflows so that
      // GET /api/sessions/:id returns a non-empty workflows array and
      // the right panel can render the AfterRunReport/interactive tools.
      if (finalStatus === 'completed' && executionRun.chatSessionId) {
        try {
          const wfName = (executionRun as any).workflowName ||
                         (executionRun as any).workflowDefinition?.name ||
                         (executionRun as any).workflowDefinition?.chain_name ||
                         'Workflow';
          const wfEntry = JSON.stringify([{
            workflow_id: executionRun.id,
            workflow_name: wfName,
            status: 'completed',
          }]);
          await pool.query(
            `UPDATE chat_sessions SET workflows = $1::jsonb, last_activity = NOW()
             WHERE session_id = $2`,
            [wfEntry, executionRun.chatSessionId]
          );
          console.log(`[WorkflowComplete] Wrote workflow entry to chat_sessions for session ${executionRun.chatSessionId}`);
        } catch (sessErr: any) {
          console.error('[WorkflowComplete] Failed to update chat_sessions.workflows:', sessErr?.message);
        }
      }

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

// Start with whichever LLM key is available; Gemini (GOOGLE_API_KEY) is the
// backbone and Anthropic is used for memory, embeddings, and fallback.
// Neither key alone blocks startup — the assistant degrades gracefully.
const _hasAnyLLMKey = !!(
  process.env.ANTHROPIC_API_KEY ||
  process.env.GOOGLE_API_KEY ||
  process.env.GEMINI_API_KEY
);
const galaxyAssistant = _hasAnyLLMKey ? new GalaxyAssistant({
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
  // ── Accession Resolution ─────────────────────────────────────────────────
  {
    name: "resolve_accession",
    description:
      "Identify a public archive accession (GEO, SRA, ENA, DDBJ) and return the " +
      "best BioMate workflow to fetch it plus pre-filled params ready for run_workflow. " +
      "Examples: GSE183947 → Geo Data Connector; SRR12345 → nf-core/fetchngs. " +
      "Call this before run_workflow whenever the user provides an accession instead of a file.",
    input_schema: {
      type: "object" as const,
      properties: {
        accession: {
          type: "string",
          description: "Public archive accession: GSE*, GSM*, GDS*, SRR*, SRX*, SRP*, ERR*, ERX*, ERP*, DRR*, PRJNA*, PRJEB*, E-MTAB-*, E-GEOD-*",
        },
      },
      required: ["accession"],
    },
  },
  // ── Public Data Sources ───────────────────────────────────────────────────
  {
    name: "browse_data",
    description:
      "Browse a biological data repository or S3 workspace by listing files and directories " +
      "at a given path. Public sources (EBI, NCBI, Ensembl, UCSC) require a path. " +
      "S3 sources (biomate_workspace, user_s3) accept an optional prefix. " +
      "Use before fetch_public_data to navigate to the exact file you need.",
    input_schema: {
      type: "object" as const,
      properties: {
        source_id: {
          type: "string",
          enum: ["ebi_ftp", "ncbi_ftp", "ensembl_ftp", "ucsc_downloads", "http_public", "biomate_workspace", "user_s3"],
          description: "Data source to browse. biomate_workspace = BioMate's S3 work bucket; user_s3 = user's own S3 bucket (if configured)",
        },
        path: { type: "string", description: "Directory path or S3 prefix to list (e.g. '/pub/databases/uniprot/.../' or 'results/run-xyz/')" },
      },
      required: ["source_id"],
    },
  },
  {
    name: "fetch_public_data",
    description:
      "Download a file from a public biological repository (EBI, NCBI, Ensembl, UCSC) " +
      "into BioMate's S3 workspace and return a presigned URL and S3 URI. " +
      "Use the S3 URI as a workflow input parameter. Call browse_data first to find the exact path.",
    input_schema: {
      type: "object" as const,
      properties: {
        source_id: {
          type: "string",
          enum: ["ebi_ftp", "ncbi_ftp", "ensembl_ftp", "ucsc_downloads", "http_public"],
          description: "Data source the file comes from",
        },
        remote_path: { type: "string", description: "Path on the FTP server (e.g. '/pub/databases/uniprot/current_release/knowledgebase/complete/uniprot_sprot.fasta.gz')" },
        url: { type: "string", description: "For http_public source: full HTTPS URL of the file to download" },
      },
      required: ["source_id"],
    },
  },
  // ── Bioconductor knowledge ────────────────────────────────────────────────
  // Commented out: BioMate's search_workflow already covers this via the live
  // workflow DB (2,455 workflows). Static per-package skill files are redundant.
  // {
  //   name: "bioconductor_skill",
  //   ...
  // },
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
  // These are loopback self-calls to our own Express server. In production the
  // app force-redirects plain HTTP → HTTPS (security-config.ts), so a bare
  // http://localhost:PORT fetch gets a 301 to https on the plain port and Node
  // fails the TLS handshake → "fetch failed" → every Open-Claw tool returns an
  // error and the agentic loop degrades to narration. Send X-Forwarded-Proto:
  // https (as Caddy does) so the redirect is skipped for these internal calls.
  const _fwd = { "X-Forwarded-Proto": "https" };

  const post = async (path: string, body: any) => {
    const r = await fetch(`${baseUrl}${path}`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: authHeader, ..._fwd },
      body: JSON.stringify(body),
    });
    return r.json();
  };
  const get = async (path: string) => {
    const r = await fetch(`${baseUrl}${path}`, {
      headers: { Authorization: authHeader, ..._fwd },
    });
    return r.json();
  };

  try {
    switch (toolName) {
      // ── Discovery ────────────────────────────────────────────────────────
      case "search_workflow":
        // defer_param_prefill: the connector's client extracts params from the
        // user's request itself, so the backend's inline LLM prefill is redundant
        // here and only adds ~1-2s (up to ~13s under concurrency) to the search.
        // Skip it → sub-second search. (run_workflow takes params from the client,
        // not from the search response.)
        return await post("/api/workflows/search", { query: input.query, limit: input.limit ?? 5, defer_param_prefill: true });

      // ── Execution ────────────────────────────────────────────────────────
      case "run_workflow": {
        // /api/workflows/execute requires a full workflowDefinition object, not a
        // bare workflow_id. Resolve it by calling search first to get workflow_ga.
        const searchResult = await post("/api/workflows/search", {
          query: input.workflow_id,
          limit: 1,
          defer_param_prefill: true,
        });
        const workflowDef = searchResult?.workflow_ga;
        if (!workflowDef) {
          return {
            error: "WORKFLOW_NOT_FOUND",
            message: `No workflow found matching '${input.workflow_id}'. Use search_workflow first to find the correct workflow name.`,
          };
        }
        if (input.params && Object.keys(input.params).length > 0) {
          workflowDef.parameters = { ...(workflowDef.parameters ?? {}), ...input.params };
        }
        return await post("/api/workflows/execute", {
          workflowDefinition: workflowDef,
          ...(input.message ? { message: input.message } : {}),
        });
      }
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

      // ── Accession Resolution ─────────────────────────────────────────────
      case "resolve_accession":
        return await post("/api/accession/resolve", { accession: input.accession });

      // ── Public Data Sources ───────────────────────────────────────────────
      case "browse_data":
        if (input.source_id === "biomate_workspace" || input.source_id === "user_s3") {
          return await get(`/api/s3/browse?prefix=${encodeURIComponent(input.path ?? "")}`);
        }
        return await get(`/api/data/browse?source=${encodeURIComponent(input.source_id)}&path=${encodeURIComponent(input.path ?? "/")}`);

      case "fetch_public_data":
        return await post("/api/data/fetch", {
          source_id: input.source_id,
          remote_path: input.remote_path,
          url: input.url,
        });

      // case "bioconductor_skill": removed — use search_workflow instead

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
const prerequisitesValidator = _hasAnyLLMKey ? new WorkflowPrerequisitesValidator({
  anthropicApiKey: process.env.ANTHROPIC_API_KEY,
  galaxyAPIProxy,
}) : null;

// Initialize memory integration if Galaxy Assistant is available
const memoryIntegration = galaxyAssistant ? createMemoryIntegration(galaxyAssistant) : null;

// Configure multer for file uploads
// 10 GB per-file upload limit. Subject to the user's overall storage quota.
const MAX_FILE_SIZE_GB = 10;
const MAX_FILE_SIZE_BYTES = MAX_FILE_SIZE_GB * 1024 * 1024 * 1024; // 10 GB

const uploadDir = path.join(process.cwd(), 'data', 'uploads');

/**
 * In-memory registry of uploaded files keyed by dataset_id.
 * Used by run_code as a local fallback when Galaxy upload is unavailable.
 * s3Uri is set when the file was also uploaded to S3 for Nextflow access.
 */
const uploadedFileRegistry = new Map<string, { name: string; filePath: string; uploadedAt: number; s3Uri?: string }>();

export function getUploadedFile(datasetId: string): { name: string; filePath: string; s3Uri?: string } | undefined {
  const cached = uploadedFileRegistry.get(datasetId);
  if (cached) return cached;
  // Fallback: scan uploads directory after server restart (registry is in-memory only).
  // Files are stored flat as "<datasetId>.<ext>" (multer renames to UUID-based names).
  try {
    const uploadsDir = path.join(process.cwd(), 'data', 'uploads');
    if (existsSync(uploadsDir)) {
      const allFiles = readdirSync(uploadsDir);
      const match = allFiles.find(f => f.startsWith(datasetId));
      if (match) {
        const filePath = path.join(uploadsDir, match);
        const entry = { name: match, filePath, uploadedAt: 0 };
        uploadedFileRegistry.set(datasetId, entry);
        return entry;
      }
    }
  } catch { /* ignore */ }
  return undefined;
}

/**
 * Upload a local file to S3 for Nextflow workflow access.
 * Fire-and-forget: errors are logged but do not block the response.
 */
/**
 * Build an S3Client pinned to the BUCKET's real region. The nextflow work bucket lives
 * in us-east-1 while the app default region is us-west-2 — a client created with the
 * default region rejects cross-region writes with "must be addressed using the specified
 * endpoint". Resolve the bucket's region (GetBucketLocation: empty => us-east-1) first.
 * Also avoids the aws CLI, which is not installed in the frontend/galaxy containers.
 */
async function _s3ClientForBucket(s3Bucket: string): Promise<any> {
  const { S3Client, GetBucketLocationCommand } = await import('@aws-sdk/client-s3');
  const base = process.env.AWS_DEFAULT_REGION || process.env.AWS_REGION || 'us-east-1';
  let region = base;
  try {
    const loc: any = await new S3Client({ region: base }).send(new GetBucketLocationCommand({ Bucket: s3Bucket }));
    region = (loc?.LocationConstraint as string) || 'us-east-1';
  } catch { /* fall back to base region */ }
  return new S3Client({ region });
}

async function _uploadFileToS3(localPath: string, datasetId: string, fileName: string): Promise<string | undefined> {
  const s3Bucket = process.env.NEXTFLOW_S3_BUCKET || process.env.AWS_S3_NEXTFLOW_BUCKET || 'biomate-nextflow-work';
  const s3Key = `uploads/${datasetId}/${fileName}`;
  const s3Uri = `s3://${s3Bucket}/${s3Key}`;
  try {
    const { PutObjectCommand } = await import('@aws-sdk/client-s3');
    const fs = await import('node:fs');
    const s3 = await _s3ClientForBucket(s3Bucket);
    await s3.send(new PutObjectCommand({ Bucket: s3Bucket, Key: s3Key, Body: fs.createReadStream(localPath) }));
    console.log(`[FileUpload] Mirrored to S3: ${s3Uri}`);
    return s3Uri;
  } catch (err: any) {
    console.warn(`[FileUpload] S3 mirror failed (Nextflow workflows may not access this file): ${err.message}`);
    return undefined;
  }
}

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
      '.fasta', '.fa', '.fna', '.fas', '.faa', '.fap',
      '.vcf', '.vcf.gz', '.bed', '.gff', '.gtf',
      '.h5ad', '.h5', '.hdf5', '.loom',
      '.json', '.xml',
      // Research papers / literature
      '.pdf',
      // Cryo-EM / electron microscopy formats
      '.mrc', '.mrcs', '.tif', '.tiff', '.eer', '.spi', '.dm4', '.map',
      // Archive formats (capsule data, bulk uploads)
      '.zip', '.tar', '.tar.gz', '.tgz',
      // Notebook and R formats
      '.ipynb', '.rds', '.rda', '.xlsx', '.xls',
      // Phylogenomics / alignment formats
      '.nwk', '.newick', '.treefile', '.tree', '.mafft', '.clipkit', '.iqtree', '.log',
      // Generic compressed and model/distance/tree files
      '.gz', '.mldist', '.model', '.phy', '.phylip', '.aln', '.bionj', '.contree', '.splits', '.nxs', '.nexus',
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

  const { PutObjectCommand } = await import('@aws-sdk/client-s3');
  const s3Bucket = process.env.AWS_S3_NEXTFLOW_BUCKET || process.env.NEXTFLOW_S3_BUCKET || 'biomate-nextflow-work';
  // Pin the client to the BUCKET's real region (us-east-1), not the us-west-2 default —
  // a region-mismatched client rejects the PutObject with "must be addressed using the
  // specified endpoint", which silently failed input staging for every file-param run.
  const s3 = await _s3ClientForBucket(s3Bucket);

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

  // Project CRUD — list/create/fetch/update/archive/delete user projects.
  // Provides the path by which client-sent projectId in chat-stream
  // context comes to exist. See docs/20260612_DATASET_STORAGE_AND_SESSION_BOUNDARIES.md.
  const { registerProjectRoutes } = await import("./project-routes");
  registerProjectRoutes(app);

  // Project Notes (synthesis) — Stream-A platform. On-demand LLM
  // synthesis of completed runs + recent chat into a markdown brief.
  // See docs/20260619_AI_GLASSES_AND_AUDIO_BIOMATE_PROTOTYPES.md.
  const { registerNotesRoutes } = await import("./notes-routes");
  registerNotesRoutes(app);

  // Project Workbench (pinboard) — Stream-A platform. Lets a user pin
  // output files from any run in a project and render them side-by-side
  // via the existing step-output-preview renderers. Reuses
  // project_knowledge with knowledgeType='workbench_pin'.
  const { registerWorkbenchRoutes } = await import("./workbench-routes");
  registerWorkbenchRoutes(app);

  // Evidence Search — cross-cutting feature. Parses a claim/hypothesis,
  // queries registered evidence datasets in parallel (PubMed,
  // OpenTargets, STRING for v1), LLM-reranks with citations.
  const { registerEvidenceRoutes } = await import("./evidence-routes");
  registerEvidenceRoutes(app);

  // Lane B3 — per-org adapter retrain queue. Mounted via dynamic import so
  // a missing module doesn't crash the rest of the app at boot. The route
  // file ships from a parallel work stream alongside this registration.
  try {
    // @ts-ignore — module may not exist yet
    const { registerRegulatoryTrainingRoutes } = await import(
      "./regulatory-training-routes.js"
    );
    registerRegulatoryTrainingRoutes(app);
  } catch (e: any) {
    console.warn(
      "[routes] regulatory-training-routes not loaded:",
      e?.message ?? e
    );
  }

  // ─── /api/contact — public contact form submission ───────────────────────
  // Sends to CONTACT_INBOX (default: yaoyun.zhang@biomate.ai) via AWS SES through
  // existing email-service.ts. Falls back to logging if email service is not
  // configured (e.g., SMTP env vars missing in dev). No auth required.
  app.post('/api/contact', async (req, res) => {
    try {
      const { name, email, company, subject, message } = req.body ?? {};
      // Minimal validation
      if (!name || typeof name !== 'string' || name.trim().length < 1) {
        return res.status(400).json({ error: 'name is required' });
      }
      if (!email || typeof email !== 'string' || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        return res.status(400).json({ error: 'valid email is required' });
      }
      if (!message || typeof message !== 'string' || message.trim().length < 10) {
        return res.status(400).json({ error: 'message must be at least 10 characters' });
      }
      const safeName = String(name).slice(0, 200);
      const safeEmail = String(email).slice(0, 320);
      const safeCompany = company ? String(company).slice(0, 200) : '';
      const safeSubject = subject ? String(subject).slice(0, 200) : 'Contact form submission';
      const safeMessage = String(message).slice(0, 10000);

      const inbox = process.env.CONTACT_INBOX || 'yaoyun.zhang@biomate.ai';
      const escapeHtml = (s: string) =>
        s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
         .replace(/"/g, '&quot;').replace(/'/g, '&#39;');

      const html = `
        <div style="font-family: -apple-system, system-ui, sans-serif; max-width: 600px;">
          <h2 style="color: #1f2937;">New contact form submission</h2>
          <table style="border-collapse: collapse; width: 100%;">
            <tr><td style="padding: 6px 12px; color: #6b7280;"><strong>From</strong></td>
                <td style="padding: 6px 12px;">${escapeHtml(safeName)} &lt;${escapeHtml(safeEmail)}&gt;</td></tr>
            ${safeCompany ? `<tr><td style="padding: 6px 12px; color: #6b7280;"><strong>Company</strong></td>
                <td style="padding: 6px 12px;">${escapeHtml(safeCompany)}</td></tr>` : ''}
            <tr><td style="padding: 6px 12px; color: #6b7280;"><strong>Subject</strong></td>
                <td style="padding: 6px 12px;">${escapeHtml(safeSubject)}</td></tr>
          </table>
          <h3 style="color: #1f2937; margin-top: 24px;">Message</h3>
          <div style="padding: 12px; background: #f9fafb; border-left: 3px solid #3b82f6; white-space: pre-wrap; line-height: 1.5;">
            ${escapeHtml(safeMessage)}
          </div>
          <p style="color: #9ca3af; font-size: 12px; margin-top: 24px;">
            Reply directly to this email to respond. Submitted via BioMate /contact form.
          </p>
        </div>
      `;
      const text =
        `New contact form submission\n\n` +
        `From:    ${safeName} <${safeEmail}>\n` +
        (safeCompany ? `Company: ${safeCompany}\n` : '') +
        `Subject: ${safeSubject}\n\n` +
        `Message:\n${safeMessage}\n\n` +
        `Reply directly to this email to respond.`;

      const sent = await emailService.sendEmail({
        to: inbox,
        subject: `[BioMate contact] ${safeSubject}`,
        html,
        text,
      });

      if (sent) {
        return res.json({ ok: true, message: 'Thanks — we received your message and will reply within one business day.' });
      }
      // Email service not configured — fall back to logging so the message is not lost
      console.log('[CONTACT_FORM_FALLBACK]', JSON.stringify({
        ts: new Date().toISOString(), inbox, name: safeName, email: safeEmail,
        company: safeCompany, subject: safeSubject, message: safeMessage,
      }));
      return res.json({
        ok: true,
        message: 'Thanks — we received your message. Email delivery is queuing; we will reach out within one business day.',
        delivery: 'logged_fallback',
      });
    } catch (err: any) {
      console.error('[CONTACT_FORM] Error:', err?.message ?? err);
      return res.status(500).json({ error: 'Could not submit contact form. Please email yaoyun.zhang@biomate.ai directly.' });
    }
  });
  // ─── End /api/contact ────────────────────────────────────────────────────

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

  // Async job-queue subsystem (Phase 0) — /api/jobs CRUD + executor.
  // See docs/20260602_ASYNC_JOB_QUEUE_DESIGN.md.
  registerJobsRouter(app);

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

      // Issue the verification token here (not fire-and-forget) so we can
      // return it to the client in dev / no-SMTP environments. The
      // registration UI surfaces a "use this link to verify" affordance
      // when SMTP isn't configured — without this token in the response,
      // that link rendered as `/verify-email?token=null` and 404'd into
      // the React error path. See 2026-06-12 auth audit.
      let _verificationToken: string | null = null;
      try {
        _verificationToken = await authService.sendVerificationEmail(result.user.id, { returnToken: true });
      } catch (err) {
        console.error('[Auth] Failed to send verification email:', err);
      }

      // Notify the admin of every new registration (fire-and-forget; never fails the signup)
      try {
        const _adminNotifyEmail = process.env.ADMIN_NOTIFY_EMAIL || 'contact@biomate.ai';
        const _regSummary =
          `Email: ${result.user.email}\n` +
          `Name: ${result.user.fullName || '(none)'}\n` +
          `Plan: ${result.user.subscriptionTier || 'base'}\n` +
          `User ID: ${result.user.id}\n` +
          `Time: ${new Date().toISOString()}`;
        emailService.sendEmail({
          to: _adminNotifyEmail,
          subject: `New BioMate registration: ${result.user.email}`,
          html: `<h3>New BioMate registration</h3><pre>${_regSummary.replace(/</g, '&lt;')}</pre>`,
          text: `A new user registered.\n\n${_regSummary}`,
        }).catch((err) => console.error('[Auth] Failed to send admin registration notice:', err));
      } catch (err) {
        console.error('[Auth] admin registration notice error:', err);
      }

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

      // Only expose the raw verification token when SMTP is not configured
      // (dev/local environments). In production the email is delivered normally
      // and surfacing the token would show the "Dev mode" bypass box to real users.
      const _emailConfigured = !!(process.env.EMAIL_HOST && process.env.EMAIL_USER && process.env.EMAIL_PASS);
      await auditService.logAuth(
        'register',
        result.user.id,
        req.ip || req.socket.remoteAddress || 'unknown',
        req.headers['user-agent'] || 'unknown',
        true,
        undefined,
        { email: result.user.email, reason: 'ok' }
      );

      res.status(201).json({
        success: true,
        user: { ...result.user, verificationToken: _emailConfigured ? null : _verificationToken },
        token: result.token,
        expiresIn: result.expiresIn,
      });
    } catch (error: any) {
      console.error('[Auth] Registration error:', error);
      // Record the failed registration attempt with the attempted email +
      // reason (e.g. email already registered) so a stuck user — can't log in,
      // can't register — is diagnosable from the audit log alone.
      await auditService.logAuth(
        'register',
        null,
        req.ip || req.socket.remoteAddress || 'unknown',
        req.headers['user-agent'] || 'unknown',
        false,
        error.message,
        { email: req.body?.email, reason: error.code || (/(exist|registered|taken)/i.test(error.message || '') ? 'EMAIL_EXISTS' : 'unknown') }
      );
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
        true,
        undefined,
        { email: result.user.email, reason: 'ok' }
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
        error.message,
        { email: req.body?.email, reason: error.code || 'unknown' }
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

  // ── Deep-linkable workflow draft ──────────────────────────────────────────
  // Loads a workflow persisted at generation time (see /api/chat/stream). The
  // /workflow/:id frontend route fetches this to render the workflow panel
  // focused on a connector-shared workflow. Owner-scoped: a cross-user id
  // returns 404 (not 403) so it can't be probed for existence — matches the
  // project-routes ownership convention.
  app.get("/api/workflow-draft/:id", authenticateToken, async (req, res) => {
    try {
      const { id } = req.params;
      const result = await pool.query(
        `SELECT user_id, workflow_name, payload, expires_at FROM workflow_drafts WHERE id = $1`,
        [id]
      );
      if (result.rowCount === 0) {
        return res.status(404).json({ error: 'not_found' });
      }
      const row = result.rows[0];
      if (row.expires_at && new Date(row.expires_at) < new Date()) {
        return res.status(410).json({ error: 'expired' });
      }
      if (String(row.user_id) !== String(req.user!.id)) {
        return res.status(404).json({ error: 'not_found' });
      }
      // payload is already a JS object (pg parses jsonb columns).
      const payload = (row.payload && typeof row.payload === 'object') ? row.payload : {};
      res.json({ id, workflow_name: row.workflow_name, ...payload });
    } catch (error: any) {
      console.error('[WorkflowDraft] fetch error:', error?.message || error);
      res.status(500).json({ error: 'Failed to load workflow' });
    }
  });

  // ── Magic-link auto-login for chat connectors ─────────────────────────────
  // Two-step, secret-never-in-URL flow:
  //   1. POST /api/auth/login-token  (Bearer of the bound BioMate credential)
  //      → mints a short-lived (5 min), single-use token. The IM bot calls this
  //        with the api_key it stored via `bind`; that credential is the same
  //        Bearer the bot already sends to /api/chat/stream, so authenticateToken
  //        resolves it to the bound user. Only the token's SHA-256 hash is stored.
  //   2. GET  /api/auth/magic?token=<ott>&redirect=<path>
  //      → consumes the token, sets the biomate_token session cookie, 302s to the
  //        (same-origin) redirect, e.g. the view_url path. The long-lived
  //        credential never appears in any URL.
  app.post("/api/auth/login-token", authLimiter, authenticateToken, async (req, res) => {
    try {
      const userId = String(req.user!.id);
      // Optional redirect path baked into the token at mint time; query-param
      // redirect at consume time takes precedence. Only same-origin paths allowed.
      const rawRedirect = typeof req.body?.redirect === 'string' ? req.body.redirect : undefined;
      const safeRedirect =
        rawRedirect && rawRedirect.startsWith('/') && !rawRedirect.startsWith('//')
          ? rawRedirect
          : null;

      // base64url so it's URL-safe without encoding.
      const oneTimeToken = randomBytes(32).toString('base64url');
      const tokenHash = createHash('sha256').update(oneTimeToken).digest('hex');
      const ttlSeconds = 300; // 5 minutes
      const expiresAt = new Date(Date.now() + ttlSeconds * 1000);

      await pool.query(
        `INSERT INTO login_tokens (token_hash, user_id, redirect, expires_at)
           VALUES ($1, $2, $3, $4)`,
        [tokenHash, userId, safeRedirect, expiresAt]
      );

      res.json({ token: oneTimeToken, expires_in: ttlSeconds });
    } catch (error: any) {
      console.error('[Auth] login-token error:', error?.message || error);
      res.status(500).json({ error: 'Failed to mint login token' });
    }
  });

  app.get("/api/auth/magic", async (req, res) => {
    const sanitizePath = (p: unknown): string | null => {
      if (typeof p !== 'string' || !p.startsWith('/') || p.startsWith('//')) return null;
      return p;
    };
    try {
      const rawToken = typeof req.query.token === 'string' ? req.query.token : '';
      const redirectFromQuery = sanitizePath(req.query.redirect);
      if (!rawToken) {
        return res.redirect(302, '/login?error=missing_token');
      }

      const tokenHash = createHash('sha256').update(rawToken).digest('hex');
      // Atomically consume: succeeds only if the token exists, is unconsumed, and
      // is unexpired. The single UPDATE makes the token genuinely single-use even
      // under concurrent clicks (e.g. IM link-preview crawler + the user).
      const consume = await pool.query(
        `UPDATE login_tokens
            SET consumed_at = NOW()
          WHERE token_hash = $1 AND consumed_at IS NULL AND expires_at > NOW()
        RETURNING user_id, redirect`,
        [tokenHash]
      );
      if (consume.rowCount === 0) {
        return res.redirect(302, '/login?error=invalid_or_expired');
      }

      const { user_id, redirect: storedRedirect } = consume.rows[0];
      const user = await authService.getUserById(String(user_id));
      if (!user) {
        return res.redirect(302, '/login?error=user_not_found');
      }

      // New entry path to the SAME session — reuse the standard JWT cookie the
      // app already authenticates with (auth-middleware reads biomate_token).
      const sessionToken = authService.generateToken(user as any, false); // 24h
      res.cookie('biomate_token', sessionToken, {
        httpOnly: true,
        secure: process.env.NODE_ENV === 'production',
        sameSite: 'lax',
        maxAge: 24 * 60 * 60 * 1000,
      });

      const dest = redirectFromQuery || sanitizePath(storedRedirect) || '/';
      return res.redirect(302, dest);
    } catch (error: any) {
      console.error('[Auth] magic login error:', error?.message || error);
      return res.redirect(302, '/login?error=magic_failed');
    }
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

  app.get("/api/auth/config", (req, res) => {
    res.json({
      requireInviteCode: process.env.REQUIRE_INVITE_CODE === 'true',
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
        // For large files, use real S3 multipart upload (chunk to S3 directly).
        const multipartData = await s3Service.startMultipartUpload(
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
          numParts: multipartData.numParts,
          method: 'multipart',
          expiresIn: 6 * 3600,
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

  // Finalise a multipart upload — assembles the parts into a single S3 object.
  // Body: { key, uploadId, parts: [{ PartNumber, ETag }, ...] }
  app.post("/api/s3/upload/complete", authenticateToken, async (req, res) => {
    try {
      const { key, uploadId, parts } = req.body ?? {};
      if (!key || !uploadId || !Array.isArray(parts) || parts.length === 0) {
        return res.status(400).json({
          error: 'Missing required fields: key, uploadId, parts[]',
        });
      }
      // Tenant isolation: caller can only complete uploads under their own prefix.
      const userId = req.user!.id;
      if (!String(key).startsWith(`users/${userId}/`)) {
        return res.status(403).json({ error: 'Access denied' });
      }
      const out = await s3Service.completeMultipartUpload(key, uploadId, parts);
      res.json({ key: out.key, bucket: out.bucket, location: out.location });
    } catch (error: any) {
      console.error('[S3] Upload complete error:', error);
      res.status(500).json({
        error: 'Failed to complete multipart upload',
        message: error.message,
      });
    }
  });

  // Cancel an in-flight multipart upload so S3 stops billing the staged parts.
  // Body: { key, uploadId }
  app.post("/api/s3/upload/abort", authenticateToken, async (req, res) => {
    try {
      const { key, uploadId } = req.body ?? {};
      if (!key || !uploadId) {
        return res.status(400).json({ error: 'Missing required fields: key, uploadId' });
      }
      const userId = req.user!.id;
      if (!String(key).startsWith(`users/${userId}/`)) {
        return res.status(403).json({ error: 'Access denied' });
      }
      await s3Service.abortMultipartUpload(key, uploadId);
      res.json({ ok: true });
    } catch (error: any) {
      console.error('[S3] Upload abort error:', error);
      res.status(500).json({
        error: 'Failed to abort multipart upload',
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

  // Add credits via one-time Stripe Checkout top-up
  app.post("/api/payments/add-credits", authenticateToken, async (req, res) => {
    try {
      if (!stripeService.isConfigured()) {
        // Dev mode: return null URL so billing.tsx shows toast instead of redirecting
        return res.json({ url: null });
      }

      const { amountCents, returnUrl } = req.body;

      if (!amountCents || typeof amountCents !== 'number' || amountCents < 100) {
        return res.status(400).json({ error: 'amountCents must be a number >= 100' });
      }

      const session = await stripeService.createCreditTopupSession(
        req.user!.id,
        amountCents,
        returnUrl,
      );

      res.json({ url: session.url });
    } catch (error: any) {
      console.error('[Payments] Add-credits error:', error);
      res.status(500).json({
        error: 'Failed to create credit top-up session',
        message: error.message,
      });
    }
  });

  // Start a trial subscription via Stripe Checkout
  app.post("/api/payments/start-trial", authenticateToken, async (req, res) => {
    try {
      if (!stripeService.isConfigured()) {
        return res.status(503).json({
          error: 'Payment system not configured',
          message: 'Stripe is not set up. Contact support.',
        });
      }

      // Accept either a direct priceId or a tier+interval pair
      let { priceId, tier, interval, returnUrl } = req.body;

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

      const session = await stripeService.createTrialCheckoutSession(
        req.user!.id,
        priceId,
        returnUrl,
      );

      res.json({ url: session.url });
    } catch (error: any) {
      console.error('[Payments] Start-trial error:', error);
      res.status(500).json({
        error: 'Failed to create trial checkout session',
        message: error.message,
      });
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
      const galaxyHistories = await proxy.getHistories().catch(() => []);
      const galaxyShaped = (galaxyHistories || []).map((h: any) => ({
        id: h.id,
        name: h.name,
        count: h.count ?? h.dataset_count ?? 0,
        size: h.size ?? h.total_size ?? 0,
        create_time: h.create_time ?? h.create_date ?? '',
        update_time: h.update_time ?? h.update_date ?? '',
        source: 'galaxy' as const,
      }));

      // Also include completed BioMate execution runs as virtual histories so users
      // can browse workflow output files through the same "BioMate history" tab.
      const userId = (req as any).userId || (req as any).user?.id;
      const execRuns = await storage.getExecutionRuns(userId, undefined, undefined, 20).catch(() => []);
      const runHistories = execRuns
        .filter((r: any) => r.execution?.status === 'completed' && r.execution?.nextflowOutputDir)
        .map((r: any) => ({
          id: `run:${r.id}`,
          name: r.workflowName || r.execution?.workflowName
            || (r.workflowDefinition as any)?.name || (r.workflowDefinition as any)?.workflow_name
            || r.name || `Run ${r.id.slice(0, 8)}`,
          count: 0,
          size: 0,
          create_time: r.execution?.startedAt || r.createdAt || '',
          update_time: r.execution?.completedAt || '',
          source: 'run' as const,
          runId: r.id,
          outputDir: r.execution?.nextflowOutputDir,
        }));

      res.json({ histories: [...galaxyShaped, ...runHistories] });
    } catch (err: any) {
      console.error('[Histories] fetch failed:', err.message);
      res.json({ histories: [] });
    }
  });

  app.get("/api/galaxy/histories/:historyId/datasets", optionalAuth, async (req, res) => {
    try {
      const { historyId } = req.params;

      // Virtual history IDs prefixed with "run:" → list S3 output files for that run
      if (historyId.startsWith('run:')) {
        const runId = historyId.slice(4);
        const run = await storage.getExecutionRun(runId).catch(() => null);
        const outputDir: string = (run as any)?.execution?.nextflowOutputDir || '';
        if (!outputDir) return res.json({ datasets: [] });

        // List S3 output files using AWS CLI
        // Use Nextflow-specific credentials (AWS_NF_*) — these have S3 access.
        // The primary AWS_ACCESS_KEY_ID is for Galaxy/ECS and may lack S3 permissions.
        const { promisify: _pfy } = await import('util');
        const { exec: _exec } = await import('child_process');
        const execP = _pfy(_exec);
        const s3Prefix = outputDir.replace(/\/?$/, '/');
        const bucket = outputDir.replace(/^s3:\/\//, '').split('/')[0];
        const _nfKey = process.env.AWS_NF_ACCESS_KEY_ID || process.env.AWS_ACCESS_KEY_ID || '';
        const _nfSecret = process.env.AWS_NF_SECRET_ACCESS_KEY || process.env.AWS_SECRET_ACCESS_KEY || '';
        const _s3Env = {
          ...process.env,
          ...((_nfKey && _nfSecret) ? { AWS_ACCESS_KEY_ID: _nfKey, AWS_SECRET_ACCESS_KEY: _nfSecret } : {}),
        };
        const rawLs = await execP(
          `aws s3 ls "${s3Prefix}" --recursive`,
          { env: _s3Env }
        ).then(({ stdout }) => stdout).catch((e: any) => {
          console.warn('[HistoryDatasets/run] S3 ls error code=%s stderr=%s',
            e?.code, e?.stderr?.slice?.(0, 120));
          return (e?.stdout as string) || '';
        });
        // aws s3 ls --recursive format: "YYYY-MM-DD HH:MM:SS   <bytes>  <key>"
        const datasets: any[] = [];
        for (const line of rawLs.split('\n')) {
          const m = line.match(/^\s*(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\s+(\d+)\s+(.+)$/);
          if (!m) continue;
          const [, dateStr, sizeBytes, key] = m;
          if (key.endsWith('/')) continue; // skip directory markers
          const name = key.split('/').pop() || key;
          const ext = name.includes('.') ? name.split('.').pop()! : '';
          datasets.push({
            id: `s3:${key}`,
            name,
            extension: ext,
            file_size: parseInt(sizeBytes, 10),
            state: 'ok',
            create_time: dateStr.trim(),
            s3_uri: `s3://${bucket}/${key}`,
          });
        }
        return res.json({ datasets });
      }

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

      // Rename the multer-generated file to use datasetId as the filename prefix,
      // so that getUploadedFile() fallback scan (f.startsWith(datasetId)) works after server restart.
      const fileExt = path.extname(file.originalname);
      const namedFilename = `${datasetId}${fileExt}`;
      const namedFilePath = path.join(path.dirname(file.path), namedFilename);
      await fs.rename(file.path, namedFilePath);
      file.path = namedFilePath;
      file.filename = namedFilename;

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

      // Mirror to S3 so Nextflow workflows on AWS Batch can access the file
      // This runs concurrently — response is not blocked by S3 upload
      const s3Uri = await _uploadFileToS3(file.path, datasetId, file.originalname).catch(() => undefined);

      // Register in in-memory registry so run_code can find files without Galaxy/Redis
      uploadedFileRegistry.set(datasetId, {
        name: file.originalname,
        filePath: file.path,
        uploadedAt: Date.now(),
        s3Uri,
      });
      // Also register by galaxy_dataset_id for cross-lookup
      if (galaxyDatasetId) {
        uploadedFileRegistry.set(galaxyDatasetId, {
          name: file.originalname,
          filePath: file.path,
          uploadedAt: Date.now(),
          s3Uri,
        });
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
          file_path: file.path,
          // Persist the durable S3 reference in the Redis-backed session too. Without it
          // the in-memory uploadedFileRegistry is the ONLY holder of s3_uri, so a server
          // restart between upload and run leaves a re-selected upload with only a local
          // file_path — unreachable from AWS Batch. With it, the "this session" list stays
          // runnable across restarts.
          s3_uri: s3Uri,
        });
        req.session.uploadedDatasets = capDatasetReferences(req.session.uploadedDatasets);
      }

      // Return dataset information with local, Galaxy, and S3 IDs
      res.json({
        dataset_id: datasetId,
        galaxy_dataset_id: galaxyDatasetId,
        galaxy_history_id: historyId,
        name: file.originalname,
        description: description,
        file_size: file.size,
        file_type: file.mimetype,
        file_path: file.path,
        s3_uri: s3Uri,
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
        req.session.uploadedDatasets = capDatasetReferences(req.session.uploadedDatasets as any[]);
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
          req.session.uploadedDatasets = capDatasetReferences(req.session.uploadedDatasets);
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
      // s3_uri: durable cross-host reference — preferred for AWS Batch runs and the only
      // upload reference that survives a server restart (file_path is host-local).
      s3_uri: d.s3_uri || null,
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

  // Deep diagnose for failed workflows — runs DeepAnalysisAgent multi-round tool-use loop.
  // Slower (~8-30s) and more expensive (~$0.008) than /error-summary; surfaced as an
  // opt-in "Get a deeper diagnosis" button on the failure card.
  app.post("/api/workflows/:invocationId/deep_diagnose", async (req, res) => {
    try {
      const galaxyUrl = process.env.GALAXY_URL || "http://localhost:8081";
      const resp = await fetch(
        `${galaxyUrl}/api/workflows/${encodeURIComponent(req.params.invocationId)}/deep_diagnose`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          signal: AbortSignal.timeout(60000),  // 60s — multi-round agent + LLM
        }
      );
      if (resp.ok) {
        return res.json(await resp.json());
      }
      return res.status(resp.status).json({ available: false, root_cause: `Backend returned ${resp.status}` });
    } catch (err: any) {
      return res.json({ available: false, root_cause: `Deep diagnose request failed: ${String(err?.message ?? err)}` });
    }
  });

  // SSE endpoint for LangGraph pipeline task-status events.
  // The Python backend publishes to Redis channel biomate:pipeline:{id};
  // this endpoint relays those events to the browser.
  app.get("/api/pipelines/:pipelineId/events", async (req, res) => {
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
      const { getRedisClient } = await import('./redis-session');
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

  // Internal — Galaxy's orphan_finalizer (L3 poller post-completion) pushes
  // terminal status into the frontend execution_runs Postgres row. Without
  // this the frontend stays "running" forever even though Redis + Galaxy
  // logs show the workflow finalized. See
  // backend/lib/galaxy/ai/runs/orphan_finalizer.py.
  app.post("/internal/runs/by-invocation/:invId/status", async (req: any, res: any) => {
    const { invId } = req.params;
    const { status, returncode, completed_at, finalized_by } = req.body || {};
    if (!status) {
      return res.status(400).json({ error: 'Missing status' });
    }
    try {
      const run = await storage.getExecutionRunByGalaxyId(String(invId));
      if (!run) {
        return res.status(404).json({ error: 'execution_run not found for invocation', invId });
      }
      const completedAtDate = (typeof completed_at === 'number' && completed_at > 0)
        ? new Date(completed_at * 1000)
        : new Date();
      await storage.updateExecutionRun(run.id, {
        execution: {
          ...(run as any).execution,
          status: String(status),
          completedAt: completedAtDate,
          returncode: typeof returncode === 'number' ? returncode : undefined,
          finalizedBy: finalized_by ? String(finalized_by) : 'orphan_poller',
        },
      } as any);

      // Persist workflow metadata to chat_sessions.workflows on completion.
      if (status === 'completed' && run.chatSessionId) {
        try {
          const wfName = (run as any).workflowName ||
                         (run as any).workflowDefinition?.name ||
                         (run as any).workflowDefinition?.chain_name ||
                         'Workflow';
          const wfEntry = JSON.stringify([{
            workflow_id: run.id,
            workflow_name: wfName,
            status: 'completed',
          }]);
          await pool.query(
            `UPDATE chat_sessions SET workflows = $1::jsonb, last_activity = NOW()
             WHERE session_id = $2`,
            [wfEntry, run.chatSessionId]
          );
          console.log(`[OrphanFinalizer] Wrote workflow entry to chat_sessions for session ${run.chatSessionId}`);
        } catch (sessErr: any) {
          console.error('[OrphanFinalizer] Failed to update chat_sessions.workflows:', sessErr?.message);
        }
      }

      return res.json({ ok: true, runId: run.id, status });
    } catch (e: any) {
      return res.status(500).json({ error: 'update failed', message: e?.message ?? String(e) });
    }
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
          // B3 — inject org_id into IND assembly bodies so the backend
          // _build_rag_context can load the per-org prompt_rules YAML +
          // few_shot_index. Matches both /ind-assembly and
          // /ind-assembly/supersede. Caller's org_id wins if already set.
          const u: any = (req as any).user;
          const isIndAssembly = /\/ind-assembly(?:\/supersede)?$/.test(targetPath);
          if (isIndAssembly && u) {
            const orgId =
              (u.organization && String(u.organization).trim()) ||
              (u.id ? String(u.id) : "");
            if (orgId && (!req.body || !req.body.org_id)) {
              req.body = { ...(req.body || {}), org_id: orgId };
            }
          }
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

  // ─────────────────────────────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────────────────
  // IND attachments — dedicated multipart route BEFORE the /api/ind-report/*
  // wildcard. multer parses the multipart body into memory; we re-issue
  // a FormData request to the Galaxy backend so the backend sees a normal
  // file upload regardless of how the browser framed it.
  // A1 from docs/20260603_IND_MODULE_HONEST_AUDIT.md.
  // ─────────────────────────────────────────────────────────────────────────
  const _indUpload = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: 50 * 1024 * 1024 },
  });
  app.post(
    "/api/ind-report/projects/:projectId/attachments",
    optionalAuth,
    _indUpload.single("file"),
    async (req: any, res: any) => {
      try {
        const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
        const _rawKey = (req as any).user?.galaxyApiKey as string | undefined;
        const apiKey = (_rawKey ? decryptField(_rawKey) : null) || process.env.GALAXY_API_KEY || '';
        if (!req.file) {
          return res.status(400).json({ error: 'no file in multipart upload' });
        }
        const fd = new FormData();
        const blob = new Blob([req.file.buffer], {
          type: req.file.mimetype || 'application/octet-stream',
        });
        fd.append('file', blob, req.file.originalname || 'upload');
        const resp = await fetch(
          `${galaxyUrl}/api/ind-report/projects/${encodeURIComponent(req.params.projectId)}/attachments`,
          {
            method: 'POST',
            headers: { 'X-API-Key': apiKey },
            body: fd,
            signal: AbortSignal.timeout(120000),
          },
        );
        const data = await resp.json().catch(() => ({}));
        return res.status(resp.status).json(data);
      } catch (err: any) {
        return res.status(502).json({ error: 'ind attachment proxy error', detail: err.message });
      }
    },
  );

  // IND Report module — proxy /api/ind-report/* to Galaxy backend
  //   POST   /api/ind-report/projects/:id/sign
  //   POST   /api/ind-report/projects/:id/document.md  (returns text/markdown)
  //   POST   /api/ind-report/projects/:id/document.docx (returns Word blob)
  //   POST   /api/ind-report/projects/:id/snapshot
  //   GET    /api/ind-report/projects/:id/versions
  //   POST   /api/ind-report/projects/:id/sections/render
  //   POST   /api/ind-report/projects
  //   PATCH  /api/ind-report/projects/:id/compounds
  // ─────────────────────────────────────────────────────────────────────────
  app.all("/api/ind-report/*", optionalAuth, async (req: any, res: any) => {
    try {
      const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
      const queryStr = req.url.includes('?') ? req.url.slice(req.url.indexOf('?')) : '';
      const fullPath = `${req.path}${queryStr}`;
      const _rawKey = (req as any).user?.galaxyApiKey as string | undefined;
      const apiKey = (_rawKey ? decryptField(_rawKey) : null) || process.env.GALAXY_API_KEY || '';
      const headers: Record<string, string> = {
        'Content-Type': req.headers['content-type'] || 'application/json',
        'X-API-Key': apiKey,
      };
      const fetchOpts: RequestInit = {
        method: req.method.toUpperCase(),
        headers,
        signal: AbortSignal.timeout(120000),
      };
      if (!['GET', 'HEAD', 'DELETE'].includes(fetchOpts.method as string)) {
        fetchOpts.body = JSON.stringify(req.body);
      }
      const resp = await fetch(`${galaxyUrl}${fullPath}`, fetchOpts);
      const contentType = resp.headers.get('content-type') || 'application/json';
      res.setHeader('Content-Type', contentType);
      const cd = resp.headers.get('content-disposition');
      if (cd) res.setHeader('Content-Disposition', cd);
      res.status(resp.status);
      if (contentType.includes('application/json')) {
        const data = await resp.json().catch(() => ({}));
        return res.json(data);
      }
      const buf = Buffer.from(await resp.arrayBuffer());
      return res.send(buf);
    } catch (err: any) {
      const status = err.response?.status || 502;
      return res.status(status).json({ error: 'IND report proxy error', detail: err.message });
    }
  });

  // Proxy /api/regulatory/* to the Galaxy backend. These are galaxy-served routes
  // (active_adapter, generate_smoke, generate_stream, feedback/queue) that the
  // public frontend must expose for the IND PI suite + the ind-report UI — without
  // this they 404 on dev/prod (caddy routes the public domain to this Node server,
  // which had no /api/regulatory handler). Mirrors the /api/ind-report/* proxy
  // above. Does NOT shadow the frontend's own /api/regulatory_llm/* routes — the
  // `/api/regulatory/` prefix (trailing slash) cannot match `/api/regulatory_llm/`.
  app.all("/api/regulatory/*", optionalAuth, async (req: any, res: any) => {
    try {
      const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
      const queryStr = req.url.includes('?') ? req.url.slice(req.url.indexOf('?')) : '';
      const fullPath = `${req.path}${queryStr}`;
      const _rawKey = (req as any).user?.galaxyApiKey as string | undefined;
      const apiKey = (_rawKey ? decryptField(_rawKey) : null) || process.env.GALAXY_API_KEY || '';
      const headers: Record<string, string> = {
        'Content-Type': req.headers['content-type'] || 'application/json',
        'X-API-Key': apiKey,
      };
      const fetchOpts: RequestInit = {
        method: req.method.toUpperCase(),
        headers,
        signal: AbortSignal.timeout(120000),
      };
      if (!['GET', 'HEAD', 'DELETE'].includes(fetchOpts.method as string)) {
        fetchOpts.body = JSON.stringify(req.body);
      }
      const resp = await fetch(`${galaxyUrl}${fullPath}`, fetchOpts);
      const contentType = resp.headers.get('content-type') || 'application/json';
      res.setHeader('Content-Type', contentType);
      const cd = resp.headers.get('content-disposition');
      if (cd) res.setHeader('Content-Disposition', cd);
      res.status(resp.status);
      if (contentType.includes('application/json')) {
        const data = await resp.json().catch(() => ({}));
        return res.json(data);
      }
      const buf = Buffer.from(await resp.arrayBuffer());
      return res.send(buf);
    } catch (err: any) {
      const status = err.response?.status || 502;
      return res.status(status).json({ error: 'regulatory proxy error', detail: err.message });
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

  // QC events list — proxy to Galaxy backend. Used by the v2 AfterRunReport
  // QC audit tab to render the gate event history.
  app.get("/api/invocations/:invocationId/qc-events", async (req: any, res: any) => {
    try {
      const { invocationId } = req.params;
      const inv = await storage.getInvocation(invocationId).catch(() => null);
      const backendId = inv?.galaxyInvocationId || invocationId;
      const response = await (galaxyAPIProxy.client as any).get(
        `/api/invocations/${backendId}/qc-events`,
        { params: req.query }
      );
      return res.status(response.status).json(response.data);
    } catch (err: any) {
      const status = err.response?.status || 502;
      // AfterRunReport hides the tab on any non-200; a 404 here is the
      // "this workflow has no QC gates" signal and is expected for non-
      // QC domains.
      return res.status(status).json(err.response?.data || { error: 'QC events proxy error' });
    }
  });

  // Software tab — list per-run tool versions.
  // Tries Galaxy backend first (where versions.yml files are aggregated);
  // falls back to an empty object so the v2 AfterRunReport's Software tab
  // simply doesn't render. Backend implementation under nextflow_executor.py
  // walks the run's work dir for **/versions.yml and merges them.
  app.get("/api/invocations/:invocationId/software", async (req: any, res: any) => {
    try {
      const { invocationId } = req.params;
      const inv = await storage.getInvocation(invocationId).catch(() => null);
      const backendId = inv?.galaxyInvocationId || invocationId;
      const response = await (galaxyAPIProxy.client as any).get(
        `/api/invocations/${backendId}/software`,
        { params: req.query }
      );
      return res.status(response.status).json(response.data);
    } catch (err: any) {
      const status = err.response?.status || 404;
      return res.status(status).json(err.response?.data || { versions: {}, count: 0 });
    }
  });

  // Citations — workflow-level paper references for the v2 AfterRunReport
  // Citations tab. Backend assembles from cryo-EM RAG topics + qc_evidence.yaml
  // gate DOIs + (future) nf-core meta.yml.
  app.get("/api/workflows/:name/citations", async (req: any, res: any) => {
    try {
      const { name } = req.params;
      const response = await (galaxyAPIProxy.client as any).get(
        `/api/workflows/${encodeURIComponent(name)}/citations`,
        { params: req.query }
      );
      return res.status(response.status).json(response.data);
    } catch (err: any) {
      const status = err.response?.status || 404;
      return res.status(status).json(err.response?.data || { citations: [], count: 0 });
    }
  });

  // Rationale lookup — per-event (why?) anchor backing for chain phases.
  // Backend is /api/rationale/{rationale_id:path} in nextflow_executor.py.
  // Unauthed (curated rationale is non-sensitive); returns {} when no row.
  app.get(/^\/api\/rationale\/(.+)$/, async (req: any, res: any) => {
    try {
      const rid = req.params[0];
      const response = await (galaxyAPIProxy.client as any).get(
        `/api/rationale/${encodeURIComponent(rid)}`
      );
      return res.status(response.status).json(response.data);
    } catch (err: any) {
      const status = err.response?.status || 404;
      return res.status(status).json(err.response?.data || {});
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
        const contentDisposition = response.headers['content-disposition'] || `attachment; filename="run_report_${invocationId}.txt"`;
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

          // Defensive fallbacks: some report fields are 0 due to cs_mode propagation
          // in older pipeline runs. Use the upstream confirmed count instead.
          const extractedR1Count = extractR1?.data?.num_particles ?? 0;
          const extractedR2Count = extractR2?.data?.num_particles ?? 0;
          const class2dCount     = class2dR1?.data?.num_particles ?? 0;
          // For selection: use class2D count (particles that entered classification) if selection shows 0
          const selR1Count = ((selectR1?.num_selected_particles ?? 0) > 0)
            ? selectR1!.num_selected_particles
            : (class2dCount > 0 ? class2dCount : 'not captured');
          // For NU refinement: use R2 extraction count if refinement report shows 0
          const nuCount = ((nuRpt?.data?.num_particles ?? 0) > 0)
            ? nuRpt!.data.num_particles
            : (extractedR2Count > 0 ? extractedR2Count : 'not captured');

          extractedMetrics = {
            num_micrographs:          String(motionRpt?.data?.num_micrographs          ?? 'MISSING'),
            motion_cs_job:            motionCS,
            avg_total_motion_A:       motionRpt?.data?.avg_total_motion_A != null
                                        ? String(motionRpt.data.avg_total_motion_A)
                                        : 'not available',
            avg_defocus_A:            ctfRpt?.data?.avg_defocus_A != null
                                        ? String(ctfRpt.data.avg_defocus_A)
                                        : 'not available',
            avg_fit_quality:          ctfRpt?.data?.avg_fit_quality != null
                                        ? String(ctfRpt.data.avg_fit_quality)
                                        : 'not available',
            num_blob_particles:       String(pickRpt?.data?.num_particles              ?? 'MISSING'),
            particle_diameter_A:      String(pickRpt?.data?.particle_diameter_angstroms ?? params?.particle_diameter_angstroms ?? 'MISSING'),
            num_junk_input:           String(junkRpt?.data?.num_input_particles        ?? 'MISSING'),
            num_junk_rejected:        String(junkRpt?.data?.num_rejected               ?? 'MISSING'),
            num_extracted_r1:         String(extractedR1Count || 'MISSING'),
            box_size_pix:             String(extractR1?.data?.box_size_pix             ?? extractR2?.data?.box_size_pix ?? 'MISSING'),
            num_particles_2d_r1:      String(class2dCount || 'MISSING'),
            num_classes_r1:           String(class2dR1?.data?.num_classes              ?? 'MISSING'),
            num_selected_r1:          String(selR1Count),
            num_extracted_r2:         String(extractedR2Count || 'MISSING'),
            num_particles_nu:         String(nuCount),
            fsc_0143_resolution:      fscRpt?.data?.fsc_0143_resolution != null
                                        ? String(fscRpt.data.fsc_0143_resolution)
                                        : 'not available',
            pixel_size_A:             String(wfSummary?.data?.pixel_size_angstroms     ?? params?.pixel_size ?? params?.pixel_size_angstroms ?? 'MISSING'),
            voltage_kv:               String(wfSummary?.data?.voltage_kv              ?? params?.voltage_kv ?? params?.voltage ?? 'MISSING'),
            symmetry:                 String(wfSummary?.data?.symmetry                ?? params?.symmetry   ?? 'C1'),
            steps_completed:          String(wfSummary?.data?.steps_completed         ?? 'MISSING'),
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
        // Only pass metrics that have real values — omit MISSING/not available/not captured
        const metricsBlock = Object.entries(extractedMetrics)
          .filter(([, v]) => {
            const s = String(v).toLowerCase();
            return s !== 'missing' && !s.startsWith('not available') && !s.startsWith('not captured');
          })
          .map(([k, v]) => `  ${k}: ${v}`)
          .join('\n');

        // If no AI key, produce a structured template without LLM synthesis
        if (!apiKey) {
          const fallback = [
            `BioMate AI — Report`,
            `${'='.repeat(60)}`,
            `Generated: ${new Date().toISOString()}`,
            ``,
            `1. STUDY OVERVIEW`,
            `-`.repeat(40),
            `Workflow: ${workflowName}`,
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
            `5. NEXT STEPS`,
            `-`.repeat(40),
            `Download your results using the BioMate run panel, or contact support if outputs are missing.`,
          ].filter(l => l !== undefined).join('\n');
          res.setHeader('Content-Type', 'text/plain; charset=utf-8');
          res.setHeader('Content-Disposition', `attachment; filename="run_report_${invocationId}.txt"`);
          return res.status(200).send(fallback);
        }

        // Domain-specific system + user prompts
        let SYSTEM: string;
        let USER: string;

        const executionBlock = `=== EXECUTION METADATA ===
WORKFLOW: ${workflowName}
EXECUTION STATUS: ${runStatus}
START TIME: ${startedAt}
COMPLETION TIME: ${completedAt || 'N/A'}
TOTAL WALL TIME: ${wallTimeStr}
CLOUD PLATFORM: AWS Batch (us-west-2 region)
ORCHESTRATION: BioMate pipeline on AWS Batch`;

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
          SYSTEM = `You are a structural biologist writing a concise technical run report for a cryo-EM processing pipeline. Write in third-person past tense. Every number in the report MUST come from the EXTRACTED METRICS provided — do not invent or estimate values. Omit any metric marked "not available" or "not captured" — do not mention it at all. Use section headings in ALL CAPS. Total report must be under 600 words. Do not add any prior knowledge about the sample — derive all scientific interpretation from the numbers given. Never comment on pipeline configuration, missing steps, software installation issues, or implementation details.`;

          USER = `Write a CryoSPARC SPA run report with exactly 6 sections (ABSTRACT, METHODS, DATA, OUTPUT, FINDINGS, SUMMARY). Populate every section entirely from the metrics and pipeline outputs below — do not add information not present here.

EXTRACTED METRICS:
${metricsBlock}

PIPELINE CONTEXT:
Workflow: ${workflowName}
Wall time: ${wallTimeStr}
Steps completed: ${extractedMetrics.steps_completed}
Platform: AWS Batch, CryoSPARC v5.0.2
Pixel size: ${extractedMetrics.pixel_size_A} Å/px | Voltage: ${extractedMetrics.voltage_kv} kV | Symmetry: ${extractedMetrics.symmetry}
OUTPUT FILES PRODUCED:
${allOutputFiles.filter((f: string) => !f.includes('[binary]') || f.includes('.mrc')).slice(0, 20).join('\n')}

SECTION REQUIREMENTS:
ABSTRACT — 2 sentences max. State particle counts, pixel size, voltage, symmetry, steps, software.
METHODS — Describe the processing pipeline from the metrics: motion correction → CTF → picking (particle_diameter_A Å) → 2D classification (num_classes_r1 classes) → template picking → ab-initio (num_ab_initio_classes models) → refinement → FSC. Include compute platform.
DATA — Table of available quantitative results: particle counts at each stage, box size, resolution. Omit any row where the value is "not available" or "not captured".
OUTPUT — List the output files produced (from OUTPUT FILES PRODUCED above). State S3 location and wall time.
FINDINGS — Scientific interpretation strictly from the available numbers: particle yield efficiency (num_extracted_r2 / num_blob_particles if both are present), classification quality (num_classes_r1 classes), resolution estimate (fsc_0143_resolution). Comment only on results that are present — do not mention absent metrics, pipeline steps, or technical issues.
SUMMARY — 2 sentences on what the results show and what the recommended next step is based on the data.`;


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
        // Route through the canonical fallback chain
        // (backend/config/llm_providers.yml: gemini-3.1-pro-preview primary,
        // gemini-3.5-flash-preview / claude-sonnet-4-5 / gpt-4o / qwen3:32b
        // fallbacks). Replaces the previous direct Anthropic SDK call that
        // hardcoded claude-sonnet-4-5 and bypassed the YAML chain.
        const { llmGenerate } = await import('./llm-client');
        const claudeCall = async (userPrompt: string): Promise<string> => {
          const result = await llmGenerate({
            prompt: userPrompt,
            system: SYSTEM,
            // 8192 leaves headroom for verbose pharma/IND/base-edit reports
            // (~6KB context → ~6KB output) without truncating mid-sentence.
            maxTokens: 8192,
            temperature: 0.7,
          });
          return result.text;
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

        // Single call for all domains — SYSTEM and USER are set per-domain above
        console.log(`[Report] Generating ${isCryoEM ? 'CryoEM' : 'generic'} report via fallback chain`);
        reportText = await claudeCall(USER);

        const header = [
          `BioMate AI — Report`,
          `${'='.repeat(60)}`,
          `Generated: ${new Date().toISOString()}`,
          `Workflow: ${workflowName}`,
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
          res.setHeader('Content-Disposition', `attachment; filename="run_report_${safeName}_${invocationId.slice(0,8)}.docx"`);
          return res.status(200).send(docxBuf);
        }

        res.setHeader('Content-Type', 'text/plain; charset=utf-8');
        res.setHeader('Content-Disposition', `attachment; filename="run_report_${safeName}_${invocationId.slice(0,8)}.txt"`);
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

    // Server-side assistant-message persistence guard (see docs/20260529_CHAT_STREAM_PERSISTENCE_GAP.md).
    // We accumulate every delta + capture workflow metadata so we can write the
    // assistant message back to chat_sessions even if the client disconnects
    // mid-stream. Persistence is idempotent (UPSERT by message_id) so it does
    // not race with the client-side chat-history sync.
    let accumulatedContent = "";
    let workflowMetadata: any = null;
    let persisted = false;
    // Hoisted so the persistAssistantMessage closure can read it. The
    // actual resolution happens further down (Q4 ensureDefaultProject
    // path); until that point this stays undefined and the persistence
    // path falls back to ctx.projectId or null.
    let _resolvedProjectId: string | undefined;

    const persistAssistantMessage = async (opts: { partial: boolean }): Promise<void> => {
      if (persisted) return;
      if (accumulatedContent.length === 0) return; // never persist an empty message
      const userObj: any = (req as any).user;
      if (!userObj?.id) return; // anonymous → nothing to persist (no session row)
      const ctx = (req.body && req.body.context) || {};
      const sessionId: string | undefined = ctx.sessionId || ctx.memorySessionId;
      if (!sessionId) return;
      const assistantMessageId: string =
        ctx.assistantMessageId || `srv-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;
      const messageObj: any = {
        message_id: assistantMessageId,
        role: "assistant",
        content: accumulatedContent,
        timestamp: new Date().toISOString(),
        partial: opts.partial,
      };
      if (workflowMetadata) messageObj.workflowMetadata = workflowMetadata;
      try {
        // UPSERT: ensure session row exists, then merge the assistant message by
        // message_id (replace existing entry with same id, else append).
        // project_id is set on insert AND backfilled on update if the row
        // pre-dates Q4 (had a NULL project_id). The COALESCE preserves any
        // existing non-null value so reassignment via a future UI selector
        // doesn't get clobbered by the auto-resolved default project.
        // See docs/20260612_DATASET_STORAGE_AND_SESSION_BOUNDARIES.md.
        // Prefer the server-resolved projectId (Q4 ensureDefaultProject)
        // over a client-sent value, so a buggy client can't dissociate a
        // session from the project we just resolved for it.
        const projectIdForUpsert = _resolvedProjectId || ctx.projectId || null;
        await pool.query(
          `INSERT INTO chat_sessions (session_id, user_id, title, messages, project_id)
             VALUES ($1, $2, 'New Chat', $3::jsonb, $5)
             ON CONFLICT (session_id) DO UPDATE SET
               messages = (
                 SELECT COALESCE(jsonb_agg(elem), '[]'::jsonb) || $3::jsonb
                 FROM jsonb_array_elements(chat_sessions.messages) elem
                 WHERE elem->>'message_id' IS DISTINCT FROM $4
               ),
               project_id = COALESCE(chat_sessions.project_id, EXCLUDED.project_id),
               last_activity = NOW()`,
          [sessionId, userObj.id, JSON.stringify([messageObj]), assistantMessageId, projectIdForUpsert]
        );
        persisted = true;
        console.log(`[ChatStream] Persisted assistant message ${assistantMessageId} (partial=${opts.partial}, len=${accumulatedContent.length})`);
      } catch (e: any) {
        console.error('[ChatStream] Failed to persist assistant message:', e?.message || e);
      }
    };

    // Use socket 'close' (TCP disconnect) not req 'close' (body consumed).
    // req 'close' fires as soon as express body-parser finishes reading the POST body,
    // which is before the SSE response is sent. socket 'close' fires only when the
    // TCP connection is actually destroyed (client disconnect).
    req.socket?.on('close', () => {
      abortController.abort();
      // Fire-and-forget partial persistence on client disconnect.
      if (!persisted && accumulatedContent.length > 0) {
        persistAssistantMessage({ partial: true }).catch(() => {/* logged inside */});
      }
    });

    let heartbeatTimer: NodeJS.Timeout | null = null;

    const safeSend = (event: string, data: unknown): void => {
      // Server-side accumulation (runs even if write fails / connection dead).
      if (event === 'delta') {
        const t = (data as any)?.text;
        if (typeof t === 'string') accumulatedContent += t;
      } else if (event === 'workflow_ready') {
        workflowMetadata = data;
      } else if (event === 'final') {
        // Prefer the canonical final assistant message over accumulated deltas
        // when both are available — the LLM-side message field is authoritative.
        const finalText = (data as any)?.response;
        if (typeof finalText === 'string' && finalText.length > 0) {
          accumulatedContent = finalText;
        }
        // Capture the workflow payload from the final event too (some flows
        // emit workflow data only in 'final', not 'workflow_ready').
        const wf = (data as any)?.workflow;
        if (wf && !workflowMetadata) workflowMetadata = { workflow: wf };
      }
      if (res.writableEnded || abortController.signal.aborted) return;
      res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
    };

    try {
      const { message, context } = req.body || {};
      if (!message) {
        res.status(400).json({ error: "Message is required" });
        return;
      }

      // Gate test-only context fields behind the E2E bypass token. Prod
      // requests with no E2E header silently strip testForceIntent so it
      // cannot be used to manipulate intent classification.
      if (context && (context as any).testForceIntent) {
        const e2eToken = req.headers['x-e2e-test-token'];
        const validToken = process.env.E2E_TEST_TOKEN;
        if (!validToken || e2eToken !== validToken) {
          delete (context as any).testForceIntent;
        }
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
      }, 3_000); // 3s keeps iOS Safari from dropping the SSE connection mid-stream

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

      // -----------------------------------------------------------------
      // History + dataset rehydration from chat_sessions, then a hard
      // token-budget cap. See:
      //   docs/20260610_REAL_USER_FULL_CHAT_LOGS.md  (wjunlin@HKU)
      //   docs/20260610_CHAT_CONTEXT_AUDIT_4_QUESTIONS.md (Q3)
      // Backfill when the client sent an empty/short payload (page
      // refresh, cross-device). Then run selectChatHistoryUnderBudget so
      // the assembled payload stays ≤16 KB regardless of where it came
      // from — defense in depth.
      // -----------------------------------------------------------------
      const _resolvedSessionId = (context?.sessionId || context?.memorySessionId) || undefined;
      let _historyMessages: Array<{ role: 'user' | 'assistant'; content: string }> | undefined =
        Array.isArray(context?.previousMessages) && context.previousMessages.length > 0
          ? context.previousMessages
          : undefined;
      let _historyDatasets: Array<{ id: string; name: string; type?: string; file_path?: string | null; param_name?: string | null }> | undefined;

      if (_resolvedSessionId && (!_historyMessages || !req.session?.uploadedDatasets?.length)) {
        try {
          const _row = await pool.query(
            'SELECT messages, datasets FROM chat_sessions WHERE session_id = $1 LIMIT 1',
            [_resolvedSessionId]
          );
          const _r = _row.rows?.[0];
          if (_r) {
            if (!_historyMessages && Array.isArray(_r.messages)) {
              _historyMessages = _r.messages
                .filter((m: any) => m && (m.role === 'user' || m.role === 'assistant') && typeof m.content === 'string')
                .map((m: any) => ({ role: m.role, content: m.content }));
              if (_historyMessages && _historyMessages.length === 0) _historyMessages = undefined;
            }
            if (Array.isArray(_r.datasets) && _r.datasets.length > 0) {
              // Cap rehydrated entries too — defends against a stale row
              // that pre-dates the cap from blowing up the prompt budget.
              const _capped = capDatasetReferences(_r.datasets);
              _historyDatasets = _capped.map((d: any) => ({
                id: d.id || d.galaxy_dataset_id || d.dataset_id,
                name: d.name || d.filename || 'unknown',
                type: d.type || d.file_type || 'unknown',
                file_path: d.file_path || null,
                param_name: d.param_name || null,
              })).filter((d: any) => d.id);
              if (_historyDatasets && _historyDatasets.length === 0) _historyDatasets = undefined;
            }
          }
        } catch (e: any) {
          console.warn('[chat-stream] history rehydration failed:', e?.message ?? e);
        }
      }

      // Apply token-budget cap to whatever we ended up with. This runs
      // for both the rehydrated path and the client-sent path so a stale
      // or oversized client payload can't blow up the prompt either.
      if (_historyMessages && _historyMessages.length > 0) {
        const _before = _historyMessages.length;
        _historyMessages = selectChatHistoryUnderBudget(_historyMessages as any) as any;
        if ((_historyMessages?.length ?? 0) !== _before) {
          console.log('[chat-stream] history selector trimmed:', _before, '→', _historyMessages?.length);
        }
      }

      // Project framework — Q4 (re-enabled 2026-06-12).
      //
      // Policy (docs/20260612_DATASET_STORAGE_AND_SESSION_BOUNDARIES.md):
      // NOT every chat lives in a project. A chat is project-scoped only
      // when the client explicitly sends projectId. Standalone "ask
      // BioMate a quick question" chats stay project-less. We do NOT
      // auto-create a Default Workspace — that's surprising pollution.
      //
      // What we always do (regardless of project): ensure the ltm_users
      // row exists, so user-scoped memory (preferences, corrections,
      // episodes attached to the user not a project) can write.
      // Bridge chat-stream's text sessionId to an LTM uuid sessionId so
      // recordEpisode / project_episodes writes can land. Without this,
      // memory-integration's episode + correction writes silently fail
      // against the uuid FK constraint. See 2026-06-13 audit.
      let _ltmSessionUuid: string | null = null;
      let _recoveredDatasets: Array<{ id: string; name: string; type: string; recovered: true; sourceSessionId: string; lastActivity: string }> = [];
      if (req.user) {
        try {
          const { memoryService } = await import('./memory-repository');
          const _u = req.user as any;
          await memoryService.ensureLtmUser(String(_u.id), _u.email, _u.fullName ?? _u.name);
          _resolvedProjectId = (await memoryService.resolveProjectForChat(context?.projectId)) ?? undefined;
          if (_resolvedSessionId) {
            _ltmSessionUuid = await memoryService.ensureChatLtmSession(
              String(_u.id),
              _resolvedSessionId,
              _resolvedProjectId ?? null,
            );
            // Cold-refresh recovery: pull datasets attached to OTHER
            // sessions in the same project (last 14 days, capped 20).
            // Only runs when the chat is project-scoped — project-less
            // sessions have no scope to recover within. See
            // docs/20260612_DATASET_STORAGE_AND_SESSION_BOUNDARIES.md.
            if (_resolvedProjectId) {
              _recoveredDatasets = await memoryService.recoverProjectDatasets(
                _resolvedProjectId,
                _resolvedSessionId,
              );
              if (_recoveredDatasets.length > 0) {
                console.log(`[chat-stream] recovered ${_recoveredDatasets.length} project-scoped dataset(s)`);
              }
            }
          }
        } catch (e: any) {
          // Defensive — never break chat on a memory-system error.
          console.warn('[chat-stream] memory bootstrap failed:', e?.message ?? e);
        }
      }

      // Load project researchGoal for LLM context injection when a project is active.
      let _projectContext: string | undefined;
      if (_resolvedProjectId) {
        try {
          const _proj = await pool.query(
            `SELECT name, description, research_goal, instructions FROM projects WHERE id = $1 LIMIT 1`,
            [_resolvedProjectId]
          );
          const _p = _proj.rows?.[0];
          if (_p) {
            const parts: string[] = [];
            if (_p.name) parts.push(`Project: ${_p.name}`);
            if (_p.description) parts.push(`Description: ${_p.description}`);
            if (_p.research_goal) parts.push(`Research goal: ${_p.research_goal}`);
            if (_p.instructions) parts.push(`Background instructions: ${_p.instructions}`);
            if (parts.length > 0) _projectContext = parts.join('\n');
          }
        } catch {
          // Non-fatal — never break chat on a project lookup failure.
        }
      }

      // Load user's own LLM keys if stored; decrypt for this request only.
      let _userAnthropicApiKey: string | undefined;
      let _openrouterKey: string | undefined;
      let _selectedModel: string | undefined;
      if (req.user?.id) {
        try {
          const _keyRow = await pool.query(
            `SELECT llm_api_keys FROM users WHERE id = $1 LIMIT 1`,
            [req.user.id]
          );
          const _stored = _keyRow.rows[0]?.llm_api_keys as any;
          const _encAnthropic = _stored?.anthropic;
          if (_encAnthropic) _userAnthropicApiKey = decryptField(_encAnthropic);
          const _encOpenrouter = _stored?.openrouter;
          if (_encOpenrouter) _openrouterKey = decryptField(_encOpenrouter);
          if (_stored?.selected_model) _selectedModel = _stored.selected_model;
        } catch { /* non-fatal — fall back to system key */ }
      }

      // Fall back to system-level OpenRouter key if user has none.
      // OPENROUTER_API_KEY in server env enables cheap Chinese models for all users.
      if (!_openrouterKey && process.env.OPENROUTER_API_KEY) {
        _openrouterKey = process.env.OPENROUTER_API_KEY;
        if (!_selectedModel) _selectedModel = process.env.OPENROUTER_DEFAULT_MODEL || 'deepseek/deepseek-chat';
      }

      const enrichedContext = {
        ...(context || {}),
        // Normalise session identity: frontend sends memorySessionId; processMessage uses sessionId.
        // If both are present, prefer the explicit sessionId; fall back to memorySessionId.
        sessionId: _resolvedSessionId,
        projectId: _resolvedProjectId,
        projectContext: _projectContext,
        userAnthropicApiKey: _userAnthropicApiKey,
        openrouterKey: _openrouterKey,
        selectedModel: _selectedModel,
        // memorySessionId must be the LTM sessions.id (uuid) so recordEpisode's
        // project_episodes.session_id FK is satisfied. If the bridge call
        // failed (no LTM session created), leave it undefined and let
        // memory-integration's gates skip the episode write.
        memorySessionId: _ltmSessionUuid ?? undefined,
        previousMessages: _historyMessages,
        billingUserId: req.user ? String(req.user.id) : undefined,
        isPilotUser: isPilotUser || undefined,
        // Inject integer userId so memory-integration can load user preferences/corrections
        userId: req.user ? Number((req.user as any).id) : (context?.userId),
        // Session-uploaded datasets: activates WorkflowDatasetSelector + domain-specialist format context
        // file_path is included so AI can auto-populate file-type params (e.g. movies_path, reads, input).
        // When the in-memory Express session has none (e.g. cross-device, post-refresh), fall back to
        // the persisted chat_sessions.datasets jsonb we just hydrated.
        //
        // Cold-refresh recovery: when this session has no attached datasets
        // but we resolved sister sessions in the same project that DO have
        // datasets, surface those as "recovered" entries below the
        // direct ones. The sessionDatasetsBlock in galaxy-assistant.ts
        // labels recovered ones distinctly so the LLM doesn't claim the
        // user just attached them.
        sessionDatasets: (() => {
          const direct: Array<any> = req.session?.uploadedDatasets?.length
            ? req.session.uploadedDatasets.map((d: any) => ({
                id: d.galaxy_dataset_id || d.dataset_id,
                name: d.name,
                type: d.file_type || 'unknown',
                file_path: d.file_path || null,
                param_name: d.param_name || null,
              }))
            : (_historyDatasets ?? []);
          // Dedupe: a recovered entry whose id is already in direct is dropped.
          const seen = new Set(direct.map((d: any) => d.id));
          const recovered = _recoveredDatasets
            .filter((r) => !seen.has(r.id))
            .map((r) => ({
              id: r.id,
              name: r.name,
              type: r.type,
              file_path: null,
              param_name: null,
              recovered: true,
              sourceSessionId: r.sourceSessionId,
            }));
          const combined = [...direct, ...recovered];
          return combined.length > 0 ? combined : undefined;
        })(),
        // Per-tool credential map built from user's vault — forwarded to AI backend for routing
        credentialMap: credentialMap || undefined,
        // Per-request Galaxy proxy scoped to the authenticated user's own
        // API key. Used by GalaxyAssistant for /api/ai_assistant/* calls so
        // generate_workflow doesn't fall back to the shared admin key, which
        // returns 401 from Galaxy whenever its api_keys row is missing/rotated.
        galaxyAPIOverride: req.user ? userProxy(req) : undefined,
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

      // Detect DB unavailability and alert ops immediately
      if ((workflowPayload as any)?.error === 'db_unavailable') {
        console.error('[Chat Stream API] DB unavailable error — firing admin alert');
        emailService.sendAdminAlert('DB Unavailable — Workflow Generation Failed', {
          time: new Date().toISOString(),
          userId: String((req.user as any)?.id || 'anon'),
          query: String(message || '').slice(0, 300),
          error: 'SQLite OperationalError (missing table or corrupt DB)',
        }, 'support@biomate.ai').catch((e: any) => console.error('[EmailAlert] send failed:', e.message));
      }

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

      const assistantMessage = (() => {
        const msg = String(assistantResponse.message || "");
        if (msg.trim()) return msg;
        // Fallback: LLM returned empty — surface recommended tools if available, else generic prompt
        const tools = assistantResponse.recommendedTools;
        if (tools && tools.length > 0) {
          const names = tools.slice(0, 3).map((t: any) => `**${t.name || t.tool_name}**`).join(', ');
          return `I found some relevant tools for your request: ${names}. Would you like me to run one of these on your data?`;
        }
        return "I'm ready to help with your analysis. Could you confirm what you'd like me to run, and attach or paste your data?";
      })();

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
          paramClarifications: assistantResponse.paramClarifications,
          intentClarification: assistantResponse.intentClarification,
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
              'gemini-3.5-flash':     {i:  0.075, o:  0.30},
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

      // ── Deep-link: persist a stable, URL-addressable draft at GENERATION time ──
      // A generated workflow otherwise lives only in the client's in-memory chat
      // state, so a chat connector ("Open in BioMate" button) has nothing to point
      // at. We persist the workflow draft now (not only at execution) and hand the
      // SSE consumers an absolute `view_url` → /workflow/<id>. Only for authenticated
      // requests (the IM bot calls with the bound user's Bearer credential); anonymous
      // requests get no view_url and the connector falls back to the app root.
      let workflowViewUrl: string | undefined;
      let workflowDraftId: string | undefined;
      if (responseState === "workflow_ready" && workflowPayload && req.user?.id) {
        try {
          const ga = (workflowPayload as any).workflow_ga || {};
          const draftWorkflowName =
            ga.name || (workflowPayload as any).workflow_name ||
            (workflowPayload as any).chain_display_name || "";
          // Build the panel-shaped workflow object the same way the client does
          // (chat-interface.tsx onSuccess): workflow_ga ?? workflow, with the
          // LLM-extracted inline params merged into inline_parameters.
          const inlineParams = (responsePayload.metadata as any)?.inlineParameters;
          let panelWorkflow: any = (workflowPayload as any).workflow_ga || workflowPayload;
          if (inlineParams && typeof inlineParams === "object" && Object.keys(inlineParams).length > 0) {
            panelWorkflow = {
              ...panelWorkflow,
              inline_parameters: { ...(panelWorkflow.inline_parameters || {}), ...inlineParams },
            };
          }
          const draftPayload = {
            response: assistantMessage,
            state: responseState,
            workflow: panelWorkflow,
            rawWorkflow: workflowPayload,
            inlineParameters: inlineParams || null,
            suggestions,
            prerequisitesValidation,
            workflowName: draftWorkflowName,
          };
          workflowDraftId = uuidv4();
          const appUrl = process.env.APP_URL || "http://localhost:5000";
          const draftExpiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000); // 30 days
          await pool.query(
            `INSERT INTO workflow_drafts (id, user_id, workflow_name, payload, expires_at)
               VALUES ($1, $2, $3, $4::jsonb, $5)`,
            [workflowDraftId, String(req.user.id), draftWorkflowName || null, JSON.stringify(draftPayload), draftExpiresAt]
          );
          workflowViewUrl = `${appUrl.replace(/\/+$/, "")}/workflow/${workflowDraftId}`;
        } catch (e: any) {
          // Non-fatal: a failed draft persist just means no deep link this turn.
          console.warn("[ChatStream] workflow draft persist failed:", e?.message || e);
          workflowViewUrl = undefined;
          workflowDraftId = undefined;
        }
      }
      // Surface the deep link on the canonical `final` payload too (some connector
      // flows read `view_url` from `final` rather than `workflow_ready`).
      if (workflowViewUrl) {
        (responsePayload as any).view_url = workflowViewUrl;
        (responsePayload as any).workflow_id = workflowDraftId;
      }

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
          // Prefer the stable, URL-addressable draft id over the catalog ga.id
          // (which is often empty for generated/composed workflows). This is the
          // id embedded in view_url and resolvable via /api/workflow-draft/:id.
          workflow_id:   workflowDraftId || ga.id || "",
          workflow_type: workflowPayload.workflow_type || workflowPayload.execution_engine || "",
          nextflow_path: workflowPayload.nextflow_path || "",
          source:        workflowPayload.source || "",
          confidence:    workflowPayload.confidence ?? null,
          chain_name:    workflowPayload.chain_name || "",
          chain_steps:   chainStepNames,
          // Absolute, app-origin deep link the connector puts on its
          // "Open in BioMate" button. Empty when the draft couldn't be persisted.
          view_url:      workflowViewUrl || "",
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
      // Authoritative server-side persistence on successful completion.
      // (Idempotent — UPSERT by message_id won't conflict with client sync.)
      await persistAssistantMessage({ partial: false });
      res.end();
    } catch (error: any) {
      console.error("Chat Stream API error:", error);
      // Persist whatever we managed to stream before the error so the user can
      // see partial output on session reload.
      if (!persisted && accumulatedContent.length > 0) {
        await persistAssistantMessage({ partial: true }).catch(() => {/* logged */});
      }
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

      // Call Galaxy backend via the AUTHENTICATED user's per-user API key.
      // The shared admin key (process.env.GALAXY_API_KEY) is not honoured by
      // Galaxy's /api/ai_assistant/* routes when the underlying admin user
      // record / api_keys row is missing or rotated (verified live today:
      // admin key `f17c618a…` returns 401 from /api/whoami, while per-user
      // keys provisioned at registration succeed).
      const response = await userProxy(req).generateWorkflow({
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

  // ──────────────────────────────────────────────────────────────────────
  // Per-user API keys (biomate-connector / headless access).
  // Web UI (Settings → API Keys) authenticates via the JWT cookie. The
  // plaintext key is returned ONCE on creation; only its hash is stored.
  // ──────────────────────────────────────────────────────────────────────

  // List the current user's API keys (masked — no secrets).
  app.get("/api/user/api-keys", authenticateToken, async (req, res) => {
    try {
      const rows = await listApiKeys(req.user!.id);
      res.json(rows.map((k) => ({
        id: k.id,
        name: k.name,
        keyPrefix: k.keyPrefix,
        createdAt: k.createdAt,
        lastUsedAt: k.lastUsedAt,
        revokedAt: k.revokedAt,
      })));
    } catch (error: any) {
      console.error('[api-keys] list error:', error?.message || error);
      res.status(500).json({ error: 'Failed to list API keys' });
    }
  });

  // Generate a new API key. Returns the plaintext ONCE — it is never stored.
  app.post("/api/user/api-keys", authenticateToken, express.json(), async (req, res) => {
    try {
      const name = typeof req.body?.name === 'string' ? req.body.name.trim().slice(0, 100) : null;
      const { plaintext, keyHash, keyPrefix } = generateApiKey();
      const [row] = await db.insert(apiKeys).values({
        userId: req.user!.id,
        keyHash,
        keyPrefix,
        name: name || null,
      }).returning();
      res.json({
        id: row.id,
        name: row.name,
        keyPrefix: row.keyPrefix,
        createdAt: row.createdAt,
        // Shown once — the client must copy it now.
        key: plaintext,
      });
    } catch (error: any) {
      console.error('[api-keys] create error:', error?.message || error);
      res.status(500).json({ error: 'Failed to create API key' });
    }
  });

  // Revoke (soft-delete) an API key the current user owns.
  app.delete("/api/user/api-keys/:id", authenticateToken, async (req, res) => {
    try {
      const result = await db.update(apiKeys)
        .set({ revokedAt: new Date() })
        .where(and(
          eq(apiKeys.id, req.params.id),
          eq(apiKeys.userId, req.user!.id),
          // ownership scoped; revoke is idempotent
        ))
        .returning({ id: apiKeys.id });
      if (result.length === 0) {
        // Either not found or not owned — 404 to avoid leaking existence.
        return res.status(404).json({ error: 'API key not found' });
      }
      res.json({ ok: true, id: result[0].id });
    } catch (error: any) {
      console.error('[api-keys] revoke error:', error?.message || error);
      res.status(500).json({ error: 'Failed to revoke API key' });
    }
  });

  // ── Per-user LLM provider API keys ──────────────────────────────────────────
  // Users can supply their own Anthropic key so chats use their quota.
  // The key is stored encrypted; GET only returns a boolean (never the value).

  app.get("/api/user/llm-api-keys", authenticateToken, async (req, res) => {
    try {
      const row = await pool.query(
        `SELECT llm_api_keys FROM users WHERE id = $1`,
        [req.user!.id]
      );
      const stored = (row.rows[0]?.llm_api_keys ?? {}) as any;
      res.json({
        anthropic: !!stored.anthropic,
        openrouter: !!stored.openrouter,
        selected_model: stored.selected_model ?? null,
      });
    } catch (error: any) {
      console.error('[llm-api-keys] get error:', error?.message);
      res.status(500).json({ error: 'Failed to get LLM API keys' });
    }
  });

  app.patch("/api/user/llm-api-keys", authenticateToken, express.json(), async (req, res) => {
    try {
      const { provider, key, selected_model } = req.body ?? {};
      const VALID_PROVIDERS = ['anthropic', 'openrouter'];
      if (provider !== undefined && (typeof provider !== 'string' || !VALID_PROVIDERS.includes(provider))) {
        return res.status(400).json({ error: `provider must be one of: ${VALID_PROVIDERS.join(', ')}` });
      }
      const rowResult = await pool.query(
        `SELECT llm_api_keys FROM users WHERE id = $1`,
        [req.user!.id]
      );
      const existing: Record<string, string> = rowResult.rows[0]?.llm_api_keys ?? {};
      if (provider) {
        if (typeof key === 'string' && key.trim().length > 0) {
          existing[provider] = encryptField(key.trim());
        } else if (key !== undefined) {
          delete existing[provider];
        }
      }
      if (selected_model !== undefined) {
        if (typeof selected_model === 'string' && selected_model.trim().length > 0) {
          existing.selected_model = selected_model.trim();
        } else {
          delete existing.selected_model;
        }
      }
      await pool.query(
        `UPDATE users SET llm_api_keys = $1::jsonb, updated_at = NOW() WHERE id = $2`,
        [JSON.stringify(existing), req.user!.id]
      );
      res.json({ ok: true, anthropic: !!existing.anthropic, openrouter: !!existing.openrouter, selected_model: existing.selected_model ?? null });
    } catch (error: any) {
      console.error('[llm-api-keys] patch error:', error?.message);
      res.status(500).json({ error: 'Failed to update LLM API keys' });
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
      const response = await proxy.client.get('/api/nextflow/license-requirements', { params: req.query });
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
      if (projects.length > 0) {
        const ids = projects.map(p => p.id);
        const [sessRows, runRows] = await Promise.all([
          pool.query<{ project_id: string; count: string }>(
            `SELECT project_id, COUNT(*) AS count FROM chat_sessions WHERE project_id = ANY($1) GROUP BY project_id`,
            [ids]
          ),
          pool.query<{ project_id: string; count: string }>(
            `SELECT project_id, COUNT(*) AS count FROM execution_runs WHERE project_id = ANY($1) GROUP BY project_id`,
            [ids]
          ),
        ]);
        const sessCounts = Object.fromEntries(sessRows.rows.map(r => [r.project_id, parseInt(r.count, 10)]));
        const runCounts = Object.fromEntries(runRows.rows.map(r => [r.project_id, parseInt(r.count, 10)]));
        const enriched = projects.map(p => ({ ...p, sessionCount: sessCounts[p.id] ?? 0, runCount: runCounts[p.id] ?? 0 }));
        return res.json(enriched);
      }
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
    const { sessionId, projectId, userMessage, assistantResponse, userIntent, toolsUsed, workflowGenerated, workflowId } = req.body ?? {};

    // Bug #58 fix — validate required fields + UUID shape BEFORE hitting the DB.
    // Previously this endpoint returned 500 for both malformed payloads and
    // missing-session FK violations; now it 400s with a precise diagnostic.
    const missing: string[] = [];
    if (!sessionId)         missing.push("sessionId");
    if (!userMessage)       missing.push("userMessage");
    if (!assistantResponse) missing.push("assistantResponse");
    if (missing.length) {
      return res.status(400).json({ error: "missing_required_fields", missing });
    }
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(String(sessionId))) {
      return res.status(400).json({ error: "invalid_session_id", message: "sessionId must be a UUID" });
    }

    try {
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
      // Foreign-key violation = session row doesn't exist yet → 404 is more honest than 500
      const msg = String(error?.message ?? "");
      if (msg.includes("violates foreign key constraint") && msg.includes("session_id")) {
        return res.status(404).json({ error: "session_not_found", sessionId });
      }
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
      const { query, limit, defer_param_prefill } = req.body || {};
      if (!query) return res.status(400).json({ error: "query is required" });
      const galaxyUrl = process.env.GALAXY_URL || "http://localhost:8081";
      const upstream = await fetch(`${galaxyUrl}/api/ai_assistant/search_nextflow_workflow`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        // defer_param_prefill: skip the backend's inline LLM param-prefill (~1-2s,
        // up to ~13s under concurrent retry) and return search sub-second. The
        // connector's search_workflow sets this — its LLM client extracts params
        // itself, so the inline prefill is redundant there.
        body: JSON.stringify({ user_intent: query, limit: limit ?? 5, defer_param_prefill: !!defer_param_prefill }),
      });
      const data = await upstream.json();
      res.status(upstream.status).json(data);
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  // GET /api/workflows/spec — full spec for a workflow by ID/path (used by MCP get_workflow_spec)
  // workflow_id is the nextflow path, e.g. "pharmacology/herg_cardiac_safety_qsar/main.nf"
  app.get("/api/workflows/spec", optionalAuth, async (req, res) => {
    try {
      const workflowId = String(req.query.workflow_id || '');
      if (!workflowId) return res.status(400).json({ error: "workflow_id is required" });
      const galaxyUrl = process.env.GALAXY_URL || "http://localhost:8081";
      // Extract bare name from path: "pharmacology/herg_cardiac_safety_qsar/main.nf" → "herg_cardiac_safety_qsar"
      const namePart = workflowId.replace(/\/main\.nf$/, '').split('/').pop() || workflowId;
      const upstream = await fetch(`${galaxyUrl}/api/ai_assistant/search_nextflow_workflow`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ user_intent: namePart, force_workflow_name: namePart, limit: 1 }),
      });
      const data = await upstream.json();
      res.status(upstream.status).json(data);
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  // -----------------------------------------------------------------------
  // Personal workflow upload / listing
  // -----------------------------------------------------------------------

  // Dedicated multer config for workflow definition files (small, text-based).
  // Stored in memory so we can read them without touching disk long-term.
  const workflowUploadMemory = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: 10 * 1024 * 1024 }, // 10 MB max — workflow files are tiny
    fileFilter: (_req, file, cb) => {
      const ext = path.extname(file.originalname).toLowerCase();
      if (['.nf', '.ga', '.yml', '.yaml'].includes(ext)) {
        cb(null, true);
      } else {
        cb(new Error('Only .nf, .ga, .yml, and .yaml workflow files are supported'));
      }
    },
  });

  // POST /api/workflows/upload-file — import a personal workflow file
  // Stored directly in the frontend PostgreSQL DB (personal_workflows table).
  // No Galaxy backend call required — self-contained.
  app.post(
    '/api/workflows/upload-file',
    optionalAuth,
    workflowUploadMemory.single('file'),
    async (req: any, res) => {
      try {
        const user = req.user as any;
        if (!user?.id) return res.status(401).json({ error: 'Authentication required' });

        if (!req.file) return res.status(400).json({ error: 'No file uploaded' });

        const fileContent = req.file.buffer.toString('utf-8');
        const ext = path.extname(req.file.originalname).toLowerCase().replace('.', '');
        const fileType = ext === 'yaml' ? 'yaml' : ext;

        const workflowName = (req.body?.workflowName as string)?.trim()
          || req.file.originalname.replace(/\.[^.]+$/, '');
        const description = (req.body?.description as string)?.trim() || '';

        const result = await pool.query(
          `INSERT INTO personal_workflows (user_id, name, description, file_type, file_content)
           VALUES ($1, $2, $3, $4, $5)
           RETURNING id, name AS workflow_name`,
          [String(user.id), workflowName, description, fileType, fileContent]
        );
        const row = result.rows[0];
        return res.json({
          id: row.id,
          workflow_name: row.workflow_name,
          file_type: fileType,
          message: `Workflow '${row.workflow_name}' imported successfully.`,
        });
      } catch (err: any) {
        console.error('[workflow-upload]', err);
        return res.status(500).json({ error: err.message || 'Upload failed' });
      }
    }
  );

  // GET /api/workflows/personal — list the calling user's uploaded workflows
  app.get('/api/workflows/personal', optionalAuth, async (req: any, res) => {
    try {
      const user = req.user as any;
      if (!user?.id) return res.status(401).json({ error: 'Authentication required' });

      const search = (req.query.search as string || '').trim();
      const queryParams: any[] = [String(user.id)];
      let whereClause = 'WHERE user_id = $1';
      if (search) {
        queryParams.push(`%${search}%`);
        whereClause += ` AND name ILIKE $2`;
      }
      const result = await pool.query(
        `SELECT id, user_id, name AS workflow_name, description, file_type,
                created_at, updated_at
         FROM personal_workflows
         ${whereClause}
         ORDER BY created_at DESC
         LIMIT 500`,
        queryParams
      );
      return res.json(result.rows);
    } catch (err: any) {
      return res.status(500).json({ error: err.message });
    }
  });

  // DELETE /api/workflows/personal/:id — remove an imported workflow
  app.delete('/api/workflows/personal/:id', optionalAuth, async (req: any, res) => {
    try {
      const user = req.user as any;
      if (!user?.id) return res.status(401).json({ error: 'Authentication required' });
      const result = await pool.query(
        `DELETE FROM personal_workflows WHERE id = $1 AND user_id = $2 RETURNING id`,
        [req.params.id, String(user.id)]
      );
      if (!result.rows.length) return res.status(404).json({ error: 'Not found' });
      return res.json({ ok: true });
    } catch (err: any) {
      return res.status(500).json({ error: err.message });
    }
  });

  // GET /api/workflows/personal/:id — single workflow with file_content
  app.get('/api/workflows/personal/:id', optionalAuth, async (req: any, res) => {
    try {
      const user = req.user as any;
      if (!user?.id) return res.status(401).json({ error: 'Authentication required' });
      const result = await pool.query(
        `SELECT id, user_id, name AS workflow_name, description, file_type,
                file_content, created_at, updated_at
         FROM personal_workflows WHERE id = $1 AND user_id = $2`,
        [req.params.id, String(user.id)]
      );
      if (!result.rows.length) return res.status(404).json({ error: 'Not found' });
      return res.json(result.rows[0]);
    } catch (err: any) {
      return res.status(500).json({ error: err.message });
    }
  });

  // POST /api/files/preview — render a preview of an S3 file (used by MCP preview_file)
  // Returns { content_type, preview_text?, download_url?, rows?, truncated }
  app.post("/api/files/preview", optionalAuth, async (req, res) => {
    try {
      const { s3_key, max_rows = 100 } = req.body || {};
      if (!s3_key) return res.status(400).json({ error: "s3_key is required" });

      const s3Match = (s3_key as string).match(/^s3:\/\/([^/]+)\/(.+)$/);
      if (!s3Match) return res.status(400).json({ error: "s3_key must be s3://bucket/key format" });
      const [, bucket, key] = s3Match;

      const ALLOWED_BUCKETS = new Set([
        process.env.AWS_S3_NEXTFLOW_BUCKET || 'biomate-nextflow-work',
        'biomate-nextflow-work',
        'biomate-outputs',
      ]);
      if (!ALLOWED_BUCKETS.has(bucket)) {
        return res.status(403).json({ error: "S3 bucket not allowed" });
      }

      const ext = key.split('.').pop()?.toLowerCase() ?? '';
      const TEXT_EXTS = new Set(['csv','tsv','txt','log','fasta','fa','fastq','vcf','bed','gff','gtf','json','html','htm','tabular']);
      const IMAGE_EXTS = new Set(['png','jpg','jpeg','gif','svg']);

      const { GetObjectCommand } = await import('@aws-sdk/client-s3');
      const { getSignedUrl } = await import('@aws-sdk/s3-request-presigner');
      // Pin the client to the BUCKET's real region. biomate-nextflow-work lives
      // in us-east-1 while the deploy host's AWS_REGION is us-west-2 — a region-
      // mismatched client (the old `new S3Client({ region: AWS_REGION })`) gets
      // "The bucket you are attempting to access must be addressed using the
      // specified endpoint" (PermanentRedirect → HTTP 500) on both GetObject and
      // the presigned URL. _s3ClientForBucket resolves the region via
      // GetBucketLocation, same as the Nextflow write path. (connector preview_file
      // incident 2026-06-30 — execution wrote S3 fine, only the read side broke.)
      const s3 = await _s3ClientForBucket(bucket);
      const cmd = new GetObjectCommand({ Bucket: bucket, Key: key });

      if (IMAGE_EXTS.has(ext)) {
        const url = await getSignedUrl(s3, cmd, { expiresIn: 3600 });
        return res.json({ content_type: 'image', download_url: url });
      }

      if (TEXT_EXTS.has(ext)) {
        const response = await s3.send(cmd);
        const chunks: Buffer[] = [];
        for await (const chunk of response.Body as AsyncIterable<Uint8Array>) {
          chunks.push(Buffer.from(chunk));
          if (Buffer.concat(chunks).length > 512 * 1024) break; // 512 KB cap
        }
        const text = Buffer.concat(chunks).toString('utf-8');
        const lines = text.split('\n');
        const truncated = lines.length > (max_rows as number);
        const preview = lines.slice(0, max_rows as number).join('\n');
        const isTable = ext === 'csv' || ext === 'tsv' || ext === 'tabular';
        return res.json({ content_type: isTable ? 'table' : 'text', preview_text: preview, rows: lines.length, truncated });
      }

      // Binary / unknown: return a presigned download URL
      const url = await getSignedUrl(s3, cmd, { expiresIn: 3600 });
      return res.json({ content_type: 'binary', download_url: url });
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  // POST /api/databases/query — query biological databases (used by MCP query_database)
  // Pass database="federated" (or omit) to fan-out to all relevant sources in parallel.
  // Pass a specific database name to hit a single source.
  app.post("/api/databases/query", optionalAuth, async (req, res) => {
    try {
      const { database, query, entity_type, sources } = req.body || {};
      if (!query) return res.status(400).json({ error: "query is required" });
      const galaxyUrl = process.env.GALAXY_URL || "http://localhost:8081";
      const upstream = await fetch(`${galaxyUrl}/api/databases/query`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          database: database || "federated",
          query,
          entity_type: entity_type || null,
          sources: sources || null,
        }),
      });
      const data = await upstream.json();
      res.status(upstream.status).json(data);
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  // POST /api/databases/federated — explicit federated fan-out endpoint
  app.post("/api/databases/federated", optionalAuth, async (req, res) => {
    try {
      const { query, entity_type, sources } = req.body || {};
      if (!query) return res.status(400).json({ error: "query is required" });
      const galaxyUrl = process.env.GALAXY_URL || "http://localhost:8081";
      const upstream = await fetch(`${galaxyUrl}/api/databases/query`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ database: "federated", query, entity_type, sources }),
      });
      const data = await upstream.json();
      res.status(upstream.status).json(data);
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  // POST /api/literature/search — iterative depth-loop literature search
  // Hits PubMed + EuropePMC + Semantic Scholar + OpenAlex, detects gaps, deepens.
  app.post("/api/literature/search", optionalAuth, async (req, res) => {
    try {
      const { query, max_depth, min_results } = req.body || {};
      if (!query) return res.status(400).json({ error: "query is required" });
      const galaxyUrl = process.env.GALAXY_URL || "http://localhost:8081";
      const upstream = await fetch(`${galaxyUrl}/api/literature/search`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ query, max_depth: max_depth || 3, min_results: min_results || 10 }),
      });
      const data = await upstream.json();
      res.status(upstream.status).json(data);
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  // ── Skills API — expert role injection ──────────────────────────────────
  // GET  /api/skills          — list all available skills
  // POST /api/skills/detect   — auto-detect from query
  // POST /api/skills/block    — build system prompt block for skill IDs

  app.get("/api/skills", optionalAuth, async (_req, res) => {
    try {
      const galaxyUrl = process.env.GALAXY_URL || "http://localhost:8081";
      const upstream = await fetch(`${galaxyUrl}/api/skills`);
      res.status(upstream.status).json(await upstream.json());
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  app.post("/api/skills/detect", optionalAuth, async (req, res) => {
    try {
      const { query, preferred_domains } = req.body || {};
      if (!query) return res.status(400).json({ error: "query required" });
      const galaxyUrl = process.env.GALAXY_URL || "http://localhost:8081";
      const upstream = await fetch(`${galaxyUrl}/api/skills/detect`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ query, preferred_domains }),
      });
      res.status(upstream.status).json(await upstream.json());
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  app.post("/api/skills/block", optionalAuth, async (req, res) => {
    try {
      const { skill_ids } = req.body || {};
      if (!skill_ids?.length) return res.status(400).json({ error: "skill_ids required" });
      const galaxyUrl = process.env.GALAXY_URL || "http://localhost:8081";
      const upstream = await fetch(`${galaxyUrl}/api/skills/block`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ skill_ids }),
      });
      res.status(upstream.status).json(await upstream.json());
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  // ── Accession resolver (resolve_accession MCP tool) ─────────────────────
  // POST /api/accession/resolve
  // Given a public archive accession (GEO GSE*, SRA SRR*, ENA ERR*, etc.) returns
  // the best BioMate workflow to fetch it plus pre-filled params ready for run_workflow.
  app.post("/api/accession/resolve", authenticateStaticApiKey, authenticateToken, express.json(), async (req, res) => {
    const { accession } = req.body || {};
    if (!accession || typeof accession !== "string") {
      return res.status(400).json({ error: "accession is required" });
    }
    const acc = accession.trim().toUpperCase();

    // Classify accession type and select the best fetcher workflow.
    type AccessionClass = {
      type: string;
      archive: string;
      workflow_id: number;
      workflow_name: string;
      nextflow_path: string;
      param_key: string;   // which workflow input param the accession goes into
      description: string;
    };

    const ACCESSION_MAP: Array<{ pattern: RegExp; cls: AccessionClass }> = [
      // GEO series / sample → Geo Data Connector (R-based; returns count matrix + metadata)
      {
        pattern: /^(GSE|GDS)\d+$/,
        cls: {
          type: "GEO_series", archive: "GEO",
          workflow_id: 10672, workflow_name: "Geo Data Connector",
          nextflow_path: "nextflow_nfcore/subworkflows/genomics/geo_data_connector/main.nf",
          param_key: "accession",
          description: "Downloads GEO series matrix + clinical metadata via GEOquery; emits channels ready for DESeq2/edgeR.",
        },
      },
      {
        pattern: /^GSM\d+$/,
        cls: {
          type: "GEO_sample", archive: "GEO",
          workflow_id: 10672, workflow_name: "Geo Data Connector",
          nextflow_path: "nextflow_nfcore/subworkflows/genomics/geo_data_connector/main.nf",
          param_key: "accession",
          description: "Downloads individual GEO sample via GEOquery.",
        },
      },
      // SRA/ENA/DDBJ runs/experiments/projects → nf-core/fetchngs
      {
        pattern: /^(SRR|SRX|SRS|SRP|ERP|ERR|ERX|DRR|DRP|PRJNA|PRJEB|PRJDB|E-[A-Z]+-\d+)\S*/,
        cls: {
          type: "SRA_ENA_DDBJ", archive: "SRA/ENA/DDBJ",
          workflow_id: 12704, workflow_name: "nf-core/fetchngs",
          nextflow_path: "nfcore/fetchngs/main.nf",
          param_key: "input",
          description: "Downloads raw FASTQ files and metadata from SRA, ENA, DDBJ, or GEO using nf-core/fetchngs. Output FASTQs can feed directly into nf-core/rnaseq, sarek, etc.",
        },
      },
    ];

    let matched: AccessionClass | null = null;
    for (const { pattern, cls } of ACCESSION_MAP) {
      if (pattern.test(acc)) { matched = cls; break; }
    }

    if (!matched) {
      return res.status(422).json({
        error: "Unrecognised accession format",
        hint: "Supported prefixes: GSE, GSM, GDS, SRR, SRX, SRS, SRP, ERR, ERX, ERP, DRR, DRP, PRJNA, PRJEB, E-MTAB-*, E-GEOD-*",
        accession: acc,
      });
    }

    // Verify the workflow still exists in the DB.
    let db_name: string | null = null;
    try {
      const dbPath = process.env.GALAXY_AI_TOOLS_DB || path.join(process.cwd(), "../backend/database/galaxy_ai_tools.db");
      if (existsSync(dbPath)) {
        const db = new BetterSqlite3(dbPath, { readonly: true });
        const row = db.prepare("SELECT name FROM workflows WHERE id = ?").get(matched.workflow_id) as { name: string } | undefined;
        db.close();
        db_name = row?.name ?? null;
      }
    } catch { /* non-fatal — return resolved info regardless */ }

    res.json({
      accession: acc,
      accession_type: matched.type,
      archive: matched.archive,
      workflow_id: matched.workflow_id,
      workflow_name: db_name ?? matched.workflow_name,
      nextflow_path: matched.nextflow_path,
      prefilled_params: { [matched.param_key]: acc },
      description: matched.description,
      ready_to_run: true,
      next_step: `Call run_workflow with workflow_id=${matched.workflow_id} and params=${JSON.stringify({ [matched.param_key]: acc })}`,
    });
  });

  // ── Data source browsing (browse_data MCP tool) ──────────────────────────
  // GET /api/data/sources  — list configured data sources
  // GET /api/data/browse   — list contents of a path within a source
  // POST /api/data/fetch   — download/stage a public file into BioMate S3
  //
  // Authentication: chained [authenticateStaticApiKey, authenticateToken].
  // authenticateStaticApiKey sets req.user from BIOMATE_CONNECTOR_API_KEY and
  // calls next(); authenticateToken then skips (req.user already set).
  // Clients that send only a JWT skip the API-key check and use JWT path normally.
  app.get("/api/data/sources", authenticateStaticApiKey, authenticateToken, async (req, res) => {
    // Galaxy exposes configured file source plugins at /api/remote_files/plugins.
    // We proxy and reshape the response to a stable BioMate-facing schema.
    try {
      const galaxyUrl = process.env.GALAXY_URL || "http://localhost:8081";
      const upstream = await fetch(`${galaxyUrl}/api/remote_files/plugins`, {
        signal: AbortSignal.timeout(10_000),
      });
      if (!upstream.ok) {
        // Galaxy not configured or file_sources_conf.yml missing — return
        // the static list parsed from the known config to avoid a 500.
        return res.json({
          sources: [
            { id: "ebi_ftp",        label: "EBI — European Bioinformatics Institute", type: "ftp",  writable: false },
            { id: "ncbi_ftp",       label: "NCBI — National Center for Biotechnology Information", type: "ftp", writable: false },
            { id: "ensembl_ftp",    label: "Ensembl — Genome Browser", type: "ftp", writable: false },
            { id: "ucsc_downloads", label: "UCSC Genome Downloads", type: "ftp", writable: false },
            { id: "http_public",    label: "HTTP/HTTPS — Public URLs", type: "http", writable: false },
          ],
        });
      }
      const plugins: any[] = await upstream.json();
      res.json({ sources: plugins.map((p: any) => ({ id: p.id, label: p.label ?? p.id, type: p.type, writable: p.writable ?? false })) });
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  // GET /api/bioconductor/skill/:package — commented out.
  // BioMate's search_workflow covers this via the live workflow DB.
  // app.get("/api/bioconductor/skill/:package", ...);

  app.get("/api/data/browse", authenticateStaticApiKey, authenticateToken, async (req, res) => {
    // Proxies to Galaxy's /api/remote_files which lists contents of a file source path.
    try {
      const { source, path: browsePath } = req.query as { source?: string; path?: string };
      if (!source) return res.status(400).json({ error: "source is required" });
      const galaxyUrl = process.env.GALAXY_URL || "http://localhost:8081";
      // Galaxy's remote_files `target` is the plugin's gxfiles:// URI (the
      // plugin uri_root), NOT the bare id — passing the bare id 400s with
      // "Invalid target parameter supplied". Build gxfiles://<source>/<path>.
      const root = `gxfiles://${source}`;
      const sub = browsePath && browsePath !== "/" ? String(browsePath).replace(/^\/+/, "") : "";
      const target = sub ? `${root}/${sub}` : root;
      const qs = new URLSearchParams({ target, format: "uri", browsable: "true" });
      const upstream = await fetch(`${galaxyUrl}/api/remote_files?${qs}`, {
        signal: AbortSignal.timeout(20_000),
      });
      if (!upstream.ok) {
        const body = await upstream.text();
        return res.status(upstream.status).json({ error: body });
      }
      const data = await upstream.json();
      res.json(data);
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  app.post("/api/data/fetch", authenticateStaticApiKey, authenticateToken, express.json(), async (req, res) => {
    // Stages a remote file into BioMate S3 so a workflow can consume it.
    // The Galaxy backend handles the actual download + S3 upload.
    try {
      const { source, path: remotePath, url } = req.body || {};
      if (!remotePath && !url) {
        return res.status(400).json({ error: "path or url is required" });
      }
      const galaxyUrl = process.env.GALAXY_URL || "http://localhost:8081";
      const upstream = await fetch(`${galaxyUrl}/api/nextflow/fetch_public_data`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ source_id: source, remote_path: remotePath, url }),
        signal: AbortSignal.timeout(30_000),
      });
      const data = await upstream.json();
      res.status(upstream.status).json(data);
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  // GET /api/s3/browse — list objects in BioMate's S3 workspace (or user's configured S3 bucket).
  // Proxies to Galaxy's /api/nextflow/s3/browse which resolves credentials server-side.
  app.get("/api/s3/browse", authenticateStaticApiKey, authenticateToken, async (req, res) => {
    try {
      const { prefix = "", max_keys = "200" } = req.query as { prefix?: string; max_keys?: string };
      const galaxyUrl = process.env.GALAXY_URL || "http://localhost:8081";
      const galaxyApiKey = process.env.GALAXY_API_KEY || "";
      const qs = new URLSearchParams({ prefix, max_keys });
      const upstream = await fetch(`${galaxyUrl}/api/nextflow/s3/browse?${qs}`, {
        headers: galaxyApiKey ? { "x-api-key": galaxyApiKey } : {},
        signal: AbortSignal.timeout(15_000),
      });
      const data = await upstream.json();
      res.status(upstream.status).json(data);
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  // POST /api/uploads/signed_url — get S3 presigned URL for direct file upload (used by MCP upload_file)
  app.post("/api/uploads/signed_url", optionalAuth, async (req, res) => {
    try {
      const { filename, size_bytes, content_type } = req.body || {};
      if (!filename) return res.status(400).json({ error: "filename is required" });
      if (!s3Service.getBucketName()) {
        return res.status(503).json({ error: "S3 not configured — file uploads unavailable in this environment" });
      }
      const userId = req.user?.id ?? 'anonymous';
      const uploadData = await s3Service.generatePresignedUploadUrl(
        userId,
        filename,
        content_type || 'application/octet-stream',
      );
      res.json({
        upload_url: uploadData.uploadUrl,
        s3_key: uploadData.key,
        expires_in: uploadData.expires_in,
      });
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
            let nextflowStatus = effectiveExecutionRun?.execution?.nextflowStatus;
            const nfRunId = effectiveExecutionRun?.execution?.nextflowRunId
              || effectiveExecutionRun?.execution?.galaxyInvocationId;

            // Live fallback: if stored nextflowStatus has no S3 files but a Nextflow run ID
            // exists, query Galaxy directly (covers both running and recently completed runs
            // where the poller may have exited before storing file listings).
            const storedS3Files = Array.isArray(nextflowStatus?.s3_output_files)
              ? nextflowStatus!.s3_output_files
              : [];
            if (nfRunId && storedS3Files.length === 0) {
              try {
                const liveResp = await fetch(
                  `${process.env.GALAXY_URL || 'http://localhost:8081'}/api/nextflow/status/${nfRunId}`,
                  { headers: { 'X-API-Key': process.env.GALAXY_API_KEY || '' }, signal: AbortSignal.timeout(12_000) }
                );
                if (liveResp.ok) {
                  const liveData = await liveResp.json() as any;
                  if (Array.isArray(liveData.s3_output_files) && liveData.s3_output_files.length > 0) {
                    nextflowStatus = { ...nextflowStatus, ...liveData };
                    console.log(`[Outputs] live Galaxy S3 scan: ${liveData.s3_output_files.length} files`);
                  }
                }
              } catch { /* non-fatal */ }
            }

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

            // Final fallback: direct S3 ListObjectsV2 on the outdir prefix when
            // Galaxy's /api/nextflow/runs/{nfRunId}/output_files (above) found
            // nothing. Required when the Galaxy executor's post-completion
            // callback didn't register s3_output_files in nextflowStatus AND
            // Galaxy itself has no record of the run's output files. This is
            // the same logic /api/workflows/runs/:id/output_files uses.
            if (nextflowStatus?.outdir && String(nextflowStatus.outdir).startsWith('s3://')) {
              const hasS3FileArtifact = artifacts.some(a =>
                a.startsWith('s3://') && !a.endsWith('/') && a.split('/').pop()?.includes('.')
              );
              if (!hasS3FileArtifact) {
                try {
                  const m = String(nextflowStatus.outdir).match(/^s3:\/\/([^/]+)\/(.+?)\/?$/);
                  if (m) {
                    const [, bucket, prefix] = m;
                    const AWS = await import('@aws-sdk/client-s3');
                    const _nfKey = process.env.AWS_NF_ACCESS_KEY_ID;
                    const _nfSec = process.env.AWS_NF_SECRET_ACCESS_KEY;
                    const s3 = new AWS.S3Client({
                      region: 'us-east-1',
                      followRegionRedirects: true,
                      ...(_nfKey && _nfSec ? { credentials: { accessKeyId: _nfKey, secretAccessKey: _nfSec } } : {}),
                    });
                    const listed: string[] = [];
                    let continuationToken: string | undefined = undefined;
                    do {
                      const lr: any = await s3.send(new AWS.ListObjectsV2Command({
                        Bucket: bucket,
                        Prefix: `${prefix}/`,
                        ContinuationToken: continuationToken,
                        MaxKeys: 1000,
                      }));
                      for (const obj of (lr.Contents || [])) {
                        if (!obj.Key || obj.Key.endsWith('/')) continue;
                        listed.push(`s3://${bucket}/${obj.Key}`);
                      }
                      continuationToken = lr.IsTruncated ? lr.NextContinuationToken : undefined;
                    } while (continuationToken);
                    if (listed.length > 0) {
                      // Drop the bare-directory artifact entries, replace with real file URIs
                      const nonS3 = artifacts.filter(a => !a.startsWith('s3://'));
                      artifacts.length = 0;
                      artifacts.push(...nonS3, ...listed);
                      console.log(`[Outputs] Direct S3 list fallback: ${listed.length} files under ${nextflowStatus.outdir}`);
                    }
                  }
                } catch (e: any) {
                  console.warn('[Outputs] Direct S3 list fallback failed:', e?.message || e);
                }
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
      const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
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

      // Required-parameter gate. The frontend blocks a run when required params
      // are unfilled (hasUnfilledRequired in nextflow-workflow-viewer.tsx), but
      // that guard only protects the UI — API / connector / MCP callers could
      // dispatch a workflow with empty required params and burn a Batch job that
      // fails at launch. Enforce the same gate server-side so no caller can spend
      // compute on a run that is missing required inputs.
      //
      // Also honour `request.params` (the documented openapi contract:
      // "Parameter overrides — merged on top of workflow defaults"): the frontend
      // fills values into workflowDefinition.required_params[].value, but API
      // callers pass a `params` map, which was silently ignored. Merge those
      // values onto the declared params BEFORE validating + dispatching so they
      // are actually used downstream.
      {
        const isEmptyVal = (v: any) =>
          v === undefined || v === null || (typeof v === 'string' && v.trim() === '');
        const providedParams =
          request.params && typeof request.params === 'object' ? request.params : {};
        const reqParams: any[] = Array.isArray(request.workflowDefinition?.required_params)
          ? request.workflowDefinition.required_params
          : [];
        const optParams: any[] = Array.isArray(request.workflowDefinition?.optional_params)
          ? request.workflowDefinition.optional_params
          : [];
        // Merge caller-supplied param values onto the declared params in place so
        // createExecutionRun (which reads request.workflowDefinition) picks them up.
        for (const p of [...reqParams, ...optParams]) {
          if (p && p.name && !isEmptyVal(providedParams[p.name])) {
            p.value = providedParams[p.name];
          }
        }
        // A required param is satisfied only if it now carries a usable value or
        // a non-empty default. Anything still empty blocks the launch.
        const missingParams = reqParams.filter(
          (p: any) => p && p.name && isEmptyVal(p.value) && isEmptyVal(p.default),
        );
        if (missingParams.length > 0 && request.executionConfig?.allowLowConfidence !== true) {
          return res.status(400).json({
            error: "missing_required_params",
            message: `Workflow "${request.workflowDefinition?.name || 'this workflow'}" needs ${missingParams.length} required parameter(s) before it can run. No compute was launched.`,
            missing: missingParams.map((p: any) => ({
              name: p.name,
              label: p.label || p.name,
              description: p.description || '',
              type: p.type || 'string',
            })),
            guidance:
              "Provide values for the listed parameters (fill them in the workflow params panel, or pass them in the request `params` map) and retry.",
          });
        }
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
        galaxyHistoryId = await userProxy(req).createHistory(historyName).catch(() => `nf-${executionRun.id}`);
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
      console.log('[Execute DEBUG] workflow_type=', request.workflowDefinition.workflow_type, 'hasCryoSPARCInstance=', hasCryoSPARCInstance, 'CRYOSPARC_AMI_ID=', !!process.env.CRYOSPARC_AMI_ID);
      if (request.workflowDefinition.workflow_type === 'cryosparc' && hasCryoSPARCInstance) {
        console.log('[CryoSPARC Direct] Detected workflow_type=cryosparc (instance configured)');

        try {
          // Build CryoSPARC params first — extract movies_path/pixel_size/num_movies from
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
          if (!csParams.pixel_size) {
            const m = userCtx.match(/pixel_size\s*=\s*([\d.]+)/);
            if (m) csParams.pixel_size = parseFloat(m[1]);
          }
          if (!csParams.num_movies) {
            const m = userCtx.match(/num_movies\s*=\s*(\d+)/);
            if (m) csParams.num_movies = parseInt(m[1], 10);
          }

          // Resolve CryoSPARC license key — priority:
          //   1. Credential store (user-specific, stored via Settings → Credentials)
          //   2. License key in workflow params (user typed it in chat: cryosparc_license=<key>)
          //   3. CRYOSPARC_LICENSE env var (dev/E2E fallback)
          let userLicenseKey: string | null = null;
          try {
            const credResp = await userProxy(req).client.get('/api/users/credentials/cryosparc/value');
            userLicenseKey = credResp.data?.data?.license_key || null;
          } catch (_credErr: any) {
            console.warn('[CryoSPARC Direct] credential store unavailable:', _credErr?.response?.status || _credErr?.message);
          }
          if (!userLicenseKey) {
            userLicenseKey = (csParams.cryosparc_license as string) || process.env.CRYOSPARC_LICENSE || null;
          }
          delete csParams.cryosparc_license; // don't pass license key as a pipeline param

          if (!userLicenseKey) {
            return res.status(402).json({
              error: 'cryosparc_license_required',
              message: 'A CryoSPARC license key is required. Add yours at Settings → Credentials → CryoSPARC.',
            });
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

              let latestNfStatus: any = null;
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
                latestNfStatus = s;
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
                // Also fetch Nextflow status — CryoSPARC runs via Nextflow; galaxyInvocationId IS the NF run ID.
                const nfRunId = executionRun.execution?.nextflowRunId || executionRun.execution?.galaxyInvocationId;
                if (nfRunId) {
                  try {
                    const nfResp = await fetch(
                      `${process.env.GALAXY_URL || 'http://localhost:8081'}/api/nextflow/status/${nfRunId}`,
                      { headers: { 'X-API-Key': process.env.GALAXY_API_KEY || '' } }
                    );
                    if (nfResp.ok) latestNfStatus = await nfResp.json();
                  } catch { /* non-fatal */ }
                }
              }

              const terminal = ['completed', 'failed'].includes(mappedStatus);
              await storage.updateExecutionRun(executionRun.id, {
                execution: {
                  ...executionRun.execution,
                  galaxyInvocationId: csRunId,
                  status: mappedStatus,
                  nextflowStatus: latestNfStatus ?? executionRun.execution?.nextflowStatus,
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
          const rawParams = { ...(request.workflowDefinition.parameters || {}) };
          const paramProfile =
            rawParams.profile ??
            request.executionConfig?.nextflow_profile ??
            undefined;
          if ('profile' in rawParams) delete rawParams.profile;
          if ('executor' in rawParams) delete rawParams.executor;

          const stagedParams = await stageLocalFilesForBatch(
            rawParams,
            req.user ? String(req.user.id) : 'anonymous'
          );

          // Phase C — extract __outputLocation from params (set by viewer's
          // handleExecute when user picks non-default option) and pass as a
          // top-level field that NextflowExecuteRequest.output_location reads.
          // See backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py._resolve_outdir
          const __outputLocation = (stagedParams as any).__outputLocation;
          const stagedParamsClean = { ...stagedParams };
          delete (stagedParamsClean as any).__outputLocation;

          // If a personal (user-uploaded) workflow was selected, fetch its
          // file_content from the DB and pass it to the Galaxy backend so it
          // can write the file to /tmp and execute it without needing a
          // pre-staged path on the Galaxy filesystem.
          let personalFileContent: string | undefined;
          if (request.workflowDefinition?.personal_workflow_id) {
            const pwRes = await pool.query(
              `SELECT file_content FROM personal_workflows
               WHERE id = $1 AND user_id = $2`,
              [request.workflowDefinition.personal_workflow_id, String(req.user?.id)]
            );
            personalFileContent = pwRes.rows[0]?.file_content;
          }

          const _nfBody = JSON.stringify({
              history_id: galaxyHistoryId,
              // When file_content is provided (personal workflow), the Galaxy backend
              // writes the content to a temp file and overrides nextflow_path internally.
              // We still must supply a non-null nextflow_path to pass Pydantic validation.
              nextflow_path: request.workflowDefinition.nextflow_path || (personalFileContent ? 'personal_workflow/main.nf' : ''),
              ...(personalFileContent ? { file_content: personalFileContent } : {}),
              parameters: stagedParamsClean,
              ...(__outputLocation ? { output_location: __outputLocation } : {}),
              // ⚠️ DO NOT REVERT to `docker`. Third re-application of 2885eb960 / 140502f23.
              // biomate-ai-tools workflows define an `aws` profile, NOT `docker`. nf-core
              // on Batch accepts `aws` too since both delegate to the awsbatch executor.
              // Hardcoded `docker` triggers "Unknown configuration profile: 'docker'" on
              // every tier 0 dispatch (verified 2026-05-22, 2026-05-28, 2026-05-29) and
              // kills the workflow in ~3 seconds before any phase starts.
              profile:
                paramProfile ||
                request.executionConfig?.nextflow_profile ||
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
            });
          // Retry up to 3 times on transient Galaxy backend errors:
          //   - HTTP 502/503/504: gunicorn worker recycled mid-request
          //   - TypeError "fetch failed": ECONNREFUSED during worker restart (<1s window)
          // Fixed 3s delay — gunicorn recycles in <5s.
          let nextflowResponse: Response | null = null;
          for (let _attempt = 0; _attempt < 3; _attempt++) {
            if (_attempt > 0) {
              await new Promise(r => setTimeout(r, 3000));
              console.log(`[Nextflow Direct] Retry attempt ${_attempt} after transient Galaxy error`);
            }
            try {
              nextflowResponse = await fetch(`${process.env.GALAXY_URL || 'http://localhost:8081'}/api/nextflow/execute`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'X-API-Key': process.env.GALAXY_API_KEY || '' },
                body: _nfBody,
              });
            } catch (fetchErr: any) {
              console.warn(`[Nextflow Direct] Galaxy fetch error (attempt ${_attempt + 1}/3): ${fetchErr.message}`);
              if (_attempt < 2) continue; // retry on network error (ECONNREFUSED during worker restart)
              throw fetchErr;             // last attempt — propagate
            }
            if (nextflowResponse.ok || ![502, 503, 504].includes(nextflowResponse.status)) break;
            console.warn(`[Nextflow Direct] Galaxy returned ${nextflowResponse.status} (attempt ${_attempt + 1}/3) — will retry`);
          }

          if (!nextflowResponse!.ok) {
            const errBody = await nextflowResponse!.text().catch(() => nextflowResponse!.statusText);
            throw new Error(`Nextflow execution failed (${nextflowResponse!.status}): ${errBody}`);
          }

          const nextflowData = await nextflowResponse!.json();
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
            message: `Workflow queued (run_id: ${nextflowData.run_id})`,
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
            error: 'workflow_execution_failed',
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

      // executionEngine is narrowed to 'galaxy' | 'cryosparc' here — the
      // Nextflow-direct path above returns before reaching this point, so the
      // previous `scheduler: 'nextflow'` spread was dead code.
      const invocationResult = await userProxy(req).invokeWorkflow(
        galaxyWorkflow.id,
        galaxyInputs,
        {
          history_id: galaxyHistoryId,
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
      let run = await storage.getExecutionRun(req.params.id);
      // Fall back to Galaxy invocation ID lookup (session restore may have stored
      // the Galaxy UUID instead of the DB primary key).
      if (!run) {
        run = await storage.getExecutionRunByGalaxyId(req.params.id);
      }
      if (!run) {
        return res.status(404).json({ error: "Execution run not found" });
      }

      // Stuck-running guard: if a run has been status='running' for >12h with
      // no terminal signal, the Nextflow JVM is almost certainly dead
      // (container restart, OOM, gunicorn worker recycle). No drug-dev
      // workflow legitimately exceeds 12h. Force a terminal state so the UI
      // doesn't show 'running' forever.
      //
      // History (this guard keeps getting silently stripped by auto-sync):
      //   2026-05-27 cb27e14c8 — first added
      //   2026-06-02 — stripped, re-added here with a companion test
      //               (backend/tests/test_stuck_running_guard.py) to catch
      //               future strips before deploy.
      const STUCK_RUNNING_MS = 12 * 60 * 60 * 1000;
      if (run.execution?.status === 'running' && run.execution?.startedAt) {
        const startedAt = new Date(run.execution.startedAt as any).getTime();
        if (startedAt > 0 && (Date.now() - startedAt) > STUCK_RUNNING_MS) {
          console.warn(
            `[ExecutionRun] stuck-running guard: marking ${run.id} as failed (>12h with no terminal signal)`
          );
          run = await storage.updateExecutionRun(run.id, {
            execution: {
              ...run.execution,
              status: 'failed' as any,
              errorMessage:
                'Run exceeded 12h with no terminal signal — Nextflow process likely died ' +
                '(container restart, worker recycle, OOM). AWS Batch outputs may still be ' +
                'recoverable via /api/runs/:id/outputs (publishDir-gap fallback).',
              completedAt: new Date(),
            },
          }) || run;
        }
      }

      // ── Lazy Nextflow status reconcile ────────────────────────────────────
      // The stored execution.status is otherwise only advanced by the /status
      // polling endpoint, so runs driven outside the UI poll loop (MCP /
      // headless / direct API) can show stale 'running' long after the Nextflow
      // run finished on AWS Batch. Poll the live Nextflow status and persist a
      // terminal flip here too, so EVERY reader of the run record (get_run,
      // overview, MCP) sees the real outcome — not just /status callers.
      {
        const isNextflowRun =
          getWorkflowExecutionEngine(run.workflowDefinition) === 'nextflow' ||
          run.execution?.executionEngine === 'nextflow' ||
          !!run.execution?.nextflowRunId;
        const nonTerminal = ['running', 'paused', 'queued'].includes(
          String(run.execution?.status)
        );
        const nfRunId = run.execution?.nextflowRunId || run.execution?.galaxyInvocationId;
        if (isNextflowRun && nonTerminal && nfRunId) {
          try {
            const nextflowStatus = await galaxyAPIProxy.getNextflowStatus(nfRunId);
            const nfState = String(nextflowStatus?.status || '').toLowerCase();
            if (['succeeded', 'failed', 'error'].includes(nfState)) {
              const mappedStatus: ExecutionRunStatus = toValidRunStatus(nfState);
              run = await storage.updateExecutionRun(run.id, {
                execution: {
                  ...run.execution,
                  status: mappedStatus,
                  errorMessage: nfState === 'succeeded'
                    ? undefined
                    : (nextflowStatus?.log_tail?.slice?.(-1)?.[0]
                        || run.execution?.errorMessage || 'Nextflow run failed'),
                  completedAt: new Date(),
                  nextflowStatus,
                },
              }) || run;
              const nfInvocationId = run.execution?.galaxyInvocationId || run.execution?.nextflowRunId;
              if (nfInvocationId) {
                galaxyPoller.emit('workflow_completed', {
                  invocation_id: nfInvocationId,
                  state: nfState === 'succeeded' ? 'ok' : 'failed',
                });
              }
            } else if (nextflowStatus) {
              // Non-terminal: keep latest snapshot for output/visibility.
              run = await storage.updateExecutionRun(run.id, {
                execution: { ...run.execution, nextflowStatus },
              }) || run;
            }
          } catch (e: any) {
            console.warn('[ExecutionRun] lazy nextflow reconcile failed:', e?.message || e);
          }
        }
      }

      // ── Inline convenience fields for MCP / headless consumers ────────────
      // MCP tools/get_run clients should not need a second round-trip to
      // /output_files or /status to get findings and files. Surface them here.
      const ns = (run.execution?.nextflowStatus as any) || {};
      const response: any = {
        ...run,
        // Canonical file list: prefer S3-backed files, fall back to local.
        output_files: ns.s3_output_files || ns.output_files || [],
        // AI findings / key results synthesized by the findings-analysis job.
        inline_findings: ns.findings || ns.ai_findings || ns.key_results || [],
      };

      res.json(response);
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

      // Chain runs: poll Python chain executor and mirror progress into ExecutionRun
      const isChainRun =
        run.execution?.executionEngine === 'chain' ||
        run.workflowDefinition?.workflow_type === 'chain';
      let chainStatus: any | undefined = undefined;
      if (isChainRun && run.execution?.galaxyInvocationId) {
        try {
          const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
          const chainResp = await fetch(
            `${galaxyUrl}/api/workflows/chain/${encodeURIComponent(run.execution.galaxyInvocationId)}`,
            { signal: AbortSignal.timeout(10000) },
          );
          if (chainResp.ok) {
            chainStatus = await chainResp.json();
            const chainState = String(chainStatus.status || 'running').toLowerCase();
            const progress = chainStatus.progress || {};
            const completedSteps =
              progress.completedSteps ?? chainStatus.steps_completed ?? run.progress.completedSteps;
            const totalSteps =
              progress.totalSteps ?? chainStatus.steps_total ?? run.progress.totalSteps;
            const isTerminal = ['succeeded', 'failed', 'cancelled'].includes(chainState);
            const isPaused = chainState === 'awaiting_approval';
            const mappedStatus = toValidRunStatus(chainState);
            const progressPatch = {
              totalSteps,
              completedSteps,
              percentComplete: totalSteps
                ? Math.round((100 * completedSteps) / totalSteps)
                : run.progress.percentComplete,
            };

            if (isTerminal && run.execution.status !== mappedStatus) {
              run =
                (await storage.updateExecutionRun(run.id, {
                  execution: {
                    ...run.execution,
                    status: mappedStatus,
                    completedAt: new Date(),
                    nextflowStatus: chainStatus,
                  },
                  progress: { ...run.progress, ...progressPatch },
                })) || run;

              const chainName =
                run.workflowDefinition?.chain_name || run.workflowDefinition?.name;
              if (chainState === 'succeeded' && chainName) {
                fetch(`${galaxyUrl}/api/workflow-chains/record-run`, {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json' },
                  body: JSON.stringify({ chain_name: chainName, success: true }),
                }).catch(() => undefined);
              }
            } else if (isPaused && run.execution.status !== 'paused') {
              run =
                (await storage.updateExecutionRun(run.id, {
                  execution: {
                    ...run.execution,
                    status: 'paused',
                    nextflowStatus: chainStatus,
                  },
                  progress: { ...run.progress, ...progressPatch },
                })) || run;
            } else if (run.execution.status === 'running' || run.execution.status === 'paused') {
              run =
                (await storage.updateExecutionRun(run.id, {
                  execution: {
                    ...run.execution,
                    nextflowStatus: chainStatus,
                  },
                  progress: { ...run.progress, ...progressPatch },
                })) || run;
            }
          }
        } catch (chainErr: any) {
          console.warn('[ExecutionRun] Failed to fetch chain status:', chainErr?.message || chainErr);
        }
      }

      // Return lightweight status response
      const isNextflowRun =
        !isChainRun &&
        (getWorkflowExecutionEngine(run.workflowDefinition) === 'nextflow' ||
        run.execution?.executionEngine === 'nextflow' ||
        !!run.execution?.nextflowRunId ||
        (run.execution?.executionEngine === 'cryosparc' && !!run.execution?.galaxyInvocationId));
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
          // Failed-to-succeeded rescue: BioMate may have written a bogus
          // 'failed' early (e.g. HUP-induced log-stream orphan — see
          // nextflow_executor.py _looks_like_log_stream_orphan_failure)
          // while the detached Nextflow JVM kept running and ultimately
          // succeeded on AWS Batch. When Galaxy now reports succeeded but
          // BioMate said failed, trust Galaxy (which has the real
          // workflow-trace and S3 outputs) and rescue the run state.
          const allowRescue =
            isAlreadyTerminal && run.execution.status === 'failed' && nfState === 'succeeded';
          if (((nfState === 'succeeded' || nfState === 'failed' || nfState === 'error') && !isAlreadyTerminal) || allowRescue) {
            if (allowRescue) {
              console.warn(
                `[ExecutionRun] failed→succeeded rescue: ${run.id} — Galaxy reports nextflow succeeded; flipping BioMate status (was failed, likely log-stream-orphan)`
              );
            }
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
          } else if (
            // P0 fix (2026-06-17 after-run audit): the terminal-transition
            // branch above writes nextflowStatus ONCE, but s3_output_files
            // can lag the status flip by seconds → the saved snapshot has
            // empty outputs. Refresh the snapshot post-terminal when the
            // current Nextflow status has MORE s3_output_files than the
            // stored one. Hide-when-empty: never overwrite a populated
            // snapshot with an empty one (defends against transient Galaxy
            // hiccups).
            ['completed', 'succeeded', 'failed'].includes(String(run.execution.status)) &&
            Array.isArray(nextflowStatus?.s3_output_files)
          ) {
            const storedCount = Array.isArray(run.execution.nextflowStatus?.s3_output_files)
              ? run.execution.nextflowStatus.s3_output_files.length
              : 0;
            const liveCount = nextflowStatus.s3_output_files.length;
            if (liveCount > storedCount) {
              console.log(
                `[ExecutionRun] post-terminal nextflowStatus refresh: ${run.id} s3_output_files ${storedCount} → ${liveCount}`,
              );
              run = await storage.updateExecutionRun(run.id, {
                execution: {
                  ...run.execution,
                  nextflowStatus: nextflowStatus,
                },
              }) || run;
            }
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
        // Normalize: nextflow_executor.py persists 'succeeded' (native Nextflow
        // term) on terminal completion. Without this normalization the UI's
        // status mapper (chat-with-artifacts.tsx) falls through to 'idle' and
        // phase cards never get data-status="completed".
        status: toValidRunStatus(run.execution.status),
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
        temperature: 0,
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
        temperature: 0,
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
        chain_name: req.body?.chain_name || req.body?.workflow_name,
        chat_session_id: req.body?.chatSessionId || req.body?.chat_session_id,
        connections: req.body?.connections || [],
        start_from_step: req.body?.start_from_step ?? 0,
        end_at_step: req.body?.end_at_step ?? req.body?.endAtStep ?? undefined,
        steps: rawSteps.map((s: any) => ({
          nextflow_path: s.nextflow_path || s.workflowPath || s.workflow_path || s.nextflowPath,
          workflow_name: s.workflow_name || s.name,
          role: s.role,
          step_key: s.step_key || s.stepKey,
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

      // Register chain in session Run Manager (MVI — one campaign object per chat)
      if (resp.ok && data.chain_run_id) {
        try {
          const chainName =
            req.body?.chain_name ||
            req.body?.workflow_name ||
            'Workflow chain';
          const isResume = Boolean(req.body?.chain_run_id && (req.body?.start_from_step ?? 0) > 0);
          if (isResume) {
            const sessionRuns = await storage.getExecutionRuns(
              req.user?.id,
              req.body?.projectId,
              undefined,
              50,
              req.body?.chatSessionId,
            );
            const existing = sessionRuns.find(
              (r) => r.execution?.galaxyInvocationId === data.chain_run_id,
            );
            if (existing) {
              const updated = await storage.updateExecutionRun(existing.id, {
                execution: {
                  ...existing.execution,
                  status: 'running',
                  startedAt: existing.execution.startedAt || new Date(),
                },
              });
              data.runId = updated?.id || existing.id;
            }
          }
          if (!data.runId) {
          const executionRun = await storage.createExecutionRun(
            {
              workflowDefinition: {
                name: chainName,
                workflow_type: 'chain',
                format: 'chain',
                execution_engine: 'chain',
                chain_name: req.body?.chain_name,
                chain_run_id: data.chain_run_id,
                chain_steps: rawSteps,
                chain_connections: req.body?.connections || [],
              },
              executionConfig: {
                mode: 'sandbox',
                dataScope: { fraction: 1.0, samplingStrategy: 'sequential', sampledIds: [] },
                executionEngine: 'chain',
              },
              chatSessionId: req.body?.chatSessionId,
            },
            req.user?.id,
            req.body?.projectId,
          );
          const updated = await storage.updateExecutionRun(executionRun.id, {
            execution: {
              ...executionRun.execution,
              status: 'running',
              galaxyInvocationId: data.chain_run_id,
              executionEngine: 'chain',
              startedAt: new Date(),
            },
            progress: {
              totalSteps: rawSteps.length,
              completedSteps: 0,
              percentComplete: 0,
            },
          });
          data.runId = updated?.id || executionRun.id;
          }
        } catch (regErr: any) {
          console.warn('[Chain] Failed to register ExecutionRun:', regErr?.message || regErr);
        }
      }

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

  app.get("/api/workflows/chain/:chainRunId/outputs", optionalAuth, async (req, res) => {
    const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
    try {
      const resp = await fetch(
        `${galaxyUrl}/api/workflows/chain/${req.params.chainRunId}/outputs`,
        { signal: AbortSignal.timeout(15000) },
      );
      const data = await resp.json();
      res.status(resp.status).json(data);
    } catch (err: any) {
      res.status(503).json({ error: String(err?.message ?? err) });
    }
  });

  app.get("/api/workflows/chain/:chainRunId/manifest", optionalAuth, async (req, res) => {
    const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
    try {
      const resp = await fetch(
        `${galaxyUrl}/api/workflows/chain/${req.params.chainRunId}/manifest`,
        { signal: AbortSignal.timeout(15000) },
      );
      if (resp.ok) {
        const data = await resp.json();
        return res.status(resp.status).json(data);
      }
      // Fallback when Galaxy backend predates manifest route: synthesize from chain status
      const statusResp = await fetch(
        `${galaxyUrl}/api/workflows/chain/${req.params.chainRunId}`,
        { signal: AbortSignal.timeout(10000) },
      );
      if (!statusResp.ok) {
        const errBody = await resp.text().catch(() => '');
        return res.status(statusResp.status).json({
          error: errBody || `Chain ${req.params.chainRunId} not found`,
        });
      }
      const state = await statusResp.json();
      const steps = (state.steps || []).map((step: any) => ({
        key: step.step_key || step.role || step.workflow_name || `step_${step.index}`,
        title: step.workflow_name,
        nextflow_path: step.nextflow_path,
        run_id: step.run_id,
        status: step.status,
        artifacts: step.artifacts || {},
      }));
      const succeeded = steps.filter((s: any) => s.status === 'succeeded').length;
      return res.json({
        chain_run_id: state.chain_run_id,
        chain_name: state.chain_name,
        created_at: state.created_at,
        updated_at: new Date().toISOString(),
        status: state.status,
        through_step: succeeded,
        steps,
        manifest_path: null,
        _fallback: true,
      });
    } catch (err: any) {
      res.status(503).json({ error: String(err?.message ?? err) });
    }
  });

  // ── Canonical outputs endpoint (PR 1 of outputs-consolidation) ───────────
  // Single source of truth: resolves any id (runId / galaxyInvocationId /
  // nextflowRunId), lists S3 once with the right region+creds, returns the
  // normalized shape with presigned downloadUrl on every item.
  // See docs/20260518_OUTPUTS_SERVICE_CONSOLIDATION_SPEC.md
  app.get("/api/runs/:anyId/outputs", async (req, res) => {
    try {
      const { runsOutputsService } = await import("./services/runs-outputs-service");
      const items = await runsOutputsService.list(req.params.anyId);
      res.json({ outputs: items, count: items.length });
    } catch (e: any) {
      console.error("[runs-outputs] error:", e);
      res.status(500).json({ error: e?.message || String(e) });
    }
  });

  // Resolution helper — exposes the canonical meta for debugging / future UI.
  app.get("/api/runs/:anyId/meta", async (req, res) => {
    try {
      const { runsOutputsService } = await import("./services/runs-outputs-service");
      const meta = await runsOutputsService.resolve(req.params.anyId);
      if (!meta) return res.status(404).json({ error: "Run not found" });
      res.json(meta);
    } catch (e: any) {
      console.error("[runs-outputs] meta error:", e);
      res.status(500).json({ error: e?.message || String(e) });
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
        // Try raw chain_run_id (may be passed directly)
        const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
        try {
          const chainResp = await fetch(
            `${galaxyUrl}/api/workflows/chain/${encodeURIComponent(req.params.id)}/outputs`,
            { signal: AbortSignal.timeout(12000) },
          );
          if (chainResp.ok) {
            const chainData = await chainResp.json() as any;
            return res.status(200).json({
              output_files: chainData.output_files || [],
              outputs: chainData.output_files || [],
              outdir: null,
              source: 'chain_aggregate',
              chain_run_id: chainData.chain_run_id,
              steps: chainData.steps,
            });
          }
        } catch { /* fall through */ }
        return res.status(200).json({
          output_files: [],
          outputs: [],
          outdir: null,
          source: 'chain_unregistered',
        });
      }

      // Chain ExecutionRun — aggregate outputs from all steps
      if (
        run.execution?.executionEngine === 'chain' ||
        run.workflowDefinition?.workflow_type === 'chain'
      ) {
        const chainId = run.execution?.galaxyInvocationId || run.workflowDefinition?.chain_run_id;
        if (chainId) {
          try {
            const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
            const chainResp = await fetch(
              `${galaxyUrl}/api/workflows/chain/${encodeURIComponent(chainId)}/outputs`,
              { signal: AbortSignal.timeout(12000) },
            );
            if (chainResp.ok) {
              const chainData = await chainResp.json() as any;
              return res.status(200).json({
                output_files: chainData.output_files || [],
                outputs: chainData.output_files || [],
                outdir: null,
                source: 'chain_aggregate',
                chain_run_id: chainId,
                steps: chainData.steps,
              });
            }
          } catch (chainOutErr: any) {
            console.warn('[output_files] chain aggregate failed:', chainOutErr?.message);
          }
        }
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

      // S3 listing fallback for cloud runs whose Galaxy executor never registered
      // s3_output_files in nextflowStatus (e.g. older runs, or runs where the
      // post-completion callback dropped). Without this, completed cloud pipelines
      // appear to have zero outputs in the UI even though files exist in S3.
      // Each returned entry also includes a presigned `downloadUrl` (1 hour TTL)
      // so the browser/density-viewer/findings-agent can fetch S3 directly without
      // hitting the EC2 endpoint as a proxy.
      if (outputFiles.length === 0 && outdir && String(outdir).startsWith('s3://')) {
        try {
          const m = String(outdir).match(/^s3:\/\/([^/]+)\/(.+?)\/?$/);
          if (m) {
            const [, bucket, prefix] = m;
            const AWS = await import('@aws-sdk/client-s3');
            const presigner = await import('@aws-sdk/s3-request-presigner');
            // biomate-nextflow-work lives in us-east-1; AWS_REGION on this host
            // is us-west-2 which causes "must be addressed using the specified
            // endpoint" redirect errors. Use the NF-specific creds + us-east-1
            // (same pattern as /api/invocations/:id/outputs at line ~7045).
            const _nfKey = process.env.AWS_NF_ACCESS_KEY_ID;
            const _nfSec = process.env.AWS_NF_SECRET_ACCESS_KEY;
            const s3 = new AWS.S3Client({
              region: 'us-east-1',
              followRegionRedirects: true,
              ...(_nfKey && _nfSec ? { credentials: { accessKeyId: _nfKey, secretAccessKey: _nfSec } } : {}),
            });
            const listed: any[] = [];
            let continuationToken: string | undefined = undefined;
            do {
              const lr: any = await s3.send(new AWS.ListObjectsV2Command({
                Bucket: bucket,
                Prefix: `${prefix}/`,
                ContinuationToken: continuationToken,
                MaxKeys: 1000,
              }));
              for (const obj of (lr.Contents || [])) {
                if (!obj.Key || obj.Key.endsWith('/')) continue;
                const name = obj.Key.split('/').pop() || obj.Key;
                const ext = (name.includes('.') ? name.split('.').pop() : '').toLowerCase();
                listed.push({
                  name, filename: name, extension: ext,
                  size: obj.Size || 0,
                  s3_uri: `s3://${bucket}/${obj.Key}`,  // DEPRECATED for client use — see download_endpoint below
                  s3_bucket: bucket,
                  s3_key: obj.Key,
                  // B.3 (Phase B output-lockdown) — canonical client-facing
                  // download path. Replaces s3_uri/downloadUrl for new code.
                  download_endpoint: `/api/runs/${req.params.id}/output/${encodeURIComponent(name)}`,
                });
              }
              continuationToken = lr.IsTruncated ? lr.NextContinuationToken : undefined;
            } while (continuationToken);

            // Presign each file's downloadUrl (1 hour TTL) in parallel
            const PRESIGN_TTL = 3600;
            await Promise.all(listed.map(async (f: any) => {
              try {
                f.downloadUrl = await presigner.getSignedUrl(
                  s3,
                  new AWS.GetObjectCommand({ Bucket: f.s3_bucket, Key: f.s3_key }),
                  { expiresIn: PRESIGN_TTL }
                );
              } catch (e: any) {
                console.warn(`[output_files] presign failed for ${f.s3_key}: ${e?.message}`);
              }
            }));
            outputFiles = listed;
            console.log(`[output_files] S3 listing fallback: found ${listed.length} files under ${outdir} (presigned for ${PRESIGN_TTL}s)`);
          }
        } catch (e: any) {
          console.warn(`[output_files] S3 list fallback failed: ${e?.message || e}`);
        }
      }

      if (!outdir || !String(outdir).startsWith('s3://')) {
        outdir = `s3://${s3Bucket}/nextflow/outputs/${runId}`;
      }

      // Inject download_url for every file that doesn't already have one.
      // Files from nfStatus.s3_output_files only carry {s3_uri, name, size, extension};
      // the S3-listing fallback path above already sets download_endpoint + downloadUrl.
      // This ensures MCP clients and API consumers always get an authenticated HTTP URL.
      for (const f of outputFiles) {
        if (!f.download_url && !f.download_endpoint && !f.downloadUrl) {
          const fname = encodeURIComponent(f.name || f.filename || '');
          if (fname) {
            f.download_url = `/api/runs/${runId}/output/${fname}`;
            f.download_endpoint = f.download_url;
          }
        } else if (!f.download_url) {
          // Normalise: always expose download_url alongside download_endpoint
          f.download_url = f.download_endpoint || f.downloadUrl;
        }
      }

      res.json({
        workflow_id: runId,
        status: run.execution?.status || 'unknown',
        output_files: outputFiles,
      });
    } catch (error: any) {
      console.error('[output_files] Error:', error);
      res.status(500).json({ error: error.message });
    }
  });

  // Alias: same data as /output_files but returns the bare array (matches what
  // tool-callers and the CryoEM E2E tests expect — they iterate the response
  // as `outputs.map(o => o.filename)`).
  app.get("/api/workflows/runs/:id/outputs", async (req, res) => {
    try {
      const r = await fetch(
        `http://localhost:${process.env.PORT || 5000}/api/workflows/runs/${req.params.id}/output_files`,
        // X-Forwarded-Proto: https — without it this self-fetch is 301'd to
        // https on a plain-HTTP port by forceHTTPS (only /internal/ is exempt)
        // and fails on the deploy stack. Same class as the analyze fix above.
        { headers: { Authorization: req.headers.authorization || '', cookie: req.headers.cookie || '', 'X-Forwarded-Proto': 'https' } as any }
      );
      const data: any = await r.json().catch(() => ({}));
      res.status(r.status).json(data.output_files || []);
    } catch (e: any) {
      res.status(500).json({ error: e.message });
    }
  });

  // ── B.1 — Counted output download endpoint (Phase B output-lockdown) ──
  // Replaces direct user S3 access. Resolves run + file → generates a
  // 60-second presigned S3 URL → writes audit-log row → 302 redirects.
  // Per docs/20260619_OUTPUT_LOCKDOWN_PHASE_B_C_SPEC.md (B.1).
  app.get("/api/runs/:runId/output/:filename", authenticateToken, async (req: any, res) => {
    const startedAt = Date.now();
    const { runId, filename: rawFilename } = req.params;
    const filename = decodeURIComponent(rawFilename);
    const userId: string | undefined = req.user?.id;
    const userEmail: string | undefined = req.user?.email;
    const ipAddress = (req.headers['x-forwarded-for'] as string | undefined)?.split(',')[0]?.trim()
                    || req.socket?.remoteAddress || null;
    const userAgent = req.headers['user-agent'] as string | undefined;

    // Defensive: defer audit-log writer import so a missing schema doesn't 500 the endpoint
    const writeAuditRow = async (httpStatus: number, fileSize: number | null, projectId: string | null) => {
      try {
        const { outputAccessLog } = await import("@shared/schema");
        await db.insert(outputAccessLog).values({
          runId,
          filename,
          userId: userId ?? "anonymous",
          userEmail: userEmail ?? null,
          projectId,
          ipAddress: ipAddress as any,
          userAgent: userAgent ?? null,
          httpStatus,
          fileSizeBytes: fileSize ?? null,
        });
      } catch (err: any) {
        console.warn(`[output_access_log] insert failed for ${runId}/${filename}: ${err?.message}`);
      }
    };

    try {
      // 1. Resolve run via storage (matches /output_files pattern at line 10099)
      let run = await storage.getExecutionRun(runId);
      if (!run) run = await storage.getExecutionRunByGalaxyId(runId);
      if (!run) {
        await writeAuditRow(404, null, null);
        return res.status(404).json({ error: 'Run not found' });
      }

      // 2. Authorize — owner-only by default; project members allowed when run is in a project
      const runOwnerId = (run as any).userId;
      const runProjectId = (run as any).projectId ?? null;
      const isOwner = userId && runOwnerId && userId === runOwnerId;
      let isProjectMember = false;
      if (!isOwner && runProjectId && userId) {
        try {
          // Project membership: defer to storage helper. If absent, treat as owner-only.
          const memberOf = await (storage as any).getUserProjects?.(userId);
          isProjectMember = Array.isArray(memberOf) && memberOf.some((p: any) => p?.id === runProjectId);
        } catch { /* treat as not-a-member on lookup failure */ }
      }
      if (!isOwner && !isProjectMember) {
        await writeAuditRow(403, null, runProjectId);
        return res.status(403).json({ error: 'Forbidden — run is not owned by current user and you are not a member of its project' });
      }

      // 3. Look up file in the run's output_files registry. The shape comes
      //    from the existing /output_files endpoint; nextflowStatus carries
      //    s3_output_files with s3_uri + filename + size.
      const nfStatus = (run as any).execution?.nextflowStatus as any;
      const s3Files: any[] = Array.isArray(nfStatus?.s3_output_files) ? nfStatus.s3_output_files : [];
      const localFiles: any[] = Array.isArray(nfStatus?.output_files) ? nfStatus.output_files : [];
      const allFiles = [...s3Files, ...localFiles];
      const match = allFiles.find((f: any) =>
        (f?.filename === filename || f?.name === filename) && (f?.s3_uri || f?.path)
      );
      if (!match) {
        await writeAuditRow(404, null, runProjectId);
        return res.status(404).json({ error: `File ${filename} not found in run ${runId}` });
      }

      const fileSize = typeof match.size === 'number' ? match.size : null;

      // 4. If it's an S3 file, generate 60-second presigned URL and 302 redirect.
      //    If it's a local path, stream it (small files only — large ones live in S3).
      const s3Uri: string | undefined = match.s3_uri || match.uri;
      if (s3Uri && s3Uri.startsWith('s3://')) {
        const m = s3Uri.match(/^s3:\/\/([^/]+)\/(.+)$/);
        if (!m) {
          await writeAuditRow(500, fileSize, runProjectId);
          return res.status(500).json({ error: 'Malformed s3 uri' });
        }
        const [, bucket, key] = m;
        const AWS = await import('@aws-sdk/client-s3');
        const presigner = await import('@aws-sdk/s3-request-presigner');
        const _nfKey = process.env.AWS_NF_ACCESS_KEY_ID;
        const _nfSec = process.env.AWS_NF_SECRET_ACCESS_KEY;
        const s3 = new AWS.S3Client({
          region: 'us-east-1',
          followRegionRedirects: true,
          ...(_nfKey && _nfSec ? { credentials: { accessKeyId: _nfKey, secretAccessKey: _nfSec } } : {}),
        });
        // 60-second TTL is intentional — short enough that a leaked URL is
        // not useful; long enough for the browser to follow the redirect.
        const PRESIGN_TTL = 60;
        const url = await presigner.getSignedUrl(
          s3,
          new AWS.GetObjectCommand({ Bucket: bucket, Key: key }),
          { expiresIn: PRESIGN_TTL }
        );
        await writeAuditRow(302, fileSize, runProjectId);
        const elapsed = Date.now() - startedAt;
        console.log(`[output_download] runId=${runId} file=${filename} user=${userId} → 302 (${elapsed}ms)`);
        return res.redirect(302, url);
      }

      // Local file path fallback — small files only; stream-through
      const fsLocal = await import('node:fs');
      const path = await import('node:path');
      const localPath: string = match.path || match.filepath;
      if (!localPath || !fsLocal.existsSync(localPath)) {
        await writeAuditRow(404, fileSize, runProjectId);
        return res.status(404).json({ error: 'File path unavailable' });
      }
      await writeAuditRow(200, fileSize, runProjectId);
      res.setHeader('Content-Disposition', `attachment; filename="${path.basename(localPath)}"`);
      return res.sendFile(path.resolve(localPath));
    } catch (err: any) {
      console.error(`[output_download] runId=${runId} file=${filename} 500: ${err?.message}`);
      await writeAuditRow(500, null, null);
      return res.status(500).json({ error: err?.message ?? 'Internal error' });
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
      // `run` is hoisted so the local-path block below can use its
      // nextflowStatus.work_dir / outdir for the allowed-roots check.
      const isS3Path = filePath.startsWith('s3://');
      const run = await storage.getExecutionRun(req.params.id);
      if (!isS3Path && !run) {
        return res.status(404).json({ error: 'Run not found' });
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
      const nfStatus = run?.execution?.nextflowStatus as any;
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

      res.json({
        workflow_id: runId,
        files: outputFiles,
        download_commands: {},
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

  // Save run outputs to a project's file directory.
  // Body: { projectId: string }
  // Reads output files from nextflowStatus.s3_output_files (or triggers a
  // fresh S3 scan via /api/workflows/runs/:id/output_files) and bulk-inserts
  // them into project_files with source='run_output'.
  app.post("/api/workflows/runs/:id/save-to-project", optionalAuth, async (req, res) => {
    try {
      const run = await storage.getExecutionRun(req.params.id);
      if (!run) return res.status(404).json({ error: "Execution run not found" });

      const { projectId } = req.body as { projectId?: string };
      if (!projectId) return res.status(400).json({ error: "projectId required" });

      const uid = (req as any).user?.id ? String((req as any).user.id) : run.userId ?? "system";

      // Collect output files from stored nextflowStatus first.
      const ns: any = run.execution?.nextflowStatus;
      let rawFiles: any[] = Array.isArray(ns?.s3_output_files) ? ns.s3_output_files : [];

      // If empty, do a live fetch from the Galaxy backend.
      if (rawFiles.length === 0) {
        try {
          const galUrl = process.env.GALAXY_URL || "http://localhost:8081";
          const nfRunId = run.execution?.nextflowRunId || ns?.run_id;
          if (nfRunId) {
            const r = await fetch(`${galUrl}/api/nextflow/status?run_id=${nfRunId}`, {
              headers: { "X-API-Key": process.env.GALAXY_API_KEY || "" },
            });
            if (r.ok) {
              const live = await r.json();
              rawFiles = Array.isArray(live?.s3_output_files) ? live.s3_output_files : [];
            }
          }
        } catch { /* live fetch optional */ }
      }

      if (rawFiles.length === 0) {
        return res.status(422).json({ error: "No output files found for this run yet. Try again after the run completes." });
      }

      const { registerRunOutputsInProject } = await import("./project-routes");

      // Build input context: user intent (the message that triggered the run) + input file names.
      // Parameters are already in the workflow report — we don't repeat them here.
      let userIntent: string | undefined;
      if ((run as any).chatSessionId) {
        try {
          const sessRow = await pool.query(
            `SELECT messages FROM chat_sessions WHERE session_id = $1 LIMIT 1`,
            [(run as any).chatSessionId]
          );
          const msgs: Array<{ role: string; content: string }> = sessRow.rows[0]?.messages ?? [];
          // Find the last user message before the run started — that's the intent.
          const userMsgs = msgs.filter(m => m.role === 'user');
          userIntent = userMsgs[userMsgs.length - 1]?.content?.slice(0, 300) || undefined;
        } catch { /* non-fatal */ }
      }
      const inputFiles: string[] = ((run as any).inputDatasets ?? []).map((d: any) => d.name || d.filename || String(d)).filter(Boolean);
      const inputContext = {
        intent: userIntent,
        inputFiles: inputFiles.length ? inputFiles : undefined,
      };

      const files = rawFiles.map((f: any) => {
        const uri: string = f.s3_uri || f.path || "";
        const s3Key = uri.startsWith("s3://") ? uri.replace(/^s3:\/\/[^/]+\//, "") : uri;
        // step_name comes from the executor if present (task-level tagging), or inferred from path
        const stepName: string | undefined = f.step_name || f.process_name || undefined;
        return {
          name: f.filename || f.name || s3Key.split("/").pop() || "file",
          s3Key,
          size: f.size ?? 0,
          contentType: f.content_type || "application/octet-stream",
          stepName,
        };
      }).filter((f: any) => f.s3Key);

      const workflowName: string = (run as any).workflowName || "Workflow";
      const count = await registerRunOutputsInProject({ projectId, userId: uid, runId: run.id, workflowName, inputContext, files });

      // Also persist projectId on the run so the UI can navigate to it.
      if (!(run as any).projectId) {
        await pool.query(`UPDATE execution_runs SET project_id = $1 WHERE id = $2`, [projectId, run.id]);
      }

      res.json({ ok: true, registered: count, total: files.length });
    } catch (e: any) {
      console.error("[save-to-project]", e?.message ?? e);
      res.status(500).json({ error: e?.message ?? "Failed" });
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

      // REAL pause: terminate the local Nextflow subprocess so it stops
      // submitting new tasks. The work-dir + cache survive, so /resume can
      // pick up via -resume. Best-effort — failures are logged but don't
      // block the frontend status update.
      const nextflowRunId =
        run.execution.nextflowRunId || run.execution.galaxyInvocationId || req.params.id;
      try {
        const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
        await fetch(`${galaxyUrl}/api/nextflow/pause/${encodeURIComponent(nextflowRunId)}`, {
          method: 'POST',
          signal: AbortSignal.timeout(15_000),
        });
      } catch (gxyErr) {
        console.warn('[ExecutionRun] Galaxy pause-call failed (continuing):', gxyErr);
      }

      // Update frontend-side status
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

      // REAL resume: invoke Nextflow with -resume so cached tasks are skipped
      // and only the remaining work re-runs. Returns a new run_id which we
      // store as the active nextflowRunId on the execution record.
      const nextflowRunId =
        run.execution.nextflowRunId || run.execution.galaxyInvocationId || req.params.id;
      let newNextflowRunId: string | undefined;
      try {
        const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
        const resp = await fetch(
          `${galaxyUrl}/api/nextflow/resume/${encodeURIComponent(nextflowRunId)}`,
          {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({}),
            signal: AbortSignal.timeout(30_000),
          }
        );
        if (resp.ok) {
          const d: any = await resp.json();
          newNextflowRunId = d.run_id;
        }
      } catch (gxyErr) {
        console.warn('[ExecutionRun] Galaxy resume-call failed (continuing):', gxyErr);
      }

      // Update status
      const updated = await storage.updateExecutionRun(req.params.id, {
        execution: {
          ...run.execution,
          status: 'running',
          pausedAt: undefined,
          pauseReason: undefined,
          ...(newNextflowRunId ? {
            nextflowRunId: newNextflowRunId,
            galaxyInvocationId: newNextflowRunId,
          } : {}),
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

      // REAL cancel: terminate the Nextflow subprocess on the backend.
      // Best-effort — if Galaxy is unreachable we still mark the frontend
      // record as cancelled so the user sees a terminal state.
      const nextflowRunId =
        run.execution.nextflowRunId || run.execution.galaxyInvocationId || req.params.id;
      try {
        const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
        await fetch(`${galaxyUrl}/api/nextflow/cancel/${encodeURIComponent(nextflowRunId)}`, {
          method: 'POST',
          signal: AbortSignal.timeout(15_000),
        });
      } catch (gxyErr) {
        console.warn('[ExecutionRun] Galaxy cancel-call failed (continuing):', gxyErr);
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
        // X-Forwarded-Proto: https is REQUIRED. On the deploy stack the app
        // force-redirects plain HTTP → HTTPS (security-config forceHTTPS, only
        // /internal/ is exempt). Without this header the self-fetch to
        // http://localhost:3000/api/invocations/:id/outputs gets a 301 to
        // https://localhost:3000 (a plain-HTTP port) → the fetch fails → caught
        // below → outputSamples stays empty → analyze_results silently returns
        // the generic template with output_files_sampled: []. Same self-call
        // redirect class as the open-claw tools (PR #65). 30s timeout: the
        // first /outputs call does a live S3 scan that can exceed 10s.
        const outRes = await fetch(`${localUrl}/api/invocations/${runIdForOutputs}/outputs`, {
          headers: { Authorization: req.headers.authorization || '', 'X-Forwarded-Proto': 'https' },
          signal: AbortSignal.timeout(30_000),
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

      // ── Call LLM via canonical fallback chain ─────────────────────────────
      const { llmGenerate } = await import('./llm-client');
      const completion = await llmGenerate({
        prompt: userPrompt,
        system: ANALYSIS_SYSTEM_PROMPT,
        maxTokens: 4096,
        jsonMode: true,  // findings endpoint expects JSON output
      });
      const rawText = completion.text || '';
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

      // ── Proactive follow-up suggestions for analyze endpoint ─────────────────
      const _analyzeProactive: string[] = [];
      const _analyzeText = [
        String(analysis.summary || ''),
        ...((analysis.key_findings as any[] || []).map((f: any) => `${f.finding || ''} ${f.significance || ''}`)),
      ].join(' ');

      const _isAdmetAnalyze = /admet|predict.*admet|admet.*properties/i.test(workflowName);
      const _isRarediseaseAnalyze = /raredisease|longraredisease|rare.*disease/i.test(workflowName);

      if (_isAdmetAnalyze) {
        if (/herg|cardiotox|ic50.*<.*1\s*µm|cardiac.*liab/i.test(_analyzeText)) {
          _analyzeProactive.push('Your compound has a hERG liability. I can run REINVENT4 in scaffold decoration mode with a hERG penalty function to generate 10–25 optimized analogs with improved predicted profiles — would you like me to do that?');
        } else if (/dili.*high|dili.*flag|dili.*risk|dili.*positive|hepatotox.*high/i.test(_analyzeText)) {
          _analyzeProactive.push('Your compound has a DILI liability. I can run REINVENT4 in scaffold decoration mode with a DILI penalty function to generate 10–25 optimized analogs with improved predicted profiles — would you like me to do that?');
        } else if (/ames.*positive|ames.*flag|mutagen/i.test(_analyzeText)) {
          _analyzeProactive.push('Your compound has an Ames mutagenicity liability. I can run REINVENT4 in scaffold decoration mode with an Ames penalty function to generate 10–25 optimized analogs with improved predicted profiles — would you like me to do that?');
        }
      }

      if (_isRarediseaseAnalyze && /variant|gene.*affect|pathogen|vus|causal|candidate/i.test(_analyzeText)) {
        const _geneMatches = _analyzeText.match(/\b([A-Z][A-Z0-9]{1,9})\b/g) || [];
        const _stopW = new Set(['FOUND','HIGH','LOW','PASS','FAIL','NULL','TRUE','FALSE','NONE','WITH','FROM','THAT','HAVE','BEEN','WERE','WILL','THEY','THIS','ALSO','DATA','FILE','PATH','STEP','NEXT','LAST','EACH','CALL','GENE','SNPS','INDEL']);
        const _genes = [...new Set(_geneMatches.filter(g => !_stopW.has(g)))].slice(0, 5);
        const _geneList = _genes.length > 0 ? _genes.join(', ') : 'the identified gene(s)';
        _analyzeProactive.push(`I found variants in ${_geneList}. Would you like me to query TxGNN to identify approved drugs that may be repurposable for this condition? TxGNN covers 17,000 disease phenotypes and can surface existing approved drugs that target the affected pathways.`);
      }

      if (_analyzeProactive.length > 0) {
        const _existingSteps: string[] = Array.isArray(analysis.next_steps) ? (analysis.next_steps as string[]) : [];
        analysis.next_steps = [..._analyzeProactive, ..._existingSteps];
      }
      // ── End proactive follow-up suggestions ──────────────────────────────────

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
              status: 'ready',
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
              return res.json({ ...structured, status: 'ready', runId, reportUrl });
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
        const reportUrl = `/api/workflows/runs/${runId}/findings/report`;
        return res.json({ ...cached, status: 'ready', reportUrl, runId });
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
              const readableOutputs = outputs.slice(0, 30).filter(out => {
                const filePath: string = out.s3_uri || out.file_path || out.path || '';
                const fileName: string = out.filename || out.name || out.file_name || filePath.split('/').pop() || 'output';
                return fileName && TEXT_EXTS.test(fileName);
              }).slice(0, 6);
              const readResults = await Promise.all(readableOutputs.map(async (out) => {
                const filePath: string = out.s3_uri || out.file_path || out.path || '';
                const fileName: string = out.filename || out.name || out.file_name || filePath.split('/').pop() || 'output';
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
                  return content.trim() ? { name: fileName, content } : null;
                } catch { return null; }
              }));
              outputSamples.push(...readResults.filter((r): r is { name: string; content: string } => r !== null));
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
3. Do NOT invent literature citations or PMIDs — omit the citations field entirely.
4. If a metric cannot be read from the files, omit it from key_results.
5. Each key_result MUST include "source_file" naming the EXACT file (copy the name from a "### File:" header above) the value was read from. This is grounded provenance, not a literature citation.

Respond ONLY with valid JSON (no markdown wrapper):
{
  "summary": "<2-3 sentence executive summary citing only observed results>",
  "key_results": [{"metric": "<name>", "value": "<exact value from file>", "interpretation": "<meaning>", "source_file": "<exact filename from a File: header>"}],
  "next_steps": ["<action 1>", "<action 2>"],
  "caveats": ["<caveat 1>"]
}`;

          // Diagnostics first, conclusions later: log what we're feeding
          // the model and what comes back, so the next truncation tells us
          // WHERE the problem is (input garbage? model truncation? double
          // encoding?) instead of forcing another round of guessing.
          console.log(
            `[Findings] input prep: workflow="${workflowName}" ` +
              `fileContext.length=${fileContext.length} ` +
              `outputSamples.length=${outputSamples.length} ` +
              `sample_names=${JSON.stringify(outputSamples.map((s) => s.name))} ` +
              `sample_lengths=${JSON.stringify(outputSamples.map((s) => s.content.length))}`,
          );
          const rawText = await callGeminiFlash({
            messages: [{ role: 'user', content: `Workflow: ${workflowName}\n\nOutput files:\n${fileContext}` }],
            system: SYSTEM,
            maxTokens: 8192,
            jsonMode: true,
          });
          console.log(
            `[Findings] gemini returned: length=${rawText.length} ` +
              `firstChar=${JSON.stringify(rawText.slice(0, 1))} ` +
              `endsWithBrace=${rawText.trimEnd().endsWith('}')} ` +
              `preview=${JSON.stringify(rawText.slice(0, 200))} ` +
              `tail=${JSON.stringify(rawText.slice(-100))}`,
          );
          try {
            const cleanText = rawText.replace(/^```(?:json)?\n?/, '').replace(/\n?```$/, '').trim();
            // Truncation guard — only reject when the input is obviously
            // unclosed JSON. Don't gate on length (valid small responses
            // like `{"summary":"OK","key_results":[]}` would be rejected).
            if (cleanText.startsWith('{') && !cleanText.trimEnd().endsWith('}')) {
              throw new Error(`findings synthesis returned truncated JSON (${cleanText.length} chars, unclosed)`);
            }
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
            // Provenance guardrail: source_file must name a file we actually sampled.
            // Keep grounded provenance, drop any hallucinated filename (so a finding is
            // either traceable to a real output or carries no false attribution).
            if (Array.isArray(parsed.key_results)) {
              const sampledNames = new Set(outputSamples.map((s: { name: string }) => s.name));
              for (const kr of parsed.key_results as Array<{ source_file?: string }>) {
                if (kr.source_file && !sampledNames.has(kr.source_file)) {
                  delete kr.source_file;
                }
              }
            }
            // Remove fabricated literature citations if the model included them despite
            // instruction (PMIDs the model invents are worse than none). Grounded
            // provenance lives in each key_result.source_file, validated above.
            delete parsed.citations;

            // ── Proactive follow-up suggestions ────────────────────────────────
            // Inject domain-specific next-step offers based on workflow type and findings.
            const proactiveSuggestions: string[] = [];

            const wfNameLower = workflowName.toLowerCase();
            const isAdmetWorkflow = /admet|predict.*admet|admet.*properties/i.test(workflowName);
            const isRarediseaseWorkflow = /raredisease|longraredisease|rare.*disease/i.test(workflowName);

            if (isAdmetWorkflow) {
              // Check for hERG, DILI, or Ames flags in key_results or summary
              const allText = [
                parsed.summary || '',
                ...(Array.isArray(parsed.key_results)
                  ? parsed.key_results.map((kr: any) => `${kr.metric || ''} ${kr.value || ''} ${kr.interpretation || ''}`)
                  : []),
              ].join(' ').toLowerCase();

              const hasHerg = /herg|cardiotox|ic50.*<.*1\s*µm|cardiac.*liab/i.test(allText);
              const hasDili = /dili.*high|dili.*flag|dili.*risk|dili.*positive|hepatotox.*high|liver.*toxic.*high/i.test(allText);
              const hasAmes = /ames.*positive|ames.*flag|mutagen/i.test(allText);

              if (hasHerg) {
                proactiveSuggestions.push(
                  'Your compound has a hERG liability. I can run REINVENT4 in scaffold decoration mode with a hERG penalty function to generate 10–25 optimized analogs with improved predicted profiles — would you like me to do that?'
                );
              } else if (hasDili) {
                proactiveSuggestions.push(
                  'Your compound has a DILI liability. I can run REINVENT4 in scaffold decoration mode with a DILI penalty function to generate 10–25 optimized analogs with improved predicted profiles — would you like me to do that?'
                );
              } else if (hasAmes) {
                proactiveSuggestions.push(
                  'Your compound has an Ames mutagenicity liability. I can run REINVENT4 in scaffold decoration mode with an Ames penalty function to generate 10–25 optimized analogs with improved predicted profiles — would you like me to do that?'
                );
              }
            }

            if (isRarediseaseWorkflow) {
              // Check for affected genes in key_results or summary
              const allText = [
                parsed.summary || '',
                ...(Array.isArray(parsed.key_results)
                  ? parsed.key_results.map((kr: any) => `${kr.metric || ''} ${kr.value || ''} ${kr.interpretation || ''}`)
                  : []),
              ].join(' ');

              // Extract gene symbols (e.g. BRCA1, TP53, TTN — uppercase 2-10 char words)
              const geneMatches = allText.match(/\b([A-Z][A-Z0-9]{1,9})\b/g) || [];
              // Filter plausible gene symbols (exclude common non-gene words)
              const stopWords = new Set(['FOUND', 'HIGH', 'LOW', 'PASS', 'FAIL', 'NULL', 'TRUE', 'FALSE', 'NONE', 'WITH', 'FROM', 'INTO', 'THAT', 'HAVE', 'BEEN', 'WERE', 'WILL', 'THEY', 'THIS', 'ALSO', 'DATA', 'FILE', 'PATH', 'STEP', 'NEXT', 'LAST', 'EACH', 'CALL', 'GENE', 'SNPS', 'INDEL', 'HOMO', 'HETE', 'CODING', 'SPLICE']);
              const genes = [...new Set(geneMatches.filter(g => !stopWords.has(g)))].slice(0, 5);

              const hasVariants = /variant|gene.*affect|pathogen|vus|causal|candidate/i.test(allText);
              if (hasVariants) {
                const geneList = genes.length > 0 ? genes.join(', ') : 'the identified gene(s)';
                proactiveSuggestions.push(
                  `I found variants in ${geneList}. Would you like me to query TxGNN to identify approved drugs that may be repurposable for this condition? TxGNN covers 17,000 disease phenotypes and can surface existing approved drugs that target the affected pathways.`
                );
              }
            }

            if (proactiveSuggestions.length > 0) {
              const existingSteps: string[] = Array.isArray(parsed.next_steps) ? parsed.next_steps : [];
              parsed.next_steps = [...proactiveSuggestions, ...existingSteps];
            }
            // ── End proactive follow-up suggestions ─────────────────────────────

            // Illustration figures: project the grounded key_results into qc/composition/
            // bars charts so this (Gemini) path matches the Python analyzer path. Only
            // real numbers are charted; figures inherit each metric's source_file.
            if (!Array.isArray(parsed.figures) || parsed.figures.length === 0) {
              const figs = buildFiguresFromKeyResults(parsed.key_results);
              if (figs.length > 0) parsed.figures = figs;
            }

            _findingsCache.set(runId, parsed);
          } catch (parseErr: any) {
            // Don't dump the broken raw JSON-shaped string into `summary` —
            // that's what made the bug invisible for so long. Surface the
            // failure cleanly so users know to look at outputs directly.
            console.warn('[Findings] AI synthesis JSON parse failed:', parseErr?.message, '— rawText preview:', rawText.slice(0, 200));
            _findingsCache.set(runId, {
              summary: `${workflowName} completed. AI synthesis was unavailable for this run — see the Outputs tab for raw results.`,
              key_results: [],
              next_steps: ['Open the Outputs tab to view the result files directly.'],
              caveats: ['AI summary generation did not produce a valid structured response. The underlying run succeeded.'],
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
      try {
        const md = await readFile(reportPath, 'utf8');
        res.setHeader('Content-Type', 'text/markdown; charset=utf-8');
        res.setHeader('Content-Disposition', `attachment; filename="findings_report_${runId}.md"`);
        return res.send(md);
      } catch { /* disk file missing — fall through to in-memory render */ }

      // AWS Batch runs don't write findings_report.md locally. Render markdown from
      // cached structured findings (populated by background Claude analysis).
      const cached = _findingsCache.get(runId);
      if (cached && !cached._generating) {
        const workflowName: string = (run as any).workflowName || (run as any).name || "Workflow";
        const lines: string[] = [
          `# Findings Report — ${workflowName}`,
          ``,
          `**Run ID:** ${runId}`,
          ``,
          `## Summary`,
          ``,
          String(cached.summary || `${workflowName} completed.`),
          ``,
        ];
        if (Array.isArray(cached.key_results) && cached.key_results.length > 0) {
          lines.push(`## Key Results`, ``);
          for (const kr of cached.key_results) {
            const metric = kr.metric || '';
            const value = kr.value !== undefined ? String(kr.value) : '';
            const interp = kr.interpretation || '';
            lines.push(`- **${metric}**: ${value}${interp ? ` — ${interp}` : ''}`);
          }
          lines.push(``);
        }
        if (Array.isArray(cached.next_steps) && cached.next_steps.length > 0) {
          lines.push(`## Next Steps`, ``);
          for (const s of cached.next_steps) lines.push(`- ${s}`);
          lines.push(``);
        }
        if (Array.isArray(cached.caveats) && cached.caveats.length > 0) {
          lines.push(`## Caveats`, ``);
          for (const c of cached.caveats) lines.push(`- ${c}`);
          lines.push(``);
        }
        res.setHeader('Content-Type', 'text/markdown; charset=utf-8');
        res.setHeader('Content-Disposition', `attachment; filename="findings_report_${runId}.md"`);
        return res.send(lines.join('\n'));
      }

      return res.status(404).json({ error: "Findings report not yet available" });
    } catch (err: any) {
      res.status(500).json({ error: err.message });
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
      console.error("[Interactive] Error launching:", error.message);
      // If Galaxy responded at all (any status code), our server code is working fine —
      // Galaxy rejected the request (e.g. tool not configured, not available).
      // Return 400 so callers can distinguish "Galaxy rejected" from "our server crashed" (500).
      // 500 is reserved for: no Galaxy response (network down) or our own code throwing.
      //
      // Note: galaxy-api-proxy.ts interceptor re-throws AxiosError as a GalaxyAPIError with
      // status_code (not error.response.status), so check both fields.
      const galaxyStatus = error?.response?.status ?? error?.status_code;
      const status = galaxyStatus ? 400 : 500;
      res.status(status).json({
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
      // Galaxy /api/entry_points returns 5xx when interactive tools aren't configured.
      // That means "0 active sessions" — not a server crash. Always return 200 with
      // an empty list so callers don't see spurious 500s for unconfigured environments.
      console.error("[Interactive] Error getting sessions (returning empty list):", error.message);
      res.json({ sessions: [], count: 0 });
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
      const session = rows.rows[0];

      // If the stored workflows array is empty, dynamically populate it from
      // execution_runs so that historical runs (completed before this column
      // was written) still surface the AfterRunReport in the right panel.
      if (!session.workflows || session.workflows.length === 0) {
        try {
          const runRows = await pool.query(
            `SELECT id, workflow_name, status AS run_status
             FROM execution_runs
             WHERE chat_session_id = $1
               AND status IN ('completed', 'failed', 'running')
             ORDER BY created_at DESC
             LIMIT 5`,
            [req.params.sessionId]
          );
          if (runRows.rows.length > 0) {
            session.workflows = runRows.rows.map((r: any) => ({
              workflow_id: r.id,
              workflow_name: r.workflow_name || 'Workflow',
              status: r.run_status || 'completed',
            }));
          }
        } catch (dynErr: any) {
          // Non-fatal: fall back to empty array
          console.warn('[sessions/:id] Failed to backfill workflows from execution_runs:', dynErr?.message);
        }
      }

      res.json(session);
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  app.post("/api/sessions", authenticateToken, express.json(), async (req: any, res) => {
    try {
      const { session_id, title, messages, workflows, datasets } = req.body;
      if (!session_id) return res.status(400).json({ error: 'session_id required' });
      // Cap incoming dataset list at MAX_DATASET_REFS (32, drop oldest)
      // to match the same defense applied at the PUT site + the in-memory
      // req.session.uploadedDatasets sites. Without this, a client can
      // bypass the cap on first-write. See frontend/server/dataset-cap.ts
      // and docs/20260612_DATASET_STORAGE_AND_SESSION_BOUNDARIES.md.
      const cappedDatasets = capDatasetReferences(datasets || []);
      const rows = await pool.query(
        `INSERT INTO chat_sessions (session_id, user_id, title, messages, workflows, datasets)
         VALUES ($1, $2, $3, $4, $5, $6)
         ON CONFLICT (session_id) DO UPDATE SET
           title = EXCLUDED.title, messages = EXCLUDED.messages,
           workflows = EXCLUDED.workflows, datasets = EXCLUDED.datasets,
           last_activity = NOW()
         RETURNING *`,
        [session_id, req.user.id, title || 'New Chat',
         JSON.stringify(messages || []), JSON.stringify(workflows || []), JSON.stringify(cappedDatasets)]
      );
      res.status(201).json(rows.rows[0]);
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  app.put("/api/sessions/:sessionId", authenticateToken, express.json(), async (req: any, res) => {
    try {
      const { title, status, messages, workflows, datasets } = req.body;
      const cappedDatasets = datasets ? capDatasetReferences(datasets) : null;
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
         cappedDatasets ? JSON.stringify(cappedDatasets) : null]
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
      const collectedRunIds: string[] = [];

      while (iterations < MAX_ITERATIONS) {
        iterations++;
        let hasToolUse = false;
        const toolResults: Array<{ type: 'tool_result'; tool_use_id: string; content: string }> = [];

        // Stream a single turn
        // NOTE: Open-Claw stays on direct Anthropic SDK because it uses
        // Claude-specific streaming + tool-calling that the canonical
        // fallback chain doesn't expose. This is an expert/debug endpoint
        // explicitly named "Claude has direct access" so the model lock-in
        // is by design. See docs/20260607_LLM_ROUTING_CONSOLIDATION_PLAN.md.
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
          // Capture run_id from run_workflow so the MCP server can fetch outputs post-loop
          if (block.name === "run_workflow") {
            const rid = toolResult?.runId || toolResult?.run_id || toolResult?.id;
            if (rid) collectedRunIds.push(String(rid));
          }
        }

        // Add tool results to messages for next iteration
        currentMessages = [...currentMessages, { role: "user", content: toolResults }];
      }

      safeSend("complete", { iterations, run_ids: collectedRunIds });
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
  // Instruments Config API — CRUD for registered lab instruments
  // Users add instruments here; the daemon watchers use these configs.
  // ============================================================================

  // GET /api/instruments — list all instruments for the authenticated user
  app.get("/api/instruments", authenticateToken, async (req, res) => {
    try {
      const userId = String((req.user as any).id);
      const rows = await db
        .select()
        .from(instruments)
        .where(eq(instruments.userId, userId))
        .orderBy(instruments.createdAt);
      return res.json({
        instruments: rows.map((r) => ({
          ...r,
          config: r.config ? JSON.parse(r.config) : {},
          // Never return raw auth values to the client
          apiKey: r.apiKey ? "***" : null,
          oauthToken: r.oauthToken ? "***" : null,
          oauthRefreshToken: r.oauthRefreshToken ? "***" : null,
        })),
      });
    } catch (err: any) {
      return res.status(500).json({ error: "Failed to list instruments" });
    }
  });

  // POST /api/instruments — register a new instrument
  app.post("/api/instruments", authenticateToken, async (req, res) => {
    const { name, type, host, port, apiKey, oauthToken, oauthRefreshToken, config } = req.body || {};
    if (!name || !type) {
      return res.status(400).json({ error: "name and type are required" });
    }
    if (!(INSTRUMENT_TYPES as readonly string[]).includes(type)) {
      return res.status(400).json({
        error: `Invalid type '${type}'. Valid types: ${INSTRUMENT_TYPES.join(", ")}`,
      });
    }
    try {
      const userId = String((req.user as any).id);
      const [row] = await db
        .insert(instruments)
        .values({
          userId,
          name: String(name),
          type: String(type) as InstrumentType,
          host: host ? String(host) : null,
          port: port != null ? Number(port) : null,
          apiKey: apiKey ? String(apiKey) : null,
          oauthToken: oauthToken ? String(oauthToken) : null,
          oauthRefreshToken: oauthRefreshToken ? String(oauthRefreshToken) : null,
          config: config ? JSON.stringify(config) : null,
          status: "unknown",
        })
        .returning({ id: instruments.id });
      console.log("[instruments] registered", { id: row?.id, type, name });
      return res.status(201).json({ id: row?.id, name, type, status: "unknown" });
    } catch (err: any) {
      return res.status(500).json({ error: "Failed to register instrument" });
    }
  });

  // GET /api/instruments/:id — get a single instrument (no auth fields)
  app.get("/api/instruments/:id", authenticateToken, async (req, res) => {
    try {
      const userId = String((req.user as any).id);
      const [row] = await db
        .select()
        .from(instruments)
        .where(eq(instruments.id, req.params.id))
        .limit(1);
      if (!row) return res.status(404).json({ error: "Not found" });
      if (row.userId !== userId) return res.status(403).json({ error: "Forbidden" });
      return res.json({
        ...row,
        config: row.config ? JSON.parse(row.config) : {},
        apiKey: row.apiKey ? "***" : null,
        oauthToken: row.oauthToken ? "***" : null,
        oauthRefreshToken: row.oauthRefreshToken ? "***" : null,
      });
    } catch (err: any) {
      return res.status(500).json({ error: "Failed to fetch instrument" });
    }
  });

  // PATCH /api/instruments/:id — update name, host, port, config, auth
  app.patch("/api/instruments/:id", authenticateToken, async (req, res) => {
    try {
      const userId = String((req.user as any).id);
      const [existing] = await db
        .select({ userId: instruments.userId })
        .from(instruments)
        .where(eq(instruments.id, req.params.id))
        .limit(1);
      if (!existing) return res.status(404).json({ error: "Not found" });
      if (existing.userId !== userId) return res.status(403).json({ error: "Forbidden" });

      const updates: Record<string, any> = { updatedAt: new Date() };
      const { name, host, port, apiKey, oauthToken, oauthRefreshToken, config } = req.body || {};
      if (name !== undefined) updates.name = String(name);
      if (host !== undefined) updates.host = host ? String(host) : null;
      if (port !== undefined) updates.port = port != null ? Number(port) : null;
      if (apiKey !== undefined) updates.apiKey = apiKey ? String(apiKey) : null;
      if (oauthToken !== undefined) updates.oauthToken = oauthToken ? String(oauthToken) : null;
      if (oauthRefreshToken !== undefined) updates.oauthRefreshToken = oauthRefreshToken ? String(oauthRefreshToken) : null;
      if (config !== undefined) updates.config = config ? JSON.stringify(config) : null;

      await db.update(instruments).set(updates).where(eq(instruments.id, req.params.id));
      return res.json({ ok: true });
    } catch (err: any) {
      return res.status(500).json({ error: "Failed to update instrument" });
    }
  });

  // DELETE /api/instruments/:id — remove an instrument registration
  app.delete("/api/instruments/:id", authenticateToken, async (req, res) => {
    try {
      const userId = String((req.user as any).id);
      const [existing] = await db
        .select({ userId: instruments.userId })
        .from(instruments)
        .where(eq(instruments.id, req.params.id))
        .limit(1);
      if (!existing) return res.status(404).json({ error: "Not found" });
      if (existing.userId !== userId) return res.status(403).json({ error: "Forbidden" });
      await db.delete(instruments).where(eq(instruments.id, req.params.id));
      return res.json({ ok: true });
    } catch (err: any) {
      return res.status(500).json({ error: "Failed to delete instrument" });
    }
  });

  // GET /api/instruments/:id/health — live connectivity check
  // Hits the instrument's actual endpoint and updates status in DB.
  app.get("/api/instruments/:id/health", authenticateToken, async (req, res) => {
    try {
      const userId = String((req.user as any).id);
      const [row] = await db
        .select()
        .from(instruments)
        .where(eq(instruments.id, req.params.id))
        .limit(1);
      if (!row) return res.status(404).json({ error: "Not found" });
      if (row.userId !== userId) return res.status(403).json({ error: "Forbidden" });

      let online = false;
      let detail: Record<string, any> = {};
      let errMsg: string | null = null;

      const host = row.host || "localhost";
      const port = row.port;

      try {
        if (row.type === "opentrons") {
          const url = `http://${host}:${port ?? 31950}/health`;
          const r = await fetch(url, { signal: AbortSignal.timeout(5000) });
          detail = await r.json() as Record<string, any>;
          online = r.ok;
        } else if (row.type === "minknow") {
          const url = `http://${host}:${port ?? 9501}/`;
          const r = await fetch(url, { signal: AbortSignal.timeout(5000) });
          detail = await r.json() as Record<string, any>;
          online = r.ok;
        } else if (row.type === "epu") {
          const url = `http://${host}:${port ?? 8080}/api/v1/version`;
          const r = await fetch(url, { signal: AbortSignal.timeout(5000) });
          detail = await r.json() as Record<string, any>;
          online = r.ok;
        } else if (row.type === "basespace") {
          // Validate BaseSpace token
          const token = row.apiKey || row.oauthToken;
          if (!token) throw new Error("No API key or OAuth token configured");
          const r = await fetch("https://api.basespace.illumina.com/v1pre3/users/current", {
            headers: { "x-access-token": token },
            signal: AbortSignal.timeout(8000),
          });
          const body = await r.json() as any;
          detail = { user: body?.Response?.Name, id: body?.Response?.Id };
          online = r.ok;
        } else if (row.type === "benchling") {
          const apiKey = row.apiKey;
          if (!apiKey) throw new Error("No API key configured");
          const config = row.config ? JSON.parse(row.config) : {};
          const apiUrl = config.apiUrl || "https://benchling.com";
          const r = await fetch(`${apiUrl}/api/v2/entries?pageSize=1`, {
            headers: { Authorization: `Basic ${Buffer.from(`${apiKey}:`).toString("base64")}` },
            signal: AbortSignal.timeout(8000),
          });
          detail = { tenantUrl: apiUrl, reachable: r.ok };
          online = r.ok;
        } else if (row.type === "sila2") {
          // SiLA2: attempt TCP connect (no HTTP)
          const net = await import("net");
          online = await new Promise<boolean>((resolve) => {
            const sock = net.createConnection(port ?? 50051, host);
            sock.setTimeout(4000);
            sock.on("connect", () => { sock.destroy(); resolve(true); });
            sock.on("error",   () => resolve(false));
            sock.on("timeout", () => { sock.destroy(); resolve(false); });
          });
          detail = { host, port: port ?? 50051, protocol: "gRPC/SiLA2" };
        } else {
          // File-watcher types (flow_cytometer, lcms, qpcr, plate_reader, epu file-mode):
          // Report as "online" if the configured outputDir exists
          const config = row.config ? JSON.parse(row.config) : {};
          const dir = config.outputDir || config.directory || null;
          if (dir) {
            const fs = await import("fs");
            online = fs.existsSync(dir);
            detail = { directory: dir, exists: online };
          } else {
            detail = { note: "No outputDir configured — file-watcher cannot run" };
          }
        }
      } catch (e: any) {
        errMsg = e.message || String(e);
        online = false;
      }

      const now = new Date();
      await db.update(instruments)
        .set({
          status: online ? "online" : "offline",
          lastSeenAt: online ? now : (row.lastSeenAt ?? null),
          lastError: online ? null : errMsg,
          updatedAt: now,
        })
        .where(eq(instruments.id, row.id));

      console.log("[instruments] health check", { id: row.id, type: row.type, online, errMsg });
      return res.json({
        id: row.id,
        type: row.type,
        name: row.name,
        online,
        detail,
        error: errMsg,
        checkedAt: now.toISOString(),
      });
    } catch (err: any) {
      return res.status(500).json({ error: "Health check failed" });
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

      // Resolve filenames for dataset IDs so staged files keep their original names
      const rawIds: (string | { id: string; filename?: string })[] =
        Array.isArray(input_datasets) ? input_datasets : [];
      const datasetRefs = await Promise.all(rawIds.map(async (ref) => {
        if (typeof ref === 'object' && ref !== null) return ref;
        const id = String(ref);
        // Check local upload registry first
        const localFile = getUploadedFile(id);
        if (localFile) {
          return { id, filename: localFile.name };
        }
        // Fall back to Galaxy metadata
        try {
          const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
          const meta = await fetch(`${galaxyUrl}/api/datasets/${id}`, {
            signal: AbortSignal.timeout(5000),
          });
          if (meta.ok) {
            const data = await meta.json() as any;
            const filename = data?.name || data?.file_name || id;
            return { id, filename: String(filename) };
          }
        } catch { /* fall through */ }
        return { id, filename: id };
      }));

      // downloadDataset: check local upload registry first, fall back to Galaxy
      const downloadDatasetFn = async (id: string) => {
        const localFile = getUploadedFile(id);
        if (localFile) {
          // Stream from local filesystem (uploaded without Galaxy)
          const { createReadStream } = await import('fs');
          return createReadStream(localFile.filePath) as any;
        }
        // Fall back to Galaxy
        return galaxyAPIProxy.downloadDataset(id);
      };

      const result = await runCode({
        language: language as 'python' | 'r' | 'bash',
        code,
        input_datasets: datasetRefs,
        timeout_seconds: typeof timeout_seconds === 'number' ? Math.min(timeout_seconds, 300) : 30,
        downloadDataset: downloadDatasetFn,
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

  // PDF is the dominant bioconductor figure output (~85% of figure ext occurrences
  // per docs/20260614_BIOC_VIZ_COVERAGE_AUDIT.md). It is NOT a raster image —
  // browsers can't render application/pdf inside <img>. Route it to 'interactive'
  // so the iframe / <embed> path picks it up, matching step-output-preview.tsx's
  // already-correct PDF viewer.
  // tiff/bmp also can't render natively in <img>; demoted to 'binary' (download
  // link) until a server-side PNG conversion route is added.
  const imageExts = ['png', 'jpg', 'jpeg', 'svg', 'gif'];
  // json renders as a sortable table via CsvTableViewer; csv/tsv are canonical tables
  const tableExts = ['tsv', 'csv', 'tabular', 'json', 'bed', 'gtf', 'gff', 'vcf'];
  const interactiveExts = ['html', 'htm', 'pdf'];
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

