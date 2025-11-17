import type { Express } from "express";
import express from "express";
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
import { getContextCompressor } from "./context-compressor";
import multer from "multer";
import { promises as fs } from "fs";
import path from "path";
import { v4 as uuidv4 } from "uuid";
import { authService } from "./auth-service";
import { authenticateToken, optionalAuth } from "./auth-middleware";
import type { RegisterData, LoginData } from "./auth-service";
import { s3Service } from "./s3-client";
import {
  apiLimiter,
  authLimiter,
  registerLimiter,
  passwordResetLimiter,
  emailVerificationLimiter,
  uploadLimiter,
} from "./rate-limit";
import passport from "passport";
import { oauthService } from "./oauth-service";
import { stripeService } from "./stripe-service";

// Initialize OpenAI (optional for development)
const openai = (process.env.OPENAI_API_KEY && process.env.OPENAI_API_KEY.trim()) ? new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
}) : null;

// Initialize Galaxy backend - using REAL Galaxy API (no more mock)
const galaxyAPIBackend = new GalaxyAPIProxy(); // Real Galaxy API for all operations
const galaxyAPIProxy = galaxyAPIBackend; // Alias for consistency

// Initialize state poller and SSE manager
const galaxyPoller = createPoller(galaxyAPIBackend, { pollInterval: 2000 });
const sseManager = new WorkflowSSEManager(galaxyPoller);

// Initialize Galaxy Assistant (hybrid intelligence with Claude Sonnet 4.5)
const galaxyAssistant = process.env.ANTHROPIC_API_KEY ? new GalaxyAssistant({
  anthropicApiKey: process.env.ANTHROPIC_API_KEY,
  galaxyAPIProxy,
}) : null;

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
  // Authentication API
  // ============================================================================

  // Register new user
  app.post("/api/auth/register", registerLimiter, async (req, res) => {
    try {
      const registerData: RegisterData = {
        email: req.body.email,
        password: req.body.password,
        fullName: req.body.fullName || req.body.name,
        organization: req.body.organization,
        phone: req.body.phone,
        termsAccepted: req.body.terms_accepted || req.body.termsAccepted || false,
        marketingEmailsOptIn: req.body.marketing_emails_opt_in || req.body.marketingEmailsOptIn || false,
      };

      const result = await authService.register(registerData);

      // Set HTTP-only cookie
      res.cookie('biomate_token', result.token, {
        httpOnly: true,
        secure: process.env.NODE_ENV === 'production',
        sameSite: 'strict',
        maxAge: result.expiresIn * 1000, // Convert to milliseconds
      });

      res.status(201).json({
        success: true,
        user: result.user,
        token: result.token,
        expiresIn: result.expiresIn,
      });
    } catch (error: any) {
      console.error('[Auth] Registration error:', error);
      res.status(400).json({
        success: false,
        error: error.message || 'Registration failed',
      });
    }
  });

  // Login existing user
  app.post("/api/auth/login", authLimiter, async (req, res) => {
    try {
      const loginData: LoginData = {
        email: req.body.email,
        password: req.body.password,
      };

      const result = await authService.login(loginData);

      // Set HTTP-only cookie
      res.cookie('biomate_token', result.token, {
        httpOnly: true,
        secure: process.env.NODE_ENV === 'production',
        sameSite: 'strict',
        maxAge: result.expiresIn * 1000,
      });

      // Check subscription status
      const subscriptionStatus = authService.checkSubscriptionStatus(result.user);

      res.json({
        success: true,
        user: result.user,
        token: result.token,
        subscription: subscriptionStatus,
      });
    } catch (error: any) {
      console.error('[Auth] Login error:', error);

      if (error.message === 'TRIAL_EXPIRED') {
        return res.status(403).json({
          success: false,
          error: 'TRIAL_EXPIRED',
          message: 'Your trial has expired. Please subscribe to continue.',
        });
      }

      res.status(401).json({
        success: false,
        error: 'Invalid credentials',
      });
    }
  });

  // Logout
  app.post("/api/auth/logout", (req, res) => {
    res.clearCookie('biomate_token');
    res.json({ success: true, message: 'Logged out successfully' });
  });

  // Get current user
  app.get("/api/auth/me", authenticateToken, async (req, res) => {
    try {
      if (!req.user) {
        return res.status(401).json({ error: 'Not authenticated' });
      }

      const subscriptionStatus = authService.checkSubscriptionStatus(req.user as any);

      res.json({
        success: true,
        user: req.user,
        subscription: subscriptionStatus,
      });
    } catch (error: any) {
      console.error('[Auth] Get current user error:', error);
      res.status(500).json({ error: 'Failed to get user' });
    }
  });

  // Resend verification email
  app.post("/api/auth/resend-verification", emailVerificationLimiter, authenticateToken, async (req, res) => {
    try {
      if (!req.user) {
        return res.status(401).json({ error: 'Not authenticated' });
      }

      await authService.sendVerificationEmail(req.user.id);

      res.json({
        success: true,
        message: 'Verification email sent',
      });
    } catch (error: any) {
      console.error('[Auth] Resend verification error:', error);
      res.status(400).json({
        success: false,
        error: error.message || 'Failed to send verification email',
      });
    }
  });

  // Verify email with token
  app.post("/api/auth/verify-email", emailVerificationLimiter, async (req, res) => {
    try {
      const { token } = req.body;

      if (!token) {
        return res.status(400).json({
          success: false,
          error: 'Token is required',
        });
      }

      const user = await authService.verifyEmail(token);

      res.json({
        success: true,
        message: 'Email verified successfully',
        user,
      });
    } catch (error: any) {
      console.error('[Auth] Email verification error:', error);
      res.status(400).json({
        success: false,
        error: error.message || 'Email verification failed',
      });
    }
  });

  // Request password reset
  app.post("/api/auth/request-password-reset", passwordResetLimiter, async (req, res) => {
    try {
      const { email } = req.body;

      if (!email) {
        return res.status(400).json({
          success: false,
          error: 'Email is required',
        });
      }

      await authService.requestPasswordReset(email);

      // Always return success to prevent email enumeration
      res.json({
        success: true,
        message: 'If the email exists, a password reset link has been sent',
      });
    } catch (error: any) {
      console.error('[Auth] Password reset request error:', error);
      // Still return success for security
      res.json({
        success: true,
        message: 'If the email exists, a password reset link has been sent',
      });
    }
  });

  // Reset password with token
  app.post("/api/auth/reset-password", passwordResetLimiter, async (req, res) => {
    try {
      const { token, password } = req.body;

      if (!token || !password) {
        return res.status(400).json({
          success: false,
          error: 'Token and password are required',
        });
      }

      // Basic password validation
      if (password.length < 8) {
        return res.status(400).json({
          success: false,
          error: 'Password must be at least 8 characters',
        });
      }

      await authService.resetPassword(token, password);

      res.json({
        success: true,
        message: 'Password reset successfully',
      });
    } catch (error: any) {
      console.error('[Auth] Password reset error:', error);
      res.status(400).json({
        success: false,
        error: error.message || 'Password reset failed',
      });
    }
  });

  // ============================================================================
  // OAuth Authentication (Google & GitHub)
  // ============================================================================

  // Google OAuth - Initiate
  app.get("/api/auth/google",
    authLimiter,
    passport.authenticate('google', { scope: ['profile', 'email'] })
  );

  // Google OAuth - Callback
  app.get("/api/auth/google/callback",
    passport.authenticate('google', { session: false, failureRedirect: '/login?error=oauth_failed' }),
    async (req, res) => {
      try {
        if (!req.user) {
          return res.redirect('/login?error=oauth_failed');
        }

        // Generate JWT token
        const token = oauthService.generateToken(req.user as any);
        const subscriptionStatus = authService.checkSubscriptionStatus(req.user as any);

        // Set cookie
        res.cookie('biomate_token', token, {
          httpOnly: true,
          secure: process.env.NODE_ENV === 'production',
          sameSite: 'strict',
          maxAge: 7 * 24 * 60 * 60 * 1000, // 7 days
        });

        // Redirect to dashboard with token
        res.redirect(`/dashboard?oauth_success=true`);
      } catch (error: any) {
        console.error('[OAuth] Google callback error:', error);
        res.redirect('/login?error=oauth_error');
      }
    }
  );

  // GitHub OAuth - Initiate
  app.get("/api/auth/github",
    authLimiter,
    passport.authenticate('github', { scope: ['user:email'] })
  );

  // GitHub OAuth - Callback
  app.get("/api/auth/github/callback",
    passport.authenticate('github', { session: false, failureRedirect: '/login?error=oauth_failed' }),
    async (req, res) => {
      try {
        if (!req.user) {
          return res.redirect('/login?error=oauth_failed');
        }

        // Generate JWT token
        const token = oauthService.generateToken(req.user as any);
        const subscriptionStatus = authService.checkSubscriptionStatus(req.user as any);

        // Set cookie
        res.cookie('biomate_token', token, {
          httpOnly: true,
          secure: process.env.NODE_ENV === 'production',
          sameSite: 'strict',
          maxAge: 7 * 24 * 60 * 60 * 1000, // 7 days
        });

        // Redirect to dashboard with token
        res.redirect(`/dashboard?oauth_success=true`);
      } catch (error: any) {
        console.error('[OAuth] GitHub callback error:', error);
        res.redirect('/login?error=oauth_error');
      }
    }
  );

  // Check OAuth configuration status
  app.get("/api/auth/oauth/status", (req, res) => {
    const status = oauthService.isConfigured();
    res.json({
      success: true,
      oauth: status,
    });
  });

  // ============================================================================
  // S3 File Management API
  // ============================================================================

  // Initialize S3 upload (get presigned URL)
  app.post("/api/s3/upload/init", uploadLimiter, authenticateToken, async (req, res) => {
    try {
      const { filename, fileSize, contentType } = req.body;

      if (!filename || !fileSize || !contentType) {
        return res.status(400).json({
          error: 'Missing required fields: filename, fileSize, contentType',
        });
      }

      const userId = req.user!.id;

      // For files < 100MB, use simple presigned URL
      if (fileSize < 100 * 1024 * 1024) {
        const uploadData = await s3Service.generatePresignedUploadUrl(
          userId,
          filename,
          contentType
        );

        res.json({
          uploadId: uploadData.uploadId,
          uploadUrl: uploadData.uploadUrl,
          key: uploadData.key,
          method: 'simple',
          expiresIn: uploadData.expires_in,
        });
      } else {
        // For large files, use multipart upload
        const multipartData = await s3Service.generateMultipartUploadUrls(
          userId,
          filename,
          fileSize,
          contentType
        );

        res.json({
          uploadId: multipartData.uploadId,
          key: multipartData.key,
          partUrls: multipartData.partUrls,
          chunkSize: multipartData.chunkSize,
          method: 'multipart',
          expiresIn: 3600,
        });
      }
    } catch (error: any) {
      console.error('[S3] Upload init error:', error);
      res.status(500).json({
        error: 'Failed to initialize upload',
        message: error.message,
      });
    }
  });

  // Get presigned download URL
  app.post("/api/s3/download", authenticateToken, async (req, res) => {
    try {
      const { key } = req.body;

      if (!key) {
        return res.status(400).json({ error: 'Missing required field: key' });
      }

      // Verify user owns this file (key should start with users/{userId}/)
      const userId = req.user!.id;
      if (!key.startsWith(`users/${userId}/`)) {
        return res.status(403).json({ error: 'Access denied' });
      }

      // Check if file exists
      const exists = await s3Service.fileExists(key);
      if (!exists) {
        return res.status(404).json({ error: 'File not found' });
      }

      // Generate presigned URL
      const downloadUrl = await s3Service.generatePresignedDownloadUrl(key);

      res.json({
        downloadUrl,
        expiresIn: 3600,
      });
    } catch (error: any) {
      console.error('[S3] Download URL generation error:', error);
      res.status(500).json({
        error: 'Failed to generate download URL',
        message: error.message,
      });
    }
  });

  // Delete file from S3
  app.delete("/api/s3/files/:key", authenticateToken, async (req, res) => {
    try {
      const key = decodeURIComponent(req.params.key);

      // Verify user owns this file
      const userId = req.user!.id;
      if (!key.startsWith(`users/${userId}/`)) {
        return res.status(403).json({ error: 'Access denied' });
      }

      const success = await s3Service.deleteFile(key);

      if (success) {
        res.json({ success: true, message: 'File deleted successfully' });
      } else {
        res.status(500).json({ error: 'Failed to delete file' });
      }
    } catch (error: any) {
      console.error('[S3] Delete file error:', error);
      res.status(500).json({
        error: 'Failed to delete file',
        message: error.message,
      });
    }
  });

  // ============================================================================
  // Payment & Subscription API (Stripe)
  // ============================================================================

  // Create checkout session for subscription
  app.post("/api/payments/create-checkout-session", authenticateToken, async (req, res) => {
    try {
      if (!stripeService.isConfigured()) {
        return res.status(503).json({
          error: 'Payment system not configured',
          message: 'Stripe is not set up. Contact support.',
        });
      }

      const { priceId, successUrl, cancelUrl } = req.body;

      if (!priceId) {
        return res.status(400).json({ error: 'Price ID is required' });
      }

      const session = await stripeService.createCheckoutSession(
        req.user!.id,
        priceId,
        successUrl,
        cancelUrl
      );

      res.json({
        success: true,
        sessionId: session.id,
        url: session.url,
      });
    } catch (error: any) {
      console.error('[Payments] Checkout session error:', error);
      res.status(500).json({
        error: 'Failed to create checkout session',
        message: error.message,
      });
    }
  });

  // Create customer portal session
  app.post("/api/payments/create-portal-session", authenticateToken, async (req, res) => {
    try {
      if (!stripeService.isConfigured()) {
        return res.status(503).json({
          error: 'Payment system not configured',
        });
      }

      const { returnUrl } = req.body;

      const session = await stripeService.createPortalSession(req.user!.id, returnUrl);

      res.json({
        success: true,
        url: session.url,
      });
    } catch (error: any) {
      console.error('[Payments] Portal session error:', error);
      res.status(500).json({
        error: 'Failed to create portal session',
        message: error.message,
      });
    }
  });

  // Get current subscription
  app.get("/api/payments/subscription", authenticateToken, async (req, res) => {
    try {
      if (!stripeService.isConfigured()) {
        return res.json({
          success: true,
          subscription: null,
          configured: false,
        });
      }

      const subscription = await stripeService.getSubscription(req.user!.id);

      res.json({
        success: true,
        subscription,
        configured: true,
      });
    } catch (error: any) {
      console.error('[Payments] Get subscription error:', error);
      res.status(500).json({
        error: 'Failed to get subscription',
        message: error.message,
      });
    }
  });

  // Cancel subscription
  app.post("/api/payments/cancel-subscription", authenticateToken, async (req, res) => {
    try {
      if (!stripeService.isConfigured()) {
        return res.status(503).json({
          error: 'Payment system not configured',
        });
      }

      await stripeService.cancelSubscription(req.user!.id);

      res.json({
        success: true,
        message: 'Subscription canceled successfully',
      });
    } catch (error: any) {
      console.error('[Payments] Cancel subscription error:', error);
      res.status(500).json({
        error: 'Failed to cancel subscription',
        message: error.message,
      });
    }
  });

  // Get pricing tiers
  app.get("/api/payments/pricing", (req, res) => {
    if (!stripeService.isConfigured()) {
      return res.json({
        success: true,
        pricing: null,
        configured: false,
      });
    }

    const pricing = stripeService.getPricingTiers();

    res.json({
      success: true,
      pricing,
      configured: true,
    });
  });

  // Stripe webhook handler
  app.post("/api/payments/webhook", express.raw({ type: 'application/json' }), async (req, res) => {
    const signature = req.headers['stripe-signature'];

    if (!signature) {
      return res.status(400).send('Missing stripe-signature header');
    }

    try {
      await stripeService.handleWebhook(req.body, signature);
      res.json({ received: true });
    } catch (error: any) {
      console.error('[Payments] Webhook error:', error);
      res.status(400).send(`Webhook Error: ${error.message}`);
    }
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

  app.get("/api/galaxy/tools/:toolId(*)/schema", async (req, res) => {
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
      let historyId = req.session?.galaxyHistoryId as string | undefined;

      if (!historyId) {
        try {
          // Create a new history for this session
          const sessionName = `GalaxyChat-${new Date().toISOString().split('T')[0]}`;
          historyId = await galaxyAPIProxy.createHistory(sessionName);
          if (req.session) {
            req.session.galaxyHistoryId = historyId;
          }
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
      if (req.session) {
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
      }

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
      const historyId = req.session?.galaxyHistoryId as string | undefined;

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
      if (req.session) {
        if (!req.session.workflowJobs) {
          req.session.workflowJobs = {};
        }
        req.session.workflowJobs[step_id] = {
          job_id: job.id,
          tool_id: tool_id,
          state: job.state || 'queued',
          started_at: new Date().toISOString()
        };
      }

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

  // Create/upload workflow to Galaxy
  app.post("/api/galaxy/workflows", async (req, res) => {
    try {
      const { workflow } = req.body;
      if (!workflow) {
        return res.status(400).json({ error: "workflow is required" });
      }

      console.log('[CreateWorkflow] Creating workflow in Galaxy:', workflow.name || 'unnamed');
      const createdWorkflow = await galaxyAPIBackend.createWorkflow(workflow);
      console.log('[CreateWorkflow] Successfully created workflow:', createdWorkflow.id);

      res.json(createdWorkflow);
    } catch (error: any) {
      console.error("[CreateWorkflow] Error creating workflow:", error);
      res.status(error.status_code || 500).json({
        error: error.error || 'WorkflowCreationError',
        message: error.message || 'Failed to create workflow',
      });
    }
  });

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

  app.put("/api/galaxy/jobs/:jobId/pause", async (req, res) => {
    try {
      const result = await galaxyAPIBackend.pauseJob(req.params.jobId);
      res.json({
        success: true,
        message: 'Job paused successfully',
        data: result
      });
    } catch (error: any) {
      console.error("Pause job error:", error);
      res.status(error.status_code || 500).json({
        error: error.error || 'PauseJobFailed',
        message: error.message || 'Failed to pause job',
      });
    }
  });

  app.put("/api/galaxy/jobs/:jobId/resume", async (req, res) => {
    try {
      const result = await galaxyAPIBackend.resumeJob(req.params.jobId);
      res.json({
        success: true,
        message: 'Job resumed successfully',
        data: result
      });
    } catch (error: any) {
      console.error("Resume job error:", error);
      res.status(error.status_code || 500).json({
        error: error.error || 'ResumeJobFailed',
        message: error.message || 'Failed to resume job',
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

      if (!galaxyAssistant) {
        return res.status(503).json({
          error: "Galaxy Assistant not available. ANTHROPIC_API_KEY is not configured."
        });
      }

      console.log('[Chat API] Processing message with Galaxy Assistant:', message);

      // Process message with Galaxy Assistant (hybrid intelligence)
      const assistantResponse = await galaxyAssistant.processMessage(message, context || {});

      console.log('[Chat API] Galaxy Assistant response:', {
        toolSearchUsed: assistantResponse.sources.toolSearchUsed,
        datasetRAGUsed: assistantResponse.sources.datasetRAGUsed,
        workflowGenerated: assistantResponse.sources.workflowGenerated,
        thinkingUsed: assistantResponse.sources.thinkingUsed,
        toolsFound: assistantResponse.recommendedTools?.length || 0,
        datasetsFound: assistantResponse.recommendedDatasets?.length || 0,
      });

      // Format response for frontend
      res.json({
        response: assistantResponse.message,
        suggestions: assistantResponse.suggestions,
        workflow: assistantResponse.generatedWorkflow,

        // Thinking mode support
        thinking_content: assistantResponse.thinking_content,
        thinking_level: assistantResponse.thinking_level,

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
  // Context Compression API
  // ============================================================================

  // Compress session messages
  app.post("/api/compress-session", async (req, res) => {
    try {
      const { sessionId, messages, keepRecentCount } = req.body;

      if (!messages || !Array.isArray(messages)) {
        return res.status(400).json({ error: "messages array is required" });
      }

      if (!process.env.ANTHROPIC_API_KEY) {
        return res.status(503).json({
          error: "Context compression not available. ANTHROPIC_API_KEY is not configured."
        });
      }

      console.log('[Compression API] Compressing session:', {
        sessionId,
        messageCount: messages.length,
        keepRecentCount: keepRecentCount || 3
      });

      // Get compressor instance
      const compressor = getContextCompressor(process.env.ANTHROPIC_API_KEY);

      // Compress messages
      const result = await compressor.compressMessages(messages, {
        keepRecentCount: keepRecentCount || 3
      });

      console.log('[Compression API] Compression successful:', {
        messagesReduced: `${result.messagesBeforeCount} → ${result.messagesAfterCount}`,
        tokensReduced: `${result.tokensBeforeCount} → ${result.tokensAfterCount}`,
        compressionRatio: `${(result.compressionRatio * 100).toFixed(1)}%`
      });

      res.json(result);
    } catch (error: any) {
      console.error('[Compression API] Compression failed:', error);
      res.status(500).json({
        error: 'CompressionError',
        message: error.message || 'Context compression failed',
      });
    }
  });

  // Workflow generation endpoint - proxies to Galaxy backend
  app.post("/api/ai_assistant/generate_workflow", async (req, res) => {
    try {
      const { request_text, available_datasets, context, preferred_tools, constraints } = req.body;

      if (!request_text) {
        return res.status(400).json({ error: "request_text is required" });
      }

      console.log('[WorkflowGen API] Generating workflow for:', request_text);

      // Call Galaxy backend via proxy
      const response = await galaxyAPIProxy.generateWorkflow({
        user_intent: request_text,
        datasets: available_datasets,
        max_tools_search: constraints?.max_tools_search,
      });

      console.log('[WorkflowGen API] Response:', {
        success: response.success,
        source: response.source,
        confidence: response.confidence,
        has_workflow_ga: !!response.workflow_ga,
      });

      console.log('[WorkflowGen API] Sending response to client...');
      res.json(response);
      console.log('[WorkflowGen API] Response sent successfully');
    } catch (error: any) {
      console.error("[WorkflowGen API] Error:", error);
      res.status(500).json({
        success: false,
        error: 'WorkflowGenerationError',
        message: error.message || 'Workflow generation failed',
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


  // ============================================================================
  // Workflow Management API
  // ============================================================================

  // List all workflows (for compatibility with E2E tests)
  app.get("/api/workflows", optionalAuth, async (req, res) => {
    try {
      // Return list of workflow invocations for this user
      const { limit } = req.query;
      const invocations = await storage.getInvocations(
        req.user?.id,
        limit ? parseInt(limit as string) : 100
      );
      res.json(invocations);
    } catch (error: any) {
      console.error("Error fetching workflows:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // SSE endpoint for workflow events (generic, works without specific invocation ID)
  app.get("/api/workflows/events", optionalAuth, (req, res) => {
    try {
      // Set SSE headers
      res.setHeader('Content-Type', 'text/event-stream');
      res.setHeader('Cache-Control', 'no-cache');
      res.setHeader('Connection', 'keep-alive');
      res.setHeader('X-Accel-Buffering', 'no');

      // Send initial connection message
      res.write('data: {"type":"connected","message":"SSE connection established"}\n\n');

      // Keep connection alive with periodic heartbeat
      const heartbeat = setInterval(() => {
        res.write('data: {"type":"heartbeat"}\n\n');
      }, 15000);

      // Clean up on close
      req.on('close', () => {
        clearInterval(heartbeat);
      });
    } catch (error: any) {
      console.error("SSE connection error:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // ============================================================================
  // Workflow Invocation Management API
  // ============================================================================

  // Create a new invocation record (called when workflow starts)
  app.post("/api/invocations", async (req, res) => {
    try {
      const invocationData = req.body;

      const invocation = await storage.createInvocation({
        userId: req.user?.id,
        workflowName: invocationData.workflowName,
        workflowDefinition: invocationData.workflowDefinition,
        galaxyInvocationId: invocationData.galaxyInvocationId,
        galaxyHistoryId: invocationData.galaxyHistoryId,
        galaxyWorkflowId: invocationData.galaxyWorkflowId,
        inputDatasets: invocationData.inputDatasets || [],
        totalSteps: invocationData.totalSteps || 0,
        status: 'running',
      });

      res.json(invocation);
    } catch (error: any) {
      console.error("Error creating invocation:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Get all invocations for the current user
  app.get("/api/invocations", async (req, res) => {
    try {
      const { limit } = req.query;
      const invocations = await storage.getInvocations(
        req.user?.id,
        limit ? parseInt(limit as string) : 100
      );
      res.json(invocations);
    } catch (error: any) {
      console.error("Error fetching invocations:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Get a specific invocation by ID
  app.get("/api/invocations/:id", async (req, res) => {
    try {
      const invocation = await storage.getInvocation(req.params.id);
      if (!invocation) {
        return res.status(404).json({ error: "Invocation not found" });
      }
      res.json(invocation);
    } catch (error: any) {
      console.error("Error fetching invocation:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Update an invocation (status, outputs, etc.)
  app.patch("/api/invocations/:id", async (req, res) => {
    try {
      const updates = req.body;
      const invocation = await storage.updateInvocation(req.params.id, updates);

      if (!invocation) {
        return res.status(404).json({ error: "Invocation not found" });
      }

      res.json(invocation);
    } catch (error: any) {
      console.error("Error updating invocation:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Delete an invocation
  app.delete("/api/invocations/:id", async (req, res) => {
    try {
      const success = await storage.deleteInvocation(req.params.id);
      if (!success) {
        return res.status(404).json({ error: "Invocation not found" });
      }
      res.json({ success: true });
    } catch (error: any) {
      console.error("Error deleting invocation:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Get outputs for a specific invocation
  app.get("/api/invocations/:id/outputs", async (req, res) => {
    try {
      const outputs = await storage.getInvocationOutputs(req.params.id);
      res.json(outputs);
    } catch (error: any) {
      console.error("Error fetching outputs:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Fetch outputs from Galaxy after workflow completion
  app.post("/api/invocations/:id/fetch-outputs", async (req, res) => {
    try {
      const invocation = await storage.getInvocation(req.params.id);
      if (!invocation) {
        return res.status(404).json({ error: "Invocation not found" });
      }

      // Fetch history contents from Galaxy
      const historyContents = await galaxyAPIProxy.getHistoryContents(invocation.galaxyHistoryId);

      // Filter outputs created by this invocation (after invocation start time)
      const invocationOutputs = historyContents.filter((item: any) => {
        const itemCreateTime = new Date(item.create_time);
        return (
          !item.deleted &&
          item.state === 'ok' &&
          item.history_content_type === 'dataset' &&
          itemCreateTime >= invocation.createdAt
        );
      });

      // Store each output in our database
      const storedOutputs = [];
      for (const galaxyOutput of invocationOutputs) {
        const extension = galaxyOutput.extension || galaxyOutput.file_ext || 'txt';
        const fileType = classifyFileType(extension);

        const output = await storage.addOutput({
          invocationId: invocation.id,
          galaxyDatasetId: galaxyOutput.id,
          name: galaxyOutput.name,
          extension: extension,
          size: galaxyOutput.file_size || 0,
          fileType: fileType,
          isVisualizable: isVisualizable(extension),
          previewAvailable: fileType === 'table' || fileType === 'text',
          metadata: {
            dataType: galaxyOutput.data_type,
            rows: galaxyOutput.metadata?.data_lines,
            columns: galaxyOutput.metadata?.columns,
          },
        });

        storedOutputs.push(output);
      }

      // Update invocation status to completed
      await storage.updateInvocation(invocation.id, {
        status: 'ok',
        completedAt: new Date(),
        completedSteps: invocation.totalSteps,
      });

      res.json({ outputs: storedOutputs, count: storedOutputs.length });
    } catch (error: any) {
      console.error("Error fetching outputs:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // ============================================================================
  // Output Dataset Management API
  // ============================================================================

  // Get a specific output by ID
  app.get("/api/outputs/:id", async (req, res) => {
    try {
      const output = await storage.getOutput(req.params.id);
      if (!output) {
        return res.status(404).json({ error: "Output not found" });
      }
      res.json(output);
    } catch (error: any) {
      console.error("Error fetching output:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Download output file from Galaxy
  app.get("/api/outputs/:id/download", async (req, res) => {
    try {
      const output = await storage.getOutput(req.params.id);
      if (!output) {
        return res.status(404).json({ error: "Output not found" });
      }

      // Fetch file from Galaxy
      const fileStream = await galaxyAPIProxy.downloadDataset(output.galaxyDatasetId);

      // Set appropriate headers
      res.setHeader('Content-Disposition', `attachment; filename="${output.name}"`);
      res.setHeader('Content-Type', 'application/octet-stream');

      // Pipe the stream to response
      fileStream.pipe(res);
    } catch (error: any) {
      console.error("Error downloading output:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Display output file (for images, HTML, etc.)
  app.get("/api/outputs/:id/display", async (req, res) => {
    try {
      const output = await storage.getOutput(req.params.id);
      if (!output) {
        return res.status(404).json({ error: "Output not found" });
      }

      // Fetch file from Galaxy
      const fileStream = await galaxyAPIProxy.downloadDataset(output.galaxyDatasetId);

      // Set appropriate content type for inline display
      const contentTypeMap: Record<string, string> = {
        'png': 'image/png',
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'svg': 'image/svg+xml',
        'gif': 'image/gif',
        'pdf': 'application/pdf',
        'html': 'text/html',
        'htm': 'text/html',
        'txt': 'text/plain',
        'csv': 'text/csv',
        'tsv': 'text/tab-separated-values',
      };

      const contentType = contentTypeMap[output.extension] || 'application/octet-stream';
      res.setHeader('Content-Type', contentType);
      res.setHeader('Content-Disposition', 'inline');

      // Pipe the stream to response
      fileStream.pipe(res);
    } catch (error: any) {
      console.error("Error displaying output:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Preview output (first N lines for tables/text files)
  app.get("/api/outputs/:id/preview", async (req, res) => {
    try {
      const output = await storage.getOutput(req.params.id);
      if (!output) {
        return res.status(404).json({ error: "Output not found" });
      }

      if (output.fileType !== 'table' && output.fileType !== 'text') {
        return res.status(400).json({ error: "Preview not available for this file type" });
      }

      // Fetch file content from Galaxy
      const fileStream = await galaxyAPIProxy.downloadDataset(output.galaxyDatasetId);

      // Read first N lines
      const lines: string[] = [];
      let lineCount = 0;
      const maxLines = parseInt(req.query.lines as string) || 100;

      for await (const chunk of fileStream) {
        const chunkLines = chunk.toString().split('\n');
        for (const line of chunkLines) {
          if (lineCount >= maxLines) break;
          lines.push(line);
          lineCount++;
        }
        if (lineCount >= maxLines) break;
      }

      res.json({
        lines,
        totalLines: output.metadata?.rows || lineCount,
        hasMore: (output.metadata?.rows || 0) > maxLines
      });
    } catch (error: any) {
      console.error("Error previewing output:", error);
      res.status(500).json({ error: error.message });
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

// Helper function to classify file type from extension
function classifyFileType(extension: string): 'image' | 'table' | 'text' | 'binary' | 'interactive' {
  const ext = extension.toLowerCase();

  const imageExts = ['png', 'jpg', 'jpeg', 'svg', 'gif', 'pdf', 'tiff', 'bmp'];
  const tableExts = ['tsv', 'csv', 'tabular', 'txt', 'bed', 'gtf', 'gff', 'vcf'];
  const interactiveExts = ['html', 'htm'];
  const textExts = ['txt', 'log', 'md', 'json', 'xml', 'yaml', 'yml'];

  if (imageExts.includes(ext)) return 'image';
  if (tableExts.includes(ext)) return 'table';
  if (interactiveExts.includes(ext)) return 'interactive';
  if (textExts.includes(ext)) return 'text';
  return 'binary';
}

function isVisualizable(extension: string): boolean {
  const visualizableExts = ['png', 'jpg', 'jpeg', 'svg', 'gif', 'pdf', 'html', 'htm'];
  return visualizableExts.includes(extension.toLowerCase());
}

