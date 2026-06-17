/**
 * RegulatoryDocumentEditor — DPO pair-recording RTL coverage.
 *
 * Verifies the B3 upstream UI affordance: when a user edits a paragraph
 * that started life as AI-generated, the editor POSTs a {chosen,
 * rejected, section_type} pair to /api/regulatory_llm/pairs. The pair
 * is keyed by the §X.Y.Z heading the paragraph lives under.
 *
 * The fetch path is replaced with a `recordPairFn` test hook so this
 * suite never touches the network.
 */
import React from "react";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, act } from "@testing-library/react";
import { RegulatoryDocumentEditor } from "./regulatory-document-editor";

const MD = [
  "# §2.6.1 Pharmacology Overview",
  "",
  "The pharmacology of the compound is consistent with the proposed mechanism.",
  "",
  "## §2.6.4 Pharmacokinetics",
  "",
  "PBPK qualification met EMA/CHMP/EWP/37498/2011 within-2-fold criterion.",
  "",
].join("\n");

beforeEach(() => {
  vi.useFakeTimers();
});

afterEach(() => {
  vi.useRealTimers();
  vi.restoreAllMocks();
});

describe("RegulatoryDocumentEditor — DPO pair recording", () => {
  it("does NOT spuriously emit pairs on mount (no edits yet)", async () => {
    // Regression guard: a previous draft fired the flush during the
    // initial setContent path, which would record EVERY paragraph as
    // "edited" the moment the document loaded. The fix is `emitUpdate:
    // false` on setContent. This test pins that behaviour.
    const recordPairFn = vi.fn(async () => {});
    render(
      <RegulatoryDocumentEditor
        content={MD}
        isLocked={false}
        onEdit={() => {}}
        molecule="ACME-001"
        generatedAt="2026-06-16"
        recordPairFn={recordPairFn}
      />,
    );
    await act(async () => {
      vi.advanceTimersByTime(2000);
      await Promise.resolve();
    });
    expect(recordPairFn).not.toHaveBeenCalled();
  });

  it("does NOT emit pairs when recordEditPairs={false}", async () => {
    const recordPairFn = vi.fn(async () => {});
    render(
      <RegulatoryDocumentEditor
        content={MD}
        isLocked={false}
        onEdit={() => {}}
        molecule="ACME-001"
        generatedAt="2026-06-16"
        recordEditPairs={false}
        recordPairFn={recordPairFn}
      />,
    );
    await act(async () => {
      vi.advanceTimersByTime(2000);
      await Promise.resolve();
    });
    expect(recordPairFn).not.toHaveBeenCalled();
  });

  it("maps §2.6.X tab-id → assembler section_type vocabulary", async () => {
    // Audit H1: without the mapping the recorder emitted "2.6.4" but the
    // assembler queries _build_rag_context with "pbpk"; section-filtered
    // few-shot retrieval would miss. The mapping must cover all six tabs.
    const { SECTION_TYPE_BY_TAB } = await import(
      "./regulatory-document-editor"
    );
    expect(SECTION_TYPE_BY_TAB["2.6.1"]).toBe("nonclinical_overview");
    expect(SECTION_TYPE_BY_TAB["2.6.2"]).toBe("pk_overview");
    expect(SECTION_TYPE_BY_TAB["2.6.3"]).toBe("pk_overview");
    expect(SECTION_TYPE_BY_TAB["2.6.4"]).toBe("pbpk");
    expect(SECTION_TYPE_BY_TAB["2.6.5"]).toBe("pbpk");
    expect(SECTION_TYPE_BY_TAB["2.6.6"]).toBe("tox_genotox");
  });

  it("emits a pair with mapped section_type when a §2.6.4 paragraph is edited", async () => {
    // The end-to-end positive path: drive a real TipTap edit through
    // the live editor handle, advance the 1.2 s debounce, assert the
    // recordFn fires with section_type='pbpk' (mapped from §2.6.4).
    // Use real timers — fake timers race with TipTap's internal queue
    // microtasks in ways that produce false negatives.
    vi.useRealTimers();
    const recordPairFn = vi.fn(async () => {});
    let editorHandle: any = null;
    render(
      <RegulatoryDocumentEditor
        content={MD}
        isLocked={false}
        onEdit={() => {}}
        molecule="ACME-001"
        generatedAt="2026-06-16"
        recordPairFn={recordPairFn}
        onEditorReady={(e) => {
          editorHandle = e;
        }}
      />,
    );

    // Wait for the editor to mount + the rAF baseline snapshot.
    for (let tries = 0; tries < 50 && !editorHandle; tries++) {
      await new Promise((r) => setTimeout(r, 10));
    }
    expect(editorHandle).not.toBeNull();

    // Find the §2.6.4 PBPK paragraph by its citation text and locate it
    // in the ProseMirror document by character position. Then replace
    // its contents with a user edit. This mirrors what a regulatory
    // writer would do — strip the AI text, type a revision.
    const doc = editorHandle.state.doc;
    let pbpkPos: number | null = null;
    let pbpkSize: number | null = null;
    doc.descendants((node: any, pos: number) => {
      if (node.type.name !== "paragraph") return true;
      if ((node.textContent || "").includes("EMA/CHMP/EWP/37498/2011")) {
        pbpkPos = pos;
        pbpkSize = node.nodeSize;
        return false;
      }
      return true;
    });
    expect(pbpkPos).not.toBeNull();

    // Replace the paragraph's text content with a user revision.
    await act(async () => {
      editorHandle
        .chain()
        .focus()
        .setTextSelection({
          from: pbpkPos! + 1,
          to: pbpkPos! + pbpkSize! - 1,
        })
        .insertContent(
          "PBPK qualification met the within-2-fold acceptance criterion per ICH M3(R2).",
        )
        .run();
    });

    // Wait past the 1.2 s debounce.
    await new Promise((r) => setTimeout(r, 1400));

    // What we actually need to prove (audit H1): a real edit under
    // §2.6.4 fires with the MAPPED section_type 'pbpk', not the raw
    // tab-id '2.6.4'. We also pin the prompt format so the worker's
    // ranker has a stable prompt-text signal to retrieve against.
    expect(recordPairFn).toHaveBeenCalled();
    const calls = recordPairFn.mock.calls as unknown as Array<[
      { chosen: string; rejected: string; section_type: string; prompt?: string },
    ]>;
    const pbpkCall = calls.find((c) => c[0].section_type === "pbpk");
    expect(pbpkCall).toBeDefined();
    expect(pbpkCall![0].prompt).toBe("IND §2.6.4 for ACME-001");
    expect(pbpkCall![0].chosen.length).toBeGreaterThan(0);
    expect(pbpkCall![0].rejected.length).toBeGreaterThan(0);
  });

  it("does NOT emit pairs when isLocked={true}", async () => {
    const recordPairFn = vi.fn(async () => {});
    render(
      <RegulatoryDocumentEditor
        content={MD}
        isLocked={true}
        onEdit={() => {}}
        molecule="ACME-001"
        generatedAt="2026-06-16"
        recordPairFn={recordPairFn}
      />,
    );
    await act(async () => {
      vi.advanceTimersByTime(2000);
      await Promise.resolve();
    });
    expect(recordPairFn).not.toHaveBeenCalled();
  });
});
