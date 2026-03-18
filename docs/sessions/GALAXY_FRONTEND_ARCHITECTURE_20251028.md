# Galaxy Frontend Architecture & Capabilities Analysis

**Repository:** /home/yzhang/biomate/frontend
**Analysis Date:** October 28, 2025
**Current Branch:** frontend_backend_connection

---

## 1. MAIN FRONTEND DIRECTORY STRUCTURE

### Root-Level Organization
```
/home/yzhang/biomate/frontend/
├── client/                    # React frontend (Vite + TypeScript)
├── server/                    # Express backend server
├── shared/                    # Shared types and schemas
├── data/                      # Data storage (uploads, datasets)
├── package.json              # Dependencies and build scripts
├── vite.config.ts            # Vite build configuration
├── tailwind.config.js        # Tailwind CSS configuration
└── Dockerfile                # Production Docker image (Node 18 Alpine)
```

### Client Structure
```
client/src/
├── components/              # 81 React components
│   ├── ui/                 # 30+ UI components (Radix UI wrappers)
│   ├── chat-*              # Chat interface components
│   ├── workflow-*          # Workflow builder/visualization
│   ├── parameter-*         # Parameter configuration dialogs
│   ├── dataset-*           # Dataset management components
│   ├── job-log-viewer.tsx  # Job execution logs
│   └── execution-timeline.tsx
├── pages/                  # Route-based pages
│   ├── auth/              # Login/Register/Password reset
│   ├── landing.tsx        # Marketing homepage
│   ├── pricing.tsx
│   ├── blog.tsx, blog-post.tsx
│   ├── dashboard.tsx      # User dashboard
│   ├── projects.tsx       # Project management
│   ├── project-detail.tsx
│   └── checkout.tsx
├── hooks/                 # Custom React hooks
│   ├── useWorkflowExecution.ts    # SSE-based execution tracking
│   ├── useWorkflowSync.ts         # Bidirectional workflow sync
│   ├── useDebounce.ts
│   └── use-toast.ts
├── contexts/              # React context providers
│   └── auth-context.tsx   # Authentication context
├── lib/                   # Utility libraries
│   ├── api.ts             # API client methods
│   ├── chat-history.ts    # LocalStorage chat persistence
│   ├── workflow-adapter.ts # Format conversion (demo→Galaxy→standard)
│   ├── projects.ts        # Project management utilities
│   ├── starred-workflows.ts
│   ├── recent-tools.ts
│   ├── user-settings.ts
│   └── queryClient.ts     # TanStack React Query setup
├── App.tsx                # Main app component with routing
├── main.tsx               # Entry point
└── index.css              # Global styles + Tailwind

server/
├── index.ts               # Express server setup
├── routes.ts              # REST API endpoints (3,500+ lines)
├── galaxy-api-proxy.ts    # Axios-based Galaxy API client
├── galaxy-assistant.ts    # Claude Sonnet 4.5 integration
├── galaxy-state-poller.ts # Real-time status polling
├── workflow-sse.ts        # Server-Sent Events manager
├── dataset-validator.ts   # AI-powered dataset validation
├── parameter-repository.ts # Parameter template storage
├── workflow-repository.ts # Workflow template storage
├── mock-galaxy-api.ts     # Fallback mock implementation
└── types/                 # TypeScript type definitions

shared/
├── galaxy-types.ts        # Galaxy API types
└── schema.ts              # Zod schemas for chat/workflows/datasets
```

---

## 2. KEY UI COMPONENTS AND FRAMEWORKS

### Frontend Framework Stack
```
Framework          Version      Purpose
─────────────────────────────────────────────────
React              18.3.1       UI library
TypeScript         5.6.3        Type safety
Vite               5.4.19       Build tool
Tailwind CSS       3.4.17       Styling
```

### UI Component Libraries
```
@radix-ui/*        25+ components    Accessible component primitives
lucide-react       0.453.0           Icon library
recharts           2.15.2            Data visualization/charts
framer-motion      11.13.1           Animations
embla-carousel     8.6.0             Carousel/slider
react-hook-form    7.55.0            Form handling
react-resizable-panels                Panel resizing
```

### Major UI Components (81 total)

**Core Chat & Interaction:**
- `chat-interface.tsx` - Main chat messaging interface with Galaxy integration
- `chat-with-artifacts.tsx` - Chat with embedded workflow builder
- `chat-message.tsx` - Message rendering with markdown/code
- `chat-input.tsx` - Input bar with file upload
- `chat-loading.tsx` - Loading states
- `typing-indicator.tsx` - Real-time typing indicator

**Workflow Management:**
- `workflow-builder.tsx` - Basic workflow editor
- `enhanced-workflow-builder.tsx` - Advanced builder with execution timeline
- `workflow-graph.tsx` - DAG visualization
- `workflow-step.tsx` - Individual step UI
- `execution-timeline.tsx` - Real-time execution progress
- `save-workflow-dialog.tsx` - Workflow persistence

**Data & Parameters:**
- `dataset-attachment.tsx` - File upload and attachment
- `dataset-dialog.tsx` - Dataset browser
- `dataset-validation-dialog.tsx` - AI-powered validation UI
- `parameter-editor.tsx` - Dynamic parameter form builder
- `parameter-dialog.tsx` - Step parameter configuration
- `parameter-preview-dialog.tsx` - Parameter review before execution
- `job-log-viewer.tsx` - Step execution logs

**Navigation & Sidebars:**
- `app-sidebar.tsx` - Main navigation sidebar with tools/projects
- `site-header.tsx` - Top navigation bar
- `site-footer.tsx` - Footer

**Dialogs & Modals:**
- `create-project-dialog.tsx` - Project creation form
- `tool-introduction-dialog.tsx` - Tool information modal
- `settings-dialog.tsx` - User preferences
- `starred-workflows-dialog.tsx` - Saved workflows browser
- `recent-tools-dialog.tsx` - Recently used tools
- `galaxy-recommendations.tsx` - AI-suggested tools

**UI Primitives (30+ from Radix UI):**
- Accordion, Alert, Dialog, Drawer, Dropdown Menu
- Form, Hover Card, Input, Label, Popover
- Progress, Select, Separator, Sheet, Sidebar
- Slider, Switch, Tabs, Toast, Tooltip
- Table, Pagination, Calendar, Command

---

## 3. WORKFLOW-RELATED FEATURES

### Workflow Generation & Management
```
Feature                  Implementation
────────────────────────────────────────────────────
Chat-to-Workflow         Claude Sonnet 4.5 NLU
Tool Search             Galaxy tool search (2,177 tools)
Tool Parameters         Dynamic schema-based forms
Workflow Builder        Visual DAG editor
Workflow Validation     AI-powered analysis
Format Conversion       Demo ↔ Galaxy .ga ↔ Standard
```

### Workflow Execution Pipeline

**Step 1: Workflow Generation**
- User query → Claude NLU analysis
- Intent detection → Tool search
- Tool recommendations with relevance scoring
- Dataset recommendations from BioMNI RAG
- Workflow suggestion with confidence score

**Step 2: Parameter Configuration**
- Dynamic form generation from Galaxy tool schemas
- Parameter validation with Zod
- Template-based parameter presets
- Parameter repository for reusable configs

**Step 3: Dataset Handling**
- File upload (500MB max via multer)
- Local Galaxy history creation
- Galaxy dataset upload
- Dataset validation against workflow requirements
- Metadata extraction and storage

**Step 4: Workflow Invocation**
```
POST /api/galaxy/workflows/invoke
├── workflow_id
├── inputs (dataset mapping)
└── parameters (tool config)
↓
Returns: invocation object with ID
```

**Step 5: Real-Time Execution Monitoring**
```
Server-Sent Events (SSE) Stream
├── /api/galaxy/workflows/sse/{invocationId}
├── Event Types:
│   ├── workflow_state (overall status)
│   ├── step_state (per-step updates)
│   ├── job_state (Galaxy job status)
│   └── logs (stdout/stderr)
└── Auto-reconnect handling
```

**Step 6: Step-by-Step Execution Mode**
```
Individual Tool Execution
├── POST /api/workflow/step/execute
│   ├── step_id, tool_id
│   ├── parameters, inputs
│   └── Returns: job_id, state
├── GET /api/workflow/step/{step_id}/status
│   └── Returns: current job state
└── Job logs via:
    ├── GET /api/galaxy/jobs/{jobId}/stdout
    └── GET /api/galaxy/jobs/{jobId}/stderr
```

### Workflow Format Support

**WorkflowAdapter** converts between:
1. **Demo Format** (simple UI-friendly)
   ```javascript
   {
     id, title, steps: [{ id, title, tool, status, parameters }]
   }
   ```

2. **Galaxy .ga Format** (complex nested)
   ```javascript
   {
     name, annotation, steps: { 0: {...}, 1: {...} },
     uuid, format-version
   }
   ```

3. **Standard Format** (unified internal)
   ```javascript
   {
     id, name, steps: [{ id, name, tool, toolId, type, status }],
     metadata: { source, galaxyWorkflowId }
   }
   ```

### Workflow Storage
- **In-Memory:** Chat history (localStorage)
- **Backend:** Parameter templates (repository pattern)
- **Backend:** Workflow templates (repository pattern)
- **Galaxy:** Persistent workflow definitions

---

## 4. DATA HANDLING CAPABILITIES

### Dataset Discovery
```
API Endpoint: POST /api/galaxy/datasets/search

Request:
{
  query: "string",           // Natural language query
  category?: string,         // metabolomics|proteomics|genomics|clinical
  format_type?: string,
  min_size?: number,
  max_size?: number,
  lcms_only?: boolean,
  limit?: number
}

Response:
{
  query, count,
  datasets: [
    {
      id, name, description,
      category, format, size_mb,
      rows?, entries?, sequences?,
      fields{}, lcms_relevant, source, path,
      relevance_score?, query_intent?
    }
  ]
}
```

### Dataset Upload & Processing
```
Multipart Upload:
┌─ POST /api/datasets/upload
├─ File (max 500MB)
├─ Description (optional)
└─ Returns:
   ├─ dataset_id (local)
   ├─ galaxy_dataset_id (if available)
   ├─ galaxy_history_id
   ├─ file metadata
   └─ timestamps

Session Tracking:
├─ Galaxy history creation per session
├─ Dataset metadata stored in req.session.uploadedDatasets
└─ Job tracking via req.session.workflowJobs
```

### Dataset Validation
```
API Endpoint: POST /api/datasets/validate

Validates:
├─ Dataset format compatibility
├─ Required fields presence
├─ Size constraints
├─ Reference genome availability
└─ Tool parameter compatibility

Input:
{
  workflow_name: string,
  workflow_steps: [{ tool_id, parameters, inputs }]
}

Output:
{
  workflow_id: string,
  validation_status: "valid" | "invalid" | "warning",
  dataset_validations: [...],
  recommendations: [...]
}
```

### Data Visualization
- **Recharts:** Bar, line, pie, scatter charts
- **Workflow Graphs:** DAG visualization with connections
- **Execution Timeline:** Step-by-step progress tracking
- **Tables:** Dataset listings with sorting/filtering

### Local Storage Structures
```typescript
// Chat History (localStorage: 'biomate-chat-history')
interface ChatSession {
  id: string;
  title: string;
  timestamp: Date;
  lastActivity: Date;
  messages: Message[];
  workflows?: WorkflowStepWithDatasets[];
  datasets?: DatasetConfig[];
  status: 'active' | 'archived';
}

// User Settings (localStorage)
interface UserSettings {
  theme: 'light' | 'dark' | 'system';
  language: string;
  defaultWorkflowComplexity: string;
  autoSaveWorkflows: boolean;
  defaultStorageType: 'local' | 's3' | 'replit_storage';
}
```

---

## 5. INTEGRATION PATTERNS

### Frontend-Backend Architecture
```
Vite Dev Server (Port 5173)
    ↓
    ├─ Client Assets (React SPA)
    ├─ Proxy: /api/* → localhost:8080
    └─ (dev mode)

Production Build
    ├─ Client (dist/public/)
    ├─ Server (dist/index.js)
    └─ Single Node.js process on PORT
```

### API Integration Strategy

**Fetch-Based HTTP Requests:**
- Custom ApiClient class in `lib/api.ts`
- Bearer token authentication
- Error handling with retry logic
- Content-Type: application/json

**Server-Sent Events (SSE):**
- Real-time workflow execution updates
- Auto-reconnection handling
- Multiple event types per stream
- Endpoint: `/api/galaxy/workflows/sse/{invocationId}`

**Axios (Internal Server Only):**
- Galaxy API proxy layer
- 30s timeout
- Error response normalization
- Interceptor-based error handling

### Galaxy Backend Integration

**Real Galaxy API Access:**
```
Galaxy Instance: http://localhost:8080
├─ Tool Search API (/api/tool_search)
├─ Tool Schema API (/api/tools/{id}/build)
├─ Workflow APIs (/api/workflows)
├─ Job APIs (/api/jobs)
├─ Dataset APIs (/api/datasets)
└─ History APIs (/api/histories)
```

**API Proxy Features:**
- Tool search with full-text indexing
- Tool installation from ToolShed
- Workflow invocation and monitoring
- Job status tracking
- Dataset discovery via BioMNI RAG
- Error response normalization

### State Management

**React Context:**
- `AuthProvider` - Authentication state
- `ThemeProvider` - Dark/light mode
- `TooltipProvider` - Tooltip context
- `QueryClientProvider` - TanStack React Query

**Custom Hooks for State:**
- `useWorkflowExecution()` - SSE connection & invocation tracking
- `useWorkflowSync()` - Bidirectional sync between chat & builder
- `useDebounce()` - Debounced search input
- `useToast()` - Toast notifications

**Service Classes:**
- `chatHistoryService` - LocalStorage persistence
- `projectsService` - Project CRUD
- `starredWorkflowsService` - Favorites
- `recentToolsService` - Usage tracking

### API Response Handling

**Success Responses:**
```javascript
{
  status: 200,
  data: { /* result */ }
}
```

**Error Responses:**
```javascript
{
  status: 400|500,
  error: 'ErrorCode',
  message: 'Human-readable message',
  detail?: any
}
```

**Streaming (SSE):**
```javascript
event: workflow_state
data: { workflow_state: 'running', timestamp: '...' }

event: step_state
data: { step_id: '1', state: 'ok', timestamp: '...' }
```

---

## 6. KEY CONFIGURATION AND ENTRY POINTS

### Entry Points

**Client Entry Point:**
- File: `/home/yzhang/biomate/frontend/client/src/main.tsx`
- Creates React root and renders App component
- Wraps app with: QueryClientProvider, ThemeProvider, AuthProvider

**Server Entry Point:**
- File: `/home/yzhang/biomate/frontend/server/index.ts`
- Initializes Express with middleware
- Registers all routes
- Serves static Vite build
- Listens on PORT (default: 5000)

### Configuration Files

**Vite Configuration** (`vite.config.ts`)
```typescript
{
  plugins: [react()],
  resolve: {
    alias: {
      '@': 'client/src',
      '@shared': 'shared',
      '@assets': 'attached_assets'
    }
  },
  root: 'client',
  build: { outDir: 'dist/public' },
  server: {
    proxy: { '/api': 'http://localhost:8080' }  // Dev proxy
  }
}
```

**Tailwind CSS** (`tailwind.config.js`)
- Custom theme configuration
- Dark mode support
- Extended color palette
- Animation utilities

**TypeScript** (`tsconfig.node.json`)
- Target: ES2020
- Module resolution
- JSX support

**Package.json Scripts:**
```bash
npm run dev      # Development: tsx + Vite dev server
npm run build    # Production: Vite + esbuild bundle
npm run start    # Production: Node.js
npm run check    # Type checking
npm run db:push  # Database migrations (Drizzle)
```

### Environment Variables

**Client:**
```
VITE_API_URL    # API base URL (default: http://localhost:5173/api)
```

**Server:**
```
GALAXY_URL      # Galaxy instance URL (default: http://localhost:8080)
GALAXY_API_KEY  # Galaxy API key (optional)
ANTHROPIC_API_KEY  # Claude API key (required for chat)
OPENAI_API_KEY  # OpenAI API key
SESSION_SECRET  # Express session secret (required in production)
NODE_ENV        # development|production
PORT            # Server port (default: 5000)
```

### Build System

**Development Workflow:**
```bash
npm run dev  # Starts:
# - Vite dev server with HMR
# - tsx watch for server changes
# - Proxy /api to Galaxy backend
```

**Production Build:**
```bash
npm run build  # Creates:
# - dist/public/   (Vite frontend build)
# - dist/index.js  (esbuild server bundle)
# - Optimized: minified, tree-shaken, code-split
```

**Docker Deployment:**
```dockerfile
Node 18 Alpine image
- Multi-stage build: builder → production
- Copy dist/ + node_modules
- Health check: GET /api/health
- Expose port 3000
```

---

## 7. API ENDPOINTS SUMMARY

### Tool Management
```
GET  /api/galaxy/tools/search?q=...&category=...&limit=...
GET  /api/galaxy/tools/categories
GET  /api/galaxy/tools/{toolId}
GET  /api/galaxy/tools/{toolId}/schema
GET  /api/galaxy/tools/installed/list
POST /api/galaxy/tools/{toolId}/install
```

### Dataset Operations
```
POST /api/galaxy/datasets/search
POST /api/datasets/upload
POST /api/datasets/validate
GET  /api/galaxy/datasets/{datasetId}
GET  /api/galaxy/datasets/category/{category}
```

### Workflow Execution
```
POST /api/galaxy/workflows/invoke
GET  /api/galaxy/workflows/{workflowId}/invocations/{invocationId}
GET  /api/galaxy/workflows/sse/{invocationId}  [SSE Stream]
```

### Job Management
```
POST /api/workflow/step/execute
GET  /api/workflow/step/{step_id}/status
GET  /api/galaxy/jobs/{jobId}
GET  /api/galaxy/jobs/{jobId}/stdout
GET  /api/galaxy/jobs/{jobId}/stderr
```

### Chat & AI
```
POST /api/ai_assistant/generate_workflow
POST /api/chat  [with streaming]
```

### System
```
GET  /api/health
```

---

## 8. KEY LIBRARIES & DEPENDENCIES

### Core Dependencies
```
react: 18.3.1              # UI framework
typescript: 5.6.3          # Type safety
express: 4.21.2            # Backend server
axios: 1.12.2              # HTTP client
```

### UI & Styling
```
@radix-ui/*: Latest        # Component library
tailwindcss: 3.4.17        # Utility CSS
lucide-react: 0.453.0      # Icons
framer-motion: 11.13.1     # Animations
recharts: 2.15.2           # Charts
```

### State & Forms
```
@tanstack/react-query: 5.60.5  # Data fetching
react-hook-form: 7.55.0        # Form handling
zod: 3.24.2                    # Schema validation
```

### Backend
```
drizzle-orm: 0.39.1        # ORM
express-session: 1.18.1    # Sessions
multer: 2.0.2              # File uploads
openai: 5.20.1             # OpenAI API
@anthropic-ai/sdk: Latest  # Claude API
```

### Development
```
vite: 5.4.19               # Build tool
esbuild: 0.25.0            # Bundler
tsx: 4.19.1                # TS executor
```

---

## 9. ARCHITECTURE HIGHLIGHTS

### Strengths
1. **Type Safety:** Full TypeScript codebase with Zod validation
2. **Real-time Updates:** SSE-based workflow execution tracking
3. **Modular Design:** Separation of concerns (UI, API, Logic)
4. **Responsive UI:** Radix UI + Tailwind for accessibility
5. **Data Handling:** Multi-source dataset discovery + validation
6. **Galaxy Integration:** Complete API proxy layer
7. **AI-Powered:** Claude integration for intent analysis
8. **Persistent State:** LocalStorage for offline support
9. **Scalable Forms:** Dynamic parameter configuration
10. **Production Ready:** Docker setup with health checks

### Technical Patterns
- **Server-Sent Events** for real-time updates
- **Adapter Pattern** for workflow format conversion
- **Service Classes** for business logic
- **Custom Hooks** for state management
- **Interceptors** for API error handling
- **Context Providers** for global state
- **Repository Pattern** for data access

---

## 10. DATA FLOW EXAMPLES

### Chat-to-Workflow Flow
```
User: "Analyze RNA-seq data"
  ↓
ChatInterface sends to /api/ai_assistant/generate_workflow
  ↓
Server (GalaxyAssistant):
  1. Claude analyzes intent
  2. Tool search (2,177 tools)
  3. Dataset RAG recommendations
  4. Workflow suggestion with confidence
  ↓
Client receives response with:
  - Message (chat response)
  - Recommended tools with scores
  - Recommended datasets
  - Generated workflow
  - Follow-up suggestions
  ↓
Enhanced Workflow Builder displays workflow
  ↓
User configures parameters → Execute
  ↓
Workflow invocation → SSE stream updates
```

### File Upload & Validation Flow
```
User uploads file via FileUpload
  ↓
POST /api/datasets/upload
  ↓
Server:
  1. Save file (multer diskStorage)
  2. Create Galaxy history (if not exists)
  3. Upload to Galaxy
  4. Store metadata in session
  ↓
Client receives:
  - Local dataset_id
  - Galaxy dataset_id
  - Galaxy history_id
  ↓
User builds workflow
  ↓
POST /api/datasets/validate
  ↓
Server:
  1. Get uploaded datasets from session
  2. Analyze workflow steps
  3. Run AI validation
  4. Return compatibility report
  ↓
Client shows validation results
  ↓
Execute workflow with validated inputs
```

---

## 11. SECURITY CONSIDERATIONS

### Authentication
- Bearer token in Authorization header
- Session-based (express-session with memory store)
- HTTP-only cookies with SameSite=lax
- Secure flag in production

### Data Protection
- HTTPS in production (secure cookies)
- File uploads with size limits (500MB)
- Input validation with Zod schemas
- SQL injection prevention (Drizzle ORM)

### API Security
- CORS configured for same-origin
- Error messages sanitized
- No secrets in client code (env variables)
- API key in Authorization header

---

## SUMMARY

The BioMate frontend is a **modern, type-safe React application** with:
- **Advanced workflow building** via visual editor + AI
- **Real-time execution** via Server-Sent Events
- **Comprehensive Galaxy integration** for 2,177+ tools
- **Multi-source dataset discovery** via RAG
- **Persistent state** with LocalStorage
- **Responsive design** with Radix UI + Tailwind
- **Production-ready** Docker deployment

**Key Statistics:**
- 81 React components
- 3,500+ lines of API routes
- Full TypeScript coverage
- Multi-format workflow support
- Real-time SSE streaming
- 30+ Radix UI primitives

