import {
  type User,
  type InsertUser,
  type WorkflowInvocation,
  type CreateInvocation,
  type OutputDataset,
  type ExecutionRun,
  type ExecutionRunStatus,
  type StepExecution,
  type UserInteraction,
  type DataScope,
  type VersionedParameters,
  type ExecutionMetrics,
  type RunComparison,
  type CreateExecutionRunRequest,
  type CreateExecutionRunResponse,
  type ExecutionRunStatusResponse,
  type RunComparisonResponse,
} from "@shared/schema";
import { randomUUID } from "crypto";

// modify the interface with any CRUD methods
// you might need

export interface IStorage {
  // User management
  getUser(id: string): Promise<User | undefined>;
  getUserByUsername(username: string): Promise<User | undefined>;
  createUser(user: InsertUser): Promise<User>;

  // Invocation management
  createInvocation(invocation: Partial<WorkflowInvocation>): Promise<WorkflowInvocation>;
  getInvocation(id: string): Promise<WorkflowInvocation | undefined>;
  getInvocationByGalaxyId(galaxyInvocationId: string): Promise<WorkflowInvocation | undefined>;
  getInvocations(userId?: string, limit?: number): Promise<WorkflowInvocation[]>;
  updateInvocation(id: string, updates: Partial<WorkflowInvocation>): Promise<WorkflowInvocation | undefined>;
  deleteInvocation(id: string): Promise<boolean>;

  // Output dataset management
  addOutput(output: Partial<OutputDataset>): Promise<OutputDataset>;
  getOutput(id: string): Promise<OutputDataset | undefined>;
  getInvocationOutputs(invocationId: string): Promise<OutputDataset[]>;
  deleteOutput(id: string): Promise<boolean>;

  // ExecutionRun management (Unified Workflow Execution)
  createExecutionRun(request: CreateExecutionRunRequest, userId?: string, projectId?: string): Promise<ExecutionRun>;
  getExecutionRun(id: string): Promise<ExecutionRun | undefined>;
  getExecutionRunByGalaxyId(galaxyInvocationId: string): Promise<ExecutionRun | undefined>;
  getExecutionRuns(
    userId?: string,
    projectId?: string,
    mode?: 'sandbox' | 'production',
    limit?: number,
    chatSessionId?: string
  ): Promise<ExecutionRun[]>;
  getExecutionRunsByParent(parentRunId: string): Promise<ExecutionRun[]>;
  updateExecutionRun(id: string, updates: Partial<ExecutionRun>): Promise<ExecutionRun | undefined>;
  updateExecutionRunStatus(id: string, status: ExecutionRunStatus, errorMessage?: string): Promise<ExecutionRun | undefined>;
  updateExecutionRunProgress(id: string, completedSteps: number, currentStepIndex?: number, currentStepName?: string): Promise<ExecutionRun | undefined>;
  updateExecutionRunStep(id: string, stepId: string, stepUpdates: Partial<StepExecution>): Promise<ExecutionRun | undefined>;
  addExecutionRunInteraction(id: string, interaction: UserInteraction): Promise<ExecutionRun | undefined>;
  updateExecutionRunMetrics(id: string, metrics: Partial<ExecutionMetrics>): Promise<ExecutionRun | undefined>;
  setExecutionRunComparison(id: string, comparison: RunComparison): Promise<ExecutionRun | undefined>;
  deleteExecutionRun(id: string): Promise<boolean>;
  compareExecutionRuns(runId1: string, runId2: string): Promise<RunComparisonResponse | undefined>;
}

export class MemStorage implements IStorage {
  private users: Map<string, User>;
  private invocations: Map<string, WorkflowInvocation>;
  private outputs: Map<string, OutputDataset>;
  private executionRuns: Map<string, ExecutionRun>;

  constructor() {
    this.users = new Map();
    this.invocations = new Map();
    this.outputs = new Map();
    this.executionRuns = new Map();
  }

  // User management
  async getUser(id: string): Promise<User | undefined> {
    return this.users.get(id);
  }

  async getUserByUsername(username: string): Promise<User | undefined> {
    return Array.from(this.users.values()).find(
      (user) => user.email === username,
    );
  }

  async createUser(insertUser: InsertUser): Promise<User> {
    const id = randomUUID();
    const user = { ...insertUser, id } as User;
    this.users.set(id, user);
    return user;
  }

  // Invocation management
  async createInvocation(data: Partial<WorkflowInvocation>): Promise<WorkflowInvocation> {
    const id = randomUUID();
    const now = new Date();

    const invocation: WorkflowInvocation = {
      id,
      userId: data.userId,
      workflowId: data.workflowId,
      workflowName: data.workflowName || 'Untitled Workflow',
      workflowDefinition: data.workflowDefinition || {},
      status: data.status || 'new',
      createdAt: now,
      updatedAt: now,
      completedAt: data.completedAt,
      galaxyInvocationId: data.galaxyInvocationId || '',
      galaxyHistoryId: data.galaxyHistoryId || '',
      galaxyWorkflowId: data.galaxyWorkflowId,
      totalSteps: data.totalSteps || 0,
      completedSteps: data.completedSteps || 0,
      currentStepIndex: data.currentStepIndex,
      currentStepName: data.currentStepName,
      errorMessage: data.errorMessage,
      errorStep: data.errorStep,
      inputDatasets: data.inputDatasets || [],
      outputDatasets: data.outputDatasets || [],
      executionLogs: data.executionLogs,
      outputCount: data.outputCount || 0,
      totalOutputSize: data.totalOutputSize || 0,
    };

    this.invocations.set(id, invocation);
    return invocation;
  }

  async getInvocation(id: string): Promise<WorkflowInvocation | undefined> {
    return this.invocations.get(id);
  }

  async getInvocationByGalaxyId(galaxyInvocationId: string): Promise<WorkflowInvocation | undefined> {
    return Array.from(this.invocations.values()).find(inv => inv.galaxyInvocationId === galaxyInvocationId);
  }

  async getInvocations(userId?: string, limit: number = 100): Promise<WorkflowInvocation[]> {
    // If no userId provided, return empty array for security
    // This prevents unauthenticated users from seeing all invocations
    if (!userId) {
      return [];
    }

    let invocations = Array.from(this.invocations.values());

    // Filter by userId
    invocations = invocations.filter(inv => inv.userId === userId);

    // Sort by created date (newest first)
    invocations.sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime());

    // Limit results
    return invocations.slice(0, limit);
  }

  async updateInvocation(id: string, updates: Partial<WorkflowInvocation>): Promise<WorkflowInvocation | undefined> {
    const existing = this.invocations.get(id);
    if (!existing) return undefined;

    const updated: WorkflowInvocation = {
      ...existing,
      ...updates,
      id, // Ensure ID doesn't change
      updatedAt: new Date(),
    };

    this.invocations.set(id, updated);
    return updated;
  }

  async deleteInvocation(id: string): Promise<boolean> {
    // Also delete associated outputs
    const outputs = await this.getInvocationOutputs(id);
    for (const output of outputs) {
      this.outputs.delete(output.id);
    }

    return this.invocations.delete(id);
  }

  // Output dataset management
  async addOutput(data: Partial<OutputDataset>): Promise<OutputDataset> {
    const id = randomUUID();
    const now = new Date();

    const output: OutputDataset = {
      id,
      invocationId: data.invocationId || '',
      galaxyDatasetId: data.galaxyDatasetId || '',
      name: data.name || 'output',
      extension: data.extension || 'txt',
      size: data.size || 0,
      createdAt: now,
      fileType: data.fileType || 'binary',
      isVisualizable: data.isVisualizable || false,
      previewAvailable: data.previewAvailable || false,
      metadata: data.metadata,
    };

    this.outputs.set(id, output);

    // Update invocation's output count and size
    const invocation = await this.getInvocation(output.invocationId);
    if (invocation) {
      await this.updateInvocation(output.invocationId, {
        outputCount: invocation.outputCount + 1,
        totalOutputSize: invocation.totalOutputSize + output.size,
        outputDatasets: [...invocation.outputDatasets, output],
      });
    }

    return output;
  }

  async getOutput(id: string): Promise<OutputDataset | undefined> {
    return this.outputs.get(id);
  }

  async getInvocationOutputs(invocationId: string): Promise<OutputDataset[]> {
    return Array.from(this.outputs.values())
      .filter(output => output.invocationId === invocationId)
      .sort((a, b) => a.createdAt.getTime() - b.createdAt.getTime());
  }

  async deleteOutput(id: string): Promise<boolean> {
    const output = this.outputs.get(id);
    if (!output) return false;

    // Update invocation's output count and size
    const invocation = await this.getInvocation(output.invocationId);
    if (invocation) {
      await this.updateInvocation(output.invocationId, {
        outputCount: Math.max(0, invocation.outputCount - 1),
        totalOutputSize: Math.max(0, invocation.totalOutputSize - output.size),
        outputDatasets: invocation.outputDatasets.filter(o => o.id !== id),
      });
    }

    return this.outputs.delete(id);
  }

  // ============================================================================
  // ExecutionRun Management (Unified Workflow Execution)
  // ============================================================================

  async createExecutionRun(
    request: CreateExecutionRunRequest,
    userId?: string,
    projectId?: string
  ): Promise<ExecutionRun> {
    const id = randomUUID();
    const now = new Date();
    const config = request.executionConfig;

    // Calculate run sequence if this is an iteration
    let runSequence = 1;
    if (config.parentRunId) {
      const siblings = await this.getExecutionRunsByParent(config.parentRunId);
      runSequence = siblings.length + 1;
    }

    // Extract workflow name from definition
    const workflowName = request.workflowDefinition?.name ||
                         request.workflowDefinition?.annotation ||
                         'Untitled Workflow';

    // Count total steps from workflow definition
    const totalSteps = request.workflowDefinition?.steps
      ? Object.keys(request.workflowDefinition.steps).length
      : 0;

    // Build initial steps array from workflow definition
    const steps: StepExecution[] = [];
    if (request.workflowDefinition?.steps) {
      const stepEntries = Object.entries(request.workflowDefinition.steps);
      stepEntries.forEach(([stepId, stepDef]: [string, any], index) => {
        steps.push({
          stepId,
          stepIndex: index,
          stepName: stepDef.label || stepDef.name || `Step ${index + 1}`,
          toolId: stepDef.tool_id || 'unknown',
          toolName: stepDef.name,
          status: 'pending',
          outputs: [],
        });
      });
    }

    // Extract tool parameters from workflow definition
    const toolParameters: Record<string, Record<string, any>> = {};
    if (request.workflowDefinition?.steps) {
      Object.entries(request.workflowDefinition.steps).forEach(([stepId, stepDef]: [string, any]) => {
        if (stepDef.tool_state) {
          try {
            const state = typeof stepDef.tool_state === 'string'
              ? JSON.parse(stepDef.tool_state)
              : stepDef.tool_state;
            toolParameters[stepDef.tool_id || stepId] = state;
          } catch {
            // Ignore parse errors
          }
        }
      });
    }

    const executionRun: ExecutionRun = {
      id,
      parentRunId: config.parentRunId,
      runSequence,
      userId,
      projectId,
      chatSessionId: request.chatSessionId,

      mode: config.mode || 'sandbox',
      workflowName,
      workflowDefinition: request.workflowDefinition,

      dataScope: {
        fraction: config.dataScope?.fraction ?? 1.0,
        absoluteCount: config.dataScope?.absoluteCount,
        totalAvailable: config.dataScope?.totalAvailable,
        samplingStrategy: config.dataScope?.samplingStrategy || 'random',
        sampledIds: config.dataScope?.sampledIds || [],
        strataDistribution: config.dataScope?.strataDistribution,
        strataColumn: config.dataScope?.strataColumn,
        explicitSamples: config.dataScope?.explicitSamples,
      },

      parameters: {
        version: 1,
        toolParameters,
        changedFrom: undefined,
      },

      execution: {
        galaxyInvocationId: undefined,
        galaxyHistoryId: undefined,
        galaxyWorkflowId: undefined,
        executionEngine: config.executionEngine,
        status: 'configuring',
        startedAt: undefined,
        completedAt: undefined,
        pausedAt: undefined,
        pauseReason: undefined,
        errorMessage: undefined,
      },

      progress: {
        totalSteps,
        completedSteps: 0,
        currentStepIndex: undefined,
        currentStepName: undefined,
        percentComplete: 0,
        milestone: undefined,
      },

      steps,
      metrics: {
        runtime: { totalSeconds: 0, perStepSeconds: {} },
        resources: { peakMemoryGB: 0, avgCpuPercent: 0, diskUsedGB: 0 },
        quality: {},
        outputs: { fileCount: 0, totalSizeBytes: 0, byType: {}, bySize: {} },
      },
      interactions: [],
      recommendations: [],
      comparison: undefined,

      createdAt: now,
      updatedAt: now,
    };

    this.executionRuns.set(id, executionRun);
    return executionRun;
  }

  async getExecutionRun(id: string): Promise<ExecutionRun | undefined> {
    return this.executionRuns.get(id);
  }

  async getExecutionRunByGalaxyId(galaxyInvocationId: string): Promise<ExecutionRun | undefined> {
    return Array.from(this.executionRuns.values()).find(
      run => run.execution.galaxyInvocationId === galaxyInvocationId
    );
  }

  async getExecutionRuns(
    userId?: string,
    projectId?: string,
    mode?: 'sandbox' | 'production',
    limit: number = 100,
    chatSessionId?: string
  ): Promise<ExecutionRun[]> {
    let runs = Array.from(this.executionRuns.values());

    // Filter by userId if provided
    if (userId) {
      runs = runs.filter(run => run.userId === userId);
    }

    // Filter by projectId if provided
    if (projectId) {
      runs = runs.filter(run => run.projectId === projectId);
    }

    // Filter by mode if provided
    if (mode) {
      runs = runs.filter(run => run.mode === mode);
    }

    // Filter by chat session if provided
    if (chatSessionId) {
      runs = runs.filter(run => run.chatSessionId === chatSessionId);
    }

    // Sort by created date (newest first)
    runs.sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime());

    return runs.slice(0, limit);
  }

  async getExecutionRunsByParent(parentRunId: string): Promise<ExecutionRun[]> {
    const runs = Array.from(this.executionRuns.values())
      .filter(run => run.parentRunId === parentRunId);

    // Sort by run sequence
    runs.sort((a, b) => a.runSequence - b.runSequence);

    return runs;
  }

  async updateExecutionRun(id: string, updates: Partial<ExecutionRun>): Promise<ExecutionRun | undefined> {
    const existing = this.executionRuns.get(id);
    if (!existing) return undefined;

    const updated: ExecutionRun = {
      ...existing,
      ...updates,
      id, // Ensure ID doesn't change
      updatedAt: new Date(),
    };

    this.executionRuns.set(id, updated);
    return updated;
  }

  async updateExecutionRunStatus(
    id: string,
    status: ExecutionRunStatus,
    errorMessage?: string
  ): Promise<ExecutionRun | undefined> {
    const existing = this.executionRuns.get(id);
    if (!existing) return undefined;

    const now = new Date();
    const updates: Partial<ExecutionRun> = {
      execution: {
        ...existing.execution,
        status,
        errorMessage,
      },
      updatedAt: now,
    };

    // Set timestamps based on status
    if (status === 'running' && !existing.execution.startedAt) {
      updates.execution!.startedAt = now;
    } else if (status === 'completed' || status === 'failed' || status === 'cancelled') {
      updates.execution!.completedAt = now;
    } else if (status === 'paused') {
      updates.execution!.pausedAt = now;
    }

    return this.updateExecutionRun(id, updates);
  }

  async updateExecutionRunProgress(
    id: string,
    completedSteps: number,
    currentStepIndex?: number,
    currentStepName?: string
  ): Promise<ExecutionRun | undefined> {
    const existing = this.executionRuns.get(id);
    if (!existing) return undefined;

    const totalSteps = existing.progress.totalSteps;
    const percentComplete = totalSteps > 0 ? Math.round((completedSteps / totalSteps) * 100) : 0;

    // Determine milestone
    let milestone: number | undefined = existing.progress.milestone;
    const milestones = [25, 50, 75, 100];
    for (const m of milestones) {
      if (percentComplete >= m && (!milestone || m > milestone)) {
        milestone = m;
      }
    }

    return this.updateExecutionRun(id, {
      progress: {
        ...existing.progress,
        completedSteps,
        currentStepIndex,
        currentStepName,
        percentComplete,
        milestone,
      },
    });
  }

  async updateExecutionRunStep(
    id: string,
    stepId: string,
    stepUpdates: Partial<StepExecution>
  ): Promise<ExecutionRun | undefined> {
    const existing = this.executionRuns.get(id);
    if (!existing) return undefined;

    const steps = existing.steps.map(step => {
      if (step.stepId === stepId) {
        return { ...step, ...stepUpdates };
      }
      return step;
    });

    return this.updateExecutionRun(id, { steps });
  }

  async addExecutionRunInteraction(
    id: string,
    interaction: UserInteraction
  ): Promise<ExecutionRun | undefined> {
    const existing = this.executionRuns.get(id);
    if (!existing) return undefined;

    const interactionWithId: UserInteraction = {
      ...interaction,
      id: interaction.id || randomUUID(),
      timestamp: interaction.timestamp || new Date(),
    };

    return this.updateExecutionRun(id, {
      interactions: [...existing.interactions, interactionWithId],
    });
  }

  async updateExecutionRunMetrics(
    id: string,
    metricsUpdate: Partial<ExecutionMetrics>
  ): Promise<ExecutionRun | undefined> {
    const existing = this.executionRuns.get(id);
    if (!existing) return undefined;

    const existingMetrics = existing.metrics || {
      runtime: { totalSeconds: 0, perStepSeconds: {} },
      resources: { peakMemoryGB: 0, avgCpuPercent: 0, diskUsedGB: 0 },
      quality: {},
      outputs: { fileCount: 0, totalSizeBytes: 0, byType: {}, bySize: {} },
    };
    const baseRuntime = existingMetrics.runtime || { totalSeconds: 0, perStepSeconds: {} };
    const baseResources = existingMetrics.resources || { peakMemoryGB: 0, avgCpuPercent: 0, diskUsedGB: 0 };
    const baseOutputs = existingMetrics.outputs || { fileCount: 0, totalSizeBytes: 0, byType: {}, bySize: {} };

    return this.updateExecutionRun(id, {
      metrics: {
        runtime: {
          ...baseRuntime,
          ...metricsUpdate.runtime,
          totalSeconds: metricsUpdate.runtime?.totalSeconds ?? baseRuntime.totalSeconds,
          perStepSeconds: metricsUpdate.runtime?.perStepSeconds ?? baseRuntime.perStepSeconds,
        },
        resources: {
          ...baseResources,
          ...metricsUpdate.resources,
          peakMemoryGB: metricsUpdate.resources?.peakMemoryGB ?? baseResources.peakMemoryGB,
          avgCpuPercent: metricsUpdate.resources?.avgCpuPercent ?? baseResources.avgCpuPercent,
          diskUsedGB: metricsUpdate.resources?.diskUsedGB ?? baseResources.diskUsedGB,
        },
        quality: { ...existingMetrics.quality, ...metricsUpdate.quality },
        outputs: {
          ...baseOutputs,
          ...metricsUpdate.outputs,
          fileCount: metricsUpdate.outputs?.fileCount ?? baseOutputs.fileCount,
          totalSizeBytes: metricsUpdate.outputs?.totalSizeBytes ?? baseOutputs.totalSizeBytes,
          byType: metricsUpdate.outputs?.byType ?? baseOutputs.byType,
          bySize: metricsUpdate.outputs?.bySize ?? baseOutputs.bySize,
        },
      },
    });
  }

  async setExecutionRunComparison(
    id: string,
    comparison: RunComparison
  ): Promise<ExecutionRun | undefined> {
    return this.updateExecutionRun(id, { comparison });
  }

  async deleteExecutionRun(id: string): Promise<boolean> {
    return this.executionRuns.delete(id);
  }

  async compareExecutionRuns(runId1: string, runId2: string): Promise<RunComparisonResponse | undefined> {
    const run1 = await this.getExecutionRun(runId1);
    const run2 = await this.getExecutionRun(runId2);

    if (!run1 || !run2) return undefined;

    // Calculate deltas
    const runtime1 = run1.metrics?.runtime?.totalSeconds || 0;
    const runtime2 = run2.metrics?.runtime?.totalSeconds || 0;
    const runtimeDelta = runtime1 > 0 ? ((runtime2 - runtime1) / runtime1) * 100 : 0;

    const memory1 = run1.metrics?.resources?.peakMemoryGB || 0;
    const memory2 = run2.metrics?.resources?.peakMemoryGB || 0;
    const memoryDelta = memory1 > 0 ? ((memory2 - memory1) / memory1) * 100 : 0;

    // Calculate quality deltas
    const qualityDelta: Record<string, number> = {};
    const quality1 = run1.metrics?.quality || {};
    const quality2 = run2.metrics?.quality || {};
    const allQualityKeys = new Set([...Object.keys(quality1), ...Object.keys(quality2)]);
    for (const key of allQualityKeys) {
      const v1 = quality1[key] || 0;
      const v2 = quality2[key] || 0;
      qualityDelta[key] = v2 - v1;
    }

    // Determine preferred run
    let preferredRun = runId2;
    let reason = 'More recent run';

    // Simple heuristic: prefer better quality with acceptable runtime/memory
    const qualityImproved = Object.values(qualityDelta).some(d => d > 0);
    const runtimeAcceptable = runtimeDelta < 50; // Less than 50% slower
    const memoryAcceptable = memoryDelta < 100; // Less than 100% more memory

    if (qualityImproved && runtimeAcceptable && memoryAcceptable) {
      preferredRun = runId2;
      reason = 'Better quality metrics with acceptable resource usage';
    } else if (runtimeDelta < -20 && memoryDelta < 0) {
      preferredRun = runId2;
      reason = 'Significantly faster and more memory efficient';
    }

    return {
      runs: [run1, run2],
      comparison: {
        runtimeDelta,
        memoryDelta,
        qualityDelta,
      },
      recommendation: {
        preferredRun,
        reason,
        fullRunEstimate: undefined, // Would need actual estimation logic
      },
    };
  }
}

export const storage = new MemStorage();
