/**
 * Unit tests for the composer lane heuristic (spec 06 §6.2).
 *
 * The heuristic is the load-bearing part of the lane preview: it decides the
 * Instant-vs-Cloud verdict the user reads before sending. It mirrors the
 * reference router's ORDERING — evidence/knowledge questions win over topic
 * keywords, so a "what is the evidence for hERG?" question is NOT pulled into
 * a Cloud lane just because it mentions hERG.
 */

import { describe, it, expect } from "vitest";
import { laneForText } from "./lane-preview";

describe("laneForText", () => {
  it("returns null for empty / whitespace input", () => {
    expect(laneForText("")).toBeNull();
    expect(laneForText("   ")).toBeNull();
    expect(laneForText(undefined)).toBeNull();
    expect(laneForText(null)).toBeNull();
  });

  it("routes 'what is known' questions to Instant", () => {
    expect(laneForText("What is the evidence linking TNF to disease?")?.lane).toBe("instant");
    expect(laneForText("Known SAR for this chemotype?")?.lane).toBe("instant");
    expect(laneForText("Why do inhibitors of this target fail on selectivity?")?.lane).toBe("instant");
  });

  it("routes patent / internal-record questions to Instant", () => {
    expect(laneForText("Who holds composition-of-matter claims on this scaffold?")?.lane).toBe("instant");
    expect(laneForText("Have we assayed this scaffold before?")?.lane).toBe("instant");
  });

  it("routes ad-hoc compute on an existing file to Instant", () => {
    expect(laneForText("Summarise this table and plot potency against logP")?.lane).toBe("instant");
    expect(laneForText("Correlate predicted and measured IC50")?.lane).toBe("instant");
  });

  it("routes named methods / pipelines to Cloud", () => {
    expect(laneForText("Run DESeq2 on my counts matrix")?.lane).toBe("cloud");
    expect(laneForText("Align with STAR then quantify")?.lane).toBe("cloud");
    expect(laneForText("Predict the fold of this sequence with AlphaFold")?.lane).toBe("cloud");
  });

  it("routes consequence verbs to Cloud", () => {
    expect(laneForText("Screen these SMILES for ADMET liabilities")?.lane).toBe("cloud");
    expect(laneForText("Call variants on these samples")?.lane).toBe("cloud");
    expect(laneForText("Train a potency predictor on our assay data")?.lane).toBe("cloud");
  });

  it("routes scale / dataset cues to Cloud", () => {
    expect(laneForText("Differential expression across 24 samples")?.lane).toBe("cloud");
    expect(laneForText("Process this cryo-EM dataset")?.lane).toBe("cloud");
  });

  it("lets evidence questions win over topic keywords (ordering)", () => {
    // Mentions hERG (a Cloud topic word) but is a knowledge question.
    expect(laneForText("What is the evidence for hERG liability of this series?")?.lane).toBe("instant");
    // Mentions ADMET but asks which assays are standard — a knowledge question.
    expect(laneForText("Which assays are standard for ADMET liability?")?.lane).toBe("instant");
  });

  it("defaults ambiguous free text to Instant (honest, cheap default)", () => {
    const v = laneForText("this is a plain sentence with no clear intent");
    expect(v?.lane).toBe("instant");
  });

  it("always supplies a label and a consequence sentence", () => {
    for (const q of ["Run DESeq2", "What is the evidence?", "hello there"]) {
      const v = laneForText(q);
      expect(v).not.toBeNull();
      expect(v!.label.length).toBeGreaterThan(0);
      expect(v!.sentence.length).toBeGreaterThan(0);
    }
  });
});
