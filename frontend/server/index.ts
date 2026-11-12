import "dotenv/config";
import express, { type Request, Response, NextFunction } from "express";
import session from "express-session";
import cookieParser from "cookie-parser";
import passport from "passport";
import { registerRoutes } from "./routes";
import { llmRegionMiddleware } from "./llm-region-policy";
import { installGalaxyFetchPolicy, stripInboundLlmPolicyHeader } from "./galaxy-llm-policy-header";
import { applyPendingMigrations } from "./migrate";
import { setupVite, serveStatic, log } from "./vite";
import { oauthService } from "./oauth-service";
import { createSessionStore } from "./redis-session";
import { initializeSecurity } from "./security-config";

// Crash diagnostics — log fatal errors before exit
process.on('uncaughtException', (err) => {
  console.error('[FATAL] Uncaught exception:', err);
  process.exit(1);
});
process.on('unhandledRejection', (reason) => {
  console.error('[FATAL] Unhandled rejection:', reason);
  process.exit(1);
});

// Validate required secrets at module load time (synchronous, crashes immediately in prod)
if (process.env.NODE_ENV === 'production') {
  const required = ['JWT_SECRET', 'SESSION_SECRET', 'BILLING_INTERNAL_KEY'];
  const missing = required.filter((k) => !process.env[k]);
  if (missing.length > 0) {
    console.error(`[FATAL] Missing required environment variables: ${missing.join(', ')}`);
    process.exit(1);
  }
}

const app = express();

// Chinese-LLM region policy → Galaxy: every fetch() to Galaxy carries the request's
// X-BioMate-LLM-Policy header, and no browser-sent copy of that header is ever relayed
// (galaxy-llm-policy-header.ts).
installGalaxyFetchPolicy();
app.use(stripInboundLlmPolicyHeader);

// Initialize security FIRST (before any other middleware)
const security = initializeSecurity(app);

// Trust the first proxy hop so req.ip is the real client IP (not the nginx/LB IP).
// Without this, all users share one rate-limit bucket (the proxy IP).
app.set('trust proxy', 1);

// The /mcp, /oauth/*, and /.well-known/oauth* routes are RAW-STREAM proxied to
// the remote_mcp service (see routes.ts mcpProxy). A global body parser here
// would consume the POST body before the proxy can pipe it upstream — remote_mcp
// then hangs waiting for a body that never arrives (observed as a 000/timeout on
// POST /mcp initialize, while GET well-known worked). Skip parsing for those
// paths so the untouched request stream reaches the proxy.
const _isMcpProxyPath = (p: string) =>
  p === '/mcp' || p.startsWith('/mcp/') ||
  p.startsWith('/oauth/') || p.startsWith('/.well-known/oauth');
// The Stripe webhook route (routes.ts) uses express.raw() and verifies the signature
// over the ORIGINAL raw body. A global express.json() here would parse it into an
// object first, making constructEvent throw "payload must be a string or Buffer" ->
// every webhook 400s (signature verification impossible). Skip parsing for it so the
// route's own raw parser receives the untouched bytes.
// The /interactive/<token>/* routes are RAW-STREAM proxied to the interactive-tool
// container (routes.ts /interactive proxy). Same failure mode as MCP above: a global
// body parser drains the POST stream, so req.pipe() forwards an empty body and Jupyter
// hangs (observed as 000/timeout on POST /api/kernels — starting a kernel — while every
// GET worked). Skip parsing so the untouched stream reaches the proxy.
const _needsRawBody = (req: Request) =>
  _isMcpProxyPath(req.path) || req.path === '/api/payments/webhook' ||
  req.path.startsWith('/interactive/') ||
  // On-prem MinIO multipart upload proxy: browser PUTs raw binary chunks here.
  req.path === '/api/s3/upload/part';
const _jsonParser = express.json();
const _urlencodedParser = express.urlencoded({ extended: false });
app.use((req, res, next) => (_needsRawBody(req) ? next() : _jsonParser(req, res, next)));
app.use((req, res, next) => (_needsRawBody(req) ? next() : _urlencodedParser(req, res, next)));
app.use(cookieParser());

// Session middleware configuration (will be initialized async)
async function initializeSession() {
  const store = await createSessionStore();

  const sessionSecret = process.env.SESSION_SECRET || 'dev-only-insecure-session-secret';
  if (!process.env.SESSION_SECRET) {
    console.warn('[session] WARNING: SESSION_SECRET not set — using insecure default for development only');
  }

  app.use(session({
    secret: sessionSecret,
    resave: false,
    saveUninitialized: false,
    store,
    cookie: {
      maxAge: 24 * 60 * 60 * 1000, // 24 hours
      httpOnly: true,
      secure: process.env.NODE_ENV === 'production',
      sameSite: 'lax'
    }
  }));

  // Initialize OAuth/Passport
  oauthService.initialize();
  app.use(passport.initialize());
  app.use(passport.session());
}

app.use((req, res, next) => {
  const start = Date.now();
  const path = req.path;
  let capturedJsonResponse: Record<string, any> | undefined = undefined;

  const originalResJson = res.json;
  res.json = function (bodyJson, ...args) {
    capturedJsonResponse = bodyJson;
    return originalResJson.apply(res, [bodyJson, ...args]);
  };

  res.on("finish", () => {
    const duration = Date.now() - start;
    if (path.startsWith("/api")) {
      let logLine = `${req.method} ${path} ${res.statusCode} in ${duration}ms`;
      if (capturedJsonResponse && !path.startsWith("/api/voice/")) {
        logLine += ` :: ${JSON.stringify(capturedJsonResponse)}`;
      }

      if (logLine.length > 80) {
        logLine = logLine.slice(0, 79) + "…";
      }

      log(logLine);
    }
  });

  next();
});

(async () => {
  // Apply any pending DB migrations BEFORE routes register, so handlers
  // never query missing tables. See server/migrate.ts. A failure here is
  // fatal — a half-applied schema is worse than a refused start.
  try {
    await applyPendingMigrations();
  } catch (err) {
    console.error("[FATAL] Migration runner failed:", err);
    process.exit(1);
  }

  // Initialize session store (Redis or Memory fallback)
  await initializeSession();

  // Chinese-LLM region policy: every request runs inside its region decision, so any LLM call made
  // while serving it (notes, evidence, findings… not only chat) obeys it. After body/session/auth
  // parsing (llm-region-policy.ts).
  app.use(llmRegionMiddleware);

  const server = await registerRoutes(app);

  app.use((err: any, _req: Request, res: Response, _next: NextFunction) => {
    const status = err.status || err.statusCode || 500;
    const message = err.message || "Internal Server Error";

    console.error("[ExpressError]", err);
    res.status(status).json({ message });
  });

  // importantly only setup vite in development and after
  // setting up all the other routes so the catch-all route
  // doesn't interfere with the other routes
  if (app.get("env") === "development") {
    await setupVite(app, server);
  } else {
    serveStatic(app);
  }

  // ALWAYS serve the app on the port specified in the environment variable PORT
  // Other ports are firewalled. Default to 5000 if not specified.
  // this serves both the API and the client.
  // It is the only port that is not firewalled.
  const port = parseInt(process.env.PORT || '5000', 10);
  server.listen(port, process.env.HOST || "0.0.0.0", () => {
    log(`serving on port ${port}`);
  });
})();
