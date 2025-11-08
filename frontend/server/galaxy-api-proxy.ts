/**
 * Galaxy API Proxy Layer
 * Calls existing Galaxy backend at /tmp/lcms-platform-galaxy
 * Leverages production-ready tool search, installation, and dataset discovery
 */

import axios, { AxiosInstance, AxiosError } from 'axios';
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
} from '../shared/galaxy-types';

export class GalaxyAPIProxy {
  private client: AxiosInstance;
  private galaxyUrl: string;
  private apiKey?: string;

  constructor(galaxyUrl?: string, apiKey?: string) {
    this.galaxyUrl = galaxyUrl || process.env.GALAXY_URL || 'http://localhost:8080';
    this.apiKey = apiKey || process.env.GALAXY_API_KEY;

    console.log('[GalaxyAPIProxy] Initializing with:', {
      url: this.galaxyUrl,
      hasApiKey: !!this.apiKey,
      apiKeyLength: this.apiKey?.length || 0
    });

    this.client = axios.create({
      baseURL: this.galaxyUrl,
      timeout: 30000, // 30 seconds
      headers: {
        'Content-Type': 'application/json',
        ...(this.apiKey && { 'X-API-Key': this.apiKey }),
      },
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
   * Create new workflow
   * Maps to Galaxy's native POST /api/workflows
   */
  async createWorkflow(workflow: Partial<GalaxyWorkflow>): Promise<GalaxyWorkflow> {
    const response = await this.client.post<GalaxyWorkflow>('/api/workflows', {
      workflow: workflow
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
      }
    );
    return response.data;
  }

  /**
   * Get workflow invocation status
   * Maps to Galaxy's native GET /api/workflows/{workflow_id}/invocations/{invocation_id}
   */
  async getInvocation(workflowId: string, invocationId: string): Promise<GalaxyWorkflowInvocation> {
    const response = await this.client.get<GalaxyWorkflowInvocation>(
      `/api/workflows/${workflowId}/invocations/${invocationId}`
    );
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
    return job.outputs || [];
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
      // Transform request to backend format
      const backendRequest = {
        request_text: request.user_intent,  // Backend expects 'request_text' not 'user_intent'
        available_datasets: request.datasets || [],
        context: {},
        preferred_tools: [],
        constraints: {
          max_tools_search: request.max_tools_search || 30
        }
      };

      console.log('[GalaxyAPIProxy] Calling unified AI Assistant endpoint');
      console.log('[GalaxyAPIProxy] User intent:', request.user_intent);

      const response = await this.client.post<WorkflowGenerationResponse>(
        '/api/ai_assistant/generate_workflow',  // ✅ Correct unified endpoint
        backendRequest
      );

      console.log('[GalaxyAPIProxy] Workflow generated via:', response.data.source);
      console.log('[GalaxyAPIProxy] Confidence:', response.data.confidence);
      console.log('[GalaxyAPIProxy] Datasets assigned:', response.data.datasets_assigned);

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
}

// Export singleton instance
export const galaxyAPI = new GalaxyAPIProxy();
