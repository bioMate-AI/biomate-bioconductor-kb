# BioMate Performance Optimization Plan

**Document Created:** 2025-10-28
**Priority:** P2 - Platform Maturity (Month 2-4)
**Status:** Optimization Roadmap
**Estimated Implementation:** 4-6 weeks

---

## Executive Summary

This document defines the performance optimization strategy for BioMate platform across all system layers: frontend, backend, database, workflow execution, and cloud infrastructure. The goal is to achieve sub-second response times for interactive operations and efficient scaling for compute-intensive workflows.

**Key Performance Targets:**
- Page load time: <2 seconds (p95)
- API response time: <200ms (p95)
- Workflow search: <500ms (p95)
- Workflow execution start: <5 seconds
- Database queries: <50ms (p95)
- Large file upload: >100 Mbps throughput

---

## Table of Contents

1. [Current Performance Baseline](#current-performance-baseline)
2. [Frontend Optimization](#frontend-optimization)
3. [Backend Optimization](#backend-optimization)
4. [Database Optimization](#database-optimization)
5. [Workflow Execution Optimization](#workflow-execution-optimization)
6. [Cloud Infrastructure Optimization](#cloud-infrastructure-optimization)
7. [Monitoring & Profiling](#monitoring--profiling)
8. [Implementation Plan](#implementation-plan)

---

## Current Performance Baseline

### Benchmarking Methodology

**Test Environment:**
- 100 concurrent users
- Geographic distribution (US East, US West, EU)
- Mix of operations (70% reads, 30% writes)
- Realistic data sizes (1GB-100GB files)

**Key Metrics:**

| Operation | Current (p95) | Target (p95) | Gap |
|-----------|---------------|--------------|-----|
| **Frontend** | | | |
| Initial page load | 4.2s | 2.0s | 2.2s ❌ |
| Chat message send | 1.8s | 1.0s | 0.8s ❌ |
| Workflow visualization render | 1.2s | 0.5s | 0.7s ❌ |
| File upload (1GB) | 3min | 2min | 1min ❌ |
| **Backend API** | | | |
| GET /api/workflows | 450ms | 200ms | 250ms ❌ |
| POST /api/workflows/execute | 8s | 5s | 3s ❌ |
| GET /api/tools/search | 1.2s | 500ms | 700ms ❌ |
| **Database** | | | |
| Simple SELECT | 25ms | 25ms | 0ms ✅ |
| JOIN query (3 tables) | 180ms | 50ms | 130ms ❌ |
| Full-text search | 850ms | 100ms | 750ms ❌ |
| **Workflow Execution** | | | |
| Job scheduling delay | 15s | 5s | 10s ❌ |
| Data transfer (S3→Galaxy) | 2min (10GB) | 1min | 1min ❌ |

**Overall Assessment:** 70% of targets not met. Significant optimization needed.

---

## Frontend Optimization

### 1. Code Splitting & Lazy Loading

**Problem:** 3.5MB initial JavaScript bundle

**Solution:**

```typescript
// Route-based code splitting
const ChatInterface = lazy(() => import('./components/chat-interface'));
const WorkflowBuilder = lazy(() => import('./components/workflow-builder'));
const ExecutionTimeline = lazy(() => import('./components/execution-timeline'));

// Component lazy loading
<Suspense fallback={<LoadingSpinner />}>
  <Route path="/chat" element={<ChatInterface />} />
  <Route path="/workflows/:id" element={<WorkflowBuilder />} />
</Suspense>
```

**Expected Improvement:**
- Initial bundle: 3.5MB → 800KB (77% reduction)
- Page load time: 4.2s → 1.8s

---

### 2. Image & Asset Optimization

**Problem:** Unoptimized images, large file sizes

**Solution:**
- WebP format for images (30-50% smaller than PNG)
- Responsive images with `srcset`
- Lazy loading for below-fold images
- CDN for static assets (CloudFront)

```tsx
<img
  src="hero-small.webp"
  srcset="hero-small.webp 640w, hero-medium.webp 1280w, hero-large.webp 1920w"
  sizes="(max-width: 640px) 640px, (max-width: 1280px) 1280px, 1920px"
  loading="lazy"
  alt="BioMate Platform"
/>
```

**Expected Improvement:**
- Asset size: 5MB → 1.5MB (70% reduction)
- Page load time: Additional 0.5s reduction

---

### 3. React Performance

**Problem:** Unnecessary re-renders, expensive computations

**Solution:**

```typescript
// Memoization
const MemoizedWorkflowGraph = memo(WorkflowGraph, (prev, next) => {
  return prev.workflow.id === next.workflow.id &&
         prev.workflow.updatedAt === next.workflow.updatedAt;
});

// useMemo for expensive calculations
const sortedTools = useMemo(() => {
  return tools.sort((a, b) => a.name.localeCompare(b.name));
}, [tools]);

// useCallback for stable function references
const handleStepClick = useCallback((stepId: string) => {
  setSelectedStep(stepId);
}, []);

// Virtual scrolling for long lists
import { FixedSizeList } from 'react-window';

<FixedSizeList
  height={600}
  itemCount={tools.length}
  itemSize={50}
  width="100%"
>
  {({ index, style }) => (
    <div style={style}>
      <ToolListItem tool={tools[index]} />
    </div>
  )}
</FixedSizeList>
```

**Expected Improvement:**
- Workflow visualization render: 1.2s → 0.4s
- Reduced CPU usage by 40%

---

### 4. Network Optimization

**Problem:** Multiple sequential API calls, no caching

**Solution:**

```typescript
// GraphQL for efficient data fetching (single request)
const WORKFLOW_QUERY = gql`
  query GetWorkflow($id: ID!) {
    workflow(id: $id) {
      id
      name
      steps {
        id
        name
        parameters
        status
      }
      executions {
        id
        status
        completedAt
      }
    }
  }
`;

// HTTP/2 Server Push
// Preload critical resources
<link rel="preload" href="/api/user/profile" as="fetch" />

// Service Worker for offline support & caching
self.addEventListener('fetch', (event) => {
  event.respondWith(
    caches.match(event.request).then((response) => {
      return response || fetch(event.request);
    })
  );
});
```

**Expected Improvement:**
- API round trips: 8 → 2 (75% reduction)
- Repeat page loads: 2s → 0.5s (caching)

---

## Backend Optimization

### 1. Database Query Optimization

**Problem:** N+1 queries, missing indexes

**Example N+1 Query:**

```typescript
// BAD: N+1 query
const workflows = await db.workflows.findMany();
for (const wf of workflows) {
  wf.steps = await db.steps.findMany({ where: { workflowId: wf.id } });
}
// Total queries: 1 + N

// GOOD: Single query with JOIN
const workflows = await db.workflows.findMany({
  include: {
    steps: true,
  },
});
// Total queries: 1
```

**Missing Indexes:**

```sql
-- Add indexes for common queries
CREATE INDEX idx_workflows_user_created ON workflows(user_id, created_at DESC);
CREATE INDEX idx_steps_workflow ON steps(workflow_id);
CREATE INDEX idx_executions_workflow_status ON executions(workflow_id, status);
CREATE INDEX idx_tools_category ON tools(category);

-- Composite indexes for filtering + sorting
CREATE INDEX idx_workflows_status_created ON workflows(status, created_at DESC);

-- Full-text search indexes
CREATE INDEX idx_tools_name_fts ON tools USING GIN (to_tsvector('english', name));
CREATE INDEX idx_tools_description_fts ON tools USING GIN (to_tsvector('english', description));
```

**Expected Improvement:**
- JOIN queries: 180ms → 30ms (83% reduction)
- Full-text search: 850ms → 80ms (91% reduction)

---

### 2. Caching Strategy

**Redis Caching:**

```typescript
import Redis from 'ioredis';

const redis = new Redis(process.env.REDIS_URL);

// Cache frequently accessed data
async function getWorkflow(id: string): Promise<Workflow> {
  // Check cache first
  const cached = await redis.get(`workflow:${id}`);
  if (cached) {
    return JSON.parse(cached);
  }

  // Cache miss: fetch from database
  const workflow = await db.workflows.findUnique({ where: { id } });

  // Store in cache (TTL: 5 minutes)
  await redis.setex(`workflow:${id}`, 300, JSON.stringify(workflow));

  return workflow;
}

// Invalidate cache on update
async function updateWorkflow(id: string, data: any) {
  const updated = await db.workflows.update({ where: { id }, data });

  // Invalidate cache
  await redis.del(`workflow:${id}`);

  return updated;
}
```

**Caching Strategy:**

| Data Type | Cache Duration | Invalidation Strategy |
|-----------|----------------|------------------------|
| User profile | 10 minutes | On profile update |
| Workflow metadata | 5 minutes | On workflow update |
| Tool catalog | 1 hour | On tool sync |
| Static content | 24 hours | On deploy |
| API responses (GET) | 1 minute | On POST/PUT/DELETE |

**Expected Improvement:**
- Cache hit rate: 70%+
- API response time: 450ms → 120ms (for cached requests)

---

### 3. API Response Compression

**Gzip Compression:**

```typescript
import compression from 'compression';

app.use(compression({
  level: 6,  // Compression level (1-9)
  threshold: 1024,  // Only compress responses >1KB
  filter: (req, res) => {
    if (req.headers['x-no-compression']) {
      return false;
    }
    return compression.filter(req, res);
  },
}));
```

**Expected Improvement:**
- Response size: 500KB → 100KB (80% reduction for JSON)
- Transfer time: 5s → 1s (on 100 Mbps connection)

---

### 4. Async Processing

**Problem:** Long-running operations block HTTP requests

**Solution: Job Queue (Bull):**

```typescript
import Queue from 'bull';

const workflowQueue = new Queue('workflow-execution', process.env.REDIS_URL);

// API endpoint: Start workflow (non-blocking)
app.post('/api/workflows/:id/execute', async (req, res) => {
  const { id } = req.params;

  // Add job to queue (returns immediately)
  const job = await workflowQueue.add({
    workflowId: id,
    userId: req.user.id,
  });

  res.json({
    jobId: job.id,
    status: 'queued',
  });
});

// Worker: Process jobs
workflowQueue.process(async (job) => {
  const { workflowId, userId } = job.data;

  // Execute workflow (long-running)
  const result = await executeWorkflow(workflowId, userId);

  return result;
});
```

**Expected Improvement:**
- POST /api/workflows/execute: 8s → 0.5s (96% reduction)
- Better scalability (horizontal scaling of workers)

---

## Database Optimization

### 1. Connection Pooling

**Problem:** Opening new DB connections for each request (slow)

**Solution:**

```typescript
import { Pool } from 'pg';

const pool = new Pool({
  host: process.env.DB_HOST,
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  max: 20,  // Maximum pool size
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

// Reuse connections from pool
async function query(sql: string, params: any[]) {
  const client = await pool.connect();
  try {
    const result = await client.query(sql, params);
    return result.rows;
  } finally {
    client.release();
  }
}
```

**Expected Improvement:**
- Connection establishment time: 50ms → 5ms
- Throughput: +50%

---

### 2. Query Optimization

**Slow Query Analysis:**

```sql
-- Enable slow query logging
ALTER SYSTEM SET log_min_duration_statement = 100;  -- Log queries >100ms

-- Find slowest queries
SELECT
  query,
  calls,
  total_time,
  mean_time,
  max_time
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 10;
```

**Optimization Techniques:**

```sql
-- Use EXPLAIN ANALYZE to understand query plans
EXPLAIN ANALYZE
SELECT * FROM workflows w
JOIN steps s ON w.id = s.workflow_id
WHERE w.user_id = 'user_123'
ORDER BY w.created_at DESC
LIMIT 10;

-- Add covering index (includes all queried columns)
CREATE INDEX idx_workflows_covering ON workflows(user_id, created_at DESC)
INCLUDE (id, name, status);

-- Partition large tables (e.g., usage_events)
CREATE TABLE usage_events_2025_10 PARTITION OF usage_events
FOR VALUES FROM ('2025-10-01') TO ('2025-11-01');
```

---

### 3. Database Scaling

**Read Replicas:**

```typescript
// Write to primary, read from replicas
const primaryDB = new PrismaClient({
  datasources: { db: { url: process.env.DATABASE_PRIMARY_URL } },
});

const replicaDB = new PrismaClient({
  datasources: { db: { url: process.env.DATABASE_REPLICA_URL } },
});

// Route reads to replica
async function getWorkflows(userId: string) {
  return replicaDB.workflows.findMany({ where: { userId } });
}

// Route writes to primary
async function createWorkflow(data: any) {
  return primaryDB.workflows.create({ data });
}
```

**Expected Improvement:**
- Read capacity: +200% (3x replicas)
- Write latency: No impact

---

## Workflow Execution Optimization

### 1. Job Scheduling Optimization

**Problem:** 15-second delay before job starts

**Bottlenecks:**
1. Galaxy API call overhead (3s)
2. Dataset upload to Galaxy (5s)
3. Job queue wait time (7s)

**Solution 1: Pre-warm Galaxy Instances**

```python
# Keep Galaxy workers ready
GALAXY_WORKER_POOL_SIZE = 10

async def get_ready_worker():
    # Return pre-warmed worker from pool
    worker = await worker_pool.get()
    return worker
```

**Solution 2: Parallel Dataset Upload**

```python
# Upload datasets in parallel
async def upload_datasets(datasets):
    tasks = [upload_to_galaxy(ds) for ds in datasets]
    results = await asyncio.gather(*tasks)
    return results
```

**Expected Improvement:**
- Job start time: 15s → 4s (73% reduction)

---

### 2. Data Transfer Optimization

**Problem:** Slow S3 → Galaxy transfer for large files

**Solution: S3 Direct Mount**

```python
# Mount S3 bucket directly in Galaxy (via s3fs)
import s3fs

s3 = s3fs.S3FileSystem()

# Galaxy reads directly from S3 (no copy)
def run_tool(input_s3_path: str):
    with s3.open(input_s3_path, 'rb') as f:
        # Process file directly
        data = f.read()
```

**Expected Improvement:**
- Data transfer time: 2min (10GB) → 10s (90% reduction)
- Storage costs: -50% (no duplicate storage)

---

### 3. Compute Optimization

**CPU/GPU Auto-Assignment:**

```python
# Automatically select instance type based on tool requirements
def select_instance_type(tool: Tool) -> str:
    if tool.requires_gpu:
        return 'p3.2xlarge'  # GPU instance
    elif tool.is_memory_intensive:
        return 'r5.4xlarge'  # Memory-optimized
    elif tool.is_compute_intensive:
        return 'c5.9xlarge'  # Compute-optimized
    else:
        return 'm5.2xlarge'  # General purpose

# Autoscaling based on queue depth
if job_queue_depth > 50:
    scale_up_workers(count=10)
elif job_queue_depth < 5:
    scale_down_workers(count=5)
```

**Expected Improvement:**
- Cost per workflow: -20% (right-sizing instances)
- Execution time: -15% (better hardware matching)

---

### 4. Workflow Caching

**Problem:** Re-running identical workflow steps wastes compute

**Solution: Step Result Caching**

```python
def compute_step_hash(step: Step, inputs: List[File]) -> str:
    # Hash tool + version + parameters + input checksums
    return hashlib.sha256(
        f"{step.tool}:{step.version}:{step.parameters}:{input_checksums}"
    ).hexdigest()

async def execute_step(step: Step, inputs: List[File]):
    step_hash = compute_step_hash(step, inputs)

    # Check cache
    cached_result = await cache.get(f"step:{step_hash}")
    if cached_result:
        logger.info(f"Step {step.id} cache hit")
        return cached_result

    # Cache miss: execute step
    result = await galaxy.run_step(step, inputs)

    # Store in cache (TTL: 30 days)
    await cache.setex(f"step:{step_hash}", 2592000, result)

    return result
```

**Expected Improvement:**
- Cache hit rate: 30-50% (for development/testing)
- Cost savings: 30-50% for cached workflows

---

## Cloud Infrastructure Optimization

### 1. CDN Configuration (CloudFront)

**Static Assets:**

```typescript
// CloudFront distribution config
{
  origins: [
    {
      domainName: 'biomate-frontend.s3.amazonaws.com',
      originPath: '/static',
      s3OriginConfig: {
        originAccessIdentity: '...',
      },
    },
  ],
  cacheBehaviors: [
    {
      pathPattern: '/static/*',
      targetOriginId: 's3-static',
      viewerProtocolPolicy: 'redirect-to-https',
      compress: true,
      cacheTTL: {
        min: 0,
        default: 86400,  // 1 day
        max: 31536000,  // 1 year
      },
    },
  ],
}
```

**Expected Improvement:**
- Static asset latency: 500ms → 50ms (90% reduction)
- Backend bandwidth: -70%

---

### 2. Auto-Scaling

**Application Servers:**

```yaml
# AWS Auto Scaling Group
AutoScalingGroup:
  MinSize: 2
  MaxSize: 20
  DesiredCapacity: 4
  TargetTrackingScaling:
    - TargetValue: 70  # CPU utilization
      ScaleOutCooldown: 60
      ScaleInCooldown: 300
    - TargetValue: 1000  # Request count per target
      ScaleOutCooldown: 60
      ScaleInCooldown: 300
```

**Galaxy Workers:**

```python
# Kubernetes Horizontal Pod Autoscaler
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: galaxy-workers
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: galaxy-workers
  minReplicas: 5
  maxReplicas: 100
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 80
  - type: Pods
    pods:
      metric:
        name: job_queue_depth
      target:
        type: AverageValue
        averageValue: "10"
```

**Expected Improvement:**
- Handle traffic spikes automatically
- Cost optimization during low traffic (-40%)

---

### 3. Database Tuning

**PostgreSQL Configuration:**

```conf
# postgresql.conf
shared_buffers = 8GB  # 25% of RAM
effective_cache_size = 24GB  # 75% of RAM
maintenance_work_mem = 2GB
work_mem = 128MB
max_connections = 200
max_parallel_workers_per_gather = 4

# Checkpoints
checkpoint_completion_target = 0.9
wal_buffers = 16MB
min_wal_size = 1GB
max_wal_size = 4GB

# Query planning
random_page_cost = 1.1  # For SSD
effective_io_concurrency = 200
```

**Expected Improvement:**
- Query performance: +30%
- Write throughput: +50%

---

## Monitoring & Profiling

### 1. Application Performance Monitoring (APM)

**DataDog Integration:**

```typescript
import { datadogLambda } from 'datadog-lambda-js';
import tracer from 'dd-trace';

tracer.init({
  service: 'biomate-backend',
  env: process.env.NODE_ENV,
});

// Instrument HTTP requests
app.use((req, res, next) => {
  const span = tracer.startSpan('http.request', {
    resource: `${req.method} ${req.path}`,
    tags: {
      'http.method': req.method,
      'http.url': req.path,
    },
  });

  res.on('finish', () => {
    span.setTag('http.status_code', res.statusCode);
    span.finish();
  });

  next();
});
```

**Key Metrics:**
- Request latency (p50, p95, p99)
- Error rate
- Throughput (requests/second)
- Database query time
- External API calls

---

### 2. Frontend Performance Monitoring

**Web Vitals:**

```typescript
import { getCLS, getFID, getFCP, getLCP, getTTFB } from 'web-vitals';

function sendToAnalytics(metric) {
  // Send to backend
  fetch('/api/analytics/web-vitals', {
    method: 'POST',
    body: JSON.stringify(metric),
  });
}

getCLS(sendToAnalytics);  // Cumulative Layout Shift
getFID(sendToAnalytics);  // First Input Delay
getFCP(sendToAnalytics);  // First Contentful Paint
getLCP(sendToAnalytics);  // Largest Contentful Paint
getTTFB(sendToAnalytics); // Time to First Byte
```

**Targets:**
- LCP (Largest Contentful Paint): <2.5s
- FID (First Input Delay): <100ms
- CLS (Cumulative Layout Shift): <0.1

---

### 3. Database Query Profiling

```sql
-- Install pg_stat_statements
CREATE EXTENSION pg_stat_statements;

-- Top 10 slowest queries
SELECT
  substring(query, 1, 50) AS short_query,
  calls,
  mean_exec_time,
  max_exec_time,
  total_exec_time
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat_statements%'
ORDER BY mean_exec_time DESC
LIMIT 10;

-- Reset statistics
SELECT pg_stat_statements_reset();
```

---

## Implementation Plan

### Phase 1: Quick Wins (Week 1)

**High impact, low effort:**
- [ ] Add missing database indexes
- [ ] Enable gzip compression
- [ ] Implement connection pooling
- [ ] Add Redis caching for hot paths
- [ ] Code splitting (top 3 routes)

**Expected Improvement:** 30% faster overall

---

### Phase 2: Frontend (Week 2)

- [ ] Image optimization (WebP, lazy loading)
- [ ] React performance (memo, useMemo, useCallback)
- [ ] Virtual scrolling for long lists
- [ ] Service Worker for caching
- [ ] CDN configuration

**Expected Improvement:** 50% faster page loads

---

### Phase 3: Backend & Database (Weeks 3-4)

- [ ] N+1 query elimination
- [ ] Database query optimization (EXPLAIN ANALYZE)
- [ ] Async job processing (Bull queue)
- [ ] API response caching (Redis)
- [ ] Database read replicas

**Expected Improvement:** 60% faster API responses

---

### Phase 4: Workflow Execution (Weeks 5-6)

- [ ] Pre-warm Galaxy workers
- [ ] S3 direct mount (no data transfer)
- [ ] Step result caching
- [ ] CPU/GPU auto-assignment
- [ ] Autoscaling configuration

**Expected Improvement:** 70% faster workflow execution

---

## Success Metrics

### Phase 1 (Week 1)
- ✅ API response time: <300ms (p95)
- ✅ Database queries: <50ms (p95)
- ✅ Zero slow query alerts

### Phase 2 (Week 2)
- ✅ Page load time: <2s (p95)
- ✅ LCP: <2.5s
- ✅ FID: <100ms

### Phase 4 (Week 6)
- ✅ All targets met
- ✅ Cost per workflow: -20%
- ✅ User satisfaction: >90%

---

**Document Version:** 1.0
**Last Updated:** 2025-10-28
**Next Review:** After Phase 1 completion
**Owner:** BioMate Engineering Team
