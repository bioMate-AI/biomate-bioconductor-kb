import { sql } from "drizzle-orm";
import { pgTable, text, varchar, timestamp, boolean, integer, numeric, jsonb, bigint, bigserial, uuid } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod";

export const users = pgTable("users", {
  id: varchar("id").primaryKey().default(sql`gen_random_uuid()`),
  email: text("email").notNull().unique(),
  password: text("password").notNull(),
  fullName: text("full_name").notNull(),
  organization: text("organization"),   // institution / employer
  role: text("role"),                   // PI, Postdoc, Research Scientist, etc.
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

  // MFA (TOTP)
  mfaSecret: text("mfa_secret"),                          // AES-256-GCM encrypted base32 secret
  mfaEnabled: boolean("mfa_enabled").default(false),
  mfaVerifiedAt: timestamp("mfa_verified_at"),
  mfaRecoveryCodes: text("mfa_recovery_codes"),           // JSON array of bcrypt-hashed codes
  mfaFailedAttempts: integer("mfa_failed_attempts").default(0),
  mfaLockoutUntil: timestamp("mfa_lockout_until"),

  // Timestamps
  createdAt: timestamp("created_at").defaultNow(),
  updatedAt: timestamp("updated_at").defaultNow(),
  lastLoginAt: timestamp("last_login_at"),

  // Session control — set at login; rememberMe=false means 24h, true means 30d
  rememberMe: boolean("remember_me").default(false),
  sessionExpiresAt: timestamp("session_expires_at"),

  // Metadata
  termsAcceptedAt: timestamp("terms_accepted_at"),
  marketingEmailsOptIn: boolean("marketing_emails_opt_in").default(false),

  // Galaxy integration (preserve existing data)
  galaxyUserId: text("galaxy_user_id"),
  galaxyApiKey: text("galaxy_api_key"),
  galaxyUsername: text("galaxy_username"),

  // Per-user LLM API keys (AES-256-GCM encrypted).
  // Schema: { anthropic?: string }
  // Added in migration 0019_user_llm_api_keys.sql
  llmApiKeys: jsonb("llm_api_keys"),

  // Invite code (set at registration) — FK added via migration; lazy ref avoids circular init
  inviteCodeId: varchar("invite_code_id"),
  // NOTE: .references(() => inviteCodes.id) can't be set here because inviteCodes is defined
  // after users in this file. Add the FK constraint in your next Drizzle migration:
  //   ALTER TABLE users ADD CONSTRAINT users_invite_code_id_fkey
  //     FOREIGN KEY (invite_code_id) REFERENCES invite_codes(id);
});

// ============================================================================
// Invite Code Tables — for closed beta access control
// ============================================================================

export const inviteCodes = pgTable("invite_codes", {
  id: varchar("id").primaryKey().default(sql`gen_random_uuid()`),
  code: varchar("code", { length: 32 }).notNull().unique(),
  description: text("description"),
  createdBy: varchar("created_by"),

  // Usage limits
  maxUses: integer("max_uses").default(1),       // null = unlimited
  usedCount: integer("used_count").default(0).notNull(),

  // Trial overrides (null = use platform defaults)
  trialDays: integer("trial_days"),              // e.g. 30 for extended beta
  quotaOverrideUsd: numeric("quota_override_usd", { precision: 10, scale: 2 }),
  subscriptionTier: text("subscription_tier").default("academic"),

  // Validity
  expiresAt: timestamp("expires_at"),
  active: boolean("active").default(true).notNull(),

  createdAt: timestamp("created_at").defaultNow().notNull(),
});

export type InviteCode = typeof inviteCodes.$inferSelect;

export const inviteCodeUses = pgTable("invite_code_uses", {
  id: varchar("id").primaryKey().default(sql`gen_random_uuid()`),
  inviteCodeId: varchar("invite_code_id").notNull().references(() => inviteCodes.id),
  userId: varchar("user_id").notNull().references(() => users.id),
  usedAt: timestamp("used_at").defaultNow().notNull(),
});

export type InviteCodeUse = typeof inviteCodeUses.$inferSelect;

export const insertInviteCodeSchema = createInsertSchema(inviteCodes).pick({
  code: true,
  description: true,
  createdBy: true,
  maxUses: true,
  trialDays: true,
  quotaOverrideUsd: true,
  subscriptionTier: true,
  expiresAt: true,
});

export type InsertInviteCode = z.infer<typeof insertInviteCodeSchema>;

// ============================================================================
// Pilot Experiments Table — Track 2C: Experiment Test Harness
// ============================================================================

export const experiments = pgTable("experiments", {
  id: varchar("id").primaryKey().default(sql`gen_random_uuid()`),
  userId: varchar("user_id").notNull().references(() => users.id),

  // Experiment definition
  hypothesis: text("hypothesis").notNull(),
  workflowId: text("workflow_id").notNull(),
  workflowName: text("workflow_name"),
  controlLabel: text("control_label").default("Control"),
  experimentalLabel: text("experimental_label").default("Experimental"),
  controlParams: text("control_params").notNull(),      // JSON object
  experimentalParams: text("experimental_params").notNull(), // JSON object
  metrics: text("metrics").notNull(),                   // JSON string[]

  // Execution state
  status: text("status").notNull().default("pending"),  // pending/running/completed/failed
  controlRunId: text("control_run_id"),
  experimentalRunId: text("experimental_run_id"),

  // Results
  comparisonResult: text("comparison_result"),  // JSON RunComparisonResponse
  narrative: text("narrative"),
  errorMessage: text("error_message"),

  createdAt: timestamp("created_at").defaultNow(),
  updatedAt: timestamp("updated_at").defaultNow(),
});

export type Experiment = typeof experiments.$inferSelect;
export type InsertExperiment = typeof experiments.$inferInsert;

// ============================================================================

export const insertUserSchema = createInsertSchema(users).pick({
  email: true,
  password: true,
  fullName: true,
  organization: true,
  role: true,
  phone: true,
  termsAcceptedAt: true,
  marketingEmailsOptIn: true,
});

export type InsertUser = z.infer<typeof insertUserSchema>;
export type User = typeof users.$inferSelect;

// Explicit type for user without password (for API responses)
export type SafeUser = Omit<User, 'password'>;

// ============================================================================
// Per-user API keys for headless / connector (biomate-connector) access.
// Plaintext is shown once at creation; only the SHA-256 hash is stored.
// See migrations/0010_api_keys.sql.
// ============================================================================
export const apiKeys = pgTable("api_keys", {
  id: varchar("id").primaryKey().default(sql`gen_random_uuid()`),
  userId: varchar("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  keyHash: text("key_hash").notNull().unique(),
  keyPrefix: text("key_prefix").notNull(),
  name: text("name"),
  createdAt: timestamp("created_at").defaultNow().notNull(),
  lastUsedAt: timestamp("last_used_at"),
  revokedAt: timestamp("revoked_at"),
});

export type ApiKey = typeof apiKeys.$inferSelect;
export type InsertApiKey = typeof apiKeys.$inferInsert;

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
  type: z.enum(["file", "text", "url", "notes_synthesis"]),
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
    'sequence',     // FASTA, FASTQ
    'alignment',    // BAM, SAM
    'variants',     // VCF
    'annotation',   // BED, GFF, GTF
    'singlecell',   // h5ad, loom
    // Structural biology types
    'structure',    // PDB, mmCIF, CIF — 3Dmol.js viewer
    'density_map',  // MRC, MAP — cryo-EM density slice viewer
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
     source: z.string().optional(), // e.g. 'nextflow_runtime_artifact', 'galaxy'
     localPath: z.string().optional(), // Local filesystem path for Nextflow outputs
     s3Uri: z.string().optional(),    // S3 URI for cloud-stored Nextflow outputs
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

// ============================================================================
// Output Access Log — per-file download audit trail
// Mirrors migration 0017_output_access_log.sql. Required by the counted
// /api/runs/:id/output/:filename endpoint; replaces direct user S3 access.
// See docs/20260619_OUTPUT_LOCKDOWN_PHASE_B_C_SPEC.md (B.2).
// ============================================================================

export const outputAccessLog = pgTable("output_access_log", {
  id: bigserial("id", { mode: "number" }).primaryKey(),
  runId: text("run_id").notNull(),
  filename: text("filename").notNull(),
  userId: text("user_id").notNull(),
  userEmail: text("user_email"),
  projectId: text("project_id"),                     // nullable for runs not in a project
  ipAddress: text("ip_address"),                     // PG INET cast handled at insert
  userAgent: text("user_agent"),
  httpStatus: integer("http_status"),                // 200 / 302 / 403 / 404
  fileSizeBytes: bigint("file_size_bytes", { mode: "number" }),
  accessedAt: timestamp("accessed_at").defaultNow().notNull(),
});

export type OutputAccessLog = typeof outputAccessLog.$inferSelect;
export type InsertOutputAccessLog = typeof outputAccessLog.$inferInsert;

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
  samplingStrategy: z.enum(["random", "stratified", "first_n", "representative", "sequential"]).default("random"),
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
  retryOfRunId: z.string().optional(), // Explicit manual retry context
  retryOfInvocationId: z.string().optional(), // Explicit manual retry context
  executionEngine: z.enum(["nextflow", "galaxy", "chain", "pipeline"]).optional(),
  // Explicit operator override for low-confidence generation states.
  allowLowConfidence: z.boolean().optional(),
  // Named QC profile — selects a curated threshold set (e.g. "rnaseq_ribodepleted")
  qcProfile: z.string().optional(),
  // Per-metric threshold overrides (map of metric name → numeric value)
  qcOverrides: z.record(z.string(), z.number()).optional(),
  // US-4.2 — auto-apply toggle: false = always pause at QC failures (default); true = auto-apply high-confidence suggestions and continue
  pauseAtQcFailures: z.boolean().optional(),
  // Low-level compute override: executor, memory, GPU. Passed through to buildNextflowComputeConfig.
  computeConfig: z.record(z.string(), z.unknown()).optional(),
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
  "autofix",
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

// Per-step LLM cost breakdown.
// Each entry maps stepId -> cost in USD.  Null means the step did not trigger an LLM call.
// Currently null for all steps (no per-step LLM calls in the pipeline); placeholder for
// future step-level analysis features.
export const perStepLlmCostSchema = z.record(z.number().nullable()).default({});

export type PerStepLlmCost = z.infer<typeof perStepLlmCostSchema>;

// Execution metrics - comprehensive metrics collection
export const executionMetricsSchema = z.object({
  runtime: runtimeMetricsSchema.optional(),
  resources: resourceMetricsSchema.optional(),
  quality: z.record(z.number()).default({}), // Domain-specific quality metrics
  outputs: outputMetricsSchema.optional(),
  perStepLlmCost: perStepLlmCostSchema.optional(), // stepId -> USD cost (null = no LLM call for that step)
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
    nextflowRunId: z.string().optional(),
    nextflowOutputDir: z.string().optional(),
    executionEngine: z.string().optional(),
    nextflowStatus: z.any().optional(),
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
  chatSessionId: z.string().optional(),
  projectId: z.string().optional(),

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
  executionEngine: z.enum(["nextflow", "galaxy", "chain", "pipeline"]).optional(),
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
  autofix: z
    .object({
      state: z.enum(["idle", "analyzing", "fixing", "restarting", "succeeded", "failed"]),
      source: z.enum(["auto", "manual", "unknown"]).optional(),
      active: z.boolean().optional(),
      lastActionAt: z.string().optional(),
      message: z.string().optional(),
      sessionId: z.string().optional(),
      totalAttempts: z.number().optional(),
      terminationReason: z.string().optional(),
    })
    .optional(),
  artifactReadiness: z
    .object({
      hasOutputs: z.boolean().optional(),
      visualizableCount: z.number().optional(),
      downloadableCount: z.number().optional(),
      totalOutputs: z.number().optional(),
      meetsContract: z.boolean().optional(),
    })
    .optional(),
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
    parameterDifferences: z.array(z.object({
      param: z.string(),
      run1Value: z.any(),
      run2Value: z.any(),
    })).optional(),
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

  // Full execution state JSON blob (Nextflow metadata, etc.)
  executionJson: text("execution_json"),
  nextflowRunId: text("nextflow_run_id"),
  nextflowOutputDir: text("nextflow_output_dir"),

  // Timestamps
  createdAt: timestamp("created_at").defaultNow(),
  updatedAt: timestamp("updated_at").defaultNow(),
});

export type ExecutionRunDB = typeof executionRuns.$inferSelect;

export const insertExecutionRunSchema = createInsertSchema(executionRuns);
export type InsertExecutionRun = z.infer<typeof insertExecutionRunSchema>;

// ============================================================================
// UX Feedback Schema
// ============================================================================

export const feedbackTypeEnum = ['inline_thumbs', 'post_run_survey', 'report_confusion', 'download_outcome', 'session_pulse'] as const;
export type FeedbackType = (typeof feedbackTypeEnum)[number];

export const feedbackRatingEnum = ['positive', 'negative'] as const;
export type FeedbackRating = (typeof feedbackRatingEnum)[number];

export const feedbackReasonTags = [
  'unclear_output',
  'wrong_tool',
  'slow',
  'confusing_ui',
  'missing_feature',
  'error_not_helpful',
  'workflow_failed',
  'other',
] as const;
export type FeedbackReasonTag = (typeof feedbackReasonTags)[number];

export const uxFeedback = pgTable("ux_feedback", {
  id: varchar("id").primaryKey().default(sql`gen_random_uuid()`),

  // Who (nullable for anonymous)
  userId: text("user_id"),
  sessionId: text("session_id"),

  // Feedback type and sentiment
  feedbackType: text("feedback_type").notNull(),
  rating: text("rating").notNull(), // positive | negative

  // Structured context
  reasonTags: text("reason_tags"), // JSON array of reason tag strings
  comment: text("comment"),

  // Correlation IDs
  runId: text("run_id"),
  workflowId: text("workflow_id"),
  messageId: text("message_id"),

  // Context metadata (for report_confusion, post_run_survey)
  executionStatus: text("execution_status"),
  errorMessage: text("error_message"),
  uiRoute: text("ui_route"),

  // Survey scores (1-5, for post_run_survey)
  statusClarityScore: integer("status_clarity_score"),
  outputUsefulnessScore: integer("output_usefulness_score"),
  outputActionabilityScore: integer("output_actionability_score"),

  // Timestamps
  createdAt: timestamp("created_at").defaultNow().notNull(),
});

export type UxFeedback = typeof uxFeedback.$inferSelect;
export type InsertUxFeedback = typeof uxFeedback.$inferInsert;

// API payload validation schema
export const feedbackPayloadSchema = z.object({
  feedbackType: z.enum(feedbackTypeEnum),
  rating: z.enum(feedbackRatingEnum),
  reasonTags: z.array(z.string()).max(5).optional(),
  comment: z.string().max(2000).optional(),
  sessionId: z.string().optional(),
  runId: z.string().optional(),
  workflowId: z.string().optional(),
  messageId: z.string().optional(),
  executionStatus: z.string().optional(),
  errorMessage: z.string().max(500).optional(),
  uiRoute: z.string().max(200).optional(),
  statusClarityScore: z.number().min(1).max(5).optional(),
  outputUsefulnessScore: z.number().min(1).max(5).optional(),
  outputActionabilityScore: z.number().min(1).max(5).optional(),
});

export type FeedbackPayload = z.infer<typeof feedbackPayloadSchema>;

// ============================================================================
// Telemetry Events Schema
// ============================================================================

export const telemetryEvents = pgTable("telemetry_events", {
  id: varchar("id").primaryKey().default(sql`gen_random_uuid()`),

  // Event identity
  event: text("event").notNull(),
  timestamp: timestamp("timestamp").notNull(),

  // Payload (JSON) - sessionId, runId, workflowId, etc.
  payload: text("payload"),

  createdAt: timestamp("created_at").defaultNow().notNull(),
});

export type TelemetryEvent = typeof telemetryEvents.$inferSelect;
export type InsertTelemetryEvent = typeof telemetryEvents.$inferInsert;

// API payload validation schema for telemetry envelope
export const telemetryEventEnvelopeSchema = z.object({
  event: z.string().min(1).max(200),
  timestamp: z.string().min(1),
  payload: z.record(z.unknown()).optional(),
});

// ============================================================================
// Feature Flags — runtime-togglable feature gates (replaces scattered env vars)
// ============================================================================

export const featureFlags = pgTable("feature_flags", {
  flagName: varchar("flag_name", { length: 128 }).primaryKey(),
  enabled: boolean("enabled").notNull().default(false),
  /** 0–100: percentage of users this flag is active for (100 = everyone) */
  rolloutPct: integer("rollout_pct").notNull().default(100),
  /**
   * Per-user overrides: JSON object {"<userId>": true|false}.
   * Takes precedence over rolloutPct when the userId key is present.
   */
  userOverrides: text("user_overrides").default("{}"),
  description: text("description"),
  updatedAt: timestamp("updated_at").defaultNow().notNull(),
});

export type FeatureFlag = typeof featureFlags.$inferSelect;
export type InsertFeatureFlag = typeof featureFlags.$inferInsert;

// ────────────────────────────────────────────────────────────────────────────
// Instrument Events
// Records new-data notifications from physical instrument connectors
// (flow cytometer, plate reader, qPCR, LC-MS, cryo-EM, etc.)
// ────────────────────────────────────────────────────────────────────────────

export const instrumentEvents = pgTable("instrument_events", {
  id: varchar("id").primaryKey().default(sql`gen_random_uuid()`),

  // Source connector
  source: text("source").notNull(),       // e.g. "flow_cytometer_watcher"
  vendor: text("vendor"),                 // e.g. "biorad_cfx", "bmg"
  directory: text("directory"),           // watched directory path

  // Experiment classification
  experimentType: text("experiment_type").notNull(),  // e.g. "rt_qpcr_expression"
  assayType: text("assay_type"),                       // plate reader only
  workflowId: text("workflow_id").notNull(),            // BioMate workflow to launch

  // Data location
  filePath: text("file_path"),            // single file path (qPCR, plate reader)
  fcsDir: text("fcs_dir"),               // flow cytometry directory
  fileCount: integer("file_count"),       // flow cytometry file count
  paramKey: text("param_key"),           // e.g. "qpcr_data_file", "fcs_dir"

  // Run metadata
  runName: text("run_name"),
  targets: text("targets"),              // JSON array of target/gene names
  sampleCount: integer("sample_count"),
  channels: text("channels"),            // JSON array of FCS channels

  // Analysis
  analysisFunction: text("analysis_function"),

  // Human-readable
  description: text("description").notNull(),
  message: text("message").notNull(),

  // Lifecycle
  status: text("status").notNull().default("pending"),
  // "pending"   = received, not yet acted on
  // "launched"  = BioMate workflow execution started
  // "dismissed" = user dismissed without launching

  userId: text("user_id"),               // set when user acts on the notification
  timestamp: timestamp("timestamp").defaultNow().notNull(),
});

export const insertInstrumentEventSchema = createInsertSchema(instrumentEvents).pick({
  source: true,
  vendor: true,
  directory: true,
  experimentType: true,
  assayType: true,
  workflowId: true,
  filePath: true,
  fcsDir: true,
  fileCount: true,
  paramKey: true,
  runName: true,
  targets: true,
  sampleCount: true,
  channels: true,
  analysisFunction: true,
  description: true,
  message: true,
});

export type InstrumentEvent = typeof instrumentEvents.$inferSelect;
export type InsertInstrumentEvent = typeof instrumentEvents.$inferInsert;

// ============================================================================
// Instrument Configurations — user-registered lab instruments
// Each row is one physical instrument or cloud service registered by a user.
// ============================================================================

export const instruments = pgTable("instruments", {
  id: varchar("id").primaryKey().default(sql`gen_random_uuid()`),
  userId: text("user_id").notNull(),

  // Identity
  name: text("name").notNull(),         // user-given label, e.g. "Lab OT-2 (Bench 3)"
  type: text("type").notNull(),         // see INSTRUMENT_TYPES below

  // Network connection (for local instruments)
  host: text("host"),                   // IP address or hostname
  port: integer("port"),                // API port (default varies by type)

  // Auth (cloud services)
  apiKey: text("api_key"),              // Benchling sk_..., BaseSpace token, etc.
  oauthToken: text("oauth_token"),      // current access token (OAuth2)
  oauthRefreshToken: text("oauth_refresh_token"),

  // Type-specific config (JSON blob)
  // e.g. {outputDir: "/cryoem/sessions", minMovies: 50, settleSeconds: 300}
  config: text("config"),

  // Live status (updated by health check)
  status: text("status").notNull().default("unknown"),
  // "unknown" | "online" | "offline" | "error"
  lastSeenAt: timestamp("last_seen_at"),
  lastError: text("last_error"),

  createdAt: timestamp("created_at").defaultNow().notNull(),
  updatedAt: timestamp("updated_at").defaultNow().notNull(),
});

// Canonical type identifiers — must match connector file names in biomate-connectors-v2
export const INSTRUMENT_TYPES = [
  "opentrons",        // Opentrons OT-2 / Flex (HTTP API, local)
  "minknow",          // Nanopore MinKNOW (HTTP API, local)
  "epu",              // Thermo Fisher EPU / CryoEM (HTTP API or file-watcher)
  "flow_cytometer",   // Flow cytometer file-watcher (FCS files)
  "lcms",             // LC-MS file-watcher (Thermo, Waters, Bruker, SCIEX)
  "qpcr",             // qPCR file-watcher (Bio-Rad, ABI)
  "plate_reader",     // Plate reader file-watcher (BMG, BioTek, Tecan)
  "sila2",            // Generic SiLA2 device (gRPC)
  "basespace",        // Illumina BaseSpace (OAuth2, cloud)
  "benchling",        // Benchling ELN/LIMS (REST API, cloud)
] as const;

export type InstrumentType = typeof INSTRUMENT_TYPES[number];

export type Instrument = typeof instruments.$inferSelect;
export type InsertInstrument = typeof instruments.$inferInsert;

// ============================================================================
// Async Job Queue (download_jobs) — see docs/20260602_ASYNC_JOB_QUEUE_DESIGN.md
// ============================================================================

export const downloadJobs = pgTable("download_jobs", {
  id: uuid("id").primaryKey().default(sql`gen_random_uuid()`),
  userId: text("user_id").notNull(),
  kind: text("kind").notNull(),
  payload: jsonb("payload").notNull(),
  dedupKey: text("dedup_key").notNull(),
  state: text("state").notNull(),
  progress: integer("progress").notNull().default(0),
  etaSeconds: integer("eta_seconds"),
  artifactUri: text("artifact_uri"),
  artifactBytes: bigint("artifact_bytes", { mode: "number" }),
  error: text("error"),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
  startedAt: timestamp("started_at", { withTimezone: true }),
  readyAt: timestamp("ready_at", { withTimezone: true }),
  expiresAt: timestamp("expires_at", { withTimezone: true }),
  cancelledAt: timestamp("cancelled_at", { withTimezone: true }),
});

export type DownloadJob = typeof downloadJobs.$inferSelect;
export type InsertDownloadJob = typeof downloadJobs.$inferInsert;

export const DOWNLOAD_JOB_ACTIVE_STATES = ["queued", "running"] as const;
export const DOWNLOAD_JOB_DEDUP_STATES = ["queued", "running", "ready"] as const;
export const DOWNLOAD_JOB_TERMINAL_STATES = ["ready", "failed", "cancelled", "expired"] as const;

