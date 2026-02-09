import { sql } from "drizzle-orm";
import { pgTable, text, varchar, timestamp, boolean } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod";

export const users = pgTable("users", {
  id: varchar("id").primaryKey().default(sql`gen_random_uuid()`),
  email: text("email").notNull().unique(),
  password: text("password").notNull(),
  fullName: text("full_name").notNull(),
  organization: text("organization"),
  phone: text("phone"),

  // Trial management
  trialStartedAt: timestamp("trial_started_at").defaultNow(),
  trialEndsAt: timestamp("trial_ends_at").default(sql`NOW() + INTERVAL '7 days'`),
  trialUsed: boolean("trial_used").default(false),

  // Subscription
  stripeCustomerId: text("stripe_customer_id"),
  subscriptionStatus: text("subscription_status").default("trialing"),
  subscriptionTier: text("subscription_tier").default("academic"),
  subscriptionId: text("subscription_id"),
  currentPeriodEnd: timestamp("current_period_end"),

  // Security
  emailVerified: boolean("email_verified").default(false),
  verificationToken: text("verification_token"),
  resetPasswordToken: text("reset_password_token"),
  resetPasswordExpires: timestamp("reset_password_expires"),

  // Timestamps
  createdAt: timestamp("created_at").defaultNow(),
  updatedAt: timestamp("updated_at").defaultNow(),
  lastLoginAt: timestamp("last_login_at"),

  // Metadata
  termsAcceptedAt: timestamp("terms_accepted_at"),
  marketingEmailsOptIn: boolean("marketing_emails_opt_in").default(false),

  // Galaxy integration (preserve existing data)
  galaxyUserId: text("galaxy_user_id"),
  galaxyApiKey: text("galaxy_api_key"),
  galaxyUsername: text("galaxy_username"),
});

export const insertUserSchema = createInsertSchema(users).pick({
  email: true,
  password: true,
  fullName: true,
  organization: true,
  phone: true,
  termsAcceptedAt: true,
  marketingEmailsOptIn: true,
});

export type InsertUser = z.infer<typeof insertUserSchema>;
export type User = typeof users.$inferSelect;

// Explicit type for user without password (for API responses)
export type SafeUser = Omit<User, 'password'>;

// Dataset configuration schema for workflow inputs/outputs
export const datasetConfigSchema = z.object({
  id: z.string(),
  name: z.string().min(1, "Dataset name is required"),
  type: z.enum(["input", "output"]),
  storageType: z.enum(["local", "s3", "replit_storage"]),
  // Local storage configuration
  localPath: z.string().optional(),
  // S3 configuration
  s3Config: z.object({
    bucketName: z.string(),
    accessKeyId: z.string(),
    secretAccessKey: z.string(),
    region: z.string().default("us-east-1"),
    prefix: z.string().optional()
  }).optional(),
  // Replit storage configuration
  replitStoragePath: z.string().optional(),
  // Dataset metadata
  description: z.string().optional(),
  format: z.string().optional(), // e.g., "FASTQ", "BAM", "CSV", etc.
  size: z.number().optional(),
  createdAt: z.coerce.date().default(() => new Date())
});

export type DatasetConfig = z.infer<typeof datasetConfigSchema>;

// Workflow step schema with dataset support
export const workflowStepSchema = z.object({
  id: z.string(),
  title: z.string(),
  description: z.string(),
  status: z.enum(["pending", "running", "completed", "error"]),
  tool: z.string(),
  parameters: z.record(z.any()).optional(),
  complexity: z.enum(["simple", "intermediate", "complex"]),
  estimatedTime: z.string().optional(),
  // Dataset inputs and outputs
  inputs: z.array(datasetConfigSchema).optional(),
  outputs: z.array(datasetConfigSchema).optional()
});

export type WorkflowStepWithDatasets = z.infer<typeof workflowStepSchema>;

// Message schema for chat interface
export const messageSchema = z.object({
  id: z.string(),
  content: z.string(),
  role: z.enum(["user", "assistant"]),
  timestamp: z.coerce.date(),
  suggestions: z.array(z.string()).optional(),
  workflowId: z.string().optional(),
  invocationId: z.string().optional(), // Reference to workflow invocation for output display
  datasets: z.array(datasetConfigSchema).optional(),
  // Thinking mode support
  thinking_content: z.string().optional(), // AI's reasoning process
  thinking_level: z.enum(["none", "brief", "detailed"]).optional(), // Optional - defaults to "none" when not provided
  metadata: z.record(z.any()).optional() // Additional metadata (e.g., workflow data, tools)
});

export type Message = z.infer<typeof messageSchema>;

// Chat session schema
export const chatSessionSchema = z.object({
  id: z.string(),
  title: z.string(),
  timestamp: z.coerce.date(),
  lastActivity: z.coerce.date(),
  messages: z.array(messageSchema),
  workflows: z.array(workflowStepSchema).optional(),
  datasets: z.array(datasetConfigSchema).optional(),
  status: z.enum(["active", "archived"]).default("active"),
  // Token tracking for context management
  totalTokens: z.number().optional()
});

export type ChatSession = z.infer<typeof chatSessionSchema>;

// Starred workflow schema
export const starredWorkflowSchema = z.object({
  id: z.string(),
  workflowId: z.string(),
  title: z.string(),
  description: z.string(),
  starredAt: z.coerce.date(),
  workflowType: z.string(), // e.g., "RNA-seq", "Variant Calling", etc.
  complexity: z.enum(["simple", "intermediate", "complex"]),
  estimatedTime: z.string().optional()
});

export type StarredWorkflow = z.infer<typeof starredWorkflowSchema>;

// Recent tool schema
export const recentToolSchema = z.object({
  id: z.string(),
  toolId: z.string(),
  name: z.string(),
  description: z.string(),
  category: z.string(),
  complexity: z.enum(["simple", "intermediate", "complex"]),
  lastUsed: z.coerce.date(),
  usageCount: z.number().default(1)
});

export type RecentTool = z.infer<typeof recentToolSchema>;

// User settings schema
export const userSettingsSchema = z.object({
  id: z.string(),
  userId: z.string().optional(),
  // Profile settings
  displayName: z.string().optional(),
  email: z.string().email().optional(),
  role: z.string().default("Researcher"),
  avatar: z.string().optional(),
  // Application preferences
  language: z.enum(["english", "spanish", "french", "german", "chinese"]).default("english"),
  theme: z.enum(["light", "dark", "system"]).default("system"),
  // Workflow preferences
  defaultWorkflowComplexity: z.enum(["simple", "intermediate", "complex"]).default("intermediate"),
  autoSaveWorkflows: z.boolean().default(true),
  showWorkflowEstimates: z.boolean().default(true),
  // Chat preferences
  chatSuggestions: z.boolean().default(true),
  typingIndicator: z.boolean().default(true),
  messageTimestamps: z.boolean().default(true),
  // Data preferences
  defaultStorageType: z.enum(["local", "s3", "replit_storage"]).default("replit_storage"),
  autoDeleteTempFiles: z.boolean().default(true),
  dataRetentionDays: z.number().default(30),
  // Notification preferences
  workflowCompletionNotifications: z.boolean().default(true),
  errorNotifications: z.boolean().default(true),
  // Privacy settings
  shareUsageData: z.boolean().default(false),
  shareErrorReports: z.boolean().default(true),
  // Advanced settings
  debugMode: z.boolean().default(false),
  experimentalFeatures: z.boolean().default(false),
  updatedAt: z.coerce.date().default(() => new Date())
});

export type UserSettings = z.infer<typeof userSettingsSchema>;

// Project document schema for file management
export const projectDocumentSchema = z.object({
  id: z.string(),
  name: z.string(),
  type: z.enum(["file", "text", "url"]),
  content: z.string().optional(), // For text documents or file paths
  url: z.string().url().optional(), // For URL references
  size: z.number().optional(), // File size in bytes
  format: z.string().optional(), // File format/extension
  uploadedAt: z.coerce.date().default(() => new Date()),
  description: z.string().optional()
});

export type ProjectDocument = z.infer<typeof projectDocumentSchema>;

// Project schema
export const projectSchema = z.object({
  id: z.string(),
  name: z.string().min(1, "Project name is required"),
  description: z.string().optional(),
  instructions: z.string().optional(), // Background context for the project
  status: z.enum(["active", "archived", "completed"]).default("active"),
  createdAt: z.coerce.date().default(() => new Date()),
  updatedAt: z.coerce.date().default(() => new Date()),
  // Associated data
  chatSessions: z.array(z.string()).default([]), // Array of chat session IDs
  documents: z.array(projectDocumentSchema).default([]), // Project files/documents
  // Project metadata
  category: z.string().optional(), // e.g., "Genomics", "Proteomics", etc.
  tags: z.array(z.string()).default([]),
  // Progress tracking
  progress: z.number().min(0).max(100).default(0), // Project completion percentage
  lastActivity: z.coerce.date().default(() => new Date())
});

export type Project = z.infer<typeof projectSchema>;

// Project creation schema
export const createProjectSchema = projectSchema.pick({
  name: true,
  description: true,
  instructions: true,
  category: true,
  tags: true
});

export type CreateProject = z.infer<typeof createProjectSchema>;

// ============================================================================
// Workflow Invocation & Output Tracking Schemas
// ============================================================================

// Output dataset schema - tracks files generated by workflow execution
export const outputDatasetSchema = z.object({
  id: z.string(),
  invocationId: z.string(), // Links to workflow invocation
  galaxyDatasetId: z.string(), // Galaxy's dataset ID for fetching

  // File metadata
  name: z.string(),
  extension: z.string(), // 'png', 'tsv', 'html', 'bam', 'fastq', etc
  size: z.number(), // File size in bytes
  createdAt: z.coerce.date(),

  // Display metadata
  fileType: z.enum([
    'image', 'table', 'text', 'binary', 'interactive',
    // Bioinformatics-specific types
    'sequence',    // FASTA, FASTQ
    'alignment',   // BAM, SAM
    'variants',    // VCF
    'annotation',  // BED, GFF, GTF
    'singlecell',  // h5ad, loom
  ]),
  isVisualizable: z.boolean().default(false),
  previewAvailable: z.boolean().default(false),

  // Optional metadata from Galaxy
  metadata: z.object({
    rows: z.number().optional(), // For tables
    columns: z.number().optional(),
    width: z.number().optional(), // For images
    height: z.number().optional(),
    interactive: z.boolean().optional(), // For Plotly/interactive viz
    dataType: z.string().optional(), // Galaxy data type
    // Bioinformatics-specific metadata
    sequenceCount: z.number().optional(), // For FASTA/FASTQ
    avgLength: z.number().optional(),
    gcContent: z.number().optional(),
    variantCount: z.number().optional(), // For VCF
    featureCount: z.number().optional(), // For BED/GFF/GTF
    readCount: z.number().optional(), // For BAM/SAM
    cellCount: z.number().optional(), // For single-cell data
    geneCount: z.number().optional(),
  }).optional(),
});

export type OutputDataset = z.infer<typeof outputDatasetSchema>;

// Input dataset reference
export const inputDatasetSchema = z.object({
  stepId: z.number(),
  parameterName: z.string(),
  source: z.enum(['upload', 'library', 'history', 'url', 'folder']),
  path: z.string().optional(), // For local/folder paths
  galaxyDatasetId: z.string().optional(), // For Galaxy history datasets
  name: z.string().optional(),
});

export type InputDataset = z.infer<typeof inputDatasetSchema>;

// Workflow invocation schema - tracks workflow execution history
export const workflowInvocationSchema = z.object({
  id: z.string(),
  userId: z.string().optional(), // For multi-user support

  // Workflow metadata
  workflowId: z.string().optional(), // If from saved workflow
  workflowName: z.string(),
  workflowDefinition: z.any(), // Full .ga workflow object

  // Execution status
  status: z.enum(['new', 'queued', 'running', 'ok', 'error', 'paused', 'deleted']),
  createdAt: z.coerce.date(),
  updatedAt: z.coerce.date(),
  completedAt: z.coerce.date().optional(),

  // Galaxy integration
  galaxyInvocationId: z.string(),
  galaxyHistoryId: z.string(),
  galaxyWorkflowId: z.string().optional(),

  // Execution details
  totalSteps: z.number().default(0),
  completedSteps: z.number().default(0),
  currentStepIndex: z.number().optional(),
  currentStepName: z.string().optional(),

  // Error tracking
  errorMessage: z.string().optional(),
  errorStep: z.number().optional(),

  // Input/Output tracking
  inputDatasets: z.array(inputDatasetSchema).default([]),
  outputDatasets: z.array(outputDatasetSchema).default([]),

  // Execution logs
  executionLogs: z.string().optional(),

  // Statistics
  outputCount: z.number().default(0),
  totalOutputSize: z.number().default(0), // Total size in bytes
});

export type WorkflowInvocation = z.infer<typeof workflowInvocationSchema>;

// Invocation creation schema (what we receive when starting a workflow)
export const createInvocationSchema = workflowInvocationSchema.pick({
  workflowId: true,
  workflowName: true,
  workflowDefinition: true,
  galaxyInvocationId: true,
  galaxyHistoryId: true,
  galaxyWorkflowId: true,
  inputDatasets: true,
  totalSteps: true,
});

export type CreateInvocation = z.infer<typeof createInvocationSchema>;

// ============================================================================
// Citation & Methods Section Schemas
// ============================================================================

// Citation schema for tool references
export const citationSchema = z.object({
  tool_id: z.string(),
  tool_name: z.string(),
  doi: z.string().optional(),
  pmid: z.string().optional(),
  title: z.string(),
  authors: z.array(z.string()).default([]),
  year: z.number().optional(),
  journal: z.string().optional(),
  formatted_apa: z.string().default(""),
  formatted_short: z.string().default(""),
  formatted_bibtex: z.string().default(""),
});

export type Citation = z.infer<typeof citationSchema>;

// Methods section schema for auto-generated publication text
export const methodsSectionSchema = z.object({
  text: z.string(),
  style: z.enum(["short", "apa", "numbered"]).default("short"),
  tools_cited: z.array(z.string()).default([]),
  tools_missing_citations: z.array(z.string()).default([]),
});

export type MethodsSection = z.infer<typeof methodsSectionSchema>;

// ============================================================================
// Progressive Tuning & Pilot Run Schemas
// ============================================================================

// Tuning configuration for pilot runs
export const tuningConfigSchema = z.object({
  pilot_fraction: z.number().min(0.05).max(0.3).default(0.1),
  sampling_strategy: z.enum(["random", "stratified", "first_n", "representative"]).default("stratified"),
  strata_column: z.string().optional(),
  min_pilot_samples: z.number().min(1).default(3),
  max_pilot_samples: z.number().min(1).default(50),
});

export type TuningConfig = z.infer<typeof tuningConfigSchema>;

// Pilot run result schema
export const pilotResultSchema = z.object({
  pilot_id: z.string(),
  status: z.enum(["pending", "running", "complete", "failed"]),
  progress: z.number().min(0).max(100).default(0),
  runtime_seconds: z.number().optional(),
  peak_memory_gb: z.number().optional(),
  quality_metrics: z.record(z.number()).optional(),
  error_message: z.string().optional(),
});

export type PilotResult = z.infer<typeof pilotResultSchema>;

// Full run estimate schema
export const fullRunEstimateSchema = z.object({
  estimated_runtime_seconds: z.number(),
  estimated_runtime_display: z.string(),
  estimated_memory_gb: z.number(),
  estimated_cost_usd: z.number().optional(),
  confidence: z.number().min(0).max(1).default(0.8),
  scaling_factors: z.record(z.number()).default({}),
});

export type FullRunEstimate = z.infer<typeof fullRunEstimateSchema>;

// ============================================================================
// Parameter Recommendation Schemas
// ============================================================================

// Parameter recommendation from best practices or optimization
export const parameterRecommendationSchema = z.object({
  parameter_name: z.string(),
  recommended_value: z.any(),
  current_value: z.any().optional(),
  confidence: z.number().min(0).max(1).default(0.8),
  source: z.enum(["benchmark", "protocol", "best_practice", "llm_generated"]).default("best_practice"),
  reason: z.string().optional(),
});

export type ParameterRecommendation = z.infer<typeof parameterRecommendationSchema>;

// ============================================================================
// Enhanced Workflow Generation Response Schema
// ============================================================================

// Enhanced workflow generation response with citations and tuning
export const workflowGenerationResponseSchema = z.object({
  success: z.boolean(),
  workflow_ga: z.any().optional(),
  source: z.enum(["template_reuse", "template_adapted", "from_scratch"]).optional(),
  confidence: z.number().default(0),
  message: z.string().default(""),

  // Citation fields
  citations: z.array(citationSchema).default([]),
  methods_section: methodsSectionSchema.optional(),

  // Pilot run suggestion
  pilot_run_suggested: z.boolean().default(false),
  tuning_config: tuningConfigSchema.optional(),

  // Parameter recommendations (keyed by "tool_id:param_name")
  parameter_recommendations: z.record(parameterRecommendationSchema).default({}),
});

export type WorkflowGenerationResponse = z.infer<typeof workflowGenerationResponseSchema>;

// ============================================================================
// Benchmark Result Schema
// ============================================================================

// Benchmark comparison result
export const benchmarkResultSchema = z.object({
  scenario: z.string(),
  available: z.boolean(),
  tools_compared: z.array(z.string()).default([]),
  metrics: z.record(z.any()).default({}),
  recommendations: z.array(z.string()).default([]),
  last_run: z.string().optional(),
  message: z.string().optional(),
  error: z.string().optional(),
});

export type BenchmarkResult = z.infer<typeof benchmarkResultSchema>;

// ============================================================================
// Audit Log Schema - For Regulatory Compliance & Auditability
// ============================================================================

export const auditLogs = pgTable("audit_logs", {
  id: varchar("id").primaryKey().default(sql`gen_random_uuid()`),

  // Who
  userId: text("user_id"), // null for unauthenticated actions
  sessionId: text("session_id"),

  // What
  action: text("action").notNull(), // e.g., "workflow.execute", "dataset.upload", "auth.login"
  resourceType: text("resource_type"), // e.g., "workflow", "dataset", "project"
  resourceId: text("resource_id"),

  // Details
  details: text("details"), // JSON stringified additional context
  reasoning: text("reasoning"), // AI decision reasoning (for workflow generation)

  // When
  timestamp: timestamp("timestamp").defaultNow().notNull(),

  // Context
  ipAddress: text("ip_address"),
  userAgent: text("user_agent"),

  // Result
  status: text("status").default("success"), // "success", "failure", "error"
  errorMessage: text("error_message"),

  // Duration tracking
  durationMs: text("duration_ms"),
});

export const insertAuditLogSchema = createInsertSchema(auditLogs).pick({
  userId: true,
  sessionId: true,
  action: true,
  resourceType: true,
  resourceId: true,
  details: true,
  reasoning: true,
  ipAddress: true,
  userAgent: true,
  status: true,
  errorMessage: true,
  durationMs: true,
});

export type InsertAuditLog = z.infer<typeof insertAuditLogSchema>;
export type AuditLog = typeof auditLogs.$inferSelect;

// Zod schema for audit log validation
export const auditLogSchema = z.object({
  id: z.string(),
  userId: z.string().nullable().optional(),
  sessionId: z.string().nullable().optional(),
  action: z.string(),
  resourceType: z.string().nullable().optional(),
  resourceId: z.string().nullable().optional(),
  details: z.string().nullable().optional(),
  reasoning: z.string().nullable().optional(),
  timestamp: z.coerce.date(),
  ipAddress: z.string().nullable().optional(),
  userAgent: z.string().nullable().optional(),
  status: z.enum(["success", "failure", "error"]).default("success"),
  errorMessage: z.string().nullable().optional(),
  durationMs: z.string().nullable().optional(),
});

export type AuditLogEntry = z.infer<typeof auditLogSchema>;

// ============================================================================
// Workflow Execution User Tracking Schema
// ============================================================================

export const workflowExecutions = pgTable("workflow_executions", {
  id: varchar("id").primaryKey().default(sql`gen_random_uuid()`),

  // Ownership
  userId: text("user_id").notNull(),
  projectId: text("project_id"),

  // Galaxy references
  galaxyInvocationId: text("galaxy_invocation_id").notNull(),
  galaxyWorkflowId: text("galaxy_workflow_id"),
  galaxyHistoryId: text("galaxy_history_id"),

  // Workflow details
  workflowName: text("workflow_name"),
  workflowDefinition: text("workflow_definition"), // JSON stringified .ga

  // Status tracking
  status: text("status").default("new"), // new, queued, running, ok, error
  startedAt: timestamp("started_at").defaultNow(),
  completedAt: timestamp("completed_at"),

  // Error tracking
  errorMessage: text("error_message"),

  // Metadata
  totalSteps: text("total_steps"),
  completedSteps: text("completed_steps"),
  createdAt: timestamp("created_at").defaultNow(),
  updatedAt: timestamp("updated_at").defaultNow(),
});

export type WorkflowExecution = typeof workflowExecutions.$inferSelect;

// ============================================================================
// Unified Workflow Execution & Tuning Schemas
// ============================================================================

// Data scope configuration for tunable data subsets
export const dataScopeSchema = z.object({
  fraction: z.number().min(0.01).max(1.0).default(1.0), // 1% to 100%
  absoluteCount: z.number().optional(),
  totalAvailable: z.number().optional(),
  samplingStrategy: z.enum(["random", "stratified", "first_n", "representative"]).default("random"),
  sampledIds: z.array(z.string()).default([]),
  strataDistribution: z.record(z.number()).optional(), // For stratified sampling
  strataColumn: z.string().optional(),
  explicitSamples: z.array(z.string()).optional(), // User-specified sample IDs
});

export type DataScope = z.infer<typeof dataScopeSchema>;

// Execution environment configuration
export const executionEnvironmentSchema = z.object({
  historyPrefix: z.enum(["[Sandbox]", "[Production]"]).default("[Sandbox]"),
  allowTuning: z.boolean().default(true),
  allowMidRunAdjustment: z.boolean().default(true),
});

export type ExecutionEnvironment = z.infer<typeof executionEnvironmentSchema>;

// Tracking configuration
export const trackingConfigSchema = z.object({
  collectMetrics: z.boolean().default(true),
  collectDetailedMetrics: z.boolean().default(true),
  logLevel: z.enum(["minimal", "normal", "detailed", "verbose"]).default("detailed"),
  notifyMilestones: z.boolean().default(true),
  milestonePercentages: z.array(z.number()).default([25, 50, 75, 100]),
});

export type TrackingConfig = z.infer<typeof trackingConfigSchema>;

// Unified execution configuration
export const executionConfigSchema = z.object({
  mode: z.enum(["sandbox", "production"]).default("sandbox"),
  dataScope: dataScopeSchema.optional(),
  environment: executionEnvironmentSchema.optional(),
  tracking: trackingConfigSchema.optional(),
  parentRunId: z.string().optional(), // Links to previous iteration
  executionEngine: z.enum(["nextflow", "galaxy"]).optional(),
});

export type ExecutionConfig = z.infer<typeof executionConfigSchema>;

// Parameter change tracking
export const parameterChangeSchema = z.object({
  toolId: z.string(),
  paramName: z.string(),
  oldValue: z.any(),
  newValue: z.any(),
  reason: z.string().optional(),
  changedAt: z.coerce.date().default(() => new Date()),
});

export type ParameterChange = z.infer<typeof parameterChangeSchema>;

// Versioned parameters
export const versionedParametersSchema = z.object({
  version: z.number().default(1),
  toolParameters: z.record(z.record(z.any())).default({}), // toolId -> { paramName -> value }
  changedFrom: z.array(parameterChangeSchema).optional(),
});

export type VersionedParameters = z.infer<typeof versionedParametersSchema>;

// Step execution state
export const stepExecutionStatusSchema = z.enum([
  "pending", "queued", "running", "completed", "failed", "skipped", "paused"
]);

export type StepExecutionStatus = z.infer<typeof stepExecutionStatusSchema>;

// Step timing information
export const stepTimingSchema = z.object({
  queuedAt: z.coerce.date().optional(),
  startedAt: z.coerce.date().optional(),
  completedAt: z.coerce.date().optional(),
  durationMs: z.number().optional(),
  pausedDurationMs: z.number().optional(),
});

export type StepTiming = z.infer<typeof stepTimingSchema>;

// Step metrics
export const stepMetricsSchema = z.object({
  memoryUsedGB: z.number().optional(),
  peakMemoryGB: z.number().optional(),
  cpuPercent: z.number().optional(),
  avgCpuPercent: z.number().optional(),
  inputSizeBytes: z.number().optional(),
  outputSizeBytes: z.number().optional(),
  readCount: z.number().optional(), // For sequencing tools
  mappedPercent: z.number().optional(), // For alignment tools
});

export type StepMetrics = z.infer<typeof stepMetricsSchema>;

// Step logs
export const stepLogsSchema = z.object({
  stdout: z.array(z.string()).default([]),
  stderr: z.array(z.string()).default([]),
  truncated: z.boolean().default(false),
  lastLines: z.number().default(100), // Number of lines kept
});

export type StepLogs = z.infer<typeof stepLogsSchema>;

// Step output
export const stepOutputSchema = z.object({
  datasetId: z.string(),
  galaxyDatasetId: z.string().optional(),
  name: z.string(),
  extension: z.string(),
  sizeBytes: z.number(),
  isVisualizable: z.boolean().default(false),
  previewUrl: z.string().optional(),
});

export type StepOutput = z.infer<typeof stepOutputSchema>;

// Step execution - detailed tracking for each workflow step
export const stepExecutionSchema = z.object({
  stepId: z.string(),
  stepIndex: z.number(),
  stepName: z.string(),
  toolId: z.string(),
  toolName: z.string().optional(),

  status: stepExecutionStatusSchema,
  timing: stepTimingSchema.optional(),
  metrics: stepMetricsSchema.optional(),
  logs: stepLogsSchema.optional(),
  outputs: z.array(stepOutputSchema).default([]),

  // Error details
  errorMessage: z.string().optional(),
  errorCode: z.string().optional(),

  // Galaxy references
  galaxyJobId: z.string().optional(),
});

export type StepExecution = z.infer<typeof stepExecutionSchema>;

// User interaction types
export const userInteractionTypeSchema = z.enum([
  "parameter_change",
  "pause",
  "resume",
  "cancel",
  "apply_recommendation",
  "adjust_data_scope",
  "retry_step",
  "view_logs",
  "download_output"
]);

export type UserInteractionType = z.infer<typeof userInteractionTypeSchema>;

// User interaction - tracks all user actions during execution
export const userInteractionSchema = z.object({
  id: z.string().default(() => crypto.randomUUID()),
  timestamp: z.coerce.date().default(() => new Date()),
  type: userInteractionTypeSchema,
  details: z.record(z.any()).default({}),
  reason: z.string().optional(), // User's stated reason
  userId: z.string().optional(),
});

export type UserInteraction = z.infer<typeof userInteractionSchema>;

// Runtime metrics
export const runtimeMetricsSchema = z.object({
  totalSeconds: z.number().default(0),
  perStepSeconds: z.record(z.number()).default({}), // stepId -> seconds
  estimatedRemaining: z.number().optional(),
  startedAt: z.coerce.date().optional(),
  completedAt: z.coerce.date().optional(),
});

export type RuntimeMetrics = z.infer<typeof runtimeMetricsSchema>;

// Resource metrics
export const resourceMetricsSchema = z.object({
  peakMemoryGB: z.number().default(0),
  avgCpuPercent: z.number().default(0),
  diskUsedGB: z.number().default(0),
  networkBytesIn: z.number().optional(),
  networkBytesOut: z.number().optional(),
});

export type ResourceMetrics = z.infer<typeof resourceMetricsSchema>;

// Output metrics
export const outputMetricsSchema = z.object({
  fileCount: z.number().default(0),
  totalSizeBytes: z.number().default(0),
  byType: z.record(z.number()).default({}), // extension -> count
  bySize: z.record(z.number()).default({}), // extension -> total bytes
});

export type OutputMetrics = z.infer<typeof outputMetricsSchema>;

// Execution metrics - comprehensive metrics collection
export const executionMetricsSchema = z.object({
  runtime: runtimeMetricsSchema.optional(),
  resources: resourceMetricsSchema.optional(),
  quality: z.record(z.number()).default({}), // Domain-specific quality metrics
  outputs: outputMetricsSchema.optional(),
});

export type ExecutionMetrics = z.infer<typeof executionMetricsSchema>;

// Run comparison
export const runComparisonSchema = z.object({
  previousRunId: z.string(),
  runtimeDelta: z.number().optional(), // % change
  memoryDelta: z.number().optional(), // % change
  qualityDelta: z.record(z.number()).default({}), // metric -> delta
  improvementSummary: z.string().optional(),
  recommendation: z.string().optional(),
});

export type RunComparison = z.infer<typeof runComparisonSchema>;

// Execution run status
export const executionRunStatusSchema = z.enum([
  "configuring", "queued", "running", "paused", "completed", "failed", "cancelled"
]);

export type ExecutionRunStatus = z.infer<typeof executionRunStatusSchema>;

// Execution Run - the main unified workflow execution record
export const executionRunSchema = z.object({
  // Identity
  id: z.string().default(() => crypto.randomUUID()),
  parentRunId: z.string().optional(), // Links iterations together
  runSequence: z.number().default(1), // 1, 2, 3... within iteration cycle

  // Ownership
  userId: z.string().optional(),
  projectId: z.string().optional(),
  chatSessionId: z.string().optional(),

  // Mode
  mode: z.enum(["sandbox", "production"]).default("sandbox"),

  // Workflow
  workflowName: z.string(),
  workflowDefinition: z.any().optional(), // Full .ga workflow object

  // Data Scope (TUNABLE)
  dataScope: dataScopeSchema,

  // Parameters (VERSIONED)
  parameters: versionedParametersSchema,

  // Execution state
  execution: z.object({
    galaxyInvocationId: z.string().optional(),
    galaxyHistoryId: z.string().optional(),
    galaxyWorkflowId: z.string().optional(),
    executionEngine: z.string().optional(),
    status: executionRunStatusSchema,
    startedAt: z.coerce.date().optional(),
    completedAt: z.coerce.date().optional(),
    pausedAt: z.coerce.date().optional(),
    pauseReason: z.string().optional(),
    errorMessage: z.string().optional(),
  }),

  // Progress
  progress: z.object({
    totalSteps: z.number().default(0),
    completedSteps: z.number().default(0),
    currentStepIndex: z.number().optional(),
    currentStepName: z.string().optional(),
    percentComplete: z.number().default(0),
    milestone: z.number().optional(), // Last reached milestone (25, 50, 75, 100)
  }),

  // Step-Level Tracking
  steps: z.array(stepExecutionSchema).default([]),

  // Metrics (DETAILED)
  metrics: executionMetricsSchema.optional(),

  // User Interactions
  interactions: z.array(userInteractionSchema).default([]),

  // Recommendations
  recommendations: z.array(parameterRecommendationSchema).default([]),

  // Comparison (if iterating)
  comparison: runComparisonSchema.optional(),

  // Timestamps
  createdAt: z.coerce.date().default(() => new Date()),
  updatedAt: z.coerce.date().default(() => new Date()),
});

export type ExecutionRun = z.infer<typeof executionRunSchema>;

// Execution run creation request
export const createExecutionRunRequestSchema = z.object({
  workflowDefinition: z.any(), // .ga format

  executionConfig: executionConfigSchema,

  inputs: z.array(z.object({
    stepId: z.number().optional(),
    src: z.string(),
    id: z.string(),
    name: z.string().optional(),
  })).optional(),
});

export type CreateExecutionRunRequest = z.infer<typeof createExecutionRunRequestSchema>;

// Execution run creation response
export const createExecutionRunResponseSchema = z.object({
  runId: z.string(),
  galaxyInvocationId: z.string().optional(),
  galaxyHistoryId: z.string().optional(),
  executionEngine: z.enum(["nextflow", "galaxy"]).optional(),
  status: executionRunStatusSchema,
  dataScopeApplied: z.object({
    fraction: z.number(),
    absoluteCount: z.number(),
    sampledIds: z.array(z.string()),
  }).optional(),
});

export type CreateExecutionRunResponse = z.infer<typeof createExecutionRunResponseSchema>;

// Execution run status response (for polling)
export const executionRunStatusResponseSchema = z.object({
  runId: z.string(),
  status: executionRunStatusSchema,
  progress: z.object({
    totalSteps: z.number(),
    completedSteps: z.number(),
    percentComplete: z.number(),
    currentStepName: z.string().optional(),
    milestone: z.number().optional(),
  }),
  metrics: executionMetricsSchema.optional(),
  steps: z.array(stepExecutionSchema).optional(),
  errorMessage: z.string().optional(),
  nextflowStatus: z.any().optional(),
});

export type ExecutionRunStatusResponse = z.infer<typeof executionRunStatusResponseSchema>;

// Run comparison request
export const runComparisonRequestSchema = z.object({
  runId: z.string(),
  compareWithRunId: z.string(),
});

export type RunComparisonRequest = z.infer<typeof runComparisonRequestSchema>;

// Run comparison response
export const runComparisonResponseSchema = z.object({
  runs: z.array(executionRunSchema),
  comparison: z.object({
    runtimeDelta: z.number().optional(),
    memoryDelta: z.number().optional(),
    qualityDelta: z.record(z.number()).default({}),
  }),
  recommendation: z.object({
    preferredRun: z.string(),
    reason: z.string(),
    fullRunEstimate: fullRunEstimateSchema.optional(),
  }).optional(),
});

export type RunComparisonResponse = z.infer<typeof runComparisonResponseSchema>;

// ============================================================================
// Database Table for Execution Runs (Persistent Storage)
// ============================================================================

export const executionRuns = pgTable("execution_runs", {
  id: varchar("id").primaryKey().default(sql`gen_random_uuid()`),
  parentRunId: varchar("parent_run_id"),
  runSequence: text("run_sequence").default("1"),

  // Ownership
  userId: text("user_id"),
  projectId: text("project_id"),
  chatSessionId: text("chat_session_id"),

  // Mode & Workflow
  mode: text("mode").default("sandbox"),
  workflowName: text("workflow_name").notNull(),
  workflowDefinition: text("workflow_definition"), // JSON stringified

  // Data Scope (JSON)
  dataScope: text("data_scope"), // JSON stringified DataScope

  // Parameters (JSON)
  parameters: text("parameters"), // JSON stringified VersionedParameters

  // Execution state
  galaxyInvocationId: text("galaxy_invocation_id"),
  galaxyHistoryId: text("galaxy_history_id"),
  galaxyWorkflowId: text("galaxy_workflow_id"),
  status: text("status").default("configuring"),
  startedAt: timestamp("started_at"),
  completedAt: timestamp("completed_at"),
  pausedAt: timestamp("paused_at"),
  pauseReason: text("pause_reason"),
  errorMessage: text("error_message"),

  // Progress
  totalSteps: text("total_steps").default("0"),
  completedSteps: text("completed_steps").default("0"),
  currentStepIndex: text("current_step_index"),
  currentStepName: text("current_step_name"),
  percentComplete: text("percent_complete").default("0"),

  // Steps (JSON array)
  steps: text("steps"), // JSON stringified StepExecution[]

  // Metrics (JSON)
  metrics: text("metrics"), // JSON stringified ExecutionMetrics

  // Interactions (JSON array)
  interactions: text("interactions"), // JSON stringified UserInteraction[]

  // Recommendations (JSON array)
  recommendations: text("recommendations"), // JSON stringified ParameterRecommendation[]

  // Comparison (JSON)
  comparison: text("comparison"), // JSON stringified RunComparison

  // Timestamps
  createdAt: timestamp("created_at").defaultNow(),
  updatedAt: timestamp("updated_at").defaultNow(),
});

export type ExecutionRunDB = typeof executionRuns.$inferSelect;

export const insertExecutionRunSchema = createInsertSchema(executionRuns);
export type InsertExecutionRun = z.infer<typeof insertExecutionRunSchema>;
