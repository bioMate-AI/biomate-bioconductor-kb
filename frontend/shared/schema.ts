import { sql } from "drizzle-orm";
import { pgTable, text, varchar } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod";

export const users = pgTable("users", {
  id: varchar("id").primaryKey().default(sql`gen_random_uuid()`),
  username: text("username").notNull().unique(),
  password: text("password").notNull(),
});

export const insertUserSchema = createInsertSchema(users).pick({
  username: true,
  password: true,
});

export type InsertUser = z.infer<typeof insertUserSchema>;
export type User = typeof users.$inferSelect;

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
  datasets: z.array(datasetConfigSchema).optional()
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
  status: z.enum(["active", "archived"]).default("active")
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
