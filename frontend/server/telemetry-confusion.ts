export interface ConfusionTriageRow {
  rootRunId: string;
  latestSignalAt: string;
  totalSignals: number;
  signalsByType: Record<string, number>;
  runIds: string[];
  sessionIds: string[];
  latestSeverity?: string;
}

export interface ParsedConfusionEvent {
  timestamp: Date;
  signal: string;
  severity?: string;
  runId?: string;
  rootRunId?: string;
  sessionId?: string;
}

export function parseTelemetryPayload(raw: string | null): Record<string, unknown> | null {
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object") return null;
    return parsed as Record<string, unknown>;
  } catch {
    return null;
  }
}

export function toNonEmptyString(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

export function aggregateConfusionEvents(events: ParsedConfusionEvent[], limit: number): ConfusionTriageRow[] {
  const grouped = new Map<
    string,
    {
      latestSignalAt: Date;
      totalSignals: number;
      signalsByType: Record<string, number>;
      runIds: Set<string>;
      sessionIds: Set<string>;
      latestSeverity?: string;
    }
  >();

  for (const event of events) {
    const key = event.rootRunId || event.runId || "unknown_run";
    const current = grouped.get(key) || {
      latestSignalAt: event.timestamp,
      totalSignals: 0,
      signalsByType: {},
      runIds: new Set<string>(),
      sessionIds: new Set<string>(),
      latestSeverity: event.severity,
    };
    current.totalSignals += 1;
    current.signalsByType[event.signal] = (current.signalsByType[event.signal] ?? 0) + 1;
    if (event.runId) current.runIds.add(event.runId);
    if (event.sessionId) current.sessionIds.add(event.sessionId);
    if (event.timestamp > current.latestSignalAt) {
      current.latestSignalAt = event.timestamp;
      current.latestSeverity = event.severity;
    }
    grouped.set(key, current);
  }

  return Array.from(grouped.entries())
    .map(([rootRunId, value]) => ({
      rootRunId,
      latestSignalAt: value.latestSignalAt.toISOString(),
      totalSignals: value.totalSignals,
      signalsByType: value.signalsByType,
      runIds: Array.from(value.runIds),
      sessionIds: Array.from(value.sessionIds),
      latestSeverity: value.latestSeverity,
    }))
    .sort((a, b) => {
      if (b.totalSignals !== a.totalSignals) {
        return b.totalSignals - a.totalSignals;
      }
      return new Date(b.latestSignalAt).getTime() - new Date(a.latestSignalAt).getTime();
    })
    .slice(0, limit);
}
