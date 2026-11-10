/**
 * GalaxyDatasetBrowser — RTL coverage for the "Select dataset" dialog.
 *
 * Covers the three UI_refinement fixes:
 *  1. i18n — strings render via tOr (English fallback under the default locale).
 *  2. Multi-select — Project-files + BioMate-history tabs expose per-row
 *     checkboxes + a "Use selected (N)" button that returns every checked
 *     dataset at once (calls the single-select handler once per item, closes once).
 *  3. Error-item filter — BioMate-history hides datasets whose state is not a
 *     usable ('ok') dataset (e.g. an errored "Executed Notebook" ipynb).
 *
 * No network mocking of app behaviour — only the raw fetch transport is stubbed
 * to supply deterministic list payloads (unit-test scope, not an e2e harness).
 */
import React from "react";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { GalaxyDatasetBrowser } from "./galaxy-dataset-browser";

const HISTORY = { id: "h1", name: "RNA-seq run", count: 3, size: 1000, create_time: "", update_time: "" };
// Galaxy's auto-created per-session history — its raw name must never be shown.
const AUTO_HISTORY = { id: "h2", name: "GalaxyChat-2026-10-10", count: 1, size: 500, create_time: "", update_time: "" };

const DATASETS = [
  { id: "d1", name: "sample_ok_1.bam", extension: "bam", file_size: 100, state: "ok", create_time: "", s3_uri: "s3://bucket/d1" },
  { id: "d2", name: "sample_ok_2.bam", extension: "bam", file_size: 200, state: "ok", create_time: "", s3_uri: "s3://bucket/d2" },
  // Non-selectable: errored "Executed Notebook" — must be hidden (issue 3).
  { id: "d3", name: "Executed Notebook", extension: "ipynb", file_size: 0, state: "error", create_time: "" },
  { id: "d4", name: "still_running.bam", extension: "bam", file_size: 0, state: "running", create_time: "" },
];

const PROJECT_FILES = [
  { id: "f1", name: "reads_R1.fastq.gz", size: 10 },
  { id: "f2", name: "reads_R2.fastq.gz", size: 20 },
];

function mockFetch() {
  vi.spyOn(global, "fetch").mockImplementation((input: any) => {
    const url = typeof input === "string" ? input : input.url;
    let body: any = {};
    if (url.includes("/api/galaxy/histories/") && url.includes("/datasets")) body = { datasets: DATASETS };
    else if (url.endsWith("/api/galaxy/histories")) body = { histories: [HISTORY, AUTO_HISTORY] };
    else if (url.includes("/files")) body = { files: PROJECT_FILES };
    return Promise.resolve({ ok: true, json: async () => body } as Response);
  });
}

beforeEach(() => { vi.restoreAllMocks(); mockFetch(); });
afterEach(() => { vi.clearAllMocks(); });

describe("GalaxyDatasetBrowser — i18n", () => {
  it("renders the dialog title and tab labels via tOr (English fallback)", () => {
    render(<GalaxyDatasetBrowser open onClose={() => {}} onSelect={() => {}} projectId="p1" />);
    expect(screen.getByText("Select dataset")).toBeInTheDocument();
    // Tab labels are buttons ("From URL" also appears in the session help text,
    // so scope to the tab role to keep the query unambiguous).
    expect(screen.getByRole("button", { name: "This session" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Project files" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "BioMate history" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "From URL" })).toBeInTheDocument();
  });
});

describe("GalaxyDatasetBrowser — BioMate history error filter + multi-select", () => {
  it("hides non-'ok' datasets and returns all checked rows at once", async () => {
    const onSelect = vi.fn();
    const onClose = vi.fn();
    render(<GalaxyDatasetBrowser open onClose={onClose} onSelect={onSelect} />);

    fireEvent.click(screen.getByText("BioMate history"));
    // History list loads, then open it
    await waitFor(() => expect(screen.getByText("RNA-seq run")).toBeInTheDocument());
    fireEvent.click(screen.getByText("RNA-seq run"));

    // Usable datasets show; errored/running ones are filtered out (issue 3)
    await waitFor(() => expect(screen.getByText("sample_ok_1.bam")).toBeInTheDocument());
    expect(screen.getByText("sample_ok_2.bam")).toBeInTheDocument();
    expect(screen.queryByText("Executed Notebook")).not.toBeInTheDocument();
    expect(screen.queryByText("still_running.bam")).not.toBeInTheDocument();

    // Exactly one checkbox per usable row
    const checkboxes = screen.getAllByRole("checkbox");
    expect(checkboxes).toHaveLength(2);

    // No "Use selected" until something is checked
    expect(screen.queryByTestId("datasets-use-selected")).not.toBeInTheDocument();

    fireEvent.click(checkboxes[0]);
    fireEvent.click(checkboxes[1]);
    const useSelected = await screen.findByTestId("datasets-use-selected");
    expect(useSelected).toHaveTextContent("Use selected (2)");

    fireEvent.click(useSelected);
    // Single-select handler called once per checked dataset; dialog closed once
    expect(onSelect).toHaveBeenCalledTimes(2);
    expect(onSelect).toHaveBeenCalledWith("s3://bucket/d1", "sample_ok_1.bam");
    expect(onSelect).toHaveBeenCalledWith("s3://bucket/d2", "sample_ok_2.bam");
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it("keeps the single per-row Use button working", async () => {
    const onSelect = vi.fn();
    const onClose = vi.fn();
    render(<GalaxyDatasetBrowser open onClose={onClose} onSelect={onSelect} />);

    fireEvent.click(screen.getByText("BioMate history"));
    await waitFor(() => expect(screen.getByText("RNA-seq run")).toBeInTheDocument());
    fireEvent.click(screen.getByText("RNA-seq run"));
    await waitFor(() => expect(screen.getByText("sample_ok_1.bam")).toBeInTheDocument());

    const useButtons = screen.getAllByRole("button", { name: "Use" });
    fireEvent.click(useButtons[0]);
    expect(onSelect).toHaveBeenCalledTimes(1);
    expect(onSelect).toHaveBeenCalledWith("s3://bucket/d1", "sample_ok_1.bam");
    expect(onClose).toHaveBeenCalledTimes(1);
  });
});

describe("GalaxyDatasetBrowser — BioMate history auto-name handling", () => {
  it("de-identifies Galaxy's auto-generated chat-session history names", async () => {
    render(<GalaxyDatasetBrowser open onClose={() => {}} onSelect={() => {}} />);

    fireEvent.click(screen.getByText("BioMate history"));
    // User-named history shows verbatim; the auto GalaxyChat-<date> name is hidden
    await waitFor(() => expect(screen.getByText("RNA-seq run")).toBeInTheDocument());
    expect(screen.queryByText("GalaxyChat-2026-10-10")).not.toBeInTheDocument();
    // Friendly label keeps the embedded date (the only user-meaningful part)
    expect(screen.getByText("Chat session · 2026-10-10")).toBeInTheDocument();
  });

  it("still finds de-identified histories when searching 'chat'", async () => {
    render(<GalaxyDatasetBrowser open onClose={() => {}} onSelect={() => {}} />);

    fireEvent.click(screen.getByText("BioMate history"));
    await waitFor(() => expect(screen.getByText("Chat session · 2026-10-10")).toBeInTheDocument());

    fireEvent.change(screen.getByPlaceholderText(/search/i), { target: { value: "chat" } });
    // The user-named history is filtered out; the auto one matches via its label
    expect(screen.getByText("Chat session · 2026-10-10")).toBeInTheDocument();
    expect(screen.queryByText("RNA-seq run")).not.toBeInTheDocument();
  });

  it("shows the friendly label in the dataset-list header after entering an auto history", async () => {
    render(<GalaxyDatasetBrowser open onClose={() => {}} onSelect={() => {}} />);

    fireEvent.click(screen.getByText("BioMate history"));
    await waitFor(() => expect(screen.getByText("Chat session · 2026-10-10")).toBeInTheDocument());
    fireEvent.click(screen.getByText("Chat session · 2026-10-10"));

    // Header shows the friendly label, never the raw GalaxyChat identifier
    await waitFor(() => expect(screen.getByText("sample_ok_1.bam")).toBeInTheDocument());
    expect(screen.getByText("Chat session · 2026-10-10")).toBeInTheDocument();
    expect(screen.queryByText("GalaxyChat-2026-10-10")).not.toBeInTheDocument();
  });
});

describe("GalaxyDatasetBrowser — Project files multi-select", () => {
  it("returns all checked project files at once via their file id", async () => {
    const onSelect = vi.fn();
    const onClose = vi.fn();
    render(<GalaxyDatasetBrowser open onClose={onClose} onSelect={onSelect} projectId="p1" />);

    fireEvent.click(screen.getByText("Project files"));
    await waitFor(() => expect(screen.getByText("reads_R1.fastq.gz")).toBeInTheDocument());

    const checkboxes = screen.getAllByRole("checkbox");
    expect(checkboxes).toHaveLength(2);
    fireEvent.click(checkboxes[0]);
    fireEvent.click(checkboxes[1]);

    const useSelected = await screen.findByTestId("datasets-use-selected");
    expect(useSelected).toHaveTextContent("Use selected (2)");
    fireEvent.click(useSelected);

    // project_files.id contract preserved (not a URI)
    expect(onSelect).toHaveBeenCalledTimes(2);
    expect(onSelect).toHaveBeenCalledWith("f1", "reads_R1.fastq.gz");
    expect(onSelect).toHaveBeenCalledWith("f2", "reads_R2.fastq.gz");
    expect(onClose).toHaveBeenCalledTimes(1);
  });
});
