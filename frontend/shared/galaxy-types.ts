/**
 * Shared TypeScript types for Galaxy API integration
 * Based on existing Galaxy backend at /tmp/lcms-platform-galaxy
 */

// ============================================================================
// Tool Search Types (from /tmp/lcms-platform-galaxy/lib/galaxy/tools/search_index.py)
// ============================================================================

export interface GalaxyTool {
  id: number;
  tool_id: string;
  name: string;
  description: string;
  version: string;
  repo_owner: string;
  repo_name: string;
  category: string;
  tool_shed_url: string;
  changeset_revision?: string;
  is_installed: boolean;
  install_status?: 'installed' | 'not_installed' | 'installing' | 'failed';
  install_date?: string;
  rank?: number; // BM25 relevance score from full-text search
  keywords?: string;
}

export interface ToolSearchResponse {
  query: string;
  category: string | null;
  count: number;
  tools: GalaxyTool[];
}

export interface ToolCategory {
  name: string;
  count: number;
}

export interface ToolCategoriesResponse {
  categories: ToolCategory[];
}

export interface ToolParameter {
  name: string;
  label: string;
  type: 'text' | 'integer' | 'float' | 'boolean' | 'select' | 'data' | 'color' | 'genomebuild';
  value?: any;
  help?: string;
  optional?: boolean;
  options?: Array<{ value: string; label: string }>;
  min?: number;
  max?: number;
}

export interface ToolSchema {
  id: string;
  name: string;
  version: string;
  description: string;
  inputs: ToolParameter[];
  outputs: Array<{
    name: string;
    format: string;
    label?: string;
  }>;
}

export interface ToolInstallRequest {
  tool_id?: string;
  owner?: string;
  name?: string;
  changeset_revision?: string;
  tool_shed_url?: string;
  tool_panel_section_id?: string;
}

export interface ToolInstallResponse {
  success: boolean;
  message: string;
  tool_id?: string;
  status?: string;
  error?: string;
}

export interface InstalledToolsResponse {
  count: number;
  tools: GalaxyTool[];
}

// ============================================================================
// Dataset Types (from /tmp/lcms-platform-galaxy/lib/galaxy/ai/biomni_dataset_rag.py)
// ============================================================================

export interface BioMNIDataset {
  id: string;
  name: string;
  description: string;
  category: 'metabolomics' | 'proteomics' | 'genomics' | 'clinical' | 'pathways' | 'pharmacology' | 'other';
  type?: string;
  format: string;
  size_mb: number;
  rows?: number;
  entries?: number;
  sequences?: number;
  fields: Record<string, any>;
  lcms_relevant: boolean;
  source: string;
  path: string;
  relevance_score?: number;
  query_intent?: string;
}

export interface DatasetSearchRequest {
  query: string;
  category?: string;
  format_type?: string;
  min_size?: number;
  max_size?: number;
  lcms_only?: boolean;
  limit?: number;
}

export interface DatasetSearchResponse {
  success?: boolean;
  query: string;
  count: number;
  datasets: BioMNIDataset[];
}

export interface CategorySummary {
  count: number;
  total_size_mb: number;
  formats: string[];
  dataset_ids: string[];
}

// ============================================================================
// Galaxy Workflow Types
// ============================================================================

export interface GalaxyWorkflowInput {
  label: string;
  type: 'data' | 'collection';
  optional: boolean;
  format?: string[];
}

export interface GalaxyWorkflowOutput {
  label: string;
  type: 'data' | 'collection';
  format?: string;
}

export interface GalaxyWorkflowStep {
  id: string;
  tool_id: string;
  tool_version: string;
  name: string;
  annotation?: string;
  tool_state: Record<string, any>;
  input_connections: Record<string, { id: string; output_name: string }>;
  position: { left: number; top: number };
}

export interface GalaxyWorkflow {
  id: string;
  name: string;
  annotation?: string;
  version: number;
  steps: Record<string, GalaxyWorkflowStep>;
  inputs: Record<string, GalaxyWorkflowInput>;
  outputs: Record<string, GalaxyWorkflowOutput>;
}

// ============================================================================
// Galaxy Job and Invocation Types (for execution tracking)
// ============================================================================

export type GalaxyJobState =
  | 'new'       // Job created but not queued
  | 'queued'    // Job waiting in queue
  | 'running'   // Job actively executing
  | 'ok'        // Job completed successfully
  | 'error'     // Job failed with error
  | 'paused'    // Job paused by user
  | 'deleted'   // Job deleted
  | 'waiting';  // Job waiting for dependencies

export interface GalaxyJob {
  id: string;
  tool_id: string;
  state: GalaxyJobState;
  create_time: string;
  update_time: string;
  exit_code?: number;
  command_line?: string;
  stderr?: string;
  stdout?: string;
  traceback?: string;
  outputs?: Record<string, any>;
}

export interface GalaxyInvocationStep {
  id: string;
  workflow_step_id: string;
  job_id?: string;
  state: GalaxyJobState;
  update_time: string;
  order_index: number;
}

export interface GalaxyWorkflowInvocation {
  id: string;
  workflow_id: string;
  history_id?: string;
  state: 'new' | 'ready' | 'scheduled' | 'cancelled' | 'failed';
  create_time: string;
  update_time: string;
  steps: GalaxyInvocationStep[];
}

// ============================================================================
// Real-time Update Types (for SSE)
// ============================================================================

export interface WorkflowExecutionUpdate {
  type: 'workflow_state' | 'step_state' | 'job_log' | 'error' | 'progress_milestone';
  invocation_id: string;
  timestamp: string;
  data: {
    workflow_state?: GalaxyWorkflowInvocation['state'];
    step_id?: string;
    step_state?: GalaxyJobState;
    job_id?: string;
    log_message?: string;
    error?: string;
    // Progress milestone fields
    progress?: number; // 0.25, 0.50, 0.75, 1.0
    completedSteps?: number;
    totalSteps?: number;
    eta?: string;
    message?: string;
    milestone?: number; // 25, 50, 75, 100
  };
}

// ============================================================================
// Enhanced Workflow Builder Types (for UI)
// ============================================================================

export interface WorkflowStepConfig {
  id: string;
  title: string;
  description: string;
  tool_id: string;
  tool_version: string;
  status: 'pending' | 'installing' | 'ready' | 'running' | 'completed' | 'error';

  // Parameter configuration (3-tier UI)
  parameters: {
    essential: Record<string, any>;      // 3-5 critical params (always visible)
    common: Record<string, any>;          // Common params (expandable)
    advanced: Record<string, any>;        // Advanced params (collapsed by default)
  };

  // Inputs/outputs
  inputs: Array<{
    name: string;
    type: string;
    format?: string;
    source?: { step_id: string; output_name: string };
    dataset_id?: string;
  }>;
  outputs: Array<{
    name: string;
    type: string;
    format?: string;
  }>;

  // Execution info
  job_id?: string;
  create_time?: string;
  update_time?: string;
  elapsed_time?: number; // milliseconds
  log_messages?: string[];

  // UI metadata
  position: { x: number; y: number };
  complexity: 'simple' | 'intermediate' | 'complex';
}

export interface WorkflowConfig {
  id: string;
  name: string;
  description?: string;
  steps: WorkflowStepConfig[];
  status: 'draft' | 'ready' | 'running' | 'paused' | 'completed' | 'error';

  // Execution tracking
  invocation_id?: string;
  create_time?: string;
  start_time?: string;
  end_time?: string;

  // Dataset inputs
  input_datasets?: Record<string, string>; // label -> dataset_id
}

// ============================================================================
// Chat Integration Types
// ============================================================================

export interface ChatMessage {
  id: string;
  role: 'user' | 'assistant';
  content: string;
  timestamp: string;
  metadata?: {
    tool_suggestions?: GalaxyTool[];
    dataset_suggestions?: BioMNIDataset[];
    generated_workflow?: WorkflowConfig;
  };
}

export interface ChatSession {
  id: string;
  title: string;
  messages: ChatMessage[];
  workflows: WorkflowConfig[];
  created_at: string;
  updated_at: string;
}

// ============================================================================
// API Error Types
// ============================================================================

export interface GalaxyAPIError {
  error: string;
  message: string;
  status_code: number;
  detail?: any;
}

// ============================================================================
// Parameter Schema Types (for 3-tier parameter UI)
// ============================================================================

export type ParameterType =
  | 'text'
  | 'integer'
  | 'float'
  | 'boolean'
  | 'select'
  | 'data'
  | 'data_collection';

export interface ParameterOption {
  value: string | number;
  label: string;
  selected?: boolean;
}

export interface ParameterSchema {
  name: string;
  type: ParameterType;
  label: string;
  help?: string;
  optional: boolean;
  default?: any;

  // For select parameters
  options?: ParameterOption[];

  // For numeric parameters
  min?: number;
  max?: number;

  // For data parameters
  format?: string[];
  multiple?: boolean;

  // UI tier classification
  tier: 'essential' | 'common' | 'advanced';
}

export interface ToolParameterSchema {
  tool_id: string;
  tool_version: string;
  parameters: ParameterSchema[];
}

// ============================================================================
// Workflow Generation Types (AI)
// ============================================================================

export interface WorkflowGenerationRequest {
  user_intent: string;
  max_tools_search?: number;
  inline_parameters?: Record<string, string>;
  datasets?: Array<{
    id: string;
    name: string;
    type: string;
  }>;
}

export interface WorkflowGenerationResponse {
  success: boolean;
  error?: string;
  workflow_ga?: any; // Galaxy .ga JSON format
  workflow_name?: string;
  format?: string;
  workflow_type?: string;
  nextflow_path?: string;

  // ===== NEW: Unified AI Assistant Response Fields =====
  // These fields are returned by the new /api/ai_assistant/generate_workflow endpoint
  source?: 'template_reuse' | 'template_adapt' | 'tool_constrained';
  confidence?: number; // 0.0 - 1.0
  template_match_score?: number; // 0.0 - 1.0 (similarity to existing templates)
  datasets_assigned?: boolean; // Whether domain knowledge datasets were assigned
  message?: string; // Human-readable message about workflow generation
  note?: string; // Additional notes about the generation strategy

  // ===== Legacy Fields (kept for backward compatibility) =====
  tool_selections?: Array<{
    tool_id: string;
    name: string;
    category: string;
    keywords: string;
  }>;
  dataset_assignments?: Record<
    string,
    Array<{
      dataset_id: string;
      dataset_name: string;
      reasoning: string;
    }>
  >;
  missing_tools?: string[];
  execution_time_ms?: number;
  generated_parameters?: Record<string, Record<string, any>>; // Tool parameters keyed by tool_id
}

// ============================================================================
// Use Case-Based Parameter Repository Types
// ============================================================================

export interface UseCaseMetadata {
  id: string;
  name: string;
  description: string;
  category: 'genomics' | 'proteomics' | 'metabolomics' | 'clinical' | 'quality_control' | 'preprocessing' | 'analysis' | 'other';
  tags: string[];
  sample_type?: string; // e.g., "human", "mouse", "cell_line", "plasma"
  analysis_type?: string; // e.g., "rna_seq", "chip_seq", "lc_ms_positive", "peak_calling"
  difficulty: 'beginner' | 'intermediate' | 'advanced';
  created_by: string;
  created_at: string;
  updated_at: string;
  usage_count?: number;
  success_rate?: number; // percentage of successful runs
}

export interface ParameterTemplate {
  id: string;
  tool_id: string;
  tool_version: string;
  tool_name: string;
  use_case: UseCaseMetadata;
  parameters: Record<string, any>;

  // Documentation
  rationale?: string; // Why these parameters work for this use case
  references?: string[]; // Papers, protocols, or documentation
  notes?: string; // Additional usage notes

  // Validation
  validated: boolean;
  validation_date?: string;
  validation_results?: {
    test_datasets: string[];
    success: boolean;
    metrics?: Record<string, number>;
  };
}

export interface ParameterTemplateSearchRequest {
  tool_id?: string;
  use_case_category?: string;
  analysis_type?: string;
  sample_type?: string;
  tags?: string[];
  limit?: number;
}

export interface ParameterTemplateSearchResponse {
  count: number;
  templates: ParameterTemplate[];
}

export interface SaveParameterTemplateRequest {
  tool_id: string;
  tool_version: string;
  tool_name: string;
  use_case_name: string;
  use_case_description: string;
  use_case_category: string;
  tags?: string[];
  sample_type?: string;
  analysis_type?: string;
  parameters: Record<string, any>;
  rationale?: string;
  references?: string[];
  notes?: string;
}

// ============================================================================
// Use Case-Based Workflow Repository Types
// ============================================================================

export interface WorkflowUseCase {
  id: string;
  name: string;
  description: string;
  category: 'genomics' | 'proteomics' | 'metabolomics' | 'clinical' | 'multi_omics' | 'other';
  tags: string[];

  // Analysis context
  analysis_type: string; // e.g., "differential_expression", "variant_calling", "metabolite_identification"
  sample_types: string[]; // e.g., ["human_plasma", "mouse_tissue"]
  input_types: string[]; // e.g., ["fastq", "bam", "mzML"]
  expected_outputs: string[]; // e.g., ["differential_expression_table", "vcf_file"]

  // Difficulty and requirements
  difficulty: 'beginner' | 'intermediate' | 'advanced';
  estimated_time: string; // e.g., "2-4 hours"
  compute_requirements?: {
    min_cpu?: number;
    min_memory_gb?: number;
    gpu_required?: boolean;
  };

  // Documentation
  rationale: string; // Why this workflow configuration
  protocol_references?: string[]; // Papers, protocols
  tutorial_url?: string;

  // Usage tracking
  created_by: string;
  created_at: string;
  updated_at: string;
  usage_count?: number;
  success_rate?: number;
  average_runtime?: number; // minutes
}

export interface WorkflowTemplate {
  id: string;
  name: string;
  description: string;
  use_case: WorkflowUseCase;

  // Galaxy workflow definition
  workflow_ga: any; // Galaxy .ga JSON format

  // Steps with parameter templates
  steps: Array<{
    step_id: string;
    tool_id: string;
    tool_name: string;
    parameter_template_id?: string; // Link to parameter template
    custom_parameters?: Record<string, any>;
  }>;

  // Recommended datasets
  recommended_datasets?: Array<{
    dataset_id: string;
    dataset_name: string;
    purpose: string; // e.g., "example", "test", "validation"
  }>;

  // Validation
  validated: boolean;
  validation_results?: {
    test_runs: number;
    success_count: number;
    failure_modes?: string[];
  };
}

export interface WorkflowTemplateSearchRequest {
  use_case_category?: string;
  analysis_type?: string;
  sample_type?: string;
  input_type?: string;
  tags?: string[];
  difficulty?: string;
  limit?: number;
}

export interface WorkflowTemplateSearchResponse {
  count: number;
  templates: WorkflowTemplate[];
}

export interface SaveWorkflowTemplateRequest {
  name: string;
  description: string;
  use_case_name: string;
  use_case_description: string;
  use_case_category: string;
  analysis_type: string;
  sample_types: string[];
  input_types: string[];
  expected_outputs: string[];
  tags?: string[];
  difficulty?: string;
  estimated_time?: string;
  rationale: string;
  protocol_references?: string[];
  workflow_ga: any;
  parameter_template_ids?: Record<string, string>; // step_id -> template_id
}
