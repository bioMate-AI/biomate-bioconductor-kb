import { describe, expect, it } from "vitest"
import {
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
