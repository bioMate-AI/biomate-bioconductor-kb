/**
 * Telemetry Service
 *
 * Handles telemetry event ingestion and aggregate queries for dashboard use.
 */

import { db } from './db';
import { telemetryEvents } from '../shared/schema';
import { and, eq, gte, lte } from 'drizzle-orm';
import {
  aggregateConfusionEvents,
  parseTelemetryPayload,
  toNonEmptyString,
  type ConfusionTriageRow,
  type ParsedConfusionEvent,
} from './telemetry-confusion';

export interface TelemetrySummaryFilters {
  from?: string; // ISO date
  to?: string; // ISO date
}

export interface TelemetrySummary {
  total: number;
  byEventName: Record<string, number>;
  byDay: Array<{ date: string; count: number }>;
}

export interface TelemetryConfusionFilters extends TelemetrySummaryFilters {
  limit?: number;
}

export interface TelemetryCostSummary {
  eventCount: number;
  totalEstimatedCostUsd: number;
  totalInputTokensEstimated: number;
  totalOutputTokensEstimated: number;
  byModel: Record<string, { count: number; costUsd: number }>;
}

export class TelemetryService {
  /**
   * Persist a telemetry event. Fire-and-forget friendly; returns id on success.
   */
  async create(event: string, timestamp: Date, payload?: Record<string, unknown>): Promise<string> {
    const [row] = await db
      .insert(telemetryEvents)
      .values({
        event,
        timestamp,
        payload: payload ? JSON.stringify(payload) : null,
      })
      .returning({ id: telemetryEvents.id });

    return row!.id;
  }

  /**
   * Get aggregate summary: total, by event name, by day (time series).
   */
  async getSummary(filters?: TelemetrySummaryFilters): Promise<TelemetrySummary> {
    const conditions: unknown[] = [];
    if (filters?.from) {
      conditions.push(gte(telemetryEvents.timestamp, new Date(filters.from)));
    }
    if (filters?.to) {
      conditions.push(lte(telemetryEvents.timestamp, new Date(filters.to)));
    }
    const whereClause =
      conditions.length > 0 ? and(...(conditions as Parameters<typeof and>)) : undefined;

    const rows = await db
      .select({
        event: telemetryEvents.event,
        timestamp: telemetryEvents.timestamp,
      })
      .from(telemetryEvents)
      .where(whereClause);

    const byEventName: Record<string, number> = {};
    const byDayMap: Record<string, number> = {};

    for (const r of rows) {
      byEventName[r.event ?? 'unknown'] = (byEventName[r.event ?? 'unknown'] ?? 0) + 1;

      const dateKey = r.timestamp
        ? new Date(r.timestamp).toISOString().slice(0, 10)
        : 'unknown';
      byDayMap[dateKey] = (byDayMap[dateKey] ?? 0) + 1;
    }

    const byDay = Object.entries(byDayMap)
      .map(([date, count]) => ({ date, count }))
      .sort((a, b) => a.date.localeCompare(b.date));

    return {
      total: rows.length,
      byEventName,
      byDay,
    };
  }

  async getCostSummary(filters?: TelemetrySummaryFilters): Promise<TelemetryCostSummary> {
    const conditions: unknown[] = [eq(telemetryEvents.event, 'cost.chat.estimated')];
    if (filters?.from) {
      conditions.push(gte(telemetryEvents.timestamp, new Date(filters.from)));
    }
    if (filters?.to) {
      conditions.push(lte(telemetryEvents.timestamp, new Date(filters.to)));
    }
    const rows = await db
      .select({ payload: telemetryEvents.payload })
      .from(telemetryEvents)
      .where(and(...(conditions as Parameters<typeof and>)));

    let totalCost = 0;
    let totalIn = 0;
    let totalOut = 0;
    const byModel: Record<string, { count: number; costUsd: number }> = {};

    for (const r of rows) {
      const p = parseTelemetryPayload(r.payload);
      if (!p) continue;
      const cost = typeof p.estimatedCostUsd === 'number' ? p.estimatedCostUsd : 0;
      const inTok = typeof p.inputTokensEstimated === 'number' ? p.inputTokensEstimated : 0;
      const outTok = typeof p.outputTokensEstimated === 'number' ? p.outputTokensEstimated : 0;
      const model = toNonEmptyString(p.model) ?? 'unknown';

      totalCost += cost;
      totalIn += inTok;
      totalOut += outTok;
      if (!byModel[model]) byModel[model] = { count: 0, costUsd: 0 };
      byModel[model].count++;
      byModel[model].costUsd += cost;
    }

    return {
      eventCount: rows.length,
      totalEstimatedCostUsd: Number(totalCost.toFixed(6)),
      totalInputTokensEstimated: totalIn,
      totalOutputTokensEstimated: totalOut,
      byModel,
    };
  }

  async getConfusionTriage(filters?: TelemetryConfusionFilters): Promise<ConfusionTriageRow[]> {
    const conditions: unknown[] = [eq(telemetryEvents.event, 'workflow.confusion_signal')];
    if (filters?.from) {
      conditions.push(gte(telemetryEvents.timestamp, new Date(filters.from)));
    }
    if (filters?.to) {
      conditions.push(lte(telemetryEvents.timestamp, new Date(filters.to)));
    }
    const whereClause = and(...(conditions as Parameters<typeof and>));

    const rows = await db
      .select({
        timestamp: telemetryEvents.timestamp,
        payload: telemetryEvents.payload,
      })
      .from(telemetryEvents)
      .where(whereClause);

    const parsedEvents: ParsedConfusionEvent[] = [];
    for (const row of rows) {
      if (!row.timestamp) continue;
      const payload = parseTelemetryPayload(row.payload);
      const signal = toNonEmptyString(payload?.signal);
      if (!signal) continue;
      parsedEvents.push({
        timestamp: new Date(row.timestamp),
        signal,
        severity: toNonEmptyString(payload?.severity),
        runId: toNonEmptyString(payload?.runId),
        rootRunId: toNonEmptyString(payload?.rootRunId),
        sessionId: toNonEmptyString(payload?.sessionId),
      });
    }

    const limit = Math.max(1, Math.min(Number(filters?.limit) || 20, 200));
    return aggregateConfusionEvents(parsedEvents, limit);
  }
}

export const telemetryService = new TelemetryService();
