/**
 * Tests for ProjectDetailPage — the Members & roles panel.
 *
 * Focus: the panel renders the real member list + the current user's own role,
 * and feeds <RolesCard> a capability list derived from that real role so
 * owner-only controls are shown DISABLED (naming the role) to a viewer —
 * disabled-not-hidden, never a fabricated grant.
 *
 * The heavy tab children (file tree, workflow viewer) are mocked so the test
 * stays a focused unit around the collaboration surface.
 */
import { describe, it, expect, vi, beforeEach } from "vitest"
import { render, screen, waitFor } from "@testing-library/react"
import ProjectDetailPage, { buildRoleCapabilities } from "./project-detail"

vi.mock("@/components/project-file-tree", () => ({
  ProjectFileTree: () => <div data-testid="mock-file-tree" />,
}))
vi.mock("@/components/nextflow-workflow-viewer", () => ({
  NextflowWorkflowViewer: () => <div data-testid="mock-wf-viewer" />,
}))
vi.mock("@/lib/projects", () => ({
  projectService: { getProject: () => null },
}))

const PROJECT = {
  id: "proj-1",
  name: "Fibrosis target triage",
  description: "A project",
  status: "active",
  tags: [],
  createdAt: new Date().toISOString(),
  updatedAt: new Date().toISOString(),
}

const OWNER_MEMBER = { user_id: "u-owner", email: "owner@example.com", fullName: "Olive Owner", role: "owner" }
const EDITOR_MEMBER = { user_id: "u-editor", email: "editor@example.com", fullName: "Ed Editor", role: "editor" }
const VIEWER_MEMBER = { user_id: "u-viewer", email: "viewer@example.com", fullName: "Vic Viewer", role: "viewer" }

/** Install a fetch mock that answers the endpoints project-detail hits on load. */
function installFetch(opts: { role: "owner" | "editor" | "viewer"; members: any[] }) {
  const fetchMock = vi.fn((input: RequestInfo | URL) => {
    const url = typeof input === "string" ? input : input.toString()
    const json = (body: any) => Promise.resolve({ ok: true, status: 200, json: async () => body } as Response)
    if (url === `/api/projects/${PROJECT.id}`) {
      return json({
        project: PROJECT,
        context: {},
        isOwner: opts.role === "owner",
        role: opts.role,
        canEdit: opts.role === "owner" || opts.role === "editor",
      })
    }
    if (url === `/api/projects/${PROJECT.id}/members`) return json({ members: opts.members })
    if (url.startsWith(`/api/projects/${PROJECT.id}/sessions`)) return json({ sessions: [] })
    if (url.startsWith(`/api/workflows/runs`)) return json([])
    if (url.includes("/share-link")) return json({ token: null })
    return json({})
  })
  global.fetch = fetchMock as any
  return fetchMock
}

describe("buildRoleCapabilities", () => {
  it("grants a viewer only read/download; owner-only caps are not allowed", () => {
    const caps = buildRoleCapabilities("viewer")
    const read = caps.find((c) => c.capability === "Read & download files")!
    const manage = caps.find((c) => c.capability === "Manage members & roles")!
    expect(read.allowed).toBe(true)
    expect(manage.allowed).toBe(false)
    expect(manage.needs).toBe("Owner")
  })

  it("grants an editor run/edit but not owner-only actions", () => {
    const caps = buildRoleCapabilities("editor")
    expect(caps.find((c) => c.capability === "Run analyses & edit project content")!.allowed).toBe(true)
    expect(caps.find((c) => c.capability === "Approve external transfer / spend / publish")!.allowed).toBe(false)
  })

  it("grants an owner every capability", () => {
    expect(buildRoleCapabilities("owner").every((c) => c.allowed)).toBe(true)
  })
})

describe("ProjectDetailPage — Members & roles panel", () => {
  beforeEach(() => { vi.restoreAllMocks() })

  it("renders the member list and the current user's own role (owner)", async () => {
    installFetch({ role: "owner", members: [OWNER_MEMBER, EDITOR_MEMBER, VIEWER_MEMBER] })
    render(<ProjectDetailPage projectId={PROJECT.id} onBack={() => {}} />)

    expect(await screen.findByTestId("members-panel")).toBeInTheDocument()
    // Own role badge reflects the real server role.
    expect(screen.getByTestId("my-role-badge")).toHaveTextContent("You: owner")
    // Every member row is rendered.
    expect(screen.getByTestId("member-row-u-owner")).toHaveTextContent("Olive Owner")
    expect(screen.getByTestId("member-row-u-editor")).toHaveTextContent("Ed Editor")
    expect(screen.getByTestId("member-row-u-viewer")).toHaveTextContent("Vic Viewer")
  })

  it("for a viewer, RolesCard shows owner-only controls disabled and names the role", async () => {
    installFetch({ role: "viewer", members: [OWNER_MEMBER, VIEWER_MEMBER] })
    render(<ProjectDetailPage projectId={PROJECT.id} onBack={() => {}} />)

    await waitFor(() => expect(screen.getByTestId("my-role-badge")).toHaveTextContent("You: viewer"))
    // RolesCard is present and scoped to this project.
    expect(screen.getByTestId("roles-card")).toBeInTheDocument()
    expect(screen.getByTestId("roles-you")).toHaveTextContent("Viewer")
    // Owner-only capability shown (not hidden), disabled, naming the required role.
    const manage = screen.getByTestId("role-cap-Manage members & roles")
    expect(manage).toHaveTextContent("needs Owner")
    expect(screen.getByTestId("role-verdict-Manage members & roles")).toHaveTextContent("you cannot")
    // The viewer's own read capability shows as granted.
    expect(screen.getByTestId("role-verdict-Read & download files")).toHaveTextContent("you can")
  })
})


describe("Project instructions route", () => {
  it("presents the existing persisted instruction editor in the main pane", async () => {
    installFetch({ role: "owner", members: [OWNER_MEMBER] })
    render(<ProjectDetailPage projectId={PROJECT.id} initialTab="instructions" onBack={() => {}} />)
    expect(await screen.findByRole("heading", { name: "Instructions", exact: true })).toBeInTheDocument()
    expect(screen.getByTestId("project-instructions-panel")).not.toHaveClass("w-72")
    expect(screen.getByTestId("button-edit-instructions")).toBeInTheDocument()
  })
})
