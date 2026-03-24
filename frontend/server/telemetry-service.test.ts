import { describe, expect, it } from "vitest";
import { aggregateConfusionEvents } from "./telemetry-confusion";

describe("telemetry-service confusion triage aggregation", () => {
  it("groups by rootRunId and aggregates counts, signals, and identifiers", () => {
    const rows = aggregateConfusionEvents(
      [
        {
          timestamp: new Date("2026-03-05T05:50:00.000Z"),
          signal: "output_dead_end",
          severity: "high",
          runId: "run-1",
          rootRunId: "root-1",
          sessionId: "sess-1",
        },
        {
          timestamp: new Date("2026-03-05T05:50:10.000Z"),
          signal: "retry_without_progress",
          severity: "high",
          runId: "run-1",
          rootRunId: "root-1",
          sessionId: "sess-1",
        },
        {
          timestamp: new Date("2026-03-05T05:50:20.000Z"),
          signal: "output_dead_end",
          severity: "medium",
          runId: "run-2",
          rootRunId: "root-2",
          sessionId: "sess-2",
        },
      ],
      10
    );

    expect(rows).toHaveLength(2);
    expect(rows[0].rootRunId).toBe("root-1");
    expect(rows[0].totalSignals).toBe(2);
    expect(rows[0].signalsByType).toEqual({
      output_dead_end: 1,
      retry_without_progress: 1,
    });
    expect(rows[0].runIds).toEqual(["run-1"]);
    expect(rows[0].sessionIds).toEqual(["sess-1"]);
    expect(rows[0].latestSeverity).toBe("high");
  });

  it("falls back to runId when rootRunId is missing and applies limit", () => {
    const rows = aggregateConfusionEvents(
      [
        {
          timestamp: new Date("2026-03-05T05:00:00.000Z"),
          signal: "output_dead_end",
          runId: "run-A",
          sessionId: "sess-A",
        },
        {
          timestamp: new Date("2026-03-05T05:01:00.000Z"),
          signal: "output_dead_end",
          runId: "run-B",
          sessionId: "sess-B",
        },
        {
          timestamp: new Date("2026-03-05T05:02:00.000Z"),
          signal: "retry_without_progress",
          runId: "run-B",
          sessionId: "sess-B",
        },
      ],
      1
    );

    expect(rows).toHaveLength(1);
    expect(rows[0].rootRunId).toBe("run-B");
    expect(rows[0].totalSignals).toBe(2);
  });
});
