/**
 * Cold-start / example runners inject File[] via onRegisterExampleFiles.
 * Those files must paint the same composer chips + clickable content preview
 * as a normal attach — not a silent draft-only seed.
 */
import React from "react"
import { describe, it, expect, vi, afterEach } from "vitest"
import { fireEvent, render, screen, waitFor } from "@testing-library/react"
import { ChatInput } from "./chat-input"

vi.mock("./skills-selector", () => ({
  SkillsSelector: () => null,
  DEFAULT_SKILL_ID: "biomate-universe",
}))

describe("ChatInput — cold-start example file previews", () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it("registers example files as previewable composer chips (same path as uploads)", async () => {
    let inject: ((files: File[]) => void) | null = null
    render(
      <ChatInput
        onSend={vi.fn()}
        onRegisterExampleFiles={(setter) => {
          inject = setter
        }}
      />,
    )
    await waitFor(() => expect(inject).toBeTruthy())

    const csv = new File(
      ["compound_id,smiles\nA,CCO\nB,CCN\n"],
      "pilot_compounds.csv",
      { type: "text/csv" },
    )
    const pdb = new File(["HEADER    LYSOZYME\nATOM      1  N\n"], "1LYZ.pdb", {
      type: "chemical/x-pdb",
    })
    inject!([csv, pdb])

    const chips = await screen.findAllByTestId("composer-attached-file")
    expect(chips).toHaveLength(2)
    expect(chips[0]).toHaveAttribute("data-filename", "pilot_compounds.csv")
    expect(chips[0]).toHaveAttribute("data-demo", "true")
    expect(chips[1]).toHaveAttribute("data-filename", "1LYZ.pdb")

    fireEvent.click(screen.getAllByTestId("composer-attached-file-preview")[0])
    // Table preview reads CSV content (header + rows), not metadata-only fallback.
    await waitFor(() => {
      expect(screen.getByRole("dialog")).toBeInTheDocument()
      expect(screen.getByText("compound_id")).toBeInTheDocument()
      expect(screen.getByText("smiles")).toBeInTheDocument()
    })
  })

  it("previews PDB / SMILES demo formats that cold-start commonly attaches", async () => {
    let inject: ((files: File[]) => void) | null = null
    render(
      <ChatInput
        onSend={vi.fn()}
        onRegisterExampleFiles={(setter) => {
          inject = setter
        }}
      />,
    )
    await waitFor(() => expect(inject).toBeTruthy())
    inject!([
      new File(["CCO\nCCN\n"], "pilot_reference_actives.smi", { type: "text/plain" }),
    ])
    await screen.findByTestId("composer-attached-file")
    fireEvent.click(screen.getByTestId("composer-attached-file-preview"))
    await waitFor(() => {
      expect(screen.getByText(/CCO/)).toBeInTheDocument()
    })
  })
})
