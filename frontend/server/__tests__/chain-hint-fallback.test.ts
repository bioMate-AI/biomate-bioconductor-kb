/**
 * Guards the CHAIN_HINT_FALLBACK list in galaxy-assistant.ts against drift.
 *
 * The fallback is only used when Galaxy's /api/workflow-chains endpoint is
 * unreachable at boot. If it falls behind the curated chain catalog, the
 * intent classifier silently degrades — it stops proposing chains that
 * exist in the DB.
 *
 * Context: docs/20260607_PARALLELISM_AND_CROSS_DOMAIN_CHAINING_PROPOSAL.md (C7).
 */

import { describe, it, expect } from "vitest";
import { CHAIN_HINT_FALLBACK } from "../chain-hint-fallback";

describe("CHAIN_HINT_FALLBACK", () => {
  it("contains every load-bearing chain a deploy must recognize", () => {
    // Chains that are referenced by name in docs, demos, or routing rules.
    // Removing any of these without updating callers is a regression.
    const REQUIRED = [
      "bulk_rnaseq_de_analysis",
      "target_to_lead_full",
      "drug_discovery_screening",
      "drug_discovery_admet_gated_screening",
      "single_cell_multimodal_analysis",
      "rare_disease_multimodal_workup",
      "cutandtag_chromatin_analysis",
      "rnaseq_to_lincs_moa",
      "pbpk_to_tumor_tgi",
      "admet_to_virtual_patient_dose_opt",
      "mageck_to_gears_moa",
    ];
    const missing = REQUIRED.filter((c) => !CHAIN_HINT_FALLBACK.includes(c));
    expect(missing, `missing load-bearing chains in fallback: ${missing.join(", ")}`).toEqual([]);
  });

  it("has no duplicate entries", () => {
    const unique = new Set(CHAIN_HINT_FALLBACK);
    expect(unique.size).toBe(CHAIN_HINT_FALLBACK.length);
  });

  it("is non-trivially sized (catches accidental truncation)", () => {
    // DB had 29 intent-eligible chains as of 2026-06-07. Allow growth/shrinkage
    // but flag if it falls below 20 — that's evidence of accidental deletion.
    expect(CHAIN_HINT_FALLBACK.length).toBeGreaterThanOrEqual(20);
  });

  it("uses identifier-style names only (matches workflow_chains.name convention)", () => {
    // Some real chain names mix case (e.g. small_rna_piRNA_seqpac_analysis).
    // What we guard against is whitespace, slashes, or other separators.
    const bad = CHAIN_HINT_FALLBACK.filter((c) => !/^[A-Za-z0-9_]+$/.test(c));
    expect(bad, `non-identifier names: ${bad.join(", ")}`).toEqual([]);
  });

  it("is sorted (case-insensitive) for diff readability", () => {
    const sorted = [...CHAIN_HINT_FALLBACK].sort((a, b) =>
      a.toLowerCase().localeCompare(b.toLowerCase())
    );
    expect(CHAIN_HINT_FALLBACK).toEqual(sorted);
  });
});
