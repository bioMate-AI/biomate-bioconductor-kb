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
import { createWorkflowNotificationService, type WorkflowNotificationService } from "./workflow-notification-service";
import { GalaxyAssistant } from "./galaxy-assistant";
import { parameterRepository } from "./parameter-repository";
import { workflowRepository } from "./workflow-repository";
import { memoryService } from "./memory-repository";
import { createMemoryIntegration, getMemoryIntegration, type MemoryEnhancedContext } from "./memory-integration";
import { datasetValidator } from "./dataset-validator";
import { getContextCompressor } from "./context-compressor";
import { WorkflowPrerequisitesValidator } from "./workflow-prerequisites-validator";
import multer from "multer";
import { promises as fs } from "fs";
import path from "path";
import { v4 as uuidv4 } from "uuid";
import archiver from "archiver";
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
import { auditService, auditMiddleware } from "./audit-service";

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

// Initialize workflow notification service for email notifications
const workflowNotificationService = createWorkflowNotificationService(galaxyPoller, storage);

// Listen for workflow completion to update bioMate invocation records
galaxyPoller.on('workflow_completed', async (data: { invocation_id: string; state: string }) => {
  try {
    const invocation = await storage.getInvocationByGalaxyId(data.invocation_id);
    if (invocation) {
      await storage.updateInvocation(invocation.id, {
        status: data.state === 'ok' || data.state === 'scheduled' ? 'ok' : 'error',
        completedAt: new Date(),
        completedSteps: invocation.totalSteps,
      });
      console.log(`[WorkflowComplete] Updated bioMate invocation ${invocation.id} to completed`);
    }
  } catch (error) {
    console.error('[WorkflowComplete] Failed to update invocation:', error);
  }
});

// Initialize Galaxy Assistant (hybrid intelligence with Claude Sonnet 4.5)
const galaxyAssistant = process.env.ANTHROPIC_API_KEY ? new GalaxyAssistant({
  anthropicApiKey: process.env.ANTHROPIC_API_KEY,
  galaxyAPIProxy,
}) : null;

// Initialize Prerequisites Validator (LLM-powered pre-execution validation)
const prerequisitesValidator = process.env.ANTHROPIC_API_KEY ? new WorkflowPrerequisitesValidator({
  anthropicApiKey: process.env.ANTHROPIC_API_KEY,
  galaxyAPIProxy,
}) : null;

// Initialize memory integration if Galaxy Assistant is available
const memoryIntegration = galaxyAssistant ? createMemoryIntegration(galaxyAssistant) : null;

// Configure multer for file uploads
// AWS workflows require file upload first, so we constrain to 5GB to reduce latency
const MAX_FILE_SIZE_GB = 5;
const MAX_FILE_SIZE_BYTES = MAX_FILE_SIZE_GB * 1024 * 1024 * 1024; // 5GB

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
    fileSize: MAX_FILE_SIZE_BYTES, // 5GB max file size per file
  },
  fileFilter: (req, file, cb) => {
    // Accept common bioinformatics formats
    const allowedExtensions = [
      '.fastq', '.fastq.gz', '.fq', '.fq.gz',
      '.bam', '.sam', '.cram',
      '.mzml', '.mzxml', '.mgf',
      '.csv', '.tsv', '.txt', '.tab',
      '.fasta', '.fa', '.fna', '.fas',
      '.vcf', '.vcf.gz', '.bed', '.gff', '.gtf',
      '.h5ad', '.h5', '.hdf5', '.loom',
      '.json', '.xml'
    ];
    const ext = path.extname(file.originalname).toLowerCase();
    if (allowedExtensions.some(allowed => file.originalname.toLowerCase().endsWith(allowed))) {
      cb(null, true);
    } else {
      cb(new Error(`File type not supported. Allowed: ${allowedExtensions.join(', ')}`));
    }
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

  // Apply audit middleware for API routes (excludes health and SSE)
  app.use('/api', auditMiddleware({
    excludePaths: ['/api/health', '/api/workflow/sse'],
    logBody: false, // Don't log request bodies by default (privacy)
  }));

  // Health check
  app.get("/api/health", async (req, res) => {
    // Get Galaxy connection status
    const galaxyStatus = galaxyAPIBackend.getConnectionStatus();
    const galaxyHealthy = await galaxyAPIBackend.healthCheck();

    res.json({
      status: galaxyHealthy ? "ok" : "degraded",
      timestamp: new Date().toISOString(),
      services: {
        api: "ok",
        galaxy: {
          connected: galaxyHealthy,
          url: galaxyStatus.url,
          error: galaxyStatus.error
        },
        ai: !!galaxyAssistant ? "ok" : "unavailable"
      }
    });
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

      // Log successful login
      await auditService.logAuth(
        'login',
        result.user.id,
        req.ip || req.socket.remoteAddress || 'unknown',
        req.headers['user-agent'] || 'unknown',
        true
      );

      res.json({
        success: true,
        user: result.user,
        token: result.token,
        subscription: subscriptionStatus,
      });
    } catch (error: any) {
      console.error('[Auth] Login error:', error);

      // Log failed login
      await auditService.logAuth(
        'login',
        null,
        req.ip || req.socket.remoteAddress || 'unknown',
        req.headers['user-agent'] || 'unknown',
        false,
        error.message
      );

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
  app.post("/api/auth/logout", async (req, res) => {
    // Log logout
    const userId = (req as any).user?.id || null;
    await auditService.logAuth(
      'logout',
      userId,
      req.ip || req.socket.remoteAddress || 'unknown',
      req.headers['user-agent'] || 'unknown',
      true
    );

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
    const signatureHeader = req.headers['stripe-signature'];
    const signature = Array.isArray(signatureHeader) ? signatureHeader[0] : signatureHeader;

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

  // URL Import API - Galaxy fetches file from URL (no size limit, faster for large files)
  // Leverages Galaxy's built-in URL fetching capabilities (HTTP, FTP, S3)
  app.post("/api/datasets/import-url", async (req, res) => {
    try {
      const { url, filename } = req.body;

      if (!url) {
        return res.status(400).json({ error: "URL is required" });
      }

      // Validate URL format
      try {
        const parsedUrl = new URL(url);
        if (!['http:', 'https:', 'ftp:', 's3:'].includes(parsedUrl.protocol)) {
          return res.status(400).json({
            error: "Unsupported protocol. Use HTTP, HTTPS, FTP, or S3 URLs."
          });
        }
      } catch {
        return res.status(400).json({ error: "Invalid URL format" });
      }

      console.log(`[URLImport] Importing from URL: ${url}`);

      // Get or create Galaxy history
      let historyId = req.session?.galaxyHistoryId as string | undefined;
      if (!historyId) {
        try {
          const sessionName = `GalaxyChat-${new Date().toISOString().split('T')[0]}`;
          historyId = await galaxyAPIProxy.createHistory(sessionName);
          if (req.session) {
            req.session.galaxyHistoryId = historyId;
          }
          console.log(`[URLImport] Created new Galaxy history: ${historyId}`);
        } catch (error: any) {
          console.error(`[URLImport] Failed to create Galaxy history:`, error.message);
          return res.status(500).json({
            error: 'GalaxyError',
            message: 'Failed to create Galaxy history for URL import'
          });
        }
      }

      // Use Galaxy's URL fetch capability
      try {
        const datasetId = uuidv4();
        const galaxyDatasetId = await galaxyAPIProxy.uploadFromUrl(
          url,
          historyId,
          filename || url.split('/').pop() || 'imported-file'
        );

        console.log(`[URLImport] Galaxy dataset created: ${galaxyDatasetId}`);

        // Store in session (URL imports have additional metadata)
        if (req.session) {
          if (!req.session.uploadedDatasets) {
            req.session.uploadedDatasets = [];
          }
          req.session.uploadedDatasets.push({
            dataset_id: datasetId,
            galaxy_dataset_id: galaxyDatasetId,
            name: filename || url.split('/').pop() || 'imported-file',
            description: `Imported from URL: ${url}`,
            file_type: 'auto',
            file_size: 0, // Size unknown until Galaxy fetches it
          });
        }

        res.json({
          dataset_id: datasetId,
          galaxy_dataset_id: galaxyDatasetId,
          galaxy_history_id: historyId,
          name: filename || url.split('/').pop(),
          source: 'url',
          source_url: url,
          uploaded_at: new Date().toISOString(),
        });
      } catch (error: any) {
        console.error(`[URLImport] Galaxy URL import failed:`, error.message);
        res.status(500).json({
          error: 'URLImportError',
          message: error.message || 'Failed to import file from URL'
        });
      }
    } catch (error: any) {
      console.error("[URLImport] Error:", error);
      res.status(500).json({
        error: 'URLImportError',
        message: error.message || 'URL import failed',
      });
    }
  });

  // Storage/Resource Check API - Check available resources before execution
  app.get("/api/resources/status", async (req, res) => {
    try {
      // Calculate storage usage from session uploads
      const uploadedDatasets = req.session?.uploadedDatasets || [];
      const totalUploadedBytes = uploadedDatasets.reduce(
        (sum: number, d: any) => sum + (d.file_size || 0), 0
      );

      // Check local disk space (upload directory)
      let availableDiskGB = 50; // Default fallback
      try {
        const stats = await fs.statfs(uploadDir);
        availableDiskGB = (stats.bsize * stats.bavail) / (1024 * 1024 * 1024);
      } catch {
        console.warn('[Resources] Could not check disk space');
      }

      // Return resource status
      res.json({
        storage: {
          uploaded_gb: totalUploadedBytes / (1024 * 1024 * 1024),
          available_gb: availableDiskGB,
          max_file_size_gb: MAX_FILE_SIZE_GB,
          dataset_count: uploadedDatasets.length,
        },
        limits: {
          max_local_file_size_gb: MAX_FILE_SIZE_GB,
          max_concurrent_uploads: 3,
          max_concurrent_workflows: 5,
        },
        recommendations: {
          use_url_import_above_gb: 2,
          use_ftp_above_gb: 5,
        }
      });
    } catch (error: any) {
      console.error("[Resources] Status check failed:", error);
      res.status(500).json({
        error: 'ResourceCheckError',
        message: error.message || 'Failed to check resource status',
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
      if (req.session?.workflowJobs?.[step_id]) {
        req.session.workflowJobs[step_id].state = job.state;
      }

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

  /**
   * Pre-execution validation endpoint
   * Checks workflow for critical issues before allowing execution
   */
  app.post("/api/workflow/validate-before-execute", authenticateToken, async (req, res) => {
    try {
      const { workflow_ga, validation, tool_installation, pilot_run_suggested, pilot_reasons } = req.body;

      const blockers: string[] = [];
      const warnings: string[] = [];

      // Check for critical tool installation failures
      if (tool_installation && !tool_installation.success) {
        const failedTools = tool_installation.failed_tools || [];
        if (failedTools.length > 0) {
          blockers.push(`Missing tools that could not be installed: ${failedTools.join(', ')}`);
        }
      }

      // Check for critical validation issues
      if (validation) {
        const issues = validation.issues || [];
        // Issues are considered blockers
        for (const issue of issues) {
          blockers.push(`Validation issue: ${issue}`);
        }

        // Warnings are non-blocking but should be shown
        const validationWarnings = validation.warnings || [];
        warnings.push(...validationWarnings);
      }

      // Check if workflow has required steps
      if (workflow_ga) {
        const steps = workflow_ga.steps || {};
        const stepCount = Object.keys(steps).length;
        if (stepCount === 0) {
          blockers.push('Workflow has no steps defined');
        }
      }

      // Log validation check
      await auditService.log({
        userId: req.user?.id,
        action: 'workflow.validate_before_execute',
        resourceType: 'workflow',
        details: {
          blockersCount: blockers.length,
          warningsCount: warnings.length,
          pilotSuggested: pilot_run_suggested,
        },
        status: blockers.length > 0 ? 'failure' : 'success',
      });

      // Return validation result
      res.json({
        canExecute: blockers.length === 0,
        blockers,
        warnings,
        pilotRunSuggested: pilot_run_suggested,
        pilotReasons: pilot_reasons || [],
        recommendation: blockers.length > 0
          ? 'Please resolve the blocking issues before execution'
          : pilot_run_suggested
          ? 'Consider running a pilot test first to validate parameters'
          : 'Workflow is ready for execution',
      });
    } catch (error: any) {
      console.error('[ValidateBeforeExecute] Error:', error);
      res.status(500).json({ error: 'Validation check failed', message: error.message });
    }
  });

  app.post("/api/galaxy/workflows/invoke", optionalAuth, async (req, res) => {
    try {
      const {
        workflow_id,
        inputs,
        parameters,
        history_id,
        new_history_name,
        // New: optional validation bypass (for advanced users)
        skip_validation,
        // New: validation info from workflow generation
        validation,
        tool_installation
      } = req.body;

      if (!workflow_id) {
        return res.status(400).json({ error: "workflow_id is required" });
      }

      // Pre-execution validation (unless explicitly skipped)
      if (!skip_validation) {
        // Check for critical blockers
        const blockers: string[] = [];

        // Check tool installation
        if (tool_installation && !tool_installation.success) {
          const failedTools = tool_installation.failed_tools || [];
          if (failedTools.length > 0) {
            blockers.push(`Missing tools: ${failedTools.join(', ')}`);
          }
        }

        // Check validation issues
        if (validation && validation.issues && validation.issues.length > 0) {
          blockers.push(...validation.issues.map((i: string) => `Validation: ${i}`));
        }

        // Block execution if there are critical issues
        if (blockers.length > 0) {
          console.warn('[InvokeWorkflow] Blocked due to validation issues:', blockers);
          return res.status(400).json({
            error: 'VALIDATION_FAILED',
            message: 'Workflow has critical issues that must be resolved before execution',
            blockers,
            suggestion: 'Fix the issues or run a pilot test first. Use skip_validation=true to force execution.',
          });
        }
      }

      // Merge history parameters with other parameters
      const invokeParams = {
        ...parameters,
        // If history_id provided, use it; otherwise create a new history
        ...(history_id ? { history_id } : { new_history_name: new_history_name || `bioMate Workflow Run ${new Date().toISOString()}` })
      };

      console.log('[InvokeWorkflow] Invoking workflow:', workflow_id, 'with params:', invokeParams);

      const invocation = await galaxyAPIBackend.invokeWorkflow(workflow_id, inputs, invokeParams);

      // Log successful invocation
      await auditService.logWorkflowExecutionStart(
        (req as any).user?.id || null,
        invocation.id,
        workflow_id,
        invocation.history_id
      );

      // Create local invocation record for Workflow History panel
      try {
        // Get workflow name from Galaxy if possible
        let workflowName = 'Workflow';
        try {
          const workflowDetails = await galaxyAPIBackend.getWorkflow(workflow_id);
          workflowName = workflowDetails?.name || 'Workflow';
        } catch (e) {
          console.warn('[InvokeWorkflow] Could not fetch workflow name:', e);
        }

        await storage.createInvocation({
          id: invocation.id,
          galaxyInvocationId: invocation.id,
          workflowId: workflow_id,
          workflowName: workflowName,
          userId: (req as any).user?.id || 'anonymous',
          status: invocation.state || 'new',
          totalSteps: invocation.steps?.length || 0,
          completedSteps: 0,
          createdAt: new Date(),
          updatedAt: new Date(),
        });
        console.log('[InvokeWorkflow] Created local invocation record:', invocation.id);

        // Register for email notifications if user is authenticated
        const user = (req as any).user;
        if (user && user.email) {
          workflowNotificationService.registerInvocation(invocation.id, {
            userId: user.id,
            userEmail: user.email,
            userName: user.fullName || user.email.split('@')[0],
            workflowName: workflowName,
            workflowId: workflow_id,
            startTime: new Date(),
          });
          console.log('[InvokeWorkflow] Registered for email notifications:', invocation.id);
        }
      } catch (storageError) {
        console.warn('[InvokeWorkflow] Failed to create local invocation record:', storageError);
        // Don't fail the request - Galaxy invocation was successful
      }

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

  app.get("/api/galaxy/workflows/sse/:workflowId/:invocationId", (req, res) => {
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

      // Check if memory integration should be used
      const useMemory = memoryIntegration && (context?.memorySessionId || context?.projectId);
      let assistantResponse;
      let episodeId: number | undefined;

      if (useMemory) {
        // Process with memory enhancement
        console.log('[Chat API] Using memory-enhanced processing');
        const memoryResponse = await memoryIntegration!.processWithMemory(message, context as MemoryEnhancedContext);
        assistantResponse = memoryResponse;
        episodeId = memoryResponse.episodeId;
      } else {
        // Standard processing without memory
        assistantResponse = await galaxyAssistant.processMessage(message, context || {});
      }

      console.log('[Chat API] Galaxy Assistant response:', {
        toolSearchUsed: assistantResponse.sources.toolSearchUsed,
        datasetRAGUsed: assistantResponse.sources.datasetRAGUsed,
        workflowGenerated: assistantResponse.sources.workflowGenerated,
        thinkingUsed: assistantResponse.sources.thinkingUsed,
        toolsFound: assistantResponse.recommendedTools?.length || 0,
        datasetsFound: assistantResponse.recommendedDatasets?.length || 0,
        memoryUsed: useMemory,
        episodeId,
      });

      // If workflow was generated, validate prerequisites
      let prerequisitesValidation = null;
      if (assistantResponse.generatedWorkflow && prerequisitesValidator) {
        try {
          console.log('[Chat API] Validating workflow prerequisites...');
          prerequisitesValidation = await prerequisitesValidator.validate({
            workflowDefinition: assistantResponse.generatedWorkflow,
            historyId: context?.historyId,
            userContext: message, // Use original message as context
          });
          console.log('[Chat API] Prerequisites validation:', {
            fulfilled: prerequisitesValidation.fulfilled,
            missingInputs: prerequisitesValidation.analysis.missingInputs.length,
            missingParams: prerequisitesValidation.analysis.missingParameters.length,
          });
        } catch (validationError: any) {
          console.error('[Chat API] Prerequisites validation failed:', validationError.message);
          // Non-fatal - continue without validation
        }
      }

      // Format response for frontend
      res.json({
        response: assistantResponse.message,
        suggestions: assistantResponse.suggestions,
        workflow: assistantResponse.generatedWorkflow,

        // Pre-execution validation (if workflow was generated)
        prerequisitesValidation,

        // Thinking mode support
        thinking_content: assistantResponse.thinking_content,
        thinking_level: assistantResponse.thinking_level,

        // Memory tracking
        episodeId,

        // Additional metadata for UI enhancement
        metadata: {
          recommendedTools: assistantResponse.recommendedTools,
          recommendedDatasets: assistantResponse.recommendedDatasets,
          workflowSuggestion: assistantResponse.workflowSuggestion,
          sources: assistantResponse.sources,
          memoryUsed: useMemory,
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
  // AI Assistant - Pilot Run API (Added 2025-12-30)
  // ============================================================================

  // Start a pilot run for parameter tuning
  app.post("/api/ai_assistant/pilot/start", async (req, res) => {
    try {
      const { workflow_id, total_samples, config } = req.body;

      if (!workflow_id) {
        return res.status(400).json({ error: "workflow_id is required" });
      }

      console.log('[Pilot API] Starting pilot run for workflow:', workflow_id);

      // Proxy to Galaxy backend
      const response = await galaxyAPIProxy.client.post('/api/ai_assistant/pilot/start', {
        workflow_id,
        total_samples: total_samples || 100,
        config: config || {},
      });

      res.json(response.data);
    } catch (error: any) {
      console.error("[Pilot API] Error starting pilot:", error);
      res.status(500).json({
        success: false,
        error: 'PilotStartError',
        message: error.message || 'Failed to start pilot run',
      });
    }
  });

  // Get pilot run status
  app.get("/api/ai_assistant/pilot/:pilotId/status", async (req, res) => {
    try {
      const { pilotId } = req.params;

      console.log('[Pilot API] Getting status for pilot:', pilotId);

      const response = await galaxyAPIProxy.client.get(`/api/ai_assistant/pilot/${pilotId}/status`);
      res.json(response.data);
    } catch (error: any) {
      console.error("[Pilot API] Error getting pilot status:", error);
      res.status(500).json({
        success: false,
        error: 'PilotStatusError',
        message: error.message || 'Failed to get pilot status',
      });
    }
  });

  // Get full run estimate from pilot results
  app.get("/api/ai_assistant/pilot/:pilotId/estimate", async (req, res) => {
    try {
      const { pilotId } = req.params;

      console.log('[Pilot API] Getting estimate for pilot:', pilotId);

      const response = await galaxyAPIProxy.client.get(`/api/ai_assistant/pilot/${pilotId}/estimate`);
      res.json(response.data);
    } catch (error: any) {
      console.error("[Pilot API] Error getting pilot estimate:", error);
      res.status(500).json({
        success: false,
        error: 'PilotEstimateError',
        message: error.message || 'Failed to get pilot estimate',
      });
    }
  });

  // ============================================================================
  // AI Assistant - Citation API (Added 2025-12-30)
  // ============================================================================

  // Export citations as BibTeX
  app.post("/api/ai_assistant/citations/export", async (req, res) => {
    try {
      const { workflow_ga, include_all } = req.body;

      if (!workflow_ga) {
        return res.status(400).json({ error: "workflow_ga is required" });
      }

      console.log('[Citation API] Exporting citations for workflow');

      const response = await galaxyAPIProxy.client.post('/api/ai_assistant/citations/export', {
        workflow_ga,
        include_all: include_all ?? true,
      });

      res.json(response.data);
    } catch (error: any) {
      console.error("[Citation API] Error exporting citations:", error);
      res.status(500).json({
        success: false,
        error: 'CitationExportError',
        message: error.message || 'Failed to export citations',
      });
    }
  });

  // Generate methods section text
  app.post("/api/ai_assistant/citations/methods", async (req, res) => {
    try {
      const { workflow_ga, style } = req.body;

      if (!workflow_ga) {
        return res.status(400).json({ error: "workflow_ga is required" });
      }

      console.log('[Citation API] Generating methods section, style:', style);

      const response = await galaxyAPIProxy.client.post('/api/ai_assistant/citations/methods', {
        workflow_ga,
        style: style || 'apa',
      });

      res.json(response.data);
    } catch (error: any) {
      console.error("[Citation API] Error generating methods:", error);
      res.status(500).json({
        success: false,
        error: 'MethodsGenerationError',
        message: error.message || 'Failed to generate methods section',
      });
    }
  });

  // ============================================================================
  // AI Assistant - Benchmark API (Added 2025-12-30)
  // ============================================================================

  // Get benchmark results for a scenario
  app.get("/api/ai_assistant/benchmarks/:scenario", async (req, res) => {
    try {
      const { scenario } = req.params;

      console.log('[Benchmark API] Getting benchmarks for scenario:', scenario);

      const response = await galaxyAPIProxy.client.get(`/api/ai_assistant/benchmarks/${encodeURIComponent(scenario)}`);
      res.json(response.data);
    } catch (error: any) {
      console.error("[Benchmark API] Error getting benchmarks:", error);
      res.status(500).json({
        available: false,
        error: 'BenchmarkQueryError',
        message: error.message || 'Failed to get benchmark results',
      });
    }
  });

  // Query benchmarks with natural language (NEW)
  app.post("/api/ai_assistant/benchmark_query", async (req, res) => {
    try {
      const { query, constraints, top_k } = req.body;

      if (!query) {
        return res.status(400).json({ error: "query is required" });
      }

      console.log('[Benchmark API] Querying benchmarks:', query);

      const response = await galaxyAPIProxy.client.post('/api/ai_assistant/benchmark_query', {
        query,
        constraints: constraints || {},
        top_k: top_k || 5,
      });

      res.json(response.data);
    } catch (error: any) {
      console.error("[Benchmark API] Error querying benchmarks:", error);
      res.status(500).json({
        success: false,
        error: 'BenchmarkQueryError',
        message: error.message || 'Failed to query benchmarks',
      });
    }
  });

  // Compare tools with benchmark evidence (NEW)
  app.post("/api/ai_assistant/tool_comparison", async (req, res) => {
    try {
      const { tool_a, tool_b, task } = req.body;

      if (!tool_a || !tool_b) {
        return res.status(400).json({ error: "tool_a and tool_b are required" });
      }

      console.log('[Benchmark API] Comparing tools:', tool_a, 'vs', tool_b);

      const response = await galaxyAPIProxy.client.post('/api/ai_assistant/tool_comparison', {
        tool_a,
        tool_b,
        task: task || null,
      });

      res.json(response.data);
    } catch (error: any) {
      console.error("[Benchmark API] Error comparing tools:", error);
      res.status(500).json({
        success: false,
        error: 'ToolComparisonError',
        message: error.message || 'Failed to compare tools',
      });
    }
  });

  // ============================================================================
  // AI Assistant - Research Query API (Added 2025-12-30)
  // ============================================================================

  // Answer research questions with literature-backed evidence
  app.post("/api/ai_assistant/research_query", async (req, res) => {
    try {
      const { query, context, include_citations, include_benchmark_evidence, max_citations } = req.body;

      if (!query) {
        return res.status(400).json({ error: "query is required" });
      }

      console.log('[Research API] Answering research question:', query);

      const response = await galaxyAPIProxy.client.post('/api/ai_assistant/research_query', {
        query,
        context: context || {},
        include_citations: include_citations ?? true,
        include_benchmark_evidence: include_benchmark_evidence ?? true,
        max_citations: max_citations || 5,
      });

      res.json(response.data);
    } catch (error: any) {
      console.error("[Research API] Error answering research query:", error);
      res.status(500).json({
        success: false,
        error: 'ResearchQueryError',
        message: error.message || 'Failed to answer research question',
      });
    }
  });

  // Get available scientific skills
  app.get("/api/ai_assistant/skills/available", async (req, res) => {
    try {
      console.log('[Skills API] Getting available skills');

      const response = await galaxyAPIProxy.client.get('/api/ai_assistant/skills/available');
      res.json(response.data);
    } catch (error: any) {
      console.error("[Skills API] Error getting skills:", error);
      res.status(500).json({
        available: false,
        error: 'SkillsQueryError',
        message: error.message || 'Failed to get available skills',
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
  // Long-Term Memory API
  // ============================================================================

  // Get or create user profile with LTM context
  app.get("/api/memory/user", authenticateToken, async (req, res) => {
    try {
      const userContext = await memoryService.users.loadUserContext(req.user!.id);
      res.json(userContext);
    } catch (error: any) {
      console.error('[API] Load user context failed:', error);
      res.status(500).json({ error: 'Failed to load user context', message: error.message });
    }
  });

  // Update user preferences
  app.post("/api/memory/user/preferences", authenticateToken, async (req, res) => {
    try {
      const { preferenceType, preferenceKey, preferenceValue, context, learnedFrom } = req.body;
      const preference = await memoryService.users.recordPreference({
        userId: req.user!.id,
        preferenceType,
        preferenceKey,
        preferenceValue,
        context,
        learnedFrom,
      });
      res.json(preference);
    } catch (error: any) {
      console.error('[API] Record preference failed:', error);
      res.status(500).json({ error: 'Failed to record preference', message: error.message });
    }
  });

  // Record a correction
  app.post("/api/memory/user/corrections", authenticateToken, async (req, res) => {
    try {
      const { sessionId, projectId, suggestedApproach, correctedApproach, workflowContext, userExplanation } = req.body;
      const correction = await memoryService.users.recordCorrection({
        userId: req.user!.id,
        sessionId,
        projectId,
        suggestedApproach,
        correctedApproach,
        workflowContext,
        userExplanation,
      });
      res.json(correction);
    } catch (error: any) {
      console.error('[API] Record correction failed:', error);
      res.status(500).json({ error: 'Failed to record correction', message: error.message });
    }
  });

  // ============================================================================
  // Project Memory API
  // ============================================================================

  // Get all projects for user
  app.get("/api/memory/projects", authenticateToken, async (req, res) => {
    try {
      const { status } = req.query;
      const projects = await memoryService.projects.getUserProjects(
        req.user!.id,
        status as 'active' | 'archived' | 'completed' | undefined
      );
      res.json(projects);
    } catch (error: any) {
      console.error('[API] Get projects failed:', error);
      res.status(500).json({ error: 'Failed to get projects', message: error.message });
    }
  });

  // Create a new project
  app.post("/api/memory/projects", authenticateToken, async (req, res) => {
    try {
      const { name, description, researchGoal, instructions, primaryDomain, organisms, tissueTypes, conditions, dataModalities, category, tags } = req.body;
      const project = await memoryService.projects.createProject({
        userId: req.user!.id,
        name,
        description,
        researchGoal,
        instructions,
        primaryDomain,
        organisms,
        tissueTypes,
        conditions,
        dataModalities,
        category,
        tags,
      });
      res.json(project);
    } catch (error: any) {
      console.error('[API] Create project failed:', error);
      res.status(500).json({ error: 'Failed to create project', message: error.message });
    }
  });

  // Get project with full context
  app.get("/api/memory/projects/:projectId", authenticateToken, async (req, res) => {
    try {
      const { projectId } = req.params;
      const projectContext = await memoryService.projects.loadProjectContext(projectId);
      if (!projectContext.project) {
        return res.status(404).json({ error: 'Project not found' });
      }
      res.json(projectContext);
    } catch (error: any) {
      console.error('[API] Get project context failed:', error);
      res.status(500).json({ error: 'Failed to get project context', message: error.message });
    }
  });

  // Update project
  app.put("/api/memory/projects/:projectId", authenticateToken, async (req, res) => {
    try {
      const { projectId } = req.params;
      const project = await memoryService.projects.updateProject(projectId, req.body);
      res.json(project);
    } catch (error: any) {
      console.error('[API] Update project failed:', error);
      res.status(500).json({ error: 'Failed to update project', message: error.message });
    }
  });

  // Add project knowledge
  app.post("/api/memory/projects/:projectId/knowledge", authenticateToken, async (req, res) => {
    try {
      const { projectId } = req.params;
      const { knowledgeType, title, content, source, relatedWorkflows, relatedSessions } = req.body;
      const knowledge = await memoryService.projects.addProjectKnowledge({
        projectId,
        knowledgeType,
        title,
        content,
        source,
        relatedWorkflows,
        relatedSessions,
      });
      res.json(knowledge);
    } catch (error: any) {
      console.error('[API] Add project knowledge failed:', error);
      res.status(500).json({ error: 'Failed to add knowledge', message: error.message });
    }
  });

  // Search projects
  app.get("/api/memory/projects/search", authenticateToken, async (req, res) => {
    try {
      const { domain, tags, text } = req.query;
      const projects = await memoryService.projects.searchProjects(req.user!.id, {
        domain: domain as string | undefined,
        tags: tags ? (tags as string).split(',') : undefined,
        text: text as string | undefined,
      });
      res.json(projects);
    } catch (error: any) {
      console.error('[API] Search projects failed:', error);
      res.status(500).json({ error: 'Failed to search projects', message: error.message });
    }
  });

  // ============================================================================
  // Session Memory API
  // ============================================================================

  // Initialize a new session
  app.post("/api/memory/sessions", authenticateToken, async (req, res) => {
    try {
      const { projectId } = req.body;
      const result = await memoryService.initializeSession(req.user!.id, projectId);
      res.json(result);
    } catch (error: any) {
      console.error('[API] Initialize session failed:', error);
      res.status(500).json({ error: 'Failed to initialize session', message: error.message });
    }
  });

  // Get session
  app.get("/api/memory/sessions/:sessionId", authenticateToken, async (req, res) => {
    try {
      const { sessionId } = req.params;
      const session = await memoryService.sessions.getSession(sessionId);
      if (!session) {
        return res.status(404).json({ error: 'Session not found' });
      }
      const messages = await memoryService.sessions.getSessionMessages(sessionId);
      res.json({ session, messages });
    } catch (error: any) {
      console.error('[API] Get session failed:', error);
      res.status(500).json({ error: 'Failed to get session', message: error.message });
    }
  });

  // End session with summary
  app.put("/api/memory/sessions/:sessionId/end", authenticateToken, async (req, res) => {
    try {
      const { sessionId } = req.params;
      const { summary, keyDecisions } = req.body;
      const session = await memoryService.endSessionWithSummary(sessionId, summary, keyDecisions);
      res.json(session);
    } catch (error: any) {
      console.error('[API] End session failed:', error);
      res.status(500).json({ error: 'Failed to end session', message: error.message });
    }
  });

  // Get recent sessions
  app.get("/api/memory/sessions", authenticateToken, async (req, res) => {
    try {
      const { limit } = req.query;
      const sessions = await memoryService.sessions.getRecentSessions(
        req.user!.id,
        limit ? parseInt(limit as string) : 10
      );
      res.json(sessions);
    } catch (error: any) {
      console.error('[API] Get recent sessions failed:', error);
      res.status(500).json({ error: 'Failed to get sessions', message: error.message });
    }
  });

  // Record interaction (message + episode)
  app.post("/api/memory/interactions", authenticateToken, async (req, res) => {
    try {
      const { sessionId, projectId, userMessage, assistantResponse, userIntent, toolsUsed, workflowGenerated, workflowId } = req.body;
      const result = await memoryService.recordInteraction({
        sessionId,
        projectId,
        userMessage,
        assistantResponse,
        userIntent,
        toolsUsed,
        workflowGenerated,
        workflowId,
      });
      res.json(result);
    } catch (error: any) {
      console.error('[API] Record interaction failed:', error);
      res.status(500).json({ error: 'Failed to record interaction', message: error.message });
    }
  });

  // ============================================================================
  // Memory Sync API - Bidirectional sync between frontend localStorage and backend
  // ============================================================================

  /**
   * Sync frontend localStorage state with backend memory
   * Implements conflict resolution with "last write wins" strategy
   */
  app.post("/api/memory/sync", authenticateToken, async (req, res) => {
    try {
      const userId = req.user!.id;
      const { chatSessions, userSettings, lastSyncTimestamp } = req.body;

      const syncResult = {
        success: true,
        synced: {
          chatSessions: 0,
          preferences: 0,
        },
        conflicts: [] as Array<{ type: string; id: string; resolution: string }>,
        serverTimestamp: new Date().toISOString(),
      };

      // Sync chat sessions to backend memory
      if (chatSessions && Array.isArray(chatSessions)) {
        for (const session of chatSessions) {
          try {
            // Check if session exists in backend
            const existingSession = await memoryService.sessions.getSession(session.id);

            if (!existingSession) {
              // Create new session in backend
              await memoryService.sessions.createSession({
                id: session.id,
                userId,
                projectId: session.projectId,
              });
              syncResult.synced.chatSessions++;
            } else {
              // Conflict resolution: compare timestamps
              const frontendUpdated = new Date(session.lastActivity);
              const backendUpdated = existingSession.startedAt || new Date(0);

              if (frontendUpdated > backendUpdated) {
                // Frontend is newer - would update backend (not implemented yet)
                syncResult.conflicts.push({
                  type: 'chatSession',
                  id: session.id,
                  resolution: 'frontend_newer_accepted',
                });
              } else {
                syncResult.conflicts.push({
                  type: 'chatSession',
                  id: session.id,
                  resolution: 'backend_newer_kept',
                });
              }
            }
          } catch (sessionError) {
            console.error(`[MemorySync] Failed to sync session ${session.id}:`, sessionError);
          }
        }
      }

      // Sync user settings/preferences
      if (userSettings && typeof userSettings === 'object') {
        try {
          // Convert user settings to preferences
          for (const [key, value] of Object.entries(userSettings)) {
            if (key === 'id' || key === 'userId' || key === 'updatedAt') continue;

            await memoryService.users.recordPreference({
              userId,
              preferenceType: 'user_setting',
              preferenceKey: key,
              preferenceValue: JSON.stringify(value),
              context: { source: 'frontend_sync' },
              learnedFrom: 'user_explicit',
            });
            syncResult.synced.preferences++;
          }
        } catch (prefError) {
          console.error('[MemorySync] Failed to sync preferences:', prefError);
        }
      }

      // Log sync event for audit
      await auditService.log({
        userId,
        action: 'memory.sync',
        resourceType: 'memory',
        details: {
          chatSessionsSynced: syncResult.synced.chatSessions,
          preferencesSynced: syncResult.synced.preferences,
          conflictsCount: syncResult.conflicts.length,
        },
        status: 'success',
      });

      res.json(syncResult);
    } catch (error: any) {
      console.error('[API] Memory sync failed:', error);
      res.status(500).json({ error: 'Memory sync failed', message: error.message });
    }
  });

  /**
   * Get backend memory state for frontend sync
   * Returns user context, projects, and recent sessions
   */
  app.get("/api/memory/sync", authenticateToken, async (req, res) => {
    try {
      const userId = req.user!.id;

      // Load user context from backend
      const userContext = await memoryService.users.loadUserContext(userId);

      // Load user's projects
      const projects = await memoryService.projects.getUserProjects(userId, 'active');

      // Load recent sessions
      const recentSessions = await memoryService.sessions.getRecentSessions(userId, 20);

      // Convert preferences to user settings format
      const userSettings: Record<string, any> = {};
      for (const pref of userContext.preferences) {
        if (pref.preferenceType === 'user_setting') {
          try {
            userSettings[pref.preferenceKey] = JSON.parse(pref.preferenceValue as string);
          } catch {
            userSettings[pref.preferenceKey] = pref.preferenceValue;
          }
        }
      }

      res.json({
        success: true,
        serverTimestamp: new Date().toISOString(),
        data: {
          user: userContext.user,
          userSettings,
          projects,
          recentSessions,
          stats: userContext.stats,
        },
      });
    } catch (error: any) {
      console.error('[API] Get sync state failed:', error);
      res.status(500).json({ error: 'Get sync state failed', message: error.message });
    }
  });

  // ============================================================================
  // Episodic Memory API
  // ============================================================================

  // Get similar episodes for a project
  app.get("/api/memory/projects/:projectId/episodes", authenticateToken, async (req, res) => {
    try {
      const { projectId } = req.params;
      const { intent, tools, limit } = req.query;
      const episodes = await memoryService.episodes.getSimilarEpisodes(projectId, {
        intent: intent as string | undefined,
        toolsUsed: tools ? (tools as string).split(',') : undefined,
        limit: limit ? parseInt(limit as string) : 10,
      });
      res.json(episodes);
    } catch (error: any) {
      console.error('[API] Get episodes failed:', error);
      res.status(500).json({ error: 'Failed to get episodes', message: error.message });
    }
  });

  // Update episode outcome
  app.put("/api/memory/episodes/:episodeId/outcome", authenticateToken, async (req, res) => {
    try {
      const { episodeId } = req.params;
      const { success, errorType, errorMessage, whatWorked, whatFailed, lessonsLearned } = req.body;
      const episode = await memoryService.episodes.updateEpisodeOutcome(parseInt(episodeId), {
        success,
        errorType,
        errorMessage,
        whatWorked,
        whatFailed,
        lessonsLearned,
      });
      res.json(episode);
    } catch (error: any) {
      console.error('[API] Update episode outcome failed:', error);
      res.status(500).json({ error: 'Failed to update episode', message: error.message });
    }
  });

  // Consolidate episodes into patterns
  app.post("/api/memory/projects/:projectId/consolidate", authenticateToken, async (req, res) => {
    try {
      const { projectId } = req.params;
      const result = await memoryService.episodes.consolidateEpisodes(projectId);
      res.json(result);
    } catch (error: any) {
      console.error('[API] Consolidate episodes failed:', error);
      res.status(500).json({ error: 'Failed to consolidate episodes', message: error.message });
    }
  });

  // ============================================================================
  // Procedural Memory API
  // ============================================================================

  // Get procedures for a project
  app.get("/api/memory/projects/:projectId/procedures", authenticateToken, async (req, res) => {
    try {
      const { projectId } = req.params;
      const { minSuccessRate } = req.query;
      const procedures = await memoryService.procedures.getReliableProcedures(
        projectId,
        minSuccessRate ? parseFloat(minSuccessRate as string) : 0.7
      );
      res.json(procedures);
    } catch (error: any) {
      console.error('[API] Get procedures failed:', error);
      res.status(500).json({ error: 'Failed to get procedures', message: error.message });
    }
  });

  // Find matching procedures for a trigger
  app.get("/api/memory/projects/:projectId/procedures/match", authenticateToken, async (req, res) => {
    try {
      const { projectId } = req.params;
      const { trigger } = req.query;
      if (!trigger) {
        return res.status(400).json({ error: 'trigger query parameter required' });
      }
      const procedures = await memoryService.procedures.findMatchingProcedures(
        projectId,
        trigger as string
      );
      res.json(procedures);
    } catch (error: any) {
      console.error('[API] Find matching procedures failed:', error);
      res.status(500).json({ error: 'Failed to find procedures', message: error.message });
    }
  });

  // Create a procedure
  app.post("/api/memory/projects/:projectId/procedures", authenticateToken, async (req, res) => {
    try {
      const { projectId } = req.params;
      const { name, triggerPattern, description, steps, preconditions, postconditions, applicableDomains, learnedFrom } = req.body;
      const procedure = await memoryService.procedures.createProcedure({
        projectId,
        name,
        triggerPattern,
        description,
        steps,
        preconditions,
        postconditions,
        applicableDomains,
        learnedFrom,
      });
      res.json(procedure);
    } catch (error: any) {
      console.error('[API] Create procedure failed:', error);
      res.status(500).json({ error: 'Failed to create procedure', message: error.message });
    }
  });

  // Record procedure usage
  app.post("/api/memory/procedures/:procedureId/usage", authenticateToken, async (req, res) => {
    try {
      const { procedureId } = req.params;
      const { success } = req.body;
      const procedure = await memoryService.procedures.recordUsage(parseInt(procedureId), success);
      res.json(procedure);
    } catch (error: any) {
      console.error('[API] Record procedure usage failed:', error);
      res.status(500).json({ error: 'Failed to record usage', message: error.message });
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
  app.get("/api/invocations", optionalAuth, async (req, res) => {
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

  // Download all outputs for an invocation as ZIP
  app.get("/api/invocations/:id/download-all", async (req, res) => {
    try {
      const invocation = await storage.getInvocation(req.params.id);
      if (!invocation) {
        return res.status(404).json({ error: "Invocation not found" });
      }

      const outputs = await storage.getInvocationOutputs(req.params.id);
      if (!outputs || outputs.length === 0) {
        return res.status(404).json({ error: "No outputs found for this invocation" });
      }

      // Create ZIP archive
      const archive = archiver('zip', { zlib: { level: 9 } });

      // Set response headers
      const zipFilename = `${invocation.workflowName || 'workflow'}_outputs_${req.params.id.slice(0, 8)}.zip`;
      res.setHeader('Content-Type', 'application/zip');
      res.setHeader('Content-Disposition', `attachment; filename="${zipFilename}"`);

      // Pipe archive to response
      archive.pipe(res);

      // Handle archive errors
      archive.on('error', (err) => {
        console.error('Archive error:', err);
        if (!res.headersSent) {
          res.status(500).json({ error: 'Failed to create archive' });
        }
      });

      // Add each output to the archive
      for (const output of outputs) {
        try {
          const fileStream = await galaxyAPIProxy.downloadDataset(output.galaxyDatasetId);
          const filename = `${output.name}.${output.extension}`;
          archive.append(fileStream, { name: filename });
        } catch (err) {
          console.error(`Failed to add ${output.name} to archive:`, err);
          // Continue with other files
        }
      }

      // Finalize the archive
      await archive.finalize();
    } catch (error: any) {
      console.error("Error creating download archive:", error);
      if (!res.headersSent) {
        res.status(500).json({ error: error.message });
      }
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

  // ============================================================================
  // Pre-Execution Validation API (LLM-powered prerequisites check)
  // ============================================================================

  /**
   * Validate workflow prerequisites before execution
   * Uses LLM intelligence to analyze:
   * - Required inputs vs available datasets
   * - Required parameters
   * - Data format compatibility
   *
   * Returns conversational guidance for the user
   */
  app.post("/api/workflows/validate", optionalAuth, async (req, res) => {
    try {
      if (!prerequisitesValidator) {
        return res.status(503).json({
          error: "Prerequisites validator not available",
          message: "ANTHROPIC_API_KEY not configured"
        });
      }

      const { workflowDefinition, inputs, parameters, historyId, userContext } = req.body;

      if (!workflowDefinition) {
        return res.status(400).json({
          error: "workflowDefinition is required"
        });
      }

      console.log('[Validate] Starting pre-execution validation for workflow:', workflowDefinition.name);

      const result = await prerequisitesValidator.validate({
        workflowDefinition,
        inputs,
        parameters,
        historyId,
        userContext,
      });

      console.log('[Validate] Validation complete:', {
        fulfilled: result.fulfilled,
        inputMappings: result.analysis.inputMappings.length,
        missingInputs: result.analysis.missingInputs.length,
        missingParams: result.analysis.missingParameters.length,
      });

      res.json(result);
    } catch (error: any) {
      console.error('[Validate] Validation failed:', error);
      res.status(500).json({
        error: "Validation failed",
        message: error.message
      });
    }
  });

  // ============================================================================
  // Unified Workflow Execution API (Sandbox/Production with Tunable Data Scope)
  // ============================================================================

  // Create a new execution run (unified sandbox/production)
  app.post("/api/workflows/execute", optionalAuth, async (req, res) => {
    let executionRun: any = null;
    let galaxyHistoryId: string | null = null;
    let galaxyWorkflowId: string | null = null;

    try {
      const request = req.body;

      // Validation
      if (!request.workflowDefinition) {
        return res.status(400).json({ error: "workflowDefinition is required" });
      }

      // Check if workflow has input steps that require data
      const steps = request.workflowDefinition.steps || {};
      const inputSteps = Object.values(steps).filter((step: any) =>
        step.type === 'data_input' || step.type === 'data_collection_input'
      );

      // Validate inputs are provided if workflow has input steps
      const inputs = request.inputs || [];
      if (inputSteps.length > 0 && inputs.length === 0) {
        return res.status(400).json({
          error: "inputs_required",
          message: `Workflow has ${inputSteps.length} input step(s) but no inputs were provided`,
          inputStepsCount: inputSteps.length
        });
      }

      // Create execution run record
      executionRun = await storage.createExecutionRun(
        request,
        req.user?.id,
        request.projectId
      );

      // Determine history name based on mode
      const mode = request.executionConfig?.mode || 'sandbox';
      const historyPrefix = mode === 'sandbox' ? '[Sandbox]' : '[Production]';
      const historyName = `${historyPrefix} ${executionRun.workflowName} - Run ${executionRun.runSequence}`;

      // Create Galaxy history
      galaxyHistoryId = await galaxyAPIProxy.createHistory(historyName);

      // Apply data scope if specified
      let sampledInputs = inputs;
      const dataScope = executionRun.dataScope;

      if (dataScope.fraction < 1.0 && sampledInputs.length > 0) {
        // Sample inputs based on data scope configuration
        const totalCount = sampledInputs.length;
        const targetCount = Math.max(1, Math.ceil(totalCount * dataScope.fraction));

        if (dataScope.samplingStrategy === 'random') {
          // Random sampling
          const shuffled = [...sampledInputs].sort(() => Math.random() - 0.5);
          sampledInputs = shuffled.slice(0, targetCount);
        } else if (dataScope.samplingStrategy === 'first_n') {
          // First N sampling
          sampledInputs = sampledInputs.slice(0, targetCount);
        }
        // For stratified and representative, would need metadata - use all for now

        // Update execution run with sampled IDs
        await storage.updateExecutionRun(executionRun.id, {
          dataScope: {
            ...dataScope,
            absoluteCount: sampledInputs.length,
            totalAvailable: totalCount,
            sampledIds: sampledInputs.map((i: any) => i.id),
          }
        });
      }

      // Create workflow in Galaxy
      const galaxyWorkflow = await galaxyAPIProxy.createWorkflow(request.workflowDefinition);
      galaxyWorkflowId = galaxyWorkflow.id;

      // Invoke workflow in Galaxy
      // Build inputs object for Galaxy (mapping step inputs to dataset IDs)
      const galaxyInputs: Record<string, any> = {};
      for (const input of sampledInputs) {
        const stepId = input.step_id ?? 0;
        galaxyInputs[stepId.toString()] = {
          src: input.src || 'hda',
          id: input.id
        };
      }

      const invocationResult = await galaxyAPIProxy.invokeWorkflow(
        galaxyWorkflow.id,
        galaxyInputs,
        { history_id: galaxyHistoryId }
      );

      // Update execution run with Galaxy IDs and status
      await storage.updateExecutionRun(executionRun.id, {
        execution: {
          ...executionRun.execution,
          galaxyInvocationId: invocationResult.id,
          galaxyHistoryId: galaxyHistoryId,
          galaxyWorkflowId: galaxyWorkflow.id,
          status: 'queued',
          startedAt: new Date(),
        }
      });

      // Start polling for this invocation
      galaxyPoller.startPolling(
        invocationResult.id,
        galaxyWorkflow.id
      );

      // Also create a legacy invocation record for backward compatibility
      await storage.createInvocation({
        userId: req.user?.id,
        workflowName: executionRun.workflowName,
        workflowDefinition: request.workflowDefinition,
        galaxyInvocationId: invocationResult.id,
        galaxyHistoryId: galaxyHistoryId,
        galaxyWorkflowId: galaxyWorkflow.id,
        inputDatasets: sampledInputs,
        totalSteps: executionRun.progress.totalSteps,
        status: 'running',
      });

      res.json({
        runId: executionRun.id,
        galaxyInvocationId: invocationResult.id,
        galaxyHistoryId: galaxyHistoryId,
        status: 'queued',
        dataScopeApplied: {
          fraction: executionRun.dataScope.fraction,
          absoluteCount: sampledInputs.length,
          sampledIds: sampledInputs.map((i: any) => i.id),
        }
      });
    } catch (error: any) {
      console.error("[ExecutionRun] Error creating execution run:", error);

      // If execution run was created, mark it as failed
      if (executionRun?.id) {
        try {
          const errorMessage = error.detail?.err_msg || error.message || 'Unknown error';
          await storage.updateExecutionRun(executionRun.id, {
            execution: {
              ...executionRun.execution,
              status: 'failed',
              errorMessage: errorMessage,
              galaxyHistoryId: galaxyHistoryId || undefined,
              galaxyWorkflowId: galaxyWorkflowId || undefined,
            }
          });
          console.log(`[ExecutionRun] Marked run ${executionRun.id} as failed`);
        } catch (updateError) {
          console.error("[ExecutionRun] Failed to update run status:", updateError);
        }
      }

      // Return detailed error
      const statusCode = error.status_code || 500;
      res.status(statusCode).json({
        error: error.error || 'ExecutionError',
        message: error.detail?.err_msg || error.message || 'Failed to execute workflow',
        runId: executionRun?.id,
        details: error.detail
      });
    }
  });

  // Get all execution runs for the current user
  app.get("/api/workflows/runs", optionalAuth, async (req, res) => {
    try {
      const { mode, projectId, limit } = req.query;
      const runs = await storage.getExecutionRuns(
        req.user?.id,
        projectId as string,
        mode as 'sandbox' | 'production' | undefined,
        limit ? parseInt(limit as string) : 100
      );
      res.json(runs);
    } catch (error: any) {
      console.error("[ExecutionRun] Error fetching runs:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Get a specific execution run by ID
  app.get("/api/workflows/runs/:id", async (req, res) => {
    try {
      const run = await storage.getExecutionRun(req.params.id);
      if (!run) {
        return res.status(404).json({ error: "Execution run not found" });
      }
      res.json(run);
    } catch (error: any) {
      console.error("[ExecutionRun] Error fetching run:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Get execution run status (lightweight polling endpoint)
  app.get("/api/workflows/runs/:id/status", async (req, res) => {
    try {
      const run = await storage.getExecutionRun(req.params.id);
      if (!run) {
        return res.status(404).json({ error: "Execution run not found" });
      }

      // Return lightweight status response
      res.json({
        runId: run.id,
        status: run.execution.status,
        progress: run.progress,
        metrics: run.metrics,
        steps: req.query.includeSteps === 'true' ? run.steps : undefined,
        errorMessage: run.execution.errorMessage,
      });
    } catch (error: any) {
      console.error("[ExecutionRun] Error fetching run status:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Get iteration runs (all runs linked to a parent)
  app.get("/api/workflows/runs/:id/iterations", async (req, res) => {
    try {
      const runs = await storage.getExecutionRunsByParent(req.params.id);
      res.json(runs);
    } catch (error: any) {
      console.error("[ExecutionRun] Error fetching iterations:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Update execution run (for parameter changes, etc.)
  app.patch("/api/workflows/runs/:id", async (req, res) => {
    try {
      const updates = req.body;
      const run = await storage.updateExecutionRun(req.params.id, updates);

      if (!run) {
        return res.status(404).json({ error: "Execution run not found" });
      }

      res.json(run);
    } catch (error: any) {
      console.error("[ExecutionRun] Error updating run:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Pause execution run
  app.post("/api/workflows/runs/:id/pause", async (req, res) => {
    try {
      const { reason } = req.body;
      const run = await storage.getExecutionRun(req.params.id);

      if (!run) {
        return res.status(404).json({ error: "Execution run not found" });
      }

      if (run.execution.status !== 'running') {
        return res.status(400).json({ error: "Can only pause running workflows" });
      }

      // Record interaction
      await storage.addExecutionRunInteraction(req.params.id, {
        id: uuidv4(),
        timestamp: new Date(),
        type: 'pause',
        details: { reason },
        reason,
        userId: req.user?.id,
      });

      // Update status
      const updated = await storage.updateExecutionRun(req.params.id, {
        execution: {
          ...run.execution,
          status: 'paused',
          pausedAt: new Date(),
          pauseReason: reason,
        }
      });

      res.json(updated);
    } catch (error: any) {
      console.error("[ExecutionRun] Error pausing run:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Resume execution run
  app.post("/api/workflows/runs/:id/resume", async (req, res) => {
    try {
      const run = await storage.getExecutionRun(req.params.id);

      if (!run) {
        return res.status(404).json({ error: "Execution run not found" });
      }

      if (run.execution.status !== 'paused') {
        return res.status(400).json({ error: "Can only resume paused workflows" });
      }

      // Record interaction
      await storage.addExecutionRunInteraction(req.params.id, {
        id: uuidv4(),
        timestamp: new Date(),
        type: 'resume',
        details: {},
        userId: req.user?.id,
      });

      // Update status
      const updated = await storage.updateExecutionRun(req.params.id, {
        execution: {
          ...run.execution,
          status: 'running',
          pausedAt: undefined,
          pauseReason: undefined,
        }
      });

      res.json(updated);
    } catch (error: any) {
      console.error("[ExecutionRun] Error resuming run:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Cancel execution run
  app.post("/api/workflows/runs/:id/cancel", async (req, res) => {
    try {
      const { reason } = req.body;
      const run = await storage.getExecutionRun(req.params.id);

      if (!run) {
        return res.status(404).json({ error: "Execution run not found" });
      }

      // Record interaction
      await storage.addExecutionRunInteraction(req.params.id, {
        id: uuidv4(),
        timestamp: new Date(),
        type: 'cancel',
        details: { reason },
        reason,
        userId: req.user?.id,
      });

      // Cancel in Galaxy if we have an invocation ID
      if (run.execution.galaxyInvocationId) {
        try {
          // Galaxy doesn't have a direct cancel API, but we can delete the invocation
          // For now, just update our record
        } catch (galaxyError) {
          console.error('[ExecutionRun] Failed to cancel in Galaxy:', galaxyError);
        }
      }

      // Update status
      const updated = await storage.updateExecutionRunStatus(
        req.params.id,
        'cancelled',
        reason || 'Cancelled by user'
      );

      res.json(updated);
    } catch (error: any) {
      console.error("[ExecutionRun] Error cancelling run:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Record user interaction
  app.post("/api/workflows/runs/:id/interactions", async (req, res) => {
    try {
      const interaction = req.body;
      const run = await storage.addExecutionRunInteraction(req.params.id, {
        ...interaction,
        id: uuidv4(),
        timestamp: new Date(),
        userId: req.user?.id,
      });

      if (!run) {
        return res.status(404).json({ error: "Execution run not found" });
      }

      res.json(run);
    } catch (error: any) {
      console.error("[ExecutionRun] Error recording interaction:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Compare two execution runs
  app.get("/api/workflows/runs/:id/compare", async (req, res) => {
    try {
      const { with: compareWithId } = req.query;

      if (!compareWithId) {
        return res.status(400).json({ error: "'with' query parameter is required" });
      }

      const comparison = await storage.compareExecutionRuns(
        req.params.id,
        compareWithId as string
      );

      if (!comparison) {
        return res.status(404).json({ error: "One or both runs not found" });
      }

      res.json(comparison);
    } catch (error: any) {
      console.error("[ExecutionRun] Error comparing runs:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Promote sandbox run to production (create new production run with same config)
  app.post("/api/workflows/runs/:id/promote", optionalAuth, async (req, res) => {
    try {
      const sandboxRun = await storage.getExecutionRun(req.params.id);

      if (!sandboxRun) {
        return res.status(404).json({ error: "Execution run not found" });
      }

      if (sandboxRun.mode !== 'sandbox') {
        return res.status(400).json({ error: "Can only promote sandbox runs" });
      }

      // Create production run with 100% data scope
      const productionRequest = {
        workflowDefinition: sandboxRun.workflowDefinition,
        executionConfig: {
          mode: 'production' as const,
          dataScope: {
            fraction: 1.0, // Full dataset
            samplingStrategy: sandboxRun.dataScope.samplingStrategy,
            strataColumn: sandboxRun.dataScope.strataColumn,
            sampledIds: [], // Will be populated during execution
          },
          parentRunId: sandboxRun.id, // Link to sandbox run
          tracking: {
            collectMetrics: true,
            collectDetailedMetrics: true,
            logLevel: 'detailed' as const,
            notifyMilestones: true,
            milestonePercentages: [25, 50, 75, 100],
          },
        },
        inputs: req.body.inputs, // New inputs for full dataset
      };

      // Create the production run
      const productionRun = await storage.createExecutionRun(
        productionRequest,
        req.user?.id,
        sandboxRun.projectId
      );

      // Record interaction on sandbox run
      await storage.addExecutionRunInteraction(sandboxRun.id, {
        id: uuidv4(),
        timestamp: new Date(),
        type: 'parameter_change',
        details: {
          action: 'promoted_to_production',
          productionRunId: productionRun.id,
        },
        reason: 'Promoted to production run',
        userId: req.user?.id,
      });

      res.json({
        productionRunId: productionRun.id,
        sandboxRunId: sandboxRun.id,
        status: 'configuring',
        message: 'Production run created. Configure inputs and execute.',
      });
    } catch (error: any) {
      console.error("[ExecutionRun] Error promoting run:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Delete execution run
  app.delete("/api/workflows/runs/:id", async (req, res) => {
    try {
      const success = await storage.deleteExecutionRun(req.params.id);
      if (!success) {
        return res.status(404).json({ error: "Execution run not found" });
      }
      res.json({ success: true });
    } catch (error: any) {
      console.error("[ExecutionRun] Error deleting run:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // ============================================================================
  // Advanced Galaxy Capabilities API
  // ============================================================================

  // --- Workflow Reports ---

  // Get workflow report (auto-generated analysis summary)
  app.get("/api/invocations/:id/report", async (req, res) => {
    try {
      const { format } = req.query;
      const invocation = await storage.getInvocation(req.params.id);

      if (!invocation) {
        return res.status(404).json({ error: "Invocation not found" });
      }

      if (!invocation.galaxyWorkflowId || !invocation.galaxyInvocationId) {
        return res.status(400).json({
          error: "Galaxy workflow/invocation ID not available",
          message: "This invocation may not have been executed on Galaxy"
        });
      }

      const report = await galaxyAPIProxy.getWorkflowReport(
        invocation.galaxyWorkflowId,
        invocation.galaxyInvocationId,
        (format as 'markdown' | 'html') || 'markdown'
      );

      res.json(report);
    } catch (error: any) {
      console.error("[WorkflowReport] Error generating report:", error);
      res.status(500).json({
        error: 'ReportGenerationError',
        message: error.message || 'Failed to generate workflow report',
      });
    }
  });

  // --- Dataset Collections ---

  // Create a dataset collection for batch processing
  app.post("/api/collections", async (req, res) => {
    try {
      const { name, collection_type, elements } = req.body;

      if (!name || !collection_type || !elements || !Array.isArray(elements)) {
        return res.status(400).json({
          error: "name, collection_type, and elements[] are required"
        });
      }

      // Get Galaxy history from session
      let historyId = req.session?.galaxyHistoryId as string | undefined;
      if (!historyId) {
        const sessionName = `GalaxyChat-${new Date().toISOString().split('T')[0]}`;
        historyId = await galaxyAPIProxy.createHistory(sessionName);
        if (req.session) {
          req.session.galaxyHistoryId = historyId;
        }
      }

      const collection = await galaxyAPIProxy.createDatasetCollection(
        historyId,
        name,
        collection_type as 'list' | 'paired' | 'list:paired',
        elements
      );

      res.json({
        ...collection,
        galaxy_history_id: historyId,
        message: `Collection '${name}' created with ${collection.element_count} elements`
      });
    } catch (error: any) {
      console.error("[Collections] Error creating collection:", error);
      res.status(500).json({
        error: 'CollectionCreationError',
        message: error.message || 'Failed to create dataset collection',
      });
    }
  });

  // Auto-pair datasets (discovers R1/R2 patterns automatically)
  app.post("/api/collections/auto-pair", async (req, res) => {
    try {
      const historyId = req.session?.galaxyHistoryId as string | undefined;

      if (!historyId) {
        return res.status(400).json({
          error: "No Galaxy history found. Please upload datasets first."
        });
      }

      const result = await galaxyAPIProxy.autoPairDatasets(historyId);

      res.json({
        ...result,
        message: `Found ${result.paired.length} paired datasets, ${result.unpaired.length} unpaired`
      });
    } catch (error: any) {
      console.error("[Collections] Error auto-pairing:", error);
      res.status(500).json({
        error: 'AutoPairingError',
        message: error.message || 'Failed to auto-pair datasets',
      });
    }
  });

  // Create paired collection from auto-paired results
  app.post("/api/collections/create-paired", async (req, res) => {
    try {
      const { name, pairs } = req.body;

      if (!name || !pairs || !Array.isArray(pairs)) {
        return res.status(400).json({
          error: "name and pairs[] are required"
        });
      }

      const historyId = req.session?.galaxyHistoryId as string | undefined;
      if (!historyId) {
        return res.status(400).json({
          error: "No Galaxy history found. Please upload datasets first."
        });
      }

      // Get dataset names for proper pairing
      const datasets = await galaxyAPIProxy.getHistoryDatasets(historyId);
      const datasetMap = new Map(datasets.map((d: any) => [d.id, d.name]));

      const forwardReads = pairs.map((p: any) => ({
        id: p.forward,
        name: datasetMap.get(p.forward) || p.name || 'forward'
      }));
      const reverseReads = pairs.map((p: any) => ({
        id: p.reverse,
        name: datasetMap.get(p.reverse) || p.name || 'reverse'
      }));

      const collection = await galaxyAPIProxy.createPairedCollection(
        historyId,
        name,
        forwardReads,
        reverseReads
      );

      res.json({
        ...collection,
        galaxy_history_id: historyId,
        message: `Paired collection '${name}' created with ${collection.pairs} pairs`
      });
    } catch (error: any) {
      console.error("[Collections] Error creating paired collection:", error);
      res.status(500).json({
        error: 'PairedCollectionError',
        message: error.message || 'Failed to create paired collection',
      });
    }
  });

  // --- Deferred Datasets (Lazy URL Fetching) ---

  // Create deferred dataset from URL (no immediate download)
  app.post("/api/datasets/deferred", async (req, res) => {
    try {
      const { url, name, file_type } = req.body;

      if (!url) {
        return res.status(400).json({ error: "URL is required" });
      }

      // Validate URL format
      try {
        const parsedUrl = new URL(url);
        if (!['http:', 'https:', 'ftp:', 's3:'].includes(parsedUrl.protocol)) {
          return res.status(400).json({
            error: "Unsupported protocol. Use HTTP, HTTPS, FTP, or S3 URLs."
          });
        }
      } catch {
        return res.status(400).json({ error: "Invalid URL format" });
      }

      // Get or create Galaxy history
      let historyId = req.session?.galaxyHistoryId as string | undefined;
      if (!historyId) {
        const sessionName = `GalaxyChat-${new Date().toISOString().split('T')[0]}`;
        historyId = await galaxyAPIProxy.createHistory(sessionName);
        if (req.session) {
          req.session.galaxyHistoryId = historyId;
        }
      }

      const dataset = await galaxyAPIProxy.createDeferredDataset(
        historyId,
        url,
        name,
        file_type
      );

      res.json({
        ...dataset,
        galaxy_history_id: historyId,
        source_url: url,
        message: `Deferred dataset created. Data will be fetched when workflow executes.`
      });
    } catch (error: any) {
      console.error("[DeferredDataset] Error creating:", error);
      res.status(500).json({
        error: 'DeferredDatasetError',
        message: error.message || 'Failed to create deferred dataset',
      });
    }
  });

  // Materialize a deferred dataset (trigger actual download)
  app.post("/api/datasets/:id/materialize", async (req, res) => {
    try {
      const { id } = req.params;

      const result = await galaxyAPIProxy.materializeDeferredDataset(id);

      res.json({
        ...result,
        message: `Dataset materialization started. State: ${result.state}`
      });
    } catch (error: any) {
      console.error("[DeferredDataset] Error materializing:", error);
      res.status(500).json({
        error: 'MaterializationError',
        message: error.message || 'Failed to materialize deferred dataset',
      });
    }
  });

  // --- Interactive Tools ---

  // Launch an interactive tool (Jupyter, RStudio, etc.)
  app.post("/api/interactive/launch", authenticateToken, async (req, res) => {
    try {
      const { tool_id, inputs } = req.body;

      if (!tool_id) {
        return res.status(400).json({ error: "tool_id is required" });
      }

      // Get Galaxy history from session
      let historyId = req.session?.galaxyHistoryId as string | undefined;
      if (!historyId) {
        const sessionName = `GalaxyChat-${new Date().toISOString().split('T')[0]}`;
        historyId = await galaxyAPIProxy.createHistory(sessionName);
        if (req.session) {
          req.session.galaxyHistoryId = historyId;
        }
      }

      const result = await galaxyAPIProxy.launchInteractiveTool(
        tool_id,
        historyId,
        inputs
      );

      res.json({
        ...result,
        message: `Interactive tool launched. ${result.entry_point_url ? 'Access URL provided.' : 'Waiting for session.'}`
      });
    } catch (error: any) {
      console.error("[Interactive] Error launching:", error);
      res.status(500).json({
        error: 'InteractiveLaunchError',
        message: error.message || 'Failed to launch interactive tool',
      });
    }
  });

  // Get active interactive sessions
  app.get("/api/interactive/sessions", authenticateToken, async (req, res) => {
    try {
      const sessions = await galaxyAPIProxy.getActiveInteractiveSessions();
      res.json({ sessions, count: sessions.length });
    } catch (error: any) {
      console.error("[Interactive] Error getting sessions:", error);
      res.status(500).json({
        error: 'SessionsError',
        message: error.message || 'Failed to get interactive sessions',
      });
    }
  });

  // --- Workflow Subworkflows ---

  // Extract subworkflow from existing workflow
  app.post("/api/workflows/:id/extract-subworkflow", authenticateToken, async (req, res) => {
    try {
      const { id } = req.params;
      const { step_ids, name } = req.body;

      if (!step_ids || !Array.isArray(step_ids) || step_ids.length === 0) {
        return res.status(400).json({ error: "step_ids[] is required and must not be empty" });
      }

      if (!name) {
        return res.status(400).json({ error: "name is required for the subworkflow" });
      }

      const subworkflow = await galaxyAPIProxy.extractSubworkflow(id, step_ids, name);

      res.json({
        ...subworkflow,
        message: `Subworkflow '${name}' extracted with ${step_ids.length} steps`
      });
    } catch (error: any) {
      console.error("[Subworkflow] Error extracting:", error);
      res.status(500).json({
        error: 'SubworkflowExtractionError',
        message: error.message || 'Failed to extract subworkflow',
      });
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

