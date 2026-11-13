import { describe, expect, it } from "vitest"
import {
  describeOutputReadiness,
  outputReadinessLabel,
  runPrimaryCtaLabel,
  isActiveJob,
  workflowPanelProjectId,
  workflowPanelProjectName,
  runManagerListParams,
  runManagerSwitchHref,
  getRunPrimaryCta,
  getOutputReadinessHint,
  isRunNeedsAttention,
  mapRunBucket,
  type RunListItem,
} from "./run-manager-utils"

function buildRun(overrides: Partial<RunListItem> = {}): RunListItem {
  return {
    id: "run-1",
    workflowName: "RNA Workflow",
    execution: {
      status: "completed",
      ...overrides.execution,
    },
    ...overrides,
  }
}

describe("run-manager-utils", () => {
  it("maps execution statuses into base run buckets", () => {
    expect(mapRunBucket("running")).toBe("running")
    expect(mapRunBucket("paused")).toBe("queued")
    expect(mapRunBucket("failed")).toBe("failed")
    expect(mapRunBucket("cancelled")).toBe("completed")
  })

  it("flags failed runs as needs attention", () => {
    const run = buildRun({ execution: { status: "failed" } })
    expect(isRunNeedsAttention(run)).toBe(true)
  })

  it("flags completed runs with unmet readiness contract as needs attention", () => {
    const run = buildRun({
      execution: {
        status: "completed",
        artifactReadiness: {
          meetsContract: false,
          hasOutputs: true,
          totalOutputs: 2,
        },
      },
    })
    expect(isRunNeedsAttention(run)).toBe(true)
  })

  it("uses Resolve Inputs CTA when run error indicates missing prerequisites", () => {
    const run = buildRun({
      execution: {
        status: "failed",
        errorMessage: "Missing prerequisite: reference genome required input not configured",
      },
    })
    expect(getRunPrimaryCta(run)).toBe("Resolve Inputs")
  })

  it("uses Retry Search CTA for terminal failures without input hints", () => {
    const run = buildRun({
      execution: {
        status: "failed",
        errorMessage: "Remote service returned 502",
      },
    })
    expect(getRunPrimaryCta(run)).toBe("Retry Search")
  })

  it("uses View Outputs CTA when completed outputs are ready", () => {
    const run = buildRun({
      execution: {
        status: "completed",
        artifactReadiness: {
          meetsContract: true,
          visualizableCount: 1,
          downloadableCount: 2,
        },
      },
    })
    expect(getRunPrimaryCta(run)).toBe("View Outputs")
  })

  it("uses Open Logs CTA when completed run has no ready outputs", () => {
    const run = buildRun({
      execution: {
        status: "completed",
        artifactReadiness: {
          meetsContract: false,
          hasOutputs: false,
          totalOutputs: 0,
        },
      },
    })
    expect(getRunPrimaryCta(run)).toBe("Open Logs")
  })

  it("does not advertise outputs for an explicitly stdout-only workflow", () => {
    const run = buildRun({
      execution: {
        status: "completed",
        artifactReadiness: {
          meetsContract: true,
          completionContract: {
            mode: "stdout_only",
            state: "stdout_only",
            registeredOutputCount: 0,
            meetsContract: true,
          },
        },
      },
    })
    expect(getOutputReadinessHint(run)).toBe("completed via stdout/log output")
    expect(getRunPrimaryCta(run)).toBe("Open Logs")
    expect(isRunNeedsAttention(run)).toBe(false)
  })

  it("flags a generic completed run with no registered artifacts", () => {
    const run = buildRun({
      execution: {
        status: "completed",
        artifactReadiness: {
          hasOutputs: true, // an executor hint is not a registered artifact
          meetsContract: true,
          completionContract: {
            mode: "artifacts_required",
            state: "artifact_unavailable",
            registeredOutputCount: 0,
            meetsContract: false,
          },
        },
      },
    })
    expect(getOutputReadinessHint(run)).toBe("completed; result artifacts unavailable")
    expect(getRunPrimaryCta(run)).toBe("Open Logs")
    expect(isRunNeedsAttention(run)).toBe(true)
  })
})

it('keeps terminal history and unstarted drafts out of Running jobs', () => {
  for (const status of ['running', 'queued', 'paused', 'submitted']) expect(isActiveJob(buildRun({ execution: { status } }))).toBe(true)
  for (const status of ['completed', 'failed', 'cancelled', 'configuring', 'unknown']) expect(isActiveJob(buildRun({ execution: { status } }))).toBe(false)
})

describe('saved run identity and history scope', () => {
 it('never assigns the composer project to a saved run with another or unknown project', () => {
  expect(workflowPanelProjectId({ id: 'old', projectId: 'original' }, true, 'qa-current')).toBe('original');
  expect(workflowPanelProjectId({ id: 'old', projectId: null }, true, 'qa-current')).toBeUndefined();
  expect(workflowPanelProjectId(null, false, 'qa-current')).toBe('qa-current');
 });
 it('does not query all runs under the Current chat label when the chat is unsaved', () => {
  expect(runManagerListParams('current_chat', null)).toBeNull();
  expect(runManagerListParams('current_chat', 'chat1')?.get('chatSessionId')).toBe('chat1');
  expect(runManagerListParams('all_chats', null)?.has('chatSessionId')).toBe(false);
 });
 it('opens the owning chat (+ focusRun) when switching to a run from another session', () => {
  expect(runManagerSwitchHref({ runId: 'r1', runChatSessionId: 'chat-b', currentChatSessionId: 'chat-a' }))
    .toBe('/?session=chat-b&focusRun=r1');
  expect(runManagerSwitchHref({ runId: 'r1', runChatSessionId: 'chat-a', currentChatSessionId: 'chat-a' }))
    .toBeNull();
  expect(runManagerSwitchHref({ runId: 'r1', runChatSessionId: 'chat-b', currentChatSessionId: null }))
    .toBe('/?session=chat-b&focusRun=r1');
  expect(runManagerSwitchHref({ runId: 'r1', runChatSessionId: null, currentChatSessionId: 'chat-a' }))
    .toBeNull();
 });
});

it('resolves the saved project name only from its actual project ID', () => {
 const projects = [{ id: 'current', name: 'Current QA' }, { id: 'original', name: 'Original Study' }];
 expect(workflowPanelProjectName('original', projects)).toBe('Original Study');
 expect(workflowPanelProjectName(undefined, projects)).toBeUndefined();
 expect(workflowPanelProjectName('unknown', projects)).toBeUndefined();
});

describe("run manager display labels (UI language, not identifiers)", () => {
  it("maps CTA identifiers to labels; a failed run's card says it shows the failure", () => {
    expect(runPrimaryCtaLabel("Retry Search")).not.toBe("Retry Search")
    expect(runPrimaryCtaLabel("Open Logs")).not.toBe("Open Logs")
  })

  it("describes readiness structurally and labels it", () => {
    const run = { id: "r1", execution: { status: "completed" } } as any
    expect(describeOutputReadiness(run)).toEqual({ code: "check_artifacts" })
    expect(getOutputReadinessHint(run)).toBe("completed; check artifacts")
    expect(outputReadinessLabel(run)).toBeTruthy()
  })
})

describe("AWS Batch outputs count as outputs", () => {
  it("a completed Batch run with s3_output_files is not 'needs attention'", () => {
    const run = { id: "b1", execution: { status: "completed", nextflowStatus: { s3_output_files: [{ name: "metrics.json" }, { name: "model.pkl" }] } } } as any
    expect(describeOutputReadiness(run)).toEqual({ code: "detected", n: 2 })
    expect(isRunNeedsAttention(run)).toBe(false)
    expect(getRunPrimaryCta(run)).toBe("View Outputs")
  })
})
