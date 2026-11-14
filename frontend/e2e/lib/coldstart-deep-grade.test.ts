import { describe, expect, it } from "vitest";
import { failedRunContentOk, gradeColdstartDeep } from "./coldstart-deep-grade";

describe("gradeColdstartDeep", () => {
  it("grades cryo blocked Confirm as BLOCKED_REQUIRED", () => {
    expect(
      gradeColdstartDeep({
        launch: { clicked: false, reason: "confirm_blocked_required" },
        terminal: { status: "n/a" },
        after: null,
        useCasePass: false,
      }),
    ).toBe("BLOCKED_REQUIRED");
  });

  it("does not call diagnosisOnly alone DISHONEST when RUN FAILED strip exists", () => {
    expect(
      gradeColdstartDeep({
        launch: { clicked: true, reason: "confirm" },
        terminal: {
          status: "failed",
          error:
            "RUN FAILED Process GENERATE_REINVENT4 (reinvent4_sampling) failed: Essential container in task exited — ERROR: REINVENT4 CLI/package not found in container",
        },
        after: {
          afterShell: true,
          diagnosisOnly: true,
          findingsOk: false,
          outputsOk: false,
          failSnippet:
            "RUN FAILED Process GENERATE_REINVENT4 (reinvent4_sampling) failed: ERROR: REINVENT4 CLI/package not found in container",
        },
        useCasePass: false,
      }),
    ).toBe("HONEST_FAIL");
  });

  it("grades spinner-on-fail as DISHONEST_FAIL", () => {
    expect(
      gradeColdstartDeep({
        launch: { clicked: true, reason: "confirm" },
        terminal: { status: "failed" },
        after: { stuckInProgress: true, afterShell: true },
        useCasePass: false,
      }),
    ).toBe("DISHONEST_FAIL");
  });

  it("grades completed use-case as REAL_PASS", () => {
    expect(
      gradeColdstartDeep({
        launch: { clicked: true, reason: "confirm" },
        terminal: { status: "completed" },
        after: { afterShell: true, outputsOk: true },
        useCasePass: true,
      }),
    ).toBe("REAL_PASS");
  });

  it("grades Confirm click that never started a run as NO_LAUNCH", () => {
    expect(
      gradeColdstartDeep({
        launch: { clicked: false, reason: "confirm_noop" },
        terminal: { status: "n/a", error: "confirm_noop_no_run" },
        after: null,
        useCasePass: false,
      }),
    ).toBe("NO_LAUNCH");
  });

  it("grades timed-out Confirm with no runId as NO_LAUNCH (not soft pass)", () => {
    expect(
      gradeColdstartDeep({
        launch: { clicked: true, reason: "confirm" },
        terminal: { status: "n/a", error: "no runId", timedOut: true },
        after: { afterShell: true },
        useCasePass: false,
      }),
    ).toBe("NO_LAUNCH");
  });

  it("grades QC/pipeline paused without use-case pass as HONEST_FAIL (not soft)", () => {
    expect(
      gradeColdstartDeep({
        launch: { clicked: true, reason: "confirm" },
        terminal: { status: "paused" },
        after: { afterShell: true, outputsOk: true },
        useCasePass: false,
      }),
    ).toBe("HONEST_FAIL");
  });
});

describe("failedRunContentOk", () => {
  it("accepts fail strip without Findings tab", () => {
    expect(
      failedRunContentOk({
        afterShell: true,
        failSnippet: "RUN FAILED Process X failed: ERROR: boom",
        findingsOk: false,
        outputsOk: false,
      }),
    ).toBe(true);
  });

  it("rejects empty after-run on fail", () => {
    expect(failedRunContentOk({ afterShell: true, failSnippet: "" })).toBe(false);
  });
});
