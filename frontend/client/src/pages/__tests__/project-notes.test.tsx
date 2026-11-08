/**
 * ProjectNotesPage — RTL coverage for the Stream-A Notes surface.
 *
 * Covers: empty state on 404, markdown render on 200, refresh POST +
 * re-fetch, and Markdown download. Routing is shimmed via wouter's
 * Router with a static path so useRoute resolves :projectId without
 * mounting the full App.
 */
import React from "react";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { Router as WouterRouter } from "wouter";
import { memoryLocation } from "wouter/memory-location";
import ProjectNotesPage from "../project-notes";

const downloadAsMdMock = vi.fn();
vi.mock("@/lib/download-response", () => ({
  downloadAsMd: (...args: any[]) => downloadAsMdMock(...args),
}));

function renderAt(path: string) {
  const { hook } = memoryLocation({ path, static: true });
  return render(
    <WouterRouter hook={hook}>
      <ProjectNotesPage />
    </WouterRouter>,
  );
}

beforeEach(() => {
  vi.restoreAllMocks();
  downloadAsMdMock.mockReset();
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe("ProjectNotesPage", () => {
  it("renders the empty-state copy when GET returns 404", async () => {
    vi.spyOn(global, "fetch").mockResolvedValueOnce({
      ok: false,
      status: 404,
      json: async () => ({ error: "No synthesis yet" }),
    } as unknown as Response);

    renderAt("/projects/proj-xyz/notes");

    await waitFor(() => {
      expect(screen.getByTestId("notes-empty")).toBeInTheDocument();
    });
    expect(screen.getByTestId("button-refresh-synthesis")).toBeInTheDocument();
  });

  it("renders the markdown body when GET returns content", async () => {
    vi.spyOn(global, "fetch").mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({
        note: {
          id: "note-1",
          content: "# Hello synthesis\n\nFirst paragraph.",
          createdAt: "2026-06-19T10:00:00.000Z",
          source: "claude_inferred",
        },
      }),
    } as unknown as Response);

    renderAt("/projects/proj-xyz/notes");

    await waitFor(() => {
      expect(screen.getByTestId("notes-content")).toBeInTheDocument();
    });
    expect(
      screen.getByRole("heading", { name: /Hello synthesis/i }),
    ).toBeInTheDocument();
  });

  it("triggers POST /refresh and re-fetches on Refresh click", async () => {
    const fetchSpy = vi.spyOn(global, "fetch");
    // 1. Initial GET → 404 (empty)
    fetchSpy.mockResolvedValueOnce({
      ok: false,
      status: 404,
      json: async () => ({ error: "No synthesis yet" }),
    } as unknown as Response);
    // 2. POST refresh → 201
    fetchSpy.mockResolvedValueOnce({
      ok: true,
      status: 201,
      json: async () => ({ note: { id: "note-2", content: "# Fresh" } }),
      text: async () => "",
    } as unknown as Response);
    // 3. GET after refresh → 200 with content
    fetchSpy.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({
        note: {
          id: "note-2",
          content: "# Fresh\n\nNew synthesis.",
          createdAt: "2026-06-19T11:00:00.000Z",
        },
      }),
    } as unknown as Response);

    renderAt("/projects/proj-xyz/notes");

    const refreshBtn = await screen.findByTestId("button-refresh-synthesis");
    fireEvent.click(refreshBtn);

    await waitFor(() => {
      expect(screen.getByTestId("notes-content")).toBeInTheDocument();
    });

    // Verify call sequence
    expect(fetchSpy).toHaveBeenCalledTimes(3);
    const [url1, opts1] = fetchSpy.mock.calls[0];
    const [url2, opts2] = fetchSpy.mock.calls[1];
    const [url3] = fetchSpy.mock.calls[2];
    expect(String(url1)).toBe("/api/projects/proj-xyz/notes");
    expect((opts1 as any)?.method).toBeUndefined(); // GET
    expect(String(url2)).toBe("/api/projects/proj-xyz/notes/refresh");
    expect((opts2 as any)?.method).toBe("POST");
    expect(String(url3)).toBe("/api/projects/proj-xyz/notes");
  });

  it("invokes downloadAsMd when Download as Markdown is clicked", async () => {
    vi.spyOn(global, "fetch").mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({
        note: {
          id: "note-1",
          content: "# Hi\n\nbody",
          title: "Project synthesis — 2026-06-19",
          createdAt: "2026-06-19T10:00:00.000Z",
        },
      }),
    } as unknown as Response);

    renderAt("/projects/proj-xyz/notes");

    const dlBtn = await screen.findByTestId("button-download-md");
    await waitFor(() => expect(dlBtn).not.toBeDisabled());
    fireEvent.click(dlBtn);

    expect(downloadAsMdMock).toHaveBeenCalledTimes(1);
    expect(downloadAsMdMock.mock.calls[0][0]).toContain("# Hi");
    expect(downloadAsMdMock.mock.calls[0][1]).toBe(
      "Project synthesis — 2026-06-19",
    );
  });

  // Audit gap #9 (2026-09-09): the refresh/GET FAILURE paths (project-notes.tsx
  // L77-79 GET !ok → throw → setError; L103-110 refresh !ok → throw → setError)
  // were untested. A broken error branch (silent swallow, or clobbering the
  // existing note with null) would ship green.

  it("renders the notes-error banner when refresh POST returns 500 and does NOT replace existing content", async () => {
    const fetchSpy = vi.spyOn(global, "fetch");
    // 1. Initial GET → 200 with real content (so there IS content to protect).
    fetchSpy.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({
        note: {
          id: "note-orig",
          content: "# Original synthesis\n\nKeep me.",
          createdAt: "2026-06-19T10:00:00.000Z",
        },
      }),
    } as unknown as Response);
    // 2. POST refresh → 500 (LLM/server failure).
    fetchSpy.mockResolvedValueOnce({
      ok: false,
      status: 500,
      json: async () => ({ error: "synthesis failed" }),
      text: async () => "synthesis failed",
    } as unknown as Response);

    renderAt("/projects/proj-xyz/notes");

    // Original content rendered first.
    await waitFor(() => {
      expect(screen.getByTestId("notes-content")).toBeInTheDocument();
    });
    expect(
      screen.getByRole("heading", { name: /Original synthesis/i }),
    ).toBeInTheDocument();

    fireEvent.click(screen.getByTestId("button-refresh-synthesis"));

    // Error banner appears and carries the failing status.
    await waitFor(() => {
      expect(screen.getByTestId("notes-error")).toBeInTheDocument();
    });
    expect(screen.getByTestId("notes-error")).toHaveTextContent(/500/);

    // The pre-existing content is NOT replaced (no successful re-fetch happened).
    expect(screen.getByTestId("notes-content")).toBeInTheDocument();
    expect(
      screen.getByRole("heading", { name: /Original synthesis/i }),
    ).toBeInTheDocument();
    // A 500 refresh must never fall through to the empty-state prompt.
    expect(screen.queryByTestId("notes-empty")).not.toBeInTheDocument();
    // Exactly two calls: the initial GET and the failed POST (no re-fetch).
    expect(fetchSpy).toHaveBeenCalledTimes(2);
    expect((fetchSpy.mock.calls[1][1] as any)?.method).toBe("POST");
  });

  it("renders the notes-error banner (not the empty state) when refresh POST returns 502", async () => {
    const fetchSpy = vi.spyOn(global, "fetch");
    fetchSpy.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({
        note: { id: "n", content: "# Keep", createdAt: "2026-06-19T10:00:00.000Z" },
      }),
    } as unknown as Response);
    fetchSpy.mockResolvedValueOnce({
      ok: false,
      status: 502,
      json: async () => ({ error: "upstream down" }),
      text: async () => "upstream down",
    } as unknown as Response);

    renderAt("/projects/proj-xyz/notes");
    await waitFor(() => expect(screen.getByTestId("notes-content")).toBeInTheDocument());

    fireEvent.click(screen.getByTestId("button-refresh-synthesis"));

    await waitFor(() => expect(screen.getByTestId("notes-error")).toBeInTheDocument());
    expect(screen.getByTestId("notes-error")).toHaveTextContent(/502/);
    expect(screen.queryByTestId("notes-empty")).not.toBeInTheDocument();
  });

  it("renders the error banner when the initial GET returns 500 (not the empty state)", async () => {
    vi.spyOn(global, "fetch").mockResolvedValueOnce({
      ok: false,
      status: 500,
      json: async () => ({ error: "boom" }),
    } as unknown as Response);

    renderAt("/projects/proj-xyz/notes");

    // A 500 (as opposed to a 404) is an error, not "no synthesis yet".
    await waitFor(() => {
      expect(screen.getByTestId("notes-error")).toBeInTheDocument();
    });
    expect(screen.getByTestId("notes-error")).toHaveTextContent(/500/);
    // The empty-state ("no synthesis yet") is reserved for 404, not 500. But the
    // body still renders the empty placeholder because note is null; assert the
    // error banner is the signal that distinguishes failure from "nothing yet".
    expect(screen.queryByTestId("notes-content")).not.toBeInTheDocument();
  });
});
