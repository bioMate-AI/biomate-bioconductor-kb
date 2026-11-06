/**
 * Honest load-state coverage for the Projects page (fix for "mock-as-real" bug).
 *
 * The page previously substituted fabricated demo projects ("biomate AI", "LIS")
 * on BOTH an empty successful response and an API error. It must now:
 *  - show the honest "No projects yet" empty state on an empty success, and
 *  - show an error/retry state on an API failure,
 * never fabricated demo data.
 *
 * This is a unit/integration test (not E2E), so mocking fetch is permitted.
 */
import React from "react";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, waitFor, fireEvent } from "@testing-library/react";
import ProjectsPage from "./projects";

describe("ProjectsPage — honest load states", () => {
  beforeEach(() => { vi.restoreAllMocks(); });
  afterEach(() => { vi.clearAllMocks(); });

  it("empty successful response → honest empty state, NOT demo projects", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => ({
      ok: true,
      json: async () => [],
    })) as any);

    render(<ProjectsPage />);
    await waitFor(() => expect(screen.getByText(/No projects yet/i)).toBeInTheDocument());
    // Fabricated demo projects must not appear.
    expect(screen.queryByText(/biomate AI/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/^LIS$/)).not.toBeInTheDocument();
  });

  it("API error → error/retry state, NOT demo projects", async () => {
    const fetchMock = vi.fn(async () => ({ ok: false, status: 500, json: async () => ({}) }));
    vi.stubGlobal("fetch", fetchMock as any);

    render(<ProjectsPage />);
    await waitFor(() => expect(screen.getByTestId("projects-load-error")).toBeInTheDocument());
    expect(screen.queryByText(/biomate AI/i)).not.toBeInTheDocument();

    // Retry re-issues the request.
    const callsBefore = fetchMock.mock.calls.length;
    fireEvent.click(screen.getByTestId("button-retry-projects"));
    await waitFor(() => expect(fetchMock.mock.calls.length).toBeGreaterThan(callsBefore));
  });
});
