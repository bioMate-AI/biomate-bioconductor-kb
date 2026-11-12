import React from "react"
import { afterEach, describe, expect, it } from "vitest"
import { act, fireEvent, render, screen } from "@testing-library/react"
import { PaneResizeHandle, TREE_MAX_PX, TREE_MIN_PX, clampTreeWidth, useTreeWidth } from "./pane-resize-handle"

function Harness() {
  const [w, setW] = useTreeWidth()
  return <div><span data-testid="w">{w}</span><PaneResizeHandle width={w} onWidth={setW} /></div>
}
afterEach(() => { try { localStorage.clear() } catch {} })

describe("Data page file-tree resize (founder: notResizable)", () => {
  it("drag widens the pane and the width is remembered", () => {
    const { unmount } = render(<Harness />)
    const h = screen.getByTestId("data-hub-resize-handle")
    // jsdom's fireEvent.pointer* carries no clientX — dispatch MouseEvents typed as pointer events.
    act(() => { h.dispatchEvent(new MouseEvent("pointerdown", { clientX: 300, bubbles: true })) })
    act(() => { window.dispatchEvent(new MouseEvent("pointermove", { clientX: 420 })) })
    act(() => { window.dispatchEvent(new MouseEvent("pointerup", {})) })
    expect(screen.getByTestId("w").textContent).toBe("400")
    unmount()
    render(<Harness />)
    expect(screen.getByTestId("w").textContent).toBe("400")
  })
  it("keyboard resize and clamping", () => {
    render(<Harness />)
    const h = screen.getByTestId("data-hub-resize-handle")
    fireEvent.keyDown(h, { key: "ArrowRight" })
    expect(screen.getByTestId("w").textContent).toBe("296")
    expect(clampTreeWidth(10)).toBe(TREE_MIN_PX)
    expect(clampTreeWidth(5000)).toBe(TREE_MAX_PX)
    expect(h.getAttribute("role")).toBe("separator")
  })
})
