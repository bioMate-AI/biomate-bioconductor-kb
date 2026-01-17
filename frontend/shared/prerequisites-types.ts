/**
 * Pre-Execution Validation Types
 *
 * Minimal interfaces for the LLM-powered validation system.
 * No hardcoded formats or domain-specific data - all intelligence
 * comes from the tool database and LLM analysis.
 */

// =============================================================================
// Validation Request/Response
// =============================================================================

export interface ValidateWorkflowRequest {
  workflowDefinition: any;
  inputs?: WorkflowInput[];
  parameters?: Record<string, Record<string, any>>;
  historyId?: string;
  userContext?: string;  // Additional context from the conversation
}

export interface WorkflowInput {
  stepId: number | string;
  src: 'hda' | 'hdca' | 'ldda';
  id: string;
}

export interface PrerequisitesValidationResult {
  fulfilled: boolean;

  // What the workflow needs (from tool database)
  requirements: WorkflowRequirements;

  // What the user has (from Galaxy)
  available: AvailableResources;

  // LLM analysis results
  analysis: LLMAnalysis;

  // Natural language response for chat
  conversationalResponse: string;
}

// =============================================================================
// Requirements (extracted from workflow + tool database)
// =============================================================================

export interface WorkflowRequirements {
  inputs: InputRequirement[];
  parameters: ParameterRequirement[];
  workflowType?: string;  // LLM-inferred workflow type
  scientificContext?: string;  // From tool database
}

export interface InputRequirement {
  stepId: string;
  stepLabel: string;
  toolId?: string;
  inputName: string;
  // From tool database - not hardcoded
  acceptedFormats?: string[];
  dataType?: string;
  optional: boolean;
  description?: string;
}

export interface ParameterRequirement {
  stepId: string;
  toolId: string;
  toolName: string;
  paramName: string;
  paramLabel: string;
  paramType: string;
  optional: boolean;
  defaultValue?: any;
  constraints?: any;  // Tool-specific constraints from database
  description?: string;
}

// =============================================================================
// Available Resources (from Galaxy API)
// =============================================================================

export interface AvailableResources {
  datasets: AvailableDataset[];
  histories: AvailableHistory[];
}

export interface AvailableDataset {
  id: string;
  name: string;
  extension: string;
  size: number;
  state: string;
  historyId: string;
  metadata?: Record<string, any>;
  createTime?: string;
}

export interface AvailableHistory {
  id: string;
  name: string;
  datasetCount: number;
}

// =============================================================================
// LLM Analysis Results
// =============================================================================

export interface LLMAnalysis {
  // Dataset-to-input mappings suggested by LLM
  inputMappings: InputMapping[];

  // Missing requirements identified by LLM
  missingInputs: MissingInput[];
  missingParameters: MissingParameter[];

  // LLM-generated suggestions
  suggestions: Suggestion[];

  // Compatibility notes and warnings
  notes: AnalysisNote[];

  // Confidence in the analysis
  confidence: number;
}

export interface InputMapping {
  stepId: string;
  inputName: string;
  datasetId: string;
  datasetName: string;
  confidence: number;
  reasoning: string;
}

export interface MissingInput {
  stepId: string;
  stepLabel: string;
  inputName: string;
  description: string;
  // LLM-suggested alternatives or actions
  suggestedAction: string;
}

export interface MissingParameter {
  stepId: string;
  toolId: string;
  paramName: string;
  paramLabel: string;
  description: string;
  // LLM-suggested options based on context
  suggestedOptions?: SuggestedOption[];
}

export interface SuggestedOption {
  value: any;
  label: string;
  reasoning: string;
  recommended?: boolean;
}

export interface Suggestion {
  type: 'dataset' | 'parameter' | 'preprocessing' | 'general';
  message: string;
  action?: string;
}

export interface AnalysisNote {
  type: 'info' | 'warning' | 'error';
  message: string;
  relatedStep?: string;
}

// =============================================================================
// LLM Prompt Context
// =============================================================================

export interface ValidationContext {
  workflow: {
    name: string;
    description?: string;
    steps: any[];
  };
  requirements: WorkflowRequirements;
  available: AvailableResources;
  toolDocumentation: ToolDocumentation[];
  userContext?: string;
}

export interface ToolDocumentation {
  toolId: string;
  toolName: string;
  description: string;
  inputs: any[];
  parameters: any[];
  scientificContext?: any;
  helpText?: string;
}
