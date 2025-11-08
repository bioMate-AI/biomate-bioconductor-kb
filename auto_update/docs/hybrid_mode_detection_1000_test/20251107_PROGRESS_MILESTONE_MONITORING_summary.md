# Proactive Progress Milestone Monitoring Implementation

**Date:** 2025-11-07
**Feature:** Automatic Progress Milestone Detection and Reporting
**Status:** ✅ Backend Complete, UI Enhancement Optional
**Effort:** 1.5 hours

---

## What Was Implemented

### Feature Overview
Implemented automatic detection and reporting of workflow execution progress at key milestones (25%, 50%, 75%, 100%) with ETA calculations, matching Claude Code's proactive progress monitoring capability.

### Gap Addressed
**Problem:** Biomate did not proactively report progress during long-running workflows.
**Solution:** Added milestone detection based on step completion percentage with ETA calculations using historical step timing data.

---

## Implementation Details

### 1. Enhanced Poller Interface (`galaxy-state-poller.ts:20-30`)

#### Added Tracking Fields
```typescript
export interface InvocationPoller {
  invocationId: string;
  workflowId: string;
  lastState: GalaxyWorkflowInvocation | null;
  isActive: boolean;
  failureCount: number;
  // Progress milestone tracking
  milestonesReported: Set<number>; // Track which milestones (25, 50, 75, 100) have been reported
  stepStartTimes: Map<string, number>; // Track when each step started (for ETA)
  stepCompletionTimes: Map<string, number>; // Track how long each step took
}
```

**Features:**
- ✅ Tracks which milestones have been reported (prevents duplicates)
- ✅ Records step start times for ETA calculation
- ✅ Records step completion times for average calculation

---

### 2. Step Timing Tracking (`galaxy-state-poller.ts:234-261`)

#### Enhanced State Change Detection
```typescript
// Track step start time
if (newStep.state === 'running') {
  poller.stepStartTimes.set(newStep.id, Date.now());
}

// Track completion time when step finishes
if ((newStep.state === 'ok' || newStep.state === 'error') && poller.stepStartTimes.has(newStep.id)) {
  const startTime = poller.stepStartTimes.get(newStep.id)!;
  const completionTime = Date.now() - startTime;
  poller.stepCompletionTimes.set(newStep.id, completionTime);
}
```

**What It Does:**
- Records timestamp when each step starts running
- Calculates elapsed time when step completes
- Stores completion times for ETA calculations

---

### 3. Milestone Detection Logic (`galaxy-state-poller.ts:274-326`)

#### `detectProgressMilestones()` Method

**Algorithm:**
1. Count completed steps (state = 'ok' or 'error')
2. Calculate progress percentage: `(completedSteps / totalSteps) * 100`
3. Check if any milestone threshold (25, 50, 75, 100) has been reached
4. Only report each milestone once (using `milestonesReported` set)
5. Calculate ETA from average step completion time
6. Emit milestone event via SSE

**Code:**
```typescript
private detectProgressMilestones(poller: InvocationPoller, invocation: GalaxyWorkflowInvocation): void {
  const totalSteps = invocation.steps.length;
  if (totalSteps === 0) return;

  // Count completed steps (ok or error)
  const completedSteps = invocation.steps.filter(
    step => step.state === 'ok' || step.state === 'error'
  ).length;

  // Calculate progress percentage (0-100)
  const progressPercent = Math.floor((completedSteps / totalSteps) * 100);

  // Define milestone thresholds
  const milestones = [25, 50, 75, 100];

  // Check each milestone
  for (const milestone of milestones) {
    if (progressPercent >= milestone && !poller.milestonesReported.has(milestone)) {
      poller.milestonesReported.add(milestone);

      // Calculate ETA
      const eta = this.calculateETA(poller, completedSteps, totalSteps);

      // Build milestone message
      const message = milestone === 100
        ? `✓ Workflow complete! (${completedSteps}/${totalSteps} steps)`
        : `✓ ${milestone}% complete (${completedSteps}/${totalSteps} steps)${eta ? ` - ${eta}` : ''}`;

      // Emit milestone event
      this.emitUpdate({
        type: 'progress_milestone',
        invocation_id: invocation.id,
        timestamp: new Date().toISOString(),
        data: {
          progress: milestone / 100,
          completedSteps,
          totalSteps,
          eta: eta || 'Calculating...',
          message,
          milestone,
        },
      });

      console.log(`[Milestone] Invocation ${invocation.id}: ${message}`);
    }
  }
}
```

**Features:**
- ✅ Detects 25%, 50%, 75%, 100% completion
- ✅ Only reports each milestone once
- ✅ Includes ETA in notification
- ✅ Logs to console for debugging
- ✅ Sends via SSE to UI

---

### 4. ETA Calculation (`galaxy-state-poller.ts:328-353`)

#### `calculateETA()` Method

**Algorithm:**
1. Requires at least 2 completed steps for accuracy
2. Calculates average step completion time from historical data
3. Estimates remaining time: `avgStepTime * remainingSteps`
4. Returns formatted human-readable ETA

**Code:**
```typescript
private calculateETA(poller: InvocationPoller, completedSteps: number, totalSteps: number): string | null {
  // Need at least 2 completed steps to calculate average
  if (poller.stepCompletionTimes.size < 2) {
    return null;
  }

  // Calculate average step completion time
  const completionTimes = Array.from(poller.stepCompletionTimes.values());
  const avgStepTime = completionTimes.reduce((sum, time) => sum + time, 0) / completionTimes.length;

  // Calculate remaining steps
  const remainingSteps = totalSteps - completedSteps;
  if (remainingSteps <= 0) {
    return 'Complete';
  }

  // Estimate remaining time
  const estimatedRemainingMs = avgStepTime * remainingSteps;

  // Format as human-readable ETA
  return `~${this.formatElapsedTime(estimatedRemainingMs)} remaining`;
}
```

**ETA Accuracy:**
- Uses actual step completion times (not estimates)
- Improves as more steps complete
- Accounts for variable step durations
- Returns null if insufficient data (<2 steps)

---

### 5. Type System Updates (`galaxy-types.ts:222-241`)

#### Updated `WorkflowExecutionUpdate` Interface

**Added Event Type:**
```typescript
export interface WorkflowExecutionUpdate {
  type: 'workflow_state' | 'step_state' | 'job_log' | 'error' | 'progress_milestone';
  invocation_id: string;
  timestamp: string;
  data: {
    // ... existing fields ...
    // Progress milestone fields
    progress?: number; // 0.25, 0.50, 0.75, 1.0
    completedSteps?: number;
    totalSteps?: number;
    eta?: string;
    message?: string;
    milestone?: number; // 25, 50, 75, 100
  };
}
```

**Features:**
- ✅ TypeScript type safety
- ✅ Optional fields for milestone data
- ✅ Clear documentation of value ranges

---

### 6. SSE Manager Integration (`workflow-sse.ts:53-56`)

#### Added Milestone Event Listener

**Code:**
```typescript
// Progress milestones
this.poller.on('progress_milestone', (update: WorkflowExecutionUpdate) => {
  this.broadcastToClients(update.invocation_id, update);
});
```

**Features:**
- ✅ Automatically broadcasts milestones to all connected UI clients
- ✅ No code changes needed in UI to receive events
- ✅ Works with existing SSE infrastructure

---

## How It Works

### Workflow Execution Flow

1. **User starts workflow** → Poller begins tracking invocation

2. **Step starts running** → `stepStartTimes.set(stepId, Date.now())`

3. **Step completes** → Calculate elapsed time, store in `stepCompletionTimes`

4. **After each state change** → Call `detectProgressMilestones()`
   - Count completed steps
   - Calculate progress %
   - Check if milestone threshold reached
   - If yes and not already reported:
     - Calculate ETA from average step time
     - Build milestone message
     - Emit via SSE
     - Log to console
     - Mark milestone as reported

5. **UI receives SSE event** → Display notification (optional enhancement)

---

## Event Format

### Progress Milestone SSE Event

**Event Type:** `progress_milestone`

**Example at 50% Completion:**
```json
{
  "type": "progress_milestone",
  "invocation_id": "abc123",
  "timestamp": "2025-11-07T18:30:00.000Z",
  "data": {
    "progress": 0.50,
    "completedSteps": 5,
    "totalSteps": 10,
    "eta": "~2m 30s remaining",
    "message": "✓ 50% complete (5/10 steps) - ~2m 30s remaining",
    "milestone": 50
  }
}
```

**Example at 100% Completion:**
```json
{
  "type": "progress_milestone",
  "invocation_id": "abc123",
  "timestamp": "2025-11-07T18:35:00.000Z",
  "data": {
    "progress": 1.0,
    "completedSteps": 10,
    "totalSteps": 10,
    "eta": "Complete",
    "message": "✓ Workflow complete! (10/10 steps)",
    "milestone": 100
  }
}
```

---

## Console Output

### Milestone Logging

**Example Console Output:**
```
[Milestone] Invocation abc123: ✓ 25% complete (3/12 steps) - ~8m 15s remaining
[Milestone] Invocation abc123: ✓ 50% complete (6/12 steps) - ~5m 30s remaining
[Milestone] Invocation abc123: ✓ 75% complete (9/12 steps) - ~2m 45s remaining
[Milestone] Invocation abc123: ✓ Workflow complete! (12/12 steps)
```

**Benefits:**
- Easy debugging during development
- Visible progress in server logs
- Helps diagnose timing issues

---

## Testing

### Manual Testing Procedure

1. **Start Biomate server:**
   ```bash
   cd /home/yzhang/biomate/frontend
   npm run dev
   ```

2. **Open browser console** (F12)

3. **Submit a workflow** with at least 8 steps (to see multiple milestones)

4. **Monitor server console** for milestone logs:
   ```
   [Milestone] Invocation xyz: ✓ 25% complete (2/8 steps) - ~45s remaining
   ```

5. **Check browser SSE connection** for milestone events:
   - Open Network tab → Filter by "sse"
   - Look for `progress_milestone` events

6. **Verify milestone uniqueness** - each milestone should only be reported once

---

### Test Scenarios

1. **Small workflow (4 steps):**
   - Should see: 25%, 50%, 75%, 100%
   - ETA should update as steps complete

2. **Medium workflow (12 steps):**
   - Should see all 4 milestones
   - ETA should be reasonably accurate

3. **Workflow with variable step times:**
   - ETA should adapt to changing average times
   - Should still report milestones at correct percentages

4. **Workflow that fails mid-execution:**
   - Should count failed steps in progress
   - Should still report milestones up to point of failure

---

## Benefits

### Matches Claude Code Behavior
- ✅ **Proactive reporting** - User doesn't need to ask for progress
- ✅ **Milestone-based** - Reports at 25%, 50%, 75%, 100%
- ✅ **ETA calculation** - Estimates time remaining
- ✅ **Automatic** - No user intervention required

### Technical Advantages
- ✅ Uses actual execution data (not estimates)
- ✅ Minimal overhead (only checks on state changes)
- ✅ No fake progress bars (real completion percentage)
- ✅ Integrates seamlessly with existing SSE infrastructure
- ✅ TypeScript type-safe

---

## Future Enhancements (Optional)

### UI Display Options

1. **Toast Notifications** (~30 min)
   - Install toast library (e.g., `sonner`)
   - Show toast on milestone events
   - Auto-dismiss after 5 seconds

2. **Progress Bar** (~1 hour)
   - Add progress bar component above timeline
   - Update in real-time based on milestone events
   - Show ETA below progress bar

3. **Milestone Timeline** (~2 hours)
   - Add visual milestone markers to execution timeline
   - Show estimated vs actual completion times
   - Highlight current progress point

### Advanced Features

1. **Predictive ETA** (~4 hours)
   - Use machine learning on historical workflow data
   - Factor in tool-specific execution patterns
   - Improve accuracy for recurring workflows

2. **Milestone Customization** (~2 hours)
   - Allow users to configure milestone percentages
   - Support custom milestone events (e.g., "After data loading")
   - Configurable notification preferences

---

## Code Statistics

**Files Modified:** 3
- `galaxy-state-poller.ts`: +79 lines
- `galaxy-types.ts`: +7 lines
- `workflow-sse.ts`: +4 lines

**Total Addition:** ~90 lines of code
**Dependencies Added:** 0
**Breaking Changes:** 0

---

## Integration with Pause/Resume

### Combined Capabilities

Users can now:
1. **Monitor progress** automatically at 25%, 50%, 75%
2. **Pause workflow** if needed (e.g., resource constraints)
3. **Resume workflow** when ready
4. **See ETA** to decide whether to pause or let it run

**Example Scenario:**
```
[Milestone] ✓ 25% complete (3/12 steps) - ~15m remaining
// User sees it will take 15 more minutes
// User pauses to run urgent analysis
// User resumes later
[Milestone] ✓ 50% complete (6/12 steps) - ~7m remaining
```

---

## Comparison with Claude Code

### Claude Code Behavior
- Reports progress periodically during long tasks
- Shows estimated completion time
- Proactive without user prompting

### Biomate Now Has
- ✅ Milestone-based progress reporting (25%, 50%, 75%, 100%)
- ✅ ETA calculation from actual step times
- ✅ Proactive SSE notifications
- ✅ Console logging for visibility

### Differences
- **Claude Code:** Reports periodically (time-based)
- **Biomate:** Reports at milestones (percentage-based)
- **Both:** Proactive, include ETA, automatic

---

## Related Documents

- **Gap Analysis:** `20251107_1727_TASK_MANAGEMENT_ANALYSIS_interruption_progress_monitoring.md`
- **Pause/Resume:** `20251107_PAUSE_RESUME_IMPLEMENTATION_summary.md`
- **Galaxy Queue:** `20251107_GALAXY_QUEUE_SYSTEM_INTEGRATION_ANALYSIS.md`

---

## Summary

**What We Built:**
Automatic progress milestone detection with ETA calculation that proactively notifies users at 25%, 50%, 75%, and 100% completion.

**How It Works:**
1. Poller tracks step start/completion times
2. After each state change, calculates progress percentage
3. Detects milestone thresholds (25%, 50%, 75%, 100%)
4. Calculates ETA from average step completion time
5. Emits SSE event with milestone message and ETA
6. Logs to console for visibility

**Impact:**
Addresses the second key gap in Claude Code comparison - proactive progress reporting with statistics and ETA during long-running tasks.

**Next Step:**
Optional UI enhancement to display milestone notifications as toasts or in a progress panel.

---

**Document Version:** 1.0
**Last Updated:** 2025-11-07 19:00
**Status:** Backend complete, UI enhancement optional
