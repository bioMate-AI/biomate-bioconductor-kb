/**
 * Audit round 6 (backend 2aa0348e3f): a column with ONE value in every row is `constant_columns`,
 * no longer `near_constant` ("over 99%"). The client treats it as near_constant was treated:
 *  - watch level flags the column (badge in the Columns view);
 *  - info level is a neutral note with its reason ("Expected with this few rows — not flagged.")
 *    and flags nothing.
 */
import React from "react"
import { describe, it, expect } from "vitest"
import { render, screen } from "@testing-library/react"
import { DataPerception } from "@/components/data-perception"
import { computeColumnStats } from "./dataset-columns-view"

const base = { section: "signal" as const, code: "constant_columns", params: { count: 1, columns: ["gene"] } }

describe("constant_columns", () => {
  it("watch level flags the column", () => {
    const stats = computeColumnStats(["id", "gene"], [["a", "EGFR"], ["b", "EGFR"]], [{ ...base, level: "watch" as const }])
    expect(stats.find((s) => s.name === "gene")!.watch).toBe(true)
  })
  it("info level is a neutral note with its reason, and flags no column", () => {
    const f = { ...base, level: "info" as const, params: { ...base.params, expected: "few_rows" } }
    render(React.createElement(DataPerception, {
      profile: { shape: { rows: 5, cols: 2 }, quality: "good", notes: [], columns: ["id", "gene"], findings: [f] } as any,
    }))
    const line = screen.getAllByTestId("perception-finding").find((e) => e.getAttribute("data-code") === "constant_columns")!
    expect(line).toHaveTextContent("Constant columns (the same value in every row): gene. Expected with this few rows — not flagged.")
    const stats = computeColumnStats(["id", "gene"], [["a", "EGFR"], ["b", "EGFR"]], [f])
    expect(stats.find((s) => s.name === "gene")!.watch).toBe(false)
  })
})
