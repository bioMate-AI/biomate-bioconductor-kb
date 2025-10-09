# Critical Fixes Required - Action Plan

**Priority:** 🔴 **URGENT**
**Status:** Blocking production deployment
**Estimated Time to Fix:** 8-12 hours

---

## Overview

27 issues identified across 4 categories:
- **8 Critical** - App broken/security holes
- **10 Major** - Required for production
- **9 Minor** - Improvements

---

## 🔴 CRITICAL - Fix Immediately (Blocking)

### 1. Session Middleware Missing (App Broken)

**Files Affected:**
- `/private/tmp/GalaxyChat_version2/server/index.ts`
- `/private/tmp/GalaxyChat_version2/server/routes.ts`

**Current State:**
```typescript
// routes.ts uses session but middleware not configured
req.session.galaxyHistoryId = historyId;  // ❌ UNDEFINED!
```

**Fix:**
```typescript
// server/index.ts - Add after app.use(express.json())
import session from 'express-session';
import connectRedis from 'connect-redis';
import { createClient } from 'redis';

const redisClient = createClient({
  url: process.env.REDIS_URL || 'redis://localhost:6379'
});

redisClient.connect().catch(console.error);

app.use(session({
  store: new (connectRedis(session))({ client: redisClient }),
  secret: process.env.SESSION_SECRET || 'dev-secret-change-in-production',
  resave: false,
  saveUninitialized: false,
  cookie: {
    secure: process.env.NODE_ENV === 'production',
    httpOnly: true,
    maxAge: 24 * 60 * 60 * 1000, // 24 hours
    sameSite: 'strict'
  }
}));

// Add types
declare module 'express-session' {
  interface SessionData {
    galaxyHistoryId?: string;
    uploadedDatasets?: Array<{
      dataset_id: string;
      galaxy_dataset_id?: string;
      name: string;
      description?: string;
      file_type: string;
      file_size: number;
    }>;
    workflowJobs?: Record<string, {
      job_id: string;
      tool_id: string;
      state: string;
      started_at: string;
    }>;
  }
}
```

**Dependencies:**
```bash
npm install express-session connect-redis redis
npm install -D @types/express-session
```

---

### 2. Memory Leak - Polling Not Cleaned Up

**File:** `/private/tmp/GalaxyChat_version2/client/src/components/enhanced-workflow-builder.tsx:359-389`

**Current Code:**
```typescript
const pollInterval = setInterval(async () => {
  try {
    const statusResponse = await fetch(`/api/workflow/step/${stepId}/status`)
    // ...
  } catch (err) {
    console.error('[Step] Status check failed:', err)
    // ❌ NO CLEANUP - keeps polling forever!
  }
}, 2000)
```

**Fix:**
```typescript
// Add to component state
const [activePolls, setActivePolls] = useState<Map<string, NodeJS.Timeout>>(new Map());

const handleStepAction = async (stepId: string, action: 'run' | ...) => {
  // ... existing code ...

  case 'run':
    // Clear any existing poll for this step
    const existingPoll = activePolls.get(stepId);
    if (existingPoll) {
      clearInterval(existingPoll);
      clearTimeout(existingPoll);
    }

    const step = steps.find(s => s.id === stepId)
    if (!step) return;

    try {
      const response = await fetch('/api/workflow/step/execute', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          step_id: stepId,
          tool_id: step.tool,
          parameters: step.parameters || {},
          inputs: {}
        })
      })

      if (!response.ok) {
        throw new Error(`Step execution failed: ${await response.text()}`)
      }

      const result = await response.json()
      console.log(`[Step] Execution started:`, result)

      let pollCount = 0;
      const maxPolls = 150; // 5 minutes at 2s intervals

      // Poll for status with cleanup
      const pollInterval = setInterval(async () => {
        pollCount++;

        // Auto-stop after max polls
        if (pollCount >= maxPolls) {
          clearInterval(pollInterval);
          activePolls.delete(stepId);
          console.warn(`[Step] Polling timeout for ${stepId}`);
          return;
        }

        try {
          const statusResponse = await fetch(`/api/workflow/step/${stepId}/status`)
          if (statusResponse.ok) {
            const status = await statusResponse.json()

            if (status.state === 'ok') {
              clearInterval(pollInterval)
              activePolls.delete(stepId);
              setSteps(prev => prev.map(s =>
                s.id === stepId ? { ...s, status: 'completed' as const } : s
              ))
            } else if (status.state === 'error') {
              clearInterval(pollInterval)
              activePolls.delete(stepId);
              setSteps(prev => prev.map(s =>
                s.id === stepId ? { ...s, status: 'error' as const } : s
              ))
            }
          }
        } catch (err) {
          console.error('[Step] Status check failed:', err)
          clearInterval(pollInterval) // ✅ CLEANUP ON ERROR
          activePolls.delete(stepId);
          setSteps(prev => prev.map(s =>
            s.id === stepId ? { ...s, status: 'error' as const } : s
          ))
        }
      }, 2000)

      // Track interval for cleanup
      setActivePolls(prev => new Map(prev).set(stepId, pollInterval));

    } catch (error: any) {
      console.error('[Step] Execution failed:', error)
      setSteps(prev => prev.map(s =>
        s.id === stepId ? { ...s, status: 'error' as const } : s
      ))
    }
    break
}

// Add cleanup on unmount
useEffect(() => {
  return () => {
    // Clear all active polls on unmount
    activePolls.forEach(interval => {
      clearInterval(interval);
    });
  };
}, []);
```

---

### 3. Environment Variable Validation

**Files:** All files using `process.env`

**Current Code:**
```typescript
const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY, // ❌ Could be undefined!
});
```

**Fix:**
```typescript
// server/config/env.ts
export class ConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ConfigError';
  }
}

export function getRequiredEnv(key: string): string {
  const value = process.env[key];
  if (!value) {
    throw new ConfigError(
      `Missing required environment variable: ${key}\n` +
      `Please set ${key} in your .env file or environment.`
    );
  }
  return value;
}

export function getOptionalEnv(key: string, defaultValue: string): string {
  return process.env[key] || defaultValue;
}

// Validate all required env vars on startup
export function validateEnvironment() {
  const required = [
    'OPENAI_API_KEY',
    'SESSION_SECRET',
  ];

  const missing = required.filter(key => !process.env[key]);

  if (missing.length > 0) {
    throw new ConfigError(
      `Missing required environment variables:\n${missing.join('\n')}\n\n` +
      `Please create a .env file with these variables.`
    );
  }

  console.log('✓ Environment validation passed');
}

// server/index.ts - Call before starting server
import { validateEnvironment } from './config/env';

(async () => {
  try {
    validateEnvironment(); // ✅ Validate first

    const server = await registerRoutes(app);
    // ... rest of startup
  } catch (error) {
    console.error('Failed to start server:', error);
    process.exit(1);
  }
})();

// Usage in other files:
import { getRequiredEnv } from './config/env';

const openai = new OpenAI({
  apiKey: getRequiredEnv('OPENAI_API_KEY'),
});
```

**Create .env.example:**
```bash
# OpenAI API Key (required)
OPENAI_API_KEY=sk-your-api-key-here

# Session Secret (required for production)
SESSION_SECRET=change-this-to-a-random-string

# Redis URL (optional, defaults to localhost)
REDIS_URL=redis://localhost:6379

# Galaxy API Configuration (optional)
GALAXY_URL=http://localhost:8080
GALAXY_API_KEY=your-galaxy-api-key

# Server Configuration
PORT=5000
NODE_ENV=development
```

---

### 4. Input Validation Missing

**File:** `/private/tmp/GalaxyChat_version2/server/routes.ts`

**Fix:**
```typescript
import { z } from 'zod';

// Define schemas
const executeStepSchema = z.object({
  step_id: z.string().min(1).max(100),
  tool_id: z.string().min(1).max(200),
  parameters: z.record(z.unknown()).optional().default({}),
  inputs: z.record(z.unknown()).optional().default({})
});

const datasetValidationSchema = z.object({
  workflow_name: z.string().min(1).max(200),
  workflow_steps: z.array(z.object({
    id: z.string(),
    title: z.string(),
    description: z.string(),
    tool: z.string(),
    parameters: z.record(z.unknown()).optional()
  })).min(1)
});

const chatMessageSchema = z.object({
  message: z.string().min(1).max(10000),
  context: z.record(z.unknown()).optional().default({})
});

// Validation middleware
const validateRequest = (schema: z.ZodSchema) => {
  return (req: Request, res: Response, next: NextFunction) => {
    try {
      req.body = schema.parse(req.body);
      next();
    } catch (error) {
      if (error instanceof z.ZodError) {
        return res.status(400).json({
          error: 'VALIDATION_ERROR',
          message: 'Invalid request data',
          details: error.errors
        });
      }
      next(error);
    }
  };
};

// Apply to routes
app.post("/api/workflow/step/execute",
  validateRequest(executeStepSchema),
  async (req, res) => {
    const { step_id, tool_id, parameters, inputs } = req.body;
    // Now safe to use - validated
    // ...
  }
);

app.post("/api/datasets/validate",
  validateRequest(datasetValidationSchema),
  async (req, res) => {
    const { workflow_name, workflow_steps } = req.body;
    // ...
  }
);

app.post("/api/chat",
  validateRequest(chatMessageSchema),
  async (req, res) => {
    const { message, context } = req.body;
    // ...
  }
);
```

---

## 🟡 MAJOR - Required for Production

### 5. Add Rate Limiting

**File:** `/private/tmp/GalaxyChat_version2/server/index.ts`

**Fix:**
```typescript
import rateLimit from 'express-rate-limit';

// General API rate limit
const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100,
  message: 'Too many requests, please try again later.',
  standardHeaders: true,
  legacyHeaders: false,
});

// LLM endpoints (more restrictive)
const llmLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 10,
  message: 'AI service rate limit exceeded.',
});

// File upload (very restrictive)
const uploadLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 20,
  message: 'Upload limit exceeded.',
});

app.use('/api/', apiLimiter);

// Apply to specific routes in routes.ts
app.post('/api/chat', llmLimiter, ...);
app.post('/api/datasets/validate', llmLimiter, ...);
app.post('/api/datasets/upload', uploadLimiter, ...);
```

**Dependencies:**
```bash
npm install express-rate-limit
```

---

### 6. CORS Configuration

**File:** `/private/tmp/GalaxyChat_version2/server/index.ts`

**Fix:**
```typescript
import cors from 'cors';

const allowedOrigins = process.env.ALLOWED_ORIGINS?.split(',') || [
  'http://localhost:5173',
  'http://localhost:5000'
];

app.use(cors({
  origin: (origin, callback) => {
    // Allow requests with no origin (like mobile apps or curl)
    if (!origin) return callback(null, true);

    if (allowedOrigins.includes(origin)) {
      callback(null, true);
    } else {
      callback(new Error('Not allowed by CORS'));
    }
  },
  credentials: true,
  optionsSuccessStatus: 200
}));
```

---

### 7. File Upload Security

**File:** `/private/tmp/GalaxyChat_version2/server/routes.ts:40-56`

**Fix:**
```typescript
import path from 'path';
import { v4 as uuidv4 } from 'uuid';

const ALLOWED_EXTENSIONS = [
  '.fastq', '.fq', '.fastq.gz', '.fq.gz',
  '.bam', '.sam', '.cram',
  '.vcf', '.vcf.gz', '.bcf',
  '.csv', '.tsv', '.txt',
  '.mzml', '.mzxml', '.raw'
];

const ALLOWED_MIME_TYPES = [
  'application/gzip',
  'application/x-gzip',
  'text/plain',
  'text/csv',
  'application/octet-stream',
  'application/x-compressed'
];

const upload = multer({
  storage: multer.diskStorage({
    destination: async (req, file, cb) => {
      await fs.mkdir(uploadDir, { recursive: true });
      cb(null, uploadDir);
    },
    filename: (req, file, cb) => {
      // Sanitize filename - remove path traversal
      const safeName = path.basename(file.originalname)
        .replace(/[^a-zA-Z0-9._-]/g, '_')
        .slice(0, 200); // Limit length

      const ext = path.extname(safeName).toLowerCase();

      // Validate extension
      const isAllowed = ALLOWED_EXTENSIONS.some(allowed =>
        safeName.endsWith(allowed)
      );

      if (!isAllowed) {
        return cb(new Error(`Invalid file extension: ${ext}`), '');
      }

      // Generate safe filename
      const timestamp = Date.now();
      const uniqueName = `${timestamp}_${uuidv4()}${ext}`;
      cb(null, uniqueName);
    },
  }),
  fileFilter: (req, file, cb) => {
    if (!ALLOWED_MIME_TYPES.includes(file.mimetype)) {
      return cb(new Error(`Invalid file type: ${file.mimetype}`));
    }
    cb(null, true);
  },
  limits: {
    fileSize: 500 * 1024 * 1024, // 500MB
    files: 1,
    fieldSize: 1024 * 1024, // 1MB for text fields
  },
});

// Enhanced error handling for multer
app.post("/api/datasets/upload", (req, res, next) => {
  upload.single('file')(req, res, (err) => {
    if (err instanceof multer.MulterError) {
      if (err.code === 'LIMIT_FILE_SIZE') {
        return res.status(400).json({
          error: 'FILE_TOO_LARGE',
          message: 'File size exceeds 500MB limit'
        });
      }
      return res.status(400).json({
        error: 'UPLOAD_ERROR',
        message: err.message
      });
    } else if (err) {
      return res.status(400).json({
        error: 'UPLOAD_ERROR',
        message: err.message
      });
    }
    next();
  });
}, async (req, res) => {
  // ... existing upload logic
});
```

---

### 8. Error Handler Middleware

**File:** `/private/tmp/GalaxyChat_version2/server/index.ts`

**Fix:**
```typescript
// server/middleware/error-handler.ts
export class AppError extends Error {
  constructor(
    public statusCode: number,
    public code: string,
    message: string,
    public details?: any
  ) {
    super(message);
    this.name = 'AppError';
    Error.captureStackTrace(this, this.constructor);
  }
}

export const errorHandler = (
  err: Error,
  req: Request,
  res: Response,
  next: NextFunction
) => {
  // Log error
  console.error('Error:', {
    message: err.message,
    stack: err.stack,
    path: req.path,
    method: req.method
  });

  if (err instanceof AppError) {
    return res.status(err.statusCode).json({
      error: err.code,
      message: err.message,
      details: err.details,
      timestamp: new Date().toISOString(),
      path: req.path
    });
  }

  // Zod validation errors
  if (err.name === 'ZodError') {
    return res.status(400).json({
      error: 'VALIDATION_ERROR',
      message: 'Invalid request data',
      details: (err as any).errors
    });
  }

  // Default error
  res.status(500).json({
    error: 'INTERNAL_SERVER_ERROR',
    message: process.env.NODE_ENV === 'production'
      ? 'An unexpected error occurred'
      : err.message
  });
};

// server/index.ts - Apply LAST
app.use(errorHandler);
```

---

## Installation Commands

```bash
# Critical dependencies
npm install express-session connect-redis redis
npm install express-rate-limit cors
npm install zod

# Dev dependencies
npm install -D @types/express-session @types/cors
```

---

## Environment Setup

**Create `.env` file:**
```bash
cp .env.example .env
# Edit .env with your actual values
```

**Required variables:**
```
OPENAI_API_KEY=sk-your-key-here
SESSION_SECRET=generate-random-string-here
REDIS_URL=redis://localhost:6379
```

---

## Testing Checklist

After fixes:

- [ ] App starts without errors
- [ ] Session persists across requests
- [ ] File upload works with valid files
- [ ] File upload rejects invalid extensions
- [ ] LLM validation works
- [ ] Step execution polling cleans up
- [ ] Rate limiting triggers after limit
- [ ] Missing env vars show clear error

---

## Timeline

1. **Hour 1-2:** Session middleware + env validation
2. **Hour 3-4:** Input validation + error handling
3. **Hour 5-6:** Memory leak fix + polling cleanup
4. **Hour 7-8:** Rate limiting + CORS + file security
5. **Hour 9-10:** Testing + documentation
6. **Hour 11-12:** Buffer for issues

---

**Total Estimated Time:** 8-12 hours
**Priority Order:** 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8

Start with #1 (Session) as it blocks everything else.
