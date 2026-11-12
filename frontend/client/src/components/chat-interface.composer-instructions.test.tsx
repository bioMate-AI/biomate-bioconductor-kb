const uiLocale = vi.hoisted(() => ({ language: 'en' }));
vi.mock('@/lib/i18n', async importOriginal => ({
  ...await importOriginal<typeof import('@/lib/i18n')>(),
  get locale() { return uiLocale.language; },
}));
/**
 * Behavioral regression: composer instructions must survive the real submit
 * path and be serialized into the request made by ChatInterface.  Testing
 * ChatInput's callback alone is insufficient: it would still pass if the
 * parent dropped contextOverride before calling /api/chat/stream.
 */
import React from "react"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import { fireEvent, render, screen, waitFor } from "@testing-library/react"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"

import { ChatInterface } from "./chat-interface"
import { stashWorkflowSelection } from "@/lib/workflow-selection"

const fetchMock = vi.fn()

vi.mock("./galaxy-dataset-browser", () => ({
  GalaxyDatasetBrowser: ({ onSelect }: { onSelect: (id: string, name: string) => void }) => (
    <button type="button" data-testid="select-two-project-files" onClick={() => {
      onSelect("result-a-v1", "result-A.csv")
      onSelect("result-b-v2", "result-B.csv")
    }}>
      Select project files
    </button>
  ),
}))

function wrapper() {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  })
  return ({ children }: { children: React.ReactNode }) => (
    <QueryClientProvider client={client}>{children}</QueryClientProvider>
  )
}

function jsonResponse(value: unknown) {
  return new Response(JSON.stringify(value), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  })
}

beforeEach(() => {
  uiLocale.language = 'en'
  localStorage.clear()
  // Avoid the onboarding surface covering the composer in this focused test.
  localStorage.setItem("biomate_onboarding_done", "1")
  vi.stubGlobal("fetch", fetchMock)
  fetchMock.mockImplementation((input: RequestInfo | URL) => {
    const url = String(input)
    if (url === "/api/projects") return Promise.resolve(jsonResponse({ projects: [] }))
    if (url === "/api/user/llm-api-keys") return Promise.resolve(jsonResponse({}))
    if (url === "/api/chat/stream") {
      return Promise.resolve(new Response(
        'event: final\ndata: {"message":"Done"}\n\n',
        { status: 200, headers: { "Content-Type": "text/event-stream" } },
      ))
    }
    return Promise.resolve(jsonResponse({}))
  })
  HTMLElement.prototype.scrollIntoView = vi.fn()
})

afterEach(() => {
  vi.unstubAllGlobals()
  vi.restoreAllMocks()
})

describe("ChatInterface composer instructions request contract", () => {
  it("serializes trimmed user instructions in the actual chat-stream POST body", async () => {
    render(<ChatInterface />, { wrapper: wrapper() })

    fireEvent.click(screen.getByTestId("composer-instructions-toggle"))
    fireEvent.change(screen.getByTestId("composer-instructions"), {
      target: { value: "  Use GRCh38 and FDR < 0.05.  " },
    })
    fireEvent.input(screen.getByTestId("chat-input"), {
      target: { value: "Analyze my RNA-seq dataset" },
    })
    expect(screen.getByTestId("chat-input")).toHaveValue("Analyze my RNA-seq dataset")
    expect(screen.getByTestId("chat-send-button")).not.toBeDisabled()
    fireEvent.click(screen.getByTestId("chat-send-button"))

    await waitFor(() => {
      expect(fetchMock).toHaveBeenCalledWith(
        "/api/chat/stream",
        expect.objectContaining({ method: "POST" }),
      )
    })

    const [, request] = fetchMock.mock.calls.find(([url]) => url === "/api/chat/stream")!
    const body = JSON.parse(request.body)
    expect(body).toMatchObject({
      message: "Analyze my RNA-seq dataset",
      stream: true,
      context: {
        composerInstructions: "Use GRCh38 and FDR < 0.05.",
        uiLanguage: "en",
      },
    })
    // The session is created by the same submit path; do not pin its random ID,
    // but ensure both fields retain that one real session identity.
    expect(body.context.memorySessionId).toEqual(expect.any(String))
    expect(body.context.sessionId).toBe(body.context.memorySessionId)
  })

  it("serializes exact multi-file references into the real chat-stream request", async () => {
    render(<ChatInterface />, { wrapper: wrapper() })
    fireEvent.click(screen.getByTestId("select-two-project-files"))
    fireEvent.input(screen.getByTestId("chat-input"), {
      target: { value: "Compare these two result files." },
    })
    fireEvent.click(screen.getByTestId("chat-send-button"))

    await waitFor(() => expect(fetchMock).toHaveBeenCalledWith(
      "/api/chat/stream", expect.objectContaining({ method: "POST" }),
    ))
    const [, request] = fetchMock.mock.calls.find(([url]) => url === "/api/chat/stream")!
    const body = JSON.parse(request.body)
    expect(body.context.datasetReferences).toEqual([
      { id: "result-a-v1", name: "result-A.csv" },
      { id: "result-b-v2", name: "result-B.csv" },
    ])
  })
  it("sends the Chinese UI hint without translating the user's scientific query", async () => {
    uiLocale.language = 'zh';
    render(<ChatInterface />, { wrapper: wrapper() });
    const message = 'Explain hERG for CC(=O)O in English';
    fireEvent.input(screen.getByTestId('chat-input'), { target: { value: message } });
    fireEvent.click(screen.getByTestId('chat-send-button'));
    await waitFor(() => expect(fetchMock).toHaveBeenCalledWith('/api/chat/stream', expect.objectContaining({ method: 'POST' })));
    const [, request] = fetchMock.mock.calls.find(([url]) => url === '/api/chat/stream')!;
    expect(JSON.parse(request.body)).toMatchObject({ message, context: { uiLanguage: 'zh' } });
  });

  // §7.2: a workflow picked in the Workflows library rides with the message that runs it as
  // structured context.selectedWorkflow (the server builds THAT workflow, no re-routing).
  it("sends the library-picked workflow as context.selectedWorkflow with the seeded sentence", async () => {
    sessionStorage.clear()
    stashWorkflowSelection({ name: "nf-core/rnaseq", id: 42, nextflow_path: "biomni_workflows/nfcore/rnaseq/main.nf", source: "nfcore", type: "workflow" })
    render(<ChatInterface />, { wrapper: wrapper() })
    fireEvent.input(screen.getByTestId("chat-input"), { target: { value: "Run the nf-core/rnaseq workflow." } })
    fireEvent.click(screen.getByTestId("chat-send-button"))
    await waitFor(() => expect(fetchMock).toHaveBeenCalledWith("/api/chat/stream", expect.objectContaining({ method: "POST" })))
    const [, request] = fetchMock.mock.calls.find(([url]) => url === "/api/chat/stream")!
    const body = JSON.parse(request.body)
    expect(body.message).toBe("Run the nf-core/rnaseq workflow.")
    expect(body.context.selectedWorkflow).toEqual({
      name: "nf-core/rnaseq", id: 42, nextflow_path: "biomni_workflows/nfcore/rnaseq/main.nf", source: "nfcore", type: "workflow",
    })
  })

  it("drops the parked selection when the user sends a different request instead", async () => {
    sessionStorage.clear()
    stashWorkflowSelection({ name: "nf-core/rnaseq" })
    render(<ChatInterface />, { wrapper: wrapper() })
    fireEvent.input(screen.getByTestId("chat-input"), { target: { value: "Dock these ligands against EGFR" } })
    fireEvent.click(screen.getByTestId("chat-send-button"))
    await waitFor(() => expect(fetchMock).toHaveBeenCalledWith("/api/chat/stream", expect.objectContaining({ method: "POST" })))
    const [, request] = fetchMock.mock.calls.find(([url]) => url === "/api/chat/stream")!
    expect(JSON.parse(request.body).context.selectedWorkflow).toBeUndefined()
  })

})
