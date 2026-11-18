/**
 * TrainingLauncher — the panel actually RUNS training (no chat draft).
 *
 * Fetch is mocked at the network boundary (the app's unit-test convention); the
 * assertions are on the real client contract: columns come from
 * /api/perception/profile, the plan from /api/model-training/plan, and the run
 * from /api/workflows/execute.
 */
import React from "react"
import { describe, it, expect, vi, beforeEach } from "vitest"
import { render, screen, fireEvent, waitFor } from "@testing-library/react"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"

import { TrainingLauncher } from "./training-launcher"
import {
  availableModelTypes, backendModelType, defaultModelName, detectSmilesColumns, detectTextColumns,
  fileKind, metricsFor, openRunManager, suggestTaskType,
} from "./training-logic"
import { specPayload } from "./training-specs"

const PROJECT = "11111111-1111-4111-8111-111111111111"
const TABLE_FILE = { id: "22222222-2222-4222-8222-222222222222", name: "expression.jsonl", s3_key: `projects/${PROJECT}/inputs/expression.jsonl` }
const MOL_FILE = { id: "33333333-3333-4333-8333-333333333333", name: "assay.csv", s3_key: `projects/${PROJECT}/inputs/assay.csv` }
const H5AD_FILE = { id: "44444444-4444-4444-8444-444444444444", name: "pbmc.h5ad", s3_key: `projects/${PROJECT}/inputs/pbmc.h5ad` }

vi.mock("@/contexts/active-project-context", () => ({
  useActiveProjectSafe: () => ({
    activeProjectId: PROJECT,
    projects: [{ id: PROJECT, name: "Test project" }],
    setActiveProjectId: () => {},
  }),
}))

function wrapper() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return ({ children }: { children: React.ReactNode }) => (
    <QueryClientProvider client={qc}>{children}</QueryClientProvider>
  )
}

interface MockOptions {
  files?: Array<typeof TABLE_FILE>
  profile?: Record<string, unknown>
  plan?: { ok: boolean; status?: number; body: unknown }
  execute?: { ok: boolean; status?: number; body: unknown }
  status?: Record<string, unknown>
}

function mockApi(options: MockOptions = {}) {
  const calls: Array<{ url: string; body?: any }> = []
  const {
    files = [TABLE_FILE],
    profile = { columns: ["sample_id", "gene_a", "gene_b", "subtype"], sampleRows: [
      ["S1", "1.0", "4.0", "A"], ["S2", "2.0", "3.0", "B"], ["S3", "3.5", "2.0", "A"], ["S4", "4.5", "1.0", "B"],
    ] },
    plan = { ok: true, body: { workflow_ga: { name: "expression-subtype", domain: "ml_training", parameters: {} },
      nextflow_path: "ml_training/chemprop_train.nf", compute_config: { container: "img" }, projectId: PROJECT, fileId: TABLE_FILE.id } },
    execute = { ok: true, body: { runId: "run-42", status: "running" } },
    status = { runId: "run-42", status: "running" },
  } = options

  global.fetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = typeof input === "string" ? input : input.toString()
    const body = init?.body ? JSON.parse(String(init.body)) : undefined
    calls.push({ url, body })
    const reply = (ok: boolean, payload: unknown, httpStatus = ok ? 200 : 400) =>
      ({ ok, status: httpStatus, json: async () => payload, text: async () => JSON.stringify(payload) }) as Response
    if (url.includes("/files")) return reply(true, { files })
    if (url.includes("/api/perception/profile")) return reply(true, profile)
    if (url.includes("/api/model-training/plan")) return reply(plan.ok, plan.body, plan.status)
    if (url.includes("/api/workflows/execute")) return reply(execute.ok, execute.body, execute.status)
    if (url.includes("/status")) return reply(true, status)
    return reply(false, {}, 404)
  }) as unknown as typeof fetch
  return calls
}

beforeEach(() => { vi.restoreAllMocks() })

async function pickTableFile(fileId = TABLE_FILE.id) {
  await waitFor(() => expect((screen.getByTestId("launcher-dataset") as HTMLSelectElement).options.length).toBeGreaterThan(1))
  fireEvent.change(screen.getByTestId("launcher-dataset"), { target: { value: `file:${fileId}` } })
  await waitFor(() => expect((screen.getByTestId("launcher-target") as HTMLSelectElement).options.length).toBeGreaterThan(1))
}

describe("TrainingLauncher — general data", () => {
  it("populates the target column from the dataset's REAL columns", async () => {
    mockApi()
    render(<TrainingLauncher family="general" />, { wrapper: wrapper() })
    await pickTableFile()
    const target = screen.getByTestId("launcher-target") as HTMLSelectElement
    expect([...target.options].map(o => o.value).filter(Boolean)).toEqual(["sample_id", "gene_a", "gene_b", "subtype"])
  })

  it("refuses a table with too few rows before launch (real DataProfile shape: shape.rows)", async () => {
    // dev run c0d27792: a 1-row DESeq2 contrasts.csv was trained with 5-fold CV.
    const csv = { ...TABLE_FILE, name: "contrasts.csv", s3_key: `projects/${PROJECT}/inputs/contrasts.csv` }
    const calls = mockApi({ files: [csv], profile: { shape: { rows: 1, cols: 5 }, columns: ["id", "variable", "reference", "target", "blocking"],
      sampleRows: [["MG_AChR_pos_vs_HC", "condition", "HC", "MG_AChR_pos", "9"]] } })
    render(<TrainingLauncher family="general" />, { wrapper: wrapper() })
    await pickTableFile()
    expect(await screen.findByTestId("launcher-too-few-rows")).toHaveTextContent(/1/)
    expect(screen.getByTestId("launcher-submit")).toBeDisabled()
    expect(calls.some(c => c.url.includes("/api/model-training/plan"))).toBe(false)
  })

  it("auto-suggests the task type from the chosen column's values, and stays editable", async () => {
    mockApi()
    render(<TrainingLauncher family="general" />, { wrapper: wrapper() })
    await pickTableFile()
    fireEvent.change(screen.getByTestId("launcher-target"), { target: { value: "subtype" } })
    await waitFor(() => expect((screen.getByTestId("launcher-task") as HTMLSelectElement).value).toBe("classification"))
    fireEvent.change(screen.getByTestId("launcher-target"), { target: { value: "gene_a" } })
    await waitFor(() => expect((screen.getByTestId("launcher-task") as HTMLSelectElement).value).toBe("regression"))
    fireEvent.change(screen.getByTestId("launcher-task"), { target: { value: "classification" } })
    expect((screen.getByTestId("launcher-task") as HTMLSelectElement).value).toBe("classification")
  })

  it("auto-fills the model name from the file and target", async () => {
    mockApi()
    render(<TrainingLauncher family="general" />, { wrapper: wrapper() })
    await pickTableFile()
    fireEvent.change(screen.getByTestId("launcher-target"), { target: { value: "subtype" } })
    await waitFor(() => expect((screen.getByTestId("launcher-name") as HTMLInputElement).value).toBe("expression-subtype"))
  })

  it("plans then executes, and shows the created run with a Run Manager link", async () => {
    const calls = mockApi()
    render(<TrainingLauncher family="general" />, { wrapper: wrapper() })
    await pickTableFile()
    fireEvent.change(screen.getByTestId("launcher-target"), { target: { value: "subtype" } })
    await waitFor(() => expect((screen.getByTestId("launcher-metric") as HTMLSelectElement).value).toBe("accuracy"))
    fireEvent.change(screen.getByTestId("launcher-gate"), { target: { value: "0.7" } })
    fireEvent.click(screen.getByTestId("launcher-submit"))

    await waitFor(() => expect(screen.getByTestId("launcher-run")).toBeTruthy())
    const plan = calls.find(c => c.url.includes("/api/model-training/plan"))!
    expect(plan.body).toMatchObject({
      projectId: PROJECT, fileId: TABLE_FILE.id, model_type: "sklearn_tabular",
      task_type: "classification", target_col: "subtype", metric: "accuracy", gate_threshold: 0.7,
    })
    const exec = calls.find(c => c.url.includes("/api/workflows/execute"))!
    expect(exec.body.workflowDefinition.domain).toBe("ml_training")
    expect(exec.body.executionConfig).toMatchObject({ mode: "production", executionEngine: "nextflow" })
    expect(exec.body.projectId).toBe(PROJECT)
    expect(screen.getByTestId("launcher-run-link").tagName).toBe("BUTTON")
    await waitFor(() => expect(screen.getByTestId("launcher-run-status").textContent).toContain("Running"))
  })

  it("threads adapt_of and omits a user name when adapting a model (→ versions the base)", async () => {
    const calls = mockApi()
    render(<TrainingLauncher family="general" adaptOf="custom:camp1/herg" />, { wrapper: wrapper() })
    await pickTableFile()
    fireEvent.change(screen.getByTestId("launcher-target"), { target: { value: "subtype" } })
    await waitFor(() => expect((screen.getByTestId("launcher-metric") as HTMLSelectElement).value).toBe("accuracy"))
    // Adapting versions the base, so there is no "name your model" field.
    expect(screen.queryByTestId("launcher-name")).toBeNull()
    fireEvent.click(screen.getByTestId("launcher-submit"))
    await waitFor(() => expect(calls.some(c => c.url.includes("/api/model-training/plan"))).toBe(true))
    const plan = calls.find(c => c.url.includes("/api/model-training/plan"))!
    expect(plan.body.adapt_of).toBe("custom:camp1/herg")
    expect(plan.body.model_name).toBeUndefined()   // name forced from the base, not sent
  })

  it("surfaces a rejected plan without launching anything", async () => {
    const calls = mockApi({ plan: { ok: false, status: 400, body: { error: "target_col is required: choose the column to predict" } } })
    render(<TrainingLauncher family="general" />, { wrapper: wrapper() })
    await pickTableFile()
    fireEvent.change(screen.getByTestId("launcher-target"), { target: { value: "subtype" } })
    fireEvent.click(screen.getByTestId("launcher-submit"))
    await waitFor(() => expect(screen.getByTestId("launcher-error").textContent).toContain("target_col is required"))
    expect(calls.some(c => c.url.includes("/api/workflows/execute"))).toBe(false)
    expect(screen.queryByTestId("launcher-run")).toBeNull()
  })

  it("surfaces an execution failure distinctly from a planning failure", async () => {
    mockApi({ execute: { ok: false, status: 400, body: { message: "Workflow needs 1 required parameter(s)" } } })
    render(<TrainingLauncher family="general" />, { wrapper: wrapper() })
    await pickTableFile()
    fireEvent.change(screen.getByTestId("launcher-target"), { target: { value: "subtype" } })
    fireEvent.click(screen.getByTestId("launcher-submit"))
    await waitFor(() => expect(screen.getByTestId("launcher-error").textContent).toContain("could not be started"))
    expect(screen.queryByTestId("launcher-run")).toBeNull()
  })

  it("offers only the model types this dataset can train, and LLM specs when the columns fit", async () => {
    mockApi({ profile: { columns: ["prompt", "chosen", "rejected"], sampleRows: [["q", "a", "b"], ["q2", "a2", "b2"]] } })
    render(<TrainingLauncher family="general" />, { wrapper: wrapper() })
    await waitFor(() => expect((screen.getByTestId("launcher-dataset") as HTMLSelectElement).options.length).toBeGreaterThan(1))
    fireEvent.change(screen.getByTestId("launcher-dataset"), { target: { value: `file:${TABLE_FILE.id}` } })
    await waitFor(() => expect(screen.getByTestId("launcher-model-type")).toBeTruthy())
    const types = [...(screen.getByTestId("launcher-model-type") as HTMLSelectElement).options].map(o => o.value)
    expect(types).toContain("trl_dpo")
    expect(types).toContain("trl_grpo")
    fireEvent.change(screen.getByTestId("launcher-model-type"), { target: { value: "trl_dpo" } })
    await waitFor(() => expect(screen.getByTestId("launcher-spec-beta")).toBeTruthy())
    // A generative family needs no target column.
    expect(screen.queryByTestId("launcher-target")).toBeNull()
  })

  it("uploads a local dataset in-panel and selects it (no leaving the panel)", async () => {
    const UPLOADED = { id: "44444444-4444-4444-8444-444444444444", name: "fresh.csv", s3_key: `projects/${PROJECT}/inputs/fresh.csv` }
    let fileList: any[] = [TABLE_FILE]
    const fetchSpy = vi.spyOn(global, "fetch").mockImplementation(async (url: any) => {
      const u = String(url)
      const ok = (body: unknown) => ({ ok: true, status: 200, json: async () => body, text: async () => "" } as Response)
      if (u.includes("/files/upload")) { fileList = [...fileList, UPLOADED]; return ok({ ok: true }) }
      if (u.includes("/files")) return ok({ files: fileList })
      if (u.includes("/api/perception/profile")) return ok({ columns: ["a", "b"], sampleRows: [["1", "2"], ["3", "4"]] })
      return ok({})
    })
    render(<TrainingLauncher family="general" />, { wrapper: wrapper() })
    await waitFor(() => expect((screen.getByTestId("launcher-dataset") as HTMLSelectElement).options.length).toBeGreaterThan(1))
    fireEvent.change(screen.getByTestId("launcher-upload"), {
      target: { files: [new File(["x"], "fresh.csv", { type: "text/csv" })] },
    })
    // The uploaded file appears and is auto-selected.
    await waitFor(() => expect((screen.getByTestId("launcher-dataset") as HTMLSelectElement).value).toBe(`file:${UPLOADED.id}`))
    expect(fetchSpy.mock.calls.some((c) => String(c[0]).includes("/files/upload"))).toBe(true)
  })

  it("reports an unusable file instead of offering a model that cannot train it", async () => {
    mockApi({ files: [{ id: "55555555-5555-4555-8555-555555555555", name: "notes.pdf", s3_key: "k" }] })
    render(<TrainingLauncher family="general" />, { wrapper: wrapper() })
    await waitFor(() => expect((screen.getByTestId("launcher-dataset") as HTMLSelectElement).options.length).toBeGreaterThan(1))
    fireEvent.change(screen.getByTestId("launcher-dataset"), { target: { value: "file:55555555-5555-4555-8555-555555555555" } })
    await waitFor(() => expect(screen.getByTestId("launcher-no-model-types")).toBeTruthy())
    expect(screen.getByTestId("launcher-submit")).toBeDisabled()
  })

  it("routes an h5ad file to single-cell diffusion only", async () => {
    mockApi({ files: [H5AD_FILE] })
    render(<TrainingLauncher family="general" />, { wrapper: wrapper() })
    await waitFor(() => expect((screen.getByTestId("launcher-dataset") as HTMLSelectElement).options.length).toBeGreaterThan(1))
    fireEvent.change(screen.getByTestId("launcher-dataset"), { target: { value: `file:${H5AD_FILE.id}` } })
    await waitFor(() => expect(screen.getByTestId("launcher-model-type")).toBeTruthy())
    const types = [...(screen.getByTestId("launcher-model-type") as HTMLSelectElement).options].map(o => o.value)
    expect(types).toEqual(["scrna_diffusion"])
  })

  it("selecting a folder plans with folderPath and stages every file under it", async () => {
    const F1 = { id: "aaaaaaaa-0000-4000-8000-000000000001", name: "train/a.csv", s3_key: "k/a.csv" }
    const F2 = { id: "bbbbbbbb-0000-4000-8000-000000000002", name: "train/b.csv", s3_key: "k/b.csv" }
    const sampleRows = Array.from({ length: 12 }, (_, i) => [String(i), i % 2 === 0 ? "A" : "B"])
    const calls = mockApi({
      files: [F1, F2],
      profile: { columns: ["x", "y"], sampleRows, shape: { rows: 12, cols: 2 } },
    })
    render(<TrainingLauncher family="general" />, { wrapper: wrapper() })
    await waitFor(() => expect(screen.getByTestId("launcher-dataset").textContent).toContain("train/"))
    fireEvent.change(screen.getByTestId("launcher-dataset"), { target: { value: "folder:train" } })
    expect(await screen.findByTestId("launcher-folder-count")).toHaveTextContent("2")
    await waitFor(() => expect((screen.getByTestId("launcher-target") as HTMLSelectElement).options.length).toBeGreaterThan(1))
    fireEvent.change(screen.getByTestId("launcher-target"), { target: { value: "y" } })
    await waitFor(() => expect(screen.getByTestId("launcher-submit")).not.toBeDisabled())
    fireEvent.click(screen.getByTestId("launcher-submit"))
    await waitFor(() => expect(screen.getByTestId("launcher-run")).toBeTruthy())
    const plan = calls.find(c => c.url.includes("/api/model-training/plan"))!
    expect(plan.body).toMatchObject({ projectId: PROJECT, folderPath: "train", model_type: "sklearn_tabular", target_col: "y" })
    expect(plan.body.fileId).toBeUndefined()
  })
})

describe("TrainingLauncher — molecular", () => {
  it("requires a SMILES column and sends it with the molecular model type", async () => {
    const calls = mockApi({
      files: [MOL_FILE],
      profile: { columns: ["compound_id", "smiles", "pIC50"], sampleRows: [
        ["c1", "CC(=O)Oc1ccccc1C(=O)O", "7.1"], ["c2", "CN1C=NC2=C1C(=O)N(C)C(=O)N2C", "6.4"],
      ] },
    })
    render(<TrainingLauncher family="molecular" />, { wrapper: wrapper() })
    await waitFor(() => expect((screen.getByTestId("launcher-dataset") as HTMLSelectElement).options.length).toBeGreaterThan(1))
    fireEvent.change(screen.getByTestId("launcher-dataset"), { target: { value: `file:${MOL_FILE.id}` } })
    await waitFor(() => expect(screen.getByTestId("launcher-smiles")).toBeTruthy())
    expect((screen.getByTestId("launcher-smiles") as HTMLSelectElement).value).toBe("smiles")
    fireEvent.change(screen.getByTestId("launcher-target"), { target: { value: "pIC50" } })
    await waitFor(() => expect((screen.getByTestId("launcher-task") as HTMLSelectElement).value).toBe("regression"))
    fireEvent.click(screen.getByTestId("launcher-submit"))
    await waitFor(() => expect(screen.getByTestId("launcher-run")).toBeTruthy())
    const plan = calls.find(c => c.url.includes("/api/model-training/plan"))!
    expect(plan.body).toMatchObject({ model_type: "sklearn_gbr", smiles_col: "smiles", target_col: "pIC50", task_type: "regression" })
  })

  it("will not offer molecular models for a table with no SMILES column", async () => {
    mockApi()
    render(<TrainingLauncher family="molecular" />, { wrapper: wrapper() })
    await pickTableFile().catch(() => {})
    await waitFor(() => expect(screen.getByTestId("launcher-no-model-types")).toBeTruthy())
  })
})

describe("training-logic", () => {
  it("classifies file kinds", () => {
    expect(fileKind("a.JSONL")).toBe("table")
    expect(fileKind("a.tsv.gz")).toBe("table")
    expect(fileKind("a.parquet")).toBe("table")
    expect(fileKind("a.h5ad")).toBe("h5ad")
    expect(fileKind("a.pdb")).toBe("structure")
    expect(fileKind("a.bam")).toBe("other")
  })

  it("detects SMILES columns by name and by value shape", () => {
    expect(detectSmilesColumns(["SMILES", "y"], [])).toEqual(["SMILES"])
    const cols = detectSmilesColumns(["mol", "y"], [["CC(=O)Oc1ccccc1C(=O)O", "1"], ["CN1C=NC2=C1C(=O)N(C)C(=O)N2C", "2"]])
    expect(cols).toEqual(["mol"])
    expect(detectSmilesColumns(["label", "n"], [["case", "1"], ["control", "2"]])).toEqual([])
    // Identifiers that superficially resemble ring labels are not molecules.
    expect(detectSmilesColumns(["id"], [["c1"], ["c2"], ["S1"]])).toEqual([])
    expect(detectSmilesColumns(["gene"], [["TP53"], ["EGFR"], ["BRCA1"]])).toEqual([])
    // The named column wins ordering over a value-detected one.
    expect(detectSmilesColumns(["mol", "smiles"], [["c1ccccc1", "CCO"], ["C1CCCCC1", "CCN"]])).toEqual(["smiles", "mol"])
  })

  it("suggests the task type from values", () => {
    expect(suggestTaskType(["A", "B", "A"])).toBe("classification")
    expect(suggestTaskType(["0", "1", "0", "1"])).toBe("classification")
    expect(suggestTaskType(["1.5", "2.5", "3.5", "4.5", "5.5", "6.5"])).toBe("regression")
    expect(suggestTaskType([])).toBe("classification")
    expect(suggestTaskType(["7.1", "6.4"])).toBe("regression")
  })

  it("maps panel model types onto the backend plan fields", () => {
    expect(backendModelType("ludwig_molecular")).toEqual({ model_type: "ludwig_tabular", featurizer: "rdkit_2d" })
    expect(backendModelType("ludwig_tabular")).toEqual({ model_type: "ludwig_tabular", featurizer: "none" })
    expect(backendModelType("trl_grpo")).toEqual({ model_type: "trl_grpo" })
  })

  it("offers only metrics the trainer reports (mirrors ml_training/plan.py)", () => {
    expect(metricsFor("sklearn_tabular", "classification")).toEqual(["accuracy", "macro_f1", "auc"])
    expect(metricsFor("ludwig_tabular", "regression")).toEqual(["mae"])
    expect(metricsFor("sklearn_gbr", "classification")).toEqual(["auc"])
    expect(metricsFor("trl_dpo" as any, "classification")).toEqual([])
  })

  it("filters model types by dataset shape", () => {
    expect(availableModelTypes("general", "table", ["a", "b"], [])).toContain("sklearn_tabular")
    expect(availableModelTypes("general", "table", ["a", "b"], [])).not.toContain("trl_dpo")
    expect(availableModelTypes("molecular", "table", ["smiles", "y"], ["smiles"])).toEqual(["sklearn_gbr", "ludwig_molecular", "chemprop_gnn"])
    expect(availableModelTypes("molecular", "table", ["a", "y"], [])).toEqual([])
    expect(availableModelTypes("general", "structure", [], [])).toEqual(["protein_diffusion"])
  })

  it("surfaces the full ML/DL set: tabular diffusion on any table, LLM on free-text", () => {
    // Generative tabular diffusion is offered for ANY feature matrix (no target needed).
    expect(availableModelTypes("general", "table", ["gene1", "gene2", "label"], [])).toContain("tabular_diffusion")
    // LLM SFT appears only when the table actually carries free text (content, not header names).
    const textRows = [["Summarize the result.", "The assay passed."], ["Explain the mechanism in detail here.", "It binds the pocket."]]
    expect(availableModelTypes("general", "table", ["q", "a"], [], textRows)).toContain("ludwig_llm")
    expect(availableModelTypes("general", "table", ["x", "y"], [], [["1", "2"], ["3", "4"]])).not.toContain("ludwig_llm")
    // DPO/GRPO stay honest to the backend's literal prompt/chosen/rejected columns.
    expect(availableModelTypes("general", "table", ["prompt", "chosen", "rejected"], [], textRows)).toEqual(
      expect.arrayContaining(["trl_grpo", "trl_dpo"]))
    expect(availableModelTypes("general", "table", ["q", "a"], [], textRows)).not.toContain("trl_dpo")
  })

  it("detectTextColumns flags free-text columns, not numeric or short categorical", () => {
    const rows = [["Long free-text description here", "ok", "42"], ["Another sentence with spaces", "no", "7"]]
    expect(detectTextColumns(["notes", "flag", "score"], rows)).toEqual(["notes"])
  })

  it("builds a language-neutral default model name", () => {
    expect(defaultModelName("expression.jsonl", "subtype")).toBe("expression-subtype")
    expect(defaultModelName("cells.h5ad", "")).toBe("cells")
  })
})

describe("openRunManager", () => {
  it("opens the Run Manager on the all-chats scope, then navigates to chat", () => {
    const go = vi.fn()
    openRunManager(go)
    expect(localStorage.getItem("biomate-run-manager-open")).toBe("true")
    expect(localStorage.getItem("biomate-run-manager-scope")).toBe("all_chats")
    expect(go).toHaveBeenCalledWith("/")
  })
})

describe("training-specs", () => {
  it("sends numbers as numbers under the family's spec key", () => {
    expect(specPayload("trl_dpo", { base_model: "m", adapter: "lora", max_sequence_length: "128", beta: "0.2" }))
      .toEqual({ llm: { base_model: "m", adapter: "lora", max_sequence_length: 128, beta: 0.2 } })
    expect(specPayload("scrna_diffusion", { finetune: false, base_checkpoint: "", n_cells_to_generate: "10",
      guidance_scale: "1", diffusion_steps: "100", noise_schedule: "cosine" }))
      .toEqual({ sc: { finetune: false, n_cells_to_generate: 10, guidance_scale: 1, diffusion_steps: 100, noise_schedule: "cosine" } })
    expect(specPayload("sklearn_tabular", {})).toEqual({})
    // tabular_diffusion maps under the 'tabular' plan key; a chosen column passes as a string.
    expect(specPayload("tabular_diffusion", { framework: "tabddpm", finetune: false, base_checkpoint: "",
      target_column: "subtype", n_rows_to_generate: "500", guidance_scale: "1", diffusion_steps: "100", noise_schedule: "cosine" }))
      .toEqual({ tabular: { framework: "tabddpm", finetune: false, target_column: "subtype", n_rows_to_generate: 500, guidance_scale: 1, diffusion_steps: 100, noise_schedule: "cosine" } })
  })
})
