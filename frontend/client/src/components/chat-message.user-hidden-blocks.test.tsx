/**
 * The user's bubble shows only what the user wrote: machine blocks appended at
 * send time ([Attached files], [Uploaded datasets], [Prepared inputs]) are
 * stripped, and never surface storage paths (founder directive 2026-11-10).
 */
import { describe, it, expect, vi } from "vitest"
import { render } from "@testing-library/react"

vi.mock("3dmol", () => ({ default: {}, GLViewer: class {}, createViewer: () => ({}) }))

import { ChatMessage, type Message } from "./chat-message"

describe("user bubble hides send-time machine blocks", () => {
  it("strips [Prepared inputs] and upload blocks, keeps the goal and file chips", () => {
    const message: Message = {
      id: "u1",
      role: "user",
      timestamp: new Date(),
      content:
        "Screen these SMILES for ADMET liabilities, hERG first.\n\n" +
        "[Attached files: pilot_compounds.csv]\n" +
        "[Uploaded datasets: pilot_compounds.csv: dataset_id=abc, s3_uri=s3://bucket/uploads/abc/pilot_compounds.csv]\n" +
        "[Prepared inputs: Screen the SMILES column of pilot_compounds.csv; staged at s3://bucket/x/]",
    } as Message
    const { container } = render(<ChatMessage message={message} />)
    const text = container.textContent || ""
    expect(text).toContain("Screen these SMILES for ADMET liabilities, hERG first.")
    expect(text).toContain("pilot_compounds.csv")
    expect(text).not.toMatch(/s3:\/\/|Prepared inputs|Uploaded datasets|staged at/)
  })
})
