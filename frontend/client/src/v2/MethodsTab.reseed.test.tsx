/**
 * Regression (2026-09-11): the methods-report editor must not lose the user's
 * in-progress edits when the source report text refreshes mid-edit.
 *
 * MethodsTab keeps `editedText` as a mirror of the editor content (updated via
 * onEdit) and exports THAT on Save. A useEffect re-seeds editedText from
 * methods.text when the source changes (fresh run / cache fill). Without a guard,
 * a refresh while the user is editing overwrites editedText → Save then downloads
 * the source, silently discarding the user's edits. The fix guards the re-seed
 * with `!editing`. This test drives exactly that sequence and asserts Save still
 * exports the user's edit, not the refreshed source.
 */
import React from "react";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";

// Mock the heavy TipTap editor with a textarea that surfaces content + onEdit,
// so the test can simulate a user edit deterministically.
vi.mock("@/components/regulatory-document-editor", () => ({
  RegulatoryDocumentEditor: ({ content, onEdit }: any) => (
    <textarea
      data-testid="mock-rde"
      defaultValue={content}
      onChange={(e) => onEdit((e.target as HTMLTextAreaElement).value)}
    />
  ),
}));

import { MethodsTab } from "./AfterRunReport";

const RealBlob = global.Blob;
let lastBlobParts: any[] | null = null;

beforeEach(() => {
  lastBlobParts = null;
  // Capture the parts handed to `new Blob([...])` synchronously.
  (global as any).Blob = class extends RealBlob {
    constructor(parts: any[], opts?: any) {
      super(parts, opts);
      lastBlobParts = parts;
    }
  };
  (URL as any).createObjectURL = vi.fn(() => "blob:mock");
  (URL as any).revokeObjectURL = vi.fn();
  // Save is server-first (#22): it POSTs to /report/versions and only downloads
  // locally on failure. Force the fallback deterministically so these tests can
  // assert the downloaded blob's content (the edited-text-survives behavior).
  vi.spyOn(global, "fetch").mockResolvedValue({
    ok: false, status: 404, json: async () => ({}), text: async () => "",
  } as Response);
  // Stop the anchor click from navigating jsdom.
  const origCreate = document.createElement.bind(document);
  vi.spyOn(document, "createElement").mockImplementation((tag: string) => {
    const el = origCreate(tag);
    if (tag === "a") (el as HTMLAnchorElement).click = vi.fn();
    return el;
  });
});

afterEach(() => {
  (global as any).Blob = RealBlob;
  vi.restoreAllMocks();
});

const methods = (text: string) => ({ text, toolVersions: {}, hasRealContent: true });

describe("MethodsTab — edited text survives a source refresh mid-edit", () => {
  it("Save exports the user's in-progress edit, not a source-text refresh", async () => {
    const { rerender } = render(
      <MethodsTab methods={methods("ORIGINAL methods prose")} workflowName="wf" runId="r1" />,
    );

    // Enter edit mode → editor mounts.
    fireEvent.click(screen.getByTestId("methods-edit-toggle"));
    expect(screen.getByTestId("methods-editor")).toBeInTheDocument();

    // User edits the report.
    fireEvent.change(screen.getByTestId("mock-rde"), {
      target: { value: "USER-EDITED prose the user must keep" },
    });

    // The source report refreshes WHILE the user is still editing (poll / cache
    // fill / id change). This must NOT clobber the in-progress edit.
    rerender(
      <MethodsTab methods={methods("REFRESHED source that should be ignored")} workflowName="wf" runId="r1" />,
    );

    // Save is server-first; the local download (blob) fires after the awaited
    // POST fails over, so wait for the blob before asserting its content.
    fireEvent.click(screen.getByTestId("methods-save-edited"));
    await waitFor(() => expect(lastBlobParts).not.toBeNull());
    expect(String(lastBlobParts![0])).toContain("USER-EDITED prose the user must keep");
    expect(String(lastBlobParts![0])).not.toContain("REFRESHED source");
  });

  it("re-seeds from the source when NOT editing (normal fresh-run behavior)", async () => {
    const { rerender } = render(
      <MethodsTab methods={methods("FIRST run methods")} workflowName="wf" runId="r1" />,
    );
    // A new run's methods arrive while the user is only viewing (not editing).
    rerender(<MethodsTab methods={methods("SECOND run methods")} workflowName="wf" runId="r1" />);

    // Now the user edits (starts from the refreshed source) and saves.
    fireEvent.click(screen.getByTestId("methods-edit-toggle"));
    fireEvent.click(screen.getByTestId("methods-save-edited"));
    await waitFor(() => expect(lastBlobParts).not.toBeNull());
    expect(String(lastBlobParts![0])).toContain("SECOND run methods");
  });
});
