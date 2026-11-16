/**
 * CodeSandboxPath — the Models panel power-user path.
 *
 * Runs Python / R / bash through the owned `POST /api/code/run` sandbox
 * (`biomate-runcode`), optionally staging project file(s) from S3. A project
 * folder expands to every input file under that prefix as input_datasets.
 * This is the second of the two Models paths (no-code UI + code). Galaxy
 * Interactive Tools never worked in BioMate, so we do not route here through
 * Jupyter.
 */
import { useCallback, useEffect, useMemo, useState } from "react"
import { useActiveProjectSafe } from "@/contexts/active-project-context"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Loader2, Play } from "lucide-react"
import { t } from "@/lib/i18n"
import {
  buildDatasetOptions, parseDatasetSelection, resolveSelectionToFileIds,
} from "./dataset-selection"

type Lang = "python" | "r" | "bash"

interface ProjectFile { id: string; name: string; s3_key: string; source?: string | null }

interface CodeRunResult {
  exit_code: number
  stdout: string
  stderr: string
  output_files?: Array<{ name: string; size?: number; preview?: string; image_data_uri?: string }>
  error?: string
}

const FIELD = "block w-full rounded border bg-background px-2 py-1.5 text-sm font-mono"

const STARTERS: Record<Lang, string> = {
  python: `# INPUT_FILES: filename → path. Write results under OUTPUT_DIR.
print("inputs:", list(INPUT_FILES))
`,
  r: `# INPUT_FILES: named list of paths. Write results under Sys.getenv("OUTPUT_DIR").
print(names(INPUT_FILES))
`,
  bash: `#!/bin/bash
echo "DATA_DIR=$DATA_DIR"
echo "OUTPUT_DIR=$OUTPUT_DIR"
ls -la "$DATA_DIR" 2>/dev/null || true
`,
}

export function CodeSandboxPath() {
  const context = useActiveProjectSafe()
  const [project, setProject] = useState(context?.activeProjectId ?? "")
  const [files, setFiles] = useState<ProjectFile[]>([])
  const [filesLoading, setFilesLoading] = useState(false)
  const [selectionValue, setSelectionValue] = useState("")
  const [language, setLanguage] = useState<Lang>("python")
  const [code, setCode] = useState(STARTERS.python)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState("")
  const [result, setResult] = useState<CodeRunResult | null>(null)

  useEffect(() => {
    if (context?.activeProjectId && !project) setProject(context.activeProjectId)
  }, [context?.activeProjectId]) // eslint-disable-line react-hooks/exhaustive-deps

  const loadFiles = useCallback(async () => {
    if (!project) { setFiles([]); return }
    setFilesLoading(true)
    try {
      const r = await fetch(`/api/projects/${encodeURIComponent(project)}/files`, { credentials: "include" })
      if (!r.ok) throw new Error(t("models.setup_files_error"))
      const body = await r.json()
      setFiles(body.files ?? [])
    } catch (cause) {
      setError((cause as Error).message)
      setFiles([])
    } finally {
      setFilesLoading(false)
    }
  }, [project])

  useEffect(() => {
    setSelectionValue("")
    setError("")
    loadFiles()
  }, [project, loadFiles])

  const selection = parseDatasetSelection(selectionValue)
  const selectedFileIds = resolveSelectionToFileIds(files, selection)
  const datasetOptions = useMemo(() => buildDatasetOptions(files), [files])

  const onLanguage = (lang: Lang) => {
    setLanguage(lang)
    setCode(STARTERS[lang])
    setResult(null)
  }

  const run = async () => {
    if (!code.trim()) return
    setBusy(true)
    setError("")
    setResult(null)
    try {
      const body: Record<string, unknown> = {
        language,
        code,
        timeout_seconds: 120,
      }
      if (project && selectedFileIds.length) {
        body.project_id = project
        body.input_datasets = selectedFileIds
      }
      const r = await fetch("/api/code/run", {
        method: "POST",
        credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      })
      const payload = await r.json().catch(() => ({}))
      if (!r.ok) throw new Error(payload.error || t("models.code_run_failed"))
      setResult(payload as CodeRunResult)
    } catch (cause) {
      setError((cause as Error).message || t("models.code_run_failed"))
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="space-y-3 rounded border p-3" data-testid="code-sandbox-path">
      <div>
        <h3 className="text-sm font-semibold">{t("models.code_heading")}</h3>
        <p className="text-fs-xs text-muted-foreground">{t("models.code_intro")}</p>
      </div>

      <div className="grid gap-2 sm:grid-cols-2">
        <label className="space-y-1 text-xs">
          <span className="text-muted-foreground">{t("models.setup_project")}</span>
          <select
            className={FIELD.replace("font-mono", "")}
            value={project}
            onChange={(e) => setProject(e.target.value)}
            data-testid="code-project"
          >
            <option value="">{t("models.setup_choose_project")}</option>
            {(context?.projects ?? []).map((p) => (
              <option key={p.id} value={p.id}>{p.name}</option>
            ))}
          </select>
        </label>
        <label className="space-y-1 text-xs">
          <span className="text-muted-foreground">{t("models.code_input_optional")}</span>
          <select
            className={FIELD.replace("font-mono", "")}
            value={selectionValue}
            onChange={(e) => setSelectionValue(e.target.value)}
            disabled={!project || filesLoading}
            data-testid="code-dataset"
          >
            <option value="">{t("models.code_no_input")}</option>
            {datasetOptions.map((o) => (
              <option key={o.value} value={o.value} data-kind={o.kind}>{o.label}</option>
            ))}
          </select>
          {selection?.kind === "folder" && selectedFileIds.length > 0 && (
            <p className="text-fs-xs text-muted-foreground" data-testid="code-folder-count">
              {t("models.setup_folder_files", { n: selectedFileIds.length })}
            </p>
          )}
        </label>
      </div>

      <div className="flex flex-wrap gap-1" data-testid="code-language">
        {(["python", "r", "bash"] as Lang[]).map((lang) => (
          <Button
            key={lang}
            type="button"
            size="sm"
            variant={language === lang ? "default" : "outline"}
            className="h-7 text-xs"
            onClick={() => onLanguage(lang)}
            data-testid={`code-lang-${lang}`}
          >
            {t(`models.code_lang_${lang}`)}
          </Button>
        ))}
      </div>

      <textarea
        className={`${FIELD} min-h-[10rem]`}
        value={code}
        onChange={(e) => setCode(e.target.value)}
        spellCheck={false}
        data-testid="code-editor"
        aria-label={t("models.code_heading")}
      />

      {error && (
        <p role="alert" className="text-xs text-destructive break-words" data-testid="code-error">
          {error}
        </p>
      )}

      <Button type="button" disabled={busy || !code.trim()} onClick={run} data-testid="code-run">
        {busy ? <Loader2 className="mr-1 h-3.5 w-3.5 animate-spin" /> : <Play className="mr-1 h-3.5 w-3.5" />}
        {busy ? t("models.code_running") : t("models.code_run")}
      </Button>

      {result && (
        <div className="space-y-2 rounded border px-2 py-1.5 text-xs" data-testid="code-result">
          <div className="flex items-center gap-2">
            <Badge
              variant="outline"
              className="text-fs-xs"
              style={{ color: result.exit_code === 0 ? "#15803d" : "#b91c1c" }}
              data-testid="code-exit"
            >
              {t("models.code_exit", { code: String(result.exit_code) })}
            </Badge>
          </div>
          {result.stdout ? (
            <pre className="max-h-48 overflow-auto whitespace-pre-wrap rounded bg-muted/40 p-2" data-testid="code-stdout">
              {result.stdout}
            </pre>
          ) : null}
          {result.stderr ? (
            <pre className="max-h-48 overflow-auto whitespace-pre-wrap rounded bg-destructive/5 p-2 text-destructive" data-testid="code-stderr">
              {result.stderr}
            </pre>
          ) : null}
          {(result.output_files ?? []).length > 0 && (
            <ul className="space-y-1" data-testid="code-outputs">
              {result.output_files!.map((f) => (
                <li key={f.name} className="font-mono">
                  {f.name}
                  {typeof f.size === "number" ? ` (${f.size} B)` : ""}
                  {f.image_data_uri ? (
                    <img src={f.image_data_uri} alt={f.name} className="mt-1 max-h-48 rounded border" />
                  ) : null}
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
    </div>
  )
}
