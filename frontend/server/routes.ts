import type { Express } from "express";
import { createServer, type Server } from "http";
import { storage } from "./storage";
import OpenAI from "openai";
import { datasetConfigSchema } from "../shared/schema";
import { mockGalaxyAPI } from "./mock-galaxy-api";
import { GalaxyAPIProxy } from "./galaxy-api-proxy";
import { createPoller } from "./galaxy-state-poller";
import { WorkflowSSEManager } from "./workflow-sse";
import { GalaxyAssistant } from "./galaxy-assistant";
import { parameterRepository } from "./parameter-repository";
import { workflowRepository } from "./workflow-repository";
import { datasetValidator } from "./dataset-validator";
import multer from "multer";
import { promises as fs } from "fs";
import path from "path";
import { v4 as uuidv4 } from "uuid";

// Initialize OpenAI
const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

// Initialize Galaxy backend - using REAL Galaxy API (no more mock)
const galaxyAPIBackend = new GalaxyAPIProxy(); // Real Galaxy API for all operations
const galaxyAPIProxy = galaxyAPIBackend; // Alias for consistency

// Initialize state poller and SSE manager
const galaxyPoller = createPoller(galaxyAPIBackend, { pollInterval: 2000 });
const sseManager = new WorkflowSSEManager(galaxyPoller);

// Initialize Galaxy Assistant (hybrid intelligence)
const galaxyAssistant = new GalaxyAssistant({
  openaiApiKey: process.env.OPENAI_API_KEY!,
  galaxyAPIProxy,
});

// Configure multer for file uploads
const uploadDir = path.join(process.cwd(), 'data', 'uploads');
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
    fileSize: 500 * 1024 * 1024, // 500MB max file size
  },
});

export async function registerRoutes(app: Express): Promise<Server> {
  // Initialize repositories
  await parameterRepository.initialize();
  await workflowRepository.initialize();

  // Seed example templates on first run
  const templates = await parameterRepository.searchTemplates({});
  if (templates.count === 0) {
    console.log('[Server] Seeding example parameter templates...');
    await parameterRepository.seedExamples();
  }

  const workflowTemplates = await workflowRepository.searchTemplates({});
  if (workflowTemplates.count === 0) {
    console.log('[Server] Seeding example workflow templates...');
    await workflowRepository.seedExamples();
  }

  // Health check
  app.get("/api/health", (req, res) => {
    res.json({ status: "ok", timestamp: new Date().toISOString() });
  });

  // ============================================================================
  // Galaxy Tool Search API
  // ============================================================================

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

  app.get("/api/galaxy/tools/:toolId/schema", async (req, res) => {
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

  // File Upload API
  app.post("/api/datasets/upload", upload.single('file'), async (req, res) => {
    try {
      if (!req.file) {
        return res.status(400).json({ error: "No file uploaded" });
      }

      const file = req.file;
      const datasetId = uuidv4();
      const description = req.body.description || ''; // Get optional description from request body

      console.log(`[FileUpload] File uploaded: ${file.originalname} -> ${file.filename}`);
      console.log(`[FileUpload] Dataset ID: ${datasetId}`);
      if (description) {
        console.log(`[FileUpload] Description: ${description}`);
      }

      // Get or create Galaxy history for this session
      let historyId = req.session.galaxyHistoryId as string | undefined;

      if (!historyId) {
        try {
          // Create a new history for this session
          const sessionName = `GalaxyChat-${new Date().toISOString().split('T')[0]}`;
          historyId = await galaxyAPIProxy.createHistory(sessionName);
          req.session.galaxyHistoryId = historyId;
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
          galaxyDatasetId = await galaxyAPIProxy.uploadDataset(
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

      // Store dataset in session for validation
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
      });

      // Return dataset information with both local and Galaxy IDs
      res.json({
        dataset_id: datasetId,
        galaxy_dataset_id: galaxyDatasetId,
        galaxy_history_id: historyId,
        name: file.originalname,
        description: description,
        file_size: file.size,
        file_type: file.mimetype,
        file_path: file.path,
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

  // Step execution endpoint for step-by-step mode
  app.post("/api/workflow/step/execute", async (req, res) => {
    try {
      const { step_id, tool_id, parameters, inputs } = req.body;

      if (!step_id || !tool_id) {
        return res.status(400).json({ error: "step_id and tool_id are required" });
      }

      // Get Galaxy history from session
      const historyId = req.session.galaxyHistoryId as string | undefined;

      if (!historyId) {
        return res.status(400).json({
          error: "No Galaxy history found. Please upload datasets first."
        });
      }

      console.log(`[StepExecution] Executing step ${step_id} with tool ${tool_id} in history ${historyId}`);

      // Submit tool job to Galaxy
      const job = await galaxyAPIProxy.submitToolJob(tool_id, {
        ...parameters,
        ...inputs
      }, historyId);

      console.log(`[StepExecution] Job submitted:`, job);

      // Store job info in session
      if (!req.session.workflowJobs) {
        req.session.workflowJobs = {};
      }
      req.session.workflowJobs[step_id] = {
        job_id: job.id,
        tool_id: tool_id,
        state: job.state || 'queued',
        started_at: new Date().toISOString()
      };

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
      req.session.workflowJobs[step_id].state = job.state;

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

  app.post("/api/galaxy/workflows/invoke", async (req, res) => {
    try {
      const { workflow_id, inputs, parameters } = req.body;
      if (!workflow_id) {
        return res.status(400).json({ error: "workflow_id is required" });
      }

      const invocation = await galaxyAPIBackend.invokeWorkflow(workflow_id, inputs, parameters);
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

  // ============================================================================
  // Server-Sent Events (SSE) for Real-Time Workflow Updates
  // ============================================================================

  app.get("/api/galaxy/workflows/sse/:invocationId", (req, res) => {
    sseManager.handleConnection(req, res);
  });

  // Chat endpoint with Galaxy Assistant integration
  app.post("/api/chat", async (req, res) => {
    try {
      const { message, context } = req.body;

      if (!message) {
        return res.status(400).json({ error: "Message is required" });
      }

      console.log('[Chat API] Processing message with Galaxy Assistant:', message);

      // Process message with Galaxy Assistant (hybrid intelligence)
      const assistantResponse = await galaxyAssistant.processMessage(message, context || {});

      console.log('[Chat API] Galaxy Assistant response:', {
        toolSearchUsed: assistantResponse.sources.toolSearchUsed,
        datasetRAGUsed: assistantResponse.sources.datasetRAGUsed,
        workflowGenerated: assistantResponse.sources.workflowGenerated,
        toolsFound: assistantResponse.recommendedTools?.length || 0,
        datasetsFound: assistantResponse.recommendedDatasets?.length || 0,
      });

      // Format response for frontend
      res.json({
        response: assistantResponse.message,
        suggestions: assistantResponse.suggestions,
        workflow: assistantResponse.generatedWorkflow,

        // Additional metadata for UI enhancement
        metadata: {
          recommendedTools: assistantResponse.recommendedTools,
          recommendedDatasets: assistantResponse.recommendedDatasets,
          workflowSuggestion: assistantResponse.workflowSuggestion,
          sources: assistantResponse.sources,
        },
      });

    } catch (error: any) {
      console.error("Chat API error:", error);

      // Fallback response
      const fallbackResponse = "I'm here to help you with bioinformatics analysis! What kind of data or workflow would you like to work on?";
      const fallbackSuggestions = [
        "Analyze RNA-seq data",
        "Create variant calling pipeline",
        "Build quality control workflow",
        "Help with gene expression analysis"
      ];

      res.json({
        response: fallbackResponse,
        suggestions: fallbackSuggestions,
        workflow: null,
        metadata: {
          error: error.message,
        },
      });
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
