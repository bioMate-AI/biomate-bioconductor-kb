/**
 * N7 (round 4): the project Files tab footer and its "Analyze with BioMate" button were hard-coded
 * English, so a Chinese UI showed them in English. They go through t() — zh shows zh.
 */
import { describe, it, expect, vi, afterEach } from "vitest"

vi.mock("@/components/project-file-tree", () => ({ ProjectFileTree: () => null }))
vi.mock("@/components/nextflow-workflow-viewer", () => ({ NextflowWorkflowViewer: () => null }))
vi.mock("@/lib/projects", () => ({ projectService: { getProject: () => null } }))

const PROJECT = { id: "proj-1", name: "Pilot", description: "", status: "active", tags: [], createdAt: "2026-11-01T00:00:00Z", updatedAt: "2026-11-01T00:00:00Z" }

afterEach(() => { localStorage.clear(); vi.restoreAllMocks() })

describe("project Files tab footer", () => {
  for (const [language, footer, button] of [
    ["chinese", "上传数据文件，BioMate 会为您选择并运行合适的工作流。", "用 BioMate 分析"],
    ["english", "Upload data files, then let BioMate select and run the right workflow for you.", "Analyze with BioMate"],
  ] as const) {
    it(`${language}: footer and button in the UI language`, async () => {
      vi.resetModules()
      localStorage.setItem("biomate-user-settings", JSON.stringify({ language }))
      global.fetch = vi.fn(async (input: RequestInfo | URL) => {
        const url = String(input)
        const body = url === `/api/projects/${PROJECT.id}`
          ? { project: PROJECT, context: {}, isOwner: true, role: "owner", canEdit: true }
          : url.endsWith("/members") ? { members: [] } : url.includes("/sessions") ? { sessions: [] } : {}
        return { ok: true, status: 200, json: async () => body } as unknown as Response
      }) as unknown as typeof fetch
      const React = await import("react")
      const { render, screen } = await import("@testing-library/react")
      const { default: ProjectDetailPage } = await import("./project-detail")
      render(React.createElement(ProjectDetailPage, { projectId: PROJECT.id, initialTab: "files", onBack: () => {} }))
      expect(await screen.findByTestId("project-files-footer")).toHaveTextContent(footer)
      expect(screen.getByTestId("button-analyze-files")).toHaveTextContent(button)
    }, 30_000)
  }
})
