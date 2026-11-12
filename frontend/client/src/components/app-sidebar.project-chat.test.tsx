/**
 * Round 5 (2026-11-12 walkthrough): the "Run full QC" chat sat under "Other chats" for ~46 s before
 * moving under its project — the sidebar listed a project's chats only from the server's per-project
 * list, fetched before the new session had synced. A chat started IN a project (its `projectId` set
 * at creation / first send) is listed under that project at once, never under "Other chats".
 * Only fetch is mocked; contexts / lazy dialogs are stubbed as in the other sidebar tests.
 */
import React from "react"
import { describe, it, expect, vi, beforeEach } from "vitest"
import { render, screen, waitFor } from "@testing-library/react"

vi.mock("wouter", () => ({ useLocation: () => ["/", vi.fn()] }))
vi.mock("@/contexts/auth-context", () => ({
  useAuth: () => ({ user: { id: 1, email: "lifeifei163361@163.com" }, logout: vi.fn() }),
}))
vi.mock("@/contexts/active-project-context", () => ({
  useActiveProject: () => ({ activeProjectId: "proj-1", setActiveProjectId: vi.fn() }),
}))
vi.mock("../settings-dialog", () => ({ SettingsDialog: () => null }))
vi.mock("../workflow-history-dialog", () => ({ WorkflowHistoryDialog: () => null }))

import { AppSidebar, projectChatRows } from "./app-sidebar"

const QC_CHAT = {
  id: "chat-qc", title: "samples_quoted.csv: run quality control (QC) on", projectId: "proj-1",
  lastActivity: "2026-11-12T10:00:00.000Z", messages: [{ id: "u1", role: "user", content: "samples_quoted.csv: run QC" }],
}
const UNFILED = { id: "chat-other", title: "Unfiled question", lastActivity: "2026-11-11T10:00:00.000Z", messages: [{ id: "u", role: "user", content: "hi" }] }

beforeEach(() => {
  global.fetch = vi.fn(async (url: string) => {
    const ok = (body: unknown) => ({ ok: true, status: 200, json: async () => body, text: async () => "" }) as Response
    // The server has not listed the new chat yet (its session is still syncing).
    if (String(url).includes("/api/projects/proj-1/sessions")) return ok({ sessions: [] })
    if (String(url).startsWith("/api/projects")) return ok({ projects: [{ id: "proj-1", name: "audit5", status: "active" }] })
    return ok({ projects: [], total: 0 })
  }) as unknown as typeof fetch
})

describe("a chat started in a project is listed under it immediately", () => {
  it("under the project, not under Other chats, before the server lists it", async () => {
    render(<AppSidebar chatSessions={[QC_CHAT, UNFILED] as any} />)
    await waitFor(() => expect(screen.getByTestId("button-project-chat-chat-qc")).toBeInTheDocument())
    expect(screen.queryByTestId("button-chat-chat-qc")).toBeNull()
    expect(screen.getByTestId("button-chat-chat-other")).toBeInTheDocument()
  })

  it("projectChatRows: local chats of the project first, server rows after, no duplicates; empty / hidden chats left out", () => {
    const rows = projectChatRows("proj-1", [{ session_id: "chat-qc", title: "server title" }, { session_id: "old", title: "Old" }],
      [QC_CHAT, { id: "empty", projectId: "proj-1", title: "New Chat", messages: [] }, { ...UNFILED, projectId: "proj-2" }], new Set(["old"]))
    expect(rows).toEqual([{ session_id: "chat-qc", title: "server title" }])
  })
})
