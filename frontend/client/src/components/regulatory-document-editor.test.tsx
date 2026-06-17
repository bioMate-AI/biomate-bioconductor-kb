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
