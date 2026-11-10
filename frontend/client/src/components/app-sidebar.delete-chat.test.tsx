/**
 * AppSidebar — per-chat delete control (issue #6, organic-user log).
 *
 * A real user asked "how do delete chat" and had no discoverable affordance.
 * This covers the new sidebar delete control:
 *   - every chat row in "OTHER CHATS" renders a delete (trash) button
 *   - clicking it reveals an inline confirm; confirming calls
 *     DELETE /api/sessions/:sessionId with the right id and removes the row
 *   - cancelling the confirm leaves the row in place and fires no DELETE
 *
 * Only fetch is mocked (no msw, no live server). The auth / active-project
 * contexts and the two lazy dialogs are stubbed so the test stays scoped to
 * the sidebar chat list.
 */
import React from "react"
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import { render, screen, fireEvent, waitFor } from "@testing-library/react"

vi.mock("wouter", () => ({
  useLocation: () => ["/", vi.fn()],
}))
vi.mock("@/contexts/auth-context", () => ({
  useAuth: () => ({ user: { id: 1, email: "lifeifei163361@163.com" }, logout: vi.fn() }),
}))
vi.mock("@/contexts/active-project-context", () => ({
  useActiveProject: () => ({ activeProjectId: null, setActiveProjectId: vi.fn() }),
}))
// Lazy dialogs — not under test; keep them out of the render tree.
vi.mock("../settings-dialog", () => ({ SettingsDialog: () => null }))
vi.mock("../workflow-history-dialog", () => ({ WorkflowHistoryDialog: () => null }))

import { AppSidebar } from "./app-sidebar"

const SESSIONS = [
  { id: "sess-aaa", title: "RNA-seq pilot", lastActivity: "2026-11-08T10:00:00.000Z", messages: [] },
  { id: "sess-bbb", title: "ADMET screen", lastActivity: "2026-11-07T10:00:00.000Z", messages: [] },
]

let fetchMock: any

beforeEach(() => {
  try { localStorage.clear() } catch { /* ignore */ }
  fetchMock = vi.fn(async (url: string, init?: RequestInit) => {
    if (init?.method === "DELETE") {
      return { ok: true, status: 204, json: async () => ({}), text: async () => "" } as Response
    }
    // All the mount-time polls (/api/workflows/runs, /overview, /api/projects …)
    return { ok: true, status: 200, json: async () => ({ projects: [], total: 0 }), text: async () => "[]" } as Response
  })
  global.fetch = fetchMock
})
afterEach(() => { vi.clearAllMocks() })

describe("AppSidebar — delete chat", () => {
  it("renders a delete control for every chat row", () => {
    render(<AppSidebar chatSessions={SESSIONS as any} />)
    expect(screen.getByTestId("button-delete-chat-sess-aaa")).toBeInTheDocument()
    expect(screen.getByTestId("button-delete-chat-sess-bbb")).toBeInTheDocument()
  })

  it("confirming delete calls DELETE /api/sessions/:id and removes the row", async () => {
    render(<AppSidebar chatSessions={SESSIONS as any} />)

    // Open the inline confirm, then confirm.
    fireEvent.click(screen.getByTestId("button-delete-chat-sess-aaa"))
    const confirm = await screen.findByTestId("confirm-delete-chat-sess-aaa")
    fireEvent.click(confirm)

    await waitFor(() => {
      const deleteCall = fetchMock.mock.calls.find(
        (call: any[]) => (call[1] as RequestInit | undefined)?.method === "DELETE"
      )
      expect(deleteCall).toBeTruthy()
      expect(String(deleteCall![0])).toContain("/api/sessions/sess-aaa")
    })

    // Row optimistically removed from the list.
    await waitFor(() => {
      expect(screen.queryByTestId("button-chat-sess-aaa")).not.toBeInTheDocument()
    })
    // The other chat is untouched.
    expect(screen.getByTestId("button-chat-sess-bbb")).toBeInTheDocument()
  })

  it("cancelling the confirm keeps the row and fires no DELETE", async () => {
    render(<AppSidebar chatSessions={SESSIONS as any} />)

    fireEvent.click(screen.getByTestId("button-delete-chat-sess-bbb"))
    fireEvent.click(await screen.findByTestId("cancel-delete-chat-sess-bbb"))

    expect(screen.getByTestId("button-chat-sess-bbb")).toBeInTheDocument()
    const deleteCall = fetchMock.mock.calls.find(
      (call: any[]) => (call[1] as RequestInit | undefined)?.method === "DELETE"
    )
    expect(deleteCall).toBeFalsy()
  })
})
