# Task Management & Proactive Monitoring Analysis

Date: 2025-11-07
Status: Comprehensive Analysis Complete

---

## Question 1: Task Interruption & Queue Management

### Current Implementation

**Frontend (Chat Interface):**
- Location: `/home/yzhang/biomate/frontend/client/src/components/chat-interface.tsx`
- Handles chat messages and workflow generation
- Messages are stored in session state with history service

**Backend Session Management:**
- Location: `/home/yzhang/biomate/backend/lib/galaxy/webapps/galaxy/api/sessions.py`
- Provides persistent session storage with message queuing
- Supports message history with workflow tracking
- Database schema: `chat_sessions`, `chat_messages`, `session_workflows`, `session_datasets`

**Chat History Service:**
- Location: `/home/yzhang/biomate/frontend/client/src/lib/chat-history.ts`
- Local localStorage-based session management
- Backend sync capability for persistence
- Message queue structure with timestamps

**Galaxy Job Management:**
- Location: `/home/yzhang/biomate/backend/lib/galaxy/jobs/manager.py`
- Provides `enqueue()` method for job queuing (line 50-86)
- Provides `stop()` method for job cancellation (line 88-98)
- Job handler assignment with queue callbacks

### Code Evidence

**Session Message Queue:**
```python
# /home/yzhang/biomate/backend/lib/galaxy/webapps/galaxy/api/sessions.py (lines 104-136)
@router.post("/api/sessions")
def create_session(
    self,
    payload: SessionCreatePayload,
    trans: ProvidesUserContext = DependsOnTrans,
    user: User = DependsOnUser,
) -> SessionResponse:
    """Create a new chat session"""
    db = trans.sa_session
    
    # Check if session already exists
    existing = db.execute(
        text("SELECT session_id FROM chat_sessions WHERE session_id = :session_id"),
        {"session_id": payload.session_id}
    ).fetchone()
```

**Message Update/Queue:**
```python
# /home/yzhang/biomate/backend/lib/galaxy/webapps/galaxy/api/sessions.py (lines 305-329)
if payload.messages is not None:
    # Clear existing messages
    db.execute(text("DELETE FROM chat_messages WHERE session_id = :session_id"), 
               {"session_id": session_id})
    
    # Insert new messages
    for msg in payload.messages:
        db.execute(
            text("""
            INSERT INTO chat_messages
            (message_id, session_id, role, content, timestamp, token_count,
             suggestions, workflow_id, thinking_content, thinking_level,
             error_code, error_message)
            VALUES (:message_id, :session_id, :role, :content, :timestamp, :token_count,
             :suggestions, :workflow_id, :thinking_content, :thinking_level,
             :error_code, :error_message)
            """),
            {...}
        )
```

**Job Queue Management:**
```python
# /home/yzhang/biomate/backend/lib/galaxy/jobs/manager.py (lines 50-86)
def enqueue(self, job, tool=None, flush=True):
    """Queue a job for execution."""
    tool_id = None
    configured_handler = None
    if tool:
        tool_id = tool.id
        configured_handler = tool.get_configured_job_handler(job.params)
    
    queue_callback = partial(self._queue_callback, job, tool_id)
    message_callback = partial(self._message_callback, job)
    try:
        return self.app.job_config.assign_handler(
            job,
            configured=configured_handler,
            queue_callback=queue_callback,
            message_callback=message_callback,
            flush=flush,
        )
```

**Job Stop/Cancellation:**
```python
# /home/yzhang/biomate/backend/lib/galaxy/jobs/manager.py (lines 88-98)
def stop(self, job, message=None):
    """Stop a job that is currently executing.
    
    This can be safely called on jobs that have already terminated.
    
    :param job:     Job to stop.
    :type job:      Instance of :class:`galaxy.model.Job`.
    :param message: Message (if any) to be set on the job and output dataset(s) 
                    to explain the reason for stopping.
    :type message:  str
    """
    self.job_handler.job_stop_queue.put(job.id, error_msg=message)
```

**Session Compression (for interrupted task handling):**
```python
# /home/yzhang/biomate/backend/lib/galaxy/webapps/galaxy/api/sessions.py (lines 450-504)
@router.post("/api/sessions/{session_id}/compress")
def compress_session(
    self,
    session_id: str,
    summary: str = Body(..., description="AI-generated summary of old messages"),
    messages_before: int = Body(..., description="Message count before compression"),
    messages_after: int = Body(..., description="Message count after compression"),
    tokens_before: int = Body(..., description="Token count before compression"),
    tokens_after: int = Body(..., description="Token count after compression"),
    trans: ProvidesUserContext = DependsOnTrans,
    user: User = DependsOnUser,
) -> Dict[str, Any]:
    """Record a session compression event"""
```

### Capabilities

- ✅ **Can queue new tasks**: Messages and jobs are queued in database and Galaxy job queue
- ✅ **Can interrupt current task**: Job stop queue implementation allows cancellation
- ✅ **Preserves task context**: Session API maintains full message history with metadata
- ❌ **Cannot resume interrupted tasks**: No explicit resume mechanism; tasks stay in stopped state
- ❌ **No multi-task queueing**: Only sequential message processing, not parallel task queuing
- ❌ **No task prioritization**: First-in-first-out execution, no priority levels
- ⚠️ **Partial: Switch between tasks**: Can switch conversation topics but not pause/resume same task

### Comparison to Claude Code

**Claude Code Capabilities:**
- Manages multiple concurrent file operations in queue
- Can interrupt current operation and switch to new one
- Resumes interrupted operations when requested
- Maintains operation state across interruptions
- Supports operation priority and dependencies

**Biomate Current State:**
- Only handles sequential chat messages
- Jobs can be stopped but not resumed
- Session compression clears old messages to save tokens
- No task queue with priority or dependencies

### Gap Analysis

**What's Missing:**

1. **Task Queue Structure**
   - No TaskQueue class or similar
   - No task priorities or dependencies
   - Missing: task ID tracking across interruptions
   - Gap: Cannot pause task A, do task B, then resume task A

2. **Resumable Tasks**
   - Job stop queue doesn't preserve job state for resumption
   - No "pause" state (only running/completed/failed)
   - No checkpointing for long-running tasks
   - Gap: Task context lost on interruption

3. **Multi-Task Management**
   - Chat interface processes one message at a time
   - No task switching protocol
   - Missing: task context switching mechanism
   - Gap: Cannot manage 3+ simultaneous task chains

4. **Task State Tracking**
   - Session stores messages but not task execution state
   - No checkpoint/snapshot system
   - Missing: task progress serialization
   - Gap: Cannot resume from intermediate step

---

## Question 2: Proactive Progress Monitoring

### Current Implementation

**Frontend Polling:**
- Location: `/home/yzhang/biomate/frontend/server/galaxy-state-poller.ts`
- Implements continuous polling of Galaxy invocations
- Configurable poll interval (default 2000ms)

**Real-Time Updates via SSE:**
- Location: `/home/yzhang/biomate/frontend/server/workflow-sse.ts`
- Server-Sent Events streaming for live updates
- Broadcasts to multiple clients

**Job Status Monitoring:**
- Location: `/home/yzhang/biomate/backend/lib/galaxy/jobs/manager.py`
- Job handler tracks job state
- Job stop queue for cancellation

**Workflow Execution API:**
- Location: `/home/yzhang/biomate/frontend/server/routes.ts` (lines 1023-1091)
- Provides workflow creation, invocation, and status endpoints
- Job stdout/stderr retrieval endpoints

### Code Evidence

**Galaxy State Poller (Proactive Polling):**
```typescript
// /home/yzhang/biomate/frontend/server/galaxy-state-poller.ts (lines 32-92)
export class GalaxyStatePoller extends EventEmitter {
  private pollers: Map<string, InvocationPoller> = new Map();
  private pollInterval: number;
  private maxRetries: number;
  private intervalId: NodeJS.Timeout | null = null;

  constructor(api: any, options: PollerOptions = {}) {
    super();
    this.api = api;
    this.pollInterval = options.pollInterval || 2000; // Poll every 2 seconds
    this.maxRetries = options.maxRetries || 5;
  }

  startPolling(invocationId: string, workflowId: string): void {
    if (this.pollers.has(invocationId)) {
      console.log(`Already polling invocation ${invocationId}`);
      return;
    }

    const poller: InvocationPoller = {
      invocationId,
      workflowId,
      lastState: null,
      isActive: true,
      failureCount: 0,
    };

    this.pollers.set(invocationId, poller);
    console.log(`Started polling for invocation ${invocationId}`);

    // Start interval if not already running
    if (!this.intervalId) {
      this.startInterval();
    }

    // Immediate first poll
    this.pollInvocation(invocationId);
  }
```

**Polling Implementation (Periodic Checks):**
```typescript
// /home/yzhang/biomate/frontend/server/galaxy-state-poller.ts (lines 121-181)
private startInterval(): void {
  this.intervalId = setInterval(() => {
    this.pollAll();
  }, this.pollInterval);
  console.log(`Started polling interval (${this.pollInterval}ms)`);
}

private async pollAll(): Promise<void> {
  const promises = Array.from(this.pollers.keys()).map((invocationId) => 
    this.pollInvocation(invocationId)
  );
  await Promise.all(promises);
}

private async pollInvocation(invocationId: string): Promise<void> {
  const poller = this.pollers.get(invocationId);
  if (!poller || !poller.isActive) return;

  try {
    const invocation = await this.api.getInvocation(poller.workflowId, invocationId);

    // Reset failure count on successful poll
    poller.failureCount = 0;

    // Detect state changes
    this.detectStateChanges(poller, invocation);

    // Update stored state
    poller.lastState = invocation;

    // Check if workflow is complete
    if (this.isWorkflowComplete(invocation)) {
      console.log(`Invocation ${invocationId} completed with state: ${invocation.state}`);
      this.emit('workflow_completed', { invocation_id: invocationId, state: invocation.state });
      this.stopPolling(invocationId);
    }
  } catch (error: any) {
    poller.failureCount++;
    // ... error handling
  }
}
```

**State Change Detection & Progress Events:**
```typescript
// /home/yzhang/biomate/frontend/server/galaxy-state-poller.ts (lines 186-244)
private detectStateChanges(poller: InvocationPoller, newState: GalaxyWorkflowInvocation): void {
  const oldState = poller.lastState;

  // First poll - emit initial state
  if (!oldState) {
    this.emitUpdate({
      type: 'workflow_state',
      invocation_id: newState.id,
      timestamp: new Date().toISOString(),
      data: { workflow_state: newState.state },
    });
    return;
  }

  // Workflow-level state change
  if (oldState.state !== newState.state) {
    this.emitUpdate({
      type: 'workflow_state',
      invocation_id: newState.id,
      timestamp: new Date().toISOString(),
      data: { workflow_state: newState.state },
    });
  }

  // Step-level state changes
  newState.steps.forEach((newStep) => {
    const oldStep = oldState.steps.find((s) => s.id === newStep.id);

    if (!oldStep) {
      // New step detected
      this.emitUpdate({
        type: 'step_state',
        invocation_id: newState.id,
        timestamp: new Date().toISOString(),
        data: {
          step_id: newStep.id,
          step_state: newStep.state,
          job_id: newStep.job_id,
        },
      });
    } else if (oldStep.state !== newStep.state) {
      // Step state changed - fetch logs
      if (newStep.state === 'ok' || newStep.state === 'error') {
        this.fetchJobLogs(newState.id, newStep.id, newStep.job_id);
      }
    }
  });
}
```

**Real-Time SSE Broadcasting:**
```typescript
// /home/yzhang/biomate/frontend/server/workflow-sse.ts (lines 20-91)
export class WorkflowSSEManager {
  private clients: Map<string, SSEClient[]> = new Map(); // invocationId -> clients
  private poller: GalaxyStatePoller;

  constructor(poller: GalaxyStatePoller) {
    this.poller = poller;
    this.setupPollerListeners();
  }

  private setupPollerListeners(): void {
    // Workflow-level state changes
    this.poller.on('workflow_state', (update: WorkflowExecutionUpdate) => {
      this.broadcastToClients(update.invocation_id, update);
    });

    // Step-level state changes
    this.poller.on('step_state', (update: WorkflowExecutionUpdate) => {
      this.broadcastToClients(update.invocation_id, update);
    });

    // Job logs
    this.poller.on('job_log', (update: WorkflowExecutionUpdate) => {
      this.broadcastToClients(update.invocation_id, update);
    });

    // Errors
    this.poller.on('error', (update: WorkflowExecutionUpdate) => {
      this.broadcastToClients(update.invocation_id, update);
    });

    // Workflow completed
    this.poller.on('workflow_completed', (data: { invocation_id: string; state: string }) => {
      const update: WorkflowExecutionUpdate = {
        type: 'workflow_state',
        invocation_id: data.invocation_id,
        timestamp: new Date().toISOString(),
        data: { workflow_state: data.state as any },
      };
      this.broadcastToClients(data.invocation_id, update);

      // Close all clients after completion
      setTimeout(() => {
        this.closeClientsForInvocation(data.invocation_id);
      }, 1000);
    });
  }
```

**API Endpoints for Job Tracking:**
```typescript
// /home/yzhang/biomate/frontend/server/routes.ts (lines 1080-1091)
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
    // ... error handling
  }
});
```

### Capabilities

- ✅ **Periodic progress checks**: Polls every 2 seconds (configurable)
- ✅ **State change detection**: Emits events on workflow/step state changes
- ✅ **Job log retrieval**: Fetches stdout/stderr on step completion
- ✅ **Real-time notifications**: SSE streaming to multiple clients
- ❌ **Automatic statistics generation**: No summary/statistics calculation
- ❌ **Proactive visualization**: No charts or graphs generated automatically
- ❌ **Intermediate summaries**: Only raw state updates, no narrative summaries
- ⚠️ **Partial: Progress calculation**: Can calculate % complete from step counts (no ETA)

### Comparison to Claude Code

**Claude Code Capabilities:**
- Proactively shows file operation progress
- Generates step summaries during long operations
- Creates visual progress indicators
- Automatically logs intermediate results
- Generates final summaries when complete
- Calculates time estimates

**Biomate Current State:**
- Polls and reports raw state changes
- Emits events on step completion
- Streams logs via SSE
- No automatic summary generation
- No visualization beyond status updates

### Gap Analysis

**What's Missing:**

1. **Statistics & Summaries**
   - No automatic statistics calculation
   - No intermediate progress summaries
   - Missing: workflow performance metrics
   - Gap: User doesn't know overall progress % or ETA

2. **Visualization**
   - No progress bar calculation
   - No pie/donut charts of step completion
   - Missing: timeline visualization
   - Gap: Hard to visualize where workflow is in execution

3. **Automatic Reporting**
   - No automatic intermediate reports
   - No summary generation after steps
   - Missing: benchmark results
   - Gap: User must manually check logs

4. **Notification System**
   - No email/webhook notifications on completion
   - No alert for errors until user checks
   - Missing: configurable alerting
   - Gap: User must actively monitor

---

## Recommendations

### Priority 1: Task Queue Management

**Implementation Plan (if missing features needed):**

1. **Create TaskQueue Class**
   - Location: `backend/lib/galaxy/ai/task_queue.py`
   - Implement FIFO queue with priority support
   - Add task state tracking (queued, running, paused, completed)
   - Support for task dependencies

2. **Add Resume Capability**
   - Extend Job model with checkpoint state
   - Add checkpoint/restore methods
   - Create pause/resume job handlers
   - Serialize job context at checkpoint

3. **Implement Task Switching**
   - Add task context switching to Galaxy Assistant
   - Create session stack for nested task contexts
   - Preserve message context per task
   - Add "back to previous task" capability

4. **Add Task ID Tracking**
   - Implement task IDs in message metadata
   - Track task execution context
   - Maintain task dependency graph
   - Create task completion callbacks

**Effort Estimate:** 40-60 hours
- Task queue implementation: 15h
- Resume/checkpoint system: 20h
- Task context switching: 15h
- Testing and integration: 10h

### Priority 2: Proactive Monitoring

**Implementation Plan (if missing features needed):**

1. **Statistics Generation**
   - Location: `backend/lib/galaxy/ai/workflow_monitor.py`
   - Calculate step completion % in real-time
   - Track time per step
   - Estimate time to completion
   - Generate performance metrics

2. **Summary Generation**
   - Use Claude Sonnet to generate step summaries
   - Create milestone summaries at 25%, 50%, 75%, 100%
   - Generate final workflow report
   - Include recommendations for optimization

3. **Visualization Support**
   - Create progress calculation endpoints
   - Return metrics for frontend charting
   - Add timeline data for visualization
   - Support custom widget data formats

4. **Notification System**
   - Implement webhook support for completion
   - Add email notifications
   - Create alert configuration API
   - Support for custom notification templates

**Effort Estimate:** 30-45 hours
- Statistics engine: 10h
- Summary generation: 12h
- Visualization APIs: 8h
- Notification system: 10h
- Testing: 5h

---

## Implementation Estimates

### Quick Wins (5-10 hours each)

1. **Progress % Calculation**
   - Calculate from step counts
   - Add to SSE updates
   - Frontend progress bar
   - **Effort:** 8 hours

2. **ETA Calculation**
   - Track step execution times
   - Linear extrapolation
   - Confidence intervals
   - **Effort:** 6 hours

3. **Simple Summaries**
   - Template-based summaries
   - Step completion milestones
   - **Effort:** 5 hours

### Medium Effort (15-25 hours each)

1. **Resume Task Capability**
   - Job checkpoint system
   - Pause state support
   - Context preservation
   - **Effort:** 20 hours

2. **Task Priorities**
   - Queue priority levels
   - Task reordering API
   - Priority rules engine
   - **Effort:** 18 hours

3. **Progress Visualization**
   - Metrics calculation
   - Timeline generation
   - Graph data format
   - **Effort:** 15 hours

### Major Features (40+ hours each)

1. **Full Task Queue System**
   - Queue implementation
   - Dependencies
   - Context switching
   - Task management UI
   - **Effort:** 50+ hours

2. **Intelligent Monitoring**
   - ML-based ETA
   - Anomaly detection
   - Auto-generated insights
   - **Effort:** 60+ hours

---

## Summary

**Current Strengths:**
- Solid job queuing and cancellation in Galaxy backend
- Real-time progress monitoring via polling and SSE
- Good session persistence for chat history
- Comprehensive job status tracking APIs

**Current Gaps:**
- **Task Interruption**: Jobs can be stopped but not resumed; no true task queue
- **Monitoring**: Reports state changes but no automatic statistics, summaries, or visualizations
- **User Experience**: No progress %, ETA, or intermediate insights

**Key Differences from Claude Code:**
- Claude Code: Multi-task context switching with resumable operations
- Biomate: Sequential chat messages with job execution pipeline
- Claude Code: Proactive progress summaries and visualizations
- Biomate: Reactive status reporting on state changes

**Recommendation:**
Start with quick wins (progress %, ETA) before tackling full queue system. Focus on user-visible improvements first (better progress indication, summaries) before architectural changes.
