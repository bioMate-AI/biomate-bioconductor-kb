import type { ExecutionRun } from "@shared/schema";

type RunOverviewScope = "current_chat" | "all_chats";

type RunOverviewSortField = "createdAt" | "updatedAt" | "workflowName" | "status";
type RunOverviewSortDirection = "asc" | "desc";
export type RunType = "nextflow" | "chain" | "galaxy" | "research";

interface RunOverviewStorage {
  getExecutionRuns(
    userId?: string,
    projectId?: string,
    mode?: "sandbox" | "production",
    limit?: number,
    chatSessionId?: string
  ): Promise<ExecutionRun[]>;
}

export interface RunOverviewRow {
  runId: string;
  workflowName: string;
  status: string;
  createdAt: Date;
  updatedAt: Date;
  chatSessionId?: string;
  progressPercent: number;
  runType: RunType;
  artifactReadiness?: {
    hasOutputs: boolean;
    estimatedOutputCount: number;
    meetsContract: boolean;
    source: "metrics" | "nextflow_status" | "unknown";
  };
  ids: {
    galaxyInvocationId?: string;
    nextflowRunId?: string;
  };
  lastLogLine?: string;
}

export interface RunOverviewQuery {
  userId?: string;
  scope?: string;
  chatSessionId?: string;
  status?: string;
  search?: string;
  sort?: string;
  limit?: string | number;
  offset?: string | number;
}

export interface RunOverviewResponse {
  rows: RunOverviewRow[];
  total: number;
  limit: number;
  offset: number;
}

export class RunOverviewBadRequestError extends Error {
  statusCode = 400;
}

function parseScope(raw: string | undefined): RunOverviewScope {
  if (!raw || raw === "current_chat") return "current_chat";
  if (raw === "all_chats") return "all_chats";
  throw new RunOverviewBadRequestError(
    `Invalid scope "${raw}". Expected "current_chat" or "all_chats".`
  );
}

function parseStatusFilter(raw: string | undefined): Set<string> {
  if (!raw || !raw.trim()) return new Set();
  return new Set(
    raw
      .split(",")
      .map((item) => item.trim().toLowerCase())
      .filter(Boolean)
  );
}

function parsePositiveInt(raw: string | number | undefined, fallback: number, maxValue: number): number {
  const value = Number(raw);
  if (!Number.isFinite(value)) return fallback;
  return Math.min(Math.max(Math.floor(value), 0), maxValue);
}

function parseSort(
  rawSort: string | undefined
): { field: RunOverviewSortField; direction: RunOverviewSortDirection } {
  const fallback = { field: "updatedAt" as const, direction: "desc" as const };
  if (!rawSort || !rawSort.trim()) return fallback;

  const normalized = rawSort.trim();
  let fieldRaw = normalized;
  let directionRaw = "desc";

  if (normalized.includes(":")) {
    const [left, right] = normalized.split(":");
    fieldRaw = left;
    directionRaw = right;
  } else if (normalized.endsWith("_asc")) {
    fieldRaw = normalized.slice(0, -4);
    directionRaw = "asc";
  } else if (normalized.endsWith("_desc")) {
    fieldRaw = normalized.slice(0, -5);
    directionRaw = "desc";
  }

  const field = fieldRaw as RunOverviewSortField;
  const direction = directionRaw === "asc" ? "asc" : "desc";

  if (!["createdAt", "updatedAt", "workflowName", "status"].includes(field)) {
    return fallback;
  }

  return { field, direction };
}

function collectArtifacts(value: any, sink: string[]): void {
  if (!value) return;
  if (typeof value === "string") {
    const trimmed = value.trim();
    if (trimmed) sink.push(trimmed);
    return;
  }
  if (Array.isArray(value)) {
    value.forEach((item) => collectArtifacts(item, sink));
    return;
  }
  if (typeof value === "object") {
    Object.values(value).forEach((item) => collectArtifacts(item, sink));
  }
}

function toProgressPercent(run: ExecutionRun): number {
  const nextflowStatus = run.execution?.nextflowStatus;
  const candidate =
    Number(nextflowStatus?.progressPercent) ||
    Number(nextflowStatus?.progress) ||
    Number(run.progress?.percentComplete) ||
    0;

  if (!Number.isFinite(candidate)) {
    return 0;
  }
  return Math.max(0, Math.min(100, Math.round(candidate)));
}

function toRunType(run: ExecutionRun): RunType {
  const engine = (run.execution as any)?.executionEngine as string | undefined;
  if (engine === "nextflow" || (run.execution as any)?.nextflowRunId) return "nextflow";
  if (engine === "chain") return "chain";
  if (engine === "galaxy" || (run.execution as any)?.galaxyInvocationId) return "galaxy";
  return "research";
}

function toLastLogLine(run: ExecutionRun): string | undefined {
  const logTail = run.execution?.nextflowStatus?.log_tail;
  if (Array.isArray(logTail) && logTail.length > 0) {
    const last = logTail[logTail.length - 1];
    return typeof last === "string" ? last : undefined;
  }
  if (typeof logTail === "string" && logTail.trim()) {
    return logTail;
  }
  return undefined;
}

function toArtifactReadiness(run: ExecutionRun): RunOverviewRow["artifactReadiness"] {
  const metricOutputs = Number(run.metrics?.outputs?.fileCount) || 0;
  const nextflowStatus = run.execution?.nextflowStatus;
  const inferredArtifacts: string[] = [];
  collectArtifacts(nextflowStatus?.outputs, inferredArtifacts);
  collectArtifacts(nextflowStatus?.results, inferredArtifacts);
  collectArtifacts(nextflowStatus?.output_files, inferredArtifacts);
  collectArtifacts(nextflowStatus?.outdir, inferredArtifacts);

  const estimatedOutputCount = Math.max(metricOutputs, inferredArtifacts.length);
  const hasOutputs = estimatedOutputCount > 0;
  const source: "metrics" | "nextflow_status" | "unknown" =
    metricOutputs > 0 ? "metrics" : inferredArtifacts.length > 0 ? "nextflow_status" : "unknown";

  return {
    hasOutputs,
    estimatedOutputCount,
    meetsContract: hasOutputs,
    source,
  };
}

export function buildRunOverviewRow(run: ExecutionRun): RunOverviewRow {
  return {
    runId: run.id,
    workflowName: run.workflowName,
    status: run.execution?.status || "unknown",
    createdAt: run.createdAt,
    updatedAt: run.updatedAt,
    chatSessionId: run.chatSessionId,
    progressPercent: toProgressPercent(run),
    runType: toRunType(run),
    artifactReadiness: toArtifactReadiness(run),
    ids: {
      galaxyInvocationId: run.execution?.galaxyInvocationId,
      nextflowRunId: run.execution?.nextflowRunId,
    },
    lastLogLine: toLastLogLine(run),
  };
}

function matchesSearch(row: RunOverviewRow, term: string): boolean {
  if (!term) return true;
  const normalized = term.toLowerCase();
  return (
    row.runId.toLowerCase().includes(normalized) ||
    row.workflowName.toLowerCase().includes(normalized) ||
    String(row.status).toLowerCase().includes(normalized) ||
    String(row.chatSessionId || "").toLowerCase().includes(normalized) ||
    String(row.ids.galaxyInvocationId || "").toLowerCase().includes(normalized) ||
    String(row.ids.nextflowRunId || "").toLowerCase().includes(normalized)
  );
}

function compareRows(
  left: RunOverviewRow,
  right: RunOverviewRow,
  field: RunOverviewSortField,
  direction: RunOverviewSortDirection
): number {
  let raw = 0;
  if (field === "createdAt" || field === "updatedAt") {
    raw = new Date(left[field]).getTime() - new Date(right[field]).getTime();
  } else if (field === "workflowName") {
    raw = left.workflowName.localeCompare(right.workflowName);
  } else if (field === "status") {
    raw = left.status.localeCompare(right.status);
  }

  return direction === "asc" ? raw : -raw;
}

export async function getExecutionRunsOverview(
  storage: RunOverviewStorage,
  query: RunOverviewQuery
): Promise<RunOverviewResponse> {
  const scope = parseScope(query.scope);
  const limit = parsePositiveInt(query.limit, 50, 200);
  const offset = parsePositiveInt(query.offset, 0, 20000);
  const search = (query.search || "").trim().toLowerCase();
  const sort = parseSort(query.sort);
  const statusFilter = parseStatusFilter(query.status);

  if (scope === "current_chat" && !query.chatSessionId) {
    throw new RunOverviewBadRequestError(
      "chatSessionId is required when scope=current_chat."
    );
  }

  // Reuse existing storage listing and apply overview-specific projection/filtering.
  const runs = await storage.getExecutionRuns(
    query.userId,
    undefined,
    undefined,
    5000,
    scope === "current_chat" ? query.chatSessionId : undefined
  );

  const projected = runs.map(buildRunOverviewRow);
  const filtered = projected
    .filter((row) => {
      if (statusFilter.size === 0) return true;
      return statusFilter.has(String(row.status).toLowerCase());
    })
    .filter((row) => matchesSearch(row, search));

  filtered.sort((left, right) => compareRows(left, right, sort.field, sort.direction));

  return {
    rows: filtered.slice(offset, offset + limit),
    total: filtered.length,
    limit,
    offset,
  };
}
