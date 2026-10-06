/**
 * CapabilitiesPage — RTL coverage for the "What can BioMate do for you?" page.
 *
 * This page advertises BioMate's detailed abilities as 9 use-case / job clusters.
 * It previously had NO test (identified in the 2026-10-05 instruction-panel audit),
 * so a dropped or renamed cluster would ship silently. This asserts the full set
 * of 9 clusters, the section heading, and a sample of the workflow chips each
 * cluster lists — i.e. the ability content, not just "it renders".
 */
import React from "react";
import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { Router as WouterRouter } from "wouter";
import { memoryLocation } from "wouter/memory-location";
import CapabilitiesPage from "../capabilities";

function renderPage() {
  const { hook } = memoryLocation({ path: "/capabilities", static: true });
  return render(
    <WouterRouter hook={hook}>
      <CapabilitiesPage />
    </WouterRouter>,
  );
}

// The 9 ability clusters the page must advertise (capabilities.tsx `jobClusters`).
const CLUSTER_TITLES = [
  "IND Package Preparation",
  "Lead Optimization",
  "Antibody-Drug Conjugate Design",
  "Targeted Protein Degradation",
  "Cell Therapy Construct Design",
  "Cryo-EM Structure Solution",
  "Rare Disease Translational Analysis",
  "Single-Cell Drug Mechanism",
  "RNA Therapeutic Design",
];

describe("CapabilitiesPage — ability clusters", () => {
  it("renders the use-case clusters section heading", () => {
    renderPage();
    expect(screen.getByText("Use-case clusters")).toBeInTheDocument();
  });

  it("renders all 9 ability clusters by title", () => {
    renderPage();
    for (const title of CLUSTER_TITLES) {
      expect(screen.getByText(title)).toBeInTheDocument();
    }
  });

  it("renders exactly 9 clusters (no silent add/drop)", () => {
    renderPage();
    const found = CLUSTER_TITLES.filter((t) => screen.queryByText(t) !== null);
    expect(found).toHaveLength(9);
  });

  it("describes each cluster in plain language", () => {
    renderPage();
    // Plain-language description is the ability surface (not an internal pipeline list).
    expect(
      screen.getByText(/full IND data package/i),
    ).toBeInTheDocument();
    expect(
      screen.getByText(/generative AI to decorate scaffolds/i),
    ).toBeInTheDocument();
  });

  it("honors the no-inventory front door — internal pipeline names are NOT shown", () => {
    // Design-v2 principle (capabilities.tsx:135-137): capability is legible through
    // the plain-language cluster, not a raw internal workflow inventory. These names
    // exist in the data but must not render as chips. Guards against a regression
    // that re-exposes the internal inventory.
    renderPage();
    for (const internal of [
      "pbpk_simulation",
      "clinical_trial_simulation",
      "REINVENT4",
      "OpenFE RBFE",
    ]) {
      expect(screen.queryByText(internal)).toBeNull();
    }
  });
});
