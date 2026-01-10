import {
  type User,
  type InsertUser,
  type WorkflowInvocation,
  type CreateInvocation,
  type OutputDataset,
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
}

export class MemStorage implements IStorage {
  private users: Map<string, User>;
  private invocations: Map<string, WorkflowInvocation>;
  private outputs: Map<string, OutputDataset>;

  constructor() {
    this.users = new Map();
    this.invocations = new Map();
    this.outputs = new Map();
  }

  // User management
  async getUser(id: string): Promise<User | undefined> {
    return this.users.get(id);
  }

  async getUserByUsername(username: string): Promise<User | undefined> {
    return Array.from(this.users.values()).find(
      (user) => user.username === username,
    );
  }

  async createUser(insertUser: InsertUser): Promise<User> {
    const id = randomUUID();
    const user: User = { ...insertUser, id };
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
    let invocations = Array.from(this.invocations.values());

    // Filter by userId if provided
    if (userId) {
      invocations = invocations.filter(inv => inv.userId === userId);
    }

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
}

export const storage = new MemStorage();
