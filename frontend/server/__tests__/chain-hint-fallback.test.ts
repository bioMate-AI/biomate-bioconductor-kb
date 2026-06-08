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

import { describe, it, expect, vi } from "vitest";
import { CHAIN_HINT_FALLBACK, resolveChainHintNames } from "../chain-hint-fallback";

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

describe("resolveChainHintNames", () => {
  const URL = "http://galaxy-test:8081";

  it("returns live chains when Galaxy responds with non-empty list", async () => {
    const fakeFetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ chains: [{ name: "alpha" }, { name: "beta" }] }),
    });
    const result = await resolveChainHintNames(URL, fakeFetch as any);
    expect(result.fromFallback).toBe(false);
    expect(result.names).toEqual(["alpha", "beta"]);
    // intent_hint=true must be passed so bioc_reactive chains stay excluded.
    expect(fakeFetch).toHaveBeenCalledWith(
      expect.stringContaining("/api/workflow-chains?intent_hint=true"),
      expect.any(Object),
    );
  });

  it("falls back to the full 29-chain list on network error", async () => {
    const fakeFetch = vi.fn().mockRejectedValue(new Error("ECONNREFUSED"));
    const result = await resolveChainHintNames(URL, fakeFetch as any);
    expect(result.fromFallback).toBe(true);
    expect(result.names).toEqual([...CHAIN_HINT_FALLBACK]);
    expect(result.names.length).toBeGreaterThanOrEqual(20);
  });

  it("falls back on non-OK HTTP status", async () => {
    const fakeFetch = vi.fn().mockResolvedValue({ ok: false, status: 503 });
    const result = await resolveChainHintNames(URL, fakeFetch as any);
    expect(result.fromFallback).toBe(true);
    expect(result.names).toEqual([...CHAIN_HINT_FALLBACK]);
  });

  it("falls back when Galaxy returns empty chain list", async () => {
    const fakeFetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ chains: [] }),
    });
    const result = await resolveChainHintNames(URL, fakeFetch as any);
    expect(result.fromFallback).toBe(true);
    expect(result.names).toEqual([...CHAIN_HINT_FALLBACK]);
  });

  it("falls back on malformed JSON response", async () => {
    const fakeFetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => {
        throw new SyntaxError("Unexpected token");
      },
    });
    const result = await resolveChainHintNames(URL, fakeFetch as any);
    expect(result.fromFallback).toBe(true);
    expect(result.names).toEqual([...CHAIN_HINT_FALLBACK]);
  });

  it("ignores chains lacking a name field", async () => {
    const fakeFetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ chains: [{ name: "alpha" }, { name: null }, {}, { name: "beta" }] }),
    });
    const result = await resolveChainHintNames(URL, fakeFetch as any);
    expect(result.fromFallback).toBe(false);
    expect(result.names).toEqual(["alpha", "beta"]);
  });

  it("returns the same 29-chain list regardless of Galaxy URL when failing", async () => {
    const failing = vi.fn().mockRejectedValue(new Error("DNS"));
    const a = await resolveChainHintNames("http://prod:8081", failing as any);
    const b = await resolveChainHintNames("http://dev:8081", failing as any);
    expect(a.names).toEqual(b.names);
    expect(a.names).toEqual([...CHAIN_HINT_FALLBACK]);
  });
});
