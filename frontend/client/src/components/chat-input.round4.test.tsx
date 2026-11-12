/**
 * N10 (round 4): "Ask in chat" opened the composer with the file attached, but its chip sat far to
 * the left of the centred composer. The chip row shares the composer's column (same max width,
 * centred), so the attachment reads as part of the message being written.
 */
import React from "react"
import { describe, it, expect, vi } from "vitest"
import { fireEvent, render, screen } from "@testing-library/react"
import { ChatInput, COMPOSER_MAX_WIDTH } from "./chat-input"

vi.mock("./skills-selector", () => ({ SkillsSelector: () => null }))

describe("composer attachment chips", () => {
  it("sit in the composer's centred column", async () => {
    render(<ChatInput onSend={vi.fn()} isStreaming={false} />)
    const input = screen.getByTestId("chat-attach-file-input") as HTMLInputElement
    fireEvent.change(input, { target: { files: [new File(["a\tb\n"], "header_only.tsv", { type: "text/tab-separated-values" })] } })
    await screen.findByTestId("composer-attached-file")
    const row = screen.getByTestId("composer-attachments")
    const box = document.querySelector(".chat-input") as HTMLElement
    expect(row.style.maxWidth).toBe(`${COMPOSER_MAX_WIDTH}px`)
    expect(row.style.maxWidth).toBe(box.style.maxWidth)
    expect(row.style.marginLeft).toBe("auto")
    expect(row.style.marginRight).toBe("auto")
  })
})
