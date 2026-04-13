/**
 * Security Configuration Module
 * Implements SOC 2 and HIPAA security controls
 */

import helmet from 'helmet';
import cors from 'cors';
import { csrfSync } from 'csrf-sync';
import type { Express, Request, Response, NextFunction } from 'express';
import rateLimit from 'express-rate-limit';

/**
 * Security configuration based on environment
 */
export interface SecurityConfig {
  env: 'development' | 'production' | 'test';
  enableHSTS: boolean;
  enableCSP: boolean;
  enableCSRF: boolean;
  corsOrigins: string[];
  forceHTTPS: boolean;
  sessionTimeout: number; // minutes
}

/**
 * Get security configuration based on environment
 */
export function getSecurityConfig(): SecurityConfig {
  const env = (process.env.NODE_ENV as any) || 'development';
  const isProd = env === 'production';

  const defaultOrigins = isProd
    ? ['https://biomate.ai']
    : ['http://localhost:5173', 'http://localhost:5000', 'http://localhost:3000', 'http://localhost:3001'];

  // Allow env vars to override prod defaults (for HTTP-terminated dev/staging servers)
  const forceHTTPS = process.env.FORCE_HTTPS === '0' ? false : isProd;
  const enableHSTS = process.env.ENABLE_HSTS === '0' ? false : isProd;

  return {
    env,
    enableHSTS,
    enableCSP: true,
    enableCSRF: isProd,
    corsOrigins: process.env.CORS_ORIGINS?.split(',') || defaultOrigins,
    forceHTTPS,
    sessionTimeout: 15, // HIPAA requirement: 15-minute inactivity timeout
  };
}

/**
 * HTTPS redirection middleware (SOC 2 CC6.6)
 */
export function forceHTTPS(req: Request, res: Response, next: NextFunction) {
  const config = getSecurityConfig();

  if (config.forceHTTPS && !req.secure && req.get('x-forwarded-proto') !== 'https') {
    return res.redirect(301, `https://${req.get('host')}${req.url}`);
  }

  next();
}

/**
 * Configure security headers (SOC 2 CC7.2)
 * Implements OWASP secure headers
 */
export function configureSecurityHeaders(app: Express) {
  const config = getSecurityConfig();
  const devConnectSrc = config.env !== 'production'
    ? [
        'wss://localhost:*',
        'ws://localhost:*',
        // Allow direct client-to-backend calls used by chat history sync in dev/test.
        'http://localhost:*',
        'https://localhost:*',
        ...(process.env.GALAXY_URL ? [process.env.GALAXY_URL] : []),
        ...(process.env.VITE_BACKEND_URL ? [process.env.VITE_BACKEND_URL] : []),
      ]
    : [
        process.env.WEBSOCKET_URL || 'wss://biomate.ai',
      ];

  app.use(
    helmet({
      // HTTP Strict Transport Security (HSTS)
      hsts: config.enableHSTS
        ? {
            maxAge: 31536000, // 1 year
            includeSubDomains: true,
            preload: true,
          }
        : false,

      // Content Security Policy (CSP)
      contentSecurityPolicy: config.enableCSP
        ? {
            directives: {
              defaultSrc: ["'self'"],
              scriptSrc: [
                "'self'",
                ...(config.env !== 'production' ? ["'unsafe-inline'", "'unsafe-eval'"] : []),
                'https://cdn.jsdelivr.net',
              ],
              styleSrc: ["'self'", "'unsafe-inline'", 'https://fonts.googleapis.com'],
              fontSrc: ["'self'", 'https://fonts.gstatic.com'],
              imgSrc: ["'self'", 'data:', 'https:', 'blob:'],
              connectSrc: [
                "'self'",
                'https://api.anthropic.com',
                'https://api.openai.com',
                ...devConnectSrc,
              ],
              frameSrc: ["'none'"],
              objectSrc: ["'none'"],
              // Only upgrade insecure requests when HTTPS is actually available
              upgradeInsecureRequests: (config.env === 'production' && config.forceHTTPS) ? [] : null,
            },
          }
        : false,

      // Prevent clickjacking
      frameguard: {
        action: 'deny',
      },

      // Prevent MIME-sniffing
      noSniff: true,

      // XSS Protection (legacy)
      xssFilter: true,

      // Referrer Policy
      referrerPolicy: {
        policy: 'strict-origin-when-cross-origin',
      },

      // Disable X-Powered-By header
      hidePoweredBy: true,

      // DNS Prefetch Control
      dnsPrefetchControl: {
        allow: false,
      },

      // IE No Open
      ieNoOpen: true,

      // Permissions Policy (Feature Policy)
      permittedCrossDomainPolicies: {
        permittedPolicies: 'none',
      },
    })
  );

  console.log('[Security] Security headers configured');
}

/**
 * Configure CORS (SOC 2 CC7.2)
 */
export function configureCORS(app: Express) {
  const config = getSecurityConfig();

  const corsOptions: cors.CorsOptions = {
    origin: (origin, callback) => {
      // Allow requests with no origin (mobile apps, Postman, etc.)
      if (!origin) {
        return callback(null, true);
      }

      if (config.corsOrigins.includes(origin)) {
        callback(null, true);
      } else {
        console.warn(`[Security] CORS blocked origin: ${origin}`);
        callback(new Error('Not allowed by CORS'));
      }
    },
    credentials: true, // Allow cookies
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: [
      'Content-Type',
      'Authorization',
      'X-Requested-With',
      'X-CSRF-Token',
    ],
    exposedHeaders: ['X-CSRF-Token'],
    maxAge: 600, // 10 minutes
  };

  app.use(cors(corsOptions));
  console.log(`[Security] CORS configured for origins: ${config.corsOrigins.join(', ')}`);
}

/**
 * Configure CSRF protection (SOC 2 CC7.2)
 * Protects against Cross-Site Request Forgery attacks
 */
export function configureCSRF(app: Express) {
  const config = getSecurityConfig();

  if (!config.enableCSRF) {
    console.log('[Security] CSRF protection disabled (development mode)');
    return null;
  }

  const { generateToken, csrfSynchronisedProtection } = csrfSync({
    getTokenFromRequest: (req) => {
      // Get token from header or body
      return req.headers['x-csrf-token'] as string || req.body._csrf;
    },
    getTokenFromState: (req) => {
      // Get token from session
      return (req.session as any)?.csrfToken;
    },
    storeTokenInState: (req, token) => {
      // Store token in session
      if (req.session) {
        (req.session as any).csrfToken = token;
      }
    },
    size: 64, // Token size
    ignoredMethods: ['GET', 'HEAD', 'OPTIONS'],
  });

  // Provide CSRF token endpoint
  app.get('/api/csrf-token', (req, res) => {
    const token = generateToken(req);
    res.json({ csrfToken: token });
  });

  console.log('[Security] CSRF protection enabled');
  return csrfSynchronisedProtection;
}

// E2E test bypass — same pattern as rate-limit.ts; only active when env var is set.
const _GLOBAL_E2E_TOKEN = process.env.E2E_TEST_TOKEN;
function _isGlobalE2EBypass(req: Request): boolean {
  if (!_GLOBAL_E2E_TOKEN) return false;
  return req.headers['x-e2e-test-token'] === _GLOBAL_E2E_TOKEN;
}

/**
 * Global rate limiter for all API endpoints (SOC 2 CC7.3)
 */
export const globalRateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 1000, // Limit each IP to 1000 requests per window
  message: 'Too many requests from this IP, please try again later',
  standardHeaders: true,
  legacyHeaders: false,
  skip: _isGlobalE2EBypass,
  // Store in Redis for distributed rate limiting (optional)
  // store: new RedisStore({ client: redisClient }),
});

/**
 * Security event types for audit logging
 */
export enum SecurityEventType {
  // Authentication events
  LOGIN_SUCCESS = 'auth.login.success',
  LOGIN_FAILURE = 'auth.login.failure',
  LOGOUT = 'auth.logout',
  PASSWORD_RESET_REQUEST = 'auth.password_reset.request',
  PASSWORD_RESET_SUCCESS = 'auth.password_reset.success',
  MFA_ENABLED = 'auth.mfa.enabled',
  MFA_DISABLED = 'auth.mfa.disabled',

  // Authorization events
  PERMISSION_DENIED = 'authz.permission.denied',
  ROLE_CHANGED = 'authz.role.changed',

  // Data access events (HIPAA)
  PHI_ACCESS = 'data.phi.access',
  PHI_EXPORT = 'data.phi.export',
  PHI_DELETE = 'data.phi.delete',
  PHI_MODIFY = 'data.phi.modify',

  // Security events
  SUSPICIOUS_ACTIVITY = 'security.suspicious',
  RATE_LIMIT_EXCEEDED = 'security.rate_limit',
  INVALID_TOKEN = 'security.token.invalid',
  SESSION_EXPIRED = 'security.session.expired',

  // Administrative events
  ADMIN_ACTION = 'admin.action',
  CONFIG_CHANGE = 'admin.config.change',
  USER_CREATED = 'admin.user.created',
  USER_DELETED = 'admin.user.deleted',
}

/**
 * Audit log entry structure (SOC 2 CC6.7, HIPAA §164.312(b))
 */
export interface AuditLogEntry {
  timestamp: Date;
  eventType: SecurityEventType;
  userId?: string;
  userEmail?: string;
  ipAddress: string;
  userAgent: string;
  resource?: string;
  action?: string;
  outcome: 'success' | 'failure';
  details?: Record<string, any>;
  phiAccessed?: boolean;
}

/**
 * Audit logger (HIPAA §164.312(b))
 * Logs must be retained for 6 years minimum
 */
export class AuditLogger {
  private static instance: AuditLogger;

  private constructor() {}

  static getInstance(): AuditLogger {
    if (!AuditLogger.instance) {
      AuditLogger.instance = new AuditLogger();
    }
    return AuditLogger.instance;
  }

  /**
   * Log security event
   */
  log(entry: AuditLogEntry): void {
    const logEntry = {
      ...entry,
      timestamp: entry.timestamp.toISOString(),
      _compliance: {
        soc2: true,
        hipaa: entry.phiAccessed || false,
      },
    };

    // In production, send to centralized logging (Splunk, ELK, etc.)
    // For now, log to console and file
    console.log('[AUDIT]', JSON.stringify(logEntry));

    // TODO: Implement persistent storage with 6-year retention
    // - Store in append-only log file
    // - Or send to SIEM (Splunk, Sumo Logic, etc.)
    // - Ensure logs are tamper-proof and encrypted
  }

  /**
   * Log from Express request
   */
  logFromRequest(
    req: Request,
    eventType: SecurityEventType,
    outcome: 'success' | 'failure',
    details?: Record<string, any>
  ): void {
    this.log({
      timestamp: new Date(),
      eventType,
      userId: (req as any).user?.id,
      userEmail: (req as any).user?.email,
      ipAddress: req.ip || req.socket.remoteAddress || 'unknown',
      userAgent: req.get('user-agent') || 'unknown',
      resource: req.path,
      action: req.method,
      outcome,
      details,
    });
  }
}

/**
 * Audit logging middleware
 */
export function auditLogMiddleware(req: Request, res: Response, next: NextFunction) {
  const auditLogger = AuditLogger.getInstance();
  const startTime = Date.now();

  // Log request
  res.on('finish', () => {
    const duration = Date.now() - startTime;
    const outcome = res.statusCode < 400 ? 'success' : 'failure';

    // Only log sensitive endpoints
    if (
      req.path.startsWith('/api/auth') ||
      req.path.startsWith('/api/workflows') ||
      req.path.includes('phi') // Any endpoint dealing with PHI
    ) {
      auditLogger.logFromRequest(req, SecurityEventType.PHI_ACCESS, outcome, {
        statusCode: res.statusCode,
        duration,
      });
    }
  });

  next();
}

/**
 * Session timeout middleware (HIPAA §164.312(a)(2)(iii))
 * Automatically log out users after 15 minutes of inactivity
 */
export function sessionTimeoutMiddleware(req: Request, res: Response, next: NextFunction) {
  const config = getSecurityConfig();

  if (req.session && req.session.lastActivity) {
    const now = Date.now();
    const lastActivity = new Date(req.session.lastActivity).getTime();
    const timeout = config.sessionTimeout * 60 * 1000; // Convert to milliseconds

    if (now - lastActivity > timeout) {
      // Session expired
      req.session.destroy((err) => {
        if (err) {
          console.error('[Security] Error destroying session:', err);
        }
      });

      return res.status(401).json({
        error: 'SESSION_EXPIRED',
        message: 'Your session has expired due to inactivity. Please log in again.',
      });
    }
  }

  // Update last activity timestamp
  if (req.session) {
    req.session.lastActivity = new Date().toISOString();
  }

  next();
}

/**
 * Sanitize log data to prevent PHI leakage
 */
export function sanitizeLogData(data: any): any {
  const sensitiveFields = [
    'password',
    'token',
    'secret',
    'apiKey',
    'ssn',
    'dob',
    'birthdate',
    'medicalRecord',
    'diagnosis',
    'treatment',
  ];

  if (typeof data === 'object' && data !== null) {
    const sanitized = { ...data };
    for (const key of Object.keys(sanitized)) {
      const lowerKey = key.toLowerCase();
      if (sensitiveFields.some((field) => lowerKey.includes(field.toLowerCase()))) {
        sanitized[key] = '[REDACTED]';
      } else if (typeof sanitized[key] === 'object') {
        sanitized[key] = sanitizeLogData(sanitized[key]);
      }
    }
    return sanitized;
  }

  return data;
}

/**
 * Initialize all security middleware
 */
export function initializeSecurity(app: Express) {
  const config = getSecurityConfig();

  console.log(`[Security] Initializing security for ${config.env} environment`);

  // 1. Force HTTPS in production
  if (config.forceHTTPS) {
    app.use(forceHTTPS);
  }

  // 2. Global rate limiting
  app.use('/api', globalRateLimiter);

  // 3. Security headers (Helmet)
  configureSecurityHeaders(app);

  // 4. CORS
  configureCORS(app);

  // 5. Audit logging
  app.use(auditLogMiddleware);

  // 6. Session timeout
  app.use(sessionTimeoutMiddleware);

  console.log('[Security] Security initialization complete');

  return {
    config,
    csrfProtection: configureCSRF(app),
  };
}
