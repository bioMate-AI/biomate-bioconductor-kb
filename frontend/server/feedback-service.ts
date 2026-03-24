/**
 * UX Feedback Service
 *
 * Handles feedback ingestion and aggregate queries for UX health dashboards.
 */

import { db } from './db';
import { uxFeedback } from '../shared/schema';
import type { FeedbackPayload } from '../shared/schema';
import { eq, desc, and, gte, lte } from 'drizzle-orm';

export interface FeedbackSummaryFilters {
  from?: string; // ISO date
  to?: string; // ISO date
  feedbackType?: string;
  rating?: string;
}

export interface FeedbackSummary {
  total: number;
  byType: Record<string, number>;
  byRating: Record<string, number>;
  byReason: Record<string, number>;
  byDate: Array<{ date: string; count: number }>;
}

export interface FeedbackIssue {
  reason: string;
  count: number;
  sampleIds: string[];
  lastSeen: string;
}

export class FeedbackService {
  /**
   * Create a feedback record. Accepts anonymous (no userId) submissions.
   */
  async create(payload: FeedbackPayload, userId?: string | null): Promise<string> {
    const [row] = await db
      .insert(uxFeedback)
      .values({
        userId: userId ?? null,
        sessionId: payload.sessionId ?? null,
        feedbackType: payload.feedbackType,
        rating: payload.rating,
        reasonTags: payload.reasonTags ? JSON.stringify(payload.reasonTags) : null,
        comment: payload.comment ?? null,
        runId: payload.runId ?? null,
        workflowId: payload.workflowId ?? null,
        messageId: payload.messageId ?? null,
        executionStatus: payload.executionStatus ?? null,
        errorMessage: payload.errorMessage ?? null,
        uiRoute: payload.uiRoute ?? null,
        statusClarityScore: payload.statusClarityScore ?? null,
        outputUsefulnessScore: payload.outputUsefulnessScore ?? null,
        outputActionabilityScore: payload.outputActionabilityScore ?? null,
      })
      .returning({ id: uxFeedback.id });

    return row!.id;
  }

  /**
   * Get aggregate summary by type, reason, rating, and date.
   */
  async getSummary(filters?: FeedbackSummaryFilters): Promise<FeedbackSummary> {
    const conditions: unknown[] = [];
    if (filters?.from) {
      conditions.push(gte(uxFeedback.createdAt, new Date(filters.from)));
    }
    if (filters?.to) {
      conditions.push(lte(uxFeedback.createdAt, new Date(filters.to)));
    }
    if (filters?.feedbackType) {
      conditions.push(eq(uxFeedback.feedbackType, filters.feedbackType));
    }
    if (filters?.rating) {
      conditions.push(eq(uxFeedback.rating, filters.rating));
    }
    const whereClause = conditions.length > 0 ? and(...(conditions as Parameters<typeof and>)) : undefined;

    const rows = await db
      .select({
        feedbackType: uxFeedback.feedbackType,
        rating: uxFeedback.rating,
        reasonTags: uxFeedback.reasonTags,
        createdAt: uxFeedback.createdAt,
      })
      .from(uxFeedback)
      .where(whereClause);

    const byType: Record<string, number> = {};
    const byRating: Record<string, number> = {};
    const byReason: Record<string, number> = {};
    const byDateMap: Record<string, number> = {};

    for (const r of rows) {
      byType[r.feedbackType ?? 'unknown'] = (byType[r.feedbackType ?? 'unknown'] ?? 0) + 1;
      byRating[r.rating ?? 'unknown'] = (byRating[r.rating ?? 'unknown'] ?? 0) + 1;

      if (r.reasonTags) {
        try {
          const tags = JSON.parse(r.reasonTags) as string[];
          for (const tag of tags) {
            byReason[tag] = (byReason[tag] ?? 0) + 1;
          }
        } catch {
          // ignore malformed JSON
        }
      }

      const dateKey = r.createdAt ? new Date(r.createdAt).toISOString().slice(0, 10) : 'unknown';
      byDateMap[dateKey] = (byDateMap[dateKey] ?? 0) + 1;
    }

    const byDate = Object.entries(byDateMap)
      .map(([date, count]) => ({ date, count }))
      .sort((a, b) => a.date.localeCompare(b.date));

    return {
      total: rows.length,
      byType,
      byRating,
      byReason,
      byDate,
    };
  }

  /**
   * Get top confusion/negative feedback reasons (issues) for triage.
   */
  async getIssues(filters?: FeedbackSummaryFilters & { limit?: number }): Promise<FeedbackIssue[]> {
    const limit = filters?.limit ?? 10;
    const conditions: unknown[] = [];
    if (filters?.from) {
      conditions.push(gte(uxFeedback.createdAt, new Date(filters.from)));
    }
    if (filters?.to) {
      conditions.push(lte(uxFeedback.createdAt, new Date(filters.to)));
    }
    if (filters?.feedbackType) {
      conditions.push(eq(uxFeedback.feedbackType, filters.feedbackType));
    }
    // Focus on negative feedback for "issues"
    conditions.push(eq(uxFeedback.rating, 'negative'));
    const whereClause = and(...(conditions as Parameters<typeof and>));

    const rows = await db
      .select({
        id: uxFeedback.id,
        reasonTags: uxFeedback.reasonTags,
        createdAt: uxFeedback.createdAt,
      })
      .from(uxFeedback)
      .where(whereClause)
      .orderBy(desc(uxFeedback.createdAt));

    const reasonToData: Record<
      string,
      { count: number; sampleIds: string[]; lastSeen: string }
    > = {};

    for (const r of rows) {
      const tags = r.reasonTags ? (() => {
        try {
          return JSON.parse(r.reasonTags) as string[];
        } catch {
          return [];
        }
      })() : [];

      if (tags.length === 0) {
        const key = '_no_reason';
        if (!reasonToData[key]) {
          reasonToData[key] = { count: 0, sampleIds: [], lastSeen: '' };
        }
        reasonToData[key].count += 1;
        if (reasonToData[key].sampleIds.length < 3 && r.id) {
          reasonToData[key].sampleIds.push(r.id);
        }
        const ts = r.createdAt ? new Date(r.createdAt).toISOString() : '';
        if (ts > reasonToData[key].lastSeen) {
          reasonToData[key].lastSeen = ts;
        }
      } else {
        for (const tag of tags) {
          if (!reasonToData[tag]) {
            reasonToData[tag] = { count: 0, sampleIds: [], lastSeen: '' };
          }
          reasonToData[tag].count += 1;
          if (reasonToData[tag].sampleIds.length < 3 && r.id) {
            reasonToData[tag].sampleIds.push(r.id);
          }
          const ts = r.createdAt ? new Date(r.createdAt).toISOString() : '';
          if (ts > reasonToData[tag].lastSeen) {
            reasonToData[tag].lastSeen = ts;
          }
        }
      }
    }

    const issues: FeedbackIssue[] = Object.entries(reasonToData)
      .map(([reason, data]) => ({
        reason: reason === '_no_reason' ? '(no reason given)' : reason,
        count: data.count,
        sampleIds: data.sampleIds,
        lastSeen: data.lastSeen,
      }))
      .sort((a, b) => b.count - a.count)
      .slice(0, limit);

    return issues;
  }
}

export const feedbackService = new FeedbackService();
