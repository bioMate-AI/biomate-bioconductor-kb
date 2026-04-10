/**
 * Galaxy API Proxy Layer
 * Calls existing Galaxy backend at /tmp/lcms-platform-galaxy
 * Leverages production-ready tool search, installation, and dataset discovery
 */

import axios, { AxiosInstance, AxiosError } from 'axios';
import fs from 'node:fs';
import path from 'node:path';
import type {
  GalaxyTool,
  ToolSearchResponse,
  ToolCategoriesResponse,
  ToolInstallRequest,
  ToolInstallResponse,
  InstalledToolsResponse,
  ToolSchema,
  BioMNIDataset,
  DatasetSearchRequest,
  DatasetSearchResponse,
  GalaxyWorkflow,
  GalaxyWorkflowInvocation,
  GalaxyJob,
  GalaxyAPIError,
  WorkflowGenerationRequest,
  WorkflowGenerationResponse,
} from '../shared/galaxy-types';

export class GalaxyAPIProxy {
  public client: AxiosInstance;
  private galaxyUrl: string;
  private apiKey?: string;
  private isConnected: boolean = false;
  private connectionError: string | null = null;

  constructor(galaxyUrl?: string, apiKey?: string) {
    this.galaxyUrl = galaxyUrl || process.env.GALAXY_URL || 'http://localhost:8081';
    this.apiKey = apiKey || process.env.GALAXY_API_KEY;

    // Warn if using default localhost
    if (!process.env.GALAXY_URL) {
      console.warn('[GalaxyAPIProxy] WARNING: GALAXY_URL not set, using default localhost:8080');
    }

    // Warn if no API key
    if (!this.apiKey) {
      console.warn('[GalaxyAPIProxy] WARNING: GALAXY_API_KEY not set - some operations may fail');
    }

    console.log('[GalaxyAPIProxy] Initializing with:', {
      url: this.galaxyUrl,
      hasApiKey: !!this.apiKey,
      apiKeyLength: this.apiKey?.length || 0
    });

    this.client = axios.create({
      baseURL: this.galaxyUrl,
      timeout: 120000, // 120 seconds — LLM param inference can take 60-90s on cold start
      headers: {
        'Content-Type': 'application/json',
        ...(this.apiKey && { 'X-API-Key': this.apiKey }),
      },
    });

    // Validate connection on startup (async, non-blocking)
    this.validateConnection().catch(err => {
      console.error('[GalaxyAPIProxy] Initial connection validation failed:', err.message);
    });

    // Response interceptor for error handling
    this.client.interceptors.response.use(
      (response) => response,
      (error: AxiosError) => {
        const galaxyError: GalaxyAPIError = {
          error: error.code || 'UNKNOWN_ERROR',
          message: error.message || 'An unknown error occurred',
          status_code: error.response?.status || 500,
          detail: error.response?.data,
        };
        throw galaxyError;
      }
    );
  }

  /**
   * Returns a new GalaxyAPIProxy instance scoped to a specific user's API key.
   * All user-data operations (histories, datasets, invocations) should use this
   * to achieve per-user isolation in Galaxy.
   *
   * Falls back to this (admin) proxy if userApiKey is null/undefined.
   */
  forUser(userApiKey: string | null | undefined): GalaxyAPIProxy {
    if (!userApiKey) return this;
    // Skip connection validation and logging for per-user proxies — they share the same Galaxy URL
    const proxy = Object.create(GalaxyAPIProxy.prototype) as GalaxyAPIProxy;
    (proxy as any).galaxyUrl = this.galaxyUrl;
    (proxy as any).apiKey = userApiKey;
    (proxy as any).isConnected = true;
    (proxy as any).connectionError = null;
    (proxy as any).client = axios.create({
      baseURL: this.galaxyUrl,
      timeout: 60000,
      headers: {
        'Content-Type': 'application/json',
        'X-API-Key': userApiKey,
      },
    });
    (proxy as any).client.interceptors.response.use(
      (response: any) => response,
      (error: AxiosError) => {
        const galaxyError: GalaxyAPIError = {
          error: error.code || 'UNKNOWN_ERROR',
          message: error.message || 'An unknown error occurred',
          status_code: error.response?.status || 500,
          detail: error.response?.data,
        };
        throw galaxyError;
      }
    );
    return proxy;
  }

  /**
   * Provision a new Galaxy user account and return their credentials.
   * Requires the admin API key. Called once at BioMate user registration.
   *
   * @param biomateUserId - BioMate UUID used to derive a stable, non-PII Galaxy username
   * @param email - User's email (stored in Galaxy for admin visibility)
   * @returns galaxyUserId, galaxyApiKey, galaxyUsername
   */
  async provisionGalaxyUser(biomateUserId: string, email: string): Promise<{
    galaxyUserId: string;
    galaxyApiKey: string;
    galaxyUsername: string;
  }> {
    // Use the internal provisioning endpoint — bypasses the broken admin API (which returns 501
    // because the bootstrap_admin_api_key is expired / not recognized as is_admin=True).
    const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
    const internalKey = process.env.BILLING_INTERNAL_KEY ?? 'dev-insecure-key';

    const resp = await fetch(`${galaxyUrl}/internal/users/provision`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Internal-Key': internalKey,
      },
      body: JSON.stringify({ biomate_user_id: biomateUserId, email }),
      signal: AbortSignal.timeout(10000),
    });

    if (!resp.ok) {
      const text = await resp.text();
      throw new Error(`Galaxy user provisioning failed: ${resp.status} ${text}`);
    }

    const data = await resp.json() as {
      galaxy_user_id: string;
      galaxy_api_key: string;
      galaxy_username: string;
    };

    const galaxyUserId = data.galaxy_user_id;
    const galaxyApiKey = data.galaxy_api_key;
    const resolvedUsername = data.galaxy_username;

    console.log(`[GalaxyAPIProxy] Provisioned Galaxy user ${resolvedUsername} (${galaxyUserId}) for BioMate user ${biomateUserId}`);
    return { galaxyUserId, galaxyApiKey, galaxyUsername: resolvedUsername };
  }

  // ============================================================================
  // Tool Search API (leverages /tmp/lcms-platform-galaxy/lib/galaxy/webapps/galaxy/api/tool_search.py)
  // ============================================================================

  /**
   * Search for tools using full-text search
   * Maps to GET /api/tool_search
   */
  async searchTools(
    query: string,
    category?: string,
    limit: number = 50
  ): Promise<ToolSearchResponse> {
    const response = await this.client.get<ToolSearchResponse>('/api/tool_search', {
      params: { q: query, category, limit },
    });
    return response.data;
  }

  /**
   * Get list of tool categories with counts
   * Maps to GET /api/tool_search/categories
   */
  async getToolCategories(): Promise<ToolCategoriesResponse> {
    const response = await this.client.get<ToolCategoriesResponse>('/api/tool_search/categories');
    return response.data;
  }

  /**
   * Get tool details by ID
   * Maps to GET /api/tool_search/{tool_id}
   */
  async getToolById(toolId: string): Promise<GalaxyTool> {
    const response = await this.client.get<GalaxyTool>(`/api/tool_search/${encodeURIComponent(toolId)}`);
    return response.data;
  }

  /**
   * Get tool parameter schema (for parameter configuration UI)
   * Maps to GET /api/tool_search/schema?tool_id=...
   * Returns tool inputs schema for dynamic form generation from AI tools database
   */
  async getToolSchema(toolId: string): Promise<ToolSchema> {
    try {
      // Get tool schema from AI tools database
      // Using query parameter to avoid path routing issues with slashes in tool_id
      const response = await this.client.get<ToolSchema>(`/api/tool_search/schema?tool_id=${encodeURIComponent(toolId)}`);
      return response.data;
    } catch (error: any) {
      // If tool not in AI database, just throw the error
      // Frontend will use hardcoded schemas as fallback for common tools
      console.log(`[GalaxyAPIProxy] Tool schema not found in AI database for ${toolId}`);
      throw error;
    }
  }

  /**
   * Install a tool on-demand from ToolShed
   * Maps to POST /api/tool_search/install
   * Requires admin authentication
   */
  async installTool(request: ToolInstallRequest): Promise<ToolInstallResponse> {
    const response = await this.client.post<ToolInstallResponse>('/api/tool_search/install', request);
    return response.data;
  }

  /**
   * Check if tool is installed, install if not
   * Maps to POST /api/tool_search/check_and_install
   * Requires admin authentication
   */
  async checkAndInstallTool(toolId: string): Promise<ToolInstallResponse> {
    const response = await this.client.post<ToolInstallResponse>('/api/tool_search/check_and_install', {
      tool_id: toolId,
    });
    return response.data;
  }

  /**
   * Get list of installed tools
   * Maps to GET /api/tool_search/installed
   */
  async getInstalledTools(): Promise<InstalledToolsResponse> {
    const response = await this.client.get<InstalledToolsResponse>('/api/tool_search/installed');
    return response.data;
  }

  // ============================================================================
  // Dataset Discovery API (leverages /tmp/lcms-platform-galaxy/lib/galaxy/ai/biomni_dataset_rag.py)
  // ============================================================================

  /**
   * Search for datasets using BioMNI Dataset RAG
   * Maps to Python: BioMNIDatasetRAG.search_datasets()
   */
  async searchDatasets(request: DatasetSearchRequest): Promise<DatasetSearchResponse> {
    const response = await this.client.post<DatasetSearchResponse>('/api/datasets/search', request);
    return response.data;
  }

  /**
   * Get datasets by category
   * Maps to Python: BioMNIDatasetRAG.get_datasets_by_category()
   */
  async getDatasetsByCategory(category: string): Promise<BioMNIDataset[]> {
    const response = await this.client.get<{ datasets: BioMNIDataset[] }>(`/api/datasets/category/${category}`);
    return response.data.datasets;
  }

  /**
   * Get dataset by ID
   * Maps to Python: BioMNIDatasetRAG.get_dataset_by_id()
   */
  async getDatasetById(datasetId: string): Promise<BioMNIDataset> {
    const response = await this.client.get<BioMNIDataset>(`/api/datasets/${encodeURIComponent(datasetId)}`);
    return response.data;
  }

  /**
   * Find datasets by schema (required fields)
   * Maps to Python: BioMNIDatasetRAG.get_datasets_by_schema()
   */
  async getDatasetsBySchema(requiredFields: string[]): Promise<BioMNIDataset[]> {
    const response = await this.client.post<{ datasets: BioMNIDataset[] }>('/api/datasets/by_schema', {
      required_fields: requiredFields,
    });
    return response.data.datasets;
  }

  /**
   * Get compatible datasets for workflow step
   * Maps to Python: BioMNIDatasetRAG.get_compatible_datasets()
   */
  async getCompatibleDatasets(
    inputFormat: string,
    requiredFields?: string[],
    category?: string
  ): Promise<BioMNIDataset[]> {
    const response = await this.client.post<{ datasets: BioMNIDataset[] }>('/api/datasets/compatible', {
      input_format: inputFormat,
      required_fields: requiredFields,
      category,
    });
    return response.data.datasets;
  }

  // ============================================================================
  // Workflow API (Galaxy native workflow endpoints)
  // ============================================================================

  /**
   * Get workflow by ID
   * Maps to Galaxy's native GET /api/workflows/{id}
   */
  async getWorkflow(workflowId: string): Promise<GalaxyWorkflow> {
    const response = await this.client.get<GalaxyWorkflow>(`/api/workflows/${workflowId}`);
    return response.data;
  }

  /**
   * Normalize tool ID from AI database format to Galaxy format.
   * AI database uses: biomni/database/query_uniprot
   * Galaxy uses: biomni_database_query_uniprot
   */
  private normalizeToolId(toolId: string): string {
    if (toolId.startsWith('biomni/')) {
      return toolId.replace(/\//g, '_');
    }
    return toolId;
  }

  /**
   * Normalize all tool IDs in workflow steps.
   * Converts biomni/x/y format to biomni_x_y format that Galaxy expects.
   */
  private normalizeWorkflowToolIds(workflow: any): any {
    if (!workflow?.steps) return workflow;

    const normalizedWorkflow = { ...workflow };
    const normalizedSteps: Record<string, any> = {};

    for (const [stepId, step] of Object.entries(workflow.steps as Record<string, any>)) {
      const normalizedStep = { ...step };
      if (normalizedStep.tool_id) {
        const originalId = normalizedStep.tool_id;
        normalizedStep.tool_id = this.normalizeToolId(normalizedStep.tool_id);
        if (originalId !== normalizedStep.tool_id) {
          console.log(`[GalaxyAPIProxy] Normalized tool_id: ${originalId} -> ${normalizedStep.tool_id}`);
        }
      }
      normalizedSteps[stepId] = normalizedStep;
    }

    normalizedWorkflow.steps = normalizedSteps;
    return normalizedWorkflow;
  }

  /**
   * Create new workflow
   * Maps to Galaxy's native POST /api/workflows
   */
  async createWorkflow(workflow: Partial<GalaxyWorkflow>): Promise<GalaxyWorkflow> {
    // Normalize tool IDs before sending to Galaxy
    const normalizedWorkflow = this.normalizeWorkflowToolIds(workflow);

    const response = await this.client.post<GalaxyWorkflow>('/api/workflows', {
      workflow: normalizedWorkflow
    });
    return response.data;
  }

  /**
   * Invoke (run) a workflow
   * Maps to Galaxy's native POST /api/workflows/{id}/invocations
   *
   * @param workflowId - Galaxy workflow ID
   * @param inputs - Input dataset mappings for workflow steps
   * @param parameters - Workflow parameters (optional)
   *                     - Include `__priority` to set job priority: "low" | "normal" | "high" | "critical"
   *
   * @example
   * // Invoke workflow with high priority
   * await invokeWorkflow(workflowId, inputs, { __priority: "high" });
   */
  async invokeWorkflow(
    workflowId: string,
    inputs: Record<string, any>,
    parameters?: Record<string, any>
  ): Promise<GalaxyWorkflowInvocation> {
    const response = await this.client.post<GalaxyWorkflowInvocation>(
      `/api/workflows/${workflowId}/invocations`,
      {
        inputs,
        parameters,
        // Allow workflow invocation even when tool_state has upgrade messages.
        // This is needed because AI-generated workflows may not have all parameters
        // explicitly set, relying on Galaxy's default values.
        allow_tool_state_corrections: true,
      }
    );
    return response.data;
  }

  /**
   * Get workflow invocation status
   * Maps to Galaxy's native GET /api/workflows/{workflow_id}/invocations/{invocation_id}
   * Includes step_details=true to get job state information
   */
  async getInvocation(workflowId: string, invocationId: string): Promise<GalaxyWorkflowInvocation> {
    const response = await this.client.get<GalaxyWorkflowInvocation>(
      `/api/workflows/${workflowId}/invocations/${invocationId}?step_details=true`
    );
    return response.data;
  }

  /**
   * Get Nextflow workflow status by run ID.
   * Maps to backend endpoint: GET /api/nextflow/status/{run_id}
   */
  async getNextflowStatus(runId: string): Promise<any> {
    const response = await this.client.get(`/api/nextflow/status/${runId}`);
    return response.data;
  }

  /**
   * Run AutoFix 3.0 for a workflow invocation
   */
  async runAutofix3(
    workflowId: string,
    invocationId: string,
    payload: Record<string, any>
  ): Promise<any> {
    const response = await this.client.post(
      `/api/workflows/${workflowId}/invocations/${invocationId}/autofix3/run`,
      payload
    );
    return response.data;
  }

  /**
   * List AutoFix 3.0 sessions for a workflow invocation
   */
  async listAutofix3Sessions(
    workflowId: string,
    invocationId: string,
    limit?: number
  ): Promise<any> {
    const response = await this.client.get(
      `/api/workflows/${workflowId}/invocations/${invocationId}/autofix3/sessions`,
      { params: limit ? { limit } : undefined }
    );
    return response.data;
  }

  /**
   * Get AutoFix 3.0 system status
   */
  async getAutofix3Status(): Promise<any> {
    const response = await this.client.get("/api/autofix3/status");
    return response.data;
  }

  /**
   * Cancel workflow invocation
   * Maps to Galaxy's native DELETE /api/workflows/{workflow_id}/invocations/{invocation_id}
   */
  async cancelInvocation(workflowId: string, invocationId: string): Promise<void> {
    await this.client.delete(`/api/workflows/${workflowId}/invocations/${invocationId}`);
  }

  // ============================================================================
  // Job API (Galaxy native job tracking)
  // ============================================================================

  /**
   * Get job details by ID
   * Maps to Galaxy's native GET /api/jobs/{id}
   */
  async getJob(jobId: string): Promise<GalaxyJob> {
    const response = await this.client.get<GalaxyJob>(`/api/jobs/${jobId}`);
    return response.data;
  }

  /**
   * Get job stdout log
   * Maps to Galaxy's native GET /api/jobs/{id}/stdout
   */
  async getJobStdout(jobId: string): Promise<string> {
    const response = await this.client.get<string>(`/api/jobs/${jobId}/stdout`);
    return response.data;
  }

  /**
   * Get job stderr log
   * Maps to Galaxy's native GET /api/jobs/{id}/stderr
   */
  async getJobStderr(jobId: string): Promise<string> {
    const response = await this.client.get<string>(`/api/jobs/${jobId}/stderr`);
    return response.data;
  }

  /**
   * Pause a running or queued job
   * Maps to Galaxy's native PUT /api/jobs/{id}/pause
   */
  async pauseJob(jobId: string): Promise<any> {
    const response = await this.client.put(`/api/jobs/${jobId}/pause`);
    return response.data;
  }

  /**
   * Resume a paused job
   * Maps to Galaxy's native PUT /api/jobs/{id}/resume
   */
  async resumeJob(jobId: string): Promise<any> {
    const response = await this.client.put(`/api/jobs/${jobId}/resume`);
    return response.data;
  }

  // ============================================================================
  // Dataset and History Management
  // ============================================================================

  /**
   * Create a new history for the user
   */
  async createHistory(name: string): Promise<string> {
    const response = await this.client.post('/api/histories', {
      name: name
    });
    return response.data.id;
  }

  /**
   * Get all histories for the current user
   */
  async getHistories(): Promise<any[]> {
    const response = await this.client.get('/api/histories');
    return response.data;
  }

  /**
   * Upload a dataset to a Galaxy history
   */
  async uploadDataset(filePath: string, historyId: string, fileName: string): Promise<string> {
    const FormData = require('form-data');
    const fs = require('fs');

    const formData = new FormData();
    formData.append('file', fs.createReadStream(filePath));
    formData.append('file_type', 'auto');

    const response = await this.client.post(
      `/api/histories/${historyId}/contents`,
      formData,
      {
        headers: formData.getHeaders()
      }
    );
    return response.data.id;
  }

  /**
   * Upload a dataset from a URL - Galaxy fetches the file directly
   * This is faster for large files as no browser upload is required
   * Supports HTTP, HTTPS, FTP, and S3 URLs
   */
  async uploadFromUrl(url: string, historyId: string, fileName?: string): Promise<string> {
    console.log(`[GalaxyAPIProxy] Uploading from URL: ${url} to history ${historyId}`);

    // Galaxy's paste/fetch upload API
    // Uses the same endpoint as regular uploads but with 'paste' target
    const response = await this.client.post(
      `/api/histories/${historyId}/contents`,
      {
        type: 'file',
        source: 'url',
        url: url,
        name: fileName || url.split('/').pop() || 'imported-file',
        file_type: 'auto',
        space_to_tab: false,
        to_posix_lines: true,
      }
    );

    // Galaxy may return the dataset ID directly or in a job structure
    if (response.data.id) {
      return response.data.id;
    }
    if (response.data.outputs && response.data.outputs.length > 0) {
      return response.data.outputs[0].id;
    }
    throw new Error('No dataset ID returned from URL import');
  }

  /**
   * Get datasets in a history
   */
  async getHistoryDatasets(historyId: string): Promise<any[]> {
    const response = await this.client.get(`/api/histories/${historyId}/contents`);
    return response.data;
  }

  /**
   * Submit a single tool job to Galaxy
   */
  async submitToolJob(toolId: string, inputs: any, historyId: string): Promise<any> {
    const response = await this.client.post('/api/tools', {
      tool_id: toolId,
      inputs: inputs,
      history_id: historyId
    });
    return response.data;
  }

  /**
   * Get output datasets from a completed job
   */
  async getJobOutputs(jobId: string): Promise<any[]> {
    const job = await this.getJob(jobId);
    // outputs can be an array or a Record - convert to array if needed
    const outputs = job.outputs;
    if (Array.isArray(outputs)) {
      return outputs;
    }
    if (outputs && typeof outputs === 'object') {
      return Object.values(outputs);
    }
    return [];
  }

  // ============================================================================
  // Workflow Generation (AI)
  // ============================================================================

  /**
   * Generate workflow using Galaxy AI Assistant (Python backend)
   * Maps to unified AI endpoint /api/ai_assistant/generate_workflow
   *
   * This endpoint uses the complete unified architecture:
   * 1. Search existing templates first (WorkflowSearchRAG)
   * 2. If high confidence (>0.8): Reuse template
   * 3. If medium confidence (0.5-0.8): Adapt template
   * 4. If low confidence (<0.5): Generate from scratch with tool constraint
   * 5. Always assign datasets via WorkflowDatasetSelector
   */
  async generateWorkflow(request: WorkflowGenerationRequest): Promise<WorkflowGenerationResponse> {
    try {
      const hasRunnableNextflowWorkflow = (rawPath: unknown): boolean => {
        const workflowPath = String(rawPath || "").trim();
        if (!workflowPath) {
          return false;
        }
        if (!workflowPath.toLowerCase().endsWith(".nf")) {
          return false;
        }
        const candidatePaths = path.isAbsolute(workflowPath)
          ? [workflowPath]
          : [
              workflowPath,
              path.resolve(process.cwd(), workflowPath),
              path.resolve(process.cwd(), "..", workflowPath),
              path.resolve(process.cwd(), "..", "backend", workflowPath),
            ];
        const resolvedPath = candidatePaths.find((candidate) => fs.existsSync(candidate));
        if (!resolvedPath) {
          // If the path is not locally inspectable from this process, keep it
          // as potentially runnable and let backend entry-resolution decide.
          return true;
        }
        try {
          const script = fs.readFileSync(resolvedPath, "utf8");
          // Anonymous entry workflow: `workflow { ... }`
          if (/\bworkflow\s*\{/.test(script)) {
            return true;
          }
          // Named workflow entry: `workflow name { ... }`
          const namedEntries = script.match(/\bworkflow\s+[A-Za-z_][A-Za-z0-9_]*\s*\{/g);
          return !!(namedEntries && namedEntries.length > 0);
        } catch {
          return false;
        }
      };

      const isExecutableNextflowPath = (rawPath: unknown): boolean => {
        const path = String(rawPath || "").trim().toLowerCase();
        if (!path) {
          return false;
        }
        if (!path.endsWith(".nf")) {
          return false;
        }
        // Subworkflows may still be runnable when executed with explicit entry.
        // Runtime entry resolution is handled in backend nextflow executor.
        return hasRunnableNextflowWorkflow(rawPath);
      };

      const isRunnableWorkflowResponse = (payload: any): boolean => {
        if (!payload || payload.success !== true) {
          return false;
        }
        // Curated chain plans are always accepted — they render as WorkflowChainPlan
        if (payload.workflow_type === 'chain') {
          return true;
        }
        const nextflowPath = payload.nextflow_path || payload.workflow_ga?.nextflow_path;
        if (isExecutableNextflowPath(nextflowPath)) {
          return true;
        }
        const workflowGa = payload.workflow_ga;
        const steps = workflowGa?.steps;
        return !!(
          workflowGa &&
          steps &&
          typeof steps === 'object' &&
          Object.keys(steps).length > 0
        );
      };

      // Single entry point: generate_workflow_unified handles chain lookup,
      // search (high/medium confidence), and composition (low confidence) internally.
      const backendRequest = {
        request_text: request.user_intent,
        available_datasets: request.datasets || [],
        context: {
          ...(request.session_id ? { session_id: request.session_id } : {}),
        },
        preferred_tools: [],
        constraints: { max_tools_search: request.max_tools_search || 30 },
        ...(request.preferred_domains?.length ? { preferred_domains: request.preferred_domains } : {}),
        ...(request.penalized_domains?.length ? { penalized_domains: request.penalized_domains } : {}),
        ...(request.key_terms?.length ? { key_terms: request.key_terms } : {}),
        ...(request.session_datasets?.length ? { session_datasets: request.session_datasets } : {}),
        ...(request.credential_map ? { credential_map: request.credential_map } : {}),
      };

      console.log('[GalaxyAPIProxy] Calling generate_workflow — intent:', request.user_intent);

      const response = await this.client.post<WorkflowGenerationResponse>(
        '/api/ai_assistant/generate_workflow',
        backendRequest
      );

      console.log('[GalaxyAPIProxy] source:', response.data.source, '| type:', response.data.workflow_type);

      return response.data;
    } catch (error: any) {
      console.error('[GalaxyAPIProxy] Workflow generation failed:', error.message);
      // Return error response instead of throwing
      return {
        success: false,
        error: error.message || 'Workflow generation failed',
      };
    }
  }

  /**
   * Generate workflow using multi-agent system (Python backend)
   * Maps to /api/ai_assistant/generate_workflow_multi_agent
   *
   * Uses 3-agent architecture:
   * 1. DomainRouter - Routes to domains (NO LLM, fast)
   * 2. DomainSpecialists - Parallel domain-specific recommendations
   * 3. WorkflowAssembler - Synthesizes and validates workflow
   */
  async generateWorkflowMultiAgent(request: WorkflowGenerationRequest): Promise<WorkflowGenerationResponse> {
    try {
      const backendRequest = {
        request_text: request.user_intent,
        available_datasets: request.datasets || [],
        context: {},
        constraints: {}
      };

      console.log('[GalaxyAPIProxy] Calling multi-agent AI endpoint');
      console.log('[GalaxyAPIProxy] User intent:', request.user_intent);

      const response = await this.client.post<WorkflowGenerationResponse>(
        '/api/ai_assistant/generate_workflow_multi_agent',
        backendRequest
      );

      console.log('[GalaxyAPIProxy] Multi-agent workflow generated');
      console.log('[GalaxyAPIProxy] Source:', response.data.source);
      console.log('[GalaxyAPIProxy] Confidence:', response.data.confidence);
      console.log('[GalaxyAPIProxy] Domain sources:', (response.data as any).domain_sources);

      return response.data;
    } catch (error: any) {
      console.error('[GalaxyAPIProxy] Multi-agent workflow generation failed:', error.message);
      return {
        success: false,
        error: error.message || 'Multi-agent workflow generation failed',
      };
    }
  }

  /**
   * Import a workflow to Galaxy from .ga format
   * Returns the imported workflow ID
   */
  async importWorkflow(workflowGa: any): Promise<string> {
    const response = await this.client.post('/api/workflows', {
      workflow: workflowGa
    });
    return response.data.id;
  }

  /**
   * Get workflow inputs (for mapping datasets)
   */
  async getWorkflowInputs(workflowId: string): Promise<any[]> {
    const response = await this.client.get(`/api/workflows/${workflowId}/inputs`);
    return response.data;
  }

  // ============================================================================
  // History & Dataset Management
  // ============================================================================

  /**
   * Get contents of a history (all datasets)
   */
  async getHistoryContents(historyId: string): Promise<any[]> {
    const response = await this.client.get(`/api/histories/${historyId}/contents`);
    return response.data;
  }

  /**
   * Download a dataset file from Galaxy
   * Returns a readable stream
   */
  async downloadDataset(datasetId: string): Promise<any> {
    const response = await this.client.get(`/api/datasets/${datasetId}/display`, {
      responseType: 'stream'
    });
    return response.data;
  }

  /**
   * Get dataset metadata
   */
  async getDatasetMetadata(datasetId: string): Promise<any> {
    const response = await this.client.get(`/api/datasets/${datasetId}`);
    return response.data;
  }

  // ============================================================================
  // Health Check
  // ============================================================================

  /**
   * Check if Galaxy backend is reachable
   */
  async healthCheck(): Promise<boolean> {
    try {
      await this.client.get('/api/version');
      return true;
    } catch (error) {
      return false;
    }
  }

  /**
   * Validate connection to Galaxy backend
   * Called on startup and can be called to check status
   */
  async validateConnection(): Promise<{ connected: boolean; error?: string; version?: string }> {
    try {
      const response = await this.client.get('/api/version', { timeout: 10000 });
      this.isConnected = true;
      this.connectionError = null;
      console.log('[GalaxyAPIProxy] ✅ Connection validated - Galaxy version:', response.data.version_major);
      return {
        connected: true,
        version: response.data.version_major || response.data.version || 'unknown'
      };
    } catch (error: any) {
      this.isConnected = false;
      this.connectionError = error.message || 'Connection failed';
      console.error('[GalaxyAPIProxy] ❌ Connection validation failed:', this.connectionError);
      return {
        connected: false,
        error: this.connectionError || undefined
      };
    }
  }

  /**
   * Get current connection status
   */
  getConnectionStatus(): { connected: boolean; error: string | undefined; url: string } {
    return {
      connected: this.isConnected,
      error: this.connectionError || undefined,
      url: this.galaxyUrl
    };
  }

  /**
   * Query research agent backend for literature-backed answers.
   */
  async queryResearch(payload: Record<string, any>): Promise<any> {
    try {
      const response = await this.client.post('/api/ai_assistant/query_research', payload);
      return response.data;
    } catch (error: any) {
      // Backward-compatible fallback endpoint
      const fallback = await this.client.post('/api/ai_assistant/research', payload).catch(() => null);
      if (fallback?.data) return fallback.data;
      throw error;
    }
  }

  /**
   * Query benchmark agent backend for comparative evidence.
   */
  async queryBenchmark(payload: Record<string, any>): Promise<any> {
    try {
      const response = await this.client.post('/api/ai_assistant/query_benchmark', payload);
      return response.data;
    } catch (error: any) {
      // Backward-compatible fallback endpoint
      const fallback = await this.client.post('/api/ai_assistant/benchmark', payload).catch(() => null);
      if (fallback?.data) return fallback.data;
      throw error;
    }
  }

  // ============================================================================
  // Advanced Galaxy Capabilities
  // ============================================================================

  // --- Workflow Reports ---

  /**
   * Get workflow report (auto-generated analysis summary)
   * Galaxy can generate markdown reports from workflow invocations
   * Reports include: step outputs, visualizations, parameters used
   */
  async getWorkflowReport(workflowId: string, invocationId: string, format: 'markdown' | 'html' = 'markdown'): Promise<{
    report: string;
    format: string;
    generated_at: string;
  }> {
    console.log(`[GalaxyAPIProxy] Getting workflow report for invocation ${invocationId}`);

    const response = await this.client.get(
      `/api/workflows/${workflowId}/invocations/${invocationId}/report`,
      {
        params: { format },
        headers: { 'Accept': format === 'html' ? 'text/html' : 'text/markdown' }
      }
    );

    return {
      report: typeof response.data === 'string' ? response.data : JSON.stringify(response.data),
      format,
      generated_at: new Date().toISOString(),
    };
  }

  /**
   * Configure workflow to generate reports
   * Sets up report template in workflow definition
   */
  async configureWorkflowReport(workflowId: string, reportConfig: {
    title?: string;
    include_outputs?: boolean;
    include_parameters?: boolean;
    include_visualizations?: boolean;
    custom_sections?: Array<{ name: string; markdown: string }>;
  }): Promise<any> {
    const response = await this.client.put(
      `/api/workflows/${workflowId}`,
      {
        report: {
          markdown: this.generateReportTemplate(reportConfig),
        }
      }
    );
    return response.data;
  }

  private generateReportTemplate(config: {
    title?: string;
    include_outputs?: boolean;
    include_parameters?: boolean;
    include_visualizations?: boolean;
    custom_sections?: Array<{ name: string; markdown: string }>;
  }): string {
    let template = `# ${config.title || 'Workflow Analysis Report'}\n\n`;

    if (config.include_parameters !== false) {
      template += `## Parameters Used\n\n\`\`\`galaxy\nworkflow_parameters()\n\`\`\`\n\n`;
    }

    if (config.include_outputs !== false) {
      template += `## Outputs\n\n\`\`\`galaxy\nworkflow_outputs()\n\`\`\`\n\n`;
    }

    if (config.include_visualizations !== false) {
      template += `## Visualizations\n\n\`\`\`galaxy\nworkflow_visualizations()\n\`\`\`\n\n`;
    }

    if (config.custom_sections) {
      for (const section of config.custom_sections) {
        template += `## ${section.name}\n\n${section.markdown}\n\n`;
      }
    }

    return template;
  }

  // --- Dataset Collections ---

  /**
   * Create a dataset collection (list, paired, list:paired)
   * Enables batch processing of multiple files as a single input
   *
   * @param historyId - History to create collection in
   * @param name - Collection name
   * @param collectionType - 'list', 'paired', or 'list:paired'
   * @param elements - Dataset IDs to include
   */
  async createDatasetCollection(
    historyId: string,
    name: string,
    collectionType: 'list' | 'paired' | 'list:paired',
    elements: Array<{
      id: string;
      name?: string;
      src?: 'hda' | 'ldda' | 'hdca';
    }>
  ): Promise<{
    id: string;
    name: string;
    collection_type: string;
    element_count: number;
  }> {
    console.log(`[GalaxyAPIProxy] Creating ${collectionType} collection with ${elements.length} elements`);

    const elementIdentifiers = elements.map((el, idx) => ({
      id: el.id,
      name: el.name || `element_${idx}`,
      src: el.src || 'hda',
    }));

    const response = await this.client.post(
      `/api/histories/${historyId}/contents`,
      {
        type: 'dataset_collection',
        name,
        collection_type: collectionType,
        element_identifiers: elementIdentifiers,
      }
    );

    return {
      id: response.data.id,
      name: response.data.name,
      collection_type: response.data.collection_type,
      element_count: response.data.element_count || elements.length,
    };
  }

  /**
   * Create paired collection from forward/reverse reads
   * Automatically pairs files based on naming conventions (_R1/_R2, _1/_2, etc.)
   */
  async createPairedCollection(
    historyId: string,
    name: string,
    forwardReads: Array<{ id: string; name: string }>,
    reverseReads: Array<{ id: string; name: string }>
  ): Promise<{
    id: string;
    name: string;
    pairs: number;
  }> {
    console.log(`[GalaxyAPIProxy] Creating paired collection with ${forwardReads.length} pairs`);

    if (forwardReads.length !== reverseReads.length) {
      throw new Error('Forward and reverse read counts must match');
    }

    const pairs = forwardReads.map((fwd, idx) => ({
      collection_type: 'paired',
      src: 'new_collection',
      name: fwd.name.replace(/_R1|_1|\.R1|\.1/, ''),
      element_identifiers: [
        { id: fwd.id, name: 'forward', src: 'hda' },
        { id: reverseReads[idx].id, name: 'reverse', src: 'hda' },
      ],
    }));

    const response = await this.client.post(
      `/api/histories/${historyId}/contents`,
      {
        type: 'dataset_collection',
        name,
        collection_type: 'list:paired',
        element_identifiers: pairs,
      }
    );

    return {
      id: response.data.id,
      name: response.data.name,
      pairs: forwardReads.length,
    };
  }

  /**
   * Auto-pair datasets in history based on naming patterns
   * Discovers matching R1/R2 or _1/_2 patterns automatically
   */
  async autoPairDatasets(historyId: string): Promise<{
    paired: Array<{ forward: string; reverse: string; name: string }>;
    unpaired: string[];
  }> {
    const datasets = await this.getHistoryDatasets(historyId);

    const paired: Array<{ forward: string; reverse: string; name: string }> = [];
    const used = new Set<string>();

    // Common paired-end patterns
    const forwardPatterns = [/_R1/, /_1(?=\.)/, /\.R1/, /\.1(?=\.)/];
    const reversePatterns = [/_R2/, /_2(?=\.)/, /\.R2/, /\.2(?=\.)/];

    for (const dataset of datasets) {
      if (used.has(dataset.id)) continue;

      for (let i = 0; i < forwardPatterns.length; i++) {
        if (forwardPatterns[i].test(dataset.name)) {
          // This is a forward read, find its pair
          const reverseName = dataset.name
            .replace(forwardPatterns[i], reversePatterns[i].source.replace(/[\\()]/g, ''));

          const reverseDataset = datasets.find(
            d => d.name === reverseName ||
                 d.name.replace(reversePatterns[i], '') === dataset.name.replace(forwardPatterns[i], '')
          );

          if (reverseDataset && !used.has(reverseDataset.id)) {
            paired.push({
              forward: dataset.id,
              reverse: reverseDataset.id,
              name: dataset.name.replace(forwardPatterns[i], ''),
            });
            used.add(dataset.id);
            used.add(reverseDataset.id);
            break;
          }
        }
      }
    }

    const unpaired = datasets
      .filter(d => !used.has(d.id))
      .map(d => d.id);

    return { paired, unpaired };
  }

  // --- Deferred Datasets ---

  /**
   * Create a deferred dataset (URL reference without immediate download)
   * Galaxy will fetch the data only when needed during workflow execution
   * Useful for large files or external databases
   */
  async createDeferredDataset(
    historyId: string,
    url: string,
    name?: string,
    fileType?: string
  ): Promise<{
    id: string;
    state: string;
    deferred: boolean;
  }> {
    console.log(`[GalaxyAPIProxy] Creating deferred dataset from URL: ${url}`);

    const response = await this.client.post(
      `/api/histories/${historyId}/contents`,
      {
        type: 'file',
        source: 'url',
        url: url,
        name: name || url.split('/').pop() || 'deferred-dataset',
        file_type: fileType || 'auto',
        deferred: true, // Key flag - don't fetch until needed
      }
    );

    return {
      id: response.data.id,
      state: response.data.state || 'deferred',
      deferred: true,
    };
  }

  /**
   * Materialize a deferred dataset (trigger actual download)
   * Call this when you need the data to be available
   */
  async materializeDeferredDataset(datasetId: string): Promise<{
    id: string;
    state: string;
    size?: number;
  }> {
    console.log(`[GalaxyAPIProxy] Materializing deferred dataset: ${datasetId}`);

    const response = await this.client.put(
      `/api/datasets/${datasetId}`,
      { action: 'materialize' }
    );

    return {
      id: response.data.id,
      state: response.data.state,
      size: response.data.file_size,
    };
  }

  // --- Interactive Tools ---

  /**
   * Launch an interactive tool (Jupyter, RStudio, etc.)
   * Returns entry point URL for the interactive session
   */
  async launchInteractiveTool(
    toolId: string,
    historyId: string,
    inputs?: Record<string, any>
  ): Promise<{
    job_id: string;
    entry_point_url?: string;
    state: string;
  }> {
    console.log(`[GalaxyAPIProxy] Launching interactive tool: ${toolId}`);

    const response = await this.client.post('/api/tools', {
      tool_id: toolId,
      history_id: historyId,
      inputs: inputs || {},
    });

    // Interactive tools may return entry point URL
    return {
      job_id: response.data.id || response.data.jobs?.[0]?.id,
      entry_point_url: response.data.entry_point_url,
      state: response.data.state || 'queued',
    };
  }

  /**
   * Get active interactive tool sessions
   */
  async getActiveInteractiveSessions(): Promise<Array<{
    job_id: string;
    tool_id: string;
    entry_point_url: string;
    created: string;
  }>> {
    const response = await this.client.get('/api/entry_points?active=true');
    return response.data;
  }

  // --- Workflow Subworkflows ---

  /**
   * Extract a subworkflow from a larger workflow
   * Useful for creating reusable components
   */
  async extractSubworkflow(
    workflowId: string,
    stepIds: number[],
    name: string
  ): Promise<{ id: string; name: string }> {
    console.log(`[GalaxyAPIProxy] Extracting subworkflow from steps: ${stepIds.join(', ')}`);

    const workflow = await this.getWorkflow(workflowId);

    // Extract specified steps
    const subSteps: Record<string, any> = {};
    let newStepId = 0;

    for (const stepId of stepIds) {
      if (workflow.steps && workflow.steps[stepId]) {
        subSteps[newStepId] = { ...workflow.steps[stepId], id: newStepId };
        newStepId++;
      }
    }

    // Create new workflow with extracted steps
    const subWorkflow = {
      name,
      steps: subSteps,
      annotation: `Extracted from workflow ${workflowId}`,
    };

    const response = await this.client.post('/api/workflows', { workflow: subWorkflow });
    return { id: response.data.id, name };
  }

  // ── LC-MS Agent Integration ───────────────────────────────────────────────
  /**
   * Route a user message to the LC-MS specialized agent if the query
   * is about mass spectrometry, proteomics, metabolomics, or LC-MS.
   * Returns null if the topic is not LC-MS or the service is unavailable.
   */
  async callLCMSAgent(
    userMessage: string,
    sessionId?: string
  ): Promise<{ content: string; recommendations: string[]; followUpQuestions: string[] } | null> {
    const lcmsKeywords = [
      'lc-ms', 'lcms', 'mass spec', 'mass spectrometry', 'proteomics', 'metabolomics',
      'mzml', 'mzxml', 'raw file', 'maxquant', 'dia-nn', 'openms', 'xcms', 'mzmine',
      'peptide', 'protein identification', 'feature detection', 'peak picking',
      'chromatography', 'tandem ms', 'ms/ms', 'msms', 'tmt', 'itraq', 'silac',
      'label-free quantification', 'lfq', 'dda', 'dia', 'swath'
    ];

    const lower = userMessage.toLowerCase();
    const isLCMSQuery = lcmsKeywords.some(kw => lower.includes(kw));
    if (!isLCMSQuery) return null;

    try {
      const { lcmsProxy } = await import('./lcms-proxy');
      if (!lcmsProxy.isAvailable) return null;

      const response = await lcmsProxy.query({
        query: userMessage,
        session_id: sessionId,
      });

      return {
        content: response.content,
        recommendations: response.recommendations,
        followUpQuestions: response.follow_up_questions,
      };
    } catch {
      return null;
    }
  }
}

// Export singleton instance
export const galaxyAPI = new GalaxyAPIProxy();
