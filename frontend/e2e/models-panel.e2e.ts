/**
 * Models panel — canonical LIVE UI E2E (one login, one project, one chain).
 *
 * Exercises the panel THROUGH THE BROWSER (clicks, uploads, visible DOM), not
 * API-only probes. Against https://dev-public.biomate.ai by default.
 *
 * Flow:
 *   login → /models
 *   Train No-code: upload CSV → configure sklearn → Start → see Running card
 *   Train Code: switch path → select same CSV → Run → see stdout in panel
 *   Library: catalog honesty → open Boltz → Use in run → fold launch → Running
 *   Molecular: SMILES upload → Start → Running; DMTA empty honesty
 *
 * Run:
 *   cd frontend && BIOMATE_URL=https://dev-public.biomate.ai \
 *     E2E_FIXTURE_PASSWORD=$(cat ~/.config/biomate/e2e_fixture_password) \
 *     npx playwright test e2e/models-panel.e2e.ts --project=chromium --retries=0
 */
import { test, expect, type Page, type APIResponse } from "@playwright/test"
import * as fs from "fs"
import * as os from "os"
import * as path from "path"
import { loginAsFixture, BASE_URL, resetFixtureCache } from "./_fixture-login"

test.describe.configure({ mode: "serial", timeout: 30 * 60_000 })

const SHOT = path.resolve(process.cwd(), "e2e", "execshots", "models-panel-e2e")
fs.mkdirSync(SHOT, { recursive: true })

const TERMINAL = /completed|succeeded|failed|error|cancelled|canceled|interrupted/i
const TERMINAL_LABEL = /Completed|Failed|Cancelled|Interrupted|Unknown/

async function snap(page: Page, name: string) {
  await page.screenshot({ path: path.join(SHOT, `${name}.png`), fullPage: true })
}

/** runId from an /api/workflows/execute (or plan+execute) response, if present. */
async function runIdFrom(resp: APIResponse): Promise<string | undefined> {
  try {
    const b = await resp.json()
    return typeof b?.runId === "string" ? b.runId : undefined
  } catch { return undefined }
}

/** Poll a tracked workflow run to a terminal state. Returns {status,error}. */
async function pollWorkflowTerminal(page: Page, runId: string, budgetMs: number) {
  const deadline = Date.now() + budgetMs
  let last = "queued"
  let error: string | undefined
  while (Date.now() < deadline) {
    const r = await page.request.get(`${BASE_URL}/api/workflows/runs/${runId}/status`)
    if (r.ok()) {
      const d = await r.json()
      last = String(d.status || last)
      error = d.errorMessage || error
      if (TERMINAL.test(last)) return { status: last, error }
    }
    await page.waitForTimeout(5000)
  }
  return { status: last, error, timedOut: true as const }
}

/** The REAL output of a training run is the trainer's metric, surfaced in the
 *  Train tab's runs list (train-run-metric-*). Reload the Train tab and poll the
 *  newest run's metric badge until it shows a real number (not "Not recorded").
 *  Fresh per-suite project ⇒ the first/newest row is the run we just launched. */
async function assertRealMetricRendered(page: Page, label: string, budgetMs = 5 * 60_000) {
  let seen = ""
  const deadline = Date.now() + budgetMs
  while (Date.now() < deadline) {
    // Fresh load each pass so the train-runs query re-fetches (and the server
    // backfills metrics.json into the row). Wait for the row to actually RENDER
    // on THIS load before reading — don't re-navigate out from under it.
    await page.goto(`${BASE_URL}/models`, { waitUntil: "domcontentloaded" })
    await expect(page.getByTestId("models-panel")).toBeVisible({ timeout: 45_000 })
    await page.getByTestId("models-track-0").click()
    const metric = page.locator('[data-testid^="train-run-metric-"]').first()
    const rendered = await metric.waitFor({ state: "visible", timeout: 60_000 }).then(() => true).catch(() => false)
    if (rendered) {
      seen = (await metric.textContent())?.trim() || ""
      // metricLabel renders value.toFixed(3) ⇒ a real metric always has N.NNN.
      if (/\d\.\d{3}/.test(seen)) {
        console.log(`${label}_METRIC rendered="${seen}"`)
        await snap(page, `metric-${label}`)
        return seen
      }
    }
    await page.waitForTimeout(5000)
  }
  throw new Error(`${label}: no real metric rendered in train-runs within ${budgetMs}ms (last="${seen}")`)
}

function trainCsv(): string {
  const p = path.join(os.tmpdir(), `models-e2e-train-${Date.now()}.csv`)
  const lines = ["gene_a,gene_b,subtype"]
  for (let i = 0; i < 12; i++) lines.push(`${(i % 5) + 1},${(i % 3) + 2},${i % 2 ? "B" : "A"}`)
  fs.writeFileSync(p, lines.join("\n") + "\n")
  return p
}

function smilesCsv(): string {
  const p = path.join(os.tmpdir(), `models-e2e-mol-${Date.now()}.csv`)
  const smiles = ["CCO", "CCN", "c1ccccc1", "CC(=O)O", "CCN(CC)CC", "CCOC", "CCC", "c1ccncc1", "CC(C)O", "C1CCCCC1", "CCBr", "CCI"]
  fs.writeFileSync(p, ["smiles,pIC50", ...smiles.map((s, i) => `${s},${(5 + i * 0.2).toFixed(2)}`)].join("\n") + "\n")
  return p
}

let page: Page
let projectId: string
let uploadedFileId: string

test.beforeAll(async ({ browser }) => {
  resetFixtureCache()
  page = await browser.newPage()
  await loginAsFixture(page)

  const created = await page.request.post(`${BASE_URL}/api/projects`, {
    data: { name: `models-panel-e2e ${Date.now()}`, description: "canonical Models UI e2e" },
  })
  expect(created.ok(), `create project ${created.status()}`).toBeTruthy()
  const body = await created.json()
  projectId = body.id || body.project?.id
  expect(projectId).toBeTruthy()

  await page.addInitScript((id) => {
    try { localStorage.setItem("biomate-active-project-id", id) } catch { /* ignore */ }
  }, projectId)
})

test.afterAll(async () => {
  // Best-effort cleanup of the disposable project.
  if (page && projectId) {
    await page.request.delete(`${BASE_URL}/api/projects/${projectId}`).catch(() => {})
  }
  await page?.close()
})

async function gotoModels(tab: 0 | 1 | 2) {
  await page.goto(`${BASE_URL}/models`, { waitUntil: "domcontentloaded" })
  await expect(page.getByTestId("models-panel")).toBeVisible({ timeout: 45_000 })
  await page.getByTestId(`models-track-${tab}`).click()
}

async function pickProjectInLauncher() {
  const sel = page.getByTestId("launcher-project")
  await expect(sel).toBeVisible({ timeout: 30_000 })
  await expect.poll(async () => {
    const n = await sel.locator("option").count()
    for (let i = 0; i < n; i++) {
      if ((await sel.locator("option").nth(i).getAttribute("value")) === projectId) return true
    }
    // Sidebar hydrate fallback
    if (n <= 1) {
      const side = page.locator("aside button").filter({ hasText: /models-panel-e2e/ }).first()
      if (await side.isVisible().catch(() => false)) await side.click()
    }
    return false
  }, { timeout: 90_000 }).toBeTruthy()
  await sel.selectOption(projectId)
}

test("1. Train No-code UI: upload → configure → Start → run to terminal", async () => {
  test.setTimeout(20 * 60_000)
  await gotoModels(0)
  await snap(page, "01-train-shell")

  await expect(page.getByTestId("train-path-toggle")).toBeVisible()
  await expect(page.getByTestId("train-path-ui")).toBeVisible()
  await page.getByTestId("train-path-ui").click()
  await expect(page.getByTestId("training-launcher-general")).toBeVisible()
  await expect(page.getByTestId("code-sandbox-path")).toHaveCount(0)

  await pickProjectInLauncher()
  await page.getByTestId("launcher-upload").setInputFiles(trainCsv())
  await expect(page.getByTestId("launcher-dataset")).not.toHaveValue("", { timeout: 60_000 })
  uploadedFileId = await page.getByTestId("launcher-dataset").inputValue()
  await snap(page, "02-train-uploaded")

  await expect(page.getByTestId("launcher-model-type")).toBeVisible({ timeout: 60_000 })
  await page.getByTestId("launcher-model-type").selectOption("sklearn_tabular")
  await expect(page.getByTestId("launcher-target")).toBeVisible({ timeout: 30_000 })
  await page.getByTestId("launcher-target").selectOption("subtype")
  await page.getByTestId("launcher-gate").fill("0.5")
  await snap(page, "03-train-configured")

  const waitExec = page.waitForResponse(
    (r) => r.request().method() === "POST" && r.url().includes("/api/workflows/execute"),
    { timeout: 120_000 },
  )
  await page.getByTestId("launcher-submit").click()
  const exec = await waitExec
  expect(exec.ok(), `train execute HTTP ${exec.status()}`).toBeTruthy()
  const runId = await runIdFrom(exec)
  expect(runId, "train run id").toBeTruthy()

  await expect(page.getByTestId("launcher-run")).toBeVisible({ timeout: 60_000 })
  await expect(page.getByTestId("launcher-run-status")).toBeVisible()
  await snap(page, "04-train-running")

  // END-TO-END: poll the real run to a terminal state (sklearn is quick; budget 15m).
  const term = await pollWorkflowTerminal(page, runId!, 15 * 60_000)
  expect(term.timedOut, `train still ${term.status} after 15m`).toBeFalsy()

  // UI badge must converge to the SAME terminal verdict (page keeps polling at 5s).
  await expect(page.getByTestId("launcher-run-status")).toHaveText(TERMINAL_LABEL, { timeout: 60_000 })
  const badge = await page.getByTestId("launcher-run-status").textContent()
  await snap(page, "04b-train-terminal")

  if (/completed|succeeded/i.test(term.status)) {
    // END OUTPUT: the trained model's real metric must RENDER in the Train runs
    // list — a "Completed" badge alone is not the end.
    expect(/Completed/.test(badge || ""), `badge=${badge}`).toBeTruthy()
    await assertRealMetricRendered(page, "train")
  } else {
    // Failed is a REAL backend verdict — assert the UI shows it honestly, not a spinner.
    await expect(page.getByTestId("launcher-run-status")).toHaveText(/Failed|Interrupted|Cancelled/)
    const errVisible = await page.getByTestId("launcher-run-error").isVisible().catch(() => false)
    console.log(`TRAIN_TERMINAL status=${term.status} badge=${badge} error=${term.error || "(none)"} errVisible=${errVisible}`)
    await snap(page, "04c-train-failed")
  }
})

test("2. Train Code UI: switch path → run pandas on uploaded file → stdout in panel", async () => {
  await page.getByTestId("train-path-code").click()
  await expect(page.getByTestId("code-sandbox-path")).toBeVisible()
  await expect(page.getByTestId("training-launcher-general")).toHaveCount(0)
  await snap(page, "05-code-path")

  const project = page.getByTestId("code-project")
  await expect.poll(async () => {
    const n = await project.locator("option").count()
    for (let i = 0; i < n; i++) {
      if ((await project.locator("option").nth(i).getAttribute("value")) === projectId) return true
    }
    return false
  }, { timeout: 60_000 }).toBeTruthy()
  await project.selectOption(projectId)

  const ds = page.getByTestId("code-dataset")
  await expect.poll(async () => {
    const n = await ds.locator("option").count()
    for (let i = 0; i < n; i++) {
      if ((await ds.locator("option").nth(i).getAttribute("value")) === uploadedFileId) return true
    }
    return false
  }, { timeout: 60_000 }).toBeTruthy()
  await ds.selectOption(uploadedFileId)

  await page.getByTestId("code-lang-python").click()
  await page.getByTestId("code-editor").fill(`import pandas as pd
path = next(iter(INPUT_FILES.values()))
df = pd.read_csv(path)
print("rows", len(df))
print("biomate-ui-e2e-ok", float(df.select_dtypes("number").mean().mean()))
`)
  await snap(page, "06-code-filled")

  const waitRun = page.waitForResponse(
    (r) => r.url().includes("/api/code/run") && r.request().method() === "POST",
    { timeout: 90_000 },
  )
  await page.getByTestId("code-run").click()
  const run = await waitRun
  expect(run.ok()).toBeTruthy()
  const body = await run.json()
  expect(body.exit_code, JSON.stringify(body).slice(0, 400)).toBe(0)

  // Assert ON-SCREEN output, not only response body.
  await expect(page.getByTestId("code-result")).toBeVisible()
  await expect(page.getByTestId("code-stdout")).toContainText("biomate-ui-e2e-ok")
  await expect(page.getByTestId("code-stdout")).toContainText("rows")
  await expect(page.getByTestId("code-exit")).toContainText("0")
  await snap(page, "07-code-stdout")
})

test("3. Library UI: catalog → model object → Use in run → Boltz fold Running", async () => {
  await gotoModels(1)
  await expect(page.getByTestId("track-library")).toBeVisible({ timeout: 45_000 })
  await expect(page.getByTestId("registry-table")).toBeVisible({ timeout: 45_000 })
  await expect(page.getByTestId("registry-row-bionemo:boltz2")).toBeVisible()
  await expect(page.getByTestId("registry-row-bionemo:evo2_7b")).toHaveCount(0)
  await expect(page.getByTestId("run-pretrained-origin")).toContainText(/BioMate|自有/)
  await snap(page, "08-library-catalog")

  await page.getByTestId("registry-row-bionemo:boltz2").click()
  await expect(page.getByTestId("model-object")).toBeVisible({ timeout: 45_000 })
  await expect(page.getByTestId("model-object-name")).toContainText(/Boltz/i)
  for (const t of ["evidence", "lineage", "used", "iface", "versions"] as const) {
    await page.getByTestId(`model-tab-${t}`).click()
  }
  await snap(page, "09-model-object")

  await page.getByTestId("model-object-use-in-run").click()
  await expect(page.getByTestId("run-pretrained")).toBeVisible({ timeout: 30_000 })

  await page.getByTestId("domain-genomic").click()
  await expect(page.getByTestId("run-pretrained-no-model")).toBeVisible()
  await snap(page, "10-genomic-empty")

  await page.getByTestId("domain-structure").click()
  await page.getByTestId("run-pretrained-example").click()
  await expect(page.getByTestId("run-pretrained-input")).not.toHaveValue("")
  await snap(page, "11-fold-ready")

  const waitFold = page.waitForResponse(
    (r) => r.request().method() === "POST" && r.url().includes("/api/workflows/execute"),
    { timeout: 120_000 },
  )
  await page.getByTestId("run-pretrained-submit").click()
  const foldExec = await waitFold
  expect(foldExec.ok(), `fold execute HTTP ${foldExec.status()}`).toBeTruthy()
  const foldRunId = await runIdFrom(foldExec)
  expect(foldRunId, "fold run id").toBeTruthy()
  await expect(page.getByTestId("fold-run-card")).toBeVisible({ timeout: 60_000 })
  await expect(page.getByTestId("fold-run-status")).toBeVisible()
  await snap(page, "12-fold-running")

  // END-TO-END: Boltz-2 fold on GPU Batch — poll to terminal (budget 20m).
  const term = await pollWorkflowTerminal(page, foldRunId!, 20 * 60_000)
  expect(term.timedOut, `fold still ${term.status} after 20m`).toBeFalsy()
  await expect(page.getByTestId("fold-run-status")).toHaveText(TERMINAL_LABEL, { timeout: 60_000 })
  const foldBadge = await page.getByTestId("fold-run-status").textContent()
  await expect(page.getByTestId("fold-run-note")).toBeVisible()
  const note = await page.getByTestId("fold-run-note").textContent()
  console.log(`FOLD_TERMINAL status=${term.status} badge=${foldBadge} error=${term.error || "(none)"}`)
  await snap(page, "12b-fold-terminal")
  if (/completed|succeeded/i.test(term.status)) {
    expect(/Completed/.test(foldBadge || "")).toBeTruthy()
    expect(note || "").toMatch(/open the run|structure|置信度|pLDDT/i)

    // END OUTPUT (ground truth): the fold must have produced real structure files.
    const of = await page.request.get(`${BASE_URL}/api/workflows/runs/${foldRunId}/output_files`)
    expect(of.ok(), `output_files HTTP ${of.status()}`).toBeTruthy()
    const ofb = await of.json()
    const files: any[] = ofb.output_files || ofb.outputs || []
    const names = files.map((f) => String(f.filename || f.name || f.path || "")).filter(Boolean)
    console.log(`FOLD_OUTPUTS n=${names.length} ${names.slice(0, 12).join(", ")}`)
    expect(files.length, "fold produced no output files").toBeGreaterThan(0)
    expect(names.join(" ")).toMatch(/\.(cif|mmcif|pdb)\b|confidence|plddt|affinity|\.json/i)

    // END OUTPUT (rendered INLINE): the fold card itself must show the result —
    // the predicted structure download + the output list — with no Run Manager
    // detour. This is the panel-native result surface.
    await expect(page.getByTestId("fold-outputs")).toBeVisible({ timeout: 60_000 })
    await expect(page.getByTestId("fold-structure-download")).toBeVisible({ timeout: 30_000 })
    await expect(page.getByTestId("fold-output-file").first()).toBeVisible({ timeout: 30_000 })
    // Confidence headline is best-effort (depends on the confidence JSON) — log it.
    const confVisible = await page.getByTestId("fold-confidence").isVisible().catch(() => false)
    const confText = confVisible ? await page.getByTestId("fold-confidence").textContent() : "(none)"
    console.log(`FOLD_INLINE structure+files rendered; confidence=${confText}`)
    await snap(page, "12c-fold-outputs-inline")
  } else {
    // Real backend failure (e.g. Boltz CUDA 422) must render honestly, not spin.
    expect(/Failed|Interrupted|Cancelled/.test(foldBadge || "")).toBeTruthy()
  }
})

test("4. Molecular UI: SMILES upload → Start → run to terminal; DMTA empty", async () => {
  test.setTimeout(20 * 60_000)
  // Test 3 may have left us in the Run Manager (/) — re-enter the Models panel.
  await gotoModels(2)
  await expect(page.getByTestId("training-launcher-molecular")).toBeVisible({ timeout: 45_000 })
  await expect(page.getByTestId("track-optimise")).toBeVisible()
  await expect(page.getByTestId("optimise-empty")).toBeVisible()
  await snap(page, "13-molecular-shell")

  await pickProjectInLauncher()
  await page.getByTestId("launcher-upload").setInputFiles(smilesCsv())
  await expect(page.getByTestId("launcher-dataset")).not.toHaveValue("", { timeout: 60_000 })
  await expect(page.getByTestId("launcher-model-type")).toBeVisible({ timeout: 60_000 })
  await page.getByTestId("launcher-model-type").selectOption("sklearn_gbr")
  await expect(page.getByTestId("launcher-smiles")).toHaveValue(/smiles/i)
  await page.getByTestId("launcher-target").selectOption("pIC50")
  await snap(page, "14-molecular-configured")

  const waitMol = page.waitForResponse(
    (r) => r.request().method() === "POST" && r.url().includes("/api/workflows/execute"),
    { timeout: 120_000 },
  )
  await page.getByTestId("launcher-submit").click()
  const molExec = await waitMol
  expect(molExec.ok(), `molecular execute HTTP ${molExec.status()}`).toBeTruthy()
  const molRunId = await runIdFrom(molExec)
  expect(molRunId, "molecular run id").toBeTruthy()
  await expect(page.getByTestId("launcher-run")).toBeVisible({ timeout: 60_000 })
  await snap(page, "15-molecular-running")

  // END-TO-END: scaffold-split GBR over RDKit descriptors — poll to terminal (15m).
  const term = await pollWorkflowTerminal(page, molRunId!, 15 * 60_000)
  expect(term.timedOut, `molecular still ${term.status} after 15m`).toBeFalsy()
  await expect(page.getByTestId("launcher-run-status")).toHaveText(TERMINAL_LABEL, { timeout: 60_000 })
  const molBadge = await page.getByTestId("launcher-run-status").textContent()
  console.log(`MOLECULAR_TERMINAL status=${term.status} badge=${molBadge} error=${term.error || "(none)"}`)
  await snap(page, "15b-molecular-terminal")
  if (/completed|succeeded/i.test(term.status)) {
    expect(/Completed/.test(molBadge || "")).toBeTruthy()
    // END OUTPUT: the molecular model is an ml_training run — its real metric
    // (e.g. mae over a scaffold split) renders in the shared Train runs list.
    await assertRealMetricRendered(page, "molecular")
  } else {
    expect(/Failed|Interrupted|Cancelled/.test(molBadge || "")).toBeTruthy()
  }
})
