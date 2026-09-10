/**
 * Component tests for LanePreview + its useServerLane hook (spec 06 §6.2,
 * spec 00 §2.2). The laneForText heuristic is covered separately in
 * lane-preview.test.ts; this file covers the STATEFUL, async server-arbiter
 * behaviour the heuristic tests cannot reach:
 *
 *   (a) the server upgrades the strip from the local Instant heuristic to Cloud
 *   (b) a rejected fetch leaves the strip on the local heuristic (no crash)
 *   (c) a { success: false } response is ignored (stays local)
 *   (d) a server `why` beginning with "reads as …" is NOT double-prefixed
 *       ("reads as reads as …" — a shipped dev bug fix with no test)
 *
 * The arbiter is advisory + non-blocking: it only ever *upgrades* what the
 * component already shows from laneForText, and it must never throw.
 *
 * fetch is mocked at the global boundary (the hook's only side effect). Fake
 * timers drive the 350 ms debounce deterministically.
 */

import React from "react";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, act } from "@testing-library/react";
import { LanePreview } from "./lane-preview";

// An input whose LOCAL heuristic is unambiguously Instant (a "what is known"
// question), so any Cloud strip we see must have come from the server arbiter.
const INSTANT_TEXT = "What is the evidence linking TNF to disease?";

beforeEach(() => {
  vi.useFakeTimers();
});

afterEach(() => {
  vi.runOnlyPendingTimers();
  vi.useRealTimers();
  vi.restoreAllMocks();
});

function mockClassify(
  impl: (t: string) => Promise<Partial<Response>> | Partial<Response>,
) {
  global.fetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = typeof input === "string" ? input : input.toString();
    if (!url.includes("/api/route/classify")) {
      return { ok: false, status: 404, json: async () => ({}) } as Response;
    }
    const body = JSON.parse((init?.body as string) || "{}");
    return (await impl(body.text)) as Response;
  }) as unknown as typeof fetch;
}

describe("LanePreview — useServerLane arbiter", () => {
  it("(a) server 'cloud' upgrades the strip from the local Instant heuristic to Cloud", async () => {
    mockClassify(() => ({
      ok: true,
      status: 200,
      json: async () => ({ success: true, lane: "cloud", why: "a validated workflow request" }),
    }));

    render(<LanePreview text={INSTANT_TEXT} />);

    // Immediately (before the debounced fetch), the local heuristic shows Instant.
    expect(screen.getByTestId("lane-preview").getAttribute("data-lane")).toBe("instant");

    // Fire the 350 ms debounce and flush the awaited fetch microtasks.
    await act(async () => {
      await vi.advanceTimersByTimeAsync(400);
    });

    // The server verdict upgrades the strip to Cloud (state already flushed by
    // advanceTimersByTimeAsync — no waitFor, which would stall under fake timers).
    expect(screen.getByTestId("lane-preview").getAttribute("data-lane")).toBe("cloud");
    expect(screen.getByTestId("lane-preview-chip").textContent).toContain("Cloud");
    // And the classify endpoint was actually hit.
    expect(global.fetch).toHaveBeenCalled();
  });

  it("(b) a rejected fetch leaves the strip on the local heuristic (no crash)", async () => {
    mockClassify(() => {
      throw new Error("network down");
    });

    render(<LanePreview text={INSTANT_TEXT} />);
    expect(screen.getByTestId("lane-preview").getAttribute("data-lane")).toBe("instant");

    await act(async () => {
      await vi.advanceTimersByTimeAsync(400);
    });

    // Stays on the local Instant heuristic — the component did not throw or blank.
    expect(screen.getByTestId("lane-preview")).toBeTruthy();
    expect(screen.getByTestId("lane-preview").getAttribute("data-lane")).toBe("instant");
    expect(screen.getByTestId("lane-preview-chip").textContent).toContain("Instant");
  });

  it("(c) a { success: false } response is ignored — strip stays local", async () => {
    mockClassify(() => ({
      ok: true,
      status: 200,
      // Backend explicitly declines to classify; the strip must NOT flip to cloud.
      json: async () => ({ success: false, lane: "cloud", why: "should be ignored" }),
    }));

    render(<LanePreview text={INSTANT_TEXT} />);
    await act(async () => {
      await vi.advanceTimersByTimeAsync(400);
    });

    // success:false → ignored → local Instant remains.
    expect(screen.getByTestId("lane-preview").getAttribute("data-lane")).toBe("instant");
    expect(screen.getByTestId("lane-preview-read").textContent).not.toContain("should be ignored");
  });

  it("(d) a server why beginning with 'reads as' is not double-prefixed", async () => {
    mockClassify(() => ({
      ok: true,
      status: 200,
      json: async () => ({ success: true, lane: "cloud", why: "reads as a workflow request" }),
    }));

    render(<LanePreview text={INSTANT_TEXT} />);
    await act(async () => {
      await vi.advanceTimersByTimeAsync(400);
    });

    expect(screen.getByTestId("lane-preview").getAttribute("data-lane")).toBe("cloud");
    const read = screen.getByTestId("lane-preview-read").textContent || "";
    // The render prefixes "reads as " itself; the leading "reads as " in `why`
    // must be stripped so it does NOT double up.
    expect(read).toContain("reads as a workflow request");
    expect(read).not.toContain("reads as reads as");
    // Exactly one "reads as " occurrence.
    expect((read.match(/reads as/gi) || []).length).toBe(1);
  });
});
