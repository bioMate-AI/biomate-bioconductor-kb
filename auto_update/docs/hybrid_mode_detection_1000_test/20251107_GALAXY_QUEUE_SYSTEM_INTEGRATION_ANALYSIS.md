# Galaxy Job Queue System Integration Analysis

Date: 2025-11-07
Analysis: Galaxy's Built-in Queue Features vs Biomate's Usage
Status: Complete

---

## Executive Summary

Galaxy possesses a **highly sophisticated job queue management system** with mature features for production-grade job scheduling, prioritization, resource allocation, and recovery. Biomate currently leverages only a **subset of these capabilities**:

**Currently Used:**
- ✅ Job queuing and dispatch
- ✅ Job cancellation (stop)
- ✅ Concurrent job limits (per user, per destination)
- ✅ Walltime limits
- ✅ Quota checking and pausing
- ✅ Job state tracking (new, queued, running, paused, error, ok)

**Available but Unused:**
- ❌ Multi-level job prioritization
- ❌ Job dependencies (wait for X before Y)
- ❌ Automatic job retry on failure
- ❌ Job pause/resume capability
- ❌ Resource group selection (memory, CPU, GPU)
- ❌ Handler-specific job assignment
- ❌ Dynamic job destination routing
- ❌ Task parallelization (job splitting)

---

## Part 1: Galaxy's Built-in Queue Features

### 1.1 Job Submission Queue (JobHandlerQueue)

**File:** `/home/yzhang/biomate/backend/lib/galaxy/jobs/handler.py` (lines 250-1051)
**Status:** ✅ Implemented & Available

**Features:**
- Internal queue managing job state transitions
- Two-level queue system: `JobHandlerQueue` (execution) + `JobHandlerStopQueue` (cancellation)
- Database-backed job tracking with optional in-memory queue
- Automatic job recovery on Galaxy restart

**Code Reference:**
```python
# /home/yzhang/biomate/backend/lib/galaxy/jobs/handler.py:250
class JobHandlerQueue(BaseJobHandlerQueue):
    """Job Handler's Internal Queue, this is what actually implements waiting for
    jobs to be runnable and dispatching to a JobRunner."""
    
    def __init__(self, app: MinimalManagerApp, dispatcher):
        super().__init__(app, dispatcher)
        self.waiting_jobs: list[int] = []
        self.job_wrappers: dict[int, JobWrapper] = {}
        # Jobs are processed by continuous monitoring thread
        name = "JobHandlerQueue.monitor_thread"
        self._init_monitor_thread(name, target=self.__monitor, config=app.config)

# /home/yzhang/biomate/backend/lib/galaxy/jobs/handler.py:383-399
def __monitor(self):
    """Continually iterate the waiting jobs, checking if each is ready to run 
    and dispatching if so."""
    while self.monitor_running:
        if not self.app.job_manager.job_lock:
            self.__monitor_step()
        self._monitor_sleep(self.app.config.job_handler_monitor_sleep)
```

**Biomate Usage:**
- Creates jobs with `app.job_manager.enqueue(job, tool)`
- Polls job state via REST API
- Supports workflow invocation with automatic job submission

---

### 1.2 Priority Levels & Job Ordering

**File:** `/home/yzhang/biomate/backend/lib/galaxy/jobs/handler.py` (lines 401-587)
**Status:** ⚠️ Partial Implementation

**Features:**
- Job rank-based ordering (FIFO by default)
- User-level ranking for fairness
- Ready window sizing to prevent starvation
- Step-wise execution with fair scheduling

**Code Reference:**
```python
# /home/yzhang/biomate/backend/lib/galaxy/jobs/handler.py:477-493
coalesce_exp = func.coalesce(
    model.Job.table.c.user_id, model.Job.table.c.session_id)
rank = func.rank().over(
    partition_by=coalesce_exp, order_by=model.Job.table.c.id
).label("rank")
ready_query = (
    self.sa_session.query(model.Job, rank)
    .filter(and_(*job_filter_conditions))
    .order_by(model.Job.id)
)
# Only return top N jobs (ready_window_size)
ranked = ready_query.subquery()
jobs_to_check = (
    self.sa_session.query(model.Job)
    .filter(ranked.c.rank <= self.app.job_config.handler_ready_window_size)
)
```

**Biomate Usage:** Not used - all jobs processed in order
**Gap:** No way to prioritize urgent tasks over background tasks

---

### 1.3 Job Dependencies

**File:** `/home/yzhang/biomate/backend/lib/galaxy/jobs/handler.py` (lines 418-587)
**Status:** ✅ Implemented for Workflows

**Features:**
- Automatic dependency tracking via `JobToInputDatasetAssociation`
- Jobs wait until input datasets are ready
- Dependent job pausing when inputs fail
- Support for cascading failures

**Code Reference:**
```python
# /home/yzhang/biomate/backend/lib/galaxy/jobs/handler.py:543-548
if job.copied_from_job_id:
    # Copy data from previously executed job
    copied_from_job = self.sa_session.query(model.Job).get(job.copied_from_job_id)
    job.copy_from_job(copied_from_job)
    continue

# /home/yzhang/biomate/backend/lib/galaxy/jobs/handler.py:786-811
for dataset_assoc in job.input_datasets + job.input_library_datasets:
    idata = dataset_assoc.dataset
    if idata.deleted:
        # Fail job if input deleted
        return JOB_INPUT_DELETED
    elif idata.state != idata.states.OK:
        # Requeue if not ready
        return JOB_WAIT
```

**Biomate Usage:** Leveraged by workflows but not exposed via task API
**Gap:** Cannot explicitly define task dependencies in conversation flow

---

### 1.4 Concurrent Job Limits

**File:** `/home/yzhang/biomate/backend/lib/galaxy/jobs/__init__.py` (lines 314-318)
**Status:** ✅ Fully Implemented

**Features:**
- Per-user concurrent job limits
- Per-destination concurrent job limits
- Per-destination-tag concurrent limits (e.g., "gpu" tag max 2)
- Per-destination total job limits
- Anonymous user limits
- Quota checking

**Configuration:**
```python
# /home/yzhang/biomate/backend/lib/galaxy/jobs/__init__.py:314-330
class JobLimits:
    registered_user_concurrent_jobs: Optional[int] = None
    anonymous_user_concurrent_jobs: Optional[int] = None
    destination_user_concurrent_jobs: dict = field(default_factory=dict)  # {dest_id: limit}
    destination_total_concurrent_jobs: dict = field(default_factory=dict)  # {dest_id: limit}
    walltime: Optional[timedelta] = None
    walltime_delta: Optional[timedelta] = None
    total_walltime: dict = field(default_factory=dict)  # {window, delta}
    output_size: Optional[int] = None
```

**Handler Implementation:**
```python
# /home/yzhang/biomate/backend/lib/galaxy/jobs/handler.py:932-985
def __check_user_jobs(self, job, job_wrapper):
    # Check registered user concurrent job limit
    if job.user and self.app.job_config.limits.registered_user_concurrent_jobs:
        count = self.get_user_job_count(job.user_id)
        if count >= self.app.job_config.limits.registered_user_concurrent_jobs:
            return JOB_WAIT
    
    # Check per-destination limits
    if id in self.app.job_config.limits.destination_user_concurrent_jobs:
        count = self.get_user_job_count_per_destination(job.user_id).get(id, 0)
        if count >= self.app.job_config.limits.destination_user_concurrent_jobs[id]:
            return JOB_WAIT
    
    # Check tag-based limits
    if job_wrapper.job_destination.tags:
        for tag in job_wrapper.job_destination.tags:
            if tag in self.app.job_config.limits.destination_user_concurrent_jobs:
                count = sum(count_per_id.get(id, 0) for id in tagged_ids)
                if count >= limit:
                    return JOB_WAIT
```

**Biomate Usage:** Configured at system level, enforced automatically
**Example Config:**
```yaml
limits:
  - type: registered_user_concurrent_jobs
    value: 5
  - type: destination_user_concurrent_jobs
    id: slurm
    value: 2
  - type: destination_total_concurrent_jobs
    tag: gpu
    value: 4
```

---

### 1.5 Pause/Resume Capability

**File:** `/home/yzhang/biomate/backend/lib/galaxy/jobs/__init__.py` (lines 1561-1573)
**Status:** ✅ Implemented

**Features:**
- Job pause state (separate from deletion/error)
- Pause on quota exceeded
- Pause on user walltime limit exceeded
- Pause on input dataset failure
- Pause with custom message

**Code Reference:**
```python
# /home/yzhang/biomate/backend/lib/galaxy/jobs/__init__.py:1561-1573
def pause(self, job=None, message=None):
    """Pause job execution."""
    if job is None:
        job = self.get_job()
    if message is None:
        message = "Execution of this dataset's job is paused"
    if job.state in (job.states.NEW, job.states.QUEUED):
        for dataset_assoc in job.output_datasets + job.output_library_datasets:
            dataset_assoc.dataset.dataset.state = dataset_assoc.dataset.dataset.states.PAUSED
            dataset_assoc.dataset.info = message
        log.debug("Pausing Job '%d', %s", job.id, message)
        job.set_state(job.states.PAUSED)
```

**Pause Triggers:**
```python
# /home/yzhang/biomate/backend/lib/galaxy/jobs/handler.py:564-568
if time_spent > self.app.job_config.limits.total_walltime["delta"]:
    log.info("(%d) User (%s) is over total walltime limit: job paused", job.id, job.user_id)
    job.set_state(model.Job.states.PAUSED)
    for dataset_assoc in job.output_datasets + job.output_library_datasets:
        dataset_assoc.dataset.dataset.state = model.Dataset.states.PAUSED

# /home/yzhang/biomate/backend/lib/galaxy/jobs/__init__.py:1803-1808
def _pause_job_if_over_quota(self, job):
    quota_source_map = self.app.object_store.get_quota_source_map()
    if self.app.quota_agent.is_over_quota(quota_source_map, job):
        log.info("(%d) User (%s) is over quota: job paused", job.id, job.user_id)
        message = "Execution paused because over disk quota"
        self.pause(job, message)

# /home/yzhang/biomate/backend/lib/galaxy/jobs/handler.py:649-656
for job_id in sorted(jobs_to_pause):
    pause_message = ", ".join(jobs_to_pause[job_id])
    pause_message = f"{pause_message}. To resume this job fix the input dataset(s)."
    job, job_wrapper = self.job_pair_for_id(job_id)
    try:
        job_wrapper.pause(job=job, message=pause_message)
```

**Biomate Usage:** Jobs can be paused, but no explicit resume mechanism exposed
**Gap:** Paused jobs require manual intervention or error correction; cannot resume programmatically

---

### 1.6 Automatic Retry on Failure

**File:** `/home/yzhang/biomate/backend/lib/galaxy/jobs/__init__.py` (lines 374-385, 745-754)
**Status:** ✅ Fully Implemented

**Features:**
- Configurable resubmission conditions (e.g., exit code, error patterns)
- Automatic resubmission with delay
- Resubmit counter tracking
- Conditional resubmission logic

**Configuration:**
```python
# /home/yzhang/biomate/backend/lib/galaxy/jobs/__init__.py:374-385
default_resubmits = []
default_resubmit_condition = self.app.config.default_job_resubmission_condition
if default_resubmit_condition:
    default_resubmits.append(
        dict(
            condition=default_resubmit_condition,
            handler=self.app.config.default_job_resubmission_handler,
        )
    )
self.default_resubmits = default_resubmits

# /home/yzhang/biomate/backend/lib/galaxy/jobs/__init__.py:745-754
@staticmethod
def get_resubmits(parent):
    """Parses any child <resubmit> tags into a dictionary suitable for persistence."""
    resubmits = []
    for resubmit in parent.findall("resubmit"):
        resubmit_dict = dict(resubmit.attrib)
        resubmit_dict['condition'] = resubmit.text
        resubmits.append(resubmit_dict)
    return resubmits
```

**Example Config:**
```yaml
execution:
  environments:
    - id: slurm
      runner: slurm
      resubmit:
        - condition: tool_exit_code == -1  # SIGTERM
          handler: default
        - condition: job_output_size > 10GB
          handler: bigmem
```

**Biomate Usage:** Configured at system level, not exposed via task API
**Gap:** No way to define retry behavior per conversation task

---

### 1.7 Job Destinations & Resource Allocation

**File:** `/home/yzhang/biomate/backend/lib/galaxy/jobs/__init__.py` (lines 131-155)
**Status:** ✅ Fully Implemented

**Features:**
- Multiple destination definitions (local, slurm, kubernetes, cloud, etc.)
- Destination parameters (CPU, memory, GPU, environment variables)
- Environment setup per destination
- Resource group selection
- Shell selection per destination
- Job metrics collection per destination

**Code Reference:**
```python
# /home/yzhang/biomate/backend/lib/galaxy/jobs/__init__.py:131-155
class JobDestination(Bunch):
    """Provides details about where a job runs"""
    def __init__(self, **kwds):
        self["id"] = None
        self["url"] = None
        self["tags"] = None
        self["runner"] = None
        self["shell"] = None
        self["env"] = []
        self["resubmit"] = []
        self["params"] = {}  # e.g., {nproc: 4, memory: "8G", gpu: "1"}
```

**Example Configuration:**
```yaml
execution:
  environments:
    - id: local
      runner: local
      params:
        workers: 4
    
    - id: slurm_default
      runner: slurm
      params:
        nproc: 4
        memory: "8G"
        walltime: "08:00:00"
      env:
        - SLURM_ACCOUNT=galaxy
      tags:
        - compute
    
    - id: slurm_gpu
      runner: slurm
      params:
        nproc: 8
        memory: "16G"
        gpu: "1"
        walltime: "24:00:00"
      tags:
        - gpu
```

**Biomate Usage:** Leveraged by workflows; tool-specific destination assignment available
**Gap:** No way to select resource tier from conversation (e.g., "use high-memory")

---

### 1.8 Job State Machine & Transitions

**File:** `/home/yzhang/biomate/backend/lib/galaxy/jobs/handler.py` (lines 49-70)
**Status:** ✅ Fully Implemented

**States:**
- `new` - Job created, not yet dispatched
- `queued` - Ready to run, waiting for resources
- `running` - Currently executing
- `paused` - Suspended (quota, walltime, input error)
- `stopped` - Manually stopped
- `deleted` - User deleted
- `error` - Failed
- `ok` - Successful

**State Constants:**
```python
# /home/yzhang/biomate/backend/lib/galaxy/jobs/handler.py:49-70
(
    JOB_WAIT,
    JOB_ERROR,
    JOB_INPUT_ERROR,
    JOB_INPUT_DELETED,
    JOB_READY,
    JOB_DELETED,
    JOB_ADMIN_DELETED,
    JOB_USER_OVER_QUOTA,
    JOB_USER_OVER_TOTAL_WALLTIME,
) = (
    "wait",
    "error",
    "input_error",
    "input_deleted",
    "ready",
    "deleted",
    "admin_deleted",
    "user_over_quota",
    "user_over_total_walltime",
)
```

**State Transitions:**
- Job creation: `new` (default)
- Input ready: `queued`
- Dispatch to runner: `running`
- Resource limits hit: `paused` (automatic)
- User cancellation: `stopped`
- Error in job: `error`
- Completion: `ok`
- User deletion: `deleted`
- Admin deletion: `admin_deleted`

**Biomate Usage:** Full state tracking via REST API and event system
**Gap:** No explicit pause/resume UI in chat interface

---

### 1.9 Handler Assignment & Load Balancing

**File:** `/home/yzhang/biomate/backend/lib/galaxy/jobs/handler.py` (lines 109-226)
**Status:** ✅ Implemented

**Features:**
- Multiple handler assignment methods:
  - `db_transaction_isolation` - SERIALIZABLE transaction safety
  - `db_skip_locked` - Non-blocking job grabbing
  - `mem` - In-memory handler assignment
- Job pinning to specific handlers
- Handler tag-based routing
- Handler-specific runner plugins

**Code Reference:**
```python
# /home/yzhang/biomate/backend/lib/galaxy/jobs/handler.py:185-189
def grab_unhandled_items(self):
    """Assigns unassigned jobs to itself using DB serialization methods."""
    # Sets Job.handler to current server name
    # Causes job to be picked up by appropriate handler

# /home/yzhang/biomate/backend/lib/galaxy/jobs/handler.py:269-279
self.job_grabber = JobGrabber(
    app=app,
    handler_assignment_method=handler_assignment_method,
    max_grab=self.app.job_config.handler_max_grab,
    self_handler_tags=self.app.job_config.self_handler_tags,
    handler_tags=self.app.job_config.handler_tags,
)
```

**Biomate Usage:** Configured for HA/load balancing, transparent to tasks
**Gap:** Cannot route specific tasks to specific handlers

---

### 1.10 Task Parallelization (Job Splitting)

**File:** `/home/yzhang/biomate/backend/lib/galaxy/jobs/runners/tasks.py`
**Status:** ✅ Implemented

**Features:**
- Automatic job splitting into parallel tasks
- Task dependency tracking
- Task failure handling
- Task-specific runner

**Usage:** Via job runner configuration
```python
# /home/yzhang/biomate/backend/lib/galaxy/jobs/__init__.py:415-418
if self.app.config.use_tasked_jobs:
    job_config_dict["runners"]["tasks"] = dict(
        id="tasks", load="tasks", workers=self.app.config.local_task_queue_workers, kwds={}
    )
```

**Biomate Usage:** Transparent if enabled; not exposed to conversation
**Gap:** Cannot request parallel execution from task API

---

## Part 2: How Biomate Currently Uses Galaxy Queue

### 2.1 Job Submission Flow

**File:** `/home/yzhang/biomate/frontend/server/routes.ts` (lines 929-960)
**File:** `/home/yzhang/biomate/backend/lib/galaxy/jobs/manager.py` (lines 50-86)

**Current Flow:**
```typescript
// 1. Frontend submits tool job
const job = await galaxyAPIProxy.submitToolJob(tool_id, {
  inputs: step_inputs,
  history_id: history_id,
  resource_select: workflow_step?.resource_select
});

// 2. Backend handler receives job
// /home/yzhang/biomate/backend/lib/galaxy/jobs/manager.py:50-86
def enqueue(self, job, tool=None, flush=True):
    """Queue a job for execution."""
    tool_id = None
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
    except HandlerAssignmentError as exc:
        raise ToolExecutionError(exc.args[0], job=exc.obj)

# 3. Handler processes job
# /home/yzhang/biomate/backend/lib/galaxy/jobs/handler.py:401-587
# JobHandlerQueue.__handle_waiting_jobs():
# - Checks job state and dependencies
# - Verifies limits aren't exceeded
# - Dispatches to runner when ready
# - Monitors job execution
```

**Code Evidence:**
```python
# /home/yzhang/biomate/backend/lib/galaxy/jobs/manager.py:44-46
def _queue_callback(self, job, tool_id):
    self.job_handler.job_queue.put(job.id, tool_id)

# /home/yzhang/biomate/backend/lib/galaxy/jobs/manager.py:88-98
def stop(self, job, message=None):
    """Stop a job that is currently executing."""
    self.job_handler.job_stop_queue.put(job.id, error_msg=message)
```

---

### 2.2 Workflow Invocation & Job Submission

**File:** `/home/yzhang/biomate/frontend/server/routes.ts` (lines 1049-1062)

**Flow:**
```typescript
app.post("/api/galaxy/workflows/invoke", async (req, res) => {
  try {
    const invocation = await galaxyAPIBackend.invokeWorkflow(workflow_id, inputs, parameters);
    // Returns invocation object with auto-submitted jobs
    res.json({
      message: 'Workflow invoked successfully',
      invocation_id: invocation.id
    });
  } catch (error: any) {
    res.status(error.status_code || 500).json({...});
  }
});
```

**Galaxy Workflow Engine:**
- Parses workflow definition
- Creates jobs for each step automatically
- Submits jobs to queue via `app.job_manager.enqueue()`
- Tracks dependencies between steps
- Enforces input readiness

---

### 2.3 Job Monitoring & State Tracking

**File:** `/home/yzhang/biomate/frontend/server/galaxy-state-poller.ts`

**Polling Loop:**
```typescript
// /home/yzhang/biomate/frontend/server/galaxy-state-poller.ts:236-260
startPolling(invocationId: string, workflowId: string): void {
  const poller: InvocationPoller = {
    invocationId,
    workflowId,
    lastState: null,
    isActive: true,
    failureCount: 0,
  };
  this.pollers.set(invocationId, poller);
  
  // Every 2 seconds
  if (!this.intervalId) {
    this.startInterval();  // setInterval(pollAll, 2000)
  }
}

// /home/yzhang/biomate/frontend/server/galaxy-state-poller.ts:280-301
private async pollInvocation(invocationId: string): Promise<void> {
  const poller = this.pollers.get(invocationId);
  if (!poller || !poller.isActive) return;
  
  try {
    const invocation = await this.api.getInvocation(poller.workflowId, invocationId);
    poller.failureCount = 0;
    this.detectStateChanges(poller, invocation);
    poller.lastState = invocation;
    
    if (this.isWorkflowComplete(invocation)) {
      this.emit('workflow_completed', {...});
      this.stopPolling(invocationId);
    }
  } catch (error: any) {
    poller.failureCount++;
  }
}
```

**What's Monitored:**
- Workflow state (scheduled, running, paused, failed, cancelled, ok)
- Step state for each workflow step
- Job state for jobs within steps
- Job log (stdout, stderr)

**Biomate Usage:**
- Polls Galaxy API every 2 seconds
- Emits events on state changes
- Broadcasts to frontend via SSE
- Stops polling when workflow completes

---

### 2.4 Job Cancellation

**File:** `/home/yzhang/biomate/backend/lib/galaxy/jobs/manager.py` (lines 88-98)

**Implementation:**
```python
def stop(self, job, message=None):
    """Stop a job that is currently executing."""
    self.job_handler.job_stop_queue.put(job.id, error_msg=message)

# /home/yzhang/biomate/backend/lib/galaxy/jobs/handler.py:1053-1182
class JobHandlerStopQueue(BaseJobHandlerQueue):
    """A queue for jobs which need to be terminated prematurely."""
    
    def put(self, job_id: int, error_msg: Optional[str] = None):
        if not self.track_jobs_in_database:
            self.queue.put((job_id, error_msg))
    
    def __monitor_step(self):
        """Called repeatedly to stop jobs."""
        jobs_to_check = []
        with self.sa_session.begin():
            self._add_newly_deleted_jobs(jobs_to_check)
            try:
                self._pull_from_queue(jobs_to_check)
            except StopSignalException:
                return
            self._check_jobs(jobs_to_check)
    
    def _check_jobs(self, jobs_to_check):
        for job, error_msg in jobs_to_check:
            if job.state == job.states.DELETING:
                self.__delete(job, error_msg)  # Set to DELETED
            elif job.state == job.states.STOPPING:
                self.__stop(job)  # Set to STOPPED
            if job.job_runner_name is not None:
                job_wrapper = JobWrapper(job, self, use_persisted_destination=True)
                self.dispatcher.stop(job, job_wrapper)  # Tell runner to kill
```

**Biomate Usage:**
- Frontend can stop workflows via chat
- Jobs transition to STOPPED or ERROR state
- No resume capability

---

## Part 3: Unused Galaxy Queue Features

### Summary Matrix

| Feature | Available | Biomate Use | Gap |
|---------|-----------|-------------|-----|
| Job queuing | ✅ Yes | ✅ Full | - |
| Job dispatch | ✅ Yes | ✅ Full | - |
| Concurrent limits | ✅ Yes | ✅ Full | - |
| Pause/resume | ✅ Yes | ⚠️ Partial | No resume API |
| Priority levels | ✅ Yes | ❌ None | No prioritization |
| Job dependencies | ✅ Yes | ✅ Via workflows | No explicit API |
| Automatic retry | ✅ Yes | ❌ None | Not exposed to tasks |
| Pause on quota | ✅ Yes | ✅ Full | - |
| Pause on walltime | ✅ Yes | ✅ Full | - |
| Resource allocation | ✅ Yes | ⚠️ Limited | No selector UI |
| Handler assignment | ✅ Yes | ✅ Full | - |
| Task parallelization | ✅ Yes | ❌ None | Not exposed |
| Dynamic destination | ✅ Yes | ⚠️ Tool-level | Not task-level |

---

### 3.1 Multi-Level Job Prioritization

**Where:** `/home/yzhang/biomate/backend/lib/galaxy/jobs/handler.py` (lines 477-493)

**What's Available:**
- Ranking system with `RANK().OVER()` SQL window function
- Per-user fairness (`PARTITION BY user_id`)
- Ready window size limit (default 100)
- Order by job ID (FIFO per user)

**Example:**
```python
rank = func.rank().over(
    partition_by=coalesce_exp,
    order_by=model.Job.table.c.id
).label("rank")
```

**Why Biomate Doesn't Use:**
- No priority level column in Job table for Biomate
- Would require tool configuration or user request
- No UI to set priority in conversation

**Could Enable:** "Process this urgent task ASAP" via priority hints

---

### 3.2 Automatic Job Retry on Failure

**Where:** `/home/yzhang/biomate/backend/lib/galaxy/jobs/__init__.py` (lines 374-385)

**What's Available:**
```python
default_resubmits = []
default_resubmit_condition = self.app.config.default_job_resubmission_condition
if default_resubmit_condition:
    default_resubmits.append(
        dict(
            condition=default_resubmit_condition,
            handler=self.app.config.default_job_resubmission_handler,
        )
    )
```

**Features:**
- Conditional resubmission (e.g., `tool_exit_code == -1`)
- Delay between retries (`__resubmit_delay_seconds`)
- Handler-specific retry logic
- Resubmit counter tracking

**Example Config:**
```yaml
job_config:
  default_job_resubmission_condition: "tool_exit_code == -1"  # SIGTERM
  default_job_resubmission_handler: "default"
```

**Why Biomate Doesn't Use:**
- Not exposed via conversation API
- Requires system-level configuration
- Tool must support the condition

**Could Enable:** "Retry up to 3 times if it fails" in task definition

---

### 3.3 Explicit Resume Capability

**Where:** `/home/yzhang/biomate/backend/lib/galaxy/jobs/__init__.py` (lines 1561-1573, 1575-1584)

**What's Available:**
```python
def pause(self, job=None, message=None):
    """Pause job execution without losing state."""
    if job.state in (job.states.NEW, job.states.QUEUED):
        # Pause outputs
        for dataset_assoc in job.output_datasets + job.output_library_datasets:
            dataset_assoc.dataset.dataset.state = dataset_assoc.dataset.dataset.states.PAUSED
        job.set_state(job.states.PAUSED)

def is_ready_for_resubmission(self, job=None):
    """Check if paused job can resume."""
    if "__resubmit_delay_seconds" in job.destination_params:
        delay = float(job.destination_params["__resubmit_delay_seconds"])
        if job.seconds_since_updated < delay:
            return False
    return True
```

**Pause Triggers (Automatic):**
- User hits walltime limit
- User exceeds disk quota
- Input dataset fails
- Input dataset deleted

**Resume Triggers (Manual):**
- User deletes offending dataset (for INPUT_DELETED)
- User fixes quota (for QUOTA_EXCEEDED)
- Admin resets job state

**Why Biomate Doesn't Use:**
- No explicit resume API exposed
- No UI to manually resume paused jobs
- Jobs stay paused until root cause fixed

**Could Enable:** Explicit "Resume this paused task" in chat

---

### 3.4 Resource Group Selection

**Where:** `/home/yzhang/biomate/backend/lib/galaxy/jobs/__init__.py` (lines 542-546)

**What's Available:**
```python
resources = job_config_dict.get("resources", {})
self.default_resource_group = resources.get("default", None)
for group_id, fields in resources.get("groups", {}).items():
    self.resource_groups[group_id] = fields
```

**Example Config:**
```yaml
resources:
  default: base
  groups:
    base:
      - memory
      - cores
    high_memory:
      - memory
      - cores
      - gpu_select
```

**In Tool Definition:**
```xml
<tool id="bwa_align">
  <resources group="high_memory" />
  <inputs>
    <param name="memory">16G</param>
    <param name="cores">8</param>
    <param name="gpu_select">1</param>
  </inputs>
</tool>
```

**Why Biomate Doesn't Use:**
- Requires tool-level definition
- Not exposed via task submission API
- Would need conversation parser

**Could Enable:** "Run this with high memory: 16G RAM, 8 cores"

---

### 3.5 Task Parallelization (Job Splitting)

**Where:** `/home/yzhang/biomate/backend/lib/galaxy/jobs/runners/tasks.py`

**What's Available:**
- Automatic job splitting into parallel tasks
- Task runner plugin
- Task dependency tracking
- Parallel task execution

**How It Works:**
```python
# Job can be split if:
# 1. Tool supports splitting (splitter defined)
# 2. Input has multiple datasets
# 3. Job runner is not Pulsar (doesn't support)

if job_wrapper.can_split() and runner.runner_name != "PulsarJobRunner":
    runner = self.job_runners["tasks"]  # Use task runner
    runner.put(job_wrapper)  # Tasks executed in parallel
```

**Why Biomate Doesn't Use:**
- Requires tool support for splitting
- Not exposed via conversation
- Transparent if enabled

---

## Part 4: Recommendations to Leverage Galaxy Queue Better

### Priority 1: Resume Capability (High Impact, Medium Effort)

**Current Gap:** Jobs can pause but not resume programmatically

**Implementation:**
```python
# Add to /backend/lib/galaxy/jobs/manager.py
def resume(self, job, message=None):
    """Resume a paused job."""
    if job.state == job.states.PAUSED:
        # Change job state back to NEW
        job.set_state(job.states.NEW)
        # Re-enqueue for processing
        self.job_handler.job_queue.put(job.id, job.tool_id)
        return True
    return False
```

**Frontend API:**
```typescript
// POST /api/galaxy/jobs/{jobId}/resume
await galaxyAPIBackend.resumeJob(jobId);
```

**Chat Integration:**
```
User: "Resume the paused analysis task"
→ Find paused job in current session
→ Call resume API
→ Re-enqueue for execution
```

**Effort:** 8-10 hours
**Impact:** Enable pause/resume workflows without data loss

---

### Priority 2: Task Prioritization API (Medium Impact, Medium Effort)

**Current Gap:** No way to prioritize urgent tasks

**Implementation:**
```python
# Add priority column to Job model (optional, system-level)
# Or use destination params for task-level priority hint

def set_task_priority(self, job, priority="normal"):
    """Set priority hint for job scheduling."""
    # priority: "low", "normal", "high", "critical"
    job.params["__priority"] = priority
    if priority == "critical":
        # Could bump ready_window_size or move to front
        # Requires handler changes
    self.sa_session.add(job)
    self.sa_session.commit()
```

**Chat Integration:**
```
User: "This analysis is urgent, prioritize it"
→ Extract intent: priority = "high"
→ Set priority on current job
→ Handler respects in scheduling
```

**Effort:** 12-15 hours
**Impact:** Urgent tasks processed sooner

---

### Priority 3: Explicit Retry Configuration (Low Impact, Low Effort)

**Current Gap:** Retry only configurable at system level

**Implementation:**
```python
# Add to job submission payload
{
  "tool_id": "bwa_align",
  "inputs": {...},
  "retry": {
    "max_attempts": 3,
    "condition": "tool_exit_code == -1 or tool_exit_code == 124",
    "delay_seconds": 60
  }
}
```

**Chat Integration:**
```
User: "Run with automatic retry if it times out"
→ Parse retry requirement
→ Add to job params
→ Handler respects during resubmission
```

**Effort:** 4-6 hours
**Impact:** Better fault tolerance for flaky tools

---

### Priority 4: Resource Allocation Selector (Medium Impact, High Effort)

**Current Gap:** Resource selection requires tool definition

**Implementation:**
```python
# Add resource selection to submission API
{
  "tool_id": "bwa_align",
  "inputs": {...},
  "resource_select": {
    "memory": "16G",
    "cores": "8",
    "gpu": "1"
  }
}
```

**Handler Enhancement:**
```python
# Modify destination selection logic
if job.params.get("resource_select"):
    resources = job.params["resource_select"]
    # Find destination matching resources
    # Prefer destinations with matching tags/params
    job_destination = self._select_destination_by_resources(job, resources)
```

**Chat Integration:**
```
User: "Run this with high memory (16GB)"
→ Parse resource request
→ Find GPU destination
→ Submit with resource selection
```

**Effort:** 20-25 hours
**Impact:** Fine-grained control over execution environment

---

### Priority 5: Explicit Job Dependencies API (Low Impact, High Effort)

**Current Gap:** Dependencies only via workflow datasets

**Implementation:**
```python
# Add dependency tracking to Job model
{
  "tool_id": "analyze_results",
  "inputs": {...},
  "depends_on": [job_id_1, job_id_2],
  "wait_for_all": true
}
```

**Handler Enhancement:**
```python
# Check explicit dependencies in addition to dataset dependencies
def __check_job_state(self, job):
    # Check dataset dependencies (existing)
    if not all_inputs_ready(job):
        return JOB_WAIT
    
    # Check explicit job dependencies (new)
    if job.explicit_dependencies:
        for dep_job_id in job.explicit_dependencies:
            dep_job = self.sa_session.query(model.Job).get(dep_job_id)
            if dep_job.state != model.Job.states.OK:
                return JOB_WAIT
    
    return JOB_READY
```

**Effort:** 15-18 hours
**Impact:** Multi-step task chains without workflow

---

## Part 5: Code Evidence by Feature

### Job Submission & Enqueue
```
File: /home/yzhang/biomate/backend/lib/galaxy/jobs/manager.py
Lines: 50-86 (enqueue method)
Lines: 44-46 (queue callback)

File: /home/yzhang/biomate/backend/lib/galaxy/jobs/handler.py
Lines: 250-290 (JobHandlerQueue init & start)
Lines: 401-587 (__handle_waiting_jobs)
```

### Job Cancellation
```
File: /home/yzhang/biomate/backend/lib/galaxy/jobs/manager.py
Lines: 88-98 (stop method)

File: /home/yzhang/biomate/backend/lib/galaxy/jobs/handler.py
Lines: 1053-1182 (JobHandlerStopQueue)
Lines: 1084-1097 (__delete and __stop methods)
```

### Concurrent Job Limits
```
File: /home/yzhang/biomate/backend/lib/galaxy/jobs/__init__.py
Lines: 314-330 (JobLimits configuration)
Lines: 587-609 (Limit parsing)

File: /home/yzhang/biomate/backend/lib/galaxy/jobs/handler.py
Lines: 909-930 (increase_running_job_count)
Lines: 932-985 (__check_user_jobs)
Lines: 1007-1028 (__check_destination_jobs)
```

### Pause/Resume
```
File: /home/yzhang/biomate/backend/lib/galaxy/jobs/__init__.py
Lines: 1561-1573 (pause method)
Lines: 1575-1584 (is_ready_for_resubmission)
Lines: 1803-1808 (_pause_job_if_over_quota)

File: /home/yzhang/biomate/backend/lib/galaxy/jobs/handler.py
Lines: 564-568 (pause on walltime limit)
Lines: 649-656 (pause dependent jobs)
```

### Retry on Failure
```
File: /home/yzhang/biomate/backend/lib/galaxy/jobs/__init__.py
Lines: 374-385 (default_resubmits config)
Lines: 745-754 (get_resubmits parsing)
Lines: 1575-1584 (is_ready_for_resubmission)

File: /home/yzhang/biomate/backend/lib/galaxy/jobs/handler.py
Lines: 530-537 (Resubmit jobs processing)
```

### Job State Tracking
```
File: /home/yzhang/biomate/backend/lib/galaxy/jobs/handler.py
Lines: 49-70 (Job state constants)
Lines: 668-706 (__check_job_state)
Lines: 1622-1625 (get_state)
Lines: 1595-1620 (change_state)
```

### Job Destinations & Resources
```
File: /home/yzhang/biomate/backend/lib/galaxy/jobs/__init__.py
Lines: 131-155 (JobDestination class)
Lines: 486-536 (Destination configuration parsing)
Lines: 542-546 (Resource group configuration)
```

---

## Summary: What Biomate Should Leverage More

**Immediate (Low Hanging Fruit):**
1. Expose pause/resume API to conversation
2. Add basic job priority hints
3. Expose resource selection UI

**Short Term (1-2 weeks):**
4. Implement explicit retry configuration
5. Add resource group selector
6. Create task priority inference from conversation

**Medium Term (1-2 months):**
7. Implement explicit job dependency API
8. Add task parallelization selector
9. Build proactive pause/resume notifications

**Long Term (Future):**
10. ML-based optimal destination selection
11. Adaptive resource allocation learning
12. Workflow performance optimization hints

---

## Conclusion

Galaxy provides a **production-grade, sophisticated job queue system** with extensive features for scheduling, prioritization, resource management, and fault tolerance. Biomate currently leverages the core functionality (queuing, dispatch, limits, cancellation) but leaves many advanced features untapped.

**Key Opportunities:**
- Enable pause/resume for user-friendly interruption
- Add priority hints for urgent tasks
- Expose resource selection for fine-grained control
- Implement retry policies for robustness
- Support explicit task dependencies

**Effort vs Impact:**
- Quick wins: Resume, basic priority → 2-3 weeks
- Medium effort: Full resource selection → 4-6 weeks
- Architectural: Task dependencies → 2+ months

**Recommendation:** Start with resume capability and task priority (high impact, achievable in 2-3 weeks), then evaluate resource selection based on user feedback.

